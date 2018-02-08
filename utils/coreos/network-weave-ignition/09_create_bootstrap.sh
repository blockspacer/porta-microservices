#!/bin/bash
set -e

# This script prepares environment for node bootstrapping.

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(pwd)
CA_CERT="${CWD}/CA/ca.crt"

kubectl -n kube-system create secret generic bootstrap-token-${K8S_TOKEN_PUB} \
        --type 'bootstrap.kubernetes.io/token' \
        --from-literal description="cluster bootstrap token" \
        --from-literal token-id=${K8S_TOKEN_PUB} \
        --from-literal token-secret=${K8S_TOKEN_SECRET} \
        --from-literal usage-bootstrap-authentication=true \
        --from-literal usage-bootstrap-signing=true

cat << EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:kubelet-bootstrap
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-bootstrapper
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:kubeadm:default-node-token
EOF

cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:node-autoapprove-bootstrap
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:nodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:bootstrappers:kubeadm:default-node-token
EOF

cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kubeadm:node-autoapprove-certificate-rotation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeclient
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:nodes
EOF


















# cat <<EOF | kubectl create -f -
# apiVersion: v1
# data:
#   kubeconfig: |
#     apiVersion: v1
#     clusters:
#     - cluster:
#         certificate-authority-data: $(cat ${CA_CERT} | base64 | tr -d '\r\n')
#         server: https://${MASTER_PUBLIC_HOSTNAME}:6443
#       name: ""
#     contexts: []
#     current-context: ""
#     kind: Config
#     preferences: {}
#     users: []
# kind: ConfigMap
# metadata:
#   name: cluster-info
#   namespace: kube-public
# EOF

# cat <<EOF | kubectl create -f -
# apiVersion: rbac.authorization.k8s.io/v1
# kind: Role
# metadata:
#   name: kubeadm:bootstrap-signer-clusterinfo
#   namespace: kube-public
# rules:
# - apiGroups:
#   - ""
#   resourceNames:
#   - cluster-info
#   resources:
#   - configmaps
#   verbs:
#   - get
# EOF

# cat <<EOF | kubectl create -f -
# apiVersion: rbac.authorization.k8s.io/v1
# kind: RoleBinding
# metadata:
#   name: kubeadm:bootstrap-signer-clusterinfo
#   namespace: kube-public
# roleRef:
#   apiGroup: rbac.authorization.k8s.io
#   kind: Role
#   name: kubeadm:bootstrap-signer-clusterinfo
# subjects:
# - apiGroup: rbac.authorization.k8s.io
#   kind: User
#   name: system:anonymous
# EOF