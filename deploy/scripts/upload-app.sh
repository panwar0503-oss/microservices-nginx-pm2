#!/usr/bin/env bash
################################################################################
# deploy/scripts/upload-app.sh
#
# Uploads the application to the running EC2 instance and (re)starts it
# under PM2. Idempotent - safe to re-run after every code change.
#
# Steps:
#   1. Read instance public IP and .pem path from terraform outputs
#   2. Wait until sshd is reachable and user_data has finished
#   3. rsync services/ + ecosystem.config.js + package.json to /opt/app
#   4. Copy deploy/nginx/microservices.conf into /etc/nginx/ and reload
#   5. npm install per service (using the ubuntu user's node)
#   6. pm2 start ecosystem.config.js  (or reload if already running)
#   7. pm2 save
#   8. Smoke-test the three health endpoints via Nginx (:80/api/.../health)
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform-scripts"

# shellcheck source=../../terraform-scripts/scripts/lib/helpers.sh
source "${TF_DIR}/scripts/lib/helpers.sh"

require_cmd terraform ssh rsync curl

################################################################################
# 1. Read terraform outputs
################################################################################

cd "${TF_DIR}"

IP="$(terraform output -raw instance_public_ip 2>/dev/null || true)"
KEY="$(terraform output -raw private_key_path   2>/dev/null || true)"

if [ -z "${IP}" ] || [ -z "${KEY}" ]; then
  log_error "terraform outputs missing. Run 'make apply' first."
  exit 1
fi

SSH_OPTS=(
  -i "${KEY}"
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="${TF_DIR}/.ssh_known_hosts"
  -o ConnectTimeout=10
)
REMOTE="ubuntu@${IP}"

banner "Uploading app to ${REMOTE}"

################################################################################
# 2. Wait for sshd + user_data completion
################################################################################

log_info "Waiting for sshd on ${IP} ..."
for i in $(seq 1 60); do
  if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "${REMOTE}" true 2>/dev/null; then
    log_success "sshd reachable"
    break
  fi
  sleep 5
  if [ "$i" -eq 60 ]; then
    log_error "sshd never became reachable"
    exit 1
  fi
done

log_info "Waiting for user_data to finish (pm2 must be installed) ..."
for i in $(seq 1 60); do
  if ssh "${SSH_OPTS[@]}" "${REMOTE}" 'command -v pm2 >/dev/null 2>&1 && command -v node >/dev/null 2>&1'; then
    log_success "node + pm2 present"
    break
  fi
  sleep 5
  if [ "$i" -eq 60 ]; then
    log_error "user_data did not finish in time. Check: sudo tail /var/log/user-data.log"
    exit 1
  fi
done

################################################################################
# 3. Rsync application code
################################################################################

banner "Rsync app -> /opt/app"

# Include only what the server needs; exclude local dev cruft.
rsync -avz --delete \
  -e "ssh ${SSH_OPTS[*]}" \
  --exclude 'node_modules' \
  --exclude 'logs' \
  --exclude '.git' \
  --exclude 'terraform-scripts' \
  --exclude 'deploy' \
  --exclude '.claude' \
  --exclude 'MEMORY.md' \
  "${REPO_ROOT}/" "${REMOTE}:/opt/app/"

log_success "rsync complete"

################################################################################
# 4. Deploy the Nginx site config
################################################################################

banner "Installing Nginx reverse-proxy config"

scp "${SSH_OPTS[@]}" \
  "${REPO_ROOT}/deploy/nginx/microservices.conf" \
  "${REMOTE}:/tmp/microservices.conf"

ssh "${SSH_OPTS[@]}" "${REMOTE}" bash -s <<'REMOTE_NGINX'
set -euo pipefail
sudo install -o root -g root -m 0644 /tmp/microservices.conf /etc/nginx/sites-available/microservices
sudo ln -sf /etc/nginx/sites-available/microservices /etc/nginx/sites-enabled/microservices
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
echo "nginx reloaded ok"
REMOTE_NGINX

log_success "nginx config in place"

################################################################################
# 5. + 6. + 7. Install deps, (re)start under PM2, save
################################################################################

banner "npm install + pm2 (re)start"

ssh "${SSH_OPTS[@]}" "${REMOTE}" bash -s <<'REMOTE_PM2'
set -euo pipefail
cd /opt/app

# Install each service's deps (production only)
for svc in services/user-service services/product-service services/order-service; do
  echo "-- npm install: $svc --"
  ( cd "$svc" && npm ci --omit=dev --no-audit --no-fund 2>/dev/null \
                 || npm install --omit=dev --no-audit --no-fund )
done

# Reload if the ecosystem already runs, else start it.
if pm2 describe user-service >/dev/null 2>&1; then
  echo "-- pm2 reload ecosystem.config.js --"
  pm2 reload ecosystem.config.js --update-env
else
  echo "-- pm2 start ecosystem.config.js --"
  pm2 start ecosystem.config.js
fi

pm2 save
pm2 list
REMOTE_PM2

log_success "pm2 up"

################################################################################
# 8. Smoke tests through Nginx
################################################################################

banner "Smoke tests via http://${IP}/api/*/health"

fail=0
for svc in users products orders; do
  code="$(curl -s -o /tmp/_last_body -w '%{http_code}' "http://${IP}/api/${svc}/health" || echo '000')"
  body="$(cat /tmp/_last_body 2>/dev/null || echo '')"
  if [ "${code}" = "200" ]; then
    log_success "/api/${svc}/health -> 200  ${body}"
  else
    log_error   "/api/${svc}/health -> ${code}  ${body}"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  log_error "One or more smoke tests failed."
  log_info  "Check logs: ssh -i ${KEY} ${REMOTE} 'pm2 logs --lines 50'"
  exit 1
fi

banner "Deployment complete"
log_success "URL:  http://${IP}/"
