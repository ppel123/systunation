$LogFilepath = "C:\Users\Public\log2.txt"

Function LogAndConsole($message,$LogFilepath, $level) {
    if ($level -eq "information") {
        $currenttimestamp = Get-Date -format u
        $message = "[" + $currenttimestamp + "] " + "INFO: " + $message
        Write-Host $message -ForegroundColor Green
        $message | Out-File $LogFilepath -Append
    }
    if ($level -eq "error") {
        $currenttimestamp = Get-Date -format u
        $message = "[" + $currenttimestamp + "] " + "ERROR: " + $message
        Write-Host $message -ForegroundColor Red
        $message | Out-File $LogFilepath -Append
    }
}

<#
Function LogAndConsole($message,$outputMethod,$LogFilepath) {
    if ($outputMethod -eq 1) {
        $currenttimestamp = Get-Date -format u
        $message = "[" + $currenttimestamp + "] " + $message
        Write-Host $message -ForegroundColor Green
    }
    if ($outputMethod -eq 2) {
        Log -LogFilepath $LogFilepath -message $message
    }
}

Function LogErrorAndConsole($message,$outputMethod,$LogFilepath) {
    if ($outputMethod -eq 1) {
        $currenttimestamp = Get-Date -format u
        $message = "[" + $currenttimestamp + "] " + $message
        Write-Host $message -ForegroundColor Red
    }
    if ($outputMethod -eq 2) {
        Log -LogFilepath $LogFilepath -message $message
    }
}
#>
