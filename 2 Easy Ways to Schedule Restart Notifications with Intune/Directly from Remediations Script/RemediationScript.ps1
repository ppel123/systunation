# Remediation Script: Show a toast notification to prompt a restart

# Define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RestartRemediationLog.txt"
if (-not (Test-Path -Path $LogFilePath)) {
    if (-not (Test-Path -Path "C:\Temp")) {
        New-Item -ItemType Directory -Path "C:\Temp" -ErrorAction Stop
    }
    $LogFilePath = "C:\Temp\RestartRemediationLog.txt"
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

# Function to show toast notification
function Show-ToastNotification {
    param ([string]$message)
    try {
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(10000, "Restart Reminder", $message, [System.Windows.Forms.ToolTipIcon]::Info)
        Write-Log "Toast notification shown."
    } catch {
        Write-Log "Error showing toast notification: $_"
    }
}

# Write script start to log
Write-Log "Restart Remediation Script Started"

# Show notification
Show-ToastNotification -message "You have not restarted your device in the last 2 weeks. Please restart for better performance."

# Write script end to log
Write-Log "Restart Remediation Script Ended"
