# Import the Microsoft Graph module - if required
# Import-Module Microsoft.Graph

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All"

# Function to get user details by UPN
function Get-EntraUserDetails {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserPrincipalName
    )

    try {
        # Retrieve the user details from Microsoft Entra ID (Azure AD)
        $user = Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'"
        
        if ($user) {
            # Return the user details as an object
            return [PSCustomObject]@{
                DisplayName      = $user.DisplayName
                UserPrincipalName = $user.UserPrincipalName
                Mail             = $user.Mail
                JobTitle         = $user.JobTitle
                Department       = $user.Department
                MobilePhone      = $user.MobilePhone
                AccountEnabled   = $user.AccountEnabled
                Status           = "Found"
            }
        } else {
            # Return an object indicating the user was not found
            return [PSCustomObject]@{
                DisplayName      = ""
                UserPrincipalName = $UserPrincipalName
                Mail             = ""
                JobTitle         = ""
                Department       = ""
                MobilePhone      = ""
                AccountEnabled   = ""
                Status           = "Not Found"
            }
        }
    } catch {
        # Handle errors and return an object indicating the error
        return [PSCustomObject]@{
            DisplayName      = ""
            UserPrincipalName = $UserPrincipalName
            Mail             = ""
            JobTitle         = ""
            Department       = ""
            MobilePhone      = ""
            AccountEnabled   = ""
            Status           = "Error: $_"
        }
    }
}

# Define the input and output file paths
$inputFile = "C:\Temp\userUPNs.txt"  # Path to the input text file containing UPNs
$outputFile = "C:\Temp\UserDetails.csv"  # Path to the output CSV file

# Check if the input file exists
if (-Not (Test-Path $inputFile)) {
    Write-Host "Input file '$inputFile' not found. Please provide a valid file path." -ForegroundColor Red
    exit
}

# Read UPNs from the input file
$userUPNs = Get-Content -Path $inputFile

# Initialize an array to store the results
$resultList = @()

# Loop through each UPN and get user details
foreach ($upn in $userUPNs) {
    Write-Host "Processing UPN: $upn" -ForegroundColor Yellow
    $result = Get-EntraUserDetails -UserPrincipalName $upn
    $resultList += $result

    # Print each user record to the screen
    Write-Host "User Details for $upn :"
    Write-Host "Display Name: $($result.DisplayName)"
    Write-Host "UPN: $($result.UserPrincipalName)"
    Write-Host "Mail: $($result.Mail)"
    Write-Host "Job Title: $($result.JobTitle)"
    Write-Host "Department: $($result.Department)"
    Write-Host "Mobile Phone: $($result.MobilePhone)"
    Write-Host "Account Enabled: $($result.AccountEnabled)"
    Write-Host "Status: $($result.Status)"
    Write-Host "----------------------------------------"
}

# Export the results to a CSV file
$resultList | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "User details have been exported to '$outputFile'." -ForegroundColor Green