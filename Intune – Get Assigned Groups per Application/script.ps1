Connect-MSGraph

# url to get the desired apps. In this example all apps assigned to Windows devices are selected.
$url = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?"+'$filter'+"=(isof(%27microsoft.graph.windowsStoreApp%27)%20or%20isof(%27microsoft.graph.microsoftStoreForBusinessApp%27)%20or%20isof(%27microsoft.graph.officeSuiteApp%27)%20or%20isof(%27microsoft.graph.win32LobApp%27)%20or%20isof(%27microsoft.graph.windowsMicrosoftEdgeApp%27)%20or%20isof(%27microsoft.graph.windowsPhone81AppX%27)%20or%20isof(%27microsoft.graph.windowsPhone81StoreApp%27)%20or%20isof(%27microsoft.graph.windowsPhoneXAP%27)%20or%20isof(%27microsoft.graph.windowsAppX%27)%20or%20isof(%27microsoft.graph.windowsMobileMSI%27)%20or%20isof(%27microsoft.graph.windowsUniversalAppX%27)%20or%20isof(%27microsoft.graph.webApp%27)%20or%20isof(%27microsoft.graph.windowsWebApp%27)%20or%20isof(%27microsoft.graph.winGetApp%27))%20and%20(microsoft.graph.managedApp/appAvailability%20eq%20null%20or%20microsoft.graph.managedApp/appAvailability%20eq%20%27lineOfBusiness%27%20or%20isAssigned%20eq%20true)&$orderby=displayName&"
$apps = (Invoke-MSGraphRequest -Url "$url" -HttpMethod Get).Value

# create a new table object to present the results
$table = New-Object System.Data.DataTable

$table.Columns.Add("ApplicationName") | Out-Null
$table.Columns.Add("ApplicationID") | Out-Null
$table.Columns.Add("GroupName") | Out-Null
$table.Columns.Add("GroupID") | Out-Null

# iterate through all apps and get assignments
foreach ($app in $apps){
    # for each app get the app name and id
    $appID = $app.id
    $appDisplayName = $app.displayName
    # create the Graph API url to get the groups assigned to each application
    $assignmentUrl = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appID/?"+'$expand'+"=categories,assignments"
    $assignments = (Invoke-MSGraphRequest -Url "$assignmentUrl" -HttpMethod Get)

    # iterate through all assigned groups
    foreach ($assignment in $assignments){
        $assignedGroupsIDs = $assignments.assignments.target
        foreach ($group in $assignedGroupsIDs){
            $groupID = $group.groupId
            # create the Graph API url and get the group name
            $groupUrl = "https://graph.microsoft.com/beta/groups/$groupID"
            $groupDetails = (Invoke-MSGraphRequest -Url "$groupUrl" -HttpMethod Get)
            $groupName = $groupDetails.displayName
            $table.Rows.Add($appDisplayName, $appID, $groupName, $groupID)
        }
    }
}

# display the results and export a csv
$table | Out-GridView
$table | Export-Csv -Path "C:\Users\Public\AppsAndGroups.csv" -Delimiter "," -Encoding UTF8 -NoTypeInformation -NoClobber
