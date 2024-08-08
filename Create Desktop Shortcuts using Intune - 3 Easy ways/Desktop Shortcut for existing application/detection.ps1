# Start transcript for logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\ShortcutDetection.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Host "Starting shortcut detection script"

    # Define parameters
    $ShortcutName = "OneDrive"
    $TargetPath = "C:\Program Files\Microsoft OneDrive\OneDrive.exe"
    $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$ShortcutName.lnk")

    Write-Host "Checking if shortcut exists at: $ShortcutPath"

    # Check if the shortcut already exists
    if (Test-Path $ShortcutPath) {
        Write-Host "Shortcut already exists. No remediation needed."
        exit 0  # Exit with success code, no remediation needed
    } else {
        Write-Host "Shortcut does not exist. Remediation needed."
        exit 1  # Exit with error code, remediation needed
    }
} catch {
    Write-Error "An error occurred during detection: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}