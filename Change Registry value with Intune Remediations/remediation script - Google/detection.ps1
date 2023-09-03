$date = Get-Date
$variableToReportToIntune = "$date"

# The variable below represents the path to the key
# Enter the desired key registry path here
$registryKeyLocation = "HKLM:\Software\Policies\Mozilla\Firefox"

# The variable below represents the value name
# Enter the desired value name here
$valueName = "AppAutoUpdate"

try{
    $valueData = (Get-ItemProperty -Path $registryKeyLocation -Name $valueName -ErrorAction Stop).$ValueName
    $variableToReportToIntune = $variableToReportToIntune + " | The value is: $valueData"

    if ($valueData -ne 1){
        # remediate -> must change to zero
        Write-Host "Value does not have the desired value. Going to remediation"
        $variableToReportToIntune = $variableToReportToIntune + " | Value does not have the desired value. Going to remediation"
        Write-Host $variableToReportToIntune
        EXIT 1
    }
    else{
        # value is defined
        Write-Host "Value has a desired value. Exiting."
        $variableToReportToIntune = $variableToReportToIntune + " | Value has a desired value. Exiting."
        EXIT 0
    }
}
# If value does not exist
catch [System.Management.Automation.PSArgumentException]{
    Write-Host "Key exists, but value does not exist. Going to remediation"
    $variableToReportToIntune = $variableToReportToIntune + " | Key exists, but value does not exist. Going to remediation"
    EXIT 1
}
# If Key does not exist
catch [System.Management.Automation.ItemNotFoundException]{
    # Check if Firefox is installed
    $installedSoftware = Get-ChildItem "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    foreach ($app in $installedSoftware){
        $name = $app.GetValue("DisplayName")
        if ($name -ne $null){
            if ($name.Contains("Mozilla Firefox")){
                Write-Host "Key does not exist, but application is installed. Going to remediation."
                $variableToReportToIntune = $variableToReportToIntune + " | Key does not exist, but application is installed. Going to remediation."
                EXIT 1
            }
        }
    }
    $variableToReportToIntune = $variableToReportToIntune + " | Key does not exist and application is not installed."
}
# Other error
catch{
    $errorMessage = $_.Exception.Message
    Write-Error $errorMessage
}


