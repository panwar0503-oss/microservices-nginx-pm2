#!/usr/bin/env bash
################################################################################
# deploy.sh - End-to-end Terraform deploy for microservices-nginx-pm2
#
# Modes:
#   ./deploy.sh                # interactive (plan -> confirm -> apply)
#   ./deploy.sh --dry-run      # plan only, then stop
#   ./deploy.sh --auto-approve # apply without confirmation prompt
#
# Environment knobs:
#   ENV=dev|prod               # selects environments/<env>.tfvars (default dev)
#   AWS_PROFILE=<name>         # provider profile (default aws-dharmendra)
#
# Every run writes:
#   plans/<env>_<ts>.tfplan
#   state-backups/terraform.tfstate.<ts>
#   logs/deploy_<env>_<ts>.log
#   logs/deployment_report_<env>_<ts>.md
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# shellcheck source=scripts/lib/helpers.sh
source "${SCRIPT_DIR}/scripts/lib/helpers.sh"

################################################################################
# Argument parsing
################################################################################

DRY_RUN=0
AUTO_APPROVE=0

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1        ;;
    --auto-approve) AUTO_APPROVE=1   ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      log_error "Unknown argument: $arg"
      exit 2
      ;;
  esac
done

################################################################################
# Config
################################################################################

: "${ENV:=dev}"
: "${AWS_PROFILE:=aws-dharmendra}"
export AWS_PROFILE

TS="$(ts)"
VAR_FILE="environments/${ENV}.tfvars"
PLAN_FILE="plans/${ENV}_${TS}.tfplan"
LOG_FILE="logs/deploy_${ENV}_${TS}.log"
REPORT_FILE="logs/deployment_report_${ENV}_${TS}.md"

mkdir -p plans logs state-backups

# Tee EVERYTHING that follows to the run log.
exec > >(tee -a "${LOG_FILE}") 2>&1

banner "microservices-nginx-pm2 deploy - env=${ENV} profile=${AWS_PROFILE}"

log_info "timestamp:  ${TS}"
log_info "var-file:   ${VAR_FILE}"
log_info "plan-file:  ${PLAN_FILE}"
log_info "log-file:   ${LOG_FILE}"

if [ ! -f "${VAR_FILE}" ]; then
  log_error "Var file not found: ${VAR_FILE}"
  log_error "Available: $(ls environments/ 2>/dev/null || echo '(none)')"
  exit 1
fi

################################################################################
# Prerequisites
################################################################################

banner "Checking prerequisites"

require_cmd terraform aws jq

log_info "terraform: $(terraform version | head -1)"
log_info "aws:       $(aws --version 2>&1)"

bash "${SCRIPT_DIR}/scripts/refresh-aws-session.sh"

################################################################################
# init / validate / fmt
################################################################################

banner "terraform init"
if [ ! -d ".terraform" ]; then
  terraform init -input=false
else
  terraform init -input=false -upgrade=false
fi
log_success "init complete"

banner "terraform validate"
terraform validate
log_success "validate passed"

banner "terraform fmt -check"
if ! terraform fmt -check -recursive .; then
  log_warning "Some files are not formatted. Run: make fmt"
fi

################################################################################
# plan
################################################################################

banner "terraform plan"
terraform plan \
  -input=false \
  -var-file="${VAR_FILE}" \
  -out="${PLAN_FILE}"

log_success "plan written: ${PLAN_FILE}"

if [ "${DRY_RUN}" -eq 1 ]; then
  banner "Dry-run finished - nothing applied"
  log_info "Inspect the plan with: terraform show ${PLAN_FILE}"
  exit 0
fi

################################################################################
# state backup (only meaningful with local state)
################################################################################

if [ -f terraform.tfstate ]; then
  BACKUP="state-backups/terraform.tfstate.${TS}"
  cp terraform.tfstate "${BACKUP}"
  log_success "state backup: ${BACKUP}"
fi

################################################################################
# confirm + apply
################################################################################

if [ "${AUTO_APPROVE}" -ne 1 ]; then
  echo
  log_warning "About to APPLY the plan above to env='${ENV}' (profile=${AWS_PROFILE})."
  read -rp "Type 'apply ${ENV}' to proceed: " confirm
  if [ "${confirm}" != "apply ${ENV}" ]; then
    log_error "Cancelled."
    exit 1
  fi
fi

banner "terraform apply"
terraform apply -input=false "${PLAN_FILE}"
log_success "apply complete"

################################################################################
# post-apply summary + report
################################################################################

banner "Outputs"
terraform output

PUBLIC_IP="$(terraform output -raw instance_public_ip 2>/dev/null || echo '?')"
KEY_PATH="$(terraform output -raw private_key_path 2>/dev/null || echo '?')"

{
  echo "# Deployment report"
  echo
  echo "- **Timestamp:** ${TS}"
  echo "- **Env:** ${ENV}"
  echo "- **AWS profile:** ${AWS_PROFILE}"
  echo "- **Plan:** \`${PLAN_FILE}\`"
  echo "- **Log:** \`${LOG_FILE}\`"
  echo
  echo "## Outputs"
  echo
  echo '```'
  terraform output
  echo '```'
  echo
  echo "## Next steps"
  echo
  echo '```bash'
  echo "# 1. Wait ~2 min for user_data to finish (installs nginx + node + pm2)"
  echo "ssh -i ${KEY_PATH} ubuntu@${PUBLIC_IP} 'sudo tail -n 20 /var/log/user-data.log'"
  echo
  echo "# 2. Upload the app + start under PM2"
  echo "bash ../deploy/scripts/upload-app.sh"
  echo
  echo "# 3. Smoke test"
  echo "curl http://${PUBLIC_IP}/api/users/health"
  echo "curl http://${PUBLIC_IP}/api/products/health"
  echo "curl http://${PUBLIC_IP}/api/orders/health"
  echo '```'
} > "${REPORT_FILE}"

log_success "report: ${REPORT_FILE}"

banner "Done"
log_success "Public IP:  ${PUBLIC_IP}"
log_info    "Next:       bash ../deploy/scripts/upload-app.sh"
