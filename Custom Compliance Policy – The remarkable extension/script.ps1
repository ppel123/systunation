$windowsEdition = (Get-WindowsEdition -Online).Edition

if ($windowsEdition.ToLower().Contains("enterprise") -eq $true){
    $isEnterprise = "Enterprise"
}
else{
    $isEnterprise = "NotEnterprise"
}

$isEnterpriseJSON = @{Status = $isEnterprise}

return $isEnterpriseJSON | ConvertTo-Json -Compress