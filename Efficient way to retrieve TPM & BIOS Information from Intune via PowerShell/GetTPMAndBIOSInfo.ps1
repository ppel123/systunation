<#
.SYNOPSIS
    Retrieves TPM and BIOS information from Intune-managed Windows devices.

.DESCRIPTION
    This script connects to Microsoft Graph API to fetch hardware information
    (TPM version, BIOS version, etc.) from corporate-managed Windows devices.
    Supports both PowerShell 5.1 (sequential) and PowerShell 7+ (parallel processing).

.NOTES
    Requires: Microsoft.Graph.DeviceManagement module
    Permissions: DeviceManagementManagedDevices.Read.All

.EXAMPLE
    .\GetTPMAndBIOSInfo.ps1
    Runs the script with default settings (batch size 20, exports to C:\Temp)

.EXAMPLE
    .\GetTPMAndBIOSInfo.ps1 -BatchSize 50 -ExportPath "D:\Reports"
    Runs with custom batch size and export location
#>

#Requires -Modules Microsoft.Graph.DeviceManagement

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Number of devices to process per batch")]
    [ValidateRange(1, 100)]
    [int]$BatchSize = 20,

    [Parameter(HelpMessage = "Directory path for CSV export")]
    [string]$ExportPath = "C:\Temp",

    [Parameter(HelpMessage = "Throttle limit for parallel processing (PS7+)")]
    [ValidateRange(1, 20)]
    [int]$ThrottleLimit = 10,

    [Parameter(HelpMessage = "Skip CSV export")]
    [switch]$NoExport
)

#region Configuration
$script:Config = @{
    GraphScopes      = @("DeviceManagementManagedDevices.Read.All")
    DeviceFilter     = "OperatingSystem eq 'Windows' and ManagedDeviceOwnerType eq 'company' and ManagementAgent eq 'mdm'"
    DeviceProperties = @(
        "Id", "DeviceName", "SerialNumber", "UserPrincipalName", "UserDisplayName",
        "Model", "Manufacturer", "ComplianceState", "IsEncrypted", 
        "LastSyncDateTime", "EnrolledDateTime", "OsVersion"
    )
    GraphBaseUri     = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"
}

$script:Statistics = @{
    TotalDevices     = 0
    ProcessedCount   = 0
    SuccessCount     = 0
    FailedCount      = 0
    StartTime        = $null
    EndTime          = $null
}
#endregion

#region Helper Functions
function Write-Log {
    <#
    .SYNOPSIS
        Writes formatted log messages to console with timestamps.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("Info", "Success", "Warning", "Error", "Debug")]
        [string]$Level = "Info",

        [Parameter()]
        [switch]$NoNewLine
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colorMap = @{
        Info    = "Cyan"
        Success = "Green"
        Warning = "Yellow"
        Error   = "Red"
        Debug   = "Gray"
    }

    $prefix = switch ($Level) {
        "Info"    { "[INFO]   " }
        "Success" { "[SUCCESS]" }
        "Warning" { "[WARNING]" }
        "Error"   { "[ERROR]  " }
        "Debug"   { "[DEBUG]  " }
    }

    $params = @{
        Object          = "[$timestamp] $prefix $Message"
        ForegroundColor = $colorMap[$Level]
        NoNewline       = $NoNewLine
    }
    Write-Host @params
}

function Connect-ToGraph {
    <#
    .SYNOPSIS
        Establishes connection to Microsoft Graph with required scopes.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Log "Connecting to Microsoft Graph..." -Level Info
        
        # Check if already connected with required scopes
        $context = Get-MgContext -ErrorAction SilentlyContinue
        
        if ($context) {
            $hasRequiredScope = $script:Config.GraphScopes | ForEach-Object {
                $context.Scopes -contains $_
            }
            
            if ($hasRequiredScope -notcontains $false) {
                Write-Log "Already connected to Microsoft Graph as: $($context.Account)" -Level Success
                return $true
            }
        }

        # Connect with required scopes
        Connect-MgGraph -Scopes $script:Config.GraphScopes -NoWelcome -ErrorAction Stop
        $context = Get-MgContext
        Write-Log "Successfully connected to Microsoft Graph as: $($context.Account)" -Level Success
        return $true
    }
    catch {
        Write-Log "Failed to connect to Microsoft Graph: $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Get-ManagedDevices {
    <#
    .SYNOPSIS
        Retrieves all corporate-managed Windows devices from Intune.
    #>
    [CmdletBinding()]
    param()

    try {
        Write-Log "Fetching managed devices from Intune..." -Level Info
        Write-Log "Filter: $($script:Config.DeviceFilter)" -Level Debug

        $selectProperties = $script:Config.DeviceProperties -join ","
        
        $devices = Get-MgDeviceManagementManagedDevice -All `
            -Filter $script:Config.DeviceFilter `
            -Property $selectProperties `
            -ErrorAction Stop

        if (-not $devices -or $devices.Count -eq 0) {
            Write-Log "No devices found matching the filter criteria." -Level Warning
            return $null
        }

        Write-Log "Found $($devices.Count) managed device(s)" -Level Success
        return $devices
    }
    catch {
        Write-Log "Failed to retrieve managed devices: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Get-DeviceHardwareInfo {
    <#
    .SYNOPSIS
        Retrieves hardware information for a single device.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Device
    )

    $deviceId = $Device.Id
    $uri = "$($script:Config.GraphBaseUri)('$deviceId')?`$select=hardwareInformation"

    try {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $hw = $response.hardwareInformation
        
        # Debug: Print all available hardware information properties
        Write-Host "`n========== Hardware Info for: $($Device.DeviceName) ==========" -ForegroundColor Magenta
        $hw.GetEnumerator() | Sort-Object Name | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value)" -ForegroundColor Gray
        }

        return [PSCustomObject]@{
            DeviceName              = $Device.DeviceName
            SerialNumber            = $Device.SerialNumber
            UserPrincipalName       = $Device.UserPrincipalName
            UserDisplayName         = $Device.UserDisplayName
            Model                   = $Device.Model
            Manufacturer            = $Device.Manufacturer
            ComplianceState         = $Device.ComplianceState
            IsEncrypted             = $Device.IsEncrypted
            LastSyncDateTime        = $Device.LastSyncDateTime
            EnrolledDateTime        = $Device.EnrolledDateTime
            OsVersion               = $Device.OsVersion
            OSBuildNumber           = $hw.osBuildNumber
            TPMVersion              = $hw.tpmVersion
            TPMSpecificationVersion = $hw.tpmSpecificationVersion
            TPMManufacturer         = $hw.tpmManufacturer
            BIOSVersion             = $hw.systemManagementBIOSVersion
            TotalStorageSpaceGB     = if ($hw.totalStorageSpace) { [Math]::Round($hw.totalStorageSpace / 1GB, 2) } else { $null }
            FreeStorageSpaceGB      = if ($hw.freeStorageSpace) { [Math]::Round($hw.freeStorageSpace / 1GB, 2) } else { $null }
            PhysicalMemoryGB        = if ($hw.physicalMemoryInBytes) { [Math]::Round($hw.physicalMemoryInBytes / 1GB, 2) } else { $null }
        }
    }
    catch {
        throw "Failed to get hardware info for device '$($Device.DeviceName)': $($_.Exception.Message)"
    }
}

function Process-DeviceBatch {
    <#
    .SYNOPSIS
        Processes a batch of devices to retrieve hardware information.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Devices,

        [Parameter()]
        [int]$ThrottleLimit = 10
    )

    $results = @()
    $isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7

    if ($isPowerShell7) {
        # PowerShell 7+ with parallel processing
        $results = $Devices | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
            # Import configuration in parallel scope
            $graphBaseUri = $using:script:Config.GraphBaseUri
            $device = $_
            
            try {
                $deviceId = $device.Id
                $uri = "$graphBaseUri('$deviceId')?`$select=hardwareInformation"
                
                $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
                $hw = $response.hardwareInformation

                [PSCustomObject]@{
                    DeviceName              = $device.DeviceName
                    SerialNumber            = $device.SerialNumber
                    UserPrincipalName       = $device.UserPrincipalName
                    UserDisplayName         = $device.UserDisplayName
                    Model                   = $device.Model
                    Manufacturer            = $device.Manufacturer
                    ComplianceState         = $device.ComplianceState
                    IsEncrypted             = $device.IsEncrypted
                    LastSyncDateTime        = $device.LastSyncDateTime
                    EnrolledDateTime        = $device.EnrolledDateTime
                    OsVersion               = $device.OsVersion
                    OSBuildNumber           = $hw.osBuildNumber
                    TPMVersion              = $hw.tpmVersion
                    TPMSpecificationVersion = $hw.tpmSpecificationVersion
                    TPMManufacturer         = $hw.tpmManufacturer
                    BIOSVersion             = $hw.systemManagementBIOSVersion
                    TotalStorageSpaceGB     = if ($hw.totalStorageSpace) { [Math]::Round($hw.totalStorageSpace / 1GB, 2) } else { $null }
                    FreeStorageSpaceGB      = if ($hw.freeStorageSpace) { [Math]::Round($hw.freeStorageSpace / 1GB, 2) } else { $null }
                    PhysicalMemoryGB        = if ($hw.physicalMemoryInBytes) { [Math]::Round($hw.physicalMemoryInBytes / 1GB, 2) } else { $null }
                    Status                  = "Success"
                    ErrorMessage            = $null
                }
            }
            catch {
                [PSCustomObject]@{
                    DeviceName              = $device.DeviceName
                    SerialNumber            = $device.SerialNumber
                    UserPrincipalName       = $device.UserPrincipalName
                    UserDisplayName         = $null
                    Model                   = $device.Model
                    Manufacturer            = $device.Manufacturer
                    ComplianceState         = $null
                    IsEncrypted             = $null
                    LastSyncDateTime        = $null
                    EnrolledDateTime        = $null
                    OsVersion               = $null
                    OSBuildNumber           = $null
                    TPMVersion              = $null
                    TPMSpecificationVersion = $null
                    TPMManufacturer         = $null
                    BIOSVersion             = $null
                    TotalStorageSpaceGB     = $null
                    FreeStorageSpaceGB      = $null
                    PhysicalMemoryGB        = $null
                    Status                  = "Failed"
                    ErrorMessage            = $_.Exception.Message
                }
            }
        }
    }
    else {
        # PowerShell 5.1 with sequential processing
        foreach ($device in $Devices) {
            try {
                $hwInfo = Get-DeviceHardwareInfo -Device $device
                $hwInfo | Add-Member -NotePropertyName "Status" -NotePropertyValue "Success"
                $hwInfo | Add-Member -NotePropertyName "ErrorMessage" -NotePropertyValue $null
                $results += $hwInfo
            }
            catch {
                $results += [PSCustomObject]@{
                    DeviceName              = $device.DeviceName
                    SerialNumber            = $device.SerialNumber
                    UserPrincipalName       = $device.UserPrincipalName
                    UserDisplayName         = $null
                    Model                   = $device.Model
                    Manufacturer            = $device.Manufacturer
                    ComplianceState         = $null
                    IsEncrypted             = $null
                    LastSyncDateTime        = $null
                    EnrolledDateTime        = $null
                    OsVersion               = $null
                    OSBuildNumber           = $null
                    TPMVersion              = $null
                    TPMSpecificationVersion = $null
                    TPMManufacturer         = $null
                    BIOSVersion             = $null
                    TotalStorageSpaceGB     = $null
                    FreeStorageSpaceGB      = $null
                    PhysicalMemoryGB        = $null
                    Status                  = "Failed"
                    ErrorMessage            = $_.Exception.Message
                }
                Write-Log "Failed to process device '$($device.DeviceName)': $($_.Exception.Message)" -Level Warning
            }
        }
    }

    return $results
}

function Export-Results {
    <#
    .SYNOPSIS
        Exports results to CSV file with timestamp.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Results,

        [Parameter(Mandatory)]
        [string]$ExportDirectory
    )

    try {
        # Ensure export directory exists
        if (-not (Test-Path -Path $ExportDirectory)) {
            New-Item -ItemType Directory -Path $ExportDirectory -Force | Out-Null
            Write-Log "Created export directory: $ExportDirectory" -Level Info
        }

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $fileName = "TPMAndBIOSInfo_$timestamp.csv"
        $fullPath = Join-Path -Path $ExportDirectory -ChildPath $fileName

        $Results | Export-Csv -Path $fullPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        
        Write-Log "Results exported to: $fullPath" -Level Success
        return $fullPath
    }
    catch {
        Write-Log "Failed to export results: $($_.Exception.Message)" -Level Error
        throw
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays execution summary with statistics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Results
    )

    $duration = $script:Statistics.EndTime - $script:Statistics.StartTime
    $successResults = $Results | Where-Object { $_.Status -eq "Success" }
    $failedResults = $Results | Where-Object { $_.Status -eq "Failed" }

    Write-Host "`n" -NoNewline
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "                    EXECUTION SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Total Devices Found:      $($script:Statistics.TotalDevices)" -ForegroundColor White
    Write-Host "  Successfully Processed:   $($successResults.Count)" -ForegroundColor Green
    Write-Host "  Failed:                   $($failedResults.Count)" -ForegroundColor $(if ($failedResults.Count -gt 0) { "Red" } else { "Green" })
    Write-Host "  Execution Time:           $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
    Write-Host "  PowerShell Version:       $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" -ForegroundColor White
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan

    # Show failed devices if any
    if ($failedResults.Count -gt 0) {
        Write-Host "`nFailed Devices:" -ForegroundColor Red
        $failedResults | ForEach-Object {
            Write-Host "  - $($_.DeviceName): $($_.ErrorMessage)" -ForegroundColor Red
        }
    }
}
#endregion

#region Main Execution
function Invoke-Main {
    <#
    .SYNOPSIS
        Main execution function orchestrating the script workflow.
    #>
    [CmdletBinding()]
    param()

    $script:Statistics.StartTime = Get-Date
    Write-Host ""
    Write-Log "Starting TPM and BIOS Information Collection Script" -Level Info
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion)" -Level Debug
    Write-Log "Batch Size: $BatchSize | Throttle Limit: $ThrottleLimit" -Level Debug

    try {
        # Step 1: Connect to Microsoft Graph
        $connected = Connect-ToGraph
        if (-not $connected) {
            throw "Unable to establish connection to Microsoft Graph."
        }

        # Step 2: Retrieve managed devices
        $devices = Get-ManagedDevices
        if (-not $devices) {
            Write-Log "No devices to process. Exiting." -Level Warning
            return
        }

        $script:Statistics.TotalDevices = $devices.Count
        $allResults = [System.Collections.ArrayList]::new()

        # Step 3: Process devices in batches
        $totalBatches = [Math]::Ceiling($devices.Count / $BatchSize)
        Write-Log "Processing $($devices.Count) device(s) in $totalBatches batch(es)..." -Level Info
        
        $isPowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
        if (-not $isPowerShell7) {
            Write-Log "PowerShell 5.1 detected - using sequential processing" -Level Warning
        } else {
            Write-Log "PowerShell 7+ detected - using parallel processing (ThrottleLimit: $ThrottleLimit)" -Level Info
        }

        for ($i = 0; $i -lt $devices.Count; $i += $BatchSize) {
            $batchNumber = [Math]::Floor($i / $BatchSize) + 1
            $batchEnd = [Math]::Min($i + $BatchSize - 1, $devices.Count - 1)
            $batch = $devices[$i..$batchEnd]

            # Handle single device case (array slicing returns single object)
            if ($batch -isnot [array]) {
                $batch = @($batch)
            }

            Write-Log "Processing batch $batchNumber of $totalBatches ($($batch.Count) device(s))..." -Level Info

            $batchResults = Process-DeviceBatch -Devices $batch -ThrottleLimit $ThrottleLimit

            # Add results to collection
            $batchResults | ForEach-Object {
                [void]$allResults.Add($_)
            }

            $script:Statistics.ProcessedCount += $batch.Count
            
            # Update progress
            $percentComplete = [Math]::Round(($script:Statistics.ProcessedCount / $devices.Count) * 100, 1)
            Write-Progress -Activity "Processing Devices" `
                -Status "Batch $batchNumber of $totalBatches - $($script:Statistics.ProcessedCount) of $($devices.Count) devices" `
                -PercentComplete $percentComplete
        }

        Write-Progress -Activity "Processing Devices" -Completed

        # Step 4: Display results preview
        if ($allResults.Count -gt 0) {
            Write-Host "`n--- Results Preview (TPM & BIOS Information) ---`n" -ForegroundColor Cyan
            
            $successResults = $allResults | Where-Object { $_.Status -eq "Success" }
            $successResults | 
                Select-Object DeviceName, Model, TPMVersion, TPMSpecificationVersion, BIOSVersion, UserPrincipalName |
                Format-Table -AutoSize

            # Step 5: Export to CSV
            if (-not $NoExport) {
                $exportedPath = Export-Results -Results $allResults -ExportDirectory $ExportPath
            }
        }

        # Step 6: Show summary
        $script:Statistics.EndTime = Get-Date
        Show-Summary -Results $allResults

        # Return results for pipeline usage
        return $allResults
    }
    catch {
        Write-Log "Script execution failed: $($_.Exception.Message)" -Level Error
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level Debug
        throw
    }
    finally {
        Write-Progress -Activity "Processing Devices" -Completed -ErrorAction SilentlyContinue
    }
}

# Execute main function
$results = Invoke-Main
#endregion
