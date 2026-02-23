<# 
.SYNOPSIS
    Builds a simple inventory report for a list of Entra ID device IDs:
    - Pulls device details from Intune (managedDevices)
    - Checks whether each device has Windows Autopilot identity data
    - Displays results in Out-GridView and exports to CSV

.PREREQUISITES
    - Microsoft.Graph PowerShell SDK installed
    - You are signed in with sufficient permissions to read:
        * Intune managed devices
        * Windows Autopilot device identities

.INPUT
    Text file with one Entra ID device ID (GUID) per line:
    C:\Temp\EntraIDs.txt

.OUTPUT
    Grid view + CSV:
    C:\Temp\AutopilotInfoDevices.csv
#>

# Connect to Microsoft Graph (interactive sign-in).
Connect-MgGraph

# -----------------------------
# Configuration
# -----------------------------
$InputPath  = "C:\Temp\EntraIDs.txt"
$ExportPath = "C:\Temp\AutopilotInfoDevices.csv"

# -----------------------------
# Prepare output table
# -----------------------------
$table = New-Object System.Data.DataTable
[void]$table.Columns.Add("DeviceName")
[void]$table.Columns.Add("LastSyncDateTime")
[void]$table.Columns.Add("Ownership")
[void]$table.Columns.Add("EntraID")
[void]$table.Columns.Add("IntuneID")
[void]$table.Columns.Add("AutopilotInfo")

# Read Entra device IDs from file
$deviceEntraIDIds = Get-Content -Path $InputPath
Write-Host "Count of devices: $($deviceEntraIDIds.Count)"

# -----------------------------
# Main loop
# -----------------------------
foreach ($EntraIDId in $deviceEntraIDIds) {

    # Reset variables for each iteration
    $info                = $null
    $autopilotDeviceInfo = $null
    $hasAutopilotData    = $null

    Write-Host "Processing: $EntraIDId"

    # 1) Query Intune managed device record by Entra/Azure AD device ID
    # NOTE: If multiple records could match (rare), you'd want to handle arrays.
    $info = Get-MgDeviceManagementManagedDevice -Filter "AzureAdDeviceId eq '$EntraIDId'" | Select-Object *

    # 2) Query Autopilot identity (Graph beta endpoint)
    # Filter by azureActiveDirectoryDeviceId
    $url = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$filter=azureActiveDirectoryDeviceId%20eq%20%27$EntraIDId%27"
    $autopilotDeviceInfo = (Invoke-MgGraphRequest -Method GET -Uri $url).value

    # Determine whether Autopilot data exists
    if (($null -ne $autopilotDeviceInfo) -and ($autopilotDeviceInfo -ne "")) {
        $hasAutopilotData = "Has data in Autopilot"
    }
    else {
        $hasAutopilotData = "Does not have Autopilot data."
    }

    # Extract fields from Intune managed device record
    # NOTE: If $info is $null (no Intune record), these will be empty.
    $deviceName            = $info.DeviceName
    $deviceLastSyncDateTime= $info.LastSyncDateTime
    $deviceEntraID         = $info.AzureAdDeviceId
    $deviceIntuneID        = $info.Id
    $ownership             = $info.ManagedDeviceOwnerType

    # Add row to report table
    [void]$table.Rows.Add(
        $deviceName,
        $deviceLastSyncDateTime,
        $ownership,
        $deviceEntraID,
        $deviceIntuneID,
        $hasAutopilotData
    )
}

# -----------------------------
# Display & export
# -----------------------------

# Interactive view (Windows PowerShell / desktop environments)
# Print results to terminal
$table | Format-Table -AutoSize | Out-String | Write-Host

# Interactive view (Windows PowerShell / desktop environments)
$table | Out-GridView -Title "Autopilot / Intune Device Inventory"

# Export to CSV (Append keeps adding to existing file—remove -Append if you prefer a fresh file each run)
$table | Export-Csv -NoTypeInformation -Path $ExportPath -Encoding UTF8 -Append
