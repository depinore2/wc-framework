param([Parameter(Mandatory=$true)][string]$serverName, [Parameter(Mandatory=$true)][string]$dbName, $username, $password, $authenticationDatabase)

& "$psscriptroot/exec.ps1" $servername $dbname "db.getUsers().map(u => { const copy = { ...u }; delete copy.userId; return copy; })" -username $username -password $password -authenticationdatabase $authenticationDatabase | convertfrom-json