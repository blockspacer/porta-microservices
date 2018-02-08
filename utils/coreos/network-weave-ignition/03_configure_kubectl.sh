#!/bin/bash
set -e

# this script downloads the latest stable kubectl version,
# moves it to /usr/local/bin/kubectl
# then configures it to use with particular cluster usage (defined in MASTER_PUBLIC_HOSTNAME)
# and assignes certificates that were generated for this particular cluster earlier

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(pwd)
CA_CERT="${CWD}/CA/ca.crt"
ADMIN_CERT="${CWD}/CA/admin/admin.crt"
ADMIN_KEY="${CWD}/CA/admin/admin.key"

if [ ! -e /usr/local/bin/kubectl ]; then
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
fi

cat << EOF > $HOME/.kube/config
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $(cat ${CA_CERT} | base64 | tr -d '\r\n')
    server: https://${MASTER_PUBLIC_HOSTNAME}:6443
  name: ${K8S_CLUSTER_NAME}
contexts:
- context:
    cluster: ${K8S_CLUSTER_NAME}
    user: kubernetes-admin
  name: kubernetes-admin@${K8S_CLUSTER_NAME}
current-context: kubernetes-admin@${K8S_CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: $(cat ${ADMIN_CERT} | base64 | tr -d '\r\n')
    client-key-data: $(cat ${ADMIN_KEY} | base64 | tr -d '\r\n')
EOF