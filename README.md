# Azure SRE Demo - Shopping App

A simulated e-commerce application for SRE (Site Reliability Engineering) demonstrations, featuring configurable latency and chaos engineering capabilities.

## Project Structure

```
azure-sre-demo/
├── src/
│   ├── app.py              # Main shopping application
│   ├── Dockerfile          # Container image definition
│   └── requirements.txt    # Python dependencies
├── shopping-app.yaml       # Kubernetes deployment manifests
├── memory-stress.yaml      # Chaos engineering - memory stress
├── chaos-scenario.sh       # Chaos testing scripts
├── deploy-shopping-app.sh  # Deployment automation
├── sre-demo.sh            # SRE demo script
└── chaos_investigation_queries.kql  # KQL queries for investigation
```

## Features

- **Simulated E-commerce APIs**: Products, Cart, Checkout
- **Configurable Latency**: Adjust response times per endpoint
- **Chaos Mode**: Simulate failures and increased latency
- **Load Generator**: Built-in traffic simulation

## Quick Start

### Local Development

```bash
cd src
python app.py
```

### Build Container Image

```bash
cd src
docker build -t shopping-app:latest .
docker run -p 8080:8080 shopping-app:latest
```

### Deploy to Kubernetes

```bash
kubectl apply -f shopping-app.yaml
```

## Configuration

Environment variables for the shopping app:

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_LATENCY_MS` | 50 | Base latency in milliseconds |
| `PRODUCT_LATENCY_MS` | 200 | Product API latency |
| `CART_LATENCY_MS` | 300 | Cart API latency |
| `CHECKOUT_LATENCY_MS` | 800 | Checkout API latency |
| `DB_FAILURE_RATE` | 0.05 | Database failure probability (0-1) |
| `PAYMENT_FAILURE_RATE` | 0.10 | Payment failure probability (0-1) |
| `CHAOS_MODE` | false | Enable chaos mode |
| `CHAOS_LATENCY_MULTIPLIER` | 10 | Latency multiplier in chaos mode |

## API Endpoints

- `GET /health` - Health check
- `GET /api/products` - List all products
- `GET /api/products?category=<category>` - Filter by category
- `GET /api/products/<id>` - Get product by ID
- `GET /api/categories` - List categories
- `GET /api/cart/<user_id>` - Get user cart
- `POST /api/cart/<user_id>/add` - Add item to cart
- `POST /api/checkout` - Process checkout

## Chaos Engineering

Enable chaos mode to test system resilience:

```bash
kubectl set env deployment/shopping-app CHAOS_MODE=true
```

Run chaos scenarios:

```bash
./chaos-scenario.sh
```

## License

MIT
