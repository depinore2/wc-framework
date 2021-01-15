apt-get install -y apt-transport-https gnupg2 curl
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6A030B21BA07F4FB # https://jonamiki.com/2019/11/09/ubuntu-the-following-signatures-couldnt-be-verified-because-the-public-key-is-not-available-no_pubkey/

# The following steps come from: https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-using-native-package-management
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg |  apt-key add -
echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | tee -a /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubectl