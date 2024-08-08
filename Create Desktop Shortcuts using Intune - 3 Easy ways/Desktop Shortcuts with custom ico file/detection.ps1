# Start transcript for logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WebLinkDetection.log"
Start-Transcript -Path $LogPath -Append

try {
    Write-Output "Starting web link detection script"

    # Define the shortcut details
    $ShortcutName = "Google Search"
    $TargetURL = "https://www.google.com"
    $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$ShortcutName.lnk")

    Write-Output "Checking if web link shortcut exists at: $ShortcutPath"

    # Check if the shortcut already exists
    if (Test-Path $ShortcutPath) {
        Write-Output "Web link shortcut already exists. No remediation needed."
        exit 0  # Exit with success code, no remediation needed
    } else {
        Write-Output "Web link shortcut does not exist. Remediation needed."
        exit 1  # Exit with error code, remediation needed
    }
} catch {
    Write-Error "An error occurred during detection: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}