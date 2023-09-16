$valueToReport = ""

$processorSpecs = gcim win32_processor

$processorName = $processorSpecs.Name
$valueToReport += ("Processor Name: " + $processorName.Trim() + "||")
$processorSpeed = [string]([math]::round(($processorSpecs.CurrentClockSpeed /1000),2)) + 'ghz'
$valueToReport += ("Processor Speed: " + $processorSpeed.Trim() + "||")
$processorCores = $processorSpecs.NumberOfCores
$valueToReport += ("Processor Cores: " + $processorCores.ToString() + "||")
$processorThreads = $processorSpecs.ThreadCount
$valueToReport += ("Processor Threads: " + $processorThreads.ToString() + "||")

$storage = ""

$hdd = gcim Win32_DiskDrive | where {$_.MediaType -like "Fixed*"}
$hdd | ForEach{$storage += $_.caption + ", Capacity: " + [math]::round(($_.Size / 1GB),'2') + "GB - "  }
$valueToReport += ("Storage Info: " + $storage.Trim() + "||")

$ramTotal = "{0:N2}" -f (((gcim CIM_PhysicalMemory | select -ExpandProperty Capacity) | measure -Sum).sum /1gb ) + ' GB'
$valueToReport += ("RAM Size: " + $ramTotal.Trim() + "||")
$computerName = $env:ComputerName
$valueToReport += ("Computer Name: " + $computerName.Trim() + "||")
$systemType = gcim win32_operatingsystem | select -ExpandProperty OSArchitecture
$valueToReport += ("System Type: " + $systemType.Trim() + "||")
$serial = gcim win32_bios | select -expandproperty serialnumber
$valueToReport += ("Serial Number: " + $serial.Trim() + "||")
$os = gcim win32_operatingsystem | select -expandproperty caption
$valueToReport += ("OS: " + $os.Trim() + "||")

Write-Host $valueToReport
