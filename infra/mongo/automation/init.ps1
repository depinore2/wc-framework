param([Parameter(Mandatory=$true)][string]$newAdminUsername, [Parameter(Mandatory=$true)][string]$newAdminPassword, [Parameter(Mandatory=$true)][string]$configuration)

import-module "$psscriptroot/../../../automation/wc.psm1";

$k8sPath = (resolve-path "$psscriptroot/../k8s").Path;
$sln = (get-wcsln).name;
$k8sConfigurations = get-childitem "*.yaml" -path $k8sPath | select -expandproperty basename;

if($k8sConfigurations -contains $configuration) {
    & "$psscriptroot/../../../automation/security/newBasicAuthSecret.ps1" 'mongo-initdb-root-secret' $newAdminUsername $newAdminPassword;
    $tempPath = "$k8spath/$($configuration)_$(get-random).yaml";
    cp "$k8spath/$configuration.yaml" $tempPath;
    (gc $tempPath -raw).Replace('_SOLUTION_NAME_', $sln) | Out-File -FilePath $tempPath -NoNewLine;
    kubectl apply -f $tempPath -n $sln;
    remove-item $tempPath;
}
else {
    throw "Could not find $configuration in $k8spath.";
}