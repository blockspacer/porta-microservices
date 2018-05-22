#!/bin/bash
set -e

K8S_CLUSTER_DNS_IPV4="10.3.0.10"
K8S_SERVICE_NETWORK="10.3.0.0/21"
K8S_POD_NETWORK="10.2.0.0/16"
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
  ]
}
EOF

    sed -i "s/cgroup-driver=systemd/cgroup-driver=cgroupfs/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    sed -i "s/--cluster-dns=10.96.0.10/--cluster-dns=${K8S_CLUSTER_DNS_IPV4}/g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    sed -i '/KUBELET_KUBECONFIG_ARGS=/s/"$/ --fail-swap-on=false --eviction-hard=nodefs.available<1Gi,imagefs.available<1Gi --eviction-minimum-reclaim=nodefs.available=500Mi,imagefs.available=2Gi"/' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    
    setenforce 0 || true

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
    kubeadm init --ignore-preflight-errors=swap --pod-network-cidr ${K8S_POD_NETWORK} --service-cidr ${K8S_SERVICE_NETWORK} --feature-gates CoreDNS=true --token-ttl=0
    mkdir -p /home/porta-one/.kube
    cp -f /etc/kubernetes/admin.conf /home/porta-one/.kube/config
    chown -R porta-one:staff /home/porta-one/.kube

    kubectl scale --replicas=1 deploy/coredns -n kube-system
    kubectl taint nodes --all node-role.kubernetes.io/master-
}

function setup_network_addon {
    kubectl apply -f "https://cloud.weave.works/k8s/v1.8/net.yaml?env.IPALLOC_RANGE=${K8S_POD_NETWORK}"
}

kctl() {
    kubectl -n "monitoring" "$@"
}

function setup_monitoring {
    kubectl create namespace "monitoring"

    kctl apply -f manifests/prometheus-operator/

    printf "Waiting for Operator to register custom resource definitions..."
    until kctl get customresourcedefinitions servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get customresourcedefinitions prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get customresourcedefinitions alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    echo "done!"

    kctl apply -f manifests/node-exporter/
    kctl apply -f manifests/porta-node-exporter-radius/

    kctl apply -f manifests/grafana/
    kubectl apply -f manifests/prometheus/
}

# ============================================
install_prerequisites
install_net_plugin
setup_cluster
setup_network_addon
setup_monitoring