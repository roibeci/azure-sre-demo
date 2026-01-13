# Azure SRE Agent Demo

A complete Azure infrastructure demo for Site Reliability Engineering (SRE) with Azure SRE Agent integration. This project deploys a simulated e-commerce application with full observability pipeline (AKS → Event Hub → Azure Data Explorer) and chaos engineering capabilities.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Azure SRE Agent                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                      │
│  │   Alerts    │→│ Investigation│→│ Remediation │                      │
│  │  (Monitor)  │  │   (ADX)     │  │   (AKS)     │                      │
│  └─────────────┘  └─────────────┘  └─────────────┘                      │
└────────────┬──────────────┬──────────────┬──────────────────────────────┘
             │              │              │
┌────────────▼──────────────▼──────────────▼──────────────────────────────┐
│                         Observability Pipeline                          │
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐              │
│  │  App Gateway │───▶│  Event Hub   │───▶│     ADX      │              │
│  │   (WAF_v2)   │    │  (eh-logs)   │    │ (sre_logs_db)│              │
│  └──────────────┘    └──────────────┘    └──────────────┘              │
│         │                   ▲                   │                        │
│         │            ┌──────┴──────┐           │                        │
│         │            │   Fluentd   │           │                        │
│         │            │  DaemonSet  │           │                        │
│         │            └──────┬──────┘           │                        │
│         ▼                   │                   ▼                        │
│  ┌──────────────────────────────────────────────────────┐              │
│  │                    AKS Cluster                        │              │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │              │
│  │  │ Shopping App│  │Load Generator│ │Chaos Workloads│ │              │
│  │  │  (ACR)      │  │             │  │             │  │              │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │              │
│  └──────────────────────────────────────────────────────┘              │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
azure-sre-demo/
├── src/
│   ├── app.py              # Shopping app (Python/Flask)
│   ├── Dockerfile          # Container image definition
│   ├── requirements.txt    # Python dependencies
│   └── static/             # Frontend assets
├── sre-demo.sh             # Complete infrastructure setup
├── deploy-shopping-app.sh  # App deployment & chaos control
├── shopping-app.yaml       # Kubernetes manifests
├── chaos-scenario.sh       # Multi-scenario chaos testing
├── memory-stress.yaml      # Memory pressure workload
├── chaos_investigation_queries.kql  # KQL investigation queries
└── SKILL.md                # SRE Agent skill definition
```

## Prerequisites

- **Azure CLI** (2.50+) - `az login` authenticated
- **kubectl** - Kubernetes CLI
- **Docker** - For building container images
- **Bash** - Linux/macOS/WSL

## Installation Guide

### Step 1: Deploy Infrastructure

Run the complete infrastructure setup script. This creates all Azure resources in a single resource group.

```bash
# Clone the repository
git clone https://github.com/Azure-Samples/azure-sre-demo.git
cd azure-sre-demo

# Run infrastructure setup (takes ~30-45 minutes)
./sre-demo.sh
```

**Resources Created:**
| Resource | Name | Purpose |
|----------|------|---------||
| Resource Group | `rg-sre-demo` | Contains all resources |
| Virtual Network | `vnet-sre-demo` | Network isolation |
| AKS Cluster | `aks-sre-demo` | Kubernetes workloads |
| Azure Container Registry | `acrsredemo*` | Container images |
| Application Gateway | `appgw-sre-demo` | WAF + Load balancing |
| Event Hub Namespace | `ehns-sre-demo-*` | Log streaming |
| Azure Data Explorer | `adxsredemo*` | Log analytics |
| Managed Identity | `id-sre-demo-logs` | Workload identity |

### Step 2: Create ADX Tables

After infrastructure deployment, execute the schema in Azure Data Explorer:

1. Open ADX Web UI (URL printed at end of `sre-demo.sh`)
2. Connect to `sre_logs_db` database
3. Execute contents of `adx_schema.kql`

Key tables:
- `ApplicationGatewayAccessLogs` - App Gateway access logs
- `ApplicationGatewayFirewallLogs` - WAF events
- `ContainerLogs` - AKS container logs via Fluentd
- `PerformanceMetrics` - Azure metrics

### Step 3: Build and Deploy Shopping App

```bash
# Build and push to ACR
cd src
az acr build --registry acrsredemo<suffix> --image shopping-app:latest .

# Deploy to AKS
cd ..
./deploy-shopping-app.sh full
```

Or manually:
```bash
# Get ACR name
ACR_NAME=$(az acr list -g rg-sre-demo --query "[0].name" -o tsv)

# Build and push
az acr build --registry $ACR_NAME --image shopping-app:latest ./src

# Attach ACR to AKS (if not already attached)
az aks update -g rg-sre-demo -n aks-sre-demo --attach-acr $ACR_NAME

# Deploy
kubectl apply -f shopping-app.yaml
```

### Step 4: Configure Azure SRE Agent

1. **Create SRE Agent** in Azure Portal:
   - Go to: https://portal.azure.com/#create/Microsoft.SREAgent
   - Select resource group: `rg-sre-demo`
   
2. **Assign Roles** to SRE Agent Managed Identity:
   ```bash
   SRE_AGENT_ID="<principal-id-from-portal>"
   RG_ID="/subscriptions/$(az account show -q id -o tsv)/resourceGroups/rg-sre-demo"
   AKS_ID=$(az aks show -g rg-sre-demo -n aks-sre-demo --query id -o tsv)
   
   az role assignment create --assignee $SRE_AGENT_ID --role "Contributor" --scope $RG_ID
   az role assignment create --assignee $SRE_AGENT_ID --role "Azure Kubernetes Service Cluster Admin Role" --scope $AKS_ID
   az role assignment create --assignee $SRE_AGENT_ID --role "Monitoring Reader" --scope $RG_ID
   ```

3. **Grant ADX Access** (run in ADX Web UI):
   ```kql
   .add database sre_logs_db viewers ('aadapp=<SRE_AGENT_PRINCIPAL_ID>;<TENANT_ID>')
   ```

4. **Configure ADX Connector** in SRE Agent Portal:
   - Add Azure Data Explorer connector
   - Cluster URI: `https://adxsredemo*.swedencentral.kusto.windows.net`
   - Database: `sre_logs_db`
   
5. **Import Skills** from `sre_agent_skills.json` for automated diagnostics

## Usage

### Access the Shopping App

```bash
# Get App Gateway public IP
APPGW_IP=$(az network public-ip show -g rg-sre-demo -n pip-appgw-sre-demo --query ipAddress -o tsv)
echo "Shopping App: http://$APPGW_IP"

# Test endpoints
curl http://$APPGW_IP/api/products
curl http://$APPGW_IP/api/products/1
curl http://$APPGW_IP/health
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/` | GET | Web UI (frontend) |
| `/api/products` | GET | List all products |
| `/api/products?category=<cat>` | GET | Filter by category |
| `/api/products/<id>` | GET | Get product details |
| `/api/categories` | GET | List categories |
| `/api/cart/<user_id>` | GET | Get user's cart |
| `/api/cart/<user_id>/add` | POST | Add item to cart |
| `/api/checkout` | POST | Process checkout |

### Deploy Shopping App Commands

```bash
./deploy-shopping-app.sh deploy     # Deploy app
./deploy-shopping-app.sh status     # Check status
./deploy-shopping-app.sh update-gw  # Update App Gateway backend
./deploy-shopping-app.sh full       # Deploy + update gateway
./deploy-shopping-app.sh cleanup    # Remove app
```

## Chaos Engineering

### Enable Chaos Mode (Application Level)

Increases latency 10x and failure rates for testing SRE Agent response:

```bash
./deploy-shopping-app.sh chaos-on
```

**Effect:**
- Base latency: 50ms → 500ms
- Product queries: 200ms → 2000ms
- Cart operations: 300ms → 3000ms
- Checkout: 800ms → 8000ms
- DB failure rate: 5% → 20%
- Payment failure rate: 10% → 30%

Disable chaos mode:
```bash
./deploy-shopping-app.sh chaos-off
```

### Run Full Chaos Scenario

Deploys multiple chaos workloads to trigger Azure Monitor alerts:

```bash
./chaos-scenario.sh
```

**Scenarios Deployed:**
1. **Memory Stress DaemonSet** - Consumes ~6GB per node → triggers `alert-aks-high-memory`
2. **Faulty Backend** - Returns 500 errors for 70% of requests → triggers `alert-appgw-unhealthy-backend`
3. **Slow Backend** - 2-10 second response times → triggers `alert-appgw-high-latency`
4. **Crash Loop Pods** - Continuous restarts → visible in ContainerLogs
5. **Load Generator** - Stress traffic to App Gateway

### Monitor Chaos

```bash
# Watch pods
kubectl get pods -l scenario=chaos-demo -w

# View crash loop logs
kubectl logs -l app=crash-loop --tail=20

# Check Azure Monitor alerts
az monitor metrics alert list -g rg-sre-demo -o table

# Check App Gateway backend health
az network application-gateway show-backend-health \
  -g rg-sre-demo -n appgw-sre-demo \
  --query 'backendAddressPools[].backendHttpSettingsCollection[].servers[].health'
```

### Cleanup Chaos Resources

```bash
kubectl delete deployment -l scenario=chaos-demo
kubectl delete daemonset -l scenario=chaos-demo
kubectl delete service faulty-backend-service slow-backend-service
kubectl delete configmap faulty-nginx-config
```

## SRE Agent Investigation

After chaos is deployed, SRE Agent can investigate using ADX queries:

```kql
-- Detect high error rates
DetectHighErrorRate()

-- Detect slow responses
DetectSlowResponses()

-- Detect pod crash loops
DetectPodRestartLoops()

-- Find correlated issues
FindCorrelatedIssues(30m)

-- Comprehensive investigation
InvestigateIncident(ago(30m), now())
```

See `SKILL.md` for complete KQL reference.

## Configuration

### Shopping App Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_LATENCY_MS` | 50 | Base latency in milliseconds |
| `PRODUCT_LATENCY_MS` | 200 | Product API latency |
| `CART_LATENCY_MS` | 300 | Cart API latency |
| `CHECKOUT_LATENCY_MS` | 800 | Checkout API latency |
| `DB_FAILURE_RATE` | 0.05 | Database failure probability |
| `PAYMENT_FAILURE_RATE` | 0.10 | Payment failure probability |
| `CHAOS_MODE` | false | Enable chaos mode |
| `CHAOS_LATENCY_MULTIPLIER` | 10 | Latency multiplier in chaos mode |

### Azure Monitor Alerts

Pre-configured alerts in `sre-demo.sh`:
- `alert-aks-high-cpu` - CPU > 80%
- `alert-aks-high-memory` - Memory > 80%
- `alert-appgw-unhealthy-backend` - Unhealthy backends detected
- `alert-appgw-high-latency` - Response time > 1 second

## Log Flow Architecture

```
App Gateway Logs:
  Diagnostic Settings → Event Hub (adx-appgw-raw consumer)
    → ApplicationGatewayAccessLogsRaw (staging)
    → Update Policy transforms JSON
    → ApplicationGatewayAccessLogs (30+ columns)

AKS Container Logs:
  Fluentd DaemonSet → Event Hub (adx-aks-consumer)
    → ContainerLogs table
```

**Note:** Azure diagnostic logs arrive wrapped in `{"records":[...]}` format. The staging table + update policy pattern properly extracts and parses this data.

## Cleanup

Remove all resources:
```bash
az group delete --name rg-sre-demo --yes --no-wait
```

## License

MIT
