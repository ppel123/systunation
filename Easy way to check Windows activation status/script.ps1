# Query Windows activation status via CIM
$Status = Get-CimInstance SoftwareLicensingProduct `
    -Filter "Name like 'Windows%'" |
  Where-Object { $_.PartialProductKey } |
  Select-Object -Property Description, LicenseStatus

try {
    # LicenseStatus 1 means activated; non-1 means not activated
    if ($Status.LicenseStatus -ne 1) {
        Write-Host 'Windows is not activated – needs attention'
        Exit 1
    }
    else {
        Write-Host 'Windows is activated – no action needed'
        Exit 0
    }
}
catch {
    # On any error, log and mark non-compliant
    $errMsg = $_.Exception.Message
    Write-Error "Error checking activation: $errMsg"
    Exit 1
}
