<#
.SYNOPSIS
    Detection script for HKCU remediation: checks whether all non-system users have the desired registry values.
.DESCRIPTION
    Enumerates each local user profile (excluding built-in service accounts), loads their NTUSER.DAT hive under HKEY_USERS,<SID>,
    verifies each registry value under Software\SysTuNation\Settings matches the expected data and type,
    then unloads the hive. Exits with code 0 if fully compliant, or 1 if any mismatch is found.
    Logs all actions with Start-Transcript and captures output in $intuneOutput.
#>

param (
    [string]$LogFile = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\SysTuNation_HKCUDetect.log'
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

# Define detection settings
$RegKey   = 'Software\SysTuNation\Settings'
$Values   = @{
    'EnableFeatureX' = @{ Data = 1;       Type = 'DWord' }
    'DefaultRegion'  = @{ Data = 'Europe'; Type = 'String' }
}
$TypeMap = @{ 
    'String' = [Microsoft.Win32.RegistryValueKind]::String;
    'DWord'  = [Microsoft.Win32.RegistryValueKind]::DWord;
    'QWord'  = [Microsoft.Win32.RegistryValueKind]::QWord
}

LogMessage 'Starting detection of HKCU settings for all users (excluding system/service accounts).'

try {
    # Get all profile SIDs, then exclude service accounts (S-1-5-18,19,20)
    $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction Stop |
        Where-Object { $_.PSChildName -notmatch '^S-1-5-(18|19|20)$' } |
        ForEach-Object {
            [PSCustomObject]@{
                SID      = $_.PSChildName
                HivePath = Join-Path -Path $_.GetValue('ProfileImagePath') -ChildPath 'NTUSER.DAT'
            }
        }
    LogMessage "Profiles to check: $($profiles.Count) (system/service accounts excluded)."
} catch {
    LogMessage "ERROR: Failed to enumerate profiles - $_"
    Stop-Transcript | Out-Null
    exit 1
}

$nonCompliant = $false

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
        # Load hive if not already loaded
        if (-not (Test-Path "Registry::HKEY_USERS\$sid")) {
            Write-Host "Loading hive for SID $sid"
            & reg.exe LOAD "HKEY_USERS\$sid" $hive
            if ($LASTEXITCODE -ne 0) { throw "reg.exe LOAD failed with code $LASTEXITCODE" }
            $mounted = $true
            LogMessage "Loaded hive: HKEY_USERS\$sid"
        } else {
            LogMessage "Hive already loaded: HKEY_USERS\$sid"
        }

        # Verify each expected value
        foreach ($name in $Values.Keys) {
            $fullPath = "Registry::HKEY_USERS\$sid\$RegKey"
            if (-not (Test-Path $fullPath)) {
                LogMessage "[$sid] Key missing: $RegKey"
                $nonCompliant = $true; break
            }

            Write-Host "Checking value '$name' for SID $sid"
            $item = Get-ItemProperty -Path $fullPath -Name $name -ErrorAction Stop
            $actualData = $item.$name
            $actualType = (Get-Item $fullPath).GetValueKind($name)

            if ($actualData -ne $Values[$name].Data -or $actualType -ne $TypeMap[$Values[$name].Type]) {
                LogMessage "[$sid] Mismatch on $name : expected '$($Values[$name].Data)' ($($Values[$name].Type)), got '$actualData' ($actualType)"
                $nonCompliant = $true; break
            } else {
                LogMessage "[$sid] $name is compliant"
            }
        }

    } catch {
        LogMessage "ERROR [$sid]: $_"
        $nonCompliant = $true
    } finally {
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

    if ($nonCompliant) { break }
}

if ($nonCompliant) {
    LogMessage 'Detection result: NON-COMPLIANT'
    $exitCode = 1
} else {
    LogMessage 'Detection result: COMPLIANT'
    $exitCode = 0
}

LogMessage 'Detection complete.'

# Stop transcript
Stop-Transcript | Out-Null

# Output accumulator for Intune
Write-Host "Detection Output: $intuneOutput"

exit $exitCode