# Nginx deployment (Phases 12–16, done on EC2)

## Install

```bash
sudo apt update
sudo apt install -y nginx
sudo systemctl enable --now nginx
nginx -v
```

## Deploy this config

Copy this repo's `microservices.conf` up to the server, then:

```bash
sudo cp deploy/nginx/microservices.conf /etc/nginx/sites-available/microservices
sudo ln -sf /etc/nginx/sites-available/microservices /etc/nginx/sites-enabled/microservices
sudo rm  -f /etc/nginx/sites-enabled/default          # remove default site
sudo nginx -t                                          # VALIDATE first
sudo systemctl reload nginx                            # only reload if -t was OK
```

## Verify (Phase 14)

On the server:

```bash
curl -s http://127.0.0.1/api/users/health
curl -s http://127.0.0.1/api/products/health
curl -s http://127.0.0.1/api/orders/health
curl -s http://127.0.0.1/api/orders/100
```

From your local machine (Phase 15):

```bash
curl -s http://EC2_PUBLIC_IP/api/users/health          # should work
curl -s --max-time 3 http://EC2_PUBLIC_IP:3001/health  # must FAIL — port is private
```

## Logs (Phase 16)

```bash
sudo tail -f /var/log/nginx/microservices_access.log
sudo tail -f /var/log/nginx/microservices_error.log
```

## Troubleshooting quick map

| Symptom                         | Check                                              |
|---------------------------------|----------------------------------------------------|
| `nginx -t` fails                | Read the error — usually a typo or missing `;`     |
| 502 Bad Gateway                 | `pm2 list` — is the upstream service online?       |
| 404 on `/api/users/users`       | Trailing slash on `proxy_pass` — must be `/`       |
| Public 80 unreachable           | AWS Security Group inbound 80 open?                |
| EC2:3001 reachable from outside | Bad — must be 127.0.0.1 binding in server.js       |
