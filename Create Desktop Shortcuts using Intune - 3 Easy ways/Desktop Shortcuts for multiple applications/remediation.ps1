# Start transcript for logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\MultipleShortcutsRemediation.log"
Start-Transcript -Path $LogPath -Append

# Function to create shortcut
function Create-Shortcut {
    param (
        [string]$ShortcutPath,
        [string]$TargetPath
    )
    Write-Output "Creating shortcut: $ShortcutPath"
    $WShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $TargetPath
    $Shortcut.IconLocation = "$TargetPath,0"
    $Shortcut.Save()
    Write-Output "Shortcut created successfully"
}

try {
    Write-Output "Starting shortcuts remediation script"

    # Define shortcuts
    $Shortcuts = @(
        @{
            Name = "OneDrive"
            TargetPath = "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
        },
        @{
            Name = "Edge"
            TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        }
    )

    $RemediationPerformed = $false

    foreach ($Shortcut in $Shortcuts) {
        $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$($Shortcut.Name).lnk")
        
        Write-Output "Checking shortcut: $($Shortcut.Name)"

        if (-not (Test-Path $ShortcutPath)) {
            Write-Output "Shortcut does not exist. Attempting to create."

            if (Test-Path $Shortcut.TargetPath) {
                Create-Shortcut -ShortcutPath $ShortcutPath -TargetPath $Shortcut.TargetPath
                $RemediationPerformed = $true
            } else {
                Write-Warning "Target path does not exist: $($Shortcut.TargetPath). Skipping shortcut creation."
            }
        } else {
            Write-Output "Shortcut already exists: $($Shortcut.Name)"
        }
    }

    if ($RemediationPerformed) {
        Write-Output "Remediation actions performed."
        exit 0  # Exit with success code
    } else {
        Write-Output "No remediation actions were necessary."
        exit 0  # Exit with success code
    }
} catch {
    Write-Error "An error occurred during remediation: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}