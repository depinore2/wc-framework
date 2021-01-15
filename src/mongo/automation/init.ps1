param([Parameter(Mandatory=$true)][string]$newAdminUsername, [Parameter(Mandatory=$true)][string]$newAdminPassword, [Parameter(Mandatory=$true)][string]$configuration)

$k8sPath = (resolve-path "$psscriptroot/../k8s").Path;
$k8sConfigurations = get-childitem "*.yaml" -path $k8sPath | select -expandproperty basename;

if($k8sConfigurations -contains $configuration) {
    & "$psscriptroot/../../../automation/security/newBasicAuthSecret.ps1" 'mongo-initdb-root-secret' $newAdminUsername $newAdminPassword;
    kubectl apply -f "$k8spath/$configuration.yaml";
}
else {
    throw "Could not find $configuration in $k8spath.";
}