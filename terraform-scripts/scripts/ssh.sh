#!/usr/bin/env bash
################################################################################
# scripts/ssh.sh
#
# Convenience wrapper: pulls instance_public_ip and private_key_path from
# terraform output and opens an SSH session as ubuntu.
#
# Extra args are forwarded to ssh, so this works as an ad-hoc remote runner:
#
#   ./scripts/ssh.sh                          # interactive shell
#   ./scripts/ssh.sh "pm2 list"               # one-shot command
#   ./scripts/ssh.sh "tail -f /var/log/user-data.log"
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/helpers.sh
source "${SCRIPT_DIR}/lib/helpers.sh"

require_cmd terraform ssh

cd "${TF_DIR}"

IP="$(terraform output -raw instance_public_ip 2>/dev/null || true)"
KEY="$(terraform output -raw private_key_path 2>/dev/null || true)"

if [ -z "$IP" ] || [ -z "$KEY" ]; then
  log_error "Could not read instance_public_ip / private_key_path from terraform output."
  log_error "Have you run 'terraform apply'?"
  exit 1
fi

if [ ! -f "$KEY" ]; then
  log_error "Private key not found at: $KEY"
  exit 1
fi

# ssh refuses group/other-readable keys - enforce 0600 defensively in case
# the file got copied or its mode drifted.
chmod 600 "$KEY" 2>/dev/null || true

log_info "Connecting to ubuntu@${IP}"
exec ssh -i "$KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile="${TF_DIR}/.ssh_known_hosts" \
  "ubuntu@${IP}" "$@"
