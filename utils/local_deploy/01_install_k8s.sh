#!/bin/bash
set -e

# etcd
# - --listen-peer-urls=https://127.0.0.1:2380

K8S_CLUSTER_DNS_IPV4="10.3.0.10"
K8S_SERVICE_NETWORK="10.3.0.0/21"
K8S_POD_NETWORK="10.2.0.0/16"
K8S_ADVERTISE_ADDR="10.1.0.1"
# ================================================

function install_prerequisites {
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

    if [ ! -e /usr/bin/crictl ]; then
        wget https://github.com/kubernetes-incubator/cri-tools/releases/download/v1.0.0-beta.1/crictl-v1.0.0-beta.1-linux-amd64.tar.gz
        tar -xf ./crictl-v1.0.0-beta.1-linux-amd64.tar.gz
        cp -f ./crictl /usr/bin
    fi
    
    yum install -y docker conntrack-tools.x86_64 kubelet kubectl ipvsadm kubeadm
    modprobe ip_vs || true
    modprobe br_netfilter || true
    
    cat << EOF > /etc/sysctl.d/99-k8s.conf
net.ipv4.conf.all.arp_filter=1
net.ipv4.conf.default.arp_filter=1
net.ipv4.conf.default.rp_filter=2
net.ipv4.conf.ens3.arp_filter=1
net.ipv4.conf.ens3.rp_filter=2
net.bridge.bridge-nf-call-arptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
EOF
    sysctl --system

    cat << EOF > /etc/sysconfig/docker-network
DOCKER_NETWORK_OPTIONS="--iptables=false --ip-masq=false"
EOF

    mkdir -p /etc/docker/ || true
    cat << EOF > /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "log-opts": {
      "max-size": "50m",
      "max-file": "3"
  }
}
EOF

    # sed -i "s/cgroup-driver=systemd/cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    # sed -i "s/--cluster-dns=10.96.0.10/--cluster-dns=${K8S_CLUSTER_DNS_IPV4}/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    # sed -i '/KUBELET_KUBECONFIG_ARGS=/s/"$/ --fail-swap-on=false --eviction-hard=nodefs.available<1Gi,imagefs.available<1Gi --eviction-minimum-reclaim=nodefs.available=500Mi,imagefs.available=2Gi"/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    cat << EOF > /etc/systemd/system/kubelet.service.d/90-local.conf
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf --fail-swap-on=false --eviction-hard=nodefs.available<1Gi,imagefs.available<1Gi --eviction-minimum-reclaim=nodefs.available=500Mi,imagefs.available=2Gi"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/usr/libexec/cni"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.3.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authentication-token-webhook --authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs"
EOF

    setenforce 0 || true
    systemctl disable iptables
    systemctl stop iptables

    systemctl daemon-reload
    systemctl enable docker
    systemctl enable kubelet
    systemctl start docker
    systemctl start kubelet
}

function install_net_plugin {
    curl -L git.io/weave -o ./weave
    chmod a+x ./weave

    mkdir -p /opt/cni/bin
    mkdir -p /etc/cni/net.d
    ./weave setup

    cat << EOF > /etc/cni/net.d/10-weave.conf
{
    "name": "weave",
    "type": "weave-net",
    "hairpinMode": true,
    "delegate":
    {
        "isDefaultGateway": true
    }
}
EOF
}

function setup_cluster {
    kubeadm init --ignore-preflight-errors=swap --pod-network-cidr ${K8S_POD_NETWORK} --service-cidr ${K8S_SERVICE_NETWORK} --feature-gates CoreDNS=true --token-ttl=0 --apiserver-advertise-address ${K8S_ADVERTISE_ADDR}

    mkdir -p /home/yakut/.kube
    cp -f /etc/kubernetes/admin.conf /home/yakut/.kube/config
    chown -R yakut:yakut /home/yakut/.kube

    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl scale --replicas=1 deploy/coredns -n kube-system
}

function setup_network_addon {
    kubectl apply -f "https://cloud.weave.works/k8s/v1.8/net.yaml?env.IPALLOC_RANGE=${K8S_POD_NETWORK}"
}

# ============================================
install_prerequisites
install_net_plugin
setup_cluster
setup_network_addon