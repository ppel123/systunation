# Install needed modules - if required
# Install-Module -Name Microsoft.Graph
# Install-Module -Name Microsoft.Graph.Intune
# Install-Module -Name Microsoft.Graph.DeviceManagement

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Device.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All", "Directory.ReadWrite.All", "DeviceManagementServiceConfig.ReadWrite.All"

# Import serials from a txt file
$importedSerials = Get-Content -Path "C:\Temp\serials2delete.txt"

# Iterate through every serial and delete record
foreach ($serial in $importedSerials){
    
    try {
        # Get device info from Intune
        $device = Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$serial'" 
        if ($device) {
            Write-Host "Starting deletion of device $($device.DeviceName)"
        
            # Delete Intune record using the Intune Device ID as identifier
            try {
                Write-Host "Deleting Intune Record for $serial"
                Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id -Verbose -ErrorAction Stop
                Start-Sleep -Seconds 10
            } catch {
                Write-Host "Error deleting Intune record for $serial : $_" -ForegroundColor Red
            }

            # Delete Autopilot device using serial as identifier
            try {
                Write-Host "Deleting Autopilot Record for $serial"
                $autopilotDevice = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object { $_.SerialNumber -eq $serial }
                if ($autopilotDevice) {
                    Remove-MgDeviceManagementWindowsAutopilotDeviceIdentity -WindowsAutopilotDeviceIdentityId $autopilotDevice.Id
                }
                Start-Sleep -Seconds 10
            } catch {
                Write-Host "Error deleting Autopilot record for $serial : $_" -ForegroundColor Red
            }
            
            # Delete Entra ID record using EntraID device ID as identifier
            try {
                Write-Host "Fetching Entra ID Device for $serial"
                $entraIDValue = $device.AzureAdDeviceId
                $entraIDData = Get-MgDevice -Filter "DeviceId eq '$entraIDValue'"
                Write-Host "Deleting Entra ID Record for $serial"
                Remove-MgDevice -DeviceId $entraIDData.Id
                Start-Sleep -Seconds 10
            } catch {
                Write-Host "Error deleting Entra ID record for $serial : $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No device found with serial number $serial"
        }
    } catch {
        Write-Host "Error processing serial number $serial : $_" -ForegroundColor Red
    }
}
