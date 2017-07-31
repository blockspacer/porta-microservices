#!/bin/bash
set -e

# this script downloads the latest stable kubectl version,
# moves it to /usr/local/bin/kubectl
# then configures it to use with particular cluster usage (defined in MASTER_HOST)
# and assignes certificates that were generated for this particular cluster earlier

MASTER_HOST=${MASTER_HOST:-"10.16.99.101"}
CWD=$(pwd)
CA_CERT="${CWD}/CA/ca.pem"
ADMIN_KEY="${CWD}/CA/admin-key.pem"
ADMIN_CERT="${CWD}/CA/admin.pem"

if [ !-e /usr/local/bin/kubectl ]; then
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
done

kubectl config set-cluster default-cluster --server=https://${MASTER_HOST} --certificate-authority=${CA_CERT}
kubectl config set-credentials default-admin --certificate-authority=${CA_CERT} --client-key=${ADMIN_KEY} --client-certificate=${ADMIN_CERT}
kubectl config set-context default-system --cluster=default-cluster --user=default-admin
kubectl config use-context default-system
