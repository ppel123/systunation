# Set the Group Name here
$GroupName = "your-group-name-here"  # Replace with the actual Group Display Name

# Connect to Microsoft Graph (ensure you have the necessary permissions)
Connect-MgGraph

Write-Host "=== Empty Group Members Starting ===" -ForegroundColor Cyan

try {
    # Resolve the group ID from the display name
    Write-Host "Resolving group: $GroupName" -ForegroundColor Cyan
    $group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop
    
    if ($null -eq $group) {
        Write-Error "Group '$GroupName' not found."
        return
    }
    
    $GroupID = $group.Id
    Write-Host "Found group ID: $GroupID" -ForegroundColor Green

    # Fetch group members
    Write-Host "Fetching group members..." -ForegroundColor Cyan
    $members = Get-MgGroupMember -GroupId $GroupID -All -ErrorAction Stop
    
    if ($null -eq $members -or $members.Count -eq 0) {
        Write-Host "Group is already empty." -ForegroundColor Green
        return
    }
    
    $totalMembers = $members.Count
    Write-Host "Found $totalMembers members to remove." -ForegroundColor Yellow
    
    $counter = 0
    foreach ($member in $members) {
        $counter++
        $memberId = $member.Id
        $displayName = if ($member.AdditionalProperties.ContainsKey("displayName")) { $member.AdditionalProperties["displayName"] } else { $memberId }
        $type = if ($member.AdditionalProperties.ContainsKey("@odata.type")) { $member.AdditionalProperties["@odata.type"] } else { "Unknown" }
        
        Write-Host "[$counter/$totalMembers] Removing member: $displayName ($type)..." -NoNewline
        
        try {
            Remove-MgGroupMemberByRef -GroupId $GroupID -DirectoryObjectId $memberId -ErrorAction Stop
            Write-Host " [OK]" -ForegroundColor Green
        }
        catch {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    Write-Host "Empty group operation completed." -ForegroundColor Cyan
}
catch {
    Write-Error "Error: $($_.Exception.Message)"
}
