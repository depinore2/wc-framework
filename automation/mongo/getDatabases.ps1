param([Parameter(Mandatory=$true)][string]$servername, $username, $password, $authenticationDatabase)

$cmd = "db.adminCommand({ listDatabases: 1 })";
(& "$psscriptroot/exec.ps1" -servername $servername -dbName 'admin' `
    -cmd $cmd -username $username -password $password -authenticationDatabase $authenticationDatabase | 
    convertfrom-json -depth 99).Databases;