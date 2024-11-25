# Initialize a variable for the log file location
$LogFilePath = "C:\Logs\ApplicationDetection.log"

# Check if the log file exists, and if so, delete it
if (Test-Path -Path $LogFilePath) {
    try {
        Remove-Item -Path $LogFilePath -Force -ErrorAction Stop
    } catch {
        Write-Error "Failed to delete existing log file. Error: $_"
        exit 1
    }
}

# Start transcribing to log the process
try {
    Start-Transcript -Path $LogFilePath -Append -ErrorAction Stop
} catch {
    Write-Error "Failed to start logging. Error: $_"
    exit 1
}

# Initialize the variable for the application's display name
$AppDisplayName = "your app name goes here"

# Boolean variable for version check
$CheckVersion = $false # Set to $false if version check is not required
$TargetVersion = [System.Version]"1.0.0.0"  # Define the target version as a System.Version object

# Function to parse registry for application details
function Get-InstalledAppDetails {
    param (
        [string]$DisplayName,
        [bool]$CheckVersion = $false,
        [System.Version]$TargetVersion = $null
    )

    # Define registry paths for both 32-bit and 64-bit applications
    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $AppDetails = @()
    foreach ($Path in $RegistryPaths) {
        try {
            # Get all subkeys under the registry path
            $SubKeys = Get-ChildItem -Path $Path -ErrorAction Stop
            foreach ($Key in $SubKeys) {
                $AppInfo = Get-ItemProperty -Path $Key.PSPath -ErrorAction Stop
                if ($AppInfo.DisplayName -like "*$DisplayName*") {
                    $AppDetails += [PSCustomObject]@{
                        DisplayName    = $AppInfo.DisplayName
                        Version        = $AppInfo.DisplayVersion
                        UninstallCmd   = $AppInfo.UninstallString
                        Publisher      = $AppInfo.Publisher
                        MSIProductCode = $AppInfo.PSChildName
                    }
                }
            }
        } catch {
            Write-Warning "Failed to query registry path: $Path. Error: $_"
        }
    }
    return $AppDetails
}

# Function to check MSIX and AppX packages
function Get-AppXPackageDetails {
    param (
        [string]$DisplayName
    )

    $AppXDetails = @()
    try {
        $Packages = Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like "*$DisplayName*" }
        foreach ($Package in $Packages) {
            $AppXDetails += [PSCustomObject]@{
                DisplayName = $Package.Name
                Version     = $Package.Version
                Publisher   = $Package.Publisher
                InstallPath = $Package.InstallLocation
            }
        }
    } catch {
        Write-Warning "Failed to query AppX packages. Error: $_"
    }
    return $AppXDetails
}

# Main logic for detection
try {
    $AppFound = $false
    $RegistryApps = Get-InstalledAppDetails -DisplayName $AppDisplayName -CheckVersion $CheckVersion -TargetVersion $TargetVersion
    $AppXApps = Get-AppXPackageDetails -DisplayName $AppDisplayName

    if ($RegistryApps -or $AppXApps) {
        $AppFound = $true
        Write-Output "Application found. Details:"
        $RegistryApps | ForEach-Object { Write-Output $_ }
        $AppXApps | ForEach-Object { Write-Output $_ }

        if ($CheckVersion) {
            foreach ($App in $RegistryApps) {
                # Cast the version to System.Version for accurate comparison
                $InstalledVersion = [System.Version]$App.Version
                if ($InstalledVersion -eq $TargetVersion) {
                    Write-Output "Version check passed for Registry App: $($App.DisplayName)"
                } else {
                    Write-Output "Version mismatch for Registry App: $($App.DisplayName). Expected: $TargetVersion, Found: $InstalledVersion"
                }
            }

            foreach ($App in $AppXApps) {
                # Cast the version to System.Version for accurate comparison
                $InstalledVersion = [System.Version]$App.Version
                if ($InstalledVersion -eq $TargetVersion) {
                    Write-Output "Version check passed for AppX App: $($App.DisplayName)"
                } else {
                    Write-Output "Version mismatch for AppX App: $($App.DisplayName). Expected: $TargetVersion, Found: $InstalledVersion"
                }
            }
        }
    } else {
        Write-Output "Application not found."
    }
} catch {
    Write-Error "An unexpected error occurred during the detection process. Error: $_"
} finally {
    # Stop the transcription/logging process
    try {
        Stop-Transcript -ErrorAction Stop
    } catch {
        Write-Error "Failed to stop logging. Error: $_"
    }
}

# Return the detection result
return $AppFound
