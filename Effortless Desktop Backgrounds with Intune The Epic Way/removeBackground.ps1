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
$LogPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RemoveWallpaper.log"
$WallpaperDirectory = "C:\Temp\IntuneWallpaper"
$WallpaperPath = "$WallpaperDirectory\CorporateWallpaper.jpg"
$RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"

# Start logging
Start-Transcript -Path $LogPath -Append
LogMessage "Wallpaper removal script execution started."

try {
    # Remove the wallpaper file if it exists
    if (Test-Path -Path $WallpaperPath) {
        Remove-Item -Path $WallpaperPath -Force
        LogMessage "Wallpaper file removed: $WallpaperPath"
    } else {
        LogMessage "Wallpaper file not found at: $WallpaperPath"
    }

    # Optionally remove the wallpaper directory if empty
    if ((Test-Path $WallpaperDirectory) -and ((Get-ChildItem -Path $WallpaperDirectory).Count -eq 0)) {
        Remove-Item -Path $WallpaperDirectory -Force
        LogMessage "Wallpaper directory removed: $WallpaperDirectory"
    }

    # Remove registry values if they exist
    if (Test-Path $RegKeyPath) {
        $properties = Get-ItemProperty -Path $RegKeyPath
        if ($properties.DesktopImagePath -or $properties.DesktopImageStatus) {
            Remove-ItemProperty -Path $RegKeyPath -Name "DesktopImagePath" -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $RegKeyPath -Name "DesktopImageStatus" -ErrorAction SilentlyContinue
            LogMessage "Registry values removed from: $RegKeyPath"
        } else {
            LogMessage "No wallpaper-related registry values found to remove."
        }
    } else {
        LogMessage "Registry key not found: $RegKeyPath"
    }

    # Refresh the desktop to clear the wallpaper
    # THIS PART does not work when the script is executed at system context, but I leave it here for any future references
    #     LogMessage "Refreshing desktop to clear wallpaper."
    #     Add-Type @"
    #     using System;
    #     using System.Runtime.InteropServices;
    #     public class Wallpaper {
    #         [DllImport("user32.dll", CharSet = CharSet.Auto)]
    #         public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
    #     }
    # "@
    #     [Wallpaper]::SystemParametersInfo(0x0014, 0, "", 0x0001)
    #     LogMessage "Desktop background cleared."

} catch {
    LogMessage "An error occurred during wallpaper removal: $_"
} finally {
    Stop-Transcript
    LogMessage "Script execution completed."
}
