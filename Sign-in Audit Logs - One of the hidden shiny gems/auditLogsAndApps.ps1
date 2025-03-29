# Ensure the directory exists
$logDirectory = "C:\Temp"
if (!(Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory | Out-Null
}

# Start transcript to capture console output to a file
Start-Transcript -Path "C:\Temp\AuditLogsSingleApp.log" -Append

try {
    ###############################################################################
    # Connect to Microsoft Graph
    ###############################################################################
    Connect-MgGraph -Scopes "AuditLog.Read.All"

    ###############################################################################
    # Prepare the DataTable
    ###############################################################################
    $table = New-Object System.Data.DataTable
    $table.Columns.Add("AppName")           | Out-Null
    $table.Columns.Add("SignInTime")        | Out-Null
    $table.Columns.Add("UserPrincipalName") | Out-Null
    $table.Columns.Add("IsInteractive")     | Out-Null
    $table.Columns.Add("DeviceName")        | Out-Null
    $table.Columns.Add("IsManaged")         | Out-Null
    $table.Columns.Add("TokenIssuerType")   | Out-Null

    ###############################################################################
    # Define the single app name you want to search for
    ###############################################################################
    $appName = "Windows Sign In"

    ###############################################################################
    # Retrieve ALL sign-in logs for a specified time window
    # Adjust the date range as needed, e.g. last 30 days
    ###############################################################################
    $since = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
    Write-Host "`nFetching all sign-ins from the last 30 days... (This might take a while.)"

    $allSignInLogs = Get-MgAuditLogSignIn -All `
        -Filter "createdDateTime ge $since" `
        | Select-Object `
            CreatedDateTime,
            UserPrincipalName,
            AppDisplayName,
            IsInteractive,
            TokenIssuerType,
            @{
                Name       = 'DeviceName'
                Expression = { $_.DeviceDetail.DisplayName }
            },
            @{
                Name       = 'IsManaged'
                Expression = { $_.DeviceDetail.IsManaged }
            }

    Write-Host "Total sign-ins retrieved: $($allSignInLogs.Count)"

    ###############################################################################
    # Filter the sign-ins locally for the specified app
    ###############################################################################
    Write-Host "`n=== Searching sign-in logs for app: $appName ==="

    $appSignInLogs = $allSignInLogs | Where-Object {
        $_.AppDisplayName -and ($_.AppDisplayName -like "*$appName*")
    }

    if ($appSignInLogs -and $appSignInLogs.Count -gt 0) {
        Write-Host "Found $($appSignInLogs.Count) sign-ins for app: $appName"
        foreach ($log in $appSignInLogs) {
            $row = $table.NewRow()
            $row["AppName"]           = $log.AppDisplayName
            $row["SignInTime"]        = $log.CreatedDateTime
            $row["UserPrincipalName"] = $log.UserPrincipalName
            $row["IsInteractive"]     = $log.IsInteractive
            $row["DeviceName"]        = $log.DeviceName
            $row["IsManaged"]         = $log.IsManaged
            $row["TokenIssuerType"]   = $log.TokenIssuerType
            $table.Rows.Add($row)
        }
    }
    else {
        Write-Host "No sign-in logs found for app: $appName"
    }

    ###############################################################################
    # Display the results
    ###############################################################################
    Write-Host "`n=== Final Table of App Sign-Ins ==="
    $table  # Shows the DataTable on screen in the console

    # Display in a separate GridView window (useful for interactive inspection)
    $table | Out-GridView -Title "App Sign-Ins"

    # Export to CSV if desired:
    $table | Export-Csv -Path "C:\Temp\SingleAppSignIns.csv" -NoTypeInformation
    Write-Host "Exported results to C:\Temp\SingleAppSignIns.csv"

} finally {
    # Stop transcript to end console logging
    Stop-Transcript
}