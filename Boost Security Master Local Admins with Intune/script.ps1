# PowerShell Script to Detect Local Administrators and Azure AD Admins on a Windows Device

# Get the local Administrators group members
$localAdmins = Get-LocalGroupMember -Group "Administrators" | Select-Object Name, PrincipalSource

# Initialize an array to hold formatted output
$output = @()

foreach ($admin in $localAdmins) {
    # Check if the account is an Azure AD account
    if ($admin.PrincipalSource -eq "AzureAD") {
        $type = "Azure AD User"
    } else {
        $type = "Local User"
    }
    
    # Format the output
    $output += "Type: $type, Name: $($admin.Name) || "
}

# Return the list of local administrators
Write-Host $output