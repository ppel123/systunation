$date = Get-Date
$variableToReportToIntune = "$date"

# The variable below represents the path to the key
# Enter the desired key registry path here
$registryKeyLocation = "ENTER HERE REGISTRY KEY LOCATION"

# The variable below represents the value name
# Enter the desired value name here
$valueName = "ENTER HERE VALUE NAME"

try{
    $valueData = (Get-ItemProperty -Path $registryKeyLocation -Name $valueName -ErrorAction Stop).$ValueName
    $variableToReportToIntune = $variableToReportToIntune + " | The value is: $valueData"

    if ($valueData -ne "ENTER HERE THE DESIRED VALUE"){
        # remediate -> must change to zero
        Write-Host "Value does not have the desired value. Going to remediation"
        $variableToReportToIntune = $variableToReportToIntune + " | Value does not have the desired value. Going to remediation"
        Write-Host $variableToReportToIntune
        # EXIT 1
    }
    else{
        # value is defined
        Write-Host "Value has a desired value. Exiting."
        $variableToReportToIntune = $variableToReportToIntune + " | Value has a desired value. Exiting."
        # EXIT 0
    }
}
# If value does not exist
catch [System.Management.Automation.PSArgumentException]{
    Write-Host "Value does not exist"
    $variableToReportToIntune = $variableToReportToIntune + " | Value does not exist."
}
# If Key does not exist
catch [System.Management.Automation.ItemNotFoundException]{
    Write-Host "Key does not exist"
    $variableToReportToIntune = $variableToReportToIntune + " | Key does not exist."
}
# Other error
catch{
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
}


