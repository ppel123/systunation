# Start transcript for logging
Start-Transcript -Path "$env:ProgramData\IntuneLogs\DiskSpaceRemediation.log" -Append

Write-Host "Starting disk space remediation script..."

try {
    # Get all fixed drives with less than 10 GB free space
    $lowSpaceDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 -and ($_.FreeSpace / 1GB) -lt 10 }
    
    Write-Host "Found $($lowSpaceDrives.Count) drives with less than 10 GB free space."

    if ($lowSpaceDrives.Count -gt 0) {
        # Prepare the message for the toast notification
        $driveList = $lowSpaceDrives | ForEach-Object { "$($_.DeviceID) ($('{0:N2}' -f ($_.FreeSpace / 1GB)) GB free)" }
        $message = "The following drives have less than 10 GB of free space:`n" + ($driveList -join "`n") + "`n`nPlease delete unnecessary files to free up space."

        Write-Host "Preparing toast notification with message: $message"

        # Load necessary assemblies for toast notifications
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        # Prepare the toast notification XML
        $toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
        $toastXml.LoadXml(@"
        <toast>
            <visual>
                <binding template="ToastText02">
                    <text id="1">Low Disk Space Warning</text>
                    <text id="2">Your computer's storage is running low. Please delete old or unused files to free up space. This will help keep your system running smoothly. If you need assistance, contact the IT helpdesk.</text>
                </binding>
            </visual>
        </toast>
"@)

        # Create and show the toast notification
        $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Disk Space Alert").Show($toast)

        Write-Host "Toast notification sent to user."

        # Enable Storage Sense
        Write-Host "Enabling Storage Sense..."
        if (Get-Command "Enable-StorageSense" -ErrorAction SilentlyContinue) {
            Enable-StorageSense
            Write-Host "Storage Sense enabled successfully."
        } else {
            Write-Host "Enable-StorageSense command not available. Setting registry key instead."
            New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 1 -PropertyType DWORD -Force
        }

        Write-Host "Remediation actions completed."
    } else {
        Write-Host "No drives with less than 10 GB free space found. This is unexpected as the detection script triggered remediation."
    }

    Exit 0
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Host "Error occurred: $errorMessage"
    Write-Error $errorMessage
    Exit 1
}
finally {
    Stop-Transcript
}