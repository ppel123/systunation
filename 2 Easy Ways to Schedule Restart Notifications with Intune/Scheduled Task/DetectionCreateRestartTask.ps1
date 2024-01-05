# PowerShell Script for Intune Detection of Scheduled Task

# Check and define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TaskDetectionLog.txt"
if (-not (Test-Path -Path $LogFilePath)) {
    Write-Host "Log file path does not exist. Checking C:\Temp..."
    $LogFilePath = "C:\Temp\TaskDetectionLog.txt"
    if (-not (Test-Path -Path "C:\Temp")) {
        Write-Host "C:\Temp does not exist. Creating..."
        New-Item -ItemType Directory -Path "C:\Temp" -ErrorAction Stop
    }
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
Write-Log "Detection Script Started"

# Task name to check
$taskName = "CheckRestartNotification"

# Check if the scheduled task exists
try {
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop

    if ($taskExists) {
        Write-Log "Task '$taskName' found. No remediation required."
        exit 0 # Exit code 0 for success
    } else {
        Write-Log "Task '$taskName' not found. Remediation required."
        exit 1 # Exit code 1 for failure
    }
} catch {
    Write-Log "Error checking task: $_"
    exit 1 # Exit code 1 for failure
}

# Write script end to log
Write-Log "Detection Script Ended"
