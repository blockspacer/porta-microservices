#!/bin/bash
set -e

if [ ! -e ./env.conf ]; then 
    echo "ERROR: env.conf is missed"
    exit 1
fi

source ./env.conf

CWD=$(pwd)
CA_LOCATION="${CWD}/CA"
ETCD_DIR="${CA_LOCATION}/etcd"
API_DIR="${CA_LOCATION}/apiserver"
API_KUBELET_CLIENT_DIR="${CA_LOCATION}/apiserver-kubelet-client"
KUBELET_DIR="${CA_LOCATION}/kubelet"
HELM_DIR="${CA_LOCATION}/helm"
DASHBOARD_DIR="${CA_LOCATION}/dashboard"
CONTR_MANAGER_DIR="${CA_LOCATION}/controller-manager"
SCHEDULER_DIR="${CA_LOCATION}/scheduler"
ADMIN_DIR="${CA_LOCATION}/admin"
SERVICE_ACCOUNT_DIR="${CA_LOCATION}/service-account"

mkdir -p ${CA_LOCATION} || true
cd ${CA_LOCATION}
mkdir -p ${ETCD_DIR} || true
mkdir -p ${API_DIR} || true
mkdir -p ${API_KUBELET_CLIENT_DIR} || true
mkdir -p ${KUBELET_DIR} || true
mkdir -p ${HELM_DIR} || true
mkdir -p ${DASHBOARD_DIR} || true
mkdir -p ${CONTR_MANAGER_DIR} || true
mkdir -p ${SCHEDULER_DIR} || true
mkdir -p ${SERVICE_ACCOUNT_DIR} || true
mkdir -p ${ADMIN_DIR} || true

# ================================================================================
echo "Creating Certificate Authority"
# generate the root CA private key

openssl genrsa -out ca.key 2048
# openssl req -x509 -new -nodes -key ca.key -subj "/CN=cluster-admin/O=system:masters" -days 10000 -out ca.crt
openssl req -x509 -new -nodes -key ca.key -subj "/CN=kubernetes" -days 10000 -out ca.crt
# ================================================================================

function cert_etcd {
    echo "Creating certificates for Etcd"
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
    cd ${SERVICE_ACCOUNT_DIR}

    # openssl genrsa -out sa.key 2048
    openssl genpkey -algorithm RSA -out sa.key -pkeyopt rsa_keygen_bits:2048
    openssl rsa -pubout -in sa.key -out sa.pub
}
# ================================================================================

function cert_helm {
    echo "Creating certificates for Helm"
    cd ${HELM_DIR}

    CN="cluster-admin"
    openssl genrsa -out helm.key 2048

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
IP.2 = 127.0.0.1
EOF

    openssl req -new -key helm.key -out helm.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in helm.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out helm.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

function cert_dashboard {
    echo "Creating certificates for Dashboard"
    cd ${DASHBOARD_DIR}

    CN="cluster-dashboard"
    openssl genrsa -out dashboard.key 2048

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

    openssl req -new -key dashboard.key -out dashboard.csr -config csr.conf -subj "/CN=${CN}"

    openssl x509 -req -in dashboard.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/ca.key \
    -CAcreateserial -out dashboard.crt -days 10000 -extensions v3_ext -extfile csr.conf
}
# ================================================================================

# ==================== MAIN ======================================================
cert_etcd
cert_api
cert_api_kubelet_client
cert_kubelet
cert_scheduler
cert_controller_manager
cert_admin
cert_service_account
cert_helm
cert_dashboard

exit


# write into config DNS names as well like:
# DNS.1 = domain.com
# DNS.2 = domain-1.com
# ....
# echo "Creating Master certificates"
cat << EOF > ${TMP_DIR}/openssl.cnf
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
x509_extensions    = v3_ca
req_extensions     = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[ v3_ca ]
keyUsage             = critical,keyCertSign, cRLSign
basicConstraints     = critical,CA:TRUE
subjectKeyIdentifier = hash

[ v3_req ]
keyUsage             = critical,digitalSignature, keyEncipherment, nonRepudiation
extendedKeyUsage     = clientAuth, serverAuth
basicConstraints     = critical,CA:FALSE
subjectKeyIdentifier = hash
subjectAltName       = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = ${K8S_CLUSTER_NAME}
DNS.3 = ${K8S_CLUSTER_NAME}.default
DNS.4 = ${K8S_CLUSTER_NAME}.default.svc
DNS.5 = ${K8S_CLUSTER_NAME}.default.svc.cluster.local
DNS.6 = kube-apiserver
DNS.7 = kube-admin
DNS.8 = ${MASTER_PUBLIC_HOSTNAME}
DNS.9 = ${MASTER_PUBLIC_HOSTNAME}.local
DNS.10 = ${MASTER_PUBLIC_HOSTNAME}.novalocal
IP.1  = 127.0.0.1
IP.2  = ${K8S_SERVICE_IP}
IP.3  = ${MASTER_PUBLIC_IPV4}
EOF



echo "Creating certificates for Etcd"
# generate the root CA certificate
openssl req -x509 -new -extensions v3_ca -key ${CA_LOCATION}/porta-ca.key -days 10000 -out ${CA_LOCATION}/etcd-ca.crt -subj "/CN=etcd" -config ${TMP_DIR}/openssl.cnf

# generate client/server private key
openssl genrsa -out ${CA_LOCATION}/etcd-node-key.pem 2048

# generate client/server certificate request
openssl req -new -key ${CA_LOCATION}/etcd-node-key.pem -newkey rsa:2048 -nodes -config ${TMP_DIR}/openssl.cnf -subj "/CN=etcd-node" -outform pem \
-out ${CA_LOCATION}/etcd-node-req.pem -keyout ${CA_LOCATION}/etcd-node-req.key

# sign client/server certificate request
openssl x509 -req -in ${CA_LOCATION}/etcd-node-req.pem -CA ${CA_LOCATION}/etcd-ca.crt -CAkey ${CA_LOCATION}/porta-ca.key -CAcreateserial \
-out ${CA_LOCATION}/etcd-node.crt -days 10000 -extensions v3_req -extfile ${TMP_DIR}/openssl.cnf


echo "Creating Admin certificates for kubelet"
# generate the CA private key
openssl genrsa -out ${CA_LOCATION}/kubelet-admin-key.pem 2048

# generate client/server certificate request
openssl req -new -key ${CA_LOCATION}/kubelet-admin-key.pem -newkey rsa:2048 -nodes -config ${TMP_DIR}/openssl.cnf -subj "/CN=admin-kubelet" -outform pem \
-out ${CA_LOCATION}/kubelet-admin-req.pem -keyout ${CA_LOCATION}/kubelet-admin-req.key

# sign client/server certificate request
openssl x509 -req -in ${CA_LOCATION}/kubelet-admin-req.pem -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/porta-ca.key -CAcreateserial \
-out ${CA_LOCATION}/kubelet-admin.pem -days 10000


# scp -i ${SSH_KEY} ./controller-install.sh core@${MASTER_HOST}:~/
# scp -r -i ${SSH_KEY} ${CA_LOCATION} core@${MASTER_HOST}:~/ || true
# scp -i ${SSH_KEY} /usr/local/bin/kubectl core@${MASTER_HOST}:~/

# ssh -i ${SSH_KEY} core@${MASTER_HOST} \
# 'sudo mkdir -p /var/lib/etcd/ssl/;
# sudo mkdir -p /etc/kubernetes/ssl/;
# sudo chmod 600 CA/*;
# sudo cp CA/apiserver.pem /etc/kubernetes/ssl/apiserver.pem; sudo cp CA/apiserver-key.pem /etc/kubernetes/ssl/apiserver-key.pem; \
# sudo cp CA/admin.pem /etc/kubernetes/ssl/admin.pem; sudo cp CA/admin-key.pem /etc/kubernetes/ssl/admin-key.pem; \
# sudo cp CA/ca.crt /etc/kubernetes/ssl/; \
# sudo cp CA/ca.crt /etc/ssl/certs/;'

# ssh -i ${SSH_KEY} core@${MASTER_HOST} 'sudo mkdir -p /var/lib/etcd/ssl/ /home/core/CA'
# scp -i ${SSH_KEY} ${CA_LOCATION}/ca.crt core@${MASTER_HOST}:~/CA/
# scp -i ${SSH_KEY} ${CA_LOCATION}/etcd-node-key.pem core@${MASTER_HOST}:~/CA/
# scp -i ${SSH_KEY} ${CA_LOCATION}/etcd-node.pem core@${MASTER_HOST}:~/CA/
# ssh -i ${SSH_KEY} core@${MASTER_HOST} \
# 'cd ~/CA/; sudo cp ./ca.crt /var/lib/etcd/ssl/; sudo cp ./ca.crt /etc/ssl/certs/;
# sudo cp ./etcd-node-key.pem /var/lib/etcd/ssl/;
# sudo cp ./etcd-node.pem /var/lib/etcd/ssl/'
exit


echo "Creating Worker certificates"
cat << EOF > ${TMP_DIR}/worker-openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = \$ENV::WORKER_IP
EOF

IFS=';' read -ra ES <<< "$WORKERS"
for WORKER in "${ES[@]}"; do
    IFS=',' read IP FQDN <<< $WORKER
    WORKER_CA_LOCATION=${CA_LOCATION}/worker_${IP}
    mkdir -p ${WORKER_CA_LOCATION}
    echo "ip=$IP fqdn=$FQDN"
    openssl genrsa -out ${WORKER_CA_LOCATION}/${FQDN}-worker-key.pem 2048
    WORKER_IP=${IP} 
    export WORKER_IP
    openssl req -new -key ${WORKER_CA_LOCATION}/${FQDN}-worker-key.pem -out ${WORKER_CA_LOCATION}/${FQDN}-worker.csr -subj "/CN=${FQDN}" -config ${TMP_DIR}/worker-openssl.cnf
    openssl x509 -req -in ${WORKER_CA_LOCATION}/${FQDN}-worker.csr -CA ${CA_LOCATION}/ca.crt -CAkey ${CA_LOCATION}/porta-ca.key -CAcreateserial -out ${WORKER_CA_LOCATION}/${FQDN}-worker.pem -days 365 -extensions v3_req -extfile ${TMP_DIR}/worker-openssl.cnf

    cp ${CA_LOCATION}/ca.crt ${WORKER_CA_LOCATION}/
    # cp ${CA_LOCATION}/flannel/* ${WORKER_CA_LOCATION}/
    scp -i ${SSH_KEY} ./worker-install.sh core@${IP}:~/
    ssh -i ${SSH_KEY} core@${IP} "mkdir CA || true"
    scp -i ${SSH_KEY} ${WORKER_CA_LOCATION}/* core@${IP}:~/CA/
    # scp -r -i ${SSH_KEY} ${CA_FLANNEL_LOCATION} core@${IP}:~/CA/
    ssh -i ${SSH_KEY} core@${IP} "sudo mkdir -p /etc/kubernetes/ssl/; \
sudo chmod 600 CA/*; \
sudo cp CA/${FQDN}-worker.pem /etc/kubernetes/ssl/worker.pem; \
sudo cp CA/${FQDN}-worker-key.pem /etc/kubernetes/ssl/worker-key.pem; \
sudo cp CA/ca.crt /etc/kubernetes/ssl/ca.crt; \
sudo cp CA/ca.crt /etc/ssl/certs/ca.crt"
# sudo cp CA/flannel.pem /etc/ssl/certs/pod-network.pem; sudo cp CA/flannel-key.pem /etc/ssl/certs/pod-network-key.pem; \
done
