import-module "$psscriptroot/../../../../automation/wc.psm1";

$clusterName = 'kind';

if(!(kind get clusters) -contains $clusterName) {
    kind create cluster --config "$psscriptroot/../kind.yaml" --wait 5m --name $clusterName
}
else {
    Write-Host "$clusterName already exists, skipping creation of cluster.";
}

$hostip = ip route|awk '/default/ { print $3 }'
Write-Host "Determined that the host of this workstation container has IP: $hostip"

$configLocation = "$psscriptroot/../../../../kubeconfig";

Write-Host "Updating the configuration of $configLocation to allow for this workstation computer to communicate with the kind cluster hosted on this image's host ($hostip)."
$kubeConfig = get-content $configLocation | convertfrom-yaml
$kindClusterConfig = ($kubeConfig.clusters | where name -eq "kind-$clusterName").cluster;
$sln = (get-wcsln).Name;

if($kindClusterConfig) {
    $kindClusterConfig.Remove('certificate-authority-data');
    $kindClusterconfig.Remove('insecure-skip-tls-verify')
    $kindClusterConfig.Add('insecure-skip-tls-verify', $true);
    $kindClusterConfig.server = $kindClusterConfig.server.Replace('0.0.0.0', $hostIp);
    $kubeConfig | convertto-yaml > $configLocation;

    Write-Host "Creating a folder to hold mongodb data in /mongodata"
    docker exec "$clusterName-control-plane" mkdir /mongodata/$sln --parents;

    Write-Host "Applying patches to allow for ingress according to https://kind.sigs.k8s.io/docs/user/ingress/"
    kubectl apply -f "$psscriptroot/../ingress-patches.yaml";
    Write-Host "Waiting up to 5 mins for the cluster to start..."
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s

    Write-Host "Setting your preferred namespace to be $sln."
    kubectl config set-context --current --namespace=$sln
    kubectl create namespace $sln;
}
else { 
    Write-Error "Unable to find cluster with name kind-$clusterName"
}