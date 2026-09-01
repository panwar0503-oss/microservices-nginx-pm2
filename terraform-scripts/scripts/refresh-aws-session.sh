#!/usr/bin/env bash
################################################################################
# scripts/refresh-aws-session.sh
#
# Verifies the configured AWS profile has a live session; if not, clears the
# SSO cache and runs `aws sso login`. Idempotent - safe to call before every
# terraform command.
#
#   Usage:  AWS_PROFILE=aws-dharmendra ./scripts/refresh-aws-session.sh
################################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/helpers.sh
source "${SCRIPT_DIR}/lib/helpers.sh"

: "${AWS_PROFILE:=aws-dharmendra}"
export AWS_PROFILE

require_cmd aws

if aws sts get-caller-identity >/dev/null 2>&1; then
  log_success "AWS session active for profile: $AWS_PROFILE"
  aws sts get-caller-identity --query 'Arn' --output text
  exit 0
fi

log_warning "AWS session expired or missing for profile: $AWS_PROFILE"

# Clear cached SSO tokens so `sso login` re-authenticates cleanly.
rm -rf ~/.aws/sso/cache/* 2>/dev/null || true

log_info "Launching: aws sso login --profile $AWS_PROFILE"
aws sso login --profile "$AWS_PROFILE"

if aws sts get-caller-identity >/dev/null 2>&1; then
  log_success "AWS session refreshed for profile: $AWS_PROFILE"
else
  log_error "SSO login did not produce a working session. Check your AWS config."
  exit 1
fi
