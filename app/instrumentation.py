import os
import json
import logging
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from prometheus_client import Counter, Histogram

# ---------------------------------------------------------------------------
# 1. Prometheus Metrics Definitions
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    'http_requests_total', 
    'Total HTTP requests', 
    ['method', 'endpoint', 'http_status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds', 
    'HTTP request latency', 
    ['method', 'endpoint'],
    buckets=[0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
)

# ---------------------------------------------------------------------------
# 2. Custom JSON Logger (Injects trace_id)
# ---------------------------------------------------------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record):
        span = trace.get_current_span()
        trace_id = trace.format_trace_id(span.get_span_context().trace_id) if span else "0"
        span_id = trace.format_span_id(span.get_span_context().span_id) if span else "0"
        
        log_obj = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "message": record.getMessage(),
            "trace_id": trace_id,
            "span_id": span_id
        }
        return json.dumps(log_obj)

def get_logger(name):
    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        handler = logging.StreamHandler()
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
    return logger

# Disable default flask logging so it doesn't double-print
logging.getLogger('werkzeug').disabled = True

# ---------------------------------------------------------------------------
# 3. OpenTelemetry Setup Function
# ---------------------------------------------------------------------------
def setup_telemetry(app):
    # Tell OTel to send traces to the OTel Collector receiver (or Jaeger fallback)
    # On ECS the exporter is optional: spans are only shipped when an endpoint is configured
    # (task definition env var). Without it the app still runs and logs normally.
    otlp_endpoint = os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT")
    resource = Resource.create({
        "service.name": "flask-ecommerce-api",
        "service.version": os.environ.get("APP_VERSION", "dev"),
    })
    provider = TracerProvider(resource=resource)
    if otlp_endpoint:
        processor = BatchSpanProcessor(OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True))
        provider.add_span_processor(processor)
    trace.set_tracer_provider(provider)
    
    # Auto-instrument Flask and Requests
    FlaskInstrumentor().instrument_app(app)
    RequestsInstrumentor().instrument()
    
    return trace.get_tracer(__name__)
