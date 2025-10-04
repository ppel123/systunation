# Top-level: describe purpose and prerequisites
# Purpose:
#   - Determine the most-recent user associated with a device by using Intune compliance report "LastContact"
#   - If that user differs from the device's current Intune primary user, update the primary user to the most recent reporter.
# Prerequisites:
#   - Microsoft Graph PowerShell SDK installed and available (Connect-MgGraph, Invoke-MgGraphRequest, Get-MgUser, etc.)
#   - Admin consent for scopes used: Device.ReadWrite.All, DeviceManagementManagedDevices.ReadWrite.All, Directory.Read.All, AuditLog.Read.All
#   - Script executed with sufficient rights; beta Graph endpoints are used (test in non-production)
# Notes:
#   - Script writes a transcript log to C:\Temp by default
#   - Uses device management report endpoint getDevicePoliciesComplianceReport to get per-device "LastContact" timestamps

# Create log directory if it doesn't exist
$logPath = "C:\Temp"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force
}

# Start transcript logging with timestamp in filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $logPath "UserDeviceAffinity_$timestamp.log"
Start-Transcript -Path $logFile -Force

try {
    # Script start timestamp and initial connect info
    Write-Host "Script started at $(Get-Date)"
    Write-Host "Connecting to Microsoft Graph..."

    # Validate required Graph API permissions and connect
    # we collect scopes into $requiredScopes then call Connect-MgGraph.
    # This will prompt for consent if necessary and create an OAuth session used for subsequent Invoke-MgGraphRequest calls.
    $requiredScopes = @(
        "Device.ReadWrite.All",
        "DeviceManagementManagedDevices.ReadWrite.All",
        "Directory.Read.All",
        "AuditLog.Read.All"
    )
    Connect-MgGraph -Scopes $requiredScopes

    # Successfully connected message and device retrieval
    # we fetch only Windows devices using a server-side filter to keep the dataset smaller.
    Write-Host "Successfully connected to Microsoft Graph"
    Write-Host "Retrieving Windows devices from Intune..."

    # Get all Windows devices in Intune - using filter for performance
    # only process company-owned Windows devices to avoid personal devices
    $devices = Get-MgDeviceManagementManagedDevice -Filter "operatingSystem eq 'Windows' and managedDeviceOwnerType eq 'Company'"
    Write-Host "Found $($devices.Count) Windows devices to process"

    # Process each device
    foreach ($device in $devices) {
        # Separator and device header info for readability in logs
        Write-Host "`n----------------------------------------"
        Write-Host "Processing device: $($device.DeviceName)" -ForegroundColor Cyan
        Write-Host "Serial Number: $($device.SerialNumber)"
        Write-Host "Last Sync: $($device.LastSyncDateTime)"
        
        $deviceId = $device.Id

        # Get device compliance states (report)
        # we first retrieve the device->user relations (managedDevices/{id}/users) so we can correlate relation rows
        Write-Host "Retrieving compliance states (report query)..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/users"
        $deviceUsers = (Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction SilentlyContinue).value

        if ($deviceUsers) {
            # Build POST payload for getDevicePoliciesComplianceReport
            # This POST returns a schema+values result where LastContact contains the timestamp per policy row.
            #   - We filter by deviceId and common PolicyPlatformType values to reduce noise
            #   - The report returns rows under 'Values' and accompanying 'Schema' describing column order
            $filterValue = "(DeviceId eq '$deviceId') and ((PolicyPlatformType eq '4') or (PolicyPlatformType eq '5') or (PolicyPlatformType eq '6') or (PolicyPlatformType eq '8') or (PolicyPlatformType eq '100'))"
            $body = @{
                select  = @()
                skip    = 0
                top     = 50
                filter  = $filterValue
                orderBy = @("PolicyName asc")
                search  = ""
            } | ConvertTo-Json -Depth 5

            # POST to the reports endpoint that returns Schema + Values
            $reportUri = "https://graph.microsoft.com/beta/deviceManagement/reports/getDevicePoliciesComplianceReport"
            try {
                $reportResp = Invoke-MgGraphRequest -Uri $reportUri -Method POST -Body $body -ErrorAction Stop
            } catch {
                Write-Host "Failed to run compliance report query for device $($device.DeviceName) (id: $deviceId): $($_.Exception.Message)" -ForegroundColor Red
                continue
            }

            # Validate report result exists
            if (-not $reportResp -or -not $reportResp.Values) {
                Write-Host "No report rows returned for device $($device.DeviceName)" -ForegroundColor Yellow
                continue
            }

            # Map Schema column names to numeric indices
            # Schema mapping lets us extract UserId / UPN / LastContact from each Values row without relying on hard-coded order
            $colIndex = @{}
            if ($reportResp.Schema) {
                for ($i = 0; $i -lt $reportResp.Schema.Count; $i++) {
                    $colName = $reportResp.Schema[$i].Column
                    $colIndex[$colName] = $i
                }
            }

            # Build a lookup of the most recent LastContact per user from the Values rows
            # iterates rows, extracts UserId/UPN/LastContact, normalizes datetime, and keeps the latest timestamp per key
            $userLatest = @{}  # key = UserId or UPN, value = datetime

            foreach ($row in $reportResp.Values) {
                # extract columns safely using the mapped indices
                $userId = $null; $upn = $null; $lastContact = $null
                if ($colIndex.ContainsKey("UserId")) { $userId = $row[$colIndex["UserId"]] }
                if ($colIndex.ContainsKey("UPN"))     { $upn    = $row[$colIndex["UPN"]] }
                if ($colIndex.ContainsKey("LastContact")) { $lastContact = $row[$colIndex["LastContact"]] }

                if (-not $lastContact) {
                    # skip rows without timestamp
                    continue
                }

                # normalize datetime
                try { $dt = [datetime]$lastContact } catch { continue }

                # prefer UserId as the key, fallback to UPN
                $key = $userId
                if (-not $key -and $upn) { $key = $upn }

                if ($key) {
                    if (-not $userLatest.ContainsKey($key) -or $dt -gt $userLatest[$key]) {
                        $userLatest[$key] = $dt
                    }
                }
            }

            # Build userComplianceStates by correlating deviceUsers with report lookup
            # Comment:
            #   deviceUsers may include relation-specific ids; the report may include UserId or UPN.
            #   For each device user we attempt multiple candidate matches (relation userId, userPrincipalName, relation id).
            #   If we find a match we resolve a canonical Azure AD id (if possible) and UPN for logging and later update.
            $userComplianceStates = @()
            foreach ($user in $deviceUsers) {
                # collect candidate keys that might match the report (UserId, UPN, the relation id)
                $candidates = @()
                if ($null -ne $user.userId) { $candidates += $user.userId }
                if ($null -ne $user.userPrincipalName) { $candidates += $user.userPrincipalName }
                if ($null -ne $user.id) { $candidates += $user.id }

                # find the first candidate that exists in the report's lookup
                $matchKey = $candidates | Where-Object { $userLatest.ContainsKey($_) } | Select-Object -First 1

                if ($matchKey) {
                    $last = $userLatest[$matchKey]

                    # resolve Azure AD id / UPN for logging and for the update operation
                    $resolvedId = $null
                    $resolvedUpn = $null

                    if ($matchKey -match '^[0-9a-fA-F\-]{36}$') {
                        # likely an Azure AD object id
                        $resolvedId = $matchKey
                        $u = Get-MgUser -UserId $resolvedId -ErrorAction SilentlyContinue
                        if ($u) { $resolvedUpn = $u.UserPrincipalName }
                    } else {
                        # treat as UPN, try to resolve to id
                        $resolvedUpn = $matchKey
                        $u = Get-MgUser -UserId $resolvedUpn -ErrorAction SilentlyContinue
                        if ($u) { $resolvedId = $u.Id }
                    }

                    # if still missing an ID, try using the deviceUsers relation id as a last resort
                    if (-not $resolvedId) { $resolvedId = $user.id }
                    if (-not $resolvedUpn) { $resolvedUpn = $user.userPrincipalName -or "" }

                    $userComplianceStates += [PSCustomObject]@{
                        UserId = $resolvedId
                        UserPrincipalName = $resolvedUpn
                        LastComplianceCheck = $last
                    }
                } else {
                    $display = $user.displayName -or $user.userPrincipalName -or $user.id
                    Write-Host "No LastContact row for user $display / id $($user.id) on device $($device.DeviceName)" -ForegroundColor Yellow
                }
            }

            # Fallback logic:
            # Comment:
            #   - If no deviceUsers matched but the report returned rows, fallback to the most-recent report row overall.
            #   - Try to resolve the report key to an Azure AD user id or UPN; if resolution fails, use the raw key for logging.
            # Fallback: if no deviceUsers matched but the report contains rows, pick the most-recent report row and resolve it
            if (($userComplianceStates.Count -eq 0) -and ($userLatest.Count -gt 0)) {
                $best = $userLatest.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
                $bestKey = $best.Name
                $bestDt = $best.Value

                $resolvedId = $null
                $resolvedUpn = $null
                if ($bestKey -match '^[0-9a-fA-F\-]{36}$') {
                    $resolvedId = $bestKey
                    $u = Get-MgUser -UserId $resolvedId -ErrorAction SilentlyContinue
                    if ($u) { $resolvedUpn = $u.UserPrincipalName }
                } else {
                    # bestKey likely a UPN
                    $resolvedUpn = $bestKey
                    $u = Get-MgUser -UserId $resolvedUpn -ErrorAction SilentlyContinue
                    if ($u) { $resolvedId = $u.Id }
                }

                if (-not $resolvedId) { $resolvedId = $bestKey }    # use bestKey if we cannot resolve
                if (-not $resolvedUpn) { $resolvedUpn = $bestKey }

                $userComplianceStates += [PSCustomObject]@{
                    UserId = $resolvedId
                    UserPrincipalName = $resolvedUpn
                    LastComplianceCheck = $bestDt
                }

                Write-Host "Fallback: using most-recent report user $resolvedUpn / $resolvedId with LastContact $bestDt" -ForegroundColor Cyan
            }

            if ($userComplianceStates -and $userComplianceStates.Count -gt 0) {
                # Select the most recent compliance-check user
                # pick the entry with the latest LastComplianceCheck datetime
                $mostRecentUser = $userComplianceStates |
                    Sort-Object -Property LastComplianceCheck -Descending |
                    Select-Object -First 1

                Write-Host "Found compliance LastContact for users:"
                $userComplianceStates | Format-Table -AutoSize

                # Get current primary user details from Intune
                # we fetch the managed device's current primary user via Get-MgDeviceManagementManagedDeviceUser
                #   and then resolve that id to a UserPrincipalName for clear logging.
                $primaryUser = (Get-MgDeviceManagementManagedDeviceUser -ManagedDeviceId $deviceId).Id
                $primaryUserDetails = Get-MgUser -UserId $primaryUser
                Write-Host "Current primary user: $($primaryUserDetails.UserPrincipalName)"

                # Check update decision
                # Comment:
                #   - Compare the managed device primary user id to the resolved mostRecentUser.UserId.
                #   - If different, POST to the device users/$ref endpoint to set the primary user (beta endpoint).
                #   - Log successes and failures; the update uses the beta Graph API path documented earlier.
                if ($primaryUser -ne $mostRecentUser.UserId) {
                    Write-Host "Updating primary user..." -ForegroundColor Yellow
                    
                    $uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$deviceId/users/`$ref"
                    $json = @{ 
                        "@odata.id" = "https://graph.microsoft.com/beta/users/$($mostRecentUser.UserId)" 
                    } | ConvertTo-Json
                    
                    # Perform the update
                    Invoke-MgGraphRequest -Method POST -Uri $uri -Body $json
                    Write-Host "Successfully updated device $($device.DeviceName) primary user to $($mostRecentUser.UserPrincipalName)" -ForegroundColor Green
                } else {
                    Write-Host "No update needed - correct primary user already set" -ForegroundColor Green
                }
            } else {
                # No user compliance timestamps found for this device
                # if no LastContact rows matched for any device user and no fallback was possible, we log and skip updating this device.
                Write-Host "No users on device had LastContact timestamps" -ForegroundColor Yellow
            }
        } else {
            # No users associated with device
            # device has no associated users in Intune (no relation records); nothing to compare/update.
            Write-Host "No users associated with device $($device.DeviceName)" -ForegroundColor Yellow
        }
    }

    # Script completion summary
    # prints final timestamp; transcript will be stopped in finally block
    Write-Host "`nScript completed successfully at $(Get-Date)" -ForegroundColor Green
} catch {
    # Error handling and diagnostics
    # Comment:
    #   - Provide timestamped error messages, exception text, script line number and the failing command for easier troubleshooting.
    #   - Exceptions could arise from Graph call failures, network issues, or permission problems.
    Write-Host "An error occurred at $(Get-Date):" -ForegroundColor Red
    Write-Host "Error Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Line Number: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Command: $($_.InvocationInfo.MyCommand)" -ForegroundColor Red
} finally {
    # Ensure transcript is stopped even if the script errors
    # Stop-Transcript call ensures the log file is finalized and can be reviewed after script execution.
    Stop-Transcript
}