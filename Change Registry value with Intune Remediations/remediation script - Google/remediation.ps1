$date = Get-Date
$variableToReportToIntune = "$date"

# The variable below represents the path to the key
# Enter the desired key registry path here
$registryKeyLocation = "HKLM:\Software\Policies\Mozilla\Firefox"

# The variable below represents the value name
# Enter the desired value name here
$valueName = "AppAutoUpdate"
$desiredValue = 1

try{
    
    New-Item -Path $registryKeyLocation -Name "x"
    Set-ItemProperty -Path $registryKeyLocation -Name $valueName -Value $desiredValue -Force 
    $variableToReportToIntune = $variableToReportToIntune + " | Value set successfully"
    Write-Host $variableToReportToIntune
}
catch{
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
}

try{
    $valueData = (Get-ItemProperty -Path $registryKeyLocation -Name $valueName -ErrorAction Stop).$ValueName
    $variableToReportToIntune = $variableToReportToIntune + " | The value is: $valueData"
    Set-ItemProperty -Path $registryKeyLocation -Name $valueName -Value $desiredValue -Force 
    $variableToReportToIntune = $variableToReportToIntune + " | Value changed successfully."
    Write-Host $variableToReportToIntune
}
# If value does not exist
catch [System.Management.Automation.PSArgumentException]{
    New-ItemProperty -Path $registryKeyLocation -Name $valueName -PropertyType Dword -Value $desiredValue -Force
    $variableToReportToIntune = $variableToReportToIntune + " | Value created successfully."
    Write-Host $variableToReportToIntune
}
# If Key does not exist
catch [System.Management.Automation.ItemNotFoundException]{
    New-Item $registryKeyLocation -Force | New-ItemProperty -Name $valueName -Value $desiredValue -Force
    $variableToReportToIntune = $variableToReportToIntune + " | Key created successfully."
    Write-Host $variableToReportToIntune
}
# Other error
catch{
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
}
