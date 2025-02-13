# Install-Module -Name Microsoft.Graph
# Install-Module -Name WindowsAutoPilotIntune
# Be sure to have the correct permissions to perform Autopilot related operations

Connect-MgGraph

# Specify the new group tag here
$Grouptag = "NewGroupTag" 

# Start transcript to log the output
$logFilePath = "C:\Temp\autopilot_updates.log"
Start-Transcript -Path $logFilePath

# Get the serial numbers of the devices that we want to change group tag
$serialsTXTFilePathLocation = Read-Host "Enter the txt path location containing the serial numbers:"

# Validate if the file exists
if (-Not (Test-Path $serialsTXTFilePathLocation)) {
    Write-Host "File not found. Please check the path."
    exit
}

$serials = Get-Content -Path $serialsTXTFilePathLocation

foreach($serial in $serials)
{
    Write-Host "Changing Group tag for: $serial"
    
    try {
        $autopilotDeviceInfo = Get-AutopilotDevice -serial $serial
        Set-AutopilotDevice -id $autopilotDeviceInfo.id -groupTag $Grouptag
        Write-Host "Successfully updated group tag for device: $serial"
    } catch {
        Write-Host "Failed to update group tag for $serial. Error: $_"
    }
}

# Stop the transcript and save the log file
Stop-Transcript
