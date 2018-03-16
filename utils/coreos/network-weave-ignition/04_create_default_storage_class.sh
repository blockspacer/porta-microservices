#!/bin/bash
set -e

# Installs default storage class to be used for PersistentVolumeClaim (PVC).
# The default class is openstack-cinder

cat << EOF | kubectl create -f -
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
  name: openstack-cinder
provisioner: kubernetes.io/cinder
parameters:
  type: iscsi
  availability: nova
EOF
