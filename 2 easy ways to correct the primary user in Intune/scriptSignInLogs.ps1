# Purpose:
#   Determine the most likely primary user for Intune-managed Windows devices by analyzing recent sign-in logs,
#   then update the Intune primary user if it differs. Uses Microsoft Graph PowerShell SDK.
# Prerequisites:
#   - Microsoft Graph PowerShell SDK installed
#   - Required scopes and admin consent: Device.ReadWrite.All, DeviceManagementManagedDevices.ReadWrite.All, Directory.Read.All, AuditLog.Read.All
#   - Test in non-production when using beta endpoints

# Create log directory if it doesn't exist
# ensures a local folder exists to store transcript logs; avoids failures when starting transcript.
$logPath = "C:\Temp"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force
}

# Start transcript logging with timestamp in filename
# Start-Transcript captures console output and helps troubleshoot run results later.
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logPath "UserDeviceAffinity_$timestamp.log"
Start-Transcript -Path $logFile -Force

try {
    Write-Host "Script started at $(Get-Date)"
    Write-Host "Connecting to Microsoft Graph..."

    # Validate required Graph API permissions and connect
    # Connect-MgGraph establishes an authenticated session that subsequent Get-/Invoke-MgGraphRequest calls use.
    $requiredScopes = @(
        "Device.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "Directory.Read.All",
        "AuditLog.Read.All"
    )
    Connect-MgGraph -Scopes $requiredScopes

    Write-Host "Successfully connected to Microsoft Graph"
    Write-Host "Retrieving Windows devices from Intune..."

    # Get all Windows devices in Intune - using filter for performance
    # only process company-owned Windows devices to avoid personal devices (managedDeviceOwnerType eq Company)
    $devices = Get-MgDeviceManagementManagedDevice -Filter "operatingSystem eq 'Windows' and managedDeviceOwnerType eq 'Company'"
    Write-Host "Found $($devices.Count) Windows company-owned devices to process"

    # Process each device
    foreach ($device in $devices) {
        # Device header and basic metadata for traceability
        # prints device name/serial/last sync to help correlate log entries with the Intune console.
        Write-Host "`n----------------------------------------"
        Write-Host "Processing device: $($device.DeviceName)" -ForegroundColor Cyan
        Write-Host "Serial Number: $($device.SerialNumber)"
        Write-Host "Last Sync: $($device.LastSyncDateTime)"
        
        $deviceId = $device.Id
        $azureDeviceId = $device.AzureADDeviceId

        # Query sign-in logs for last 30 days
        # Comment:
        #   - Uses Audit Log sign-in events to determine which user(s) used the device recently.
        #   - Limits the time window to 30 days to avoid scanning an excessive number of records.
        #   - The sign-in logs are grouped by UserId and the most frequent signer is assumed to be the primary user.
        Write-Host "Querying sign-in logs for the past 30 days..."
        $startDate = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $signinLogs = Get-MgAuditLogSignIn -Filter "deviceDetail/deviceId eq '$azureDeviceId' and createdDateTime ge $startDate"

        if ($signinLogs) {
            Write-Host "Found $($signinLogs.Count) sign-in events"
            
            # Group by user and sort to get most frequent user
            # Group-Object by UserId builds counts per user; Sort-Object chooses the top candidate.
            $userCounts = $signinLogs | Group-Object -Property UserId | Sort-Object Count -Descending
            $mostFrequentUser = $userCounts[0].Name
            
            # Get user details for better logging
            # Resolve the Graph user object for nicer UPN output in logs and to obtain the user id if needed.
            $mostFrequentUserDetails = Get-MgUser -UserId $mostFrequentUser
            Write-Host "Most frequent user: $($mostFrequentUserDetails.UserPrincipalName) with $($userCounts[0].Count) sign-ins"

            # Get current primary user details
            # Read the device's current primary user from Intune to compare with the candidate.
            $primaryUser = (Get-MgDeviceManagementManagedDeviceUser -ManagedDeviceId $deviceId).Id
            $primaryUserDetails = Get-MgUser -UserId $primaryUser
            Write-Host "Current primary user: $($primaryUserDetails.UserPrincipalName)"

            # Check if update is needed
            # Comment:
            #   - If the most frequent sign-in user differs from the current primary user, update via Graph.
            #   - The update uses the beta deviceManagement managedDevices/{id}/users/$ref endpoint.
            #   - Note: This operation may require elevated privileges and beta API behavior may change.
            if ($primaryUser -ne $mostFrequentUser) {
                Write-Host "Updating primary user..." -ForegroundColor Yellow
                
                # Use Graph API beta endpoint to update primary user
                # Note: This endpoint might change when moving to v1.0
                $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/users/`$ref"
                $json = @{ "@odata.id" = "https://graph.microsoft.com/beta/users/$mostFrequentUser" } | ConvertTo-Json
                
                # Perform the update
                Invoke-MgGraphRequest -Method POST -Uri $uri -Body $json
                Write-Host "Successfully updated device $($device.DeviceName) primary user to $($mostFrequentUserDetails.UserPrincipalName)" -ForegroundColor Green
            } else {
                Write-Host "No update needed - correct primary user already set" -ForegroundColor Green
            }
        } else {
            # No sign-ins found for this device within the configured window
            # In this case, the script does not update the primary user and logs the lack of events.
            Write-Host "No sign-ins found for device $($device.DeviceName) in the last 30 days" -ForegroundColor Yellow
        }
    }

    Write-Host "`nScript completed successfully at $(Get-Date)" -ForegroundColor Green
} catch {
    # Enhanced error handling with more details
    # Comment:
    #   - Provides time, error message, script line, and command to make troubleshooting easier.
    #   - Graph API calls can fail due to permissions, throttling, or network issues.
    Write-Host "An error occurred at $(Get-Date):" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line Number: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Command: $($_.InvocationInfo.MyCommand)" -ForegroundColor Red
} finally {
    # Ensure transcript is stopped even if the script errors
    # Stop-Transcript finalizes the log file and flushes output to disk.
    Stop-Transcript
}