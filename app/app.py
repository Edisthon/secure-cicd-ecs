import os
import time
import secrets
import requests
from flask import Flask, jsonify, request, Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from instrumentation import setup_telemetry, get_logger, REQUEST_COUNT, REQUEST_LATENCY

app = Flask(__name__)  # NOSONAR S4502: stateless JSON API - no sessions, cookies or auth, so there are no ambient credentials for CSRF to abuse
tracer = setup_telemetry(app)
logger = get_logger(__name__)

APP_VERSION = os.environ.get("APP_VERSION", "dev")


@app.before_request
def before_request():
    request.start_time = time.time()


@app.after_request
def after_request(response):
    req_time = time.time() - request.start_time
    REQUEST_COUNT.labels(request.method, request.path, response.status_code).inc()
    REQUEST_LATENCY.labels(request.method, request.path).observe(req_time)
    return response


@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


INVENTORY = {
    "1": {"name": "Laptop", "price": 999.99},
    "2": {"name": "Smartphone", "price": 499.99},
    "3": {"name": "Headphones", "price": 149.99},
}


@app.route('/item/<item_id>')
def get_item(item_id):
    logger.info(f"Fetching item details for {item_id}")
    item = INVENTORY.get(item_id)
    if not item:
        logger.warning(f"Item {item_id} not found!")
        return jsonify(error="Item not found"), 404
    return jsonify(item=item), 200


@app.route('/cart', methods=['POST'])
def add_to_cart():
    logger.info("Adding item to cart")
    data = request.get_json(silent=True)

    if not data or not data.get("item_id"):
        logger.error("Missing item_id in request payload")
        return jsonify(error="Bad Request: Missing item_id"), 400

    item_id = str(data.get("item_id"))
    item = INVENTORY.get(item_id)

    if not item:
        logger.warning(f"Cannot add non-existent item {item_id} to cart")
        return jsonify(error="Item not found"), 404

    logger.info(f"Successfully added {item['name']} to cart")
    return jsonify(message="Item added to cart successfully!", cart_total=item['price']), 201


@app.route('/')
def home():
    logger.info("Home page accessed")
    return jsonify(message="Welcome to the E-Commerce API!"), 200


@app.route('/health')
def health():
    # Used by the ALB target group and the ECS container health check.
    return jsonify(status="healthy"), 200


@app.route('/version')
def version():
    # Lets the pipeline prove WHICH build is serving traffic after a deploy.
    return jsonify(version=APP_VERSION), 200


@app.route('/checkout')
def checkout():
    logger.info("Starting checkout process")
    time.sleep(0.5)
    # Simulated 5% failure so the Project-Monitoring alarms have something to see.
    if secrets.randbelow(100) < 5:  # not security-sensitive; CSPRNG used so no weak-PRNG finding
        logger.error("Checkout failed! Database connection lost.")
        return jsonify(error="Internal Server Error"), 500
    logger.info("Checkout completed successfully")
    return jsonify(message="Order processed successfully!"), 200


@app.route('/search')
def search():
    query = request.args.get('q', 'default')
    logger.info(f"Searching for product: {query}")
    with tracer.start_as_current_span("inventory_api_call"):
        try:
            requests.get("https://httpbin.org/delay/1", timeout=3)
            logger.info("Successfully fetched inventory from external API")
            return jsonify(results=[f"Result 1 for {query}", f"Result 2 for {query}"]), 200
        except Exception as e:
            logger.error(f"Failed to reach inventory API: {str(e)}")
            return jsonify(error="Inventory service unavailable"), 503


if __name__ == '__main__':
    # Local development only. In the container gunicorn serves the app (see Dockerfile).
    app.run(host='127.0.0.1', port=int(os.environ.get("PORT", "8080")))
