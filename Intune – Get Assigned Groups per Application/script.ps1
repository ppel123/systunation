# =============================================================================
# Get-AppAssignments.ps1
# Retrieves all Windows app assignments from Intune, including group name,
# assignment type (Included/Excluded/All Devices/All Users) and intent.
# Requires: Microsoft.Graph PowerShell SDK
# =============================================================================

# Connect using the new SDK
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All", "Group.Read.All"

# -----------------------------------------------------------------------------
# Build the filter URL to fetch all Windows app types
# -----------------------------------------------------------------------------
$baseUrl = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
$filter  = '$filter' + "=" +
    "(isof('microsoft.graph.windowsStoreApp')" +
    " or isof('microsoft.graph.microsoftStoreForBusinessApp')" +
    " or isof('microsoft.graph.officeSuiteApp')" +
    " or isof('microsoft.graph.win32LobApp')" +
    " or isof('microsoft.graph.windowsMicrosoftEdgeApp')" +
    " or isof('microsoft.graph.windowsPhone81AppX')" +
    " or isof('microsoft.graph.windowsPhone81StoreApp')" +
    " or isof('microsoft.graph.windowsPhoneXAP')" +
    " or isof('microsoft.graph.windowsAppX')" +
    " or isof('microsoft.graph.windowsMobileMSI')" +
    " or isof('microsoft.graph.windowsUniversalAppX')" +
    " or isof('microsoft.graph.webApp')" +
    " or isof('microsoft.graph.windowsWebApp')" +
    " or isof('microsoft.graph.winGetApp'))" +
    " and (microsoft.graph.managedApp/appAvailability eq null" +
    " or microsoft.graph.managedApp/appAvailability eq 'lineOfBusiness'" +
    " or isAssigned eq true)"
$orderby = '$orderby=displayName'

$url = "$baseUrl`?$filter&$orderby"

# -----------------------------------------------------------------------------
# Fetch all apps - handle pagination via @odata.nextLink
# -----------------------------------------------------------------------------
$apps     = [System.Collections.Generic.List[object]]::new()
$nextLink = $url

do {
    $response = Invoke-MgGraphRequest -Uri $nextLink -Method GET
    $apps.AddRange($response.value)
    $nextLink = $response.'@odata.nextLink'
} while ($nextLink)

Write-Host "Total apps retrieved: $($apps.Count)" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# Helper: translate @odata.type to a readable assignment type
# -----------------------------------------------------------------------------
function Get-AssignmentType {
    param([string]$ODataType)
    switch ($ODataType) {
        "#microsoft.graph.groupAssignmentTarget"             { return "Included" }
        "#microsoft.graph.exclusionGroupAssignmentTarget"    { return "Excluded" }
        "#microsoft.graph.allDevicesAssignmentTarget"        { return "All Devices" }
        "#microsoft.graph.allLicensedUsersAssignmentTarget"  { return "All Users" }
        default                                              { return $ODataType }
    }
}

# -----------------------------------------------------------------------------
# Build result table
# -----------------------------------------------------------------------------
$table = New-Object System.Data.DataTable
$table.Columns.Add("ApplicationName") | Out-Null
$table.Columns.Add("ApplicationID")   | Out-Null
$table.Columns.Add("GroupName")       | Out-Null
$table.Columns.Add("GroupID")         | Out-Null
$table.Columns.Add("AssignmentType")  | Out-Null   # Included / Excluded / All Devices / All Users
$table.Columns.Add("Intent")          | Out-Null   # required / available / uninstall / availableWithoutEnrollment

# Cache group display names to minimise API calls
$groupCache = @{}

# -----------------------------------------------------------------------------
# Iterate apps and resolve assignments
# -----------------------------------------------------------------------------
$counter = 0

foreach ($app in $apps) {
    $counter++
    $appID          = $app.id
    $appDisplayName = $app.displayName

    Write-Progress -Activity "Processing apps" `
                   -Status "$counter of $($apps.Count): $appDisplayName" `
                   -PercentComplete (($counter / $apps.Count) * 100)

    # Fetch app details with assignments expanded - note ?$expand (not /$expand)
    $assignmentUrl = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appID" + '?$expand=assignments'
    
    try {
        $appDetails = Invoke-MgGraphRequest -Uri $assignmentUrl -Method GET
    }
    catch {
        Write-Warning "Failed to retrieve assignments for '$appDisplayName' ($appID): $_"
        continue
    }

    # Skip apps with no assignments
    if (-not $appDetails.assignments -or $appDetails.assignments.Count -eq 0) {
        continue
    }

    foreach ($assignment in $appDetails.assignments) {
        $target         = $assignment.target
        $odataType      = $target.'@odata.type'
        $assignmentType = Get-AssignmentType -ODataType $odataType
        $intent         = $assignment.intent
        $groupID        = $target.groupId

        # Resolve group name based on target type
        switch ($odataType) {
            "#microsoft.graph.allDevicesAssignmentTarget"       { $groupName = "All Devices"; $groupID = "" }
            "#microsoft.graph.allLicensedUsersAssignmentTarget" { $groupName = "All Users";   $groupID = "" }
            default {
                if ($groupID) {
                    if (-not $groupCache.ContainsKey($groupID)) {
                        try {
                            $groupDetails         = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/groups/$groupID" -Method GET
                            $groupCache[$groupID] = $groupDetails.displayName
                        }
                        catch {
                            Write-Warning "Could not resolve group '$groupID': $_"
                            $groupCache[$groupID] = "Unknown"
                        }
                    }
                    $groupName = $groupCache[$groupID]
                }
                else {
                    $groupName = "Unknown"
                }
            }
        }

        $table.Rows.Add($appDisplayName, $appID, $groupName, $groupID, $assignmentType, $intent) | Out-Null
    }
}

Write-Progress -Activity "Processing apps" -Completed
Write-Host "Total assignment rows: $($table.Rows.Count)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# Output results
# -----------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportPath = "C:\Temp\AppsAndGroups_$timestamp.csv"

# Display results in console
$table | Format-Table -AutoSize

$table | Out-GridView -Title "Intune App Assignments"
$table | Export-Csv -Path $exportPath -Delimiter "," -Encoding UTF8 -NoTypeInformation

Write-Host "CSV exported to: $exportPath" -ForegroundColor Green
