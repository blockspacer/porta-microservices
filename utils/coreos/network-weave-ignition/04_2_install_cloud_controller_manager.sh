#!/bin/bash
set -e

# Installs Cloud Controller Manager (CCM)
# NOTE: This scrip must be running after mark_master_node.sh

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(dirname $(readlink -f "$0"))

# Create ConfigMap
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  labels:
    app: cloud-controller-manager
  name: cloud-conf
  namespace: kube-system
data:
  cloud-config.conf: |-
    [Global]
    auth-url=${OPENSTACK_AUTH_URL}
    domain-id=${OPENSTACK_DOMAIN_ID}
    tenant-name=${OPENSTACK_TENANT_NAME}
    username=${OPENSTACK_AUTH_USERNAME}
    password=${OPENSTACK_AUTH_PASSWD}

    [BlockStorage]
    bs-version=auto

  cloud-controller-manager.conf: |-
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /etc/kubernetes/pki/ca.crt
        server: https://${MASTER_PRIVATE_IPV4}:6443
      name: ${K8S_CLUSTER_NAME}
    contexts:
    - context:
        cluster: ${K8S_CLUSTER_NAME}
        user: system:cloud-controller-manager
      name: cloud-controller-manager@${K8S_CLUSTER_NAME}
    current-context: cloud-controller-manager@${K8S_CLUSTER_NAME}
    users:
    - name: system:cloud-controller-manager
      user:
        client-certificate-data: $(cat $CWD/CA/cloud-controller/cloud-controller-manager.crt | base64 | tr -d '\r\n')
        client-key-data: $(cat $CWD/CA/cloud-controller/cloud-controller-manager.key | base64 | tr -d '\r\n')
EOF

# Install Initializer Configuration for CCM
cat <<EOF | kubectl create -f -
kind: InitializerConfiguration
apiVersion: admissionregistration.k8s.io/v1alpha1
metadata:
  name: pvlabel.kubernetes.io
initializers:
  - name: pvlabel.kubernetes.io
    rules:
    - apiGroups:
      - ""
      apiVersions:
      - "*"
      resources:
      - persistentvolumes
EOF

# Create Cluster Role Binding for service account
cat << EOF | kubectl create -f -
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: system:cloud-controller-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: User
  name: system:cloud-controller-manager
EOF

#  Create Deployment for CCM
cat << EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: cloud-controller-manager
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
      labels:
        component: cloud-controller-manager
        tier: control-plane
        k8s-app: cloud-controller-manager
    spec:
      containers:
      - name: cloud-controller-manager
        image: gcr.io/google-containers/cloud-controller-manager-amd64:${K8S_IMAGE_TAG}
        command:
        - /usr/local/bin/cloud-controller-manager
        - --address=${MASTER_PRIVATE_IPV4}
        - --allocate-node-cidrs=false
        - --leader-elect=false
        - --cloud-provider=openstack
        - --cloud-config=/etc/kubernetes/conf/cloud-config.conf
        - --cluster-name=${K8S_CLUSTER_NAME}
        - --cluster-cidr=${K8S_POD_NETWORK}
        - --configure-cloud-routes=false
        - --kubeconfig=/etc/kubernetes/conf/cloud-controller-manager.conf
        livenessProbe:
          failureThreshold: 8
          httpGet:
            host: ${MASTER_PRIVATE_IPV4}
            path: /healthz
            port: 10253  # Note: Using default port. Update if --port option is set differently.
            scheme: HTTP
          initialDelaySeconds: 15
          timeoutSeconds: 15
        resources:
          requests:
            cpu: 100m
        volumeMounts:
        - mountPath: /etc/kubernetes/conf
          name: cloud-config
          readOnly: true
        - mountPath: /etc/kubernetes/pki/ca.crt
          name: kube-ca-crt
          readOnly: true
      hostNetwork: true
      volumes:
      - configMap:
          defaultMode: 420
          name: cloud-conf
        name: cloud-config
      - hostPath:
          path: /etc/kubernetes/pki/ca.crt
          type: FileOrCreate
        name: kube-ca-crt
      tolerations:
      # this is required so CCM can bootstrap itself
      - key: node.cloudprovider.kubernetes.io/uninitialized
        value: "true"
        effect: NoSchedule
      # this is to have the pod runnable on master nodes
      # the taint may vary depending on your cluster setup
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      # this is to restrict CCM to only run on master nodes
      # the node selector may vary depending on your cluster setup
      nodeSelector:
        node-role.kubernetes.io/master: ""
EOF

