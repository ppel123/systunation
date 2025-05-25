# Detection Script: Check if a full restart has occurred in the last 7 days

# Define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RestartDetectionLog.txt"

Start-Transcript -Path $LogFilePath

# Function to write to log file
function Write-Log {
    param ([string]$message)
    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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

    if ($daysSinceRestart -lt 7) {
        Write-Log "Device restarted within the last 7 days. Days since restart: $daysSinceRestart"
        exit 0 # No remediation needed
        Stop-Transcript
        Write-Host "Device restarted within the last 7 days. Days since restart: $daysSinceRestart"
    } else {
        Write-Log "Device not restarted in the last 7 days. Remediation required."
        exit 1 # Remediation required
        Stop-Transcript
        Write-Host "Device not restarted in the last 7 days. Remediation required."
    }
} catch {
    Write-Log "Error during restart check: $_"
    exit 1 # Remediation required on error
    Stop-Transcript
    Write-Host "Error during restart check: $_"
}