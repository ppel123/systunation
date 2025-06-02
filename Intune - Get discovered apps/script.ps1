Connect-MGGraph

# enter device name
$device = "YourDeviceName"

# get the device Intune ID
$IntuneID = (Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$device'" | select id).id
# Graph api url to get discovered apps
$discoveredAppsUrl = "https://graph.microsoft.com/beta/deviceManagement/manageddevices('$IntuneID')/detectedApps?filter=&top=50"

# perform the request
$apps = Invoke-MgGraphRequest -Method GET -Uri $discoveredAppsUrl

$appsNextLink = $apps.'@odata.nextLink'
$allApps = $apps.value

while ($appNextLink){
    $apps = Invoke-MgGraphRequest -Method GET -Uri $appNextLink
    $appsNextLink = $apps.'@odata.nextLink'
    $allApps += $apps.value
}

# iterate through the applications and print them
foreach ($app in $allApps){
    Write-Host $app.displayName
}
