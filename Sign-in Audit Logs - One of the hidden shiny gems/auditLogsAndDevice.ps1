# Ensure the directory exists
$logDirectory = "C:\Temp"
if (!(Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
}

# Start transcript to capture console output to a file
Start-Transcript -Path "C:\Temp\AuditLogsDevices.log" -Append

try {
    ###############################################################################
    # Connect to Microsoft Graph
    ###############################################################################
    Connect-MgGraph -Scopes "AuditLog.Read.All"

    ###############################################################################
    # Prepare the DataTable
    ###############################################################################
    $table = New-Object System.Data.DataTable
    $table.Columns.Add("DeviceName")        | Out-Null
    $table.Columns.Add("DeviceID")          | Out-Null
    $table.Columns.Add("IsManaged")         | Out-Null
    $table.Columns.Add("SignInTime")        | Out-Null
    $table.Columns.Add("UserPrincipalName") | Out-Null
    $table.Columns.Add("AppDisplayName")    | Out-Null
    $table.Columns.Add("TokenIssuerType")   | Out-Null
    $table.Columns.Add("IsInteractive")     | Out-Null

    ###############################################################################
    # Define the single device name (adjust as needed)
    ###############################################################################
    $deviceName = "DeviceName"

    ###############################################################################
    # Retrieve sign-in logs for the last 30 days for this one device
    # Using server-side filter to be more efficient
    ###############################################################################
    $since = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "`nFetching sign-ins from the last 30 days for device: $deviceName"

    # Note: 'contains(...)' + 'tolower(...)' helps match partial/case-insensitive device names.
    $signInLogs = Get-MgAuditLogSignIn -All `
        -Filter "createdDateTime ge $since and contains(tolower(deviceDetail/displayName), '$($deviceName.ToLower())')" `
        | Select-Object `
            CreatedDateTime,
            UserPrincipalName,
            AppDisplayName,
            IsInteractive,
            TokenIssuerType,
            @{
                Name       = 'DeviceId'
                Expression = { $_.DeviceDetail.DeviceId }
            },
            @{
                Name       = 'DeviceName'
                Expression = { $_.DeviceDetail.DisplayName }
            },
            @{
                Name       = 'IsManaged'
                Expression = { $_.DeviceDetail.IsManaged }
            }

    Write-Host "Total sign-ins retrieved for device '$deviceName': $($signInLogs.Count)"

    ###############################################################################
    # Populate the DataTable with the sign-in details
    ###############################################################################
    if ($signInLogs -and $signInLogs.Count -gt 0) {
        foreach ($log in $signInLogs) {
            $row = $table.NewRow()
            $row["DeviceName"]        = $log.DeviceName
            $row["DeviceID"]          = $log.DeviceId
            $row["IsManaged"]         = $log.IsManaged
            $row["SignInTime"]        = $log.CreatedDateTime
            $row["UserPrincipalName"] = $log.UserPrincipalName
            $row["AppDisplayName"]    = $log.AppDisplayName
            $row["TokenIssuerType"]   = $log.TokenIssuerType
            $row["IsInteractive"]     = $log.IsInteractive
            $table.Rows.Add($row)
        }
    }
    else {
        Write-Host "No sign-in logs found for device: $deviceName"
    }

    ###############################################################################
    # Display the results
    ###############################################################################
    Write-Host "`n=== Final Table of Device Sign-Ins ==="
    $table  # Shows the DataTable on screen in the console

    # Display in a separate GridView window (useful for interactive inspection)
    $table | Out-GridView -Title "Device Sign-Ins"

    # Export to CSV if desired:
    $table | Export-Csv -Path "C:\Temp\DeviceSignIns.csv" -NoTypeInformation
    Write-Host "Exported results to C:\Temp\DeviceSignIns.csv"

} finally {
    # Stop transcript to end console logging
    Stop-Transcript
}