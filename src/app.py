#!/usr/bin/env python3
"""
Shopping Web App - Simulates realistic e-commerce with configurable latency
Replaces the basic sample web app for SRE Agent demo
"""

import os
import json
import time
import random
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger('shopping-app')

# Configuration from environment
BASE_LATENCY = int(os.getenv('BASE_LATENCY_MS', '50')) / 1000
PRODUCT_LATENCY = int(os.getenv('PRODUCT_LATENCY_MS', '200')) / 1000
CART_LATENCY = int(os.getenv('CART_LATENCY_MS', '300')) / 1000
CHECKOUT_LATENCY = int(os.getenv('CHECKOUT_LATENCY_MS', '800')) / 1000
DB_FAILURE_RATE = float(os.getenv('DB_FAILURE_RATE', '0.05'))
PAYMENT_FAILURE_RATE = float(os.getenv('PAYMENT_FAILURE_RATE', '0.10'))
CHAOS_MODE = os.getenv('CHAOS_MODE', 'false').lower() == 'true'
CHAOS_MULTIPLIER = int(os.getenv('CHAOS_LATENCY_MULTIPLIER', '10'))

# Sample product catalog
PRODUCTS = [
    {"id": 1, "name": "Laptop Pro 15", "price": 1299.99, "category": "electronics"},
    {"id": 2, "name": "Wireless Mouse", "price": 29.99, "category": "electronics"},
    {"id": 3, "name": "USB-C Hub", "price": 49.99, "category": "electronics"},
    {"id": 4, "name": "Mechanical Keyboard", "price": 149.99, "category": "electronics"},
    {"id": 5, "name": "4K Monitor", "price": 399.99, "category": "electronics"},
    {"id": 6, "name": "Headphones Pro", "price": 199.99, "category": "audio"},
    {"id": 7, "name": "Bluetooth Speaker", "price": 79.99, "category": "audio"},
    {"id": 8, "name": "Webcam HD", "price": 89.99, "category": "electronics"},
    {"id": 9, "name": "Desk Lamp", "price": 34.99, "category": "home"},
    {"id": 10, "name": "Ergonomic Chair", "price": 299.99, "category": "furniture"},
]

# In-memory cart storage
carts = {}


def simulate_latency(base_latency):
    latency = base_latency
    if CHAOS_MODE:
        latency *= CHAOS_MULTIPLIER
    # Add jitter (±20%)
    jitter = latency * random.uniform(-0.2, 0.2)
    actual_latency = latency + jitter
    time.sleep(actual_latency)
    return actual_latency


def simulate_db_call():
    if random.random() < DB_FAILURE_RATE:
        logger.error("ERROR: Database connection timeout after 30s")
        raise Exception("Database connection failed")
    return True


def simulate_payment():
    if random.random() < PAYMENT_FAILURE_RATE:
        logger.error("ERROR: Payment gateway timeout - transaction failed")
        raise Exception("Payment processing failed")
    return True


class ShoppingHandler(BaseHTTPRequestHandler):
    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('X-Response-Time', str(self.response_time))
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        start_time = time.time()
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        try:
            if path == '/' or path == '/health':
                self.response_time = simulate_latency(BASE_LATENCY)
                self.send_json({
                    "status": "healthy",
                    "service": "shopping-app",
                    "version": "1.0.0",
                    "timestamp": datetime.utcnow().isoformat(),
                    "chaos_mode": CHAOS_MODE
                })

            elif path == '/api/products':
                self.response_time = simulate_latency(PRODUCT_LATENCY)
                simulate_db_call()
                category = query.get('category', [None])[0]
                products = PRODUCTS
                if category:
                    products = [p for p in PRODUCTS if p['category'] == category]
                logger.info(f"Retrieved {len(products)} products")
                self.send_json({"products": products, "count": len(products)})

            elif path.startswith('/api/products/'):
                self.response_time = simulate_latency(PRODUCT_LATENCY)
                simulate_db_call()
                product_id = int(path.split('/')[-1])
                product = next((p for p in PRODUCTS if p['id'] == product_id), None)
                if product:
                    logger.info(f"Retrieved product {product_id}")
                    self.send_json(product)
                else:
                    logger.warning(f"Product {product_id} not found")
                    self.send_json({"error": "Product not found"}, 404)

            elif path.startswith('/api/cart/'):
                self.response_time = simulate_latency(CART_LATENCY)
                simulate_db_call()
                user_id = path.split('/')[-1]
                cart = carts.get(user_id, {"items": [], "total": 0})
                logger.info(f"Retrieved cart for user {user_id}")
                self.send_json(cart)

            elif path == '/api/categories':
                self.response_time = simulate_latency(BASE_LATENCY)
                categories = list(set(p['category'] for p in PRODUCTS))
                self.send_json({"categories": categories})

            else:
                self.response_time = simulate_latency(BASE_LATENCY)
                self.send_json({"error": "Not found", "path": path}, 404)

        except Exception as e:
            self.response_time = time.time() - start_time
            logger.error(f"ERROR: Request failed - {str(e)}")
            self.send_json({"error": str(e), "status": "error"}, 500)

    def do_POST(self):
        start_time = time.time()
        parsed = urlparse(self.path)
        path = parsed.path

        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = json.loads(self.rfile.read(content_length)) if content_length > 0 else {}

            if path.startswith('/api/cart/'):
                self.response_time = simulate_latency(CART_LATENCY)
                simulate_db_call()
                parts = path.split('/')
                user_id = parts[3]

                if len(parts) > 4 and parts[4] == 'add':
                    product_id = body.get('product_id')
                    quantity = body.get('quantity', 1)
                    product = next((p for p in PRODUCTS if p['id'] == product_id), None)
                    if product:
                        if user_id not in carts:
                            carts[user_id] = {"items": [], "total": 0}
                        carts[user_id]["items"].append({
                            "product": product,
                            "quantity": quantity
                        })
                        carts[user_id]["total"] += product["price"] * quantity
                        logger.info(f"Added product {product_id} to cart for user {user_id}")
                        self.send_json(carts[user_id])
                    else:
                        self.send_json({"error": "Product not found"}, 404)
                else:
                    self.send_json({"error": "Invalid cart operation"}, 400)

            elif path == '/api/checkout':
                self.response_time = simulate_latency(CHECKOUT_LATENCY)
                simulate_db_call()
                simulate_payment()
                user_id = body.get('user_id')
                cart = carts.get(user_id, {"items": [], "total": 0})
                if cart["items"]:
                    order_id = f"ORD-{random.randint(10000, 99999)}"
                    logger.info(f"Checkout successful for user {user_id}, order {order_id}")
                    carts[user_id] = {"items": [], "total": 0}
                    self.send_json({
                        "order_id": order_id,
                        "status": "confirmed",
                        "total": cart["total"],
                        "items_count": len(cart["items"])
                    })
                else:
                    logger.warning(f"Checkout failed - empty cart for user {user_id}")
                    self.send_json({"error": "Cart is empty"}, 400)

            else:
                self.response_time = simulate_latency(BASE_LATENCY)
                self.send_json({"error": "Not found"}, 404)

        except Exception as e:
            self.response_time = time.time() - start_time
            logger.error(f"ERROR: Request failed - {str(e)}")
            self.send_json({"error": str(e), "status": "error"}, 500)

    def log_message(self, format, *args):
        logger.info(f"{self.client_address[0]} - {args[0]}")


if __name__ == '__main__':
    logger.info(f"Starting Shopping App on port 8080")
    logger.info(f"Chaos Mode: {CHAOS_MODE}, Latency Multiplier: {CHAOS_MULTIPLIER}x")
    HTTPServer(('0.0.0.0', 8080), ShoppingHandler).serve_forever()
