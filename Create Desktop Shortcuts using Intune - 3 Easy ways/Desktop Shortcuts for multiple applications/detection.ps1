# Start transcript for logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\MultipleShortcutsDetection.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Output "Starting shortcuts detection script"

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

    $RemediationNeeded = $false

    foreach ($Shortcut in $Shortcuts) {
        $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$($Shortcut.Name).lnk")
        
        Write-Output "Checking if shortcut exists at: $ShortcutPath"

        if (-not (Test-Path $ShortcutPath)) {
            Write-Output "Shortcut does not exist: $($Shortcut.Name)"
            $RemediationNeeded = $true
        } else {
            Write-Output "Shortcut exists: $($Shortcut.Name)"
        }
    }

    if ($RemediationNeeded) {
        Write-Output "At least one shortcut is missing. Remediation needed."
        exit 1  # Exit with error code, remediation needed
    } else {
        Write-Output "All shortcuts exist. No remediation needed."
        exit 0  # Exit with success code, no remediation needed
    }
} catch {
    Write-Error "An error occurred during detection: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}