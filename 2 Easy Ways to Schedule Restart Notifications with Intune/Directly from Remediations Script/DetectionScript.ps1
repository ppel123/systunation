# Detection Script: Check if a full restart has occurred in the last 2 weeks

# Define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RestartDetectionLog.txt"
if (-not (Test-Path -Path $LogFilePath)) {
    if (-not (Test-Path -Path "C:\Temp")) {
        New-Item -ItemType Directory -Path "C:\Temp" -ErrorAction Stop
    }
    $LogFilePath = "C:\Temp\RestartDetectionLog.txt"
    if (-not (Test-Path -Path $LogFilePath)) {
        New-Item -ItemType File -Path $LogFilePath -ErrorAction Stop
    }
}

# Function to write to log file
function Write-Log {
    param ([string]$message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "$timestamp - $message" | Out-File -FilePath $LogFilePath -Append
        Write-Host "$timestamp - $message"
    } catch {
        Write-Host "Error writing to log: $_"
    }
}

# Write script start to log
Write-Log "Restart Detection Script Started"

# Check last restart time
try {
    $lastBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $currentTime = Get-Date
    $daysSinceRestart = ($currentTime - $lastBootTime).Days

    if ($daysSinceRestart -lt 14) {
        Write-Log "Device restarted within the last 2 weeks. Days since restart: $daysSinceRestart"
        exit 0 # No remediation needed
    } else {
        Write-Log "Device not restarted in the last 2 weeks. Remediation required."
        exit 1 # Remediation required
    }
} catch {
    Write-Log "Error during restart check: $_"
    exit 1 # Remediation required on error
}

# Write script end to log
Write-Log "Restart Detection Script Ended"
