# Devices whose password has not been backed up in the last N days.
# Useful during Ring 1/2 to catch devices silently not rotating
# (most commonly: disabled in Entra ID).
#
# Note the two timestamps mean opposite things:
#   LastBackupDateTime - when the credential WAS backed up (past)
#   RefreshDateTime    - when it WILL next be refreshed (future)
# Filter on LastBackupDateTime for staleness.
# Reference: https://learn.microsoft.com/en-us/graph/api/resources/devicelocalcredentialinfo

# Requires DeviceLocalCredential.ReadBasic.All (metadata only - no passwords)
Connect-MgGraph -Scopes 'DeviceLocalCredential.ReadBasic.All'

$thresholdDays = 14
$stale = Get-MgDirectoryDeviceLocalCredential -All |
    Where-Object { $_.LastBackupDateTime -lt (Get-Date).AddDays(-$thresholdDays) }

if ($stale) {
    $stale | Select-Object DeviceName, LastBackupDateTime, RefreshDateTime
} else {
    Write-Host "No stale devices - all LAPS credentials backed up within $thresholdDays days." -ForegroundColor Green
}