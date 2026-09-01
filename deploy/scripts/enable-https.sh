#!/usr/bin/env bash
################################################################################
# deploy/scripts/enable-https.sh
#
# Enables HTTPS on the deployed instance using Let's Encrypt + certbot.
# Idempotent: safe to re-run (certbot detects an existing cert and no-ops).
#
#   Usage:
#     ./deploy/scripts/enable-https.sh <domain> <email>
#
#   Example:
#     ./deploy/scripts/enable-https.sh api.example.com you@example.com
#
# Prerequisites (fail fast if any missing):
#   1. `terraform apply` has run - we read the EIP from terraform output.
#   2. `make upload-app` has run - Nginx is up with the real microservices site.
#   3. DNS: an A record for <domain> points to the Elastic IP. Verified below.
#
# What it does on the EC2 host:
#   * Installs certbot + the Nginx plugin (apt) if not already present
#   * Rewrites Nginx server_name to <domain>
#   * Runs `certbot --nginx -d <domain>` which:
#       - obtains a certificate via HTTP-01 challenge
#       - patches the Nginx config in-place with the TLS server block
#       - adds a permanent 301 redirect 80 -> 443
#   * Verifies auto-renewal with `certbot renew --dry-run`
#   * certbot installs a systemd timer (certbot.timer) that renews twice daily
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform-scripts"

# shellcheck source=../../terraform-scripts/scripts/lib/helpers.sh
source "${TF_DIR}/scripts/lib/helpers.sh"

################################################################################
# Args
################################################################################

if [ "$#" -ne 2 ]; then
  log_error "Usage: $0 <domain> <email>"
  log_error "Example: $0 api.example.com you@example.com"
  exit 2
fi

DOMAIN="$1"
EMAIL="$2"

case "$DOMAIN" in
  *.*) : ;;
  *)   log_error "Domain '$DOMAIN' doesn't look like a hostname"; exit 2 ;;
esac
case "$EMAIL" in
  *@*.*) : ;;
  *)     log_error "Email '$EMAIL' doesn't look like an email address"; exit 2 ;;
esac

require_cmd terraform ssh dig curl

################################################################################
# Read terraform outputs
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

banner "Enabling HTTPS for ${DOMAIN} on ${IP}"

################################################################################
# Preflight: DNS must resolve to the EIP (otherwise HTTP-01 fails)
################################################################################

log_info "Resolving A record for ${DOMAIN} ..."
DNS_IP="$(dig +short A "${DOMAIN}" | tail -n1)"

if [ -z "${DNS_IP}" ]; then
  log_error "No A record for ${DOMAIN}. Add: ${DOMAIN}. IN A ${IP}"
  exit 1
fi

if [ "${DNS_IP}" != "${IP}" ]; then
  log_error "DNS mismatch: ${DOMAIN} -> ${DNS_IP}, but Elastic IP is ${IP}"
  log_error "Update your DNS to point at ${IP} and wait for propagation, then re-run."
  exit 1
fi
log_success "DNS ok: ${DOMAIN} -> ${IP}"

# HTTP must already work before certbot can complete the HTTP-01 challenge.
log_info "Preflight: http://${DOMAIN}/ ..."
if ! curl -fsS --max-time 5 "http://${DOMAIN}/" >/dev/null; then
  log_error "http://${DOMAIN}/ did not respond. Is Nginx up? (make upload-app)"
  exit 1
fi
log_success "HTTP preflight ok"

################################################################################
# Remote work: install certbot, patch server_name, run certbot, dry-run renew
################################################################################

banner "Running certbot on ${REMOTE}"

ssh "${SSH_OPTS[@]}" "${REMOTE}" \
  DOMAIN="${DOMAIN}" EMAIL="${EMAIL}" bash -s <<'REMOTE_HTTPS'
set -euo pipefail

echo "-- installing certbot + nginx plugin (idempotent) --"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx

CONF=/etc/nginx/sites-available/microservices
if [ -f "$CONF" ]; then
  echo "-- pointing server_name at ${DOMAIN} --"
  # Replace the placeholder `server_name _;` with the real domain.
  # (certbot needs a real server_name to attach the TLS block correctly.)
  sudo sed -i "s|server_name .*;|server_name ${DOMAIN};|" "$CONF"
  sudo nginx -t
  sudo systemctl reload nginx
else
  echo "!! $CONF not found; did you run upload-app.sh?" >&2
  exit 1
fi

echo "-- requesting certificate via HTTP-01 --"
# --nginx           : patch nginx config to serve the cert
# --redirect        : install permanent 80 -> 443 redirect
# --non-interactive : no prompts
# --agree-tos       : agree to Let's Encrypt subscriber agreement
# -m EMAIL          : contact for renewal warnings
sudo certbot --nginx \
  --non-interactive --agree-tos --redirect \
  -m "${EMAIL}" \
  -d "${DOMAIN}"

echo "-- verifying auto-renewal --"
sudo certbot renew --dry-run

echo "-- systemd renew timer status --"
systemctl list-timers certbot.timer --no-pager || true
REMOTE_HTTPS

banner "Verifying HTTPS from your workstation"

if curl -fsS --max-time 10 "https://${DOMAIN}/api/users/health"; then
  echo
  log_success "HTTPS is live"
else
  log_error "HTTPS check failed. Debug on the box:"
  log_info  "  ssh -i ${KEY} ${REMOTE} 'sudo tail -50 /var/log/letsencrypt/letsencrypt.log'"
  exit 1
fi

log_info "http://${DOMAIN}/ now redirects to https://${DOMAIN}/"
log_info "certbot.timer will auto-renew ~30 days before expiry (twice-daily check)."
