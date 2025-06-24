<#
.SYNOPSIS
    Deploy HKCU registry values for all users via Intune (no caching).
.DESCRIPTION
    Loads each user NTUSER.DAT hive, writes desired HKCU values, then unloads the hive.
    Uses Start-Transcript and Write-Host for logging, with -ErrorAction Stop on critical cmdlets.
    Captures all Write-Host output in $intuneOutput for later inspection.
#>

param (
    [string]$LogFile = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\SysTuNation_HKCUDeploy.log'
)

try {
    Start-Transcript -Path $LogFile -Append -NoClobber -ErrorAction Stop | Out-Null
    Write-Host "Transcript started: $LogFile"
} catch {
    Write-Host "ERROR: Failed to start transcript - $_"
    exit 1
}

# Initialize Intune output accumulator
$script:intuneOutput = ""

function LogMessage {
    param([string]$Msg)
    $ts   = (Get-Date).ToString('o')
    $line = "$ts`t$Msg"
    Write-Host $line
    $script:intuneOutput += $line + "|"
}

# Define registry settings
$RegKey = 'Software\SysTuNation\Settings'
$Values = @{
    'EnableFeatureX' = @{ Data = 1;       Type = 'DWord' }
    'DefaultRegion'  = @{ Data = 'Europe'; Type = 'String' }
}

LogMessage 'Starting deployment of HKCU settings for all users (excluding system/service accounts).'

try {
    # Enumerate all profile SIDs, excluding system/service accounts (S-1-5-18,19,20)
    $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop |
        Where-Object { $_.PSChildName -notmatch '^S-1-5-(18|19|20)$' } |
        ForEach-Object {
            [PSCustomObject]@{
                SID      = $_.PSChildName
                HivePath = Join-Path -Path $_.GetValue('ProfileImagePath') -ChildPath 'NTUSER.DAT'
            }
        }
    LogMessage "Profiles to process: $($profiles.Count) (system/service accounts excluded)."
} catch {
    LogMessage "ERROR: Failed to enumerate profiles - $_"
    Stop-Transcript | Out-Null
    exit 1
}

foreach ($p in $profiles) {
    $sid     = $p.SID
    $hive    = $p.HivePath
    $mounted = $false

    LogMessage "Processing SID: $sid"

    if (-not (Test-Path $hive -PathType Leaf)) {
        LogMessage "SKIP [$sid]: Hive not found at $hive"
        continue
    }

    try {
        # Load user hive if not already loaded
        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            Write-Host "Loading hive for SID $sid"
            & reg.exe LOAD "HKEY_USERS\$sid" $hive
            if ($LASTEXITCODE -ne 0) { throw "reg.exe LOAD failed with exit code $LASTEXITCODE" }
            $mounted = $true
            LogMessage "Loaded hive: HKEY_USERS\$sid"
        } else {
            LogMessage "Hive already loaded: HKEY_USERS\$sid"
        }

        # Apply each registry setting
        foreach ($name in $Values.Keys) {
            $exp      = $Values[$name]
            $fullPath = "Registry::HKEY_USERS\$sid\$RegKey"

            if (-not (Test-Path $fullPath)) {
                New-Item -Path $fullPath -Force -ErrorAction Stop | Out-Null
                LogMessage "[$sid] Created key: $RegKey"
            }

            New-ItemProperty -Path $fullPath -Name $name `
                -Value $exp.Data -PropertyType $exp.Type -Force -ErrorAction Stop | Out-Null
            LogMessage "[$sid] Set $name = $($exp.Data) ($($exp.Type))"
        }

    } catch {
        LogMessage "ERROR [$sid]: $_"
    } finally {
        # Unload hive if loaded
        if ($mounted) {
            Write-Host "Unloading hive for SID $sid"
            & reg.exe UNLOAD "HKEY_USERS\$sid"
            if ($LASTEXITCODE -ne 0) {
                LogMessage "WARNING [$sid]: reg.exe UNLOAD exit code $LASTEXITCODE"
            } else {
                LogMessage "Unloaded hive: HKEY_USERS\$sid"
            }
        }
    }
}

LogMessage 'HKCU deployment finished.'

# Stop transcript
Stop-Transcript | Out-Null

# Output accumulator for Intune
Write-Host $script:intuneOutput