# Start transcript to log output to a file
Start-Transcript -Path "C:\Users\Public\LastLoggedInUser.txt"

# Display message indicating connection to Microsoft Graph
Write-Host "$(Get-Date) Connecting to Graph"

# Connect to Microsoft Graph with specific permissions
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All, Device.Read.All, User.Read.All"

# Display message indicating reading device list to obtain last logged in user
# The device list is expected to be in a .txt file with Intune Device IDs
$devices = Get-Content -Path "C:\Users\Public\DevicesIntuneIDs.txt"

# Loop through each Intune Device ID to fetch device and user information
foreach ($deviceIntuneID in $devices){
    # Display message indicating fetching information about the managed device
    Write-Host "$(Get-Date) Getting wanted information about the managed device"

    # Retrieve device information based on Intune Device ID
    $deviceInfo = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $deviceIntuneID | Select-Object Id, AzureAdDeviceId, DeviceName, EmailAddress, UserPrincipalName, UserDisplayName

    # Display message indicating fetching last logged in user information using Graph API
    Write-Host "$(Get-Date) Getting the last logged in user information calling Graph API"

    # Construct URL for calling Graph API to retrieve last logged in user information
    $url = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($deviceInfo.Id)"
    $lastLoggedInUserInfo = (Invoke-MgGraphRequest -Method Get $url).usersLoggedon

    # Display message indicating fetching further information about the user
    Write-Host "$(Get-Date) Getting further information about the user"

    # Retrieve user details based on user ID obtained from Graph API
    $userDetails = Get-MgUser -All -Filter "Id eq '$($lastLoggedInUserInfo.userId)'"

    # Display last user connected to the device along with relevant details
    Write-Host "Last user connected to the device $($deviceInfo.DeviceName) with Intune Device ID $($deviceInfo.Id) is $($userDetails.DisplayName) with ID $($userDetails.Id) on $($lastLoggedInUserInfo.lastLogOnDateTime)" -ForegroundColor Yellow
}

# Stop transcript logging
Stop-Transcript
