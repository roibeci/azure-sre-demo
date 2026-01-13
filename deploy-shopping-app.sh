#!/bin/bash

################################################################################
# Shopping App Deployment & Chaos Control
# Deploy the shopping web app and toggle chaos mode for SRE demo
################################################################################

set -e

RESOURCE_GROUP="rg-sre-demo"
AKS_CLUSTER_NAME="aks-sre-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure kubectl context
ensure_aks_context() {
    echo "Getting AKS credentials..."
    az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing
}

# Deploy the shopping app
deploy_shopping_app() {
    echo "========================================================================"
    echo "Deploying Shopping Web Application"
    echo "========================================================================"
    
    # Remove old web app if exists
    kubectl delete deployment web-app-demo --ignore-not-found=true
    kubectl delete service web-app-service --ignore-not-found=true
    
    # Deploy shopping app
    kubectl apply -f "$SCRIPT_DIR/shopping-app.yaml"
    
    echo ""
    echo "Waiting for Shopping App pods to be ready..."
    kubectl rollout status deployment/shopping-app --timeout=120s
    
    echo ""
    echo "Waiting for LoadBalancer IP..."
    for i in {1..60}; do
        SHOP_IP=$(kubectl get svc shopping-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$SHOP_IP" && "$SHOP_IP" != "null" ]]; then
            echo "Shopping App Internal IP: $SHOP_IP"
            break
        fi
        echo "Waiting... ($i/60)"
        sleep 5
    done
    
    echo ""
    echo "Shopping App deployed successfully!"
    echo ""
    echo "API Endpoints:"
    echo "  GET  /health              - Health check"
    echo "  GET  /api/products        - List all products"
    echo "  GET  /api/products?category=electronics"
    echo "  GET  /api/products/{id}   - Get product details"
    echo "  GET  /api/cart/{user_id}  - Get user's cart"
    echo "  POST /api/cart/{user_id}/add - Add to cart"
    echo "  POST /api/checkout        - Process checkout"
    echo ""
}

# Enable chaos mode (10x latency, higher failure rates)
enable_chaos() {
    echo "========================================================================"
    echo "ENABLING CHAOS MODE"
    echo "========================================================================"
    echo ""
    echo "This will:"
    echo "  - Increase all latencies by 10x"
    echo "  - Simulate database timeouts"
    echo "  - Simulate payment failures"
    echo ""
    
    kubectl patch configmap shopping-app-config -p '{"data":{"CHAOS_MODE":"true","CHAOS_LATENCY_MULTIPLIER":"10","DB_FAILURE_RATE":"0.20","PAYMENT_FAILURE_RATE":"0.30"}}'
    
    # Restart pods to pick up new config
    kubectl rollout restart deployment/shopping-app
    kubectl rollout status deployment/shopping-app --timeout=120s
    
    echo ""
    echo "CHAOS MODE ENABLED!"
    echo ""
    echo "Expected behavior:"
    echo "  - Base latency: 500ms (was 50ms)"
    echo "  - Product queries: 2000ms (was 200ms)"
    echo "  - Cart operations: 3000ms (was 300ms)"
    echo "  - Checkout: 8000ms (was 800ms)"
    echo "  - DB failure rate: 20%"
    echo "  - Payment failure rate: 30%"
    echo ""
    echo "Monitor with:"
    echo "  kubectl logs -l app=shopping-app -f"
    echo ""
}

# Disable chaos mode (return to normal)
disable_chaos() {
    echo "========================================================================"
    echo "DISABLING CHAOS MODE"
    echo "========================================================================"
    
    kubectl patch configmap shopping-app-config -p '{"data":{"CHAOS_MODE":"false","CHAOS_LATENCY_MULTIPLIER":"1","DB_FAILURE_RATE":"0.05","PAYMENT_FAILURE_RATE":"0.10"}}'
    
    # Restart pods to pick up new config
    kubectl rollout restart deployment/shopping-app
    kubectl rollout status deployment/shopping-app --timeout=120s
    
    echo ""
    echo "Chaos mode disabled. Normal operation restored."
}

# Update App Gateway to point to shopping app
update_appgw_backend() {
    echo "========================================================================"
    echo "Updating Application Gateway Backend"
    echo "========================================================================"
    
    SHOP_IP=$(kubectl get svc shopping-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    
    if [[ -z "$SHOP_IP" || "$SHOP_IP" == "null" ]]; then
        echo "ERROR: Shopping app service IP not found"
        exit 1
    fi
    
    echo "Updating App Gateway backend pool to: $SHOP_IP"
    
    az network application-gateway address-pool update \
        --resource-group $RESOURCE_GROUP \
        --gateway-name appgw-sre-demo \
        --name appGatewayBackendPool \
        --servers $SHOP_IP
    
    echo ""
    echo "App Gateway backend updated to shopping app!"
    
    APPGW_IP=$(az network public-ip show \
        --resource-group $RESOURCE_GROUP \
        --name pip-appgw-sre-demo \
        --query ipAddress -o tsv)
    
    echo ""
    echo "Access shopping app via: http://$APPGW_IP/api/products"
}

# Show status
show_status() {
    echo "========================================================================"
    echo "Shopping App Status"
    echo "========================================================================"
    echo ""
    echo "Pods:"
    kubectl get pods -l app=shopping-app -o wide
    echo ""
    echo "Service:"
    kubectl get svc shopping-app-service
    echo ""
    echo "ConfigMap (chaos settings):"
    kubectl get configmap shopping-app-config -o jsonpath='{.data}' | jq .
    echo ""
    echo "Load Generator:"
    kubectl get pods -l app=shopping-load-generator
}

# Cleanup
cleanup() {
    echo "Removing shopping app resources..."
    kubectl delete -f "$SCRIPT_DIR/shopping-app.yaml" --ignore-not-found=true
    echo "Cleanup complete."
}

# Show help
show_help() {
    echo "Shopping App Deployment & Chaos Control"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy      Deploy the shopping web application"
    echo "  chaos-on    Enable chaos mode (10x latency, high failure rates)"
    echo "  chaos-off   Disable chaos mode (normal operation)"
    echo "  update-gw   Update App Gateway to use shopping app backend"
    echo "  status      Show current status"
    echo "  cleanup     Remove all shopping app resources"
    echo "  full        Full deployment: deploy + update gateway"
    echo ""
}

# Main
case "${1:-help}" in
    deploy)
        ensure_aks_context
        deploy_shopping_app
        ;;
    chaos-on)
        ensure_aks_context
        enable_chaos
        ;;
    chaos-off)
        ensure_aks_context
        disable_chaos
        ;;
    update-gw)
        ensure_aks_context
        update_appgw_backend
        ;;
    status)
        ensure_aks_context
        show_status
        ;;
    cleanup)
        ensure_aks_context
        cleanup
        ;;
    full)
        ensure_aks_context
        deploy_shopping_app
        update_appgw_backend
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
