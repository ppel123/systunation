param($Timer)
# ============================================================
# Sync Intune Group Membership
# Adds/removes devices from a static Entra group based on
# whether a target application is detected as installed
# (a condition dynamic membership rules cannot express).
# ============================================================
$ErrorActionPreference = "Stop"
# --- Configuration: read from Function App Application Settings, not hardcoded ---
$tenantId       = $env:TENANT_ID
$clientId       = $env:CLIENT_ID
$keyVaultName   = $env:KEY_VAULT_NAME
$secretName     = $env:KEY_VAULT_SECRET_NAME
$targetGroupId  = $env:TARGET_GROUP_ID
$targetAppName  = $env:TARGET_APP_NAME   # exact displayName as it appears in detectedApps

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "[$Level] $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
}

function Invoke-GraphGetAll {
    param([string]$Uri, [hashtable]$Headers)
    $all = [System.Collections.Generic.List[object]]::new()
    $nextUri = $Uri
    do {
        $page = Invoke-RestMethod -Method Get -Uri $nextUri -Headers $Headers
        if ($page.value) {
            foreach ($item in $page.value) { $all.Add($item) }
        }
        $nextUri = $page.'@odata.nextLink'
    } while ($nextUri)
    return @($all)
}

# --- Step 1: Authenticate using the Function's own Managed Identity ---
Write-Log "Connecting with Managed Identity..."
Connect-AzAccount -Identity | Out-Null

# --- Step 2: Pull the app registration's client secret from Key Vault ---
Write-Log "Retrieving client secret from Key Vault..."
$clientSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -AsPlainText
if ([string]::IsNullOrEmpty($clientSecret)) {
    throw "Key Vault secret '$secretName' is empty or missing."
}

# --- Step 3: Get an app-only Graph token via client credentials ---
Write-Log "Requesting Graph token..."
$tokenBody = @{
    client_id     = $clientId
    scope         = "https://graph.microsoft.com/.default"
    client_secret = $clientSecret
    grant_type    = "client_credentials"
}
$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $tokenBody
$graphHeaders = @{ Authorization = "Bearer $($tokenResponse.access_token)" }

# --- Step 4: Find the target app's detectedApps entry ---
# detectedApps is Intune's own software inventory, already collected on the
# device's normal check-in cadence; nothing extra runs on the endpoint.
Write-Log "Looking up detectedApps entry for '$targetAppName'..."
$detectedAppsUri = "https://graph.microsoft.com/v1.0/deviceManagement/detectedApps?`$filter=displayName eq '$targetAppName'"
$detectedApps = Invoke-GraphGetAll -Uri $detectedAppsUri -Headers $graphHeaders
if ($detectedApps.Count -eq 0) {
    Write-Log "No detectedApps entry found for '$targetAppName'. Treating as zero matching devices, proceeding to reconcile (existing group members will be removed if they no longer match)." "WARN"
}
# An app can have multiple detectedApps entries across versions; union all of them.
$deviceIdsWithApp = New-Object System.Collections.Generic.HashSet[string]
foreach ($app in $detectedApps) {
    $managedDevicesUri = "https://graph.microsoft.com/v1.0/deviceManagement/detectedApps/$($app.id)/managedDevices?`$select=id,deviceName"
    $devicesForApp = Invoke-GraphGetAll -Uri $managedDevicesUri -Headers $graphHeaders
    foreach ($d in $devicesForApp) {
        # The detectedApps navigation doesn't expose azureADDeviceId directly;
        # look it up via the full managedDevices resource, which does.
        $fullDeviceUri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($d.id)?`$select=azureADDeviceId,deviceName"
        try {
            $fullDevice = Invoke-RestMethod -Method Get -Uri $fullDeviceUri -Headers $graphHeaders
            if (-not [string]::IsNullOrEmpty($fullDevice.azureADDeviceId)) {
                [void]$deviceIdsWithApp.Add($fullDevice.azureADDeviceId)
            } else {
                Write-Log "Device '$($fullDevice.deviceName)' has no azureADDeviceId, skipping." "WARN"
            }
        }
        catch {
            Write-Log "Could not resolve managed device $($d.id): $($_.Exception.Message)" "WARN"
        }
    }
}
Write-Log "Found $($deviceIdsWithApp.Count) device(s) with '$targetAppName' installed."

# --- Step 5: Resolve azureADDeviceId to the Entra device object ID ---
# Group membership operations need the device object's own "id", which is
# different from azureADDeviceId (the device's deviceId property).
function Get-EntraDeviceObjectId {
    param([string]$AzureAdDeviceId)
    $uri = "https://graph.microsoft.com/v1.0/devices?`$filter=deviceId eq '$AzureAdDeviceId'&`$count=true"
    $advancedHeaders = $graphHeaders + @{ ConsistencyLevel = "eventual" }
    $result = Invoke-RestMethod -Method Get -Uri $uri -Headers $advancedHeaders
    if ($result.value.Count -gt 0) { return $result.value[0].id }
    return $null
}
$targetObjectIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($aadId in $deviceIdsWithApp) {
    $objectId = Get-EntraDeviceObjectId -AzureAdDeviceId $aadId
    if ($objectId) { [void]$targetObjectIds.Add($objectId) }
    else { Write-Log "Could not resolve device object ID for azureADDeviceId $aadId" "WARN" }
}

# --- Step 6: Get current group membership ---
Write-Log "Retrieving current members of target group..."
$currentMembersUri = "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members?`$select=id"
$currentMembers = Invoke-GraphGetAll -Uri $currentMembersUri -Headers $graphHeaders
$currentMemberIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($m in $currentMembers) { [void]$currentMemberIds.Add($m.id) }

# --- Step 7: Diff, so repeated runs only touch what actually changed ---
$toAdd    = $targetObjectIds | Where-Object { -not $currentMemberIds.Contains($_) }
$toRemove = $currentMemberIds | Where-Object { -not $targetObjectIds.Contains($_) }
Write-Log "Devices to add: $($toAdd.Count) | Devices to remove: $($toRemove.Count)"

# --- Step 8: Apply additions ---
foreach ($deviceObjectId in $toAdd) {
    try {
        $addBody = @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$deviceObjectId" } | ConvertTo-Json
        Invoke-RestMethod -Method Post `
            -Uri "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members/`$ref" `
            -Headers ($graphHeaders + @{ "Content-Type" = "application/json" }) `
            -Body $addBody
        Write-Log "Added device $deviceObjectId to group."
    }
    catch {
        Write-Log "Failed to add device $deviceObjectId : $($_.Exception.Message)" "ERROR"
    }
}

# --- Step 9: Apply removals ---
foreach ($deviceObjectId in $toRemove) {
    try {
        Invoke-RestMethod -Method Delete `
            -Uri "https://graph.microsoft.com/v1.0/groups/$targetGroupId/members/$deviceObjectId/`$ref" `
            -Headers $graphHeaders
        Write-Log "Removed device $deviceObjectId from group."
    }
    catch {
        Write-Log "Failed to remove device $deviceObjectId : $($_.Exception.Message)" "ERROR"
    }
}
Write-Log "Reconciliation complete."