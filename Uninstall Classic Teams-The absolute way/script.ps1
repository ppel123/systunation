# Define function to unload user hives after loading
function UnloadUserHive {
    param (
        [string]$Username
    )
    if (Test-Path "HKU:\$Username") {
        Remove-PSDrive -Name $Username -Scope Global -Force
        Write-Host "Removed PSDrive for user $Username." -ForegroundColor Cyan

        # Use reg unload to fully release the registry hive
        reg unload "HKU\$Username" | Out-Null
        Write-Host "Unloaded registry hive for user $Username." -ForegroundColor Cyan
    }
}

$logpath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\_UninstallTeamsFinal.log"

if (Test-Path -Path $logpath){
    Remove-Item -PAth $logpath
}

Start-Transcript -Path $logpath

# Start of the script
Write-Host "Starting Classic Teams removal script..." -ForegroundColor Cyan

# Check if the Teams Machine-Wide Installer is present
# Define registry path and display name for Teams Machine-Wide Installer
$registryPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
$displayName = "Teams Machine-Wide Installer"

# Search the registry for the Teams Machine-Wide Installer
Write-Host "Searching for Teams Machine-Wide Installer in the registry..." -ForegroundColor Yellow
$teamsInstallerKey = Get-ChildItem -Path $registryPath | Where-Object {
    $_.GetValue("DisplayName") -eq $displayName
}

# If found, proceed with uninstallation
if ($teamsInstallerKey) {
    $uninstallString = $teamsInstallerKey.GetValue("UninstallString")
    
    if ($uninstallString) {
        
        if ($uninstallString -match '\{[A-F0-9-]+\}') {
            $msiCode = $matches[0]
            Write-Host "Extracted MSI Code: $msiCode" -ForegroundColor Green
        } else {
            Write-Host "No MSI Code found in the string." -ForegroundColor Red
        }

        Write-Host "Found uninstall string for Teams Machine-Wide Installer." -ForegroundColor Yellow
        Write-Host "Starting silent uninstallation..." -ForegroundColor Yellow

        $uninstallArgs = "/x $msiCode /quiet /norestart"

        try {
            # Execute the uninstall command silently
            Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait
            Write-Host "Teams Machine-Wide Installer uninstalled successfully." -ForegroundColor Green
        } catch {
            Write-Host "Error during silent uninstallation: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "No uninstall string found for Teams Machine-Wide Installer." -ForegroundColor Red
    }
} else {
    Write-Host "Teams Machine-Wide Installer is not present on this system." -ForegroundColor Gray
}

# Get list of user profiles on the system
Write-Host "Retrieving user profiles on the system..." -ForegroundColor Yellow
$users = Get-WmiObject -Class Win32_UserProfile -ErrorAction Stop | Where-Object { $_.Special -eq $false }

# Loop through each user profile
foreach ($user in $users) {
    $userSID = $user.SID
    $userProfilePath = $user.LocalPath

    Write-Host "`nProcessing user profile for SID: $userSID" -ForegroundColor Cyan
    Write-Host "User Profile Path: $userProfilePath" -ForegroundColor Cyan

    try {
        # Load the user hive if not currently loaded and create PSDrive
        if (!(Get-PSDrive -Name $userSID -ErrorAction SilentlyContinue)) {
            Write-Host "Loading registry hive for user $userSID..." -ForegroundColor Yellow
            reg load "HKU\$userSID" "$userProfilePath\NTUSER.DAT" | Out-Null
            New-PSDrive -Name $userSID -PSProvider Registry -Root "HKU\$userSID" -Scope Global | Out-Null
        }

        # Define Teams-related paths for per-user installations
        $teamsAppDataPath = Join-Path -Path $userProfilePath -ChildPath "AppData\Local\Microsoft\Teams"
        $updateExePath = Join-Path -Path $teamsAppDataPath -ChildPath "Update.exe"
        $teamsOfficeRegistryPath = "$($userSID):\Software\Microsoft\Office\Teams"
        $teamsUninstallRegistryPath = "$($userSID):\Software\Microsoft\Windows\CurrentVersion\Uninstall"

        Write-Host "Teams AppData Path: $teamsAppDataPath" -ForegroundColor Cyan
        Write-Host "Update.exe Path: $updateExePath" -ForegroundColor Cyan

        # Check if Update.exe exists, and uninstall Teams
        if (Test-Path $updateExePath) {
            Write-Host "Running Teams uninstallation for user $userSID..." -ForegroundColor Yellow
            try {
                & $updateExePath --uninstall | Out-Null
                Write-Host "Teams uninstalled for user $userSID." -ForegroundColor Green
            } catch {
                Write-Host "Error during Teams uninstallation for user $userSID : $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No Teams Update.exe found for user $userSID; skipping uninstallation." -ForegroundColor Gray
        }

        # Remove Teams files from user AppData
        if (Test-Path $teamsAppDataPath) {
            Write-Host "Removing Teams data from AppData for user $userSID..." -ForegroundColor Yellow
            try {
                Remove-Item -Recurse -Force -Path $teamsAppDataPath -ErrorAction Stop
                Write-Host "Teams AppData removed for user $userSID." -ForegroundColor Green
            } catch {
                Write-Host "Error removing Teams AppData for user $userSID : $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No Teams data found in AppData for user $userSID." -ForegroundColor Gray
        }

        # Remove Teams registry entries under Office path
        if (Test-Path $teamsOfficeRegistryPath) {
            Write-Host "Removing Teams registry entries from Office path for user $userSID..." -ForegroundColor Yellow
            try {
                Remove-Item -Recurse -Force -Path $teamsOfficeRegistryPath -ErrorAction Stop
                Write-Host "Teams registry entries removed from Office path for user $userSID." -ForegroundColor Green
            } catch {
                Write-Host "Error removing Teams registry entries from Office path for user $userSID : $_" -ForegroundColor Red
            }
        } else {
            Write-Host "No Teams registry entries found in Office path for user $userSID." -ForegroundColor Gray
        }

        # Search and remove Teams-related registry keys under Uninstall path
        if (Test-Path $teamsUninstallRegistryPath) {
            $uninstallKeys = Get-ChildItem -Path $teamsUninstallRegistryPath | Where-Object {
                $_.GetValue("DisplayName") -like "*Teams*"
            }

            foreach ($key in $uninstallKeys) {
                Write-Host "Removing Teams uninstall registry entry $($key.PSChildName) for user $userSID..." -ForegroundColor Yellow
                try {
                    Remove-Item -Recurse -Force -Path $key.PSPath -ErrorAction Stop
                    Write-Host "Teams uninstall registry entry removed for user $userSID." -ForegroundColor Green
                } catch {
                    Write-Host "Error removing Teams uninstall registry entry $($key.PSChildName) for user $userSID : $_" -ForegroundColor Red
                }
            }
        } else {
            Write-Host "No Teams uninstall registry entries found for user $userSID." -ForegroundColor Gray
        }

    } catch {
        Write-Host "Error processing Teams removal for user $userSID : $_" -ForegroundColor Red
    } finally {
        # Unload the hive to prevent any locked registry files
        UnloadUserHive -Username $userSID
    }
}

Write-Host "Classic Teams removal process completed." -ForegroundColor Cyan

Stop-Transcript