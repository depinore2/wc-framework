param([Parameter(Mandatory=$true)][string]$serverName, [Parameter(Mandatory=$true)][string]$apiName, [Parameter(Mandatory=$true)][string]$adminUsername, [Parameter(Mandatory=$true)][string]$adminPassword, [string]$newUsername = "$($apiName)-rw", [string]$newPassword)

if(!$newPassword) {
    $length = 200;
    $newPassword = & "$psscriptroot/../security/genPassword.ps1" $length -alpha -numeric;
    Write-Host "New Username = $newUsername; New Password is a $length-length randomly-generated alphanumeric string..."
}
$secretName = "$apiName-mongo-secret";

Write-Host "Storing these credentials as a new Basic Auth Secret '$secretName' in k8s."
& "$psscriptroot/../security/newBasicAuthSecret.ps1" $secretName $newUsername $newPassword;

Write-Host "Creating a new user $newUsername in database $apiName within mongo server $servername."
& "$psscriptroot/newUser.ps1" $serverName $apiName $newUsername $newPassword $adminUsername $adminPassword 'admin'