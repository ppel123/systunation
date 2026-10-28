<#
.SYNOPSIS
    Detection: is this device locked to a single user yet?
.NOTES
    Run as SYSTEM, 64-bit PowerShell.
    Exit 0 = already locked, or no single eligible user signed in (do nothing)
    Exit 1 = not locked and exactly one eligible user is signed in (remediate)
    Author: systunation.com
#>

$usersSID = 'S-1-5-32-545'   # BUILTIN\Users - its presence means "not locked yet"
$logPath  = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs\LockToUser_Detection.log"
$cfgPath  = "$env:windir\Temp\LockToUser_detect.cfg"

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'u')] $Message"
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
}

try {
    # -- 1. Read the effective right from the LSA store --------------------------
    $null = secedit.exe /export /cfg $cfgPath /areas USER_RIGHTS 2>&1
    if (-not (Test-Path $cfgPath)) { Write-Log 'secedit export failed.'; Write-Output 'Export failed'; exit 0 }

    $line = Get-Content -Path $cfgPath -Encoding Unicode |
            Where-Object { $_ -match '^SeInteractiveLogonRight\s*=' }
    Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
    Write-Log "Current: $line"

    if (-not $line) { Write-Log 'Right not found - not touching it.'; Write-Output 'Right missing'; exit 0 }

    # -- 2. Already locked? (Users group removed) ----------------------------------
    if ($line -notmatch [regex]::Escape("*$usersSID")) {
        Write-Log 'Users group absent - device already locked.'
        Write-Output 'Locked'
        exit 0
    }

    # -- 3. Who is signed in? SID straight from the explorer.exe token ------------
    $machineSid = (Get-LocalUser | Where-Object { $_.SID.Value -match '-500$' }).SID.AccountDomainSid.Value

    $userSids = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" |
        ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid } |
        Where-Object { $_.ReturnValue -eq 0 -and $_.Sid } |
        Select-Object -ExpandProperty Sid -Unique |
        Where-Object {
            # Drop local accounts (LAPS admin, built-in Administrator, other local users)
            ([System.Security.Principal.SecurityIdentifier]$_).AccountDomainSid.Value -ne $machineSid
        }

    # -- 4. Only act on exactly one eligible user --------------------------------
    $count = @($userSids).Count
    if ($count -ne 1) {
        Write-Log "Eligible interactive users found: $count - doing nothing."
        Write-Output "Not locked - $count eligible users"
        exit 0
    }

    # -- 5. Not locked and one user signed in: remediate --------------------------
    Write-Log "Not locked. Eligible user SID: $userSids - triggering remediation."
    Write-Output "Not locked - user $userSids"
    exit 1
}
catch {
    Write-Log "Detection error: $($_.Exception.Message)"
    Write-Output 'Detection error'
    exit 0   # fail safe: never remediate on an error
}