# Clear/remove a device extension attribute (using Entra ID deviceId as input)

$entraDeviceId  = "d4fe7726-5966-431c-b3b8-cddc8fdb717d"   # Device ID (GUID)
$attributeName  = "extensionAttribute1"

Connect-MgGraph -Scopes "Device.ReadWrite.All","Directory.ReadWrite.All"

# Look up the device by deviceId (GUID)
$device = Get-MgDevice -Filter "deviceId eq '$entraDeviceId'"

if (-not $device) {
    throw "Device with deviceId '$entraDeviceId' not found in Microsoft Entra ID."
}

# Optional safety check
if ($device.Count -gt 1) {
    throw "Multiple devices found for deviceId '$entraDeviceId'. Verify the value."
}

$params = @{
    extensionAttributes = @{
        $attributeName = ""
    }
}

# IMPORTANT: Update-MgDevice requires the Entra object Id (device.Id), not the deviceId GUID
Update-MgDevice -DeviceId $device.Id -BodyParameter $params

Write-Host "Attribute '$attributeName' cleared for device '$($device.DisplayName)' (deviceId: $entraDeviceId)."