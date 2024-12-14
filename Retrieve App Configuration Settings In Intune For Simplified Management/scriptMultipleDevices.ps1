# Connect to Microsoft Graph
Connect-MgGraph

# Path to the file containing Device IDs
$deviceIDFile = "C:\Temp\deviceIntuneIDs.txt"

# Define the Policy ID
$policyID = "079f6ffa-77ff-4e59-90c8-3758418972bc"

# Define request headers
$headers = @{
    "Referer" = ""
    "Accept-Language" = "en"
    "X-Content-Type-Options" = "nosniff"
    "Accept" = "*/*"
    "x-ms-effective-locale" = "en.en-us"
}

# Read all Device IDs from the file into an array
$deviceIDs = Get-Content -Path $deviceIDFile

# Create an empty array to hold the final custom objects
$dataArray = @()

# Loop through each Device ID
foreach ($deviceID in $deviceIDs) {
    Write-Host "Processing Device ID: $deviceID" -ForegroundColor Cyan

    # Define the request body as a PowerShell object
    $bodyObject = @{
        select   = @()
        filter   = "(PolicyId eq '$policyID') and (DeviceId eq '$deviceID') and (UserId eq '00000000-0000-0000-0000-000000000000')"
        top      = 50
        orderBy  = @("SettingName")
    }

    # Convert the PowerShell object to JSON
    $bodyJson = $bodyObject | ConvertTo-Json -Depth 3 -Compress

    # Define request method, content type, and URI
    $method = "POST"
    $contentType = "application/json"
    $uri = "https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationSettingNonComplianceReport"

    # Invoke the request using Microsoft Graph API
    $response = Invoke-MgGraphRequest -Method $method -Uri $uri -Body $bodyJson -ContentType $contentType #-Headers $headers

    # Loop through each item in the 'Values' property of the response
    foreach ($item in $response.values) {
        Write-Host $item -ForegroundColor Yellow

        # Create a custom object with properties corresponding to the columns
        $customObject = New-Object -TypeName PSObject -Property @{
            SettingStatus = $item[8]
            ErrorType     = $item[9]
            ErrorCode     = $item[10]
            SettingName   = $item[12]
            ErrorMessage  = $item[11]
            DeviceID      = $deviceID
        }

        # Add the custom object to the array
        $dataArray += $customObject
        Write-Host "-------" -ForegroundColor Blue
    }
}

# Export the array to a CSV file
$dataArray | Export-Csv -Path 'output.csv' -NoTypeInformation

# Optionally, display the data in a grid view
$dataArray | Out-GridView
