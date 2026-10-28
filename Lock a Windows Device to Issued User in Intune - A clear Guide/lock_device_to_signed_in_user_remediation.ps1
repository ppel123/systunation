<#
.SYNOPSIS
    Remediation: lock SeInteractiveLogonRight to the signed-in user + Administrators.
.NOTES
    Run as SYSTEM, 64-bit PowerShell.
    Removes BUILTIN\Users (and Backup Operators) from "Allow log on locally".
    Author: systunation.com
#>

$adminSID  = 'S-1-5-32-544'   # BUILTIN\Administrators - never remove
$usersSID  = 'S-1-5-32-545'
# -- Accounts that must ALWAYS keep "Allow log on locally" --------------------
# $adminSID above already covers every member of the local Administrators group:
#   - the built-in Administrator account (if enabled)
#   - the Windows LAPS managed account (it is a local admin)
#   - Microsoft Entra Joined Device Local Administrator role holders
# No action is needed for those.
#
# Add below ONLY accounts that are NOT local admins but must still sign in,
# for example a non-admin local support / break-glass account, or a dedicated
# Entra ID break-glass user. One SID per line, WITHOUT the leading *.
#   Local account : (Get-LocalUser -Name 'breakglass').SID.Value
#   Entra user    : run 'whoami /user' while signed in as that user (S-1-12-1-...)
#   SSPR / PIN reset at the lock screen: 'S-1-5-113' (allows ALL local accounts)
$extraSIDs = @(
    # 'S-1-5-21-1111111111-2222222222-3333333333-1001'   # local break-glass (example)
    # 'S-1-12-1-1111111111-2222222222-3333333333-4444444444'   # Entra break-glass (example)
)

$logPath = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\LockToUser_Remediation.log"
$expPath = "$env:windir\Temp\LockToUser_export.cfg"
$cfgPath = "$env:windir\Temp\LockToUser_apply.inf"
$dbPath  = "$env:windir\Temp\LockToUser_apply.sdb"

function Write-Log {
    param([string]$Message)
    Add-Content -Path $logPath -Value "[$(Get-Date -Format 'u')] $Message" -Encoding UTF8
}

function Get-LogonRightLine {
    $null = secedit.exe /export /cfg $expPath /areas USER_RIGHTS 2>&1
    $l = Get-Content -Path $expPath -Encoding Unicode | Where-Object { $_ -match '^SeInteractiveLogonRight\s*=' }
    Remove-Item $expPath -Force -ErrorAction SilentlyContinue
    return $l
}

try {
    # -- 1. Re-check state ---------------------------------------------------------
    $line = Get-LogonRightLine
    if (-not $line -or $line -notmatch [regex]::Escape("*$usersSID")) {
        Write-Log 'Already locked or right missing - no change.'; Write-Output 'No change'; exit 0
    }

    $machineSid = (Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }).SID.AccountDomainSid.Value
    $userSids = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" |
        ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid } |
        Where-Object { $_.ReturnValue -eq 0 -and $_.Sid } |
        Select-Object -ExpandProperty Sid -Unique |
        Where-Object { ([System.Security.Principal.SecurityIdentifier]$_).AccountDomainSid.Value -ne $machineSid }

    if (@($userSids).Count -ne 1) {
        Write-Log "Eligible users: $(@($userSids).Count) - no change."; Write-Output 'No change'; exit 0
    }
    $userSID = [string]$userSids

    # -- 2. Build the template (Users group intentionally excluded) ---------------
    $entries = @("*$adminSID", "*$userSID") + ($extraSIDs | ForEach-Object { "*$_" })
    $inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeInteractiveLogonRight = $($entries -join ',')
"@
    $inf | Out-File -FilePath $cfgPath -Encoding Unicode -Force

    # -- 3. Apply it ---------------------------------------------------------------
    $out = secedit.exe /configure /db $dbPath /cfg $cfgPath /areas USER_RIGHTS /quiet 2>&1
    Write-Log "secedit /configure: $out"
    Remove-Item $cfgPath, $dbPath -Force -ErrorAction SilentlyContinue

    # -- 4. Verify -----------------------------------------------------------------
    $after = Get-LogonRightLine
    Write-Log "After: $after"
    if ($after -match [regex]::Escape("*$userSID") -and $after -notmatch [regex]::Escape("*$usersSID")) {
        Write-Output "Locked to $userSID + Administrators"
        exit 0
    }
    Write-Output 'Verification failed'
    exit 1
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output 'Remediation error'
    exit 1
}