param([switch]$decrypt)

import-module "$psscriptroot/../wc.psm1";

$result = (kubectl get secrets -o json -n (get-wcsln).name | convertfrom-json -depth 99).items

if($decrypt) {
    $result | & "$psscriptroot/decryptSecret.ps1";
}
else {
    $result;
}