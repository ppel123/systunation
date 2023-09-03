# This is the initials of the organization's name: Example Company -> EC
$prefix = "EC"
# Get the serial using Get-WmiObject
$serial = (Get-WmiObject win32_bios | select Serialnumber).Serialnumber
# Create the final name by concatenating the prefix and the serial 
$finalName = $prefix + $serial
# Remove spaces
$finalName = $finalName.replace(' ','')

# here we have to be careful because NETBIOS allows only a 15 digit name a best practice is to keep that # in mind and keep only the first 15 chars of each name. In the majority of the cases, longer names will # not create a problem
$finalName = $finalName.Substring(0,15)

Rename-Computer -NewName $finalName
