apt-get install wget -y;

wget https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64 -O ./kind --no-check-certificate
chmod +x ./kind
mv ./kind /usr/local/bin/kind