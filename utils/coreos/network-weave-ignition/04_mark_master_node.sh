#!/bin/bash
set -e

# Mark node as 'master' role and add taint 'NoSchedule' - it meant only critical 
# pods can be scheduled on this node

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

kubectl label node ${MASTER_PUBLIC_HOSTNAME} node-role.kubernetes.io/master=""
kubectl taint nodes -l node-role.kubernetes.io/master="" node-role.kubernetes.io/master="":NoSchedule