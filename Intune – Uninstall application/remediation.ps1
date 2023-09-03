# There should be a different handling for 32 and 64 bit apps﻿

#First let's search if the app is under the 32 bit path

$32BitPath =  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
# Get the application name and the uninstall string
$32BitApp = Get-ChildItem -Path $32BitPath | Get-ItemProperty | Where-Object {($_.DisplayName -match "Wireshark")} | Select-Object -Property DisplayName, UninstallString

if ($32BitApp -ne $null){

    $uninstallStringValue = $32BitApp.uninstallstring

    # Check if it is .msi or .exe
    if ($uninstallStringValue -match "^msiexec*") {
        # MSI installer
        # Replace the /I with /X and add the quiet parameter
        $finalString = $uninstallStringValue + " /quiet /norestart"
        $finalString = $finalString -replace "/I", "/X "
        $finalString = $finalString -replace "msiexec.exe", ""
        Start-Process 'msiexec.exe' -ArgumentList $finalString -NoNewWindow -Wait
    }
    else {
        # Exe installer
        # Here we can search if there are specific parameters for the silently uninstallation of the application
        # For wireshark the /S start the uninstallation process silently
        $finalString = $uninstallStringValue
        start-process $finalString -ArgumentList "/S"
    }
}

# Next check the 64 bit path

$64BitPath =  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
#Loop Through the apps if name has Adobe and NOT reader
$64BitApp = Get-ChildItem -Path $64BitPath | Get-ItemProperty | Where-Object {($_.DisplayName -match "Wireshark")} | Select-Object -Property DisplayName, UninstallString

if ($64BitApp -ne $null){

    $uninstallStringValue = $64BitApp.uninstallstring

    # Check if it is .msi or .exe
    if ($uninstallStringValue -match "^msiexec*") {
        # MSI installer
        # Replace the /I with /X and add the quiet parameter
        $finalString = $uninstallStringValue + " /quiet /norestart"
        $finalString = $finalString -replace "/I", "/X "
        $finalString = $finalString -replace "msiexec.exe", ""
        Start-Process 'msiexec.exe' -ArgumentList $finalString -NoNewWindow -Wait
    }
    else {
        # Exe installer
        # Here we can search if there are specific parameters for the silently uninstallation of the application
        # For wireshark the /S start the uninstallation process silently
        $finalString = $uninstallStringValue
        start-process $finalString -ArgumentList "/S"
    }
}

# Check if there is a shortcut in the Start menu and remove it
$startMenuPath = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs"
$appShortcutPath = $startMenuPath + "\Wireshark.lnk"

if ((Test-Path -Path $appShortcutPath) -eq $true){
    Remove-Item -Path $appShortcutPath
}
