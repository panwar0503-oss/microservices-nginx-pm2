// PM2 ecosystem — one config for all three microservices.
// Boot everything with:  pm2 start ecosystem.config.js
// Persist across reboot: pm2 save && pm2 startup   (see Phase 17)
//
// Common defaults are extracted into `common` and spread into each app so
// the intent stays obvious and drift stays impossible.
//
// ------------------------------------------------------------------------
// All three services run in CLUSTER mode with 2 workers each.
// ------------------------------------------------------------------------
// Cluster mode = PM2 forks N Node workers, all listening on the same port.
// The Node cluster master owns the listening socket and round-robins new
// connections to workers. Two consequences that matter for us:
//
//   1. Zero-downtime reloads — `pm2 reload <name>` restarts workers one at
//      a time; the other worker(s) keep serving during the swap, so no 5xx.
//   2. Multi-core CPU use — a single Node process is single-threaded; two
//      workers on a 2-vCPU box double request-handling throughput on
//      CPU-bound work.
//
// 6 Node workers + Nginx fit comfortably on t3.micro (1 GB RAM); each
// worker sits around 40-60 MB in this project.
// ------------------------------------------------------------------------

const path = require('path');
const LOGS = path.join(__dirname, 'logs');

const common = {
  exec_mode:     'cluster', // was 'fork'; cluster enables zero-downtime reload for every service
  instances:     2,         // 2 workers per service — same knob as user-service used to have
  autorestart:   true,      // restart on unexpected exit
  restart_delay: 2000,      // wait 2s between restarts (avoids CPU thrash)
  max_restarts:  10,        // give up after 10 rapid failures…
  min_uptime:    '10s',     // …where "rapid" means dies within 10s
  kill_timeout:  5000,      // SIGKILL 5s after SIGINT if not exited (matches our 10s safety net)
  wait_ready:    false,     // set true only if the app emits `process.send('ready')`
  time:          true,      // timestamp every log line
  merge_logs:    true,      // combine cluster workers' logs into one file
};

module.exports = {
  apps: [
    {
      ...common,
      name:       'user-service',
      script:     './services/user-service/server.js',
      cwd:        __dirname,
      env: {
        NODE_ENV: 'production',
        PORT:     3001,
      },
      out_file:   `${LOGS}/user-out.log`,
      error_file: `${LOGS}/user-error.log`,
    },
    {
      ...common,
      name:       'product-service',
      script:     './services/product-service/server.js',
      cwd:        __dirname,
      env: {
        NODE_ENV: 'production',
        PORT:     3002,
      },
      out_file:   `${LOGS}/product-out.log`,
      error_file: `${LOGS}/product-error.log`,
    },
    {
      ...common,
      name:       'order-service',
      script:     './services/order-service/server.js',
      cwd:        __dirname,
      env: {
        NODE_ENV:            'production',
        PORT:                3003,
        PRODUCT_SERVICE_URL: 'http://127.0.0.1:3002',
      },
      out_file:   `${LOGS}/order-out.log`,
      error_file: `${LOGS}/order-error.log`,
    },
  ],
};
