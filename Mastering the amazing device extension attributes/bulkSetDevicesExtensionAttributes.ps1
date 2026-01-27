Connect-MgGraph -Scopes "Device.ReadWrite.All","Directory.ReadWrite.All"

$csv = Import-Csv "C:\Temp\devices.csv" -Delimiter ","

foreach ($row in $csv) {
    $aadDeviceId = $row.deviceId
    $ringValue   = $row.ring

    $device = Get-MgDevice -Filter "deviceId eq '$aadDeviceId'"

    if (-not $device) {
        Write-Warning "DeviceId '$aadDeviceId' not found. Skipping."
        continue
    }

    $params = @{
        extensionAttributes = @{
            extensionAttribute1 = $ringValue
        }
    }

    Update-MgDevice -DeviceId $device.Id -BodyParameter $params
    Write-Host "Tagged $($device.DisplayName) ($aadDeviceId) => $ringValue"
}