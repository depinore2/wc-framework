param([Parameter(Mandatory=$true)][int32]$length, [string]$excludeChars, [string]$allowedCharacters, [switch]$alpha, [switch]$numeric)

if($alpha) {
    $allowedCharacters += 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
}
if($numeric) {
    $allowedCharacters += '0123456789'
}

[array]$excludedChars = if($excludedChars) { ($excludeChars -split $null)[1..$excludeChars.length] } else { @() }
[array]$allowedCharacters = if($allowedCharacters) { ($allowedCharacters -split $null)[1..$allowedCharacters.length] } else { @() }

$password = "";
while($password.Length -lt $length) {
    $newChar = if($allowedCharacters.length) { $allowedCharacters | get-random } else { [char](get-random -minimum 33 -maximum 126) }
    if(!($excludedChars -contains $newChar)) {
        $password += $newChar;
    }
}

$password