# PowerShell Script to Schedule Restart Notification

# Add necessary Windows types for toast notifications
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;

        public static class ToastNotificationManager {
            [DllImport("user32.dll", CharSet = CharSet.Auto)]
            public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
        }
"@ -ErrorAction Stop
    Write-Host "Windows types added successfully."
} catch {
    Write-Host "Error adding Windows types: $_"
}

# Check and define log file path
$LogFilePath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\RestartNotificationLog.txt"
if (-not (Test-Path -Path $LogFilePath)) {
    Write-Host "Log file path does not exist. Checking C:\Temp..."
    $LogFilePath = "C:\Temp\RestartNotificationLog.txt"
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
Write-Log "Script Started"

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

# Function to check last restart time and show notification if needed
function Check-And-Notify {
    try {
        $lastBootUpTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
        $currentTime = Get-Date
        $daysSinceRestart = ($currentTime - $lastBootUpTime).Days

        if ($daysSinceRestart -ge 14) {
            # Show toast notification
            $toastMessage = "You haven't performed a restart for $daysSinceRestart days. For better performance, please perform a restart as soon as possible"
            Show-ToastNotification -message $toastMessage

            # Log notification
            Write-Log "Notification displayed: $toastMessage"
        } else {
            Write-Log "No restart required. Days since last restart: $daysSinceRestart"
        }
    } catch {
        Write-Log "Error in Check-And-Notify: $_"
    }
}

# Function to register the scheduled task
function Register-ScheduledTask {
    try {
        $scriptBlock = {
            Add-Type -AssemblyName System.Windows.Forms
            Check-And-Notify
        }

        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock))

        $action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument "-encodedCommand $encodedCommand" -ErrorAction Stop
        $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 2 -DaysOfWeek Monday -At 10am -ErrorAction Stop
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ErrorAction Stop

        # Register the task
        Register-ScheduledTask -TaskName "CheckRestartNotification" -Action $action -Trigger $trigger -Settings $settings -Description "Check and notify for system restart every 2 weeks" -ErrorAction Stop

        Write-Log "Scheduled task 'CheckRestartNotification' registered"
    } catch {
        Write-Log "Error registering scheduled task: $_"
    }
}

# Attempt to register the task
try {
    Register-ScheduledTask
} catch {
    Write-Log "Error encountered during task registration: $_"
}

# Write script end to log
Write-Log "Script Ended"
