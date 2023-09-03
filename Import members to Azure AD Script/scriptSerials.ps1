Connect-AzureAD
Connect-MSGraph

$serials = Get-Content -Path "C:\Users\Public\devicesSerials.txt"

$group = Read-Host -Prompt "Give the group name: "
try{
    $groupObjectID = (Get-AzureADGroup -SearchString $group | select objectID).objectID
    Write-Host "Group Object ID: $groupObjectID"
}
catch{
    Write-Output "Azure AD Group does not exist or insufficient right"
    Start-Sleep -Seconds 3
    exit
}

foreach ($serial in $serials){
    Write-Host "-------------------------"
    $AzureDevice = Get-IntuneManagedDevice -Filter "serialNumber eq '$serial'"
    $AzureDeviceName = $AzureDevice.deviceName
    Write-Host "Going to import device: $AzureDeviceName"

    if ($AzureDevice -ne $null){
        $AzureADID = $AzureDevice.azureADDeviceId
        Write-Host "Device AzureAD ID: $AzureADID"
        $DeviceObjectID = (Get-AzureADDevice -Filter "deviceId eq guid'$AzureADID'" | select objectID).objectID
        Write-Host "Device Object ID: $DeviceObjectID"
    }
    else{
        Write-Output "Device does not exist"
        continue
    }

    $isDeviceMemberOfGroup = Get-AzureADGroupMember -ObjectId $groupObjectID -All $true | Where-Object {$_.DisplayName -like "*$($AzureDeviceName)*"}

    if($isUserMemberOfGroup -eq $null) {
        Write-Host "Adding the device $AzureDeviceName to group $group"
        Add-AzureADGroupMember -ObjectId $groupObjectID -RefObjectId $DeviceObjectID
    }
    else{
        Write-Host "Device already member"
    }
}