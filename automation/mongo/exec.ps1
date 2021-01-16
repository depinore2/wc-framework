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

$output = kubectl run -it --rm --restart=Never "mongo-cli-$((get-date).Ticks)" --image=mongo -- bash -c "echo ===cmdoutput=== && $cmd && echo ===/cmdoutput==="
$output = [string]::Join("`n", $output);

$output -replace '(?ms).*===cmdoutput===', '' -replace '(?ms)===/cmdoutput===.*','';