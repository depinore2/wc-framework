param([switch]$decrypt)
$result = (kubectl get secrets -o json | convertfrom-json -depth 99).items

if($decrypt) {
    $result | & "$psscriptroot/decryptSecret.ps1";
}
else {
    $result;
}