Install-Module -Name Microsoft.Graph.Intune
Install-Module -Name WindowsAutopilotIntune
Install-Module -Name AzureAD

Connect-MSGraph
Connect-AzureAD

$importedSerials = Get-Content -Path "C:\Users\Public\serials2delete.txt"

foreach ($serial in $importedSerials){

    $info = Get-IntuneManagedDevice -Filter "serialNumber eq '$serial'" | Select deviceName, serialNumber, lastSyncDateTime, complianceState, managedDeviceId
    Write-Host "Starting deletion of device $($info.deviceName)"

    Write-Host "Deleting Intune Record for $serial"
    Remove-IntuneManagedDevice -managedDeviceId $info.managedDeviceId -Verbose -ErrorAction Stop
    Start-Sleep -Seconds 5

    Write-Host "Deleting Autopilot Record for $serial"
    Get-AutopilotDevice | Where-Object SerialNumber -eq $serial | Remove-AutopilotDevice
    Start-Sleep -Seconds 5
    
    $azureADinfo = Get-AzureADDevice -Filter "DisplayName eq '$($info.deviceName)'" | select *
    Write-Host "Deleting Azure AD Record for $serial"
    Remove-AzureADDevice -ObjectId $azureADinfo.ObjectId
    Start-Sleep -Seconds 5
}

# asd
