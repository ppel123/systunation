# Start transcript for logging
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\WebLinkRemediation.log"
Start-Transcript -Path $LogPath -Append

function Create-TempDirectory {
    # Check if the directory exists
    if (!(Test-Path -Path "C:\Temp" -PathType Container)) {
        # Create the directory
        New-Item -Path "C:\Temp" -ItemType Directory | Out-Null
        Write-Host "Directory 'C:\Temp' created."
    } else {
        Write-Host "Directory 'C:\Temp' already exists."
    }
}

function Create-WebLinkShortcut {
    param (
        [string]$ShortcutPath,
        [string]$TargetURL,
        [string]$IconBase64
    )
    Write-Output "Creating web link shortcut..."

    # Create temporary icon file
    $iconPath = "C:\Temp\temp_icon.ico"
    [byte[]]$iconBytes = [Convert]::FromBase64String($IconBase64)
    [System.IO.File]::WriteAllBytes($iconPath, $iconBytes)

    # Start-BitsTransfer -Source $iconPath -Description $iconPath

    # Create shortcut
    $WShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
    $Shortcut.Arguments = $TargetURL
    $Shortcut.IconLocation = $iconPath
    $Shortcut.Save()

    Write-Output "Web link shortcut created successfully"
}

try {
    Write-Output "Starting web link remediation script"

    Create-TempDirectory

    # Define shortcut details
    $ShortcutName = "Google Search"
    $TargetURL = "https://www.google.com"
    $ShortcutPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("CommonDesktopDirectory"), "$ShortcutName.lnk")

    # Base64 encoded icon (replace this with your actual Base64 string)
    $IconBase64 = "YOUR_BASE_64_STRING_HERE"

    Write-Output "Checking if web link shortcut already exists at: $ShortcutPath"

    # Check if the shortcut already exists
    if (Test-Path $ShortcutPath) {
        Write-Output "Web link shortcut already exists. No action taken."
        exit 0  # Exit with success code
    }

    # Create the web link shortcut
    Create-WebLinkShortcut -ShortcutPath $ShortcutPath -TargetURL $TargetURL -IconBase64 $IconBase64

    # Output success message
    Write-Output "Web link shortcut created successfully at: $ShortcutPath"
    exit 0  # Exit with success code
} catch {
    # Catch any unexpected errors and output them
    Write-Error "An error occurred during remediation: $_"
    exit 1  # Exit with error code
} finally {
    Stop-Transcript
}