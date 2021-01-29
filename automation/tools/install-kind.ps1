invoke-webrequest https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 -outfile ./kind
chmod +x ./kind
mv ./kind /usr/local/bin/kind