# Connect to Microsoft Graph using the current account's credentials.
# This establishes a session with Microsoft Graph to allow API requests.
Connect-MgGraph

# Define the Device ID and Policy ID for which the compliance data will be queried.
# These values act as filters in the API request to narrow down the results.
$deviceID = "fe7f320b-610f-456a-ac9d-c9cd9e9d8e1e"
$policyID = "079f6ffa-77ff-4e59-90c8-3758418972bc"

# Define custom request headers to control the behavior of the HTTP request.
# Headers include metadata like accepted content types and localization preferences.
$headers = @{
    "Referer" = ""                            # Empty Referer header (can be omitted if unnecessary)
    "Accept-Language" = "en"                  # Set the language preference to English
    "X-Content-Type-Options" = "nosniff"      # Prevent MIME type sniffing
    "Accept" = "*/*"                          # Allow any content type to be accepted
    "x-ms-effective-locale" = "en.en-us"      # Set the locale to English (US)
}

# Define the request body as a PowerShell object.
# This object specifies the query parameters for the API call:
# - 'filter': Filters data based on PolicyId, DeviceId, and UserId
# - 'top': Limits the result set to 50 items
# - 'orderBy': Sorts the results by 'SettingName'.
$bodyObject = @{
    select   = @()  # Empty 'select' property to retrieve all available fields
    filter   = "(PolicyId eq '$policyID') and (DeviceId eq '$deviceID') and (UserId eq '00000000-0000-0000-0000-000000000000')"
    top      = 50   # Limit the response to 50 records
    orderBy  = @("SettingName")  # Sort the results by SettingName
}

# Convert the PowerShell object to a JSON string as required by the Microsoft Graph API.
# The JSON format is necessary for the request body in the HTTP POST call.
$bodyJson = $bodyObject | ConvertTo-Json -Depth 3 -Compress

# Define the HTTP request parameters:
# - 'POST' is the HTTP method used to send data.
# - 'application/json' is the content type of the request body.
# - The URI is the endpoint for the non-compliance report.
$method = "POST"
$contentType = "application/json"
$uri = "https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationSettingNonComplianceReport"

# Send the HTTP request to the Microsoft Graph API and store the response.
# - The body is passed in JSON format.
# - The content type specifies that the body is JSON.
$response = Invoke-MgGraphRequest -Method $method -Uri $uri -Body $bodyJson -ContentType $contentType #-Headers $headers

# Create an empty array to store custom objects that will represent the report data.
$dataArray = @()

# Loop through each item in the 'Values' property of the response.
# The 'Values' property is an array of rows returned from the API query.
foreach ($item in $response.values) {
    # Output the current item to the console for debugging or informational purposes.
    Write-Host $item -ForegroundColor Yellow

    # Create a custom PowerShell object with properties corresponding to relevant fields.
    # The 'item' array contains data in a specific order; we use indexes to map it.
    $customObject = New-Object -TypeName PSObject -Property @{
        SettingStatus = $item[8]    # Index 8: Status of the setting
        ErrorType     = $item[9]    # Index 9: Type of the error
        ErrorCode     = $item[10]   # Index 10: Specific error code
        SettingName   = $item[12]   # Index 12: Name of the setting
        ErrorMessage  = $item[11]   # Index 11: Detailed error message
        DeviceID      = $deviceID   # Add the Device ID as part of the output for reference
    }

    # Add the custom object to the data array.
    $dataArray += $customObject

    # Output a separator line to the console for better readability.
    Write-Host "-------" -ForegroundColor Blue
}

# Export the data array (containing all custom objects) to a CSV file named 'output.csv'.
# -NoTypeInformation ensures that no type metadata is added to the CSV file.
$dataArray | Export-Csv -Path 'output.csv' -NoTypeInformation

# Optionally, display the results in an interactive grid view for easy analysis.
# 'Out-GridView' provides a user-friendly table display in PowerShell.
$dataArray | Out-GridView
