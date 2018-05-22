#!/bin/bash
set -e

K8S_CLUSTER_DNS_IPV4="10.3.0.10"
K8S_MASTER_ADDR="192.168.5.15:6443"
K8S_TOKEN="uvaooa.mr1vwjoyi1p0nwvp"
K8S_HASH="sha256:969103fc8bfda5f8b963137884b5d7e388c94af38b72b3b6d091aec02256b27f"
# ================================================

function install_prerequisites {
    if [ "x$(hostname | grep 'service.net428595.oraclevcn.com')" = "x" ]; then
        hostname $(hostname).service.net428595.oraclevcn.com
        echo $(hostname) > /etc/hostname
    fi

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
    
    yum install -y docker conntrack-tools.x86_64 kubelet ipvsadm kubeadm
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
  ]
}
EOF

    sed -i "s/cgroup-driver=systemd/cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sed -i "s/--cluster-dns=10.96.0.10/--cluster-dns=${K8S_CLUSTER_DNS_IPV4}/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    sed -i '/KUBELET_KUBECONFIG_ARGS=/s/"$/ --fail-swap-on=false --node-labels=kubernetes.io\/role=pb-radius --eviction-hard=nodefs.available<1Gi,imagefs.available<1Gi --eviction-minimum-reclaim=nodefs.available=500Mi,imagefs.available=2Gi"/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    
    setenforce 0 || true

    systemctl daemon-reload
    systemctl enable docker
    systemctl enable kubelet
    systemctl start docker
    systemctl start kubelet

    cat << EOF >> /etc/cron.d/porta-k8s
SHELL=/bin/bash
BASH_ENV=/etc/profile
    
* * * * * root mkdir -p /var/run/porta-one/radiusd && ${PORTARADIUS_HOME:='/home/porta-radius'}/utils/rad mon -type local > /var/run/porta-one/radiusd/radiusd-local.stats
* * * * * root mkdir -p /var/run/porta-one/radiusd && ${PORTARADIUS_HOME:='/home/porta-radius'}/utils/rad mon -type cluster > /var/run/porta-one/radiusd/radiusd-cluster.stats
EOF
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

function join_cluster {
    kubeadm join $K8S_MASTER_ADDR --ignore-preflight-errors=cri,swap --token $K8S_TOKEN --discovery-token-ca-cert-hash $K8S_HASH
}

# ============================================
install_prerequisites
install_net_plugin
join_cluster