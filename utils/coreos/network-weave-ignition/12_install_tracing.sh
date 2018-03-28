#!/bin/bash
set -e

# This script installs the tracing system:
# http://jaeger.readthedocs.io/en/latest/
# https://github.com/jaegertracing/jaeger-kubernetes

if [ ! -e ./master-env.conf ]; then
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf

CWD=$(dirname $(readlink -f "$0"))

JAEGER_DOCKER_IMAGE_TAG="1.3"

function install_prerequisites {
  # Create namespace for tracing staff
  kubectl create namespace "tracing"
}

function install_jaeger {
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: jaeger-configuration
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: configuration
data:
  span-storage-type: elasticsearch
  collector: |
    es:
      server-urls: http://elasticsearch.logging:${ES_LOGGING_PORT}
    collector:
      zipkin:
        http-port: 9411
  query: |
    es:
      server-urls: http://elasticsearch.logging:${ES_LOGGING_PORT}
    query:
      static-files: /go/jaeger-ui/
      base-path: /${TRACING_INGRESS_ROUTE}
  agent: |
    collector:
      host-port: "jaeger-collector:14267"
EOF

# create jaeger collector deployment
cat <<EOF | kubectl create -f -
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: jaeger-collector
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: collector-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: jaeger
        jaeger-infra: collector-pod
    spec:
      nodeSelector:
        kubernetes.io/role: minion
      containers:
      - image: jaegertracing/jaeger-collector:${JAEGER_DOCKER_IMAGE_TAG}
        name: jaeger-collector
        command:
          - "/go/bin/collector-linux"
          - "--config-file=/conf/collector.yaml"
        ports:
        - containerPort: 14267
          protocol: TCP
        - containerPort: 14268
          protocol: TCP
        - containerPort: 9411
          protocol: TCP
        volumeMounts:
        - name: jaeger-configuration-volume
          mountPath: /conf
        env:
        - name: SPAN_STORAGE_TYPE
          valueFrom:
            configMapKeyRef:
              name: jaeger-configuration
              key: span-storage-type
      volumes:
      - name: jaeger-configuration-volume
        configMap:
          name: jaeger-configuration
          items:
          - key: collector
            path: collector.yaml
EOF

# create jaeger collector service
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: jaeger-collector
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: collector-service
spec:
  ports:
  - name: jaeger-collector-tchannel
    port: 14267
    protocol: TCP
    targetPort: 14267
  - name: jaeger-collector-http
    port: 14268
    protocol: TCP
    targetPort: 14268
  - name: jaeger-collector-zipkin
    port: 9411
    protocol: TCP
    targetPort: 9411
  selector:
    jaeger-infra: collector-pod
  type: ClusterIP
EOF

# create jaeger query deployment
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: jaeger-query
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: query-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: jaeger
        jaeger-infra: query-pod
    spec:
      nodeSelector:
        kubernetes.io/role: minion
      containers:
      - image: jaegertracing/jaeger-query:${JAEGER_DOCKER_IMAGE_TAG}
        name: jaeger-query
        command:
          - "/go/bin/query-linux"
          - "--config-file=/conf/query.yaml"
        ports:
        - containerPort: 16686
          protocol: TCP
        readinessProbe:
          httpGet:
            path: "/"
            port: 16686
        volumeMounts:
        - name: jaeger-configuration-volume
          mountPath: /conf
        env:
        - name: SPAN_STORAGE_TYPE
          valueFrom:
            configMapKeyRef:
              name: jaeger-configuration
              key: span-storage-type
      volumes:
      - name: jaeger-configuration-volume
        configMap:
          name: jaeger-configuration
          items:
          - key: query
            path: query.yaml
EOF

# create jaeger query service
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: jaeger-query
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: query-service
spec:
  ports:
  - name: jaeger-query
    port: 80
    protocol: TCP
    targetPort: 16686
  selector:
    jaeger-infra: query-pod
  type: ClusterIP
EOF

# create jaeger agent daemonset
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: jaeger-agent
  namespace: tracing
  labels:
    app: jaeger
    jaeger-infra: agent-daemonset
spec:
  template:
    metadata:
      labels:
        app: jaeger
        jaeger-infra: agent-instance
    spec:
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      containers:
      - name: agent-instance
        image: jaegertracing/jaeger-agent:${JAEGER_DOCKER_IMAGE_TAG}
        command:
          - "/go/bin/agent-linux"
          - "--config-file=/conf/agent.yaml"
        volumeMounts:
        - name: jaeger-configuration-volume
          mountPath: /conf
        ports:
        - containerPort: 5775
          protocol: UDP
        - containerPort: 6831
          protocol: UDP
        - containerPort: 6832
          protocol: UDP
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      volumes:
      - name: jaeger-configuration-volume
        configMap:
          name: jaeger-configuration
          items:
          - key: agent
            path: agent.yaml
EOF
}

function install_ingress {
    # Create Ingress for Jaeger
    kubectl create -n tracing secret generic tracing-certs --from-file=tls.crt=${CWD}/CA/tracing/tracing.crt \
    --from-file=tls.key=${CWD}/CA/tracing/tracing.key --from-file=ca.crt=${CWD}/CA/ca.crt

    cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/add-base-url: "true"
    nginx.ingress.kubernetes.io/from-to-www-redirect: "true"
    nginx.ingress.kubernetes.io/configuration-snippet: |
      opentracing off;
  name: jaeger
  namespace: tracing
spec:
  tls:
  - hosts:
    - ${MASTER_PUBLIC_HOSTNAME}
    secretName: tracing-certs
  rules:
  - host: ${MASTER_PUBLIC_HOSTNAME}
    http:
      paths:
      - path: /${TRACING_INGRESS_ROUTE}
        backend:
          serviceName: jaeger-query
          servicePort: jaeger-query
EOF
}

# ======================== MAIN ========================
install_prerequisites
install_jaeger
install_ingress
