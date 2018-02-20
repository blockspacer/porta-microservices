#!/bin/bash -e

set -e 

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

if [ ! -e ./ct ]; then
    curl -L https://github.com/coreos/container-linux-config-transpiler/releases/download/v0.6.0/ct-v0.6.0-x86_64-unknown-linux-gnu -o ./ct
    chmod +x ./ct
fi

CWD=$(dirname $(readlink -f "$0"))
CLOUD_CONF=$CWD/cloud-conf-master.yaml
IGNITION_CONF=$CWD/cloud-conf-master.ign

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

# add certificates for api-server
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/pki/apiserver.crt
      filesystem: root
      mode: 0644
      contents:
        inline: |
$(cat $CWD/CA/apiserver/apiserver.crt | sed 's/^/          /')
    - path: /etc/kubernetes/pki/apiserver.key
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/apiserver/apiserver.key | sed 's/^/          /')
    - path: /etc/kubernetes/pki/apiserver-kubelet-client.crt
      filesystem: root
      mode: 0644
      contents:
        inline: |
$(cat $CWD/CA/apiserver-kubelet-client/apiserver-kubelet-client.crt | sed 's/^/          /')
    - path: /etc/kubernetes/pki/apiserver-kubelet-client.key
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/apiserver-kubelet-client/apiserver-kubelet-client.key | sed 's/^/          /')
EOF

# add certificate authority
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/pki/ca.crt
      filesystem: root
      mode: 0644
      contents:
        inline: |
$(cat $CWD/CA/ca.crt | sed 's/^/          /')
    - path: /etc/kubernetes/pki/ca.key
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/ca.key | sed 's/^/          /')
EOF

# add certificates for service account
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/pki/sa.key
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/service-account/sa.key | sed 's/^/          /')
    - path: /etc/kubernetes/pki/sa.pub
      filesystem: root
      mode: 0600
      contents:
        inline: |
$(cat $CWD/CA/service-account/sa.pub | sed 's/^/          /')

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

# add config for controller-manager
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/controller-manager.conf
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
              user: system:kube-controller-manager
            name: system:kube-controller-manager@${K8S_CLUSTER_NAME}
          current-context: system:kube-controller-manager@${K8S_CLUSTER_NAME}
          kind: Config
          preferences: {}
          users:
          - name: system:kube-controller-manager
            user:
              client-certificate-data: $(cat $CWD/CA/controller-manager/controller-manager.crt | base64 | tr -d '\r\n')
              client-key-data: $(cat $CWD/CA/controller-manager/controller-manager.key | base64 | tr -d '\r\n')
EOF

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
              user: system:node:${MASTER_PUBLIC_HOSTNAME}
            name: system:node:${MASTER_PUBLIC_HOSTNAME}@${K8S_CLUSTER_NAME}
          current-context: system:node:${MASTER_PUBLIC_HOSTNAME}@${K8S_CLUSTER_NAME}
          kind: Config
          preferences: {}
          users:
          - name: system:node:${MASTER_PUBLIC_HOSTNAME}
            user:
              client-certificate-data: $(cat $CWD/CA/kubelet/kubelet.crt | base64 | tr -d '\r\n')
              client-key-data: $(cat $CWD/CA/kubelet/kubelet.key | base64 | tr -d '\r\n')
EOF

# add config for scheduler
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/scheduler.conf
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
              user: system:kube-scheduler
            name: system:kube-scheduler@${K8S_CLUSTER_NAME}
          current-context: system:kube-scheduler@${K8S_CLUSTER_NAME}
          kind: Config
          preferences: {}
          users:
          - name: system:kube-scheduler
            user:
              client-certificate-data: $(cat $CWD/CA/scheduler/scheduler.crt | base64 | tr -d '\r\n')
              client-key-data: $(cat $CWD/CA/scheduler/scheduler.key | base64 | tr -d '\r\n')
EOF

# add kubernets manifest
cat << EOF >> $CLOUD_CONF
    - path: /etc/kubernetes/manifests/kube-apiserver.yaml
      filesystem: root
      mode: 0600
      contents:
        inline: |
          apiVersion: v1
          kind: Pod
          metadata:
            annotations:
              scheduler.alpha.kubernetes.io/critical-pod: ""
            labels:
              component: kube-apiserver
              tier: control-plane
            name: kube-apiserver
            namespace: kube-system
          spec:
            containers:
            - command:
              - kube-apiserver
              - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
              - --admission-control=Initializers,NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,NodeRestriction,ResourceQuota
              - --allow-privileged=true
              - --advertise-address=${MASTER_PRIVATE_IPV4}
              - --kubelet-client-certificate=/etc/kubernetes/pki/apiserver-kubelet-client.crt
              - --secure-port=6443
              - --service-account-key-file=/etc/kubernetes/pki/sa.pub
              - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
              - --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
              - --service-cluster-ip-range=${K8S_SERVICE_NETWORK}
              - --client-ca-file=/etc/kubernetes/pki/ca.crt
              - --insecure-port=0
              - --kubelet-client-key=/etc/kubernetes/pki/apiserver-kubelet-client.key
              - --authorization-mode=Node,RBAC
              - --etcd-servers=http://127.0.0.1:2379
              - --tls-ca-file=/etc/kubernetes/pki/ca.crt
              image: gcr.io/google_containers/kube-apiserver-amd64:${K8S_IMAGE_TAG}
              livenessProbe:
                failureThreshold: 8
                httpGet:
                  host: ${MASTER_PRIVATE_IPV4}
                  port: 6443
                  path: /healthz
                  scheme: HTTPS
                initialDelaySeconds: 15
                timeoutSeconds: 15
              name: kube-apiserver
              resources:
                requests:
                  cpu: 250m
              volumeMounts:
              - mountPath: /etc/pki
                name: ca-certs-etc-pki
                readOnly: true
              - mountPath: /etc/kubernetes/pki
                name: k8s-certs
                readOnly: true
              - mountPath: /etc/ssl/certs
                name: ca-certs
                readOnly: true
            hostNetwork: true
            volumes:
            - hostPath:
                path: /etc/kubernetes/pki
                type: DirectoryOrCreate
              name: k8s-certs
            - hostPath:
                path: /etc/ssl/certs
                type: DirectoryOrCreate
              name: ca-certs
            - hostPath:
                path: /etc/pki
                type: DirectoryOrCreate
              name: ca-certs-etc-pki
    - path: /etc/kubernetes/manifests/kube-controller-manager.yaml
      filesystem: root
      mode: 0600
      contents:
        inline: |
          apiVersion: v1
          kind: Pod
          metadata:
            annotations:
              scheduler.alpha.kubernetes.io/critical-pod: ""
            labels:
              component: kube-controller-manager
              tier: control-plane
            name: kube-controller-manager
            namespace: kube-system
          spec:
            containers:
            - command:
              - kube-controller-manager
              - --use-service-account-credentials=true
              - --controllers=*,bootstrapsigner,tokencleaner
              - --service-account-private-key-file=/etc/kubernetes/pki/sa.key
              - --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt
              - --cluster-signing-key-file=/etc/kubernetes/pki/ca.key
              - --address=127.0.0.1
              - --leader-elect=true
              - --kubeconfig=/etc/kubernetes/controller-manager.conf
              - --root-ca-file=/etc/kubernetes/pki/ca.crt
              - --allocate-node-cidrs=true
              - --cluster-cidr=${K8S_POD_NETWORK}
              - --node-cidr-mask-size=16
              image: gcr.io/google_containers/kube-controller-manager-amd64:${K8S_IMAGE_TAG}
              livenessProbe:
                failureThreshold: 8
                httpGet:
                  host: 127.0.0.1
                  path: /healthz
                  port: 10252  # Note: Using default port. Update if --port option is set differently.
                  scheme: HTTP
                initialDelaySeconds: 15
                timeoutSeconds: 15
              name: kube-controller-manager
              resources:
                requests:
                  cpu: 200m
              volumeMounts:
              - mountPath: /etc/ssl/certs
                name: ca-certs
                readOnly: true
              - mountPath: /etc/kubernetes/controller-manager.conf
                name: kubeconfig
                readOnly: true
              - mountPath: /etc/pki
                name: ca-certs-etc-pki
                readOnly: true
              - mountPath: /etc/kubernetes/pki
                name: k8s-certs
                readOnly: true
            hostNetwork: true
            volumes:
            - hostPath:
                path: /etc/pki
                type: DirectoryOrCreate
              name: ca-certs-etc-pki
            - hostPath:
                path: /etc/kubernetes/pki
                type: DirectoryOrCreate
              name: k8s-certs
            - hostPath:
                path: /etc/ssl/certs
                type: DirectoryOrCreate
              name: ca-certs
            - hostPath:
                path: /etc/kubernetes/controller-manager.conf
                type: FileOrCreate
              name: kubeconfig
    - path: /etc/kubernetes/manifests/kube-scheduler.yaml
      filesystem: root
      mode: 0600
      contents:
        inline: |
          apiVersion: v1
          kind: Pod
          metadata:
            annotations:
              scheduler.alpha.kubernetes.io/critical-pod: ""
            labels:
              component: kube-scheduler
              tier: control-plane
            name: kube-scheduler
            namespace: kube-system
          spec:
            containers:
            - command:
              - kube-scheduler
              - --address=127.0.0.1
              - --leader-elect=true
              - --kubeconfig=/etc/kubernetes/scheduler.conf
              image: gcr.io/google_containers/kube-scheduler-amd64:${K8S_IMAGE_TAG}
              livenessProbe:
                failureThreshold: 8
                httpGet:
                  host: 127.0.0.1
                  path: /healthz
                  port: 10251  # Note: Using default port. Update if --port option is set differently.
                  scheme: HTTP
                initialDelaySeconds: 15
                timeoutSeconds: 15
              name: kube-scheduler
              resources:
                requests:
                  cpu: 100m
              volumeMounts:
              - mountPath: /etc/kubernetes/scheduler.conf
                name: kubeconfig
                readOnly: true
              - mountPath: /etc/kubernetes/pki/ca.crt
                name: kube-ca-crt
                readOnly: true
            hostNetwork: true
            volumes:
            - hostPath:
                path: /etc/kubernetes/scheduler.conf
                type: FileOrCreate
              name: kubeconfig 
            - hostPath:
                path: /etc/kubernetes/pki/ca.crt
                type: FileOrCreate
              name: kube-ca-crt                                
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
        Requires=etcd-member.service
        After=etcd-member.service
         
        [Service]
        Slice=system.slice
        Environment=KUBELET_IMAGE_TAG=${KUBELET_IMAGE_TAG}
        ExecStartPre=/usr/bin/mkdir -p /var/log/containers
        ExecStartPre=/usr/bin/mkdir -p /var/log/kubernetes
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
          --hostname-override=${MASTER_PUBLIC_HOSTNAME}
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


# add etcd
cat << EOF >> $CLOUD_CONF
etcd:
  version:                     3.2.9
  name:                        "{HOSTNAME}"
  data_dir:                    /var/lib/etcd
  listen_client_urls:          http://127.0.0.1:2379
  advertise_client_urls:       http://127.0.0.1:2379
  initial_advertise_peer_urls: http://127.0.0.1:2380
  listen_peer_urls:            http://127.0.0.1:2380
  initial_cluster_token:       ${ETCD_DISCOVERY_TOKEN}
  initial_cluster:             "{HOSTNAME}=http://127.0.0.1:2380"
  initial_cluster_state:       new
  auto_compaction_retention:   1
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
