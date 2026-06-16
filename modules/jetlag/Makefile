# Jetlag Module Makefile
# Deploys OpenShift clusters on bare metal using Jetlag

SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.PHONY: help configure init deploy validate status clean

# Module paths
MODULE_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell cd $(MODULE_DIR)/../.. && pwd)

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;36m
NC := \033[0m

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------

help:
	@echo ""
	@echo -e "$(BLUE)Jetlag Module - OpenShift Cluster Deployment$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Setup:"
	@echo "  configure    Interactive configuration helper (updates vars/config.json)"
	@echo "  init         Initialize module (Jetlag venv, pull secret)"
	@echo ""
	@echo "Operations:"
	@echo "  deploy       Deploy new cluster (auto-resumes on retry)"
	@echo "  validate     Validate cluster is accessible"
	@echo ""
	@echo "Utilities:"
	@echo "  status       Show deployment status and state"
	@echo "  clean        Remove generated configs and state"
	@echo ""
	@echo "Workflows:"
	@echo ""
	@echo "  Deploy New Cluster:"
	@echo "    make init              # First time setup"
	@echo "    make deploy            # Deploy cluster"
	@echo "    make deploy            # If failed, auto-resumes from last stage"
	@echo "    make validate          # Verify cluster is accessible"
	@echo ""
	@echo "Generated files:"
	@echo "  State:  $(MODULE_DIR)/generated/state/"
	@echo "  Logs:   $(MODULE_DIR)/generated/logs/"
	@echo ""

#------------------------------------------------------------------------------
# Configuration Target - Interactive JSON builder
#------------------------------------------------------------------------------

configure:
	@echo ""
	@$(MODULE_DIR)/configure-json.sh

#------------------------------------------------------------------------------
# Initialization
#------------------------------------------------------------------------------

init:
	@mkdir -p $(MODULE_DIR)/generated/state
	@if [ -f "$(MODULE_DIR)/generated/state/init.env" ] && grep -q "^INIT_COMPLETED=true" "$(MODULE_DIR)/generated/state/init.env" 2>/dev/null; then \
		echo ""; \
		echo -e "$(GREEN)✓ Jetlag module already initialized (idempotent - skipping)$(NC)"; \
		echo ""; \
		echo "To force re-initialization:"; \
		echo "  rm $(MODULE_DIR)/generated/state/init.env"; \
		echo "  make init"; \
		echo ""; \
	else \
		echo ""; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo -e "$(BLUE)Jetlag Module Initialization$(NC)"; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo ""; \
		echo "Step 1: Checking Jetlag repository..."; \
		if [ ! -d "$(ROOT_DIR)/repos/jetlag" ]; then \
			echo -e "$(YELLOW)Jetlag repository not found$(NC)"; \
			echo "Run: $(ROOT_DIR)/bootstrap.sh"; \
			exit 1; \
		else \
			echo -e "$(GREEN)✓ Jetlag repository exists$(NC)"; \
		fi; \
		echo ""; \
		echo "Step 2: Initializing Jetlag (Python venv, Ansible)..."; \
		if [ ! -d "$(ROOT_DIR)/repos/jetlag/.ansible" ]; then \
			echo "Running Jetlag bootstrap..."; \
			cd $(ROOT_DIR)/repos/jetlag && ./bootstrap.sh; \
			echo -e "$(GREEN)✓ Jetlag initialized$(NC)"; \
		else \
			echo -e "$(GREEN)✓ Jetlag already initialized$(NC)"; \
		fi; \
		echo ""; \
		echo "Step 3: Checking pull secret..."; \
		if [ -f "$(ROOT_DIR)/pull-secret.txt" ]; then \
			echo -e "$(GREEN)✓ Pull secret found at $(ROOT_DIR)/pull-secret.txt$(NC)"; \
			cd $(ROOT_DIR)/repos/jetlag && cp $(ROOT_DIR)/pull-secret.txt pull-secret.txt; \
		elif [ -f "$(ROOT_DIR)/repos/jetlag/pull-secret.txt" ]; then \
			echo -e "$(GREEN)✓ Pull secret found in Jetlag directory$(NC)"; \
		else \
			echo -e "$(YELLOW)⚠ Pull secret not found$(NC)"; \
			echo ""; \
			echo "Please place your OpenShift pull secret at:"; \
			echo "  $(ROOT_DIR)/pull-secret.txt"; \
			echo ""; \
			echo "Get it from: https://console.redhat.com/openshift/install/pull-secret"; \
			echo ""; \
			echo "After placing the file, re-run: make init"; \
		fi; \
		echo ""; \
		echo "# Jetlag module initialization state" > $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_COMPLETED=true" >> $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_TIMESTAMP=$$(date +%Y%m%d_%H%M%S)" >> $(MODULE_DIR)/generated/state/init.env; \
		echo ""; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo -e "$(GREEN)✓ Jetlag Module Initialized$(NC)"; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo ""; \
		echo "Next: make deploy"; \
		echo ""; \
	fi

#------------------------------------------------------------------------------
# Primary Operations
#------------------------------------------------------------------------------

deploy:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Deploying Cluster$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@$(MODULE_DIR)/jetlag-deploy.sh

validate:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Validating Cluster$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@$(MODULE_DIR)/jetlag-validate.sh

#------------------------------------------------------------------------------
# Status and Utilities
#------------------------------------------------------------------------------

status:
	@echo -e "$(BLUE)Jetlag Deployment Status$(NC)"
	@echo "=========================="
	@echo ""
	@if [ -f $(MODULE_DIR)/generated/state/current.env ]; then \
		echo "State file: $(MODULE_DIR)/generated/state/current.env"; \
		echo ""; \
		cat $(MODULE_DIR)/generated/state/current.env; \
	else \
		echo -e "$(YELLOW)No deployment state found$(NC)"; \
		echo "Run: make deploy"; \
	fi
	@echo ""
	@if [ -f $(ROOT_DIR)/vars/state.env ]; then \
		echo "Global state: $(ROOT_DIR)/vars/state.env"; \
		echo ""; \
		grep -E "BASTION_HOST|KUBECONFIG_PATH|CLUSTER_TYPE|JETLAG" $(ROOT_DIR)/vars/state.env 2>/dev/null || echo "No Jetlag state in global file"; \
	fi
	@echo ""

clean:
	@echo -e "$(YELLOW)Cleaning Jetlag module generated files...$(NC)"
	@echo "  - Module state, logs, output, init state"
	@rm -rf $(MODULE_DIR)/generated/state/*
	@rm -rf $(MODULE_DIR)/generated/logs/*
	@rm -rf $(MODULE_DIR)/generated/output/*
	@rm -rf $(MODULE_DIR)/generated/config/*
	@echo "  - Jetlag all.yml and inventory"
	@rm -f $(ROOT_DIR)/repos/jetlag/ansible/vars/all.yml
	@rm -rf $(ROOT_DIR)/repos/jetlag/ansible/inventory/*.local
	@echo -e "$(GREEN)✓ Jetlag module cleaned$(NC)"
	@echo ""
	@echo "Preserved:"
	@echo "  - Jetlag repository (repos/jetlag/)"
	@echo "  - Pull secret (if exists)"
	@echo ""
