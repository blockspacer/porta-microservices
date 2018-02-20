#!/bin/bash -e

set -e 

if [ ! -e ./master-env.conf -o ! -e worker-env.conf ]; then 
    echo "ERROR: master-env.conf or worker-env.conf is missed"
    exit 1
fi

source ./master-env.conf
source ./worker-env.conf

if [ ! -e ./ct ]; then
    curl -L https://github.com/coreos/container-linux-config-transpiler/releases/download/v0.6.0/ct-v0.6.0-x86_64-unknown-linux-gnu -o ./ct
    chmod +x ./ct
fi

CWD=$(dirname $(readlink -f "$0"))
CLOUD_CONF=$CWD/cloud-conf-worker-${WORKER_PRIVATE_IPV4}.yaml
IGNITION_CONF=$CWD/cloud-conf-worker-${WORKER_PRIVATE_IPV4}.ign

# add general stuff
cat << EOF > $CLOUD_CONF
storage:
  files:
    - path: /etc/systemd/timesyncd.conf
      filesystem: root
      mode: 0644
      contents:
        inline: |
          [Time]
          NTP=time.domain.com
EOF

# add certificate authority
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/pki/ca.crt
      filesystem: root
      mode: 0644
      contents:
        inline: |
$(cat $CWD/CA/ca.crt | sed 's/^/          /')
    - path: /etc/kubernetes/pki/kubelet.crt
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/worker-${WORKER_PRIVATE_IPV4}/kubelet/kubelet.crt | sed 's/^/          /')
    - path: /etc/kubernetes/pki/kubelet.key
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/worker-${WORKER_PRIVATE_IPV4}/kubelet/kubelet.key | sed 's/^/          /')
EOF

# add kubernets network config
cat << EOF >> $CLOUD_CONF
    - path: /etc/cni/net.d/10-weave.conf
      filesystem: root
      mode: 0644
      contents:
        inline: |
          {
            "name": "weave",
            "type": "weave-net",
            "hairpinMode": true,
            "delegate": {
              "isDefaultGateway": true
            }
          }
EOF

# add kubernetes configs
# these files will be placed in /etc/kubernetes/

# add config for kubelet
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/kubelet.conf
      filesystem: root
      mode: 0600
      contents:
        inline: |
          apiVersion: v1
          clusters:
          - cluster:
              certificate-authority: /etc/kubernetes/pki/ca.crt
              server: https://${MASTER_PRIVATE_IPV4}:6443
            name: ${K8S_CLUSTER_NAME}
          contexts:
          - context:
              cluster: ${K8S_CLUSTER_NAME}
              user: default-auth
              namespace: default
            name: default-context
          current-context: default-context
          kind: Config
          preferences: {}
          users:
          - name: default-auth
            user:
              client-certificate: /etc/kubernetes/pki/kubelet.crt
              client-key: /etc/kubernetes/pki/kubelet.key
EOF

# add config for node bootstrapping
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/bootstrap-kubelet.conf
      filesystem: root
      mode: 0600
      contents:
        inline: |
          apiVersion: v1
          clusters:
          - cluster:
              certificate-authority: /etc/kubernetes/pki/ca.crt
              server: https://${MASTER_PRIVATE_IPV4}:6443
            name: ${K8S_CLUSTER_NAME}
          contexts:
          - context:
              cluster: ${K8S_CLUSTER_NAME}
              user: tls-bootstrap-token-user
            name: tls-bootstrap-token-user@${K8S_CLUSTER_NAME}
          current-context: tls-bootstrap-token-user@${K8S_CLUSTER_NAME}
          kind: Config
          preferences: {}
          users:
          - name: tls-bootstrap-token-user
            user:
              token: ${K8S_TOKEN_PUB}.${K8S_TOKEN_SECRET}
EOF

# add users
cat << EOF >> $CLOUD_CONF
passwd:
  users:
    - name: "porta-one"
      password_hash: "$(openssl passwd -1 -salt $(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 6 ; echo '') b0neynem)"
      groups:
       - "sudo"
EOF

# add systemd units
cat << EOF >> $CLOUD_CONF
systemd:
  units:
    - name: docker.service
      enabled: true
    - name: etcd-member.service
      enabled: false
    - name: settimezone.service
      enabled: true
      contents: |
        [Unit]
        Description=Set the time zone
 
        [Service]
        ExecStart=/usr/bin/timedatectl set-timezone UTC
        RemainAfterExit=yes
        Type=oneshot
    - name: kubelet.service
      enabled: true
      contents: |
        [Unit]
        Description=The primary agent to run pods
        Documentation=http://kubernetes.io/docs/admin/kubelet/
        After=docker.service
        Requires=docker.service
         
        [Service]
        Slice=system.slice
        Environment=KUBELET_IMAGE_TAG=${KUBELET_IMAGE_TAG}
        ExecStartPre=/usr/bin/mkdir -p /var/log/containers
        ExecStartPre=/usr/bin/mkdir -p /var/log/kubernetes
        ExecStartPre=/usr/bin/mkdir -p /etc/kubernetes/manifests
        ExecStartPre=/usr/bin/mkdir -p /opt/cni/bin
        ExecStartPre=/usr/bin/mkdir -p /var/lib/cni
        ExecStartPre=/usr/bin/mkdir -p /etc/cni/net.d
        Environment="RKT_RUN_ARGS=--uuid-file-save=/var/run/kubelet-pod.uuid \
          --net=host \
          --dns=host \
          --volume var-lib-rkt,kind=host,source=/var/lib/rkt \
          --mount volume=var-lib-rkt,target=/var/lib/rkt \
          --volume etc-cni-net,kind=host,source=/etc/cni/net.d \
          --mount volume=etc-cni-net,target=/etc/cni/net.d \
          --volume weave-net-bin,kind=host,source=/opt/cni/bin \
          --mount volume=weave-net-bin,target=/opt/weave-net/bin \
          --volume dns,kind=host,source=/etc/resolv.conf \
          --mount volume=dns,target=/etc/resolv.conf \
          --volume var-lib-cni,kind=host,source=/var/lib/cni \
          --mount volume=var-lib-cni,target=/var/lib/cni \
          --volume var-log,kind=host,source=/var/log \
          --mount volume=var-log,target=/var/log \
          --volume container,kind=host,source=/var/log/containers \
          --mount volume=container,target=/var/log/containers \
          --volume rkt,kind=host,source=/usr/bin/rkt \
          --mount volume=rkt,target=/usr/bin/rkt"
        ExecStart=/usr/lib/coreos/kubelet-wrapper \
          --bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf \
          --container-runtime=docker \
          --pod-manifest-path=/etc/kubernetes/manifests \
          --allow-privileged=true \
          --client-ca-file=/etc/kubernetes/pki/ca.crt \
          --authorization-mode=Webhook \
          --kubeconfig=/etc/kubernetes/kubelet.conf \
          --cluster-dns=${K8S_CLUSTER_DNS_IPV4} \
          --cluster-domain=${K8S_CLUSTER_DOMAIN} \
          --network-plugin=cni \
          --cni-conf-dir=/etc/cni/net.d \
          --cni-bin-dir=/opt/cni/bin \
          --cadvisor-port=0 \
          --hostname-override=${WORKER_PRIVATE_HOSTNAME}
        ExecStop=-/usr/bin/rkt stop --uuid-file=/var/run/kubelet-pod.uuid
        Restart=always
        RestartSec=10
         
        [Install]
        WantedBy=multi-user.target     
    - name: porta-adjust-confs.service
      enabled: true
      contents: |
        [Unit]
        Description=Adjust kubernets manifest and config files!
        Type=oneshot
        Requires=coreos-metadata.service
        After=coreos-metadata.service

        [Service]
        EnvironmentFile=/run/metadata/coreos
        ExecStartPre=/bin/bash -c "cat /run/metadata/coreos | grep HOSTNAME | awk -F '=' -p '{print \$2}' > /etc/hostname"
        ExecStart=/bin/bash -c "hostname -F /etc/hostname"

        [Install]
        WantedBy=multi-user.target
EOF


# add docker options
cat << EOF >> $CLOUD_CONF
docker:
  flags:
    - --iptables=false
    - --ip-masq=false
EOF

$CWD/ct -in-file $CLOUD_CONF -platform openstack-metadata -strict -out-file $IGNITION_CONF
rm -f $CLOUD_CONF
