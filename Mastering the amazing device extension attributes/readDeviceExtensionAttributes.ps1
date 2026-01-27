Connect-MgGraph -Scopes "Device.Read.All","Directory.Read.All"

# Entra ID deviceId (GUID) - the "Device ID" property on the device object
$entraDeviceId = "d4fe7726-5966-431c-b3b8-cddc8fdb717d"

# Look up the device by deviceId
$device = Get-MgDevice -Filter "deviceId eq '$entraDeviceId'" | Select-Object *

if (-not $device) {
    throw "Device with deviceId '$entraDeviceId' not found in Microsoft Entra ID."
}

# Optional safety check
if ($device.Count -gt 1) {
    throw "Multiple devices found for deviceId '$entraDeviceId'. Verify the value."
}

# Output extension attributes
$device.AdditionalProperties["extensionAttributes"] | Format-List