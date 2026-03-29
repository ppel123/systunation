Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "DeviceManagementManagedDevices.Read.All"

$serialsPath = "C:\Temp\deviceSerials.txt"
if (-not (Test-Path $serialsPath)) {
    Write-Warning "Serials list not found at: $serialsPath"
    exit
}
$serials = Get-Content -Path $serialsPath

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

foreach ($serial in $serials){
    Write-Host "-------------------------"
    Write-Host "Going to import device with serial: $serial"
    $IntuneDevice = Get-MgDeviceManagementManagedDevice -Filter "serialNumber eq '$serial'"

    if ($null -ne $IntuneDevice){
        $DeviceName = $IntuneDevice.DeviceName
        $EntraDeviceID = $IntuneDevice.AzureADDeviceId
        Write-Host "Device Name: $DeviceName"
        Write-Host "Device Entra ID: $EntraDeviceID"
        $DeviceObject = Get-MgDevice -Filter "deviceId eq '$EntraDeviceID'"
        $DeviceObjectID = $DeviceObject.Id
        Write-Host "Device Object ID: $DeviceObjectID"
    }
    else{
        Write-Output "Device does not exist"
        continue
    }

    $isDeviceMemberOfGroup = Get-MgGroupMember -GroupId $groupObjectID -All | Where-Object {$_.AdditionalProperties.displayName -like "*$($DeviceName)*"}

    if($isDeviceMemberOfGroup -eq $null) {
        Write-Host "Adding the device $DeviceName to group $group"
        New-MgGroupMember -GroupId $groupObjectID -DirectoryObjectId $DeviceObjectID
    }
    else{
        Write-Host "Device already member"
    }
}
