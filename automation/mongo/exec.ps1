param([Parameter(Mandatory=$true)][string]$serverName, [Parameter(Mandatory=$true)][string]$dbName, [Parameter(Mandatory=$true)][string]$cmd, [string]$username, [string]$password, [string]$authenticationDatabase)

import-module "$psscriptroot/../wc.psm1";

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

# kubectl run is a little bit chatty.  Some of our commands return output that we want to parse, so we wrap the command output with delimiters ===cmdoutput===
# this way, we can distinguish between kubectl's chatter and our cmd's output.
$output = kubectl run -it --rm --restart=Never "mongo-cli-$((get-date).Ticks)" -n (get-wcsln).name --image=mongo -- bash -c "echo ===cmdoutput=== && $cmd && echo ===/cmdoutput==="
$output = [string]::Join("`n", $output);

# Using the delimiters, we are able to use regular expressions to remove anything that comes before or after our output
# This way, if our cmd output is JSON, all that's returned to the caller of this script is JSON without any random help messages from kubectl.
$output -replace '(?ms).*===cmdoutput===', '' -replace '(?ms)===/cmdoutput===.*','';