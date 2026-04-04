#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.DeviceManagement

<#
.SYNOPSIS
    Bulk reinstall an Android app on Intune-managed devices by triggering the
    changeAssignments remote action (equivalent to "Remove apps and configuration" in the portal).

.DESCRIPTION
    Reads a list of device serial numbers from a text file, resolves each to an
    Intune managed device ID, fetches all Android apps from the tenant, prompts
    the admin to pick one, and fires the changeAssignments Graph API call for
    every resolved device.

    Intune automatically reapplies the app assignment within 8-24 hours after
    removal, effectively reinstalling the app fresh.

.NOTES
    Required Graph permission: DeviceManagementManagedDevices.PrivilegedOperations.All
    Author : Paris Petsanas / systunation.com
#>

# ----------------------------------------------------------------
# SETTINGS - adjust before running
# ----------------------------------------------------------------
$SerialNumberFilePath = "C:\Temp\serials.txt"   # One serial number per line
$LogPath              = "C:\Temp\AndroidAppReinstall_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
# ----------------------------------------------------------------

#region Helpers

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'u')] [$Level] $Message"
    Write-Host $entry -ForegroundColor $(switch ($Level) {
        "INFO"    { "Cyan"   }
        "SUCCESS" { "Green"  }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red"    }
        default   { "White"  }
    })
    Add-Content -Path $LogPath -Value $entry -Encoding UTF8
}

function ConvertTo-SafeFilterString {
    param([string]$InputString)
    # Strip single quotes to prevent OData filter injection
    return $InputString -replace "'", ""
}

#endregion

#region Graph Connection

Write-Log "Checking Microsoft Graph connection..."
try {
    $ctx = Get-MgContext
    if ($null -eq $ctx) {
        Write-Log "No active session found - connecting..."
        Connect-MgGraph -Scopes @(
            "DeviceManagementManagedDevices.ReadWrite.All",
            "DeviceManagementManagedDevices.PrivilegedOperations.All"
        ) | Out-Null
        Write-Log "Connected to Microsoft Graph." "SUCCESS"
    } else {
        Write-Log "Already connected as: $($ctx.Account)" "SUCCESS"
    }
} catch {
    Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" "ERROR"
    exit 1
}

#endregion

#region Validate serial file

if (-not (Test-Path -Path $SerialNumberFilePath)) {
    Write-Log "Serial number file not found: $SerialNumberFilePath" "ERROR"
    exit 1
}

$serials = Get-Content -Path $SerialNumberFilePath -Encoding UTF8 |
           Where-Object { $_ -match '\S' } |
           ForEach-Object { $_.Trim() }

if ($serials.Count -eq 0) {
    Write-Log "Serial number file is empty." "ERROR"
    exit 1
}

Write-Log "Loaded $($serials.Count) serial number(s) from file."

#endregion

#region Fetch Android apps

Write-Log "Fetching Android apps from Intune..."
try {
    $appsResponse = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
        -ErrorAction Stop

    $androidApps = $appsResponse.value | Where-Object {
        $_.'@odata.type' -match 'android'
    } | Select-Object displayName, id | Sort-Object displayName

    if ($androidApps.Count -eq 0) {
        Write-Log "No Android apps found in this tenant." "WARN"
        exit 1
    }

    Write-Log "Found $($androidApps.Count) Android app(s)." "SUCCESS"
} catch {
    Write-Log "Failed to fetch Android apps: $($_.Exception.Message)" "ERROR"
    exit 1
}

#endregion

#region App selection menu

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Available Android Apps" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

for ($i = 0; $i -lt $androidApps.Count; $i++) {
    Write-Host "  [$($i + 1)] $($androidApps[$i].displayName)"
}

Write-Host ""
$selection = Read-Host "Enter the number of the app to reinstall"

if (-not ($selection -match '^\d+$') -or
    [int]$selection -lt 1 -or
    [int]$selection -gt $androidApps.Count) {
    Write-Log "Invalid selection: '$selection'" "ERROR"
    exit 1
}

$selectedApp = $androidApps[[int]$selection - 1]
Write-Log "Selected app: '$($selectedApp.displayName)' | ID: $($selectedApp.id)"

#endregion

#region Resolve serials to Intune device IDs

Write-Log "Resolving serial numbers to Intune managed device IDs..."

$deviceIds = [System.Collections.Generic.List[string]]::new()

foreach ($serial in $serials) {
    $safeSerial = ConvertTo-SafeFilterString -InputString $serial
    try {
        $dev = Invoke-MgGraphRequest -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$safeSerial'" `
            -ErrorAction Stop

        if ($dev.value -and $dev.value.Count -gt 0) {
            $deviceIds.Add($dev.value[0].id)
            Write-Log "Resolved: $safeSerial -> $($dev.value[0].id)"
        } else {
            Write-Log "Device not found for serial: $safeSerial" "WARN"
        }
    } catch {
        Write-Log "Error resolving serial '$safeSerial': $($_.Exception.Message)" "ERROR"
    }
}

if ($deviceIds.Count -eq 0) {
    Write-Log "No devices resolved. Nothing to do." "WARN"
    exit 1
}

Write-Log "Resolved $($deviceIds.Count) of $($serials.Count) device(s)."

#endregion

#region Confirmation

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host "  Summary" -ForegroundColor Yellow
Write-Host "=====================================================" -ForegroundColor Yellow
Write-Host "  App    : $($selectedApp.displayName)"
Write-Host "  Devices: $($deviceIds.Count) resolved"
Write-Host ""
$confirm = Read-Host "Proceed with changeAssignments for all $($deviceIds.Count) device(s)? (Y/N)"

if ($confirm -notmatch '^[Yy]$') {
    Write-Log "Action cancelled by user." "WARN"
    exit 0
}

#endregion

#region Send changeAssignments

Write-Log "Sending changeAssignments remote action..."

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$counter = 0

foreach ($deviceId in $deviceIds) {
    $counter++
    Write-Log "#$counter/$($deviceIds.Count) - Processing device: $deviceId"

    try {
        $uri  = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$deviceId')/changeAssignments"
        $body = @{
            deviceAssignmentItems = @(
                @{
                    itemId   = $selectedApp.id
                    itemType = "application"
                }
            )
        } | ConvertTo-Json -Depth 4

        $null = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body `
            -ContentType "application/json" -ErrorAction Stop

        Write-Log "Device $deviceId - action sent successfully." "SUCCESS"
        $results.Add([PSCustomObject]@{
            DeviceId = $deviceId
            Status   = "Requested"
            Message  = "OK"
        })
    } catch {
        Write-Log "Device $deviceId - failed: $($_.Exception.Message)" "ERROR"
        $results.Add([PSCustomObject]@{
            DeviceId = $deviceId
            Status   = "Error"
            Message  = $_.Exception.Message
        })
    }
}

#endregion

#region Results summary

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Results" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

$results | Format-Table -AutoSize

$succeeded = ($results | Where-Object { $_.Status -eq "Requested" }).Count
$failed    = ($results | Where-Object { $_.Status -eq "Error" }).Count

Write-Log "Completed. Succeeded: $succeeded | Failed: $failed"
Write-Log "Log saved to: $LogPath"