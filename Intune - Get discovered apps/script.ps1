Connect-MSGraph

# enter device name
$device = "DESKTOP-22V7417"

# get the device Intune ID
$IntuneID = (Get-IntuneManagedDevice -Filter "deviceName eq '$device'" | select id).id
# Graph api url to get discovered apps
$discoveredAppsUrl = "https://graph.microsoft.com/beta/deviceManagement/manageddevices('$IntuneID')/detectedApps?filter=&top=50"

# perform the request
$apps = Invoke-MSGraphRequest -Url $discoveredAppsUrl -HttpMethod GET
# get all pages returned
$appsNextLink = $apps.'@odata.nextLink'
$allApps = $apps.value

while ($appNextLink){
    $apps = Invoke-MSGraphRequest -Url $appNextLink -HttpMethod GET
    $appsNextLink = $apps.'@odata.nextLink'
    $allApps += $apps.value
}

# iterate through the applications and print them
foreach ($app in $allApps){
    Write-Host $app.displayName
}