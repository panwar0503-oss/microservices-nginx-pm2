# terraform-scripts — AWS infrastructure for `microservices-nginx-pm2`

Provisions a VPC with **one public and one private subnet**, an Internet Gateway,
security groups, an SSH key pair, and a single Ubuntu 24.04 EC2 instance
bootstrapped with **Nginx + Node.js + PM2** via `user_data`. The three Node
microservices are uploaded post-boot with `deploy/scripts/upload-app.sh` and
run under PM2 behind Nginx.

## Architecture

```
                              Internet
                                 │
                    ┌────────────┴────────────┐
                    │      Security Group     │
                    │      22 (your IP)       │
                    │      80, 443 (world)    │
                    └────────────┬────────────┘
                                 │
                          Internet Gateway
                                 │
   ┌─────────────────────────────┴──────────────────────────────┐
   │                     VPC 10.20.0.0/16                        │
   │                                                             │
   │  ┌──────────────────────┐   ┌──────────────────────┐        │
   │  │  PUBLIC #1  (AZ a)   │   │  PUBLIC #2  (AZ b)   │        │
   │  │  10.20.1.0/24        │   │  10.20.2.0/24        │        │
   │  │  route 0/0 → IGW     │   │  route 0/0 → IGW     │        │
   │  │                      │   │                      │        │
   │  │  ┌────────────────┐  │   │  (empty — reserved   │        │
   │  │  │  EC2 + EIP     │  │   │   for future ALB;    │        │
   │  │  │  Nginx :80,443 │  │   │   ALB requires ≥ 2   │        │
   │  │  │  PM2 fork/cl   │  │   │   AZs)               │        │
   │  │  │  Node :3001-3  │  │   │                      │        │
   │  │  │  (127.0.0.1)   │  │   └──────────────────────┘        │
   │  │  └────────────────┘  │                                   │
   │  └──────────────────────┘                                   │
   │                                                             │
   │  (private subnet is COMMENTED OUT in modules/vpc — this     │
   │   project has no private-tier workloads yet)                │
   └─────────────────────────────────────────────────────────────┘
```

Ports **3001 / 3002 / 3003** are **never** in the security group — the app
services bind to `127.0.0.1` and only Nginx (same host) reaches them.

## Layout

```
terraform-scripts/
├── main.tf                    # composes the modules below
├── variables.tf               # root inputs
├── outputs.tf
├── terraform.tfvars.example
├── deploy.sh                  # ./deploy.sh [--dry-run|--auto-approve]
├── Makefile                   # make plan | apply | destroy | ssh | ...
├── environments/
│   ├── dev.tfvars             # t3.micro, 2 public + 1 private, no NAT
│   └── prod.tfvars            # t3.small, 2 public + 1 private, no NAT
├── scripts/
│   ├── lib/helpers.sh
│   ├── refresh-aws-session.sh
│   └── ssh.sh
└── modules/
    ├── vpc/                   # VPC + IGW + 2 public subnets (multi-AZ)
    ├── security-group/        # app-sg (public)
    ├── key-pair/              # generates RSA locally, registers in AWS
    └── ec2/                   # instance + EIP + user_data.sh
```

## Prerequisites

- Terraform ≥ 1.5
- AWS CLI v2 with an SSO profile (default: `aws-dharmendra`)
- `jq`, `rsync`, `ssh`, `curl`

## Quick start

```bash
cd terraform-scripts

# 1. Set your SSH source IP in the env tfvars.
curl -s https://checkip.amazonaws.com                     # → x.x.x.x
$EDITOR environments/dev.tfvars                           # ssh_cidr = ".../32"

# 2. Initialise + plan + apply (interactive)
make init
make plan ENV=dev
make apply ENV=dev

# 3. Deploy the app onto the instance
make upload-app

# 4. Verify
curl "http://$(terraform output -raw instance_public_ip)/api/users/health"
```

## The deploy.sh workflow

```bash
./deploy.sh                    # interactive: plan -> confirm ('apply dev') -> apply
./deploy.sh --dry-run          # plan only
./deploy.sh --auto-approve     # non-interactive apply
ENV=prod ./deploy.sh           # target prod tfvars
```

Every run writes: `logs/deploy_<env>_<ts>.log`, `plans/<env>_<ts>.tfplan`,
`state-backups/terraform.tfstate.<ts>`, `logs/deployment_report_<env>_<ts>.md`.

## Common Make targets

```
make help              # menu
make init              # terraform init
make fmt / fmt-check
make validate
make plan     ENV=dev
make apply    ENV=dev  # interactive via deploy.sh
make dry-run  ENV=dev
make destroy  ENV=dev  # asks you to type 'destroy dev' to confirm
make ssh               # ssh -i keys/... ubuntu@<eip>
make upload-app        # rsync + pm2 (re)start
make outputs
make refresh           # refresh AWS SSO session
```

## What runs at boot (user_data.sh)

1. `apt update && apt upgrade`
2. Installs **Node.js LTS** from NodeSource (system-wide `/usr/bin/node`)
3. Installs **PM2** globally
4. Installs **Nginx**, disables the default site, drops in a placeholder
5. Creates `/opt/app` (owned by `ubuntu`)
6. Registers **PM2 as a systemd unit** so services resurrect on reboot

The full log is at `/var/log/user-data.log` on the instance.

## What upload-app.sh does after boot

Idempotent — safe to re-run after every code change:

1. Waits for sshd + user_data completion
2. `rsync` the repo (minus `node_modules`, `terraform-scripts`, `.git`) to `/opt/app`
3. Copies `deploy/nginx/microservices.conf` into `/etc/nginx/`, runs `nginx -t`, reloads
4. `npm ci --omit=dev` in each service
5. `pm2 start` (or `reload` if already up) → `pm2 save`
6. Smoke-tests all three `/api/*/health` endpoints via public IP

## Destroy

```bash
make destroy ENV=dev
# Type: destroy dev
```

Removes EIP, instance, key pair (AWS + local `.pem`), security groups, subnets,
IGW and VPC. Local `logs/`, `plans/`, and `state-backups/` remain — run
`make clean` to sweep them.

## Notes

- **Region** defaults to `ap-south-1`. Change in `environments/<env>.tfvars`.
- **Profile** defaults to `aws-dharmendra`. Override with `AWS_PROFILE=... make apply`.
- **AMI drift is intentionally ignored** (`lifecycle.ignore_changes = [ami]`).
- **State is local** by default. For team use, add an S3 backend block.
- **Cost check:** in `ap-south-1`, one `t3.micro` + one EIP (in use) + 12 GB gp3
  runs at roughly USD $8–10/month. No NAT gateway is provisioned — the private
  subnet has no default route. Add a NAT (~$32/mo) or S3/ECR VPC endpoints the
  day you put something in that subnet that needs internet outbound.
