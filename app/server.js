const express = require('express');
const path = require('path');
const client = require('prom-client');

const app = express();
const PORT = Number(process.env.PORT) || 8000;
const HOST = process.env.HOST || '0.0.0.0';

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// 1. Prometheus Registry & Default Host/Process Metrics
const register = new client.Registry();
client.collectDefaultMetrics({
  register,
  prefix: 'order_api_'
});

// 2. Custom Prometheus Metrics with Strictly Bounded Labels
const httpRequestsTotal = new client.Counter({
  name: 'order_api_http_requests_total',
  help: 'Total number of HTTP requests processed by the Order API',
  labelNames: ['method', 'route', 'status_code', 'outcome'],
  registers: [register]
});

const httpRequestDurationSeconds = new client.Histogram({
  name: 'order_api_http_request_duration_seconds',
  help: 'HTTP request latency distribution in seconds',
  labelNames: ['method', 'route', 'status_code', 'outcome'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  registers: [register]
});

const ordersCreatedTotal = new client.Counter({
  name: 'order_api_orders_created_total',
  help: 'Total number of business orders successfully created',
  labelNames: ['category', 'payment_method'],
  registers: [register]
});

const orderFailuresTotal = new client.Counter({
  name: 'order_api_order_failures_total',
  help: 'Total number of failed order attempts categorized by failure reason',
  labelNames: ['reason'],
  registers: [register]
});

// Whitelists to enforce bounded label cardinality
const ALLOWED_CATEGORIES = new Set(['electronics', 'books', 'groceries', 'general']);
const ALLOWED_PAYMENTS = new Set(['card', 'bkash', 'cod']);

function normalizeRoute(reqPath) {
  if (reqPath === '/health') return '/health';
  if (reqPath === '/api/orders') return '/api/orders';
  if (reqPath === '/metrics') return '/metrics';
  if (reqPath === '/' || reqPath === '/index.html') return '/';
  return 'unmatched';
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Pre-initialize zero-value label series so Prometheus/Grafana sees all series immediately on startup
['electronics', 'books', 'groceries'].forEach((cat) => {
  ['card', 'bkash', 'cod'].forEach((pay) => {
    ordersCreatedTotal.labels(cat, pay).inc(0);
  });
});
orderFailuresTotal.labels('validation_error').inc(0);
orderFailuresTotal.labels('payment_gateway_error').inc(0);

// 3. Request Telemetry Middleware
app.use((req, res, next) => {
  const stopTimer = httpRequestDurationSeconds.startTimer();

  res.on('finish', () => {
    const route = normalizeRoute(req.path);
    const statusCode = String(res.statusCode);
    const outcome = res.statusCode >= 400 ? 'failure' : 'success';
    const labels = {
      method: req.method,
      route,
      status_code: statusCode,
      outcome
    };

    httpRequestsTotal.inc(labels);
    stopTimer(labels);
  });

  next();
});

// 4. Required API Endpoints
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'UP',
    service: 'order-observability-api',
    uptime_seconds: Math.round(process.uptime()),
    timestamp: new Date().toISOString()
  });
});

app.post('/api/orders', async (req, res) => {
  try {
    const {
      item = 'mechanical-keyboard',
      quantity = 1,
      category = 'electronics',
      payment_method = 'card',
      mode = 'normal'
    } = req.body || {};

    const safeCategory = ALLOWED_CATEGORIES.has(category) ? category : 'general';
    const safePayment = ALLOWED_PAYMENTS.has(payment_method) ? payment_method : 'card';
    const parsedQty = Number(quantity);

    // Simulate realistic latency profiles across histogram buckets
    if (mode === 'slow') {
      await sleep(350 + Math.floor(Math.random() * 550)); // 350ms - 900ms
    } else {
      await sleep(12 + Math.floor(Math.random() * 48));   // 12ms - 60ms
    }

    // Controlled HTTP 400 Client Validation Error
    if (mode === 'error400' || !item || Number.isNaN(parsedQty) || parsedQty <= 0) {
      orderFailuresTotal.inc({ reason: 'validation_error' });
      const errPayload = {
        status: 'error',
        http_code: 400,
        outcome: 'failure',
        error_code: 'INVALID_ORDER_PAYLOAD',
        reason: 'validation_error',
        message: 'Order rejected: item name is required and quantity must be a positive integer.',
        timestamp: new Date().toISOString()
      };
      console.warn(JSON.stringify({ level: 'WARN', event: 'order_rejected_400', ...errPayload }));
      return res.status(400).json(errPayload);
    }

    // Controlled HTTP 500 Downstream Payment Gateway Failure
    if (mode === 'error500') {
      orderFailuresTotal.inc({ reason: 'payment_gateway_error' });
      const errPayload = {
        status: 'error',
        http_code: 500,
        outcome: 'failure',
        error_code: 'PAYMENT_GATEWAY_TIMEOUT',
        reason: 'payment_gateway_error',
        category: safeCategory,
        payment_method: safePayment,
        message: 'Simulated upstream payment gateway timeout while authorizing transaction.',
        timestamp: new Date().toISOString()
      };
      console.error(JSON.stringify({ level: 'ERROR', event: 'order_failed_500', ...errPayload }));
      return res.status(500).json(errPayload);
    }

    // Normal / Slow Successful Order Creation (HTTP 201)
    ordersCreatedTotal.inc({
      category: safeCategory,
      payment_method: safePayment
    });

    const orderId = `ORD-${Date.now()}-${Math.floor(100 + Math.random() * 900)}`;
    const successPayload = {
      status: 'success',
      http_code: 201,
      outcome: 'success',
      order_id: orderId,
      item: String(item).slice(0, 64),
      quantity: parsedQty,
      category: safeCategory,
      payment_method: safePayment,
      latency_profile: mode === 'slow' ? 'degraded_slow' : 'normal_fast',
      timestamp: new Date().toISOString()
    };

    console.log(JSON.stringify({ level: 'INFO', event: 'order_created_201', ...successPayload }));
    return res.status(201).json(successPayload);
  } catch (unexpectedErr) {
    orderFailuresTotal.inc({ reason: 'payment_gateway_error' });
    console.error(JSON.stringify({
      level: 'ERROR',
      event: 'unhandled_order_exception',
      message: unexpectedErr.message,
      timestamp: new Date().toISOString()
    }));
    return res.status(500).json({
      status: 'error',
      http_code: 500,
      outcome: 'failure',
      error_code: 'INTERNAL_SERVER_ERROR',
      message: 'Unexpected error processing order request.'
    });
  }
});

app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.status(200).end(await register.metrics());
  } catch (err) {
    res.status(500).end(err.message);
  }
});

app.listen(PORT, HOST, () => {
  console.log(JSON.stringify({
    level: 'INFO',
    event: 'server_started',
    listen: `${HOST}:${PORT}`,
    endpoints: ['/health', '/api/orders', '/metrics'],
    timestamp: new Date().toISOString()
  }));
});
