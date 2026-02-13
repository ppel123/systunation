# Get ASR block events from the last 7 days
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Windows Defender/Operational'
    ID = 1122
    StartTime = (Get-Date).AddDays(-7)
} -ErrorAction SilentlyContinue

if ($events) {
    # Parse and group events by rule
    $summary = $events | ForEach-Object {
        $xmlData = [xml]$_.ToXml()
        $ruleId = $xmlData.Event.EventData.Data | Where-Object {$_.Name -eq 'ID'} | Select-Object -ExpandProperty '#text'
        $fileName = $xmlData.Event.EventData.Data | Where-Object {$_.Name -eq 'Path'} | Select-Object -ExpandProperty '#text'
        
        [PSCustomObject]@{
            Time = $_.TimeCreated
            RuleID = $ruleId
            BlockedFile = $fileName
        }
    } | Group-Object RuleID | Select-Object Name, Count
    
    Write-Host "`nASR Block Summary (Last 7 Days):" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize
    Write-Host "`nTotal Blocks: $($events.Count)" -ForegroundColor Green
} else {
    Write-Host "No ASR block events found in the last 7 days." -ForegroundColor Yellow
}
