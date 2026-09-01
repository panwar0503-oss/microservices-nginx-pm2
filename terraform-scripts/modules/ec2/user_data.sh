#!/bin/bash
##############################################################################
# EC2 User Data - microservices-nginx-pm2 bootstrap
#
# Runs once on first boot as root. Installs the runtime dependencies for
# the app (Node.js LTS, PM2, Nginx) and drops in a placeholder Nginx site
# that returns 200 "bootstrap-ok". The real reverse-proxy config is put in
# place later by scripts/upload-app.sh, which also boots the app under PM2.
#
# Terraform template vars used below (via templatefile):
#   ${node_version}   -> Node major version, e.g. "20"
#   ${aws_region}     -> region string, only used in logs
#   ${project_name}   -> project name for logs
#   ${environment}    -> environment for logs
#
# Bash variables inside this file must be escaped as $${VAR} so Terraform
# does not try to interpolate them.
##############################################################################

set -euo pipefail

# Log every command's stdout + stderr to /var/log/user-data.log for later
# inspection: sudo tail -f /var/log/user-data.log
exec > >(tee /var/log/user-data.log) 2>&1

log()  { echo "[user-data] $$(date -u +%FT%TZ) $$*"; }
step() { echo; echo "########## $$* ##########"; }

step "Starting user_data for ${project_name}-${environment} in ${aws_region}"
log  "Node major: ${node_version}"

##############################################################################
# 1. System update + base packages
##############################################################################
step "Updating apt and installing base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  curl wget git unzip ca-certificates gnupg \
  net-tools lsof htop jq

##############################################################################
# 2. Node.js LTS from NodeSource
#
# We install system-wide (not via nvm) because PM2 runs under systemd as the
# ubuntu user, and systemd needs the interpreter to exist at a stable path
# (/usr/bin/node). NodeSource is the standard maintained Debian/Ubuntu repo.
##############################################################################
step "Installing Node.js ${node_version}.x from NodeSource"
curl -fsSL "https://deb.nodesource.com/setup_${node_version}.x" | bash -
apt-get install -y nodejs
log "node: $$(node -v),  npm: $$(npm -v)"

##############################################################################
# 3. PM2 (globally)
##############################################################################
step "Installing PM2 globally"
npm install -g pm2@latest
log "pm2: $$(pm2 -v)"

##############################################################################
# 4. Nginx
##############################################################################
step "Installing Nginx"
apt-get install -y nginx
systemctl enable nginx

# Drop the default catch-all so it does not race with our future
# microservices site once upload-app.sh enables it.
rm -f /etc/nginx/sites-enabled/default

# Placeholder site so `curl http://<eip>/` returns something meaningful
# BEFORE the app is deployed. upload-app.sh overwrites this file.
cat >/etc/nginx/sites-available/microservices <<'NGINX_PLACEHOLDER'
server {
    listen      80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location = / {
        add_header Content-Type text/plain;
        return 200 "bootstrap-ok - app not deployed yet\n";
    }
}
NGINX_PLACEHOLDER

ln -sf /etc/nginx/sites-available/microservices /etc/nginx/sites-enabled/microservices
nginx -t
systemctl reload nginx

##############################################################################
# 5. Application layout owned by ubuntu
#
# App code will land in /opt/app (uploaded by scripts/upload-app.sh).
# Logs live in /opt/app/logs (PM2 writes them there per ecosystem.config.js).
##############################################################################
step "Preparing /opt/app for the ubuntu user"
install -d -o ubuntu -g ubuntu -m 0755 /opt/app
install -d -o ubuntu -g ubuntu -m 0755 /opt/app/logs

##############################################################################
# 6. PM2 startup wiring (as ubuntu, not root)
#
# `pm2 startup` prints a command that we then execute to register PM2 as a
# systemd unit that runs `pm2 resurrect` on boot. Doing it now (with an
# empty dump) is safe - the first `pm2 save` on the deploy will populate
# the dump, and subsequent reboots will bring the whole app back.
##############################################################################
step "Configuring PM2 systemd startup"
sudo -u ubuntu env PATH=$$PATH:/usr/bin \
  pm2 startup systemd -u ubuntu --hp /home/ubuntu | \
  tail -n 1 | bash || log "pm2 startup command not emitted - already installed?"

# Give the ubuntu user a valid but empty PM2 dump so `pm2 resurrect` at
# next boot does not error before we have deployed anything.
sudo -u ubuntu pm2 save --force || true

step "user_data complete"
log "Ready for scripts/upload-app.sh from your workstation."
