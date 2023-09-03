Connect-AzureAD

$group = Get-AzureADGroup -SearchString "ThisIsYourGroup"

# depending on the user members users or devices select the appropriate command below
$devices = Get-AzureADGroupMember -ObjectId $group.ObjectId -All $true | where {$_.ObjectType -eq 'Device'} 
# $users = Get-AzureADGroupMember -ObjectId $group.ObjectId -All $true | where {$_.ObjectType -eq 'User'}

foreach($device in $devices){
    Remove-AzureADGroupMember -ObjectId $group.ObjectId -MemberId $device.objectId
}