// Product Service
// -------------------------------------------------------------
// Owns the "product" domain. Listens only on 127.0.0.1:3002.
// -------------------------------------------------------------

const express = require('express');

const SERVICE_NAME = 'product-service';
const HOST = '127.0.0.1';
const PORT = parseInt(process.env.PORT, 10) || 3002;

const app = express();
app.use(express.json());

const products = [
  { id: 1, name: 'Keyboard',       price:  49.99, stock:  120 },
  { id: 2, name: 'Wireless Mouse', price:  24.50, stock:  340 },
  { id: 3, name: '27" Monitor',    price: 289.00, stock:   42 },
  { id: 4, name: 'USB-C Hub',      price:  35.75, stock:  210 },
];

app.get('/health', (req, res) => {
  res.json({
    service:   SERVICE_NAME,
    status:    'UP',
    port:      PORT,
    pid:       process.pid,
    timestamp: new Date().toISOString(),
  });
});

app.get('/products', (req, res) => {
  res.json({ service: SERVICE_NAME, count: products.length, products });
});

app.get('/products/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) {
    return res.status(400).json({ error: 'id must be a number' });
  }
  const product = products.find(p => p.id === id);
  if (!product) {
    return res.status(404).json({ error: `product ${id} not found` });
  }
  res.json({ service: SERVICE_NAME, product });
});

const server = app.listen(PORT, HOST, () => {
  console.log(`[${SERVICE_NAME}] listening on http://${HOST}:${PORT} (pid=${process.pid})`);
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
