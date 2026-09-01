# DEPLOY_CHECKLIST.md

One-page recipe to take the project from empty AWS account to fully verified
deployment. Follow top-to-bottom. Every requirement from the task is mapped
to the exact command that proves it.

Legend:
- `[local]` — run on your workstation
- `[ec2]` — run via `make ssh` on the instance
- `[browser]` — from your laptop against the public IP

Copy `EIP=<paste elastic ip>` into your shell after Section 1 so `$EIP` works
in every subsequent curl.

---

## 0. One-time prep

```bash
# [local]
cd /home/lenovo/microservices-nginx-pm2

curl -s https://checkip.amazonaws.com     # copy the IP
$EDITOR terraform-scripts/environments/dev.tfvars
# set:  ssh_cidr = "<your-ip>/32"

aws sso login --profile aws-dharmendra    # or: make -C terraform-scripts refresh
```

---

## 1. Provision AWS infrastructure

```bash
# [local]
cd terraform-scripts
make init
make plan ENV=dev            # review resource count
make apply ENV=dev           # type 'apply dev' at prompt
EIP=$(terraform output -raw instance_public_ip)
echo "EIP=$EIP"
```

Wait ~2 min for `user_data.sh` to install Node/PM2/Nginx:

```bash
# [local]
make ssh CMD='sudo tail -n 5 /var/log/user-data.log'
# expect: ########## user_data complete ##########
```

---

## 2. Deploy the application

```bash
# [local]
cd ..                        # back to repo root
make -C terraform-scripts upload-app
# or directly:
# ./deploy/scripts/upload-app.sh
```

The script rsyncs the app, installs `deploy/nginx/microservices.conf`, runs
`npm ci` per service, starts PM2, and smoke-tests all three health endpoints.

---

## 3. Verify every task requirement

### ✅ Req 1 — Three microservices exist and respond

```bash
# [browser] all should return {"service":"...","status":"UP",...}
curl http://$EIP/api/users/health
curl http://$EIP/api/products/health
curl http://$EIP/api/orders/health
```

### ✅ Req 2 & 3 — Managed by PM2 via single ecosystem file

```bash
# [ec2]
make -C terraform-scripts ssh CMD='pm2 list && cat /opt/app/ecosystem.config.js | head -20'
# expect: 3 processes (or 4 rows if user-service is in cluster mode) all "online"
```

### ✅ Req 4a — PM2 crash recovery

```bash
# [ec2]
make -C terraform-scripts ssh CMD='
  BEFORE=$(pm2 pid user-service | head -1)
  echo "before: $BEFORE"
  kill -9 $BEFORE
  sleep 3
  AFTER=$(pm2 pid user-service | head -1)
  echo "after:  $AFTER"
  test "$BEFORE" != "$AFTER" && echo "PID changed - PM2 restarted OK"
'
```

### ✅ Req 4b — Services start after EC2 reboot

```bash
# [local] hard-reboot the instance from AWS side
IID=$(cd terraform-scripts && terraform output -raw instance_id)
aws ec2 reboot-instances --instance-ids "$IID" --profile aws-dharmendra
sleep 90                     # give it time to come back
curl -sf http://$EIP/api/users/health && echo OK
curl -sf http://$EIP/api/products/health && echo OK
curl -sf http://$EIP/api/orders/health && echo OK
```

### ✅ Req 5 & 6 — Nginx reverse proxy + path routing

```bash
# [browser]
curl -i http://$EIP/api/users/1
curl -i http://$EIP/api/products/2
curl -i http://$EIP/api/orders/100         # calls product-service internally
```

### ✅ Req 7 — Ports 3001-3003 NOT public

```bash
# [browser] each of these MUST fail with a timeout / connection refused
curl --max-time 3 http://$EIP:3001/health && echo LEAKED || echo "3001 blocked ✓"
curl --max-time 3 http://$EIP:3002/health && echo LEAKED || echo "3002 blocked ✓"
curl --max-time 3 http://$EIP:3003/health && echo LEAKED || echo "3003 blocked ✓"
```

### ✅ Req 8 — Security Group rules

```bash
# [local]
SG=$(cd terraform-scripts && terraform output -raw app_security_group_id)
aws ec2 describe-security-groups --group-ids "$SG" \
  --profile aws-dharmendra \
  --query 'SecurityGroups[0].IpPermissions[].{proto:IpProtocol,from:FromPort,to:ToPort,cidr:IpRanges[0].CidrIp}' \
  --output table
# expect: 22 <your-ip>/32, 80 0.0.0.0/0, 443 0.0.0.0/0 - NOTHING else
```

### ✅ Req 9 — /health endpoints (already covered by Req 1)

### ✅ Req 10 — Each service reachable through Nginx (already covered by Req 1)

### ✅ Req 11 — Isolation: crashing one doesn't affect others

```bash
# [ec2]
make -C terraform-scripts ssh CMD='
  pm2 stop product-service
  echo "-- users still ok --"; curl -sf http://127.0.0.1:3001/health && echo
  echo "-- orders /health still ok --"; curl -sf http://127.0.0.1:3003/health && echo
  echo "-- orders/100 returns 503 (product down) --"
  curl -s -o - -w "\nHTTP %{http_code}\n" http://127.0.0.1:3003/orders/100
  pm2 start product-service
'
```

### ✅ Req 12 — Crash recovery (already covered by Req 4a)

### ✅ Req 13 — Logs

```bash
# [ec2] PM2 logs
make -C terraform-scripts ssh CMD='ls -la /opt/app/logs && pm2 logs --lines 5 --nostream'

# [ec2] Nginx logs
make -C terraform-scripts ssh CMD='
  sudo tail -3 /var/log/nginx/microservices_access.log
  sudo tail -3 /var/log/nginx/microservices_error.log
'
```

### ✅ Req 14 — Auto-start after reboot (already covered by Req 4b)

### ✅ Req 15 — Inter-service communication

```bash
# [browser] Order Service must call Product Service transparently
curl http://$EIP/api/orders/100
# expect JSON with BOTH "order" and "product" keys
```

---

## 4. Bonus — PM2 cluster + zero-downtime reload

Cluster mode is already on for `user-service` (2 instances). Prove the reload:

```bash
# [local] terminal A - continuous load
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" "http://$EIP/api/users/health"
  sleep 0.1
done

# [ec2] terminal B - reload
make -C terraform-scripts ssh CMD='pm2 reload user-service && pm2 list'

# terminal A should show ONLY 200s throughout the reload window
```

---

## 5. Bonus — HTTPS with Let's Encrypt

Requires a real domain with an A-record pointing at `$EIP`. Wait for DNS
propagation (`dig api.example.com` returns your EIP), then:

```bash
# [local]
./deploy/scripts/enable-https.sh api.example.com you@example.com
```

Verify:

```bash
# [browser]
curl -i http://api.example.com/api/users/health           # -> 301 to https
curl -sf https://api.example.com/api/users/health && echo OK
# Renewal test (already run by the script; re-run any time)
make -C terraform-scripts ssh CMD='sudo certbot renew --dry-run'
```

---

## 6. Teardown

```bash
make -C terraform-scripts destroy ENV=dev     # type 'destroy dev'
```

Removes EIP, instance, key pair (AWS + local .pem), security group, subnet,
IGW, and VPC. `logs/`, `plans/`, `state-backups/` remain locally — sweep with:

```bash
make -C terraform-scripts clean
```

---

## Quick-reference: what to check when something is off

| Symptom | First check |
|---|---|
| `terraform apply` times out on EIP | Public IP unreachable — SG rules or `map_public_ip_on_launch` |
| SSH refused | `ssh_cidr` — did your public IP change? |
| `upload-app.sh` hangs on "waiting for sshd" | Instance still booting; wait 60s and re-run |
| `/api/*/health` returns 502 | `make ssh CMD='pm2 list && sudo tail -30 /var/log/nginx/microservices_error.log'` |
| `/api/*/health` returns 404 | Trailing slash on `proxy_pass` in `deploy/nginx/microservices.conf` |
| Port 3001 leaks | server.js binding not `127.0.0.1` — grep `app.listen` |
| PM2 doesn't come back after reboot | `pm2 startup` step failed — `systemctl status pm2-ubuntu` |
| certbot fails with `unauthorized` | DNS not yet propagated OR HTTP-01 blocked by an intermediate proxy |
