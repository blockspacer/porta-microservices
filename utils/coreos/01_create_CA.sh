#!/bin/bash
set -e

# The IP address of the Kubernetes API Service. The K8S_SERVICE_IP will be the first IP in the SERVICE_IP_RANGE
# discussed in the deployment guide. The first IP in the default range of 10.3.0.0/24 will be 10.3.0.1.
# If the SERVICE_IP_RANGE was changed from the default, this value must be updated as well.
export K8S_SERVICE_IP="10.3.0.1"

# The address of the master node. In most cases this will be the publicly routable IP or hostname of the node.
# Worker nodes must be able to reach the master node(s) via this address on port 443. Additionally, external 
# clients (such as an administrator using kubectl) will also need access, since this will run the Kubernetes API endpoint.
export MASTER_HOST="10.16.99.101"

# The list of workers in format: IP_1,FQDN_1;IP_2,FQDN_2
export WORKERS="10.16.99.201,coreos201;10.16.99.202,coreos202"

export CA_LOCATION="./CA"

mkdir -p ${CA_LOCATION}
openssl genrsa -out ${CA_LOCATION}/ca-key.pem 2048
openssl req -x509 -new -nodes -key ${CA_LOCATION}/ca-key.pem -days 10000 -out ${CA_LOCATION}/ca.pem -subj "/CN=kube-ca"

cat << EOF > openssl.cnf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = ${K8S_SERVICE_IP}
IP.2 = ${MASTER_HOST}
EOF


openssl genrsa -out ${CA_LOCATION}/apiserver-key.pem 2048
openssl req -new -key ${CA_LOCATION}/apiserver-key.pem -out ${CA_LOCATION}/apiserver.csr -subj "/CN=kube-apiserver" -config openssl.cnf
openssl x509 -req -in ${CA_LOCATION}/apiserver.csr -CA ${CA_LOCATION}/ca.pem -CAkey ${CA_LOCATION}/ca-key.pem -CAcreateserial -out ${CA_LOCATION}/apiserver.pem -days 365 -extensions v3_req -extfile openssl.cnf

cat << EOF > worker-openssl.cnf
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
    openssl req -new -key ${WORKER_CA_LOCATION}/${FQDN}-worker-key.pem -out ${WORKER_CA_LOCATION}/${FQDN}-worker.csr -subj "/CN=${FQDN}" -config worker-openssl.cnf
    openssl x509 -req -in ${WORKER_CA_LOCATION}/${FQDN}-worker.csr -CA ${CA_LOCATION}/ca.pem -CAkey ${CA_LOCATION}/ca-key.pem -CAcreateserial -out ${WORKER_CA_LOCATION}/${FQDN}-worker.pem -days 365 -extensions v3_req -extfile worker-openssl.cnf

    cp ${CA_LOCATION}/ca.pem ${WORKER_CA_LOCATION}/
    scp -i ~/.ssh/atomic ./worker-install.sh core@${IP}:~/
    ssh -i ~/.ssh/atomic core@${IP} "mkdir CA || true"
    scp -i ~/.ssh/atomic ${WORKER_CA_LOCATION}/* core@${IP}:~/CA/
    ssh -i ~/.ssh/atomic core@${IP} "sudo mkdir -p /etc/kubernetes/ssl/; sudo cp CA/${FQDN}-worker.pem /etc/kubernetes/ssl/worker.pem; sudo cp CA/${FQDN}-worker-key.pem /etc/kubernetes/ssl/worker-key.pem; sudo cp CA/ca.pem /etc/kubernetes/ssl/ca.pem; sudo chmod 600 /etc/kubernetes/ssl/*"


done

openssl genrsa -out ${CA_LOCATION}/admin-key.pem 2048
openssl req -new -key ${CA_LOCATION}/admin-key.pem -out ${CA_LOCATION}/admin.csr -subj "/CN=kube-admin"
openssl x509 -req -in ${CA_LOCATION}/admin.csr -CA ${CA_LOCATION}/ca.pem -CAkey ${CA_LOCATION}/ca-key.pem -CAcreateserial -out ${CA_LOCATION}/admin.pem -days 365

scp -i ~/.ssh/atomic ./controller-install.sh core@${MASTER_HOST}:~/
ssh -i ~/.ssh/atomic core@${MASTER_HOST} "mkdir CA || true"
scp -i ~/.ssh/atomic ${CA_LOCATION}/* core@${MASTER_HOST}:~/CA/ || true

ssh -i ~/.ssh/atomic core@${MASTER_HOST} 'sudo mkdir -p /etc/kubernetes/ssl/; sudo cp CA/apiserver.pem /etc/kubernetes/ssl/apiserver.pem; sudo cp CA/apiserver-key.pem /etc/kubernetes/ssl/apiserver-key.pem; sudo cp CA/ca.pem /etc/kubernetes/ssl/ca.pem; sudo chmod 600 /etc/kubernetes/ssl/*'
