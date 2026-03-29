Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "DeviceManagementManagedDevices.Read.All"

$devicesPath = "C:\Temp\deviceNames.txt"
if (-not (Test-Path $devicesPath)) {
    Write-Warning "Device list not found at: $devicesPath"
    exit
}
$devices = Get-Content -Path $devicesPath

$group = Read-Host -Prompt "Give the group name: "
try{
    $groupObject = Get-MgGroup -Filter "displayName eq '$group'"
    $groupObjectID = $groupObject.Id
    Write-Host "Group Object ID: $groupObjectID"
}
catch{
    Write-Output "Entra ID Group does not exist or insufficient right"
    Start-Sleep -Seconds 3
    exit
}

foreach ($device in $devices){
    Write-Host "-------------------------"
    Write-Host "Going to import device: $device"
    $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$device'"

    if ($null -ne $IntuneDevice){
        $EntraDeviceID = $IntuneDevice.AzureADDeviceId
        Write-Host "Device Entra ID: $EntraDeviceID"
        $DeviceObject = Get-MgDevice -Filter "deviceId eq '$EntraDeviceID'"
        $DeviceObjectID = $DeviceObject.Id
        Write-Host "Device Object ID: $DeviceObjectID"
    }
    else{
        Write-Output "Device does not exist"
        continue
    }

    $isDeviceMemberOfGroup = Get-MgGroupMember -GroupId $groupObjectID -All | Where-Object {$_.AdditionalProperties.displayName -like "*$($device)*"}

    if($isDeviceMemberOfGroup -eq $null) {
        Write-Host "Adding the device $device to group $group"
        New-MgGroupMember -GroupId $groupObjectID -DirectoryObjectId $DeviceObjectID
    }
    else{
        Write-Host "Device already member"
    }
}
