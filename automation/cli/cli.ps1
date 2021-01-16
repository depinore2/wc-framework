# Use this script to open an interactive session into your local development k8s cluster.
# This image comes prebuilt with powershell and mongo.  Update the Dockerfile in this same folder if you want to have it load additional stuff for you.
# Note: this is specifically for local debugging and will not function on a remote cluster.
param([string]$cmd)

$imageName = 'wc-cli'

$alreadyExists = ([array](docker images "$($imageName):local")).length -eq 2;

if(!$alreadyExists) {
    docker build $psscriptroot/.. -f "$psscriptroot/Dockerfile" -t "$($imageName):local"
}

if(kubectl get pods | select-string $imageName) {
    kubectl delete pod $imagename | out-null;
}

kind load docker-image "$($imageName):local"

if($cmd) {
    $expr = "kubectl run -it --quiet --restart=Never $imageName --image=$($imageName):local -- $cmd"

    Write-Verbose "cli.ps1: $expr"

    $result = bash -c $expr;
    kubectl delete pod $imagename | out-null;
    $result;
}
else {
    kubectl run -it --rm --restart=Never $imageName --image="$($imageName):local" -- /bin/bash
}