#!/bin/bash
set -e

# This script installs Ingress controller NGINX into Kubernetes cluster and namespace ingress-nginx
# to get generated config run:
# kubectl -n ingress-nginx exec <nginx-ingress-controller-pod-name> -- cat /etc/nginx/nginx.conf > ./nginx.conf

if [ ! -e ./master-env.conf ]; then 
    echo "ERROR: master-env.conf is missed"
    exit 1
fi

source ./master-env.conf


# namespace ingress-nginx
curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/namespace.yaml | kubectl apply -f -

# default back-end deployment
# curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/default-backend.yaml | kubectl apply -f -
cat << EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: default-http-backend
  labels:
    app: default-http-backend
  namespace: ingress-nginx
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: default-http-backend
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: default-http-backend
        # Any image is permissable as long as:
        # 1. It serves a 404 page at /
        # 2. It serves 200 on a /healthz endpoint
        image: gcr.io/google_containers/defaultbackend:1.4
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
          requests:
            cpu: 10m
            memory: 20Mi
---

apiVersion: v1
kind: Service
metadata:
  name: default-http-backend
  namespace: ingress-nginx
  labels:
    app: default-http-backend
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: default-http-backend
EOF

# NGINX configmap
# curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/configmap.yaml | kubectl apply -f -
cat <<EOF | kubectl create -f -
kind: ConfigMap
apiVersion: v1
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
  labels:
    app: ingress-nginx
data:
  disable-ipv6: "true"
  enable-vts-status: "true"
  enable-opentracing: "true"
  jaeger-collector-host: "${MASTER_PRIVATE_IPV4}"
  jaeger-collector-port: "6831"
  jaeger-service-name: "nginx"
  jaeger-sampler-type: "const"
  jaeger-sampler-param: "0"
EOF

# TCP configmap
curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/tcp-services-configmap.yaml | kubectl apply -f -

# cat <<EOF | kubectl create -f -
# kind: ConfigMap
# apiVersion: v1
# metadata:
#   name: tcp-services
#   namespace: ingress-nginx
# EOF

# UDP configmap
curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/udp-services-configmap.yaml | kubectl apply -f -
# cat <<EOF | kubectl create -f -
# kind: ConfigMap
# apiVersion: v1
# metadata:
#   name: udp-services
#   namespace: ingress-nginx
# EOF


# serviceaccount and bindings
curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/rbac.yaml | kubectl apply -f -

# NGINX deployment
# curl https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/with-rbac.yaml | kubectl apply -f -
cat <<EOF | kubectl create -f -
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ""
  name: nginx-ingress-controller
  namespace: ingress-nginx 
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ingress-nginx
  template:
    metadata:
      labels:
        app: ingress-nginx
      annotations:
        prometheus.io/port: '10254'
        prometheus.io/scrape: 'true'
    spec:
      nodeSelector:
        kubernetes.io/hostname: ${MASTER_PUBLIC_HOSTNAME}
      serviceAccountName: nginx-ingress-serviceaccount
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      hostNetwork: true
      initContainers:
      - command:
        - sh
        - -c
        - sysctl -w net.core.somaxconn=32768; sysctl -w net.ipv4.ip_local_port_range="1024 65535"
        image: alpine:3.6
        imagePullPolicy: IfNotPresent
        name: sysctl
        securityContext:
          privileged: true
      containers:
        - name: nginx-ingress-controller
          image: quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.10.2
          args:
            - /nginx-ingress-controller
            - --default-backend-service=\$(POD_NAMESPACE)/default-http-backend
            - --configmap=\$(POD_NAMESPACE)/nginx-configuration
            - --tcp-services-configmap=\$(POD_NAMESPACE)/tcp-services
            - --udp-services-configmap=\$(POD_NAMESPACE)/udp-services
            - --annotations-prefix=nginx.ingress.kubernetes.io
          env:
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          ports:
          - name: http
            containerPort: 80
          - name: https
            containerPort: 443
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          readinessProbe:
            failureThreshold: 3
            httpGet:
              path: /healthz
              port: 10254
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
EOF

# Create service for metrics
cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-ingress-controller-metrics
  namespace: ingress-nginx
  labels:
    component: ingress-nginx
    provider: nginx
spec:
  type: ClusterIP
  ports:
  - name: http-metrics
    port: 10254
    protocol: TCP
  selector:
    app: ingress-nginx
EOF