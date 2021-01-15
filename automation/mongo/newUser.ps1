param([Parameter(Mandatory=$true)][string]$serverName, [Parameter(Mandatory=$true)][string]$dbName, $newUsername = "$($dbName)_user", [Parameter(Mandatory=$true)][string]$newPassword, $adminUsername, $adminPassword, $authenticationDatabase)

$users = & "$psscriptroot/getUsers.ps1" $serverName $dbName -username $adminUsername -password $adminPassword -authenticationDatabase $authenticationDatabase;

if($users | where User -eq $newUsername) {
    Write-Warning "$newUsername already exits in $serverName/$dbName.  Skipping..."
}
else {
    $escapedPassword = $newPassword.Replace("\","\\").Replace("'","\'")
    $cmd = "db.createUser({ user: '$newUsername', pwd: '$escapedPassword', roles: ['readWrite'] })"
    & "$psscriptroot/exec.ps1" $servername $dbname $cmd -username $adminUsername -password $adminPassword -authenticationDatabase $authenticationDatabase
}