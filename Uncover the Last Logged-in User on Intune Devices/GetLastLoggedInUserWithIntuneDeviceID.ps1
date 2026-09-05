<#
.SYNOPSIS
    Exports device + last-logged-on-user information from Intune for a list of serial numbers.

.DESCRIPTION
    Reads serial numbers from a file (one per line, or a CSV with a SerialNumber column),
    looks up each managed device in Intune, resolves the most recent interactive user from
    the beta 'usersLoggedOn' property, and falls back to the device compliance report when
    'usersLoggedOn' is empty. Results are exported to CSV.

.PARAMETER CsvPath
    Path to the file containing serial numbers. Prompted for if not supplied.

.PARAMETER OutputPath
    Destination CSV. Defaults to $env:PUBLIC\LastLoggedOnUser.csv (Windows) or the current
    directory on other platforms.

.EXAMPLE
    .\Get-LastLoggedOnUser.ps1 -CsvPath C:\Temp\serials.csv
#>

[CmdletBinding()]
param(
    [string]$CsvPath,
    [string]$OutputPath
)

#region Setup ---------------------------------------------------------------

# Invoke-MgGraphRequest returns a Hashtable by default, but can be configured to return a
# PSObject. This reads a key/property from either, and avoids the Hashtable member collision
# on names like Values / Keys / Count (where dot-notation returns the Hashtable's own member).
function Get-GraphValue {
    param($InputObject, [string]$Name)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    return $InputObject.PSObject.Properties[$Name].Value
}

if (-not $OutputPath) {
    $base = if ($env:PUBLIC) { $env:PUBLIC } else { (Get-Location).Path }
    $OutputPath = Join-Path $base 'LastLoggedOnUser.csv'
}

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All", "User.Read.All" -NoWelcome

#endregion

#region Read serial numbers -------------------------------------------------

if (-not $CsvPath) {
    $CsvPath = Read-Host -Prompt "Enter the full path to the file containing SerialNumbers (one per line, or a CSV with a SerialNumber column)"
}

if (-not (Test-Path -LiteralPath $CsvPath)) {
    Write-Host "File not found at $CsvPath. Exiting." -ForegroundColor Red
    return
}

# Accept either a real CSV with a SerialNumber column, or a plain one-serial-per-line list.
$serials = @()
$firstLine = Get-Content -LiteralPath $CsvPath -TotalCount 1

if ($firstLine -match '(?i)serial') {
    $imported = Import-Csv -LiteralPath $CsvPath
    $serialColumn = ($imported | Get-Member -MemberType NoteProperty |
        Where-Object { $_.Name -match '(?i)serial' } | Select-Object -First 1).Name

    if ($serialColumn) {
        $serials = $imported | ForEach-Object { $_.$serialColumn }
    }
    else {
        # Header-ish first line but no usable column: fall back to raw lines, skipping the header.
        $serials = Get-Content -LiteralPath $CsvPath | Select-Object -Skip 1
    }
}
else {
    $serials = Get-Content -LiteralPath $CsvPath
}

$serials = $serials |
    ForEach-Object { if ($null -ne $_) { $_.ToString().Trim().Trim('"').Trim() } } |
    Where-Object { $_ -and $_ -ne 'ToBeFilledByO.E.M.' } |
    Select-Object -Unique

if (-not $serials) {
    Write-Host "No usable serial numbers found in $CsvPath. Exiting." -ForegroundColor Red
    return
}

Write-Host "Read $($serials.Count) serial number(s) from $CsvPath" -ForegroundColor Cyan

#endregion

#region Resolve devices -----------------------------------------------------

$deviceProperties = @(
    'id', 'deviceName', 'serialNumber', 'userPrincipalName', 'userDisplayName',
    'model', 'manufacturer', 'complianceState', 'lastSyncDateTime', 'enrolledDateTime',
    'operatingSystem', 'managedDeviceOwnerType', 'managementAgent', 'deviceEnrollmentType'
)

$devices     = [System.Collections.Generic.List[object]]::new()
$notFound    = [System.Collections.Generic.List[string]]::new()
$serialCount = 0

foreach ($serial in $serials) {
    $serialCount++
    Write-Host "Looking up $serialCount / $($serials.Count) : $serial" -ForegroundColor DarkCyan

    $escapedSerial = $serial.Replace("'", "''")   # escape single quotes for the OData filter

    try {
        $match = Get-MgDeviceManagementManagedDevice -All -Filter "serialNumber eq '$escapedSerial'" -ErrorAction Stop |
            Select-Object $deviceProperties
    }
    catch {
        Write-Host "  Lookup failed for '$serial': $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    if ($match) { $devices.AddRange(@($match)) }
    else {
        Write-Host "  No device found for serial '$serial'" -ForegroundColor DarkYellow
        $notFound.Add($serial)
    }
}

if ($devices.Count -eq 0) {
    Write-Host "No devices found." -ForegroundColor Yellow
    return
}

#endregion

#region Build output table --------------------------------------------------

$table = New-Object System.Data.DataTable

@(
    'DeviceId', 'DeviceName', 'SerialNumber', 'UPN', 'UserDisplayName',
    'LastLogonUser', 'LastLogonUserEmail', 'LastLogonTime',
    'Model', 'Manufacturer', 'ComplianceState', 'LastSyncTime', 'EnrollDate',
    'OperatingSystem', 'DeviceOwnership', 'ManagementAgent', 'EnrollmentType'
) | ForEach-Object { $table.Columns.Add($_) | Out-Null }

$count             = 0
$totalDevicesCount = $devices.Count

foreach ($device in $devices) {
    $count++
    Write-Host "# $count / $totalDevicesCount : $($device.DeviceName)" -ForegroundColor Yellow

    # Defaults reset every iteration so stale values can never leak into the next row.
    $userName      = '--Unknown--'
    $userEmail     = '--Unknown--'
    $lastLogonTime = $null

    $id  = $device.Id
    $url = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id"

    try {
        $deviceBeta = Invoke-MgGraphRequest -Method GET -Uri $url -ErrorAction Stop
    }
    catch {
        Write-Host "  Failed to read beta device object: $($_.Exception.Message)" -ForegroundColor Red
        $deviceBeta = $null
    }

    $usersLoggedOn = @(Get-GraphValue -InputObject $deviceBeta -Name 'usersLoggedOn')
    $usersLoggedOn = @($usersLoggedOn | Where-Object { $_ })

    if ($usersLoggedOn.Count -gt 0) {

        if ($usersLoggedOn.Count -gt 1) {
            $usersLoggedOn = @($usersLoggedOn | Sort-Object -Descending -Property lastLogOnDateTime)
        }

        $lastUserId    = $usersLoggedOn[0].userId
        $lastLogonTime = $usersLoggedOn[0].lastLogOnDateTime

        if ($lastUserId) {
            try {
                $user      = Get-MgUser -UserId $lastUserId -ErrorAction Stop
                $userName  = $user.DisplayName
                $userEmail = $user.Mail
            }
            catch {
                Write-Host "  Error getting user info. Likely deleted account." -ForegroundColor DarkYellow
            }
        }
    }
    else {
        # Fallback: device compliance report often still carries a UPN and last contact time.
        $body = @{
            select  = @()
            skip    = 0
            top     = 50
            filter  = "(DeviceId eq '$id') and (PolicyPlatformType eq '6')"
            orderBy = @('PolicyName asc')
            search  = ''
        } | ConvertTo-Json -Depth 3

        $uri = 'https://graph.microsoft.com/beta/deviceManagement/reports/getDevicePoliciesComplianceReport'

        try {
            $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $body -ContentType 'application/json' -ErrorAction Stop
        }
        catch {
            Write-Host "  Compliance report call failed: $($_.Exception.Message)" -ForegroundColor Red
            $response = $null
        }

        if ($response) {
            # Resolve column positions by name from the returned schema instead of hardcoding indices.
            $schema   = @(Get-GraphValue -InputObject $response -Name 'Schema')
            $colIndex = @{}
            for ($i = 0; $i -lt $schema.Count; $i++) {
                $colName = Get-GraphValue -InputObject $schema[$i] -Name 'Column'
                if ($colName) { $colIndex[[string]$colName] = $i }
            }

            $rows  = @(Get-GraphValue -InputObject $response -Name 'Values')
            $items = if ($rows.Count -gt 0) { @($rows[0]) } else { $null }

            if ($items) {
                # Verify these against the schema your tenant actually returns on the first run.
                $userColName = 'UPN'
                $timeColName = 'LastContact'

                $userInfo      = if ($colIndex.ContainsKey($userColName)) { $items[$colIndex[$userColName]] } else { $null }
                $lastLogonTime = if ($colIndex.ContainsKey($timeColName)) { $items[$colIndex[$timeColName]] } else { $null }

                if ($userInfo) {
                    try {
                        $user      = Get-MgUser -UserId $userInfo -ErrorAction Stop
                        $userName  = $user.DisplayName
                        $userEmail = $user.Mail
                    }
                    catch {
                        Write-Host "  Error getting user info. Likely deleted account." -ForegroundColor DarkYellow
                    }
                }
            }
        }
    }

    $table.Rows.Add(
        $device.Id, $device.DeviceName, $device.SerialNumber, $device.UserPrincipalName, $device.UserDisplayName,
        $userName, $userEmail, $lastLogonTime,
        $device.Model, $device.Manufacturer, $device.ComplianceState, $device.LastSyncDateTime, $device.EnrolledDateTime,
        $device.OperatingSystem, $device.ManagedDeviceOwnerType, $device.ManagementAgent, $device.DeviceEnrollmentType
    ) | Out-Null
}

#endregion

#region Export --------------------------------------------------------------

$columnNames = $table.Columns | Select-Object -ExpandProperty ColumnName

$table.Rows |
    Select-Object -Property $columnNames |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Exported $($table.Rows.Count) row(s) to $OutputPath" -ForegroundColor Green

if ($notFound.Count -gt 0) {
    Write-Host "$($notFound.Count) serial(s) had no matching Intune device:" -ForegroundColor Yellow
    $notFound | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}

if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    $table.Rows | Select-Object -Property $columnNames | Out-GridView
}

#endregion