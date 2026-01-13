#!/bin/bash

################################################################################
# SRE Agent Demo - Chaos Scenario
# This script creates conditions that will:
# 1. Stress the web application
# 2. Generate errors visible in ADX logs
# 3. Trigger Azure Monitor alerts
# 4. Allow SRE Agent to detect and investigate
################################################################################

set -e

RESOURCE_GROUP="rg-sre-demo"
AKS_CLUSTER_NAME="aks-sre-demo"
APPGW_NAME="appgw-sre-demo"
APPGW_PUBLIC_IP_NAME="pip-appgw-sre-demo"

# Get Application Gateway public IP
APPGW_PUBLIC_IP=$(az network public-ip show \
  --resource-group $RESOURCE_GROUP \
  --name $APPGW_PUBLIC_IP_NAME \
  --query ipAddress -o tsv)

echo "========================================================================"
echo "SRE Agent Chaos Scenario"
echo "Application Gateway IP: $APPGW_PUBLIC_IP"
echo "========================================================================"

# Ensure we have kubectl context
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing

# ============================================================================
# SCENARIO 1: MEMORY PRESSURE - NODE-LEVEL MEMORY STRESS
# This will stress node memory to trigger Azure Monitor alerts:
# - Azure Monitor alert: alert-aks-high-memory (>80% memory)
# - Visible in kubectl top nodes
# Uses DaemonSet to ensure stress runs on ALL nodes
# ============================================================================
echo ""
echo "--- SCENARIO 1: Deploy Node Memory Stress (DaemonSet) ---"
echo "This DaemonSet runs on each node and consumes ~6GB memory per node"

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: memory-stress-daemonset
  namespace: default
  labels:
    app: memory-stress-ds
    scenario: chaos-demo
spec:
  selector:
    matchLabels:
      app: memory-stress-ds
  template:
    metadata:
      labels:
        app: memory-stress-ds
        scenario: chaos-demo
    spec:
      containers:
      - name: memory-hog
        image: polinux/stress
        command: ["stress"]
        args: ["--vm", "4", "--vm-bytes", "1500M", "--vm-hang", "1"]
        resources:
          requests:
            memory: "100Mi"
            cpu: "50m"
EOF

echo "Memory stress DaemonSet deployed. Each node will have ~6GB memory consumed."
echo "This should push node memory above 80% threshold."
echo "Watch with: kubectl top nodes"
echo "Alert 'alert-aks-high-memory' should fire within 5 minutes."

# ============================================================================
# SCENARIO 2: HIGH ERROR RATE - CAUSE 5XX ERRORS
# This will generate backend errors visible in:
# - ApplicationGatewayAccessLogs (ADX) - HttpStatus >= 500
# - Azure Monitor alert: alert-appgw-unhealthy-backend
# ============================================================================
echo ""
echo "--- SCENARIO 2: Deploy Faulty Backend ---"
echo "This pod returns 500 errors, causing App Gateway backend health issues"

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: faulty-backend
  namespace: default
  labels:
    app: faulty-backend
    scenario: chaos-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: faulty-backend
  template:
    metadata:
      labels:
        app: faulty-backend
        scenario: chaos-demo
    spec:
      containers:
      - name: faulty-app
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/conf.d/default.conf
          subPath: default.conf
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
      volumes:
      - name: nginx-config
        configMap:
          name: faulty-nginx-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: faulty-nginx-config
  namespace: default
data:
  default.conf: |
    server {
        listen 80;
        
        # Return 500 error for 70% of requests
        location / {
            set $error_chance "";
            if ($request_id ~* "^[0-7]") {
                set $error_chance "error";
            }
            if ($error_chance = "error") {
                return 500 '{"error": "Internal Server Error", "message": "Backend service unavailable", "timestamp": "$time_iso8601"}';
            }
            return 200 '{"status": "ok", "timestamp": "$time_iso8601"}';
            add_header Content-Type application/json;
        }
        
        # Health check endpoint - also fails sometimes
        location /health {
            set $health_fail "";
            if ($request_id ~* "^[0-5]") {
                set $health_fail "fail";
            }
            if ($health_fail = "fail") {
                return 503 '{"status": "unhealthy"}';
            }
            return 200 '{"status": "healthy"}';
            add_header Content-Type application/json;
        }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: faulty-backend-service
  namespace: default
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: faulty-backend
EOF

echo "Faulty backend deployed. It returns 500 errors for ~70% of requests."

# ============================================================================
# SCENARIO 3: SLOW RESPONSE - CAUSE LATENCY ALERTS
# This will cause high latency visible in:
# - ApplicationGatewayAccessLogs (ADX) - ResponseTime > 1000ms
# - Azure Monitor alert: alert-appgw-high-latency
# ============================================================================
echo ""
echo "--- SCENARIO 3: Deploy Slow Backend ---"
echo "This pod has artificial delays, causing latency alerts"

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: slow-backend
  namespace: default
  labels:
    app: slow-backend
    scenario: chaos-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: slow-backend
  template:
    metadata:
      labels:
        app: slow-backend
        scenario: chaos-demo
    spec:
      containers:
      - name: slow-app
        image: python:3.9-slim
        command: ["python", "-c"]
        args:
        - |
          from http.server import HTTPServer, BaseHTTPRequestHandler
          import time
          import random
          import json
          
          class SlowHandler(BaseHTTPRequestHandler):
              def do_GET(self):
                  # Random delay between 2-10 seconds
                  delay = random.uniform(2, 10)
                  print(f"Request received, delaying {delay:.2f}s", flush=True)
                  time.sleep(delay)
                  
                  self.send_response(200)
                  self.send_header('Content-Type', 'application/json')
                  self.end_headers()
                  response = json.dumps({
                      "status": "ok",
                      "delay_seconds": delay,
                      "message": "Response delayed intentionally"
                  })
                  self.wfile.write(response.encode())
              
              def log_message(self, format, *args):
                  print(f"[SLOW-BACKEND] {args[0]}", flush=True)
          
          print("Starting slow backend on port 8080...", flush=True)
          HTTPServer(('0.0.0.0', 8080), SlowHandler).serve_forever()
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: slow-backend-service
  namespace: default
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: slow-backend
EOF

echo "Slow backend deployed. Response times will be 2-10 seconds."

# ============================================================================
# SCENARIO 4: CRASH LOOP - POD RESTART STORM
# This will cause pod restart loops visible in:
# - ContainerLogs (ADX) - CrashLoopBackOff errors
# - Azure Monitor metrics
# ============================================================================
echo ""
echo "--- SCENARIO 4: Deploy Crash Loop Pod ---"
echo "This pod crashes repeatedly, generating restart errors"

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crash-loop-pod
  namespace: default
  labels:
    app: crash-loop
    scenario: chaos-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: crash-loop
  template:
    metadata:
      labels:
        app: crash-loop
        scenario: chaos-demo
    spec:
      containers:
      - name: crasher
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "ERROR: Application startup failed - database connection refused"
          echo "ERROR: Retrying connection to backend service..."
          echo "FATAL: Cannot connect to required services after 3 retries"
          echo "ERROR: Unhandled exception in main thread"
          sleep 5
          exit 1
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
          limits:
            cpu: 50m
            memory: 32Mi
      restartPolicy: Always
EOF

echo "Crash loop pods deployed. They will restart every ~5 seconds."
echo "Watch with: kubectl get pods -l app=crash-loop -w"

# ============================================================================
# LOAD GENERATOR - STRESS THE APPLICATION
# This generates traffic to trigger all the above scenarios
# ============================================================================
echo ""
echo "--- Deploying Load Generator ---"
echo "This will send continuous traffic to the Application Gateway"

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-generator
  namespace: default
  labels:
    app: load-generator
    scenario: chaos-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-generator
  template:
    metadata:
      labels:
        app: load-generator
        scenario: chaos-demo
    spec:
      containers:
      - name: load-gen
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo "Starting load generation against http://${APPGW_PUBLIC_IP}"
          while true; do
            # Send requests to App Gateway
            for i in \$(seq 1 10); do
              curl -s -o /dev/null -w "%{http_code} - %{time_total}s\n" \
                "http://${APPGW_PUBLIC_IP}/" &
            done
            wait
            sleep 1
          done
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF

echo "Load generator deployed. It will send 10 requests/second to App Gateway."

# ============================================================================
# AZURE MONITOR ALERT VERIFICATION
# ============================================================================
echo ""
echo "========================================================================"
echo "AZURE MONITOR ALERTS CONFIGURED"
echo "========================================================================"
echo ""
echo "The following alerts should fire within 5-10 minutes:"
echo ""
echo "1. alert-aks-high-memory"
echo "   Condition: avg Memory Working Set Percentage > 80%"
echo "   Trigger: memory-stress-pod consuming memory"
echo ""
echo "2. alert-appgw-unhealthy-backend"  
echo "   Condition: avg UnhealthyHostCount > 0"
echo "   Trigger: faulty-backend returning 500 errors"
echo ""
echo "3. alert-appgw-high-latency"
echo "   Condition: avg Backend Response Time > 1000ms"
echo "   Trigger: slow-backend with 2-10s delays"
echo ""
echo "4. alert-aks-high-cpu"
echo "   Condition: avg Percentage CPU > 80%"
echo "   Trigger: load-generator creating CPU pressure"
echo ""

# ============================================================================
# ADX QUERIES FOR SRE AGENT
# ============================================================================
echo "========================================================================"
echo "ADX QUERIES FOR SRE AGENT INVESTIGATION"
echo "========================================================================"
echo ""
echo "After 5-10 minutes, run these queries in ADX to see the incident data:"
echo ""
echo "1. Detect High Error Rate:"
echo "   DetectHighErrorRate()"
echo ""
echo "2. Detect Slow Responses:"
echo "   DetectSlowResponses()"
echo ""
echo "3. Detect Pod Crash Loops:"
echo "   DetectPodRestartLoops()"
echo ""
echo "4. Find Correlated Issues:"
echo "   FindCorrelatedIssues(30m)"
echo ""
echo "5. Comprehensive Investigation (last 30 mins):"
echo "   InvestigateIncident(ago(30m), now())"
echo ""

# ============================================================================
# MONITORING COMMANDS
# ============================================================================
echo "========================================================================"
echo "MONITORING COMMANDS"
echo "========================================================================"
echo ""
echo "Watch pod status:"
echo "  kubectl get pods -l scenario=chaos-demo -w"
echo ""
echo "View pod logs:"
echo "  kubectl logs -l app=crash-loop --tail=20"
echo "  kubectl logs -l app=memory-stress --tail=20"
echo ""
echo "Check Azure Monitor alerts:"
echo "  az monitor metrics alert list -g $RESOURCE_GROUP -o table"
echo ""
echo "View alert state:"
echo "  az monitor alert list -g $RESOURCE_GROUP --query \"[].{Name:name, State:properties.essentials.monitorCondition}\" -o table"
echo ""
echo "Application Gateway backend health:"
echo "  az network application-gateway show-backend-health -g $RESOURCE_GROUP -n $APPGW_NAME --query 'backendAddressPools[].backendHttpSettingsCollection[].servers[].health' -o table"
echo ""
echo "========================================================================"
echo "CLEANUP COMMAND"
echo "========================================================================"
echo ""
echo "To remove all chaos resources:"
echo "  kubectl delete deployment -l scenario=chaos-demo"
echo "  kubectl delete daemonset -l scenario=chaos-demo"
echo "  kubectl delete service faulty-backend-service slow-backend-service"
echo "  kubectl delete configmap faulty-nginx-config"
echo ""
echo "========================================================================"
echo "SCENARIO DEPLOYED!"
echo "========================================================================"
echo ""
echo "Timeline:"
echo "- 0-1 min:  Chaos pods starting, memory stress begins"
echo "- 1-2 min:  Node memory rising above 80%"
echo "- 2-5 min:  Logs flowing to Event Hub -> ADX"
echo "- 5-10 min: Azure Monitor alerts firing"
echo "- 10+ min:  SRE Agent can investigate via ADX"
echo ""
echo "Access your app (with errors): http://$APPGW_PUBLIC_IP"
echo ""
