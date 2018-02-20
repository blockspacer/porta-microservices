#!/bin/bash
set -e

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(dirname $(readlink -f "$0"))
CA_LOCATION="${CWD}/CA"
ETCD_DIR="${CA_LOCATION}/etcd"
API_DIR="${CA_LOCATION}/apiserver"
API_KUBELET_CLIENT_DIR="${CA_LOCATION}/apiserver-kubelet-client"
KUBELET_DIR="${CA_LOCATION}/kubelet"
HELM_DIR="${CA_LOCATION}/helm"
MONITOR_DIR="${CA_LOCATION}/monitoring"
CONTR_MANAGER_DIR="${CA_LOCATION}/controller-manager"
SCHEDULER_DIR="${CA_LOCATION}/scheduler"
ADMIN_DIR="${CA_LOCATION}/admin"
SERVICE_ACCOUNT_DIR="${CA_LOCATION}/service-account"

# ================================================================================
function cert_ca {
    echo "Creating Certificate Authority"
    # generate the root CA private key

    mkdir -p ${CA_LOCATION} || true
    cd ${CA_LOCATION}

    openssl genrsa -out ca.key 2048
    # openssl req -x509 -new -nodes -key ca.key -subj "/CN=cluster-admin/O=system:masters" -days 10000 -out ca.crt
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=kubernetes/O=PortaOne, Inc" -days 10000 -out ca.crt
}
# ================================================================================

function cert_etcd {
    echo "Creating certificates for Etcd"
    mkdir -p ${ETCD_DIR} || true
    cd ${ETCD_DIR}

    CN="etcd"
    openssl genrsa -out etcd.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
    
[ dn ]
CN = ${CN}

[ req_ext ]
subjectAltName = @alt_names
    
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = ${MASTER_PUBLIC_HOSTNAME}
IP.1 = ${MASTER_PUBLIC_IPV4}
IP.2 = ${K8S_SERVICE_IP}
IP.3 = ${MASTER_PRIVATE_IPV4}
EOF

    openssl req -new -key etcd.key -out etcd.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in etcd.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out etcd.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_api {
    echo "Creating certificates for API server"
    mkdir -p ${API_DIR} || true
    cd ${API_DIR}

    CN="kube-apiserver"
    openssl genrsa -out apiserver.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
CN = ${CN}

[ req_ext ]
subjectAltName = @alt_names
    
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = ${K8S_CLUSTER_NAME}
DNS.2 = ${K8S_CLUSTER_NAME}.default
DNS.3 = ${K8S_CLUSTER_NAME}.default.svc
DNS.4 = ${K8S_CLUSTER_NAME}.default.svc.cluster
DNS.5 = ${K8S_CLUSTER_NAME}.default.svc.cluster.local
DNS.6 = ${MASTER_PUBLIC_HOSTNAME}
IP.1 = ${MASTER_PUBLIC_IPV4}
IP.2 = ${K8S_SERVICE_IP}
IP.3 = ${MASTER_PRIVATE_IPV4}
EOF

    openssl req -new -key apiserver.key -out apiserver.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in apiserver.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out apiserver.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_api_kubelet_client {
    echo "Creating certificates for Kubelet API client"
    mkdir -p ${API_KUBELET_CLIENT_DIR} || true
    cd ${API_KUBELET_CLIENT_DIR}

    CN="kube-apiserver-kubelet-client"
    openssl genrsa -out apiserver-kubelet-client.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${CN}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=clientAuth
EOF

    openssl req -new -key apiserver-kubelet-client.key -out apiserver-kubelet-client.csr -config csr.conf -subj "/CN=${CN}/O=system:masters"

    openssl x509 -req -in apiserver-kubelet-client.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out apiserver-kubelet-client.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_kubelet {
    echo "Creating certificates for Kubelet"
    mkdir -p ${KUBELET_DIR} || true
    cd ${KUBELET_DIR}

    CN="system:node:${MASTER_PUBLIC_HOSTNAME}"

    openssl genrsa -out kubelet.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
    
[ dn ]
CN = ${CN}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=clientAuth
EOF

    openssl req -new -key kubelet.key -out kubelet.csr -config csr.conf -subj "/O=system:nodes/CN=${CN}"

    openssl x509 -req -in kubelet.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out kubelet.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_controller_manager {
    echo "Creating certificates for Controller-Manager"
    mkdir -p ${CONTR_MANAGER_DIR} || true
    cd ${CONTR_MANAGER_DIR}

    CN="system:kube-controller-manager"

    openssl genrsa -out controller-manager.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${CN}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=clientAuth
EOF

    openssl req -new -key controller-manager.key -out controller-manager.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in controller-manager.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out controller-manager.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_scheduler {
    echo "Creating certificates for Scheduler"
    mkdir -p ${SCHEDULER_DIR} || true
    cd ${SCHEDULER_DIR}

    CN="system:kube-scheduler"

    openssl genrsa -out scheduler.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${CN}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=clientAuth
EOF

    openssl req -new -key scheduler.key -out scheduler.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in scheduler.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out scheduler.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_admin {
    echo "Creating certificates for Admin"
    mkdir -p ${ADMIN_DIR} || true
    cd ${ADMIN_DIR}

    CN="kubernetes-admin"

    openssl genrsa -out admin.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn

[ dn ]
CN = ${CN}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=clientAuth
EOF

    openssl req -new -key admin.key -out admin.csr -config csr.conf -subj "/CN=${CN}/O=system:masters"

    openssl x509 -req -in admin.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out admin.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_service_account {
    echo "Creating certificates for Service Account"
    mkdir -p ${SERVICE_ACCOUNT_DIR} || true
    cd ${SERVICE_ACCOUNT_DIR}

    # openssl genrsa -out sa.key 2048
    openssl genpkey -algorithm RSA -out sa.key -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in sa.key -out sa.pub
}
# ================================================================================

# function cert_helm {
#     echo "Creating certificates for Helm"
#     mkdir -p ${HELM_DIR} || true
#     cd ${HELM_DIR}

#     CN="cluster-admin"
#     openssl genrsa -out helm.key 2048

#     cat << EOF > ./csr.conf
# [ req ]
# default_bits = 2048
# prompt = no
# default_md = sha256
# req_extensions = req_ext
# distinguished_name = dn
    
# [ dn ]
# CN = ${CN}

# [ req_ext ]
# subjectAltName = @alt_names
    
# [ v3_ext ]
# authorityKeyIdentifier=keyid,issuer:always
# basicConstraints=CA:FALSE
# keyUsage=keyEncipherment,dataEncipherment
# extendedKeyUsage=serverAuth,clientAuth
# subjectAltName=@alt_names

# [ alt_names ]
# DNS.1 = ${MASTER_PUBLIC_HOSTNAME}
# IP.1 = ${MASTER_PUBLIC_IPV4}
# IP.2 = 127.0.0.1
# EOF

#     openssl req -new -key helm.key -out helm.csr -config csr.conf -subj "/CN=${CN}"

#     openssl x509 -req -in helm.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
#     -CAcreateserial -out helm.crt -days 10000 -extensions v3_ext -extfile csr.conf
# }
# ================================================================================

function cert_monitor {
    echo "Creating certificates for Monitor and Metrics"
    mkdir -p ${MONITOR_DIR} || true
    cd ${MONITOR_DIR}

    CN="Monitor & Metrics dashboard"
    openssl genrsa -out monitor.key 2048

    cat << EOF > ./csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
    
[ dn ]
CN = ${CN}

[ req_ext ]
subjectAltName = @alt_names

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names

[ alt_names ]
DNS.1 = ${MASTER_PUBLIC_HOSTNAME}
IP.1 = ${MASTER_PUBLIC_IPV4}
EOF

    openssl req -new -key monitor.key -out monitor.csr -config csr.conf -subj "/CN=${CN}/O=PortaOne, Inc"

    openssl x509 -req -in monitor.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out monitor.crt -days 10000 -extensions v3_ext -extfile csr.conf
}

# ==================== MAIN ======================================================
cert_ca
cert_etcd
cert_api
cert_api_kubelet_client
cert_kubelet
cert_scheduler
cert_controller_manager
cert_admin
cert_service_account
# cert_helm
cert_monitor
