$version = (invoke-webrequest https://dl.k8s.io/release/stable.txt).Content
invoke-webrequest "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl" -outfile kubectl
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl