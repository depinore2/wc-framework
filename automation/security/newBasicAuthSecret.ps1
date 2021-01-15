param([Parameter(Mandatory=$true)][string]$secretName, [Parameter(Mandatory=$true)][string]$username, [Parameter(Mandatory=$true)][string]$password)

kubectl create secret generic $secretName --from-literal=username=$username --from-literal=password=$password