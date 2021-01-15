param([Parameter(Mandatory=$true, ValueFromPipeline=$true)][array]$secrets)

Begin { }
Process {
    foreach($secret in $secrets) {
        $deepClone = $secret | convertto-json -depth 99 | convertfrom-json -depth 99
        foreach($property in $secret.data.PsObject.Properties) {
            $decrypted = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($property.Value))
            $deepClone.data."$($property.Name)" = $decrypted
        }
        $deepClone;
    }
}
End { }