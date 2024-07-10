# Start transcript for logging
Start-Transcript -Path "$env:ProgramData\IntuneLogs\DiskSpaceDetection.log" -Append

Write-Host "Starting disk space detection script..."

try {
    # Get all fixed drives
    $drives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    
    Write-Host "Found $($drives.Count) fixed drives."

    $lowSpaceDrives = @()

    foreach ($drive in $drives) {
        $freeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
        Write-Host "Drive $($drive.DeviceID) has $freeSpaceGB GB free space."
        
        if ($freeSpaceGB -lt 10) {
            $lowSpaceDrives += $drive.DeviceID
            Write-Host "Drive $($drive.DeviceID) has less than 10 GB free space. Adding to low space drives list."
        }
    }

    if ($lowSpaceDrives.Count -gt 0) {
        Write-Host "Detected $($lowSpaceDrives.Count) drives with less than 10 GB free space."
        Write-Host "Low space drives: $($lowSpaceDrives -join ', ')"
        Write-Output "Remediation needed"
        Exit 1
    } else {
        Write-Host "All drives have more than 10 GB free space."
        Write-Output "No remediation needed"
        Exit 0
    }
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