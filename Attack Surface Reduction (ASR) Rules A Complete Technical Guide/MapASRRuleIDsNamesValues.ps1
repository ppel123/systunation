# Define ASR rule mapping with GUIDs and friendly names
$asrRules = @{
    "BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550" = "Block executable content from email client and webmail"
    "D4F940AB-401B-4EFC-AADC-AD5F3C50688A" = "Block all Office applications from creating child processes"
    "3B576869-A4EC-4529-8536-B80A7769E899" = "Block Office applications from creating executable content"
    "75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84" = "Block Office applications from injecting code into other processes"
    "D3E037E1-3EB8-44C8-A917-57927947596D" = "Block JavaScript or VBScript from launching downloaded executable content"
    "5BEB7EFE-FD9A-4556-801D-275E5FFC04CC" = "Block execution of potentially obfuscated scripts"
    "92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B" = "Block Win32 API calls from Office macros"
    "01443614-CD74-433A-B99E-2ECDC07BFC25" = "Block executable files from running unless they meet prevalence, age, or trusted list criterion"
    "C1DB55AB-C21A-4637-BB3F-A12568109D35" = "Use advanced protection against ransomware"
    "9E6C4E1F-7D60-472F-BA1A-A39EF669E4B2" = "Block credential stealing from LSASS"
    "D1E49AAC-8F56-4280-B9BA-993A6D77406C" = "Block process creations originating from PSExec and WMI commands"
    "B2B3F03D-6A65-4F7B-A9C7-1C7EF74A9BA4" = "Block untrusted and unsigned processes that run from USB"
    "26190899-1602-49E8-8B27-EB1D0A1CE869" = "Block Office communication application from creating child processes"
    "7674BA52-37EB-4A4F-A9A1-F0F9A1619A2C" = "Block Adobe Reader from creating child processes"
    "E6DB77E5-3DF2-4CF1-B95A-636979351E5B" = "Block persistence through WMI event subscription"
    "56A863A9-875E-4185-98A7-B882C64B5CE5" = "Block abuse of exploited vulnerable signed drivers"
    "c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb" = "Block use of copied or impersonated system tools"
    "33ddedf1-c6e0-47cb-833e-de6133960387" = "Block rebooting machine in Safe Mode"
    "a8f5898e-1dc8-49a9-9878-85004b8a61e6" = "Block Webshell creation for Servers"
}

# State mapping for better readability
$stateMap = @{
    0 = "Disabled"
    1 = "Block"
    2 = "Audit"
    6 = "Warn"
}

# Get current ASR configuration from the device
$mpPreference = Get-MpPreference
$currentRules = $mpPreference.AttackSurfaceReductionRules_Ids
$currentActions = $mpPreference.AttackSurfaceReductionRules_Actions

# Create an array to hold our formatted results
$results = @()

# If there are configured rules, process them
if ($currentRules) {
    for ($i = 0; $i -lt $currentRules.Count; $i++) {
        $ruleId = $currentRules[$i]
        $action = $currentActions[$i]
        
        # Create a custom object for each rule with all relevant information
        $results += [PSCustomObject]@{
            RuleID = $ruleId
            RuleName = if ($asrRules.ContainsKey($ruleId)) { $asrRules[$ruleId] } else { "Unknown Rule" }
            State = if ($stateMap.ContainsKey([int]$action)) { $stateMap[[int]$action] } else { "Unknown ($action)" }
            ActionValue = $action
        }
    }
    
    # Display the results in a formatted table
    $results | Format-Table -AutoSize
    
    # Summary information
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "Total ASR Rules Configured: $($results.Count)" -ForegroundColor Green
    Write-Host "Enabled (Block): $(($results | Where-Object {$_.ActionValue -eq 1}).Count)" -ForegroundColor Green
    Write-Host "Audit Mode: $(($results | Where-Object {$_.ActionValue -eq 2}).Count)" -ForegroundColor Yellow
    Write-Host "Warn Mode: $(($results | Where-Object {$_.ActionValue -eq 6}).Count)" -ForegroundColor Yellow
    Write-Host "Disabled: $(($results | Where-Object {$_.ActionValue -eq 0}).Count)" -ForegroundColor Red
} else {
    Write-Host "No ASR rules are currently configured on this system." -ForegroundColor Yellow
}
