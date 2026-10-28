<#
.SYNOPSIS
    Unlock: restore default "Allow log on locally" (Administrators, Users, Backup Operators).
.NOTES
    Run as SYSTEM, 64-bit PowerShell.
    Author: systunation.com
#>

$cfgPath = "$env:windir\Temp\LockToUser_restore.inf"
$dbPath  = "$env:windir\Temp\LockToUser_restore.sdb"

$inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeInteractiveLogonRight = *S-1-5-32-544,*S-1-5-32-545,*S-1-5-32-551
"@

$inf | Out-File -FilePath $cfgPath -Encoding Unicode -Force
secedit.exe /configure /db $dbPath /cfg $cfgPath /areas USER_RIGHTS /quiet | Out-Null
Remove-Item $cfgPath, $dbPath -Force -ErrorAction SilentlyContinue

Write-Output 'Allow log on locally restored to Windows defaults'
exit 0