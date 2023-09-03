$32BitPath =  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
# Get the application name and the uninstall string
$32BitApp = Get-ChildItem -Path $32BitPath | Get-ItemProperty | Where-Object {($_.DisplayName -match "Wireshark")} | Select-Object -Property DisplayName, UninstallString

if ($32BitApp -eq $null){
    Write-Host "32 bit application does not exist, exit"
    # exit 0 to exit
    exit 0
}
else{
    Write-Host "32 bit application exists, remediate"
    # exit 1 to remediate
    exit 1
}

$64BitPath =  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
#Loop Through the apps if name has Adobe and NOT reader
$64BitApp = Get-ChildItem -Path $64BitPath | Get-ItemProperty | Where-Object {($_.DisplayName -match "Wireshark")} | Select-Object -Property DisplayName, UninstallString

if ($64BitApp -eq $null){
    Write-Host "64 bit application does not exist, exit"
    # exit 0 to exit
    exit 0
}
else{
    Write-Host "64 bit application exists, remediate"
    # exit 1 to remediate
    exit 1
}
