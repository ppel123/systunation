#-----------------------------------------
# Default settings (edit as needed)
#-----------------------------------------
$GridView = $true
$CSV = $true
$CsvPath = "C:\TEMP\Intune_RemediationScripts_Assignments_Report.csv"

#-----------------------------------------
# Script purpose
#-----------------------------------------
# This script retrieves all Intune Remediation scripts assignments (deviceHealthScripts) and their data:
# - Assignment target type (group/all devices/all users/etc.)
# - Group name and ID (when applicable)
# - Assignment filter details
# - Schedule type and frequency/timing summary
#
# Output can be viewed in console, Out-GridView, and/or CSV.

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " Intune Remediation Scripts Assignment Report" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "[$(Get-Date -Format 'u')] Starting script..." -ForegroundColor Yellow

#-----------------------------------------
# Connect to Microsoft Graph
#-----------------------------------------
Write-Host "[$(Get-Date -Format 'u')] Checking Microsoft Graph connection..." -ForegroundColor Yellow
try {
    if (-not (Get-MgContext)) {
        Write-Host "[$(Get-Date -Format 'u')] No active Graph session found. Connecting..." -ForegroundColor Yellow
        Connect-MgGraph -Scopes @(
            "DeviceManagementConfiguration.Read.All",
            "DeviceManagementManagedDevices.Read.All",
            "Group.Read.All"
        ) | Out-Null
        Write-Host "[$(Get-Date -Format 'u')] Connected to Microsoft Graph." -ForegroundColor Green
    }
    else {
        $ctx = Get-MgContext
        Write-Host "[$(Get-Date -Format 'u')] Already connected to Graph as $($ctx.Account)." -ForegroundColor Green
    }
}
catch {
    Write-Error "Failed to connect to Microsoft Graph. $_"
    return
}

#-----------------------------------------
# Helper: Resolve AAD group display name safely
#-----------------------------------------
function Get-GroupDisplayNameSafe {
    param(
        [Parameter(Mandatory = $true)][string]$GroupId
    )
    try {
        $group = Get-MgGroup -GroupId $GroupId -ErrorAction Stop
        return $group.DisplayName
    }
    catch {
        return "Unknown group ($GroupId)"
    }
}

#-----------------------------------------
# Helper: Convert assignment runSchedule into readable text
#-----------------------------------------
function Get-ScheduleSummary {
    param(
        [Parameter(Mandatory = $false)]$RunSchedule
    )

    if (-not $RunSchedule) { return "Not specified" }

    $odataType = $RunSchedule.'@odata.type'

    switch -Regex ($odataType) {
        "deviceHealthScriptDailySchedule" {
            $time = if ($RunSchedule.time) { $RunSchedule.time } else { "N/A" }
            $interval = if ($RunSchedule.interval) { $RunSchedule.interval } else { "1" }
            $useUtc = if ($null -ne $RunSchedule.useUtc) { $RunSchedule.useUtc } else { "N/A" }
            return "Daily | Every $interval day(s) | Time: $time | UTC: $useUtc"
        }
        "deviceHealthScriptHourlySchedule" {
            $interval = if ($RunSchedule.interval) { $RunSchedule.interval } else { "1" }
            $useUtc = if ($null -ne $RunSchedule.useUtc) { $RunSchedule.useUtc } else { "N/A" }
            return "Hourly | Every $interval hour(s) | UTC: $useUtc"
        }
        "deviceHealthScriptWeeklySchedule" {
            $interval = if ($RunSchedule.interval) { $RunSchedule.interval } else { "1" }
            $time = if ($RunSchedule.time) { $RunSchedule.time } else { "N/A" }
            $day = if ($RunSchedule.dayOfWeek) { $RunSchedule.dayOfWeek } else { "N/A" }
            $useUtc = if ($null -ne $RunSchedule.useUtc) { $RunSchedule.useUtc } else { "N/A" }
            return "Weekly | Every $interval week(s) | Day: $day | Time: $time | UTC: $useUtc"
        }
        default {
            return "Other schedule type ($odataType): $($RunSchedule | ConvertTo-Json -Compress -Depth 10)"
        }
    }
}

#-----------------------------------------
# Main: Retrieve remediation scripts
#-----------------------------------------
$baseUrl = "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"
Write-Host "[$(Get-Date -Format 'u')] Retrieving remediation scripts from Intune..." -ForegroundColor Yellow

try {
    $scriptsResponse = Invoke-MgGraphRequest -Uri $baseUrl -Method GET
}
catch {
    Write-Error "Failed to retrieve remediation scripts. $_"
    return
}

if (-not $scriptsResponse.value) {
    Write-Host "[$(Get-Date -Format 'u')] No remediation scripts found." -ForegroundColor Yellow
    return
}

$totalScripts = $scriptsResponse.value.Count
Write-Host "[$(Get-Date -Format 'u')] Found $totalScripts remediation script(s)." -ForegroundColor Green

$report = New-Object System.Collections.Generic.List[object]
$scriptCounter = 0

foreach ($script in $scriptsResponse.value) {
    $scriptCounter++
    $scriptId = $script.id
    $scriptName = $script.displayName
    $scriptDescription = $script.description

    Write-Host "[$(Get-Date -Format 'u')] [$scriptCounter/$totalScripts] Checking script: '$scriptName'" -ForegroundColor Cyan

    $scriptAssignmentsUrl = "$baseUrl/$scriptId/assignments"

    try {
        $assignmentsResponse = Invoke-MgGraphRequest -Uri $scriptAssignmentsUrl -Method GET
        $assignments = $assignmentsResponse.value
    }
    catch {
        Write-Warning "Could not get assignments for script '$scriptName' ($scriptId)."
        $assignments = @()
    }

    if (-not $assignments -or $assignments.Count -eq 0) {
        Write-Host "[$(Get-Date -Format 'u')]    -> No assignments found." -ForegroundColor DarkYellow

        $report.Add([PSCustomObject]@{
            ScriptName           = $scriptName
            ScriptId             = $scriptId
            Description          = $scriptDescription
            Publisher            = $script.publisher
            Version              = $script.version
            CreatedDateTime      = $script.createdDateTime
            LastModifiedDateTime = $script.lastModifiedDateTime
            AssignmentId         = ""
            AssignmentTargetType = "Unassigned"
            AssignmentGroupId    = ""
            AssignmentGroupName  = ""
            AssignmentIntent     = ""
            AssignmentFilterType = ""
            AssignmentFilterId   = ""
            ScheduleType         = ""
            ScheduleSummary      = "Not assigned"
        })
        continue
    }

    Write-Host "[$(Get-Date -Format 'u')]    -> Found $($assignments.Count) assignment(s)." -ForegroundColor Green

    foreach ($a in $assignments) {
        $target = $a.target
        $targetType = $target.'@odata.type'

        $groupId = ""
        $groupName = ""
        $intent = ""
        $filterType = ""
        $filterId = ""

        if ($target.deviceAndAppManagementAssignmentFilterType) {
            $filterType = $target.deviceAndAppManagementAssignmentFilterType
        }
        if ($target.deviceAndAppManagementAssignmentFilterId) {
            $filterId = $target.deviceAndAppManagementAssignmentFilterId
        }

        if ($targetType -match "groupAssignmentTarget") {
            $groupId = $target.groupId
            if ($groupId) { $groupName = Get-GroupDisplayNameSafe -GroupId $groupId }
        }

        if ($target.intent) { $intent = $target.intent }

        $scheduleType = ""
        $scheduleSummary = "Not specified"

        if ($a.runSchedule) {
            $scheduleType = $a.runSchedule.'@odata.type'
            $scheduleSummary = Get-ScheduleSummary -RunSchedule $a.runSchedule
        }

        $report.Add([PSCustomObject]@{
            ScriptName           = $scriptName
            ScriptId             = $scriptId
            Description          = $scriptDescription
            Publisher            = $script.publisher
            Version              = $script.version
            CreatedDateTime      = $script.createdDateTime
            LastModifiedDateTime = $script.lastModifiedDateTime
            AssignmentId         = $a.id
            AssignmentTargetType = $targetType
            AssignmentGroupId    = $groupId
            AssignmentGroupName  = $groupName
            AssignmentIntent     = $intent
            AssignmentFilterType = $filterType
            AssignmentFilterId   = $filterId
            ScheduleType         = $scheduleType
            ScheduleSummary      = $scheduleSummary
        })
    }
}

#-----------------------------------------
# Output section
#-----------------------------------------
Write-Host "[$(Get-Date -Format 'u')] Preparing final report output..." -ForegroundColor Yellow

$reportSorted = $report | Sort-Object ScriptName, AssignmentGroupName

$reportSorted | Format-Table -AutoSize

Write-Host "[$(Get-Date -Format 'u')] Total output rows: $($reportSorted.Count)" -ForegroundColor Green

if ($GridView) {
    Write-Host "[$(Get-Date -Format 'u')] Opening Out-GridView..." -ForegroundColor Yellow
    $reportSorted | Out-GridView -Title "Intune Remediation Scripts Assignments"
}

if ($CSV) {
    $csvFolder = Split-Path -Path $CsvPath -Parent
    if (-not (Test-Path -Path $csvFolder)) {
        Write-Host "[$(Get-Date -Format 'u')] CSV folder does not exist. Creating: $csvFolder" -ForegroundColor Yellow
        New-Item -Path $csvFolder -ItemType Directory -Force | Out-Null
    }

    Write-Host "[$(Get-Date -Format 'u')] Exporting CSV to: $CsvPath" -ForegroundColor Yellow
    $reportSorted | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "[$(Get-Date -Format 'u')] CSV export complete." -ForegroundColor Green
}

Write-Host "[$(Get-Date -Format 'u')] Script finished successfully." -ForegroundColor Cyan