# Remediation Script: Show a toast notification then force restart

# Define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RestartRemediationLog.txt"

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

# Function to show toast notification
function Show-ToastNotification {
    param (
        [int]$CountdownMinutes = 5
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.Visible = $true

        $message = "Mandatory restart in 5 minutes.`n" +
                   "Please save any open work now."

        # Show balloon tip for 30 seconds (30000 ms)
        $notifyIcon.ShowBalloonTip(30000, "Restart Reminder", $message, [System.Windows.Forms.ToolTipIcon]::Info)
        Write-Log "Toast notification shown with message: $message"

        # Optionally keep the icon visible for the toast duration
        Start-Sleep -Seconds 30
        $notifyIcon.Dispose()
    } catch {
        Write-Log "Error showing toast notification: $_"
    }
}

# Write script start to log
Write-Log "Restart Remediation Script Started"

# Show notification: device will restart in 5 minutes
Show-ToastNotification -CountdownMinutes 5

# Wait for 5 minutes before forcing reboot
Start-Sleep -Seconds 300
Write-Log "Countdown complete, initiating restart"
Stop-Transcript
Write-Host "Countdown complete, initiating restart"

# Force a restart
try {
    Restart-Computer -Force
} catch {
    Write-Log "Restart-Computer command failed: $_. Scheduling via shutdown.exe"
    shutdown.exe /r /t 60 /f
}