param([Parameter(Mandatory=$true)][string]$serverName, [Parameter(Mandatory=$true)][string]$dbName, [Parameter(Mandatory=$true)][string]$cmd, [string]$username, [string]$password, [string]$authenticationDatabase)

$cmd = "db = db.getSiblingDB('$dbName'); $cmd"
$cmd = "mongo mongodb://$serverName --eval $($cmd -replace '([^a-zA-Z0-9])','\$1') --quiet"

if($username) {
    $cmd = "$cmd --username '$username'"
}
if($password) {
    $cmd = "$cmd --password '$password'"
}
if($authenticationDatabase) {
    $cmd = "$cmd --authenticationDatabase '$authenticationDatabase'"
}

Write-Verbose "exec.ps1: $cmd";

& "$psscriptroot/../cli/cli.ps1" -cmd $cmd -verbose:$verbose;