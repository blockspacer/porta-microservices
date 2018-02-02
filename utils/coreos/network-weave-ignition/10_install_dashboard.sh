#!/bin/bash
set -e

# This script installs Dashboard plugin into Kubernetes cluster
# See more details about Dashboard here:
# https://github.com/kubernetes/dashboard

# create secret from certificate file
# kubectl create secret generic kubernetes-dashboard-certs -n kube-system \
# --from-file=tls.crt=$(pwd)/CA/dashboard/dashboard.crt \
# --from-file=tls.key=$(pwd)/CA/dashboard/dashboard.key \
# --from-file=ca.crt=$(pwd)/CA/ca.crt

# # create service account for dashboard
# kubectl create serviceaccount kubernetes-dashboard -n kube-system

# cat << EOF | kubectl create -f -
# # ------------------- Dashboard Role ------------------- #
# kind: Role
# apiVersion: rbac.authorization.k8s.io/v1
# metadata:
#   name: kubernetes-dashboard-minimal
#   namespace: kube-system
# rules:
#   # Allow Dashboard to create 'kubernetes-dashboard-key-holder' secret.
# - apiGroups: [""]
#   resources: ["secrets"]
#   verbs: ["create"]
#   # Allow Dashboard to create 'kubernetes-dashboard-settings' config map.
# - apiGroups: [""]
#   resources: ["configmaps"]
#   verbs: ["create"]
#   # Allow Dashboard to get, update and delete Dashboard exclusive secrets.
# - apiGroups: [""]
#   resources: ["secrets"]
#   resourceNames: ["kubernetes-dashboard-key-holder", "kubernetes-dashboard-certs"]
#   verbs: ["get", "update", "delete"]
#   # Allow Dashboard to get and update 'kubernetes-dashboard-settings' config map.
# - apiGroups: [""]
#   resources: ["configmaps"]
#   resourceNames: ["kubernetes-dashboard-settings"]
#   verbs: ["get", "update"]
#   # Allow Dashboard to get metrics from heapster.
# - apiGroups: [""]
#   resources: ["services"]
#   resourceNames: ["heapster"]
#   verbs: ["proxy"]
# - apiGroups: [""]
#   resources: ["services/proxy"]
#   resourceNames: ["heapster", "http:heapster:", "https:heapster:"]
#   verbs: ["get"]
# EOF

# kubectl create rolebinding kubernetes-dashboard-minimal --role=kubernetes-dashboard-minimal --serviceaccount=kube-system:kubernetes-dashboard -n kube-system

# cat << EOF | kubectl create -f -
# # ------------------- Dashboard Deployment ------------------- #
# kind: Deployment
# apiVersion: apps/v1beta2
# metadata:
#   labels:
#     k8s-app: kubernetes-dashboard
#     kubernetes.io/cluster-service: "true"
#   name: kubernetes-dashboard
#   namespace: kube-system
# spec:
#   replicas: 1
#   revisionHistoryLimit: 10
#   selector:
#     matchLabels:
#       k8s-app: kubernetes-dashboard
#   template:
#     metadata:
#       labels:
#         k8s-app: kubernetes-dashboard
#     spec:
#       containers:
#       - name: kubernetes-dashboard
#         image: k8s.gcr.io/kubernetes-dashboard-amd64:v1.8.2
#         ports:
#         # - containerPort: 8443
#         #   protocol: TCP
#         - containerPort: 9090
#           protocol: TCP
#         args:
#           # - --auto-generate-certificates
#           # Uncomment the following line to manually specify Kubernetes API server Host
#           # If not specified, Dashboard will attempt to auto discover the API server and connect
#           # to it. Uncomment only if the default does not work.
#           # - --apiserver-host=https://10.16.50.3:6443
#           # - --tls-cert-file=tls.crt
#           # - --tls-key-file=tls.key
#           - --port=0
#           - --insecure-port=9090
#           # - --port=8443
#           - --insecure-bind-address=0.0.0.0
#           - --enable-insecure-login=true
#         volumeMounts:
#         - name: kubernetes-dashboard-certs
#           mountPath: /certs
#           # Create on-disk volume to store exec logs
#         - mountPath: /tmp
#           name: tmp-volume
#         # livenessProbe:
#         #   httpGet:
#         #     scheme: HTTPS
#         #     path: /
#         #     port: 8443
#           # initialDelaySeconds: 60
#           # periodSeconds: 10
#           # successThreshold: 1
#           # timeoutSeconds: 5
#       volumes:
#       - name: kubernetes-dashboard-certs
#         secret:
#           secretName: kubernetes-dashboard-certs
#       - name: tmp-volume
#         emptyDir: {}
#       serviceAccountName: kubernetes-dashboard
#       # Comment the following tolerations if Dashboard must not be deployed on master
#       tolerations:
#       - key: CriticalAddonsOnly
#         operator: Exists
#       - effect: NoSchedule
#         key: node-role.kubernetes.io/master
# EOF

# cat <<EOF | kubectl create -f -
# # ------------------- Dashboard Service ------------------- #
# kind: Service
# apiVersion: v1
# metadata:
#   labels:
#     k8s-app: kubernetes-dashboard
#     kubernetes.io/cluster-service: "true"
#   name: kubernetes-dashboard
#   namespace: kube-system
# spec:
#   selector:
#     k8s-app: kubernetes-dashboard
#   ports:
#     # - port: 443
#     #   targetPort: 8443
#     #   name: https
#     - port: 9090
#       targetPort: 9090
#       name: http
#   type: ClusterIP
# EOF

cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    kubernetes.io/tls-acme: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/add-base-url: "true"
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
  labels:
    app: kubernetes-dashboard
  name: ing-kubernetes-dashboard
  namespace: kube-system
spec:
  tls:
  - hosts:
    - etsys-sm-107.vms
    secretName: kubernetes-dashboard-certs
  rules:
  - host: etsys-sm-107.vms
    http:
      paths:
      - path: /dashboard
        backend:
          serviceName: kubernetes-dashboard
          servicePort: 9090
EOF


# kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml
