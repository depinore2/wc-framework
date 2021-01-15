param($clusterName = 'kind')

kind create cluster --config "$psscriptroot/../kind.yaml" --wait 5m --name $clusterName

$hostip = /sbin/ip route|awk '/default/ { print $3 }'
Write-Host "Determined that the host of this workstation container has IP: $hostip"

$configLocation = '~/.kube/config';

Write-Host "Updating the configuration of $configLocation to allow for this workstation computer to communicate with the kind cluster hosted on this image's host ($hostip)."
$kubeConfig = get-content $configLocation | convertfrom-yaml
$kindClusterConfig = ($kubeConfig.clusters | where name -eq "kind-$clusterName").cluster;

if($kindClusterConfig) {
    $kindClusterConfig.Remove('certificate-authority-data');
    $kindClusterConfig.Add('insecure-skip-tls-verify', $true);
    $kindClusterConfig.server = $kindClusterConfig.server.Replace('0.0.0.0', $hostIp);
    $kubeConfig | convertto-yaml > $configLocation;

    Write-Host "Adding and configuring a dashboard..."
    kubectl apply -f "$psscriptroot/../dashboard.yaml";
    kubectl apply -f "$psscriptroot/../dev-dashboard-user.yaml";

    Write-Host "Creating a folder to hold mongodb data in /mongodata"
    docker exec "$clusterName-control-plane" mkdir /mongodata;

    Write-Host "Creating a PersistentVolume [localdev] bound to /k8sdata..."
    kubectl apply -f "$psscriptroot/../dev-volume.yaml"

    Write-Host "Applying patches to allow for ingress according to https://kind.sigs.k8s.io/docs/user/ingress/"
    kubectl apply -f "$psscriptroot/../ingress-patches.yaml"
    Write-Host "Waiting up to 5 mins for the cluster to start..."
    kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
}
else { 
    Write-Error "Unable to find cluster with name kind-$clusterName"
}