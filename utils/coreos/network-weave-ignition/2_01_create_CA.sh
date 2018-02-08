#!/bin/bash
set -e

if [ ! -e ./master-env.conf -o ! -e worker-env.conf]; then 
    echo "ERROR: master-env.conf or worker-env.conf is missed"
    exit 1
fi

source ./master-env.conf
source ./worker-env.conf

CWD=$(pwd)
CA_LOCATION="${CWD}/CA"
WORKER_DIR="${CA_LOCATION}/worker-${WORKER_PRIVATE_IPV4}"
KUBELET_DIR="${WORKER_DIR}/kubelet"


mkdir -p ${CA_LOCATION} || true
cd ${CA_LOCATION}
mkdir -p ${KUBELET_DIR} || true

# ================================================================================

function cert_kubelet {
    echo "Creating certificates for Kubelet"
    cd ${KUBELET_DIR}

    CN="system:node:${WORKER_PRIVATE_HOSTNAME}"

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

# ==================== MAIN ======================================================
# Master Node
cert_kubelet
