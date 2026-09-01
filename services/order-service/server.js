// Order Service
// -------------------------------------------------------------
// Owns the "order" domain. Listens only on 127.0.0.1:3003.
// Calls Product Service for product enrichment on GET /orders/:id.
// -------------------------------------------------------------

const express = require('express');
const axios   = require('axios');

const SERVICE_NAME = 'order-service';
const HOST = '127.0.0.1';
const PORT = parseInt(process.env.PORT, 10) || 3003;

// Dependency URL is an env var — makes it swappable in ecosystem.config.js
// and easy to change to a real hostname in production.
const PRODUCT_SERVICE_URL = process.env.PRODUCT_SERVICE_URL || 'http://127.0.0.1:3002';

// Short timeout — a slow dependency should fail fast, not hang the caller.
const PRODUCT_TIMEOUT_MS = 2000;

const app = express();
app.use(express.json());

// Orders reference product IDs; product details are fetched on demand.
const orders = [
  { id: 100, userId: 1, productId: 1, quantity: 2 },
  { id: 101, userId: 2, productId: 3, quantity: 1 },
  { id: 102, userId: 1, productId: 4, quantity: 3 },
  { id: 103, userId: 3, productId: 2, quantity: 5 },
];

// -------------------------------------------------------------
// GET /health
// Intentionally does NOT check Product Service. This service is
// "healthy" if its own process is alive. A dependency outage
// should surface as a 503 on the dependent endpoint, not as this
// service being marked down and killed by an orchestrator.
// -------------------------------------------------------------
app.get('/health', (req, res) => {
  res.json({
    service:   SERVICE_NAME,
    status:    'UP',
    port:      PORT,
    pid:       process.pid,
    timestamp: new Date().toISOString(),
  });
});

// -------------------------------------------------------------
// GET /orders — list all orders (no product enrichment)
// -------------------------------------------------------------
app.get('/orders', (req, res) => {
  res.json({ service: SERVICE_NAME, count: orders.length, orders });
});

// -------------------------------------------------------------
// GET /orders/:id — order enriched with product details.
// Demonstrates service-to-service communication and graceful
// degradation when the dependency is unavailable.
// -------------------------------------------------------------
app.get('/orders/:id', async (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) {
    return res.status(400).json({ error: 'id must be a number' });
  }

  const order = orders.find(o => o.id === id);
  if (!order) {
    return res.status(404).json({ error: `order ${id} not found` });
  }

  try {
    const url = `${PRODUCT_SERVICE_URL}/products/${order.productId}`;
    const { data } = await axios.get(url, { timeout: PRODUCT_TIMEOUT_MS });
    return res.json({
      service: SERVICE_NAME,
      order,
      product: data.product,
    });
  } catch (err) {
    // Map any dependency failure (connection refused, timeout, 5xx)
    // to a clear 503 so callers know it's the *dependency* that failed.
    console.error(`[${SERVICE_NAME}] product-service call failed:`, err.code || err.message);
    return res.status(503).json({
      error:      'Product service unavailable',
      dependency: PRODUCT_SERVICE_URL,
      reason:     err.code || err.message,
    });
  }
});

const server = app.listen(PORT, HOST, () => {
  console.log(`[${SERVICE_NAME}] listening on http://${HOST}:${PORT} (pid=${process.pid})`);
  console.log(`[${SERVICE_NAME}] depends on ${PRODUCT_SERVICE_URL}`);
});

const shutdown = (signal) => {
  console.log(`[${SERVICE_NAME}] received ${signal}, shutting down…`);
  server.close(() => {
    console.log(`[${SERVICE_NAME}] closed cleanly`);
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
