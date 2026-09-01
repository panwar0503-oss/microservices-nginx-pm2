// User Service
// -------------------------------------------------------------
// A tiny Express microservice that owns the "user" domain.
// It listens ONLY on 127.0.0.1 (loopback) so it is unreachable
// from outside the host. Nginx (same host) will proxy to it.
// -------------------------------------------------------------

const express = require('express');

const SERVICE_NAME = 'user-service';
const HOST = '127.0.0.1';                                 // loopback only — see README
const PORT = parseInt(process.env.PORT, 10) || 3001;      // env override for PM2/tests

const app = express();
app.use(express.json());

// -------------------------------------------------------------
// In-memory "database" — good enough for a learning project.
// In real production this would be Postgres/DynamoDB/etc.
// -------------------------------------------------------------
const users = [
  { id: 1, name: 'Alice',   email: 'alice@example.com'   },
  { id: 2, name: 'Bob',     email: 'bob@example.com'     },
  { id: 3, name: 'Charlie', email: 'charlie@example.com' },
];

// -------------------------------------------------------------
// GET /health
// Standard health probe. Includes PID so we can later observe
// PM2 restarts and cluster-mode workers.
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
// GET /users — list all users
// -------------------------------------------------------------
app.get('/users', (req, res) => {
  res.json({ service: SERVICE_NAME, count: users.length, users });
});

// -------------------------------------------------------------
// GET /users/:id — fetch a single user by numeric id
// -------------------------------------------------------------
app.get('/users/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  if (Number.isNaN(id)) {
    return res.status(400).json({ error: 'id must be a number' });
  }
  const user = users.find(u => u.id === id);
  if (!user) {
    return res.status(404).json({ error: `user ${id} not found` });
  }
  res.json({ service: SERVICE_NAME, user });
});

// -------------------------------------------------------------
// Boot — bind explicitly to 127.0.0.1 to keep the port private.
// -------------------------------------------------------------
const server = app.listen(PORT, HOST, () => {
  console.log(`[${SERVICE_NAME}] listening on http://${HOST}:${PORT} (pid=${process.pid})`);
});

// -------------------------------------------------------------
// Graceful shutdown — PM2 sends SIGINT on stop/reload. Closing
// the server lets in-flight requests finish before we exit,
// which is the foundation of zero-downtime reloads later.
// -------------------------------------------------------------
const shutdown = (signal) => {
  console.log(`[${SERVICE_NAME}] received ${signal}, shutting down…`);
  server.close(() => {
    console.log(`[${SERVICE_NAME}] closed cleanly`);
    process.exit(0);
  });
  // Safety net — if something hangs, force-exit after 10s.
  setTimeout(() => process.exit(1), 10_000).unref();
};
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
