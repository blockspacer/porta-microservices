#!/bin/bash
set -e

if [ ! -e /usr/local/bin/helm ]; then
    curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get | bash
fi

# create service account for tiller in namespace 'kube-system'
# kubectl create serviceaccount tiller --namespace kube-system
# create service account for tiller in namespace 'default'
kubectl create serviceaccount tiller --namespace default

# grand permissions to 'tiller' account to be able to install charts in 'kube-system' namespace only
# kubectl create rolebinding tiller-kube-system --role=admin --serviceaccount=kube-system:tiller --namespace=kube-system
# kubectl create clusterrolebinding tiller-kube-system --clusterrole=cluster-admin --serviceaccount=kube-system:tiller --namespace=kube-system
# grand permissions to 'tiller' account to be able to install charts in 'default' namespace only
kubectl create rolebinding tiller-default --role=admin --serviceaccount=default:tiller --namespace=default

# install tiller to kube-system namespace
# helm init \
# --service-account tiller \
# --tiller-namespace kube-system \
# --override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}' \
# --tiller-tls \
# --tiller-tls-cert=./CA/helm/helm.crt \
# --tiller-tls-key=./CA/helm/helm.key \
# --tls-ca-cert=./CA/cluster-ca.crt

# install tiller to default namespace
helm init \
--service-account tiller \
--tiller-namespace default \
--override 'spec.template.spec.containers[0].command'='{/tiller,--storage=secret}' \
--tiller-tls \
--tiller-tls-cert=./CA/helm/helm.crt \
--tiller-tls-key=./CA/helm/helm.key \
--tls-ca-cert=./CA/ca.crt

# copy certificates to HELM_HOME to simplify usage
# Note: in all helm commands flag '--tls' is required like:
# helm --tls <cmd>
cp ./CA/ca.crt $HOME/.helm/ca.pem
cp ./CA/helm/helm.crt $HOME/.helm/cert.pem
cp ./CA/helm/helm.key $HOME/.helm/key.pem

echo "export HELM_HOME=$HOME/.helm" >> $HOME/.bashrc
source $HOME/.bashrc
