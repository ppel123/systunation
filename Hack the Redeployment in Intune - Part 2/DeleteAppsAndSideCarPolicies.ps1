# Define the registry paths
$baseKey = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps"
$timeKeyPath = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32AppSettings\LastEvaluationCheckInTimeUTC"

$executionKey = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Execution"
$reportsKey = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\Scripts\Reports"
$statusServiceReportsKey = "HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\SideCarPolicies\StatusServiceReports"

# Define the log file paths
$logFilePathScript = "C:\Temp\logs\instantsync.log"

# Function to ensure the log directory exists
function EnsureLogDirectoryExists {
    param (
        [string]$logFilePath
    )
    $logDir = [System.IO.Path]::GetDirectoryName($logFilePath)
    if (-Not (Test-Path -Path $logDir)) {
        Write-Host "Log directory does not exist. Creating: $logDir" -ForegroundColor Yellow
        try {
            New-Item -Path $logDir -ItemType Directory -Force
            Write-Host "Log directory created successfully." -ForegroundColor Green
        } catch {
            Write-Error "Failed to create log directory: $_"
            exit 1
        }
    }
}

# Function to iterate over subkeys and delete them based on specified conditions
function IterateAndDeleteSubKeys {
    param (
        [string]$key
    )

    Write-Host "Checking key: $key" -ForegroundColor Yellow
    Write-Output "Checking key: $key"
    
    try {
        $subKeys = Get-ChildItem -Path $key -ErrorAction Stop
    } catch {
        Write-Error "Failed to get subkeys for $key : $_"
        return
    }

    foreach ($subKey in $subKeys) {
        $name = $subKey.PSChildName
        Write-Host "SubKey: $name" -ForegroundColor Cyan
        Write-Output "SubKey: $name"

        try {
            if ($name -eq "OperationalState" -or $name -eq "Reporting") {
                Write-Host "Found $name, iterating and deleting subkeys:" -ForegroundColor Green
                Write-Output "Found $name, iterating and deleting subkeys:"
                $guidKeys = Get-ChildItem -Path $subKey.PSPath -ErrorAction Stop
                foreach ($guidKey in $guidKeys) {
                    $guid = $guidKey.PSChildName
                    if ($guid -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                        Write-Host "Deleting subkeys under GUID: $guid" -ForegroundColor Red
                        Write-Output "Deleting subkeys under GUID: $guid"
                        try {
                            Remove-Item -Path "$($guidKey.PSPath)\*" -Recurse -Force -ErrorAction Stop
                            Write-Host "Successfully deleted subkeys under GUID: $guid" -ForegroundColor Green
                            Write-Output "Successfully deleted subkeys under GUID: $guid"
                        } catch {
                            Write-Error "Failed to delete subkeys under GUID: $guid : $_"
                        }
                    }
                }
            } elseif ($name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                Write-Host "Found GUID-like key: $name, iterating and deleting subkeys except GRS:" -ForegroundColor Green
                Write-Output "Found GUID-like key: $name, iterating and deleting subkeys except GRS:"
                $subSubKeys = Get-ChildItem -Path $subKey.PSPath -ErrorAction Stop
                foreach ($subSubKey in $subSubKeys) {
                    $subName = $subSubKey.PSChildName
                    if ($subName -ne "GRS") {
                        Write-Host "Deleting subkey: $subName" -ForegroundColor Red
                        Write-Output "Deleting subkey: $subName"
                        try {
                            Remove-Item -Path "$($subSubKey.PSPath)" -Recurse -Force -ErrorAction Stop
                            Write-Host "Successfully deleted subkey: $subName" -ForegroundColor Green
                            Write-Output "Successfully deleted subkey: $subName"
                        } catch {
                            Write-Error "Failed to delete subkey: $subName : $_"
                        }
                    } elseif ($subName -eq "GRS") {
                        Write-Host "Found GRS, iterating and deleting all subkeys:" -ForegroundColor Green
                        Write-Output "Found GRS, iterating and deleting all subkeys:"
                        $grsSubKeys = Get-ChildItem -Path $subSubKey.PSPath -ErrorAction Stop
                        foreach ($grsSubKey in $grsSubKeys) {
                            $grsName = $grsSubKey.PSChildName
                            Write-Host "Deleting subkey under GRS: $grsName" -ForegroundColor Red
                            Write-Output "Deleting subkey under GRS: $grsName"
                            try {
                                Remove-Item -Path "$($grsSubKey.PSPath)" -Recurse -Force -ErrorAction Stop
                                Write-Host "Successfully deleted subkey under GRS: $grsName" -ForegroundColor Green
                                Write-Output "Successfully deleted subkey under GRS: $grsName"
                            } catch {
                                Write-Error "Failed to delete subkey under GRS: $grsName : $_"
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Error "An error occurred while processing $name : $_"
        }
    }
}

# Function to iterate over subkeys and delete them under GUID subkeys
function IterateAndDeleteGUIDSubKeys {
    param (
        [string]$key
    )

    Write-Host "Checking key: $key" -ForegroundColor Yellow
    Write-Output "Checking key: $key"
    
    try {
        $subKeys = Get-ChildItem -Path $key -ErrorAction Stop
    } catch {
        Write-Error "Failed to get subkeys for $key : $_"
        return
    }

    foreach ($subKey in $subKeys) {
        $name = $subKey.PSChildName
        Write-Host "SubKey: $name" -ForegroundColor Cyan
        Write-Output "SubKey: $name"
        
        try {
            if ($name -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                Write-Host "Found GUID-like key: $name, deleting all subkeys:" -ForegroundColor Green
                Write-Output "Found GUID-like key: $name, deleting all subkeys:"
                try {
                    Remove-Item -Path "$($subKey.PSPath)\*" -Recurse -Force -ErrorAction Stop
                    Write-Host "Successfully deleted subkeys under GUID: $name" -ForegroundColor Green
                    Write-Output "Successfully deleted subkeys under GUID: $name"
                } catch {
                    Write-Error "Failed to delete subkeys under GUID: $name : $_"
                }
            }
        } catch {
            Write-Error "An error occurred while processing $name : $_"
        }
    }
}

# Function to update the "Time" value under the specified registry key
function UpdateLastEvaluationCheckInTimeUTC {
    Write-Host "Checking for registry key: $timeKeyPath" -ForegroundColor Yellow
    Write-Output "Checking for registry key: $timeKeyPath"
    
    try {
        if (Test-Path -Path $timeKeyPath) {
            Write-Host "Registry key found: $timeKeyPath" -ForegroundColor Green
            Write-Output "Registry key found: $timeKeyPath"

            $timeValue = Get-ItemProperty -Path $timeKeyPath -Name "Time" -ErrorAction Stop
            Write-Host "Current Time value: $($timeValue.Time)" -ForegroundColor Cyan
            Write-Output "Current Time value: $($timeValue.Time)"

            $currentDate = Get-Date
            $newDate = $currentDate.AddDays(-2)
            $newTimeValue = $newDate.ToString("MM/dd/yyyy HH:mm:ss")

            Set-ItemProperty -Path $timeKeyPath -Name "Time" -Value $newTimeValue -ErrorAction Stop
            Write-Host "Time value updated to: $newTimeValue" -ForegroundColor Green
            Write-Output "Time value updated to: $newTimeValue"
        } else {
            Write-Warning "Registry key not found: $timeKeyPath"
            Write-Output "Registry key not found: $timeKeyPath"
        }
    } catch {
        Write-Error "An error occurred while updating the registry key: $_"
    }
}

# Ensure the log directories exist
EnsureLogDirectoryExists -logFilePath $logFilePathScript

# Start logging
Start-Transcript -Path $logFilePathScript -Append

# Start the iteration from the base key
IterateAndDeleteSubKeys $baseKey

# Update the registry value for LastEvaluationCheckInTimeUTC
UpdateLastEvaluationCheckInTimeUTC

# Begin processing registry keys
Write-Host "Starting registry key cleanup..." -ForegroundColor Yellow
Write-Output "Starting registry key cleanup..."

# Process the Execution key
try {
    if (Test-Path -Path $executionKey) {
        Write-Host "Processing Execution key: $executionKey" -ForegroundColor Yellow
        Write-Output "Processing Execution key: $executionKey"
        IterateAndDeleteGUIDSubKeys $executionKey
    } else {
        Write-Warning "Execution key not found: $executionKey"
        Write-Output "Execution key not found: $executionKey"
    }
} catch {
    Write-Error "An error occurred during Execution key processing: $_"
}

# Process the Reports key
try {
    if (Test-Path -Path $reportsKey) {
        Write-Host "Processing Reports key: $reportsKey" -ForegroundColor Yellow
        Write-Output "Processing Reports key: $reportsKey"
        IterateAndDeleteGUIDSubKeys $reportsKey
    } else {
        Write-Warning "Reports key not found: $reportsKey"
        Write-Output "Reports key not found: $reportsKey"
    }
} catch {
    Write-Error "An error occurred during Reports key processing: $_"
}

# Process the StatusServiceReports key
try {
    if (Test-Path -Path $statusServiceReportsKey) {
        Write-Host "Processing StatusServiceReports key: $statusServiceReportsKey" -ForegroundColor Yellow
        Write-Output "Processing StatusServiceReports key: $statusServiceReportsKey"
        IterateAndDeleteGUIDSubKeys $statusServiceReportsKey
    } else {
        Write-Warning "StatusServiceReports key not found: $statusServiceReportsKey"
        Write-Output "StatusServiceReports key not found: $statusServiceReportsKey"
    }
} catch {
    Write-Error "An error occurred during StatusServiceReports key processing: $_"
}

# Define the task name and service name
$intuneServiceName = 'IntuneManagementExtension'


# Function to sync Intune devices by running the PushLaunch scheduled task
function SyncIntuneDevices {
    try {
        Write-Host "Getting Enrollment ID"
        $EnrollmentID = Get-ScheduledTask | Where-Object { $_.TaskPath -like "*Microsoft*Windows*EnterpriseMgmt\*" } | Select-Object -ExpandProperty TaskPath -Unique | Where-Object { $_ -like "*-*-*" } | Split-Path -Leaf
        Write-Host "Enrollment ID: $EnrollmentID"
        Write-Host "Starting Syncing."
        Start-Process -FilePath "C:\Windows\system32\deviceenroller.exe" -Wait -ArgumentList "/o $EnrollmentID /c /b"
    } catch {
        Write-Error "Failed to start scheduled task '$taskName': $_"
    }
}

# Function to restart the Intune Management Extension service
function RestartIntuneService {
    try {
        # Get the service object
        $service = Get-Service -Name $intuneServiceName -ErrorAction Stop

        # Check the service status and restart if necessary
        if ($service.Status -eq 'Running') {
            Write-Host "Stopping service: $intuneServiceName" -ForegroundColor Yellow
            Stop-Service -Name $intuneServiceName -Force -ErrorAction Stop
            Write-Host "Service '$intuneServiceName' stopped." -ForegroundColor Yellow
        }

        Write-Host "Starting service: $intuneServiceName" -ForegroundColor Green
        Start-Service -Name $intuneServiceName -ErrorAction Stop
        Write-Host "Service '$intuneServiceName' started successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to restart service '$intuneServiceName': $_"
    }
}

# Run the functions
RestartIntuneService
SyncIntuneDevices

# End logging
Stop-Transcript

Write-Host "Registry key cleanup completed." -ForegroundColor Green
Write-Output "Registry key cleanup completed."
