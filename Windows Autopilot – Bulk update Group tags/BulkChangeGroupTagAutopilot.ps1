# Install-Module -Name Microsoft.Graph
# Install-Module -Name WindowsAutoPilotIntune
# Be sure to have the correct permissions to perform Autopilot related operations

Connect-MgGraph

# Specify the new group tag here
$Grouptag = "NewGroupTag" 

# Get the serial numbers of the devices that we want to change group tag
$serialsTXTFilePathLocation = Read-Host "Enter the txt path location containing the serial numbers:"
$serials = Get-Content -Path $serialsTXTFilePathLocation

foreach($serial in $serials)
{
    Write-Host "Changing Group tag for: $serial"
    Get-AutopilotDevice -serial $serial | Set-AutopilotDevice -groupTag $Grouptag
}