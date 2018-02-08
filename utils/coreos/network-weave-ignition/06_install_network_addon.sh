#!/bin/bash
set -e

# This script installs Weave-Net network plugin into Kubernetes cluster.
# See more info about Weave-Net here:
# https://www.weave.works/docs/net/latest/kubernetes/kube-addon/

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

kubectl create secret -n kube-system generic weave-passwd --from-literal=weave-passwd=s3cr3tp4ssw0rdb0neynem
kubectl apply -f "https://cloud.weave.works/k8s/v1.8/net.yaml?env.IPALLOC_RANGE=${K8S_POD_NETWORK}&password-secret=weave-passwd"