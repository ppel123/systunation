#=====================================================================
# Import Users to Entra ID Group via Microsoft Graph API
# Blog  : systunation.com
# Author: Paris
# Notes : Reads UPNs from a text file and adds them to an Entra ID
#         group one by one. Skips users who are already members.
#=====================================================================

#-----------------------------------------
# Settings - edit before running
#-----------------------------------------
$InputTxtPath = "C:\Temp\usr.txt"    # One UPN per line
$GroupName    = "TestUserGroup"   # Target Entra ID group display name
# $GroupId    = ""                   # Uncomment and set to use Object ID directly

#-----------------------------------------
# Prerequisites
#-----------------------------------------
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Import Users to Entra ID Group                     " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

try {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
        Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Yellow
        Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
    }
} catch {
    Write-Host "Failed to install Microsoft.Graph module: $_" -ForegroundColor Red
    exit
}

#-----------------------------------------
# Connect to Microsoft Graph
#-----------------------------------------
try {
    Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All" -NoWelcome -ErrorAction Stop
    Write-Host "Connected to Microsoft Graph" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "Failed to connect to Microsoft Graph: $_" -ForegroundColor Red
    exit
}

#-----------------------------------------
# Resolve target group
#-----------------------------------------
try {
    if ($GroupId) {
        $resolvedGroupId = $GroupId
    } elseif ($GroupName) {
        $match = Get-MgGroup -Filter "displayName eq '$($GroupName -replace "'", "''")'" -ConsistencyLevel eventual -ErrorAction Stop
        if     ($match.Count -eq 0) { throw "No group found: '$GroupName'" }
        elseif ($match.Count -gt 1) { throw "Multiple groups named '$GroupName'. Use -GroupId instead." }
        $resolvedGroupId = $match.Id
        Write-Host "Group resolved: '$GroupName' ($resolvedGroupId)" -ForegroundColor Green
        Write-Host ""
    } else {
        throw "Provide either -GroupId or -GroupName."
    }
} catch {
    Write-Host "Failed to resolve group: $_" -ForegroundColor Red
    exit
}

#-----------------------------------------
# Read UPNs from file
#-----------------------------------------
try {
    if (-not (Test-Path $InputTxtPath)) { throw "File not found: $InputTxtPath" }

    $upns = Get-Content $InputTxtPath -ErrorAction Stop |
            ForEach-Object { $_.Trim() } |
            Where-Object   { $_ -ne '' } |
            Select-Object  -Unique

    Write-Host "$($upns.Count) UPN(s) loaded from file." -ForegroundColor Cyan
    Write-Host ""
} catch {
    Write-Host "Failed to read input file: $_" -ForegroundColor Red
    exit
}

#-----------------------------------------
# Add members one by one
#-----------------------------------------
$added   = 0
$skipped = 0
$failed  = 0

foreach ($upn in $upns) {
    try {
        $user = Get-MgUser -UserId $upn -ErrorAction Stop

        # Skip if already a member
        $isMember = Get-MgGroupMember -GroupId $resolvedGroupId -Filter "id eq '$($user.Id)'" -ErrorAction SilentlyContinue
        if ($isMember) {
            Write-Host "SKIP  $upn (already a member)" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        New-MgGroupMember -GroupId $resolvedGroupId -DirectoryObjectId $user.Id -ErrorAction Stop
        Write-Host "OK    $upn" -ForegroundColor Green
        $added++
    } catch {
        Write-Host "FAIL  $upn — $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

#-----------------------------------------
# Summary
#-----------------------------------------
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  Added     : $added" -ForegroundColor Green
Write-Host "  Skipped   : $skipped" -ForegroundColor DarkGray
Write-Host "  Failed    : $failed" -ForegroundColor Red
Write-Host "=====================================================" -ForegroundColor Cyan
