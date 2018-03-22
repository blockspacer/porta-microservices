#!/bin/bash
set -e

# This script installs the monitoring system (Prometheus)

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(dirname $(readlink -f "$0"))

kctl() {
    kubectl -n "monitoring" "$@"
}

# Install Prometheus Operator
function install_prometheus_operator {

    kubectl create namespace "monitoring"

    # Create ServiceAccount
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus-operator/prometheus-operator-service-account.yaml

    # Create ClusterRole
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus-operator/prometheus-operator-cluster-role.yaml

    # Create ClusterRoleBinding
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus-operator/prometheus-operator-cluster-role-binding.yaml

    # Create Deployment
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus-operator/prometheus-operator.yaml

    # Create Service
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus-operator/prometheus-operator-service.yaml

    printf "Waiting for Operator to register custom resource definitions..."
    until kctl get customresourcedefinitions servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get customresourcedefinitions prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get customresourcedefinitions alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get servicemonitors.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get prometheuses.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    until kctl get alertmanagers.monitoring.coreos.com > /dev/null 2>&1; do sleep 1; printf "."; done
    echo "done!"
}

# Install Node-Exporter
function install_node_exporter {
    # Create ServiceAccount
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/node-exporter/node-exporter-service-account.yaml

    # Create ClusterRole
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/node-exporter/node-exporter-cluster-role.yaml

    # Create ClusterRoleBinding
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/node-exporter/node-exporter-cluster-role-binding.yaml

    # Create DaemonSet
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/node-exporter/node-exporter-daemonset.yaml

    # Create Service
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/node-exporter/node-exporter-service.yaml

}

# Install Kube-State-Metrics
function install_kube_state_metrics {
    # Create ServiceAccount
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-service-account.yaml

    # Create Role
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-role.yaml

    # Create RoleBinding
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-role-binding.yaml

    # Create ClusterRole
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-cluster-role.yaml

    # Create ClusterRoleBinding
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-cluster-role-binding.yaml

    # Create Deployment
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-deployment.yaml

    # Create Service
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/kube-state-metrics/kube-state-metrics-service.yaml
}

# Install Grafana
function install_grafana {
    # Create ConfigMap (Dashboards)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/grafana/grafana-dashboards.yaml

    kctl create configmap grafana-dashboard-definitions --from-file=${CWD}/grafana-dashboards

    # Create ConfigMap (Datasources)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/grafana/grafana-datasources.yaml

    # Create ConfigMap with custom Grafana options
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-config
  namespace: monitoring
data:
  custom.ini: |-
    [server]
    protocol=http
    root_url=http://MASTER_PUBLIC_HOSTNAME/${GRAFANA_INGRESS_ROUTE}
    
    [security]
    admin_user=${GRAFANA_ADMIN_USER}
    admin_password=${GRAFANA_ADMIN_PASSWORD}
    disable_gravatar=true

    [analytics]
    reporting_enabled=false

    [metrics]
    enabled=false

    [snapshots]
    external_enabled=false

    [database]
    path = /data/grafana.db

    [paths]
    data = /data
    logs = /data/log
    plugins = /data/plugins

    [session]
    provider = memory

    [auth.basic]
    enabled = false

    [auth.anonymous]
    enabled = false
EOF

    # Create Deployment
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/grafana/grafana-deployment.yaml
    cat <<EOF | kubectl create -f -
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: grafana
    spec:
      nodeSelector:
        kubernetes.io/role: minion
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
      containers:
      - name: grafana
        image: quay.io/coreos/monitoring-grafana:5.0.0-beta1
        args:
        - --config=/grafana/conf.d/custom.ini
        volumeMounts:
        - name: grafana-storage
          mountPath: /data
        - name: grafana-datasources
          mountPath: /grafana/conf/provisioning/datasources
        - name: grafana-dashboards
          mountPath: /grafana/conf/provisioning/dashboards
        - name: grafana-dashboard-definitions
          mountPath: /grafana-dashboard-definitions/0
        - name: grafana-config
          mountPath: /grafana/conf.d
        ports:
        - name: web
          containerPort: 3000
          protocol: TCP
        resources:
          requests:
            memory: 100Mi
            cpu: 100m
          limits:
            memory: 200Mi
            cpu: 200m
      volumes:
      - name: grafana-storage
        emptyDir: {}
      - name: grafana-datasources
        configMap:
          name: grafana-datasources
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboards
      - name: grafana-dashboard-definitions
        configMap:
          name: grafana-dashboard-definitions
      - name: grafana-config
        configMap:
          name: grafana-config
EOF

    # Create Service
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/grafana/grafana-service.yaml
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app: grafana
spec:
  type: ClusterIP
  ports:
  - port: 3000
    name: web
    protocol: TCP
    targetPort: web
  selector:
    app: grafana    
EOF
}

# Install Prometheus
function install_prometheus {
    # Create ServiceAccount
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-account.yaml

    # Create ClusterRole
    # kubectl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-roles.yaml
    cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: Role
metadata:
  name: prometheus-k8s
  namespace: monitoring
rules:
- apiGroups: [""]
  resources:
  - configmaps
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: prometheus-k8s
rules:
- apiGroups: [""]
  resources:
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources:
  - nodes/metrics
  verbs: ["get"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
EOF

    # Create ClusterRoleBinding
    # kubectl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-role-bindings.yaml
    cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding
metadata:
  name: prometheus-k8s
  namespace: monitoring
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: prometheus-k8s
subjects:
- kind: ServiceAccount
  name: prometheus-k8s
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: prometheus-k8s
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-k8s
subjects:
- kind: ServiceAccount
  name: prometheus-k8s
  namespace: monitoring
EOF

    # Create ConfigMap (Rules)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-rules.yaml

    # Create ServiceMonitor (AlertManager)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-alertmanager.yaml

    # Create Servicemonitor (ApiServer)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-apiserver.yaml

    # Create ServiceMonitor (Controller-Manager)
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-kube-controller-manager.yaml
    cat <<EOF | kubectl create -f - 
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-controller-manager
  namespace: monitoring
  labels:
    k8s-app: kube-controller-manager
spec:
  jobLabel: component
  endpoints:
  - port: http-metrics
    interval: 30s
  selector:
    matchLabels:
      component: kube-controller-manager
      provider: kubernetes
  namespaceSelector:
    matchNames:
    - kube-system
EOF

    # Create service for Controller-Manager
    cat <<EOF | kubectl create -f  -
apiVersion: v1
kind: Service
metadata:
  labels:
    component: kube-controller-manager
    provider: kubernetes
  name: kube-controller-manager-metrics
  namespace: kube-system
spec:
  ports:
  - name: http-metrics
    port: 10252
    protocol: TCP
    targetPort: 10252
  sessionAffinity: None
  selector:
    component: kube-controller-manager
    tier: control-plane
  type: ClusterIP
EOF

    # Create ServiceMonitor (Scheduler)
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-kube-scheduler.yaml

    cat <<EOF | kubectl create -f - 
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kube-scheduler
  namespace: monitoring
  labels:
    k8s-app: kube-scheduler
spec:
  jobLabel: component
  endpoints:
  - port: http-metrics
    interval: 30s
  selector:
    matchLabels:
      component: kube-scheduler
      provider: kubernetes
  namespaceSelector:
    matchNames:
    - kube-system
EOF
    
    # Create service for Scheduler
    cat <<EOF | kubectl create -n kube-system -f  -
apiVersion: v1
kind: Service
metadata:
  labels:
    component: kube-scheduler
    provider: kubernetes
  name: kube-scheduler-metrics
  namespace: kube-system
spec:
  ports:
  - name: http-metrics
    port: 10251
    protocol: TCP
    targetPort: 10251
  sessionAffinity: None
  selector:
    component: kube-scheduler
    tier: control-plane
  type: ClusterIP
EOF

    # Create ServiceMonitor (State-Metrics)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-kube-state-metrics.yaml

    # Create ServiceMonitor (Kubelet)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-kubelet.yaml

    # Create ServiceMonitor (Node-Exporter)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-node-exporter.yaml

    # Create ServiceMonitor (Prometheus-Operator)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-prometheus-operator.yaml

    # Create ServiceMonitor (Prometheus)
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service-monitor-prometheus.yaml

    # Create Service (Prometheus)
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s-service.yaml
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    prometheus: k8s
  name: prometheus-k8s
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - name: web
    port: 9090
    protocol: TCP
    targetPort: web
  selector:
    prometheus: k8s
EOF

    # Create Prometheus
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/prometheus/prometheus-k8s.yaml
    cat << EOF | kubectl create -f -
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: k8s
  namespace: monitoring
  labels:
    prometheus: k8s
spec:
  replicas: 1
  secrets:
  - etcd-certs
  version: v2.1.0
  externalUrl: http://${MASTER_PUBLIC_HOSTNAME}/${PROMETHEUS_INGRESS_ROUTE}
  serviceAccountName: prometheus-k8s
  nodeSelector:
    kubernetes.io/role: storage
  serviceMonitorSelector:
    matchExpressions:
    - {key: k8s-app, operator: Exists}
  ruleSelector:
    matchLabels:
      role: prometheus-rulefiles
      prometheus: k8s
  resources:
    requests:
      # 2Gi is default, but won't schedule if you don't have a node with >2Gi
      # memory. Modify based on your target and time-series count for
      # production use. This value is mainly meant for demonstration/testing
      # purposes.
      memory: 400Mi
  retention: 30d
  storage:
    class: openstack-cinder
    selector:
    resources:
      requests:
        storage: ${PROMETHEUS_STORAGE_SIZE}
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        storageClassName: openstack-cinder
        selector:
        resources:
          requests:
            storage: ${PROMETHEUS_STORAGE_SIZE}
  alerting:
    alertmanagers:
    - namespace: monitoring
      name: alertmanager-main
      port: web
EOF
}

# Install AlertManager
function install_alert_manager {
    # Create Secret
    kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/alertmanager/alertmanager-config.yaml

    # Create Service
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/alertmanager/alertmanager-service.yaml
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  labels:
    alertmanager: main
  name: alertmanager-main
  namespace: monitoring
spec:
  type: ClusterIP
  ports:
  - name: web
    port: 9093
    protocol: TCP
    targetPort: web
  selector:
    alertmanager: main
EOF

    # Create AlertManager
    # kctl create -f https://raw.githubusercontent.com/coreos/prometheus-operator/master/contrib/kube-prometheus/manifests/alertmanager/alertmanager.yaml
    cat <<EOF | kubectl create -f -
apiVersion: monitoring.coreos.com/v1
kind: Alertmanager
metadata:
  name: main
  namespace: monitoring
  labels:
    alertmanager: main
spec:
  replicas: 1
  version: v0.14.0
  externalUrl: http://${MASTER_PUBLIC_HOSTNAME}/${ALERT_MNG_INGRESS_ROUTE}
  nodeSelector:
    kubernetes.io/role: minion
  resources:
    requests:
      memory: 400Mi    
EOF
}

function install_etcd_monitor {
    # Create service for Etcd
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: etcd-metrics
  namespace: kube-system
  labels:
    component: etcd
    provider: etcd
spec:
  type: ClusterIP
  clusterIP: None
  ports:
  - name: http-metrics
    port: 2379
    protocol: TCP
EOF
    
    # Create custom endpoint for Etcd since it is not handled by Kubernetes
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Endpoints
metadata:
  namespace: kube-system
  name: etcd-metrics
  labels:
    component: etcd
    tier: etcd
subsets:
- addresses:
  - ip: ${MASTER_PRIVATE_IPV4}
    nodeName: ${MASTER_PUBLIC_HOSTNAME}
  ports:
  - name: http-metrics
    port: 2379
    protocol: TCP
EOF

    # Create secret for etcd endpoint
    kubectl -n monitoring create secret generic etcd-certs --from-file=$CWD/CA/ca.crt \
    --from-file=$CWD/CA/etcd/etcd.crt --from-file=$CWD/CA/etcd/etcd.key

    # Create service monitor
    cat <<EOF | kubectl create -f - 
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  namespace: monitoring
  name: etcd
  labels:
    k8s-app: etcd
spec:
  jobLabel: component
  endpoints:
  - port: http-metrics
    interval: 30s
    scheme: https
    tlsConfig:
      insecureSkipVerify: true
      caFile: /etc/prometheus/secrets/etcd-certs/ca.crt
      certFile: /etc/prometheus/secrets/etcd-certs/etcd.crt
      keyFile: /etc/prometheus/secrets/etcd-certs/etcd.key
  selector:
    matchLabels:
      component: etcd
      provider: etcd
  namespaceSelector:
    matchNames:
    - kube-system
EOF
}

function install_ingress_nginx_monitor {
    # Create service monitor for Nginx ingress controller
    cat <<EOF | kubectl create -f - 
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  namespace: monitoring
  name: nginx-ingress-controller
  labels:
    k8s-app: nginx
spec:
  jobLabel: component
  endpoints:
  - port: http-metrics
    interval: 30s
    scheme: http
  selector:
    matchLabels:
      component: ingress-nginx
      provider: nginx
  namespaceSelector:
    matchNames:
    - ingress-nginx
EOF
}

function install_ingress_resources {
     # Create secret for ingress certificate
    kctl create secret generic monitor-certs --from-file=tls.crt=${CWD}/CA/monitoring/monitor.crt \
    --from-file=tls.key=${CWD}/CA/monitoring/monitor.key --from-file=ca.crt=${CWD}/CA/ca.crt

    cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/add-base-url: "true"
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
  name: monitor
  namespace: monitoring
spec:
  tls:
  - hosts:
    - ${MASTER_PUBLIC_HOSTNAME}
    secretName: monitor-certs
  rules:
  - host: ${MASTER_PUBLIC_HOSTNAME}
    http:
      paths:
      - path: /${GRAFANA_INGRESS_ROUTE}
        backend:
          serviceName: grafana
          servicePort: web
      - path: /${PROMETHEUS_INGRESS_ROUTE}
        backend:
          serviceName: prometheus-k8s
          servicePort: web
      - path: /${ALERT_MNG_INGRESS_ROUTE}
        backend:
          serviceName: alertmanager-main
          servicePort: web
EOF
}

# ======================== MAIN ========================
install_prometheus_operator
install_node_exporter
install_kube_state_metrics
install_grafana
install_etcd_monitor
install_prometheus
install_alert_manager
install_ingress_nginx_monitor
install_ingress_resources