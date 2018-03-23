#!/bin/bash
set -e

# This script installs the logging system:
# - fluentbit to fetch logs from containers and send them to storage
# - elasticsearch as storage backend
# - kibana as log analyzer
# NOTE: ES pods are scheduled on node with label "kubernetes.io/role: storage".
# As soon as they require a lot of RAM+CPU it is reasonable
# to deploy them separately from the other staff.
#
# NOTE 2: ES is installed in a following configuration:
# - master node - ${ES_MASTER_COUNT}
# - client node -${ES_CLIENT_COUNT}
# - storage node - ${ES_STORAGE_COUNT}
# Such configuration allows to scale ES once it is required.
#
# TODO: install X-PACK for security

if [ ! -e ./master-env.conf ]; then
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(dirname $(readlink -f "$0"))


function install_prerequisites {
  # Create namespace for logging staff
  kubectl create namespace "logging"
}

function install_elastic_search {
# ======================= MASTER node =======================
# cretae master service
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-discovery
  namespace: logging
  labels:
    component: elasticsearch
    role: master
spec:
  selector:
    component: elasticsearch
    role: master
  ports:
  - name: transport
    port: 9300
    protocol: TCP
EOF

# create master deployment
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: es-master
  namespace: logging
  labels:
    component: elasticsearch
    role: master
spec:
  replicas: ${ES_MASTER_COUNT}
  template:
    metadata:
      labels:
        component: elasticsearch
        role: master
    spec:
      nodeSelector:
        kubernetes.io/role: storage
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: es-master
        securityContext:
          privileged: false
          capabilities:
            add:
              - IPC_LOCK
              - SYS_RESOURCE
        image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.2
        imagePullPolicy: Always
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: "CLUSTER_NAME"
          value: "${ES_CLUSTER_NAME}"
        - name: "NUMBER_OF_MASTERS"
          value: "${ES_MASTER_COUNT}"
        - name: NODE_MASTER
          value: "true"
        - name: NODE_INGEST
          value: "false"
        - name: NODE_DATA
          value: "false"
        - name: HTTP_ENABLE
          value: "false"
        - name: "ES_JAVA_OPTS"
          value: "-Xms256m -Xmx256m"
        ports:
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
          - emptyDir:
              medium: ""
            name: "storage"
EOF

# ======================= CLIENT node =======================
# cretae client service
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch
  namespace: logging
  labels:
    component: elasticsearch
    role: client
spec:
  type: ClusterIP
  selector:
    component: elasticsearch
    role: client
  ports:
  - name: http
    port: ${ES_LOGGING_PORT}
    protocol: TCP
EOF

# create client deployment
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: es-client
  namespace: logging
  labels:
    component: elasticsearch
    role: client
spec:
  replicas: ${ES_CLIENT_COUNT}
  template:
    metadata:
      labels:
        component: elasticsearch
        role: client
    spec:
      nodeSelector:
        kubernetes.io/role: storage
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: es-client
        securityContext:
          privileged: false
          capabilities:
            add:
              - IPC_LOCK
              - SYS_RESOURCE
        image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.2
        imagePullPolicy: Always
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: "CLUSTER_NAME"
          value: "${ES_CLUSTER_NAME}"
        - name: NODE_MASTER
          value: "false"
        - name: NODE_DATA
          value: "false"
        - name: HTTP_ENABLE
          value: "true"
        - name: "ES_JAVA_OPTS"
          value: "-Xms256m -Xmx256m"
        ports:
        - containerPort: ${ES_LOGGING_PORT}
          name: http
          protocol: TCP
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
          - emptyDir:
              medium: ""
            name: "storage"
EOF

# ======================= STORAGE node =======================
# cretae storage service
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: elasticsearch-data
  namespace: logging
  labels:
    component: elasticsearch
    role: data
spec:
  clusterIP: None
  selector:
    component: elasticsearch
    role: data
  ports:
  - name: transport
    port: 9300
    protocol: TCP
EOF

# create storage statefulset
cat <<EOF | kubectl create -f -
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: elasticsearch-data
  namespace: logging
  labels:
    component: elasticsearch
    role: data
spec:
  serviceName: elasticsearch-data
  replicas: ${ES_STORAGE_COUNT}
  template:
    metadata:
      labels:
        component: elasticsearch
        role: data
    spec:
      nodeSelector:
        kubernetes.io/role: storage
      initContainers:
      - name: init-sysctl
        image: busybox
        imagePullPolicy: IfNotPresent
        command: ["sysctl", "-w", "vm.max_map_count=262144"]
        securityContext:
          privileged: true
      containers:
      - name: elasticsearch-data-pod
        securityContext:
          privileged: true
          capabilities:
            add:
              - IPC_LOCK
        image: docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.2
        imagePullPolicy: Always
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: "CLUSTER_NAME"
          value: "${ES_CLUSTER_NAME}"
        - name: NODE_MASTER
          value: "false"
        - name: NODE_INGEST
          value: "false"
        - name: HTTP_ENABLE
          value: "false"
        - name: "ES_JAVA_OPTS"
          value: "-Xms256m -Xmx256m"
        ports:
        - containerPort: 9300
          name: transport
          protocol: TCP
        volumeMounts:
        - name: es-storage
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: es-storage
      annotations:
        volume.beta.kubernetes.io/storage-class: openstack-cinder
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: ${ES_STORAGE_SIZE}
EOF
}

function install_fluentbit {
  # ConfigMap based on https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-configmap.yaml
  # See more info on configuration http://fluentbit.io/documentation/0.11/getting_started/
  cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: logging
  labels:
    k8s-app: fluent-bit
data:
  # Configuration files: server, input, filters and output
  # ======================================================
  fluent-bit.conf: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf

    @INCLUDE input-kubernetes.conf
    @INCLUDE filter-kubernetes.conf
    @INCLUDE output-elasticsearch.conf

  input-kubernetes.conf: |
    [INPUT]
        Name              tail
        Tag               kube.*
        Path              /var/log/containers/*.log
        Exclude_Path      *weave-net*,*default-http-backend*,*node-exporter*,*fluent-bit*
        Parser            docker
        DB                /var/log/flb_ingress.db
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On
        Refresh_Interval  10

  filter-kubernetes.conf: |
    [FILTER]
        Name           kubernetes
        Match          kube.*
        tls.verify     Off
        Kube_URL       https://${K8S_CLUSTER_NAME}.default.svc:443
        Kube_CA_File   /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        Kube_Token_File /var/run/secrets/kubernetes.io/serviceaccount/token
        Merge_JSON_Log On
        Annotations    On

  output-elasticsearch.conf: |
    [OUTPUT]
        Name            es
        Match           kube.*
        Host            elasticsearch
        Port            ${ES_LOGGING_PORT}
        Index           fluentbit
        Logstash_Format False
        Retry_Limit     False

  parsers.conf: |
    [PARSER]
        Name   nginx
        Format regex
        Regex ^(?<remote>[^ ]*) (?<host>[^ ]*) (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$
        Time_Key time
        Time_Format %d/%b/%Y:%H:%M:%S %z

    [PARSER]
        Name        docker
        Format      json
        Time_Key    time
        Time_Format %Y-%m-%dT%H:%M:%S.%L
        Time_Keep   On

    [PARSER]
        Name        syslog
        Format      regex
        Regex       ^\<(?<pri>[0-9]+)\>(?<time>[^ ]* {1,2}[^ ]* [^ ]*) (?<host>[^ ]*) (?<ident>[a-zA-Z0-9_\/\.\-]*)(?:\[(?<pid>[0-9]+)\])?(?:[^\:]*\:)? *(?<message>.*)$
        Time_Key    time
        Time_Format %b %d %H:%M:%S
EOF

    # ServiceAccount
    kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-service-account.yaml

    # ClusterRole
    kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role.yaml

    # ClusterRoleBinding
    kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/fluent-bit-role-binding.yaml


    # DaemonSet for fluent-bit
    # kubectl create -f https://raw.githubusercontent.com/fluent/fluent-bit-kubernetes-logging/master/output/elasticsearch/fluent-bit-ds.yaml
    cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
  labels:
    k8s-app: fluent-bit-logging
    version: v1
    kubernetes.io/cluster-service: "true"
spec:
  template:
    metadata:
      labels:
        k8s-app: fluent-bit-logging
        version: v1
        kubernetes.io/cluster-service: "true"
    spec:
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:0.12.14
        resources:
          limits:
            cpu: 10m
            memory: 200Mi
          requests:
            cpu: 10m
            memory: 200Mi
        volumeMounts:
        - name: varlog
          mountPath: /var/log
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc/
      terminationGracePeriodSeconds: 10
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config
      serviceAccountName: fluent-bit
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
EOF
}

function install_kibana {
    # ConfigMap for Kibana
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kibana-config
  namespace: logging
  labels:
    k8s-app: kibana
data:
  kibana.yml: |
    elasticsearch.url: "http://elasticsearch:${ES_LOGGING_PORT}"
    server.host: "0.0.0.0"
    server.basePath: /${KIBANA_INGRESS_ROUTE}
EOF

    # Deployment for Kibana
    cat << EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kibana
  labels:
    app: kibana
    kubernetes.io/cluster-service: "true"
  namespace: logging
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: kibana
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: kibana
        image: docker.elastic.co/kibana/kibana-oss:6.2.2
        ports:
        - containerPort: 5601
          name: kibana
          protocol: TCP
        terminationMessagePolicy: FallbackToLogsOnError
        resources:
          limits:
            cpu: 1000m
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 1Gi
        volumeMounts:
        - name: kibana-config
          mountPath: /usr/share/kibana/config
      volumes:
      - name: kibana-config
        configMap:
          name: kibana-config
EOF

    # Service for Kibana
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: kibana
  namespace: logging
  labels:
    app: kibana
spec:
  ports:
  - port: 5601
    targetPort: 5601
    name: log
    protocol: TCP
  selector:
    app: kibana
EOF

    # Create Ingress for Kibana
    kubectl create -n logging secret generic logging-certs --from-file=tls.crt=${CWD}/CA/logging/logging.crt \
    --from-file=tls.key=${CWD}/CA/logging/logging.key --from-file=ca.crt=${CWD}/CA/ca.crt

    cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/add-base-url: "true"
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
  name: kibana
  namespace: logging
spec:
  tls:
  - hosts:
    - ${MASTER_PUBLIC_HOSTNAME}
    secretName: logging-certs
  rules:
  - host: ${MASTER_PUBLIC_HOSTNAME}
    http:
      paths:
      - path: /${KIBANA_INGRESS_ROUTE}
        backend:
          serviceName: kibana
          servicePort: log
EOF
}

# ======================== MAIN ========================
install_prerequisites
install_elastic_search
install_fluentbit
install_kibana