################################################################################
# Makefile - workflow shortcuts for terraform-scripts
#
#   make init             - terraform init
#   make fmt              - format everything
#   make validate         - static validation of the config
#   make plan             - plan against environments/<env>.tfvars
#   make apply            - interactive deploy via deploy.sh
#   make auto-deploy      - non-interactive deploy via deploy.sh --auto-approve
#   make dry-run          - deploy.sh --dry-run (plan only)
#   make destroy          - plan-destroy -> confirm -> terraform destroy
#   make outputs          - show terraform outputs
#   make ssh              - ssh into the instance (uses scripts/ssh.sh)
#   make upload-app       - rsync app + start under PM2 via deploy/scripts
#   make refresh          - refresh AWS SSO session
#
# Environment knobs:
#   ENV=dev|prod          - which env tfvars file to use (default dev)
#   AWS_PROFILE           - which AWS profile the provider should use
################################################################################

SHELL := /bin/bash

# --- Colours ----------------------------------------------------------------
BLUE   := \033[0;34m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
NC     := \033[0m

# --- Config -----------------------------------------------------------------
ENV          ?= dev
AWS_PROFILE  ?= aws-dharmendra
VAR_FILE     := environments/$(ENV).tfvars
PLAN_FILE    := plans/$(ENV).tfplan

REFRESH_SESSION := @AWS_PROFILE=$(AWS_PROFILE) bash scripts/refresh-aws-session.sh

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@printf "$(BLUE)microservices-nginx-pm2 / terraform-scripts$(NC)\n"
	@printf "  ENV=$(GREEN)$(ENV)$(NC)  AWS_PROFILE=$(GREEN)$(AWS_PROFILE)$(NC)\n\n"
	@awk 'BEGIN{FS=":.*##"; printf "Usage: make $(GREEN)<target>$(NC) [ENV=dev|prod]\n\nTargets:\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-16s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Setup

.PHONY: refresh
refresh: ## Refresh the AWS SSO session
	$(REFRESH_SESSION)

.PHONY: init
init: ## terraform init
	$(REFRESH_SESSION)
	AWS_PROFILE=$(AWS_PROFILE) terraform init

.PHONY: fmt
fmt: ## Format all .tf files recursively
	terraform fmt -recursive .

.PHONY: fmt-check
fmt-check: ## Fail if any .tf file is not formatted
	terraform fmt -check -recursive .

.PHONY: validate
validate: ## terraform validate
	AWS_PROFILE=$(AWS_PROFILE) terraform validate

##@ Plan / Apply

.PHONY: plan
plan: ## terraform plan -var-file=environments/$$ENV.tfvars
	$(REFRESH_SESSION)
	@mkdir -p plans
	AWS_PROFILE=$(AWS_PROFILE) terraform plan -var-file=$(VAR_FILE) -out=$(PLAN_FILE)
	@printf "$(GREEN)Plan written to $(PLAN_FILE)$(NC)\n"

.PHONY: apply
apply: ## Interactive deploy via deploy.sh
	@ENV=$(ENV) AWS_PROFILE=$(AWS_PROFILE) ./deploy.sh

.PHONY: auto-deploy
auto-deploy: ## Non-interactive deploy via deploy.sh --auto-approve
	@ENV=$(ENV) AWS_PROFILE=$(AWS_PROFILE) ./deploy.sh --auto-approve

.PHONY: dry-run
dry-run: ## deploy.sh --dry-run
	@ENV=$(ENV) AWS_PROFILE=$(AWS_PROFILE) ./deploy.sh --dry-run

##@ Destroy

.PHONY: plan-destroy
plan-destroy: ## Preview what destroy will remove
	$(REFRESH_SESSION)
	AWS_PROFILE=$(AWS_PROFILE) terraform plan -destroy -var-file=$(VAR_FILE)

.PHONY: destroy
destroy: ## Destroy the environment (asks for confirmation)
	$(REFRESH_SESSION)
	@printf "$(RED)About to DESTROY environment '$(ENV)'.$(NC)\n"
	@read -rp "Type 'destroy $(ENV)' to confirm: " ans && \
	  [ "$$ans" = "destroy $(ENV)" ] || { echo "Cancelled."; exit 1; }
	AWS_PROFILE=$(AWS_PROFILE) terraform destroy -var-file=$(VAR_FILE) -auto-approve

##@ Introspection

.PHONY: outputs
outputs: ## Show terraform outputs
	@AWS_PROFILE=$(AWS_PROFILE) terraform output

.PHONY: state-list
state-list: ## List resources in state
	@AWS_PROFILE=$(AWS_PROFILE) terraform state list

.PHONY: ssh
ssh: ## SSH into the instance (uses terraform outputs)
	@./scripts/ssh.sh

.PHONY: upload-app
upload-app: ## Rsync services + ecosystem to the instance and start under PM2
	@bash ../deploy/scripts/upload-app.sh

##@ Housekeeping

.PHONY: clean
clean: ## Remove local runtime artefacts (plans/, logs/, state-backups/)
	rm -rf plans logs state-backups
	@printf "$(GREEN)cleaned$(NC)\n"

.PHONY: state-backup
state-backup: ## Snapshot terraform.tfstate to state-backups/
	@mkdir -p state-backups
	@if [ -f terraform.tfstate ]; then \
	  cp -v terraform.tfstate state-backups/terraform.tfstate.$$(date -u +%Y%m%dT%H%M%SZ); \
	else \
	  printf "$(YELLOW)no local state file to back up (remote backend?)$(NC)\n"; \
	fi
