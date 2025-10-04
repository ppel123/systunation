<#
.SYNOPSIS
  Determine the currently logged-in user on this Windows device (local run) and print a detailed summary.
.NOTES
  - Designed to run locally on the endpoint; does not call Microsoft Graph.
  - Uses dsregcmd and WMI/CIM as data sources and includes fallbacks.
  - Writes a transcript log to C:\Temp for troubleshooting.
#>

# Create log directory and start transcript (consistent with other scripts)
# Ensures a local directory exists for logs and starts PowerShell transcript for debugging.
$logPath = "C:\Temp"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logPath "CheckLoggedInUser_$timestamp.log"
Start-Transcript -Path $logFile -Force

try {
    # Header
    # Prints a timestamped start message to indicate script execution.
    Write-Host "Starting local logged-in user check at $(Get-Date)" -ForegroundColor Cyan

    # Basic host info
    # Retrieves hostname and OS version for context in the summary.
    $hostname = $env:COMPUTERNAME
    $os = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption

    # Primary identity using .NET (returns DOMAIN\username for the interactive user)
    # Uses WindowsIdentity to get the current user's SAM account (e.g., DOMAIN\user) and SID.
    $winIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $samAccount = $winIdentity.Name          # e.g. CONTOSO\alice
    $sid = $winIdentity.User.Value

    # Use dsregcmd to extract AzureAd join state and device ID
    # Runs dsregcmd /status to get Azure AD join info and device ID if available.
    $dsreg = $null
    $isAzureAdJoined = $false
    $dsregDeviceId = $null
    try {
        $dsregRaw = dsregcmd /status 2>$null
        if ($dsregRaw) {
            $dsreg = $dsregRaw -split "`r?`n"
            # Parse common useful values
            # Parses the output to extract Azure AD join status and device ID.
            foreach ($line in $dsreg) {
                $trim = $line.Trim()
                if ($trim -match "AzureAdJoined\s*:\s*YES") { $isAzureAdJoined = $true }
                if ($trim -match "DeviceId\s*:\s*([0-9a-fA-F\-]{36})") { $dsregDeviceId = $matches[1].Trim() }
            }
        }
    } catch {
        # dsregcmd may not be present or available on older SKUs; ignore parsing errors
        # Silently handles cases where dsregcmd is not available.
    }

    # Additional fallback: Win32_ComputerSystem Username property
    # Uses WMI to get the username as a backup if .NET identity fails.
    $wmiUser = $null
    try {
        $wmiUser = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
        if (-not $samAccount -and $wmiUser) { $samAccount = $wmiUser }
    } catch { }

    # Fallback: Query the Registry for the UPN of the logged-in user by comparing SAMName
    # Dynamically searches the IdentityStore registry for the logged-in user's UPN by matching SAMName.
    $registryUserUPN = $null
    try {
        Write-Host "Querying Registry for logged-in user's UPN dynamically..." -ForegroundColor Yellow
        $identityStoreBasePath = "HKLM:\SOFTWARE\Microsoft\IdentityStore\Cache"
        if (Test-Path $identityStoreBasePath) {
            # Get all SID-based folders under Cache
            # Enumerates SID folders in the registry cache.
            $sidFolders = Get-ChildItem -Path $identityStoreBasePath -ErrorAction SilentlyContinue
            Write-Host "Found $($sidFolders.Count) SID folders in IdentityStore Cache" -ForegroundColor Yellow
            
            foreach ($sidFolder in $sidFolders) {
                # Look for IdentityCache subfolder
                # Checks for the IdentityCache subfolder under each SID.
                $identityCachePath = Join-Path $sidFolder.PSPath "IdentityCache"
                if (Test-Path $identityCachePath) {
                    Write-Host "Checking IdentityCache in: $($sidFolder.Name)" -ForegroundColor Yellow
                    $identityKeys = Get-ChildItem -Path $identityCachePath -ErrorAction SilentlyContinue
                    
                    foreach ($key in $identityKeys) {
                        try {
                            # Read SAMName and UserName from the registry key
                            # Retrieves SAMName and UserName values from each registry key.
                            $regProperties = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
                            $samName = $regProperties.SAMName
                            $userName = $regProperties.UserName
                            
                            Write-Host "Checking key: $($key.Name), SAMName: '$samName', UserName: '$userName'" -ForegroundColor Yellow
                            
                            # Compare SAMName with the SAMAccount from other methods
                            # Compares the registry SAMName with the determined SAM account (handling domain prefixes).
                            $samAccountToCompare = $samAccount
                            if ($samAccount -and $samAccount.Contains('\')) {
                                $samAccountToCompare = $samAccount.Split('\')[1]  # Get just the username part
                            }
                            
                            if ($samName -and ($samName -eq $samAccount -or $samName -eq $samAccountToCompare)) {
                                $registryUserUPN = $userName
                                Write-Host "Match found in Registry: SAMName='$samName', UserName='$userName'" -ForegroundColor Green
                                break
                            }
                        } catch {
                            Write-Host "Failed to read registry key: $($key.PSPath). Error: $($_.Exception.Message)" -ForegroundColor Red
                        }
                    }
                    
                    if ($registryUserUPN) { break }
                }
            }
        }
        
        if (-not $registryUserUPN) {
            Write-Host "No matching SAM account found in registry. SAM Account to match: '$samAccount'" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Failed to query Registry for UPN dynamically: $($_.Exception.Message)" -ForegroundColor Red
    }

    # Update determination if Registry provided a user
    # Sets the determined user if registry query succeeded.
    if ($registryUserUPN -and -not $determinedUser) {
        $determinedUser = $registryUserUPN
        $method = "Registry (IdentityStore, dynamic)"
    }

    # Build details object with collected facts
    # Compiles all gathered information into a hashtable for the summary.
    $details = [ordered]@{
        HostName           = $hostname
        OS                 = $os
        SAMAccount         = $samAccount
        SID                = $sid
        AzureADJoined      = $isAzureAdJoined
        DSREG_DeviceId     = $dsregDeviceId
        RegistryUserUPN    = $registryUserUPN
    }

    # Decide best determination and method (update to prioritize registry UPN)
    # Prioritizes registry UPN, then SAM account as fallbacks.
    if ($details.RegistryUserUPN) {
        $determinedUser = $details.RegistryUserUPN
        $method = "Registry (IdentityStore, dynamic)"
    } elseif ($details.SAMAccount) {
        $determinedUser = $details.SAMAccount
        $method = "WindowsIdentity (SAM)"
    } else {
        $determinedUser = "<Unknown>"
        $method = "None"
    }

    # Final detailed summary
    # Builds and displays a formatted summary of all collected data.
    $finalOutput = @"
===== Logged-in user determination summary =====
Host:            $($details.HostName)
OS:              $($details.OS)
DeterminedUser:  $determinedUser
Method:          $method
SAM Account:     $($details.SAMAccount)
SID:             $($details.SID)
AzureAD Joined:  $($details.AzureADJoined)
DSREG DeviceId:  $($details.DSREG_DeviceId)
Registry UPN:    $($details.RegistryUserUPN)
===== End summary =====
"@

    Write-Host $finalOutput -ForegroundColor Cyan

} catch {
    # Error handling and diagnostics
    # Catches and displays any errors during execution.
    Write-Host "An error occurred during local determination: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    # Ensure transcript is stopped even if the script errors
    # Stops the transcript to finalize the log file.
    Stop-Transcript
}

# Outputs the final summary again after transcript stop for visibility.
Write-Host $finalOutput

