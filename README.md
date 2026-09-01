# microservices-nginx-pm2

A **production-style Node.js microservices deployment** on AWS EC2 with Nginx as
an API gateway, PM2 for process management, and Terraform for infrastructure —
built as a learning project that mirrors how a small-to-mid team would ship a
Node.js API before moving to Kubernetes.

Three Node/Express services (`user`, `product`, `order`) each own their domain
and bind to `127.0.0.1`; Nginx is the sole internet entry point; PM2 runs the
services under systemd so they survive crashes and reboots; Terraform builds
the VPC, subnets, security groups, key pair, and EC2 instance.

---

## Table of contents

1. [Architecture](#1-architecture)
2. [What's in this repo](#2-whats-in-this-repo)
3. [Prerequisites](#3-prerequisites)
4. [Quick start (5-minute local run)](#4-quick-start-5-minute-local-run)
5. [Full AWS deployment — step by step](#5-full-aws-deployment--step-by-step)
6. [Verifying every requirement](#6-verifying-every-requirement)
7. [Enabling HTTPS (Let's Encrypt)](#7-enabling-https-lets-encrypt)
8. [Day-2 operations](#8-day-2-operations)
9. [Troubleshooting](#9-troubleshooting)
10. [Design decisions & interview notes](#10-design-decisions--interview-notes)
11. [Cost](#11-cost)
12. [Teardown](#12-teardown)

---

## 1. Architecture

### 1.1 System diagram

```
                                    Internet
                                       │
                          ┌────────────┴────────────┐
                          │      Security Group     │
                          │      22   ← your IP     │
                          │      80   ← 0.0.0.0/0   │
                          │      443  ← 0.0.0.0/0   │
                          │  (3001-3003 NEVER open) │
                          └────────────┬────────────┘
                                       │
                                Internet Gateway
                                       │
      ┌────────────────────────────────┴────────────────────────────────┐
      │                       VPC 10.20.0.0/16                          │
      │                                                                 │
      │  ┌────────────────────┐   ┌────────────────────┐                │
      │  │ PUBLIC #1 (AZ a)   │   │ PUBLIC #2 (AZ b)   │                │
      │  │ 10.20.1.0/24       │   │ 10.20.2.0/24       │                │
      │  │ route 0/0 → IGW    │   │ route 0/0 → IGW    │                │
      │  │                    │   │                    │                │
      │  │ ┌────────────────┐ │   │ (empty — reserved  │                │
      │  │ │ Ubuntu EC2     │ │   │  for a future ALB, │                │
      │  │ │ + Elastic IP   │ │   │  which needs ≥ 2   │                │
      │  │ │                │ │   │  AZs)              │                │
      │  │ │ ┌────────────┐ │ │   └────────────────────┘                │
      │  │ │ │  Nginx     │ │ │                                         │
      │  │ │ │  :80 :443  │ │ │   (private subnet is commented out      │
      │  │ │ └─────┬──────┘ │ │    in modules/vpc — not used in this    │
      │  │ │       │        │ │    project)                             │
      │  │ │ reverse proxy  │ │                                         │
      │  │ │ /api/users/* → │ │                                         │
      │  │ │ /api/products/→│ │                                         │
      │  │ │ /api/orders/*→ │ │                                         │
      │  │ │                │ │                                         │
      │  │ │ ┌───┐┌───┐┌───┐│ │                                         │
      │  │ │ │usr││prd││ord││ │                                         │
      │  │ │ │3001││3002││3003│                                         │
      │  │ │ └───┘└───┘└─┬─┘│ │                                         │
      │  │ │ 127.0.0.1  │   │ │                                         │
      │  │ │  axios ←───┘   │ │                                         │
      │  │ └────────────────┘ │                                         │
      │  └────────────────────┘                                         │
      └─────────────────────────────────────────────────────────────────┘
```

### 1.2 Request flow

```
Client ─► https://api.example.com/api/orders/100
       ─► Nginx (:443)                                          [entry point]
       ─► strip /api/orders prefix → :3003/orders/100
       ─► order-service (PM2)
              ├── looks up order 100
              └── axios GET http://127.0.0.1:3002/products/1    [inter-service]
                     └── product-service returns product json
       ─► order-service merges order + product → 200
       ─► Nginx → Client
```

### 1.3 Failure semantics

| Event | User Service | Product Service | Order Service /health | `/api/orders/100` |
|---|---|---|---|---|
| All up | UP | UP | 200 UP | 200 order + product |
| Product killed | UP | ✗ | **200 UP** | **503 "Product service unavailable"** |
| `kill -9 <user-pid>` | **auto-restart <2s** (new PID) | UP | 200 UP | 200 (product still up) |
| EC2 reboot | comes back via PM2 systemd unit | same | same | same |

`/health` on any service **never** calls a dependency — that's why Order's
`/health` stays UP when Product is dead. Load balancers can trust it.

---

## 2. What's in this repo

```
microservices-nginx-pm2/
├── README.md                    ← you are here
├── DEPLOY_CHECKLIST.md          ← one-page recipe, task item → verify command
├── package.json                 ← root npm scripts (install:all etc.)
├── ecosystem.config.js          ← PM2 config for all 3 services
│
├── services/
│   ├── user-service/            ← Express :3001, in-memory users
│   ├── product-service/         ← Express :3002, in-memory products
│   └── order-service/           ← Express :3003, calls product-service via axios
│
├── deploy/
│   ├── nginx/
│   │   ├── microservices.conf   ← Nginx site config (reverse proxy /api/*)
│   │   └── README.md
│   └── scripts/
│       ├── upload-app.sh        ← rsync app to EC2 + reload nginx + pm2 start
│       └── enable-https.sh      ← certbot --nginx wrapper (bonus)
│
└── terraform-scripts/
    ├── main.tf                  ← module composition
    ├── variables.tf             ← root inputs
    ├── outputs.tf               ← EIP, ssh command, curl URLs, etc.
    ├── deploy.sh                ← interactive/dry-run/auto-approve driver
    ├── Makefile                 ← make plan | apply | ssh | destroy | ...
    ├── environments/
    │   ├── dev.tfvars           ← t3.micro, NAT off
    │   └── prod.tfvars          ← t3.small, NAT on
    ├── scripts/
    │   ├── ssh.sh               ← shortcut to ssh into the deployed box
    │   ├── refresh-aws-session.sh
    │   └── lib/helpers.sh       ← shared bash logging
    └── modules/
        ├── vpc/                 ← VPC + IGW + public + private subnet + optional NAT
        ├── security-group/      ← app-sg (public) + internal-sg (private)
        ├── key-pair/            ← RSA 4096, writes keys/*.pem (chmod 0400)
        └── ec2/                 ← Ubuntu 24.04 + user_data.sh (nginx+node+pm2)
```

---

## 3. Prerequisites

On your **workstation**:

| Tool | Version | Install |
|---|---|---|
| Node.js | 20 LTS | `nvm install 20` |
| npm | ≥10 | (ships with Node) |
| PM2 | latest | `npm install -g pm2` |
| Terraform | ≥1.5 | `brew install terraform` or apt/HashiCorp repo |
| AWS CLI v2 | latest | see AWS docs |
| jq, rsync, ssh, curl, dig | any recent | `sudo apt install jq rsync openssh-client curl dnsutils` |

An AWS account with:
- an IAM identity that can create VPC/EC2/EIP/IGW/SG/KeyPair
- an **SSO profile** named `aws-dharmendra` (or set `AWS_PROFILE`/`TF_VAR_aws_profile`)
- ~$10/month of budget for a `t3.micro` + EIP

For the HTTPS bonus, a **real domain** you control (e.g. `api.example.com`)
whose DNS you can edit to point at the Elastic IP.

---

## 4. Quick start (5-minute local run)

Run the whole microservice stack **on your own machine** — no AWS required —
to see it work end-to-end:

```bash
git clone <this-repo>
cd microservices-nginx-pm2

# 1. Install all three services' deps
npm run install:all

# 2. Start under PM2 (fork mode initially)
pm2 start ecosystem.config.js
pm2 list

# 3. Smoke test
curl http://127.0.0.1:3001/health
curl http://127.0.0.1:3002/health
curl http://127.0.0.1:3003/health
curl http://127.0.0.1:3003/orders/100     # calls product-service internally

# 4. Watch it crash-recover
pm2 pid user-service                       # remember the PID
kill -9 $(pm2 pid user-service)
sleep 3
pm2 list                                   # restart counter went 0 → 1, new PID

# 5. Cluster mode + zero-downtime reload demo
pm2 delete user-service
pm2 start ecosystem.config.js --only user-service   # comes back with 2 workers
# in one terminal: while true; do curl -s http://127.0.0.1:3001/health >/dev/null && echo OK; done
# in another:      pm2 reload user-service           # zero 5xx during the reload

# 6. Tear it down
pm2 delete all
```

You now understand what will run on the EC2 instance. Ready to ship it there.

---

## 5. Full AWS deployment — step by step

### Step 5.1 — Configure AWS access

```bash
aws configure sso --profile aws-dharmendra    # or reuse an existing profile
aws sso login --profile aws-dharmendra
aws sts get-caller-identity --profile aws-dharmendra
```

If your profile is not called `aws-dharmendra`, override it every time:

```bash
export AWS_PROFILE=<yours>
export TF_VAR_aws_profile=<yours>
```

### Step 5.2 — Set your SSH source IP

The security group only allows SSH from **your** public IP. Find it and put it
in `terraform-scripts/environments/dev.tfvars`:

```bash
curl -s https://checkip.amazonaws.com
# → e.g. 203.0.113.5

$EDITOR terraform-scripts/environments/dev.tfvars
# change:
#   ssh_cidr = "0.0.0.0/32"
# to:
#   ssh_cidr = "203.0.113.5/32"
```

⚠️ Never set this to `0.0.0.0/0`. The validation block will reject it, and
even if it didn't, doing so exposes port 22 to every bot on the internet.

### Step 5.3 — Provision infrastructure

```bash
cd terraform-scripts

make init                           # terraform init (downloads providers)
make plan     ENV=dev               # review what will be created (~25 resources)
make apply    ENV=dev               # interactive: type "apply dev" to confirm
```

`make apply` calls `./deploy.sh` which:

1. Refreshes the AWS SSO session (`refresh-aws-session.sh`)
2. `terraform init` / `validate` / `fmt -check`
3. `terraform plan -out=plans/dev_<ts>.tfplan`
4. Backs up `terraform.tfstate` to `state-backups/`
5. Prompts for `apply dev` confirmation
6. `terraform apply <plan>`
7. Writes a Markdown deployment report to `logs/deployment_report_dev_<ts>.md`

Non-interactive alternative:

```bash
make auto-deploy  ENV=dev           # skips the confirmation prompt
make dry-run      ENV=dev           # plan only, nothing applied
```

Capture the public IP so subsequent steps can use it:

```bash
EIP=$(terraform output -raw instance_public_ip)
echo "EIP=$EIP"
```

### Step 5.4 — Wait for the boot bootstrap

The instance runs `modules/ec2/user_data.sh` on first boot. It installs
Node.js LTS, PM2, and Nginx (~90 seconds). Watch it live:

```bash
make ssh CMD='sudo tail -f /var/log/user-data.log'
# Ctrl-C when you see: ########## user_data complete ##########
```

At this point `curl http://$EIP/` returns `bootstrap-ok - app not deployed yet` —
Nginx is serving a placeholder site while it waits for our real config.

### Step 5.5 — Deploy the app

```bash
make upload-app
```

This runs `deploy/scripts/upload-app.sh`, which:

1. Waits for sshd + user_data to be complete
2. `rsync`s the whole repo (minus `node_modules`, `terraform-scripts`, `.git`) to `/opt/app`
3. Copies `deploy/nginx/microservices.conf` to `/etc/nginx/sites-available/`, symlinks it, `nginx -t`, `systemctl reload nginx`
4. Runs `npm ci --omit=dev` in each service
5. Runs `pm2 start ecosystem.config.js` (or `pm2 reload …` if it's already up) → `pm2 save`
6. Smoke-tests all three `/api/*/health` endpoints via the public IP

It's **idempotent** — re-run it after every code change.

### Step 5.6 — Verify from your workstation

```bash
curl http://$EIP/api/users/health
curl http://$EIP/api/products/health
curl http://$EIP/api/orders/100    # order-service → product-service internal call
```

---

## 6. Verifying every requirement

The full verification playbook is in **[DEPLOY_CHECKLIST.md](./DEPLOY_CHECKLIST.md)** —
every requirement mapped to the exact command that proves it. Quick highlights:

| Requirement | Command |
|---|---|
| 3 services respond via Nginx | `curl http://$EIP/api/{users,products,orders}/health` |
| Managed by PM2 | `make ssh CMD='pm2 list'` |
| Crash recovery | `make ssh CMD='kill -9 $(pm2 pid user-service); sleep 3; pm2 list'` |
| Restart after reboot | `aws ec2 reboot-instances --instance-ids $(terraform output -raw instance_id); sleep 90; curl -sf http://$EIP/api/users/health` |
| Path routing | `curl -i http://$EIP/api/products/2` |
| Ports 3001-3003 NOT public | `curl --max-time 3 http://$EIP:3001/health` → must fail |
| Service isolation | `make ssh CMD='pm2 stop product-service; curl http://127.0.0.1:3003/health'` → still 200 |
| Inter-service | `curl http://$EIP/api/orders/100` → response has both `order` and `product` |
| Nginx + PM2 logs | `make ssh CMD='sudo tail /var/log/nginx/microservices_access.log; pm2 logs --lines 5'` |
| Cluster mode | `make ssh CMD='pm2 list | grep user-service'` → 2 workers |
| Zero-downtime reload | `while true; do curl -s -o /dev/null -w "%{http_code}\n" http://$EIP/api/users/health; done` in one shell, `pm2 reload user-service` in another — only 200s |

---

## 7. Enabling HTTPS (Let's Encrypt)

Requires a real domain with an A-record pointing at the EIP.

```bash
# 1. Configure DNS (in your registrar):
#    api.example.com   IN   A   <EIP>

# 2. Wait for DNS to propagate:
dig +short api.example.com
# → must return $EIP

# 3. Enable
./deploy/scripts/enable-https.sh api.example.com you@example.com
```

Under the hood the script:
1. Verifies DNS + HTTP preflight
2. `apt install certbot python3-certbot-nginx` on the instance
3. Rewrites `server_name _;` → `server_name api.example.com;`
4. `certbot --nginx --redirect --agree-tos -m … -d …` (auto-installs cert + 301 http→https)
5. `certbot renew --dry-run` to prove auto-renewal
6. Curls `https://<domain>/api/users/health` from your workstation

`certbot.timer` (systemd) then auto-renews twice daily.

---

## 8. Day-2 operations

### 8.1 SSH

```bash
make ssh                                # interactive shell
make ssh CMD='pm2 list'                 # one-shot command
make ssh CMD='tail -f /opt/app/logs/user-out.log'
```

### 8.2 Deploy new code

```bash
$EDITOR services/user-service/server.js
make upload-app                         # re-runs rsync + pm2 reload (zero downtime)
```

### 8.3 Add/remove PM2 processes

Edit `ecosystem.config.js`, then re-deploy:

```bash
make upload-app
# on the box:
# pm2 reload ecosystem.config.js --update-env
# pm2 save
```

### 8.4 Change infrastructure

Edit `terraform-scripts/environments/dev.tfvars` (or `variables.tf`), then:

```bash
cd terraform-scripts
make plan  ENV=dev
make apply ENV=dev
```

Editing `modules/ec2/user_data.sh` forces the instance to be **replaced**
(that's `user_data_replace_on_change = true`). This is safe — the EIP re-attaches
to the new instance and `make upload-app` restores the app.

### 8.5 View logs

| Log | Location |
|---|---|
| PM2 stdout/stderr | `/opt/app/logs/{user,product,order}-{out,error}.log` |
| Nginx access | `/var/log/nginx/microservices_access.log` |
| Nginx error | `/var/log/nginx/microservices_error.log` |
| Cloud-init user_data | `/var/log/user-data.log` (only on first boot) |
| Terraform run logs | `terraform-scripts/logs/deploy_<env>_<ts>.log` |

Tail from your workstation:

```bash
make ssh CMD='sudo tail -f /var/log/nginx/microservices_access.log'
make ssh CMD='pm2 logs --lines 100'
```

---

## 9. Troubleshooting

### 502 Bad Gateway from Nginx

```bash
make ssh CMD='pm2 list && sudo tail -30 /var/log/nginx/microservices_error.log'
```

Root causes:
- A PM2 process is `stopped` or `errored` — `pm2 restart <name>`
- Service isn't binding to 127.0.0.1 — `ss -lntp | grep :300`
- Wrong port in `ecosystem.config.js`

### 404 on `/api/users/health`

The `proxy_pass` trailing slash matters:

```nginx
location /api/users/ {
    proxy_pass http://user_backend/;   # ← trailing / strips the prefix
}
```

Without the trailing slash, the upstream sees `/api/users/health` instead of `/health`.

### `terraform apply` fails: "AuthFailure"

```bash
make refresh                            # aws sso login --profile aws-dharmendra
```

Or explicitly:

```bash
aws sso login --profile aws-dharmendra
```

### `ssh: connect to host …: Connection timed out`

Your public IP changed (very common on home ISPs). Update `ssh_cidr`:

```bash
curl -s https://checkip.amazonaws.com
$EDITOR terraform-scripts/environments/dev.tfvars   # update ssh_cidr
cd terraform-scripts && make apply ENV=dev          # updates the SG rule
```

### `upload-app.sh` hangs on "Waiting for sshd"

`user_data.sh` is still running. Check:

```bash
KEY=$(cd terraform-scripts && terraform output -raw private_key_path)
IP=$(cd terraform-scripts && terraform output -raw instance_public_ip)
ssh -i $KEY ubuntu@$IP 'sudo tail -f /var/log/user-data.log'
```

### PM2 doesn't come back after reboot

Verify the systemd unit was registered by `user_data.sh`:

```bash
make ssh CMD='systemctl status pm2-ubuntu'
make ssh CMD='journalctl -u pm2-ubuntu --since -1h'
```

If missing, re-run inside the box:

```bash
make ssh
sudo env PATH=$PATH:/usr/bin \
  pm2 startup systemd -u ubuntu --hp /home/ubuntu | tail -1 | sudo bash
pm2 save
```

### certbot: "unauthorized" on HTTP-01 challenge

DNS hasn't fully propagated. Wait 5-10 minutes:

```bash
dig +short api.example.com          # must return the EIP everywhere
curl -I http://api.example.com/     # must return 200 from your Nginx
```

Then re-run `enable-https.sh`.

---

## 10. Design decisions & interview notes

**Why bind services to `127.0.0.1` instead of `0.0.0.0`?**
Defense in depth. Even if Nginx, the security group, and IPtables were all
misconfigured, the OS kernel refuses connections from any non-loopback
interface. Only Nginx (same host) can reach the port.

**Why one Nginx per host, not a separate ALB per service?**
Cost + simplicity for a project this size. In production with real traffic
you'd put an ALB in the public subnet and move the EC2 into the private
subnet + ASG.

**Why does the `/health` endpoint not check dependencies?**
So a Product outage doesn't get Order labelled unhealthy and killed by an
orchestrator. Dependency failure surfaces on the specific endpoint that
needs it (`/orders/:id` → 503), not on `/health`.

**Why PM2 fork vs cluster?**
Fork = one process per app, simplest. Cluster = N workers on the same port,
required for `pm2 reload` (zero-downtime). We keep Product/Order in fork
and User in cluster (2 workers) to demonstrate both.

**Why is the EC2 in the public subnet, not the private one?**
Nginx is the internet entry point. Putting it behind an ALB in the public
subnet just moves the internet-facing surface — it doesn't reduce it. The
private subnet is provisioned and wired for future services (DB, worker)
that must never be reachable from outside.

**Why is `user_data_replace_on_change = true`?**
So a change to the bootstrap script is guaranteed to be re-executed. Editing
it and running `apply` will replace the instance; the EIP re-attaches; the
next `make upload-app` restores the app. A slightly heavy hammer, but the
cost of "user_data drift" (running instance no longer matches config) is
much worse in practice.

**Why `lifecycle.ignore_changes = [ami]`?**
Canonical publishes a new Ubuntu image roughly weekly. Without this, every
`terraform plan` proposes to replace your running instance. Bump the AMI
deliberately (delete the ignore, plan, apply, re-add ignore).

---

## 11. Cost

Rough monthly cost in `ap-south-1` for the default `dev` environment:

| Resource | Cost |
|---|---|
| t3.micro (720h × $0.0104) | ~$7.50 |
| Elastic IP (in use, attached) | $0.00 |
| Elastic IP (idle, not attached) | ~$3.60 |
| 12 GB gp3 root volume | ~$1.10 |
| Data transfer out (first 100 GB) | free |
| VPC, IGW, subnets, route tables, SGs | free |
| **Total (running)** | **~$8-10/month** |

No NAT gateway is provisioned in this layout — the private subnet has no
default route, so nothing there can reach the internet outbound. Add a NAT
gateway (~$32/mo) or S3/ECR VPC endpoints the day you put something in the
private subnet that needs it.

To pause billing: `pm2 stop all` doesn't help — the instance still runs. Use
`aws ec2 stop-instances --instance-ids …` (EIP charges begin only while
detached, so leave it attached).

---

## 12. Teardown

```bash
cd terraform-scripts
make destroy ENV=dev
# type: destroy dev
```

Removes: EIP, instance, key pair (AWS + local `.pem`), all SGs, both subnets,
IGW, and VPC. `logs/`, `plans/`, `state-backups/` remain locally — sweep
with `make clean`.

---

## References

- [DEPLOY_CHECKLIST.md](./DEPLOY_CHECKLIST.md) — one-page verify recipe
- [terraform-scripts/README.md](./terraform-scripts/README.md) — infra deep-dive
- [deploy/nginx/README.md](./deploy/nginx/README.md) — Nginx notes
- [PM2 docs](https://pm2.keymetrics.io/docs/usage/quick-start/) — ecosystem + cluster
- [NodeSource Node.js repo](https://github.com/nodesource/distributions) — how Node gets installed on the EC2
- [Let's Encrypt / certbot](https://certbot.eff.org/) — HTTPS
