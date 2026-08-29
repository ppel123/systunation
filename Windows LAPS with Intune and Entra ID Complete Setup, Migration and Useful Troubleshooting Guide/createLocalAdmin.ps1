# Pre-create the LAPS-managed local admin account on down-level Windows.
# Run as system, 64-bit. The password set here is a throwaway - LAPS
# overwrites it on the first rotation.

$AccountName = 'LapsAdmin'

# S-1-5-32-544 is the well-known SID for the local Administrators group.
# Use the SID, not the name - the group name is localized on non-English Windows.
$AdminsSid = 'S-1-5-32-544'

function New-SeedPassword {
    param([int]$Length = 24)

    # Ambiguous characters (0/O, 1/l/I) left out - this value is short-lived
    # but may need to be typed once during testing.
    $upper  = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower  = 'abcdefghijkmnopqrstuvwxyz'
    $digit  = '23456789'
    $symbol = '!#$%&*+-=?@'
    $all    = $upper + $lower + $digit + $symbol

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = [byte[]]::new(4)

    # Rejection sampling to avoid modulo bias.
    $pickIndex = {
        param([int]$Max)
        $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$Max)
        do {
            $rng.GetBytes($buf)
            $val = [BitConverter]::ToUInt32($buf, 0)
        } while ($val -ge $limit)
        [int]($val % $Max)
    }

    # Guarantee one character from each class, then fill the rest.
    $chars = [System.Collections.Generic.List[char]]::new()
    foreach ($set in @($upper, $lower, $digit, $symbol)) {
        $chars.Add($set[(& $pickIndex $set.Length)])
    }
    while ($chars.Count -lt $Length) {
        $chars.Add($all[(& $pickIndex $all.Length)])
    }

    # Fisher-Yates shuffle so the guaranteed characters aren't always first.
    for ($i = $chars.Count - 1; $i -gt 0; $i--) {
        $j = & $pickIndex ($i + 1)
        $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
    }

    $rng.Dispose()
    -join $chars
}

if (-not (Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue)) {
    $TempPassword = ConvertTo-SecureString (New-SeedPassword) -AsPlainText -Force

    New-LocalUser -Name $AccountName `
        -Password $TempPassword `
        -FullName 'Managed Local Administrator' `
        -Description 'Password managed by Windows LAPS' `
        -PasswordNeverExpires
}

# Ensure membership in the local Administrators group
$IsMember = Get-LocalGroupMember -SID $AdminsSid -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "*\$AccountName" }

if (-not $IsMember) {
    Add-LocalGroupMember -SID $AdminsSid -Member $AccountName
}