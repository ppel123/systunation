# ===============================
# Tag a device for Pilot rollout
# (using Entra ID deviceId as input)
# ===============================

# Connect (admin consent required for the scopes)
Connect-MgGraph -Scopes "Device.ReadWrite.All","Directory.ReadWrite.All"

# Entra ID deviceId (GUID) - this is the "Device ID" property on the device object
# Example: d4fe7726-5966-431c-b3b8-cddc8fdb717d
$entraDeviceId = "d4fe7726-5966-431c-b3b8-cddc8fdb717d"

# Look up the device by deviceId (GUID)
$device = Get-MgDevice -Filter "deviceId eq '$entraDeviceId'"

if (-not $device) {
    throw "Device with deviceId '$entraDeviceId' not found in Microsoft Entra ID."
}

# If you want to be extra safe in case of unexpected duplicates:
if ($device.Count -gt 1) {
    throw "Multiple devices found for deviceId '$entraDeviceId'. This should not happen—verify the value."
}

$params = @{
    extensionAttributes = @{
        extensionAttribute1 = "Pilot"
    }
}

# IMPORTANT: Update-MgDevice requires the Entra object Id (device.Id), not the deviceId GUID
Update-MgDevice -DeviceId $device.Id -BodyParameter $params

Write-Host "Device '$($device.DisplayName)' (deviceId: $entraDeviceId) successfully tagged as Pilot."