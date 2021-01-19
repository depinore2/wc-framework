# https://github.com/kubernetes/dashboard/blob/master/docs/user/access-control/creating-sample-user.md
param($secretName = 'dashboard-user*', $namespace = 'kubernetes-dashboard');

$matchingOutput = kubectl get secrets --namespace $namespace | select-string $secretName;
if($matchingOutput) {
    $secretName = (-split $matchingoutput)[0];

    $token = (kubectl describe secret $secretName --namespace $namespace | select-string token:) -replace 'token:\W+',''

    @{
        DashboardUrl = 'http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/';
        LoginToken = $token
    }
    Write-Warning "If you did not already do so, please make sure to run 'kubectl proxy' to expose your cluster's dashboard to your host computer."
    Write-Warning "If you are running this from within a development container, ensure that the proxy port is exposed in your Ports Remote Development Panel."
}
else {
    throw "Unable to find any secrets that match the pattern $secretName in namespace $namespace."
}