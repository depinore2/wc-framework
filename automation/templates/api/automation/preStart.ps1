# place custom automation you'd like to run before Start-Wcproject here.
param($apiName = '_REPLACE_ME_')

import-module "$psscriptroot/../../../automation/wc.psm1";

$mongoIsEnabled = (get-wcproject $apiName).mongoEnabled;

if($mongoIsEnabled) {
    $credentials = & "$psscriptroot/../../../automation/security/getSecrets.ps1" | & "$psscriptroot/../../../automation/security/decryptSecret.ps1" | where { $_.metadata.name -eq 'mongo-initdb-root-secret' };
    $mongoUsername = $credentials.data.username;
    $mongoPassword = $credentials.data.password;

    & "$psscriptroot/../../../automation/mongo/deployK8sSecrets.ps1" -serverName 'mongo-0.mongo' -apiName $apiName -adminUsername $mongoUsername -adminPassword $mongoPassword
}
else {
    Write-Host "Mongodb integration is not enabled for this project, skipping preStart.ps1."
}