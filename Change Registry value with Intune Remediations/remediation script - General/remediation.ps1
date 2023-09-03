$date = Get-Date
$variableToReportToIntune = "$date"

# The variable below represents the path to the key
# Enter the desired key registry path here
$registryKeyLocation = "ENTER HERE REGISTRY KEY LOCATION"

# The variable below represents the value name
# Enter the desired value name here
$valueName = "ENTER HERE VALUE NAME"
$desiredValue = "ENTER HERE THE DESIRED VALUE"

try{
    Set-ItemProperty -Path $registryKeyLocation -Name $valueName -Value $desiredValue
    $variableToReportToIntune = $variableToReportToIntune + " | Value set successfully"
    Write-Host $variableToReportToIntune
}
catch{
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
}
