# Initialize the variable for collecting log messages
$script:intuneOutput = ""

# Define the LogMessage function
function LogMessage {
    param (
        [string]$message
    )
    Write-Host $message
    $script:intuneOutput += $message + "`n"
}

# Define variables
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\DeployWallpaper.log"
$WallpaperDirectory = "C:\Temp\IntuneWallpaper"
$WallpaperPath = "$WallpaperDirectory\CorporateWallpaper.jpg"
$RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$Base64Image = "YOUR BASE 64 STRING"

# Start logging
Start-Transcript -Path $LogPath -Append
LogMessage "Script execution started."

try {
    # Ensure the directory exists
    if (-not (Test-Path -Path $WallpaperDirectory)) {
        New-Item -Path $WallpaperDirectory -ItemType Directory -ErrorAction Stop -Force
        LogMessage "Created directory: $WallpaperDirectory"
    } else {
        LogMessage "Directory already exists: $WallpaperDirectory"
    }

    # Decode the Base64 string to bytes
    LogMessage "Decoding Base64 string to byte array."
    $ImageBytes = [Convert]::FromBase64String($Base64Image)

    # Write the bytes to create the image file
    [System.IO.File]::WriteAllBytes($WallpaperPath, $ImageBytes)
    LogMessage "Wallpaper image saved to: $WallpaperPath"

    # Ensure the registry key exists
    if (-not (Test-Path $RegKeyPath)) {
        New-Item -Path $RegKeyPath -ErrorAction Stop -Force | Out-Null
        LogMessage "Created registry key: $RegKeyPath"
    } else {
        LogMessage "Registry key already exists: $RegKeyPath"
    }

    # Set the registry values
    New-ItemProperty -Path $RegKeyPath -Name "DesktopImagePath" -Value $WallpaperPath -PropertyType String -ErrorAction Stop -Force | Out-Null
    New-ItemProperty -Path $RegKeyPath -Name "DesktopImageStatus" -Value 1 -PropertyType DWord -ErrorAction Stop -Force | Out-Null
    LogMessage "Updated registry with new wallpaper path and status."

    # Refresh the desktop background using SystemParametersInfo
    # THIS PART does not work when the script is executed at system context, but I leave it here for any future references
    #     LogMessage "Attempting to refresh desktop wallpaper."
    #     Add-Type @"
    #     using System;
    #     using System.Runtime.InteropServices;
    #     public class Wallpaper {
    #         [DllImport("user32.dll", CharSet = CharSet.Auto)]
    #         public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    #     }
    # "@
    #     [Wallpaper]::SystemParametersInfo(0x0014, 0, $WallpaperPath, 0x0001)
    #     LogMessage "Desktop background refreshed."

} catch {
    LogMessage "An error occurred during execution: $_"
} finally {
    Stop-Transcript
    LogMessage "Script execution completed."
}