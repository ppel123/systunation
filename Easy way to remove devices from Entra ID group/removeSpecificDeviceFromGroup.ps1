<#
.SYNOPSIS
    Removes devices by serial number from an Entra ID group.

.DESCRIPTION
    Connects to Microsoft Graph, reads a list of serial numbers from 
    "C:\Temp\serials.txt", prompts for a target group name, and then
    iterates through each serial number to remove the corresponding device
    from the specified Entra ID group. Logs progress and errors to the host.
#>

Write-Host "=== Device Removal Script Starting ===" -ForegroundColor Cyan

Write-Host "Step 1: Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph
Write-Host "Connected to Microsoft Graph" -ForegroundColor Green

Write-Host "Step 2: Reading serial numbers file..." -ForegroundColor Cyan
$serialFile = "C:\Temp\serials.txt"
if (-Not (Test-Path $serialFile)) {
    Write-Host "ERROR: Serial file not found at $serialFile" -ForegroundColor Red
    Exit 1
}
$Serials = Get-Content -Path $serialFile
Write-Host "Loaded $($Serials.Count) serial numbers" -ForegroundColor Green

Write-Host "Step 3: Prompting for target group..." -ForegroundColor Cyan
Write-Host "Please enter the name of the Entra ID group to remove members from:" -ForegroundColor Yellow
$group = Read-Host

Write-Host "Step 4: Preparing to remove $($Serials.Count) device(s) from group '$group'" -ForegroundColor Cyan
Start-Sleep -Seconds 1

$totalDevices = $Serials.Count
$counter      = 1

foreach ($Serial in $Serials) {
    Write-Host "Processing device $counter of $totalDevices : Serial='$Serial'" -ForegroundColor DarkCyan
    try {
        # Lookup managed device by serial
        $mgDevice = Get-MgDeviceManagementManagedDevice -Filter "SerialNumber eq '$Serial'" -ErrorAction Stop | Select-Object -ExpandProperty azureADDeviceId

        Write-Host "Found Entra ID Device ID: $mgDevice" -ForegroundColor Gray

        # Lookup Entra ID device object
        $aadDevice = Get-MgDevice -Filter "deviceId eq '$mgDevice'" -ErrorAction Stop | Select-Object -ExpandProperty Id

        Write-Host "Found Directory Object ID: $aadDevice" -ForegroundColor Gray

        # Lookup group object
        $groupObj = Get-MgGroup -Filter "DisplayName eq '$group'" -ErrorAction Stop | Select-Object -ExpandProperty Id

        Write-Host "Found Group Object ID: $groupObj" -ForegroundColor Gray

        # Remove device from group
        Remove-MgGroupMemberByRef -GroupId $groupObj -DirectoryObjectId $aadDevice -ErrorAction Stop
        Write-Host "Successfully removed device" -ForegroundColor Green
    }
    catch {
        Write-Host "Error removing serial '$Serial' from group '$group'" -ForegroundColor Red
        Write-Host "$($_.Exception.Message)" -ForegroundColor Red
    }

    $counter++
}

Write-Host "=== Script complete: Processed $($counter - 1) device(s) ===" -ForegroundColor Cyan
