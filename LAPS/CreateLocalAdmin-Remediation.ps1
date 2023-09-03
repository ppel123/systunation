# Username and Password
$username = "WindowsLocalAdmin"
$password = ConvertTo-SecureString "WindowsLocalAdmin123!" -AsPlainText -Force
# Creating the user
New-LocalUser -Name "$username" -Password $password -FullName "$username" -Description "LAPS Admin"