$allAdmins = Get-LocalGroupMember -Group "Administrators"

$allAdminsNames = $allAdmins.Name

if ("WindowsLocalAdmin" -in $allAdminsNames){
    Write-Host "Local admin exists. Remediation not needed."
    # exit 0 to not remediate
    exit 0
}
else{
    Write-Host "Local admin doesn't exist. Must create. Going to remediation."
    # exit 1 to remediate
    exit 1
}
