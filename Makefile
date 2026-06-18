# Makefile for reg-agent
# AI-Driven CI/CD Orchestrator for Regulus Testing

SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.PHONY: all help deploy run validate validate-config save-config clean status info configure-tests

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;36m
NC := \033[0m

# Deployment guard removed - can run on any machine

#------------------------------------------------------------------------------
# Main Targets
#------------------------------------------------------------------------------

all:
	@# If CONFIG_FILE is provided, validate it first
	@if [ -n "$(CONFIG_FILE)" ]; then \
		echo ""; \
		echo -e "$(BLUE)Validating configuration before deployment...$(NC)"; \
		echo ""; \
		$(MAKE) validate-config CONFIG_FILE=$(CONFIG_FILE); \
		echo ""; \
	fi
	@$(MAKE) deploy run validate

help:
	@echo ""
	@echo -e "$(BLUE)reg-agent - AI-Driven CI/CD Orchestrator$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "CONFIGURATION (Required: vars/config.json)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "Option 1: Manual configuration"
	@echo "  cp vars/config.json.template vars/config.json"
	@echo "  vi vars/config.json"
	@echo ""
	@echo "Option 2: Interactive helpers (per module)"
	@echo "  make -C modules/quads configure      # Configure QUADS section"
	@echo "  make -C modules/jetlag configure     # Configure Jetlag section"
	@echo "  make -C modules/crucible configure   # Configure Crucible section"
	@echo "  make -C modules/regulus configure    # Configure Regulus section"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "MAIN OPERATIONS"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  all              Complete pipeline: deploy + run + validate (one command)"
	@echo "  deploy           Deploy infrastructure (requires vars/config.json)"
	@echo "  run              Execute Regulus tests (requires vars/config.json)"
	@echo "  validate         Validate test results"
	@echo ""
	@echo "Deployment modes (set in config.json):"
	@echo "  full             QUADS + Jetlag + Crucible + Regulus + Tests"
	@echo "  cluster-ready    User provides cluster → Crucible + Regulus + Tests"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "UTILITIES"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  validate-config     Validate config.json before deployment"
	@echo "  info                Show detailed status of all modules"
	@echo "  status              Show config and state files"
	@echo "  clean               Remove generated state (preserves test data)"
	@echo "  deallocate-quads    Release QUADS assignment"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "EXAMPLES"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  # Complete pipeline in one command"
	@echo "  make -C modules/quads configure && make all"
	@echo ""
	@echo "  # Quick start (step-by-step)"
	@echo "  make -C modules/quads configure && make deploy"
	@echo ""
	@echo "  # Configure all modules, then run complete pipeline"
	@echo "  for m in quads jetlag crucible regulus; do \\"
	@echo "    make -C modules/\$$\$$m configure; \\"
	@echo "  done"
	@echo "  make all"
	@echo ""
	@echo "  # Re-run tests with existing deployment"
	@echo "  make run validate"
	@echo ""
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "MODULE-SPECIFIC HELP"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo ""
	@echo "  cd modules/quads && make help"
	@echo "  cd modules/jetlag && make help"
	@echo "  cd modules/crucible && make help"
	@echo "  cd modules/regulus && make help"
	@echo ""

#------------------------------------------------------------------------------
# Configuration
# NOTE: Top-level configure removed. Use module-level configure:
#   make -C modules/quads configure
#   make -C modules/jetlag configure
#   make -C modules/crucible configure
#   make -C modules/regulus configure
# Or manually create vars/config.json from vars/config.json.template
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Deployment - Setup Infrastructure
# Mode-aware: executes based on DEPLOY_MODE from configure
#
# Supported modes:
#   full          - Start from scratch (QUADS → Jetlag → Crucible → Regulus)
#   from-cluster  - Start from existing cluster (Crucible → Regulus)
#   from-workspace - Everything ready, validate workspace only
#------------------------------------------------------------------------------

deploy:
	@# Require config.json (mandatory)
	@if [ ! -f vars/config.json ]; then \
		echo ""; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo -e "$(RED)ERROR: vars/config.json not found$(NC)"; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo ""; \
		echo "Create config.json using one of these methods:"; \
		echo ""; \
		echo "  1. Copy template and edit:"; \
		echo "     cp vars/config.json.template vars/config.json"; \
		echo "     vi vars/config.json"; \
		echo ""; \
		echo "  2. Use module helpers (interactive):"; \
		echo "     make -C modules/quads configure"; \
		echo "     make -C modules/jetlag configure"; \
		echo "     make -C modules/crucible configure"; \
		echo "     make -C modules/regulus configure"; \
		echo ""; \
		exit 1; \
	fi
	@# Validate config.json before deployment
	@echo ""
	@echo -e "$(BLUE)Validating configuration...$(NC)"
	@if ! ./config/validate-config.sh vars/config.json; then \
		echo ""; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo -e "$(RED)Configuration validation failed$(NC)"; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo ""; \
		echo "Fix the errors above before deploying."; \
		echo ""; \
		exit 1; \
	fi
	@echo ""
	@echo -e "$(BLUE)=========================================$(NC)"
	@echo -e "$(BLUE)Infrastructure Setup$(NC)"
	@echo -e "$(BLUE)=========================================$(NC)"
	@echo ""
	@export REG_AGENT_ROOT=$$(pwd) && \
	source modules/lib/json-config.sh && \
	export QUADS_MODE=$$(jq -r '.quads.mode // "allocate"' vars/config.json) && \
	echo "Mode: $$QUADS_MODE (QUADS → Jetlag → Crucible → Regulus)"; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "Phase 1: QUADS - $$QUADS_MODE bare metal"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	$(MAKE) -C modules/quads init; \
	if [ -f modules/quads/generated/state/current.env ]; then \
		source modules/quads/generated/state/current.env 2>/dev/null; \
		if [ -n "$$CLOUD_NAME" ]; then \
			echo -e "$(GREEN)✓ QUADS allocation already exists, skipping Phase 1$(NC)"; \
			echo "  Cloud: $$CLOUD_NAME"; \
			echo "  Assignment: $$ASSIGNMENT_ID"; \
		else \
			if [ "$$QUADS_MODE" = "import" ]; then \
				echo "QUADS mode: import"; \
				CLOUD_NAME=$$(jq -r '.quads.cloud_name // empty' vars/config.json); \
				LAB=$$(jq -r '.quads.lab // empty' vars/config.json); \
				if [ "$$LAB" = "byol" ]; then \
					echo -e "$(GREEN)✓ BYOL mode - skipping QUADS import (no QUADS API)$(NC)"; \
					echo "  Lab: $$LAB"; \
				elif [ -n "$$CLOUD_NAME" ] && [ -n "$$LAB" ]; then \
					$(MAKE) -C modules/quads import CLOUD_NAME=$$CLOUD_NAME LAB=$$LAB; \
				else \
					echo -e "$(RED)Error: Import mode requires cloud_name and lab in config.json$(NC)"; \
					exit 1; \
				fi; \
			else \
				echo "QUADS mode: allocate"; \
				$(MAKE) -C modules/quads allocate; \
			fi; \
		fi; \
	else \
		if [ "$$QUADS_MODE" = "import" ]; then \
			echo "QUADS mode: import"; \
			CLOUD_NAME=$$(jq -r '.quads.cloud_name // empty' vars/config.json); \
			LAB=$$(jq -r '.quads.lab // empty' vars/config.json); \
			if [ "$$LAB" = "byol" ]; then \
				echo -e "$(GREEN)✓ BYOL mode - skipping QUADS import (no QUADS API)$(NC)"; \
				echo "  Lab: $$LAB"; \
			elif [ -n "$$CLOUD_NAME" ] && [ -n "$$LAB" ]; then \
				$(MAKE) -C modules/quads import CLOUD_NAME=$$CLOUD_NAME LAB=$$LAB; \
			else \
				echo -e "$(RED)Error: Import mode requires cloud_name and lab in config.json$(NC)"; \
				exit 1; \
			fi; \
		else \
			echo "QUADS mode: allocate"; \
			$(MAKE) -C modules/quads allocate; \
		fi; \
	fi; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "Phase 2: Jetlag - Deploy/validate cluster"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	$(MAKE) -C modules/jetlag init; \
	LAB=$$(jq -r '.quads.lab // empty' vars/config.json); \
	QUADS_MODE=$$(jq -r '.quads.mode // "allocate"' vars/config.json); \
	if [ "$$LAB" = "byol" ] && [ "$$QUADS_MODE" = "import" ]; then \
		echo -e "$(GREEN)✓ BYOL mode - using cluster info from config.json$(NC)"; \
		BASTION_HOST=$$(jq -r '.jetlag.bastion_host' vars/config.json); \
		KUBECONFIG_PATH=$$(jq -r '.jetlag.kubeconfig_path' vars/config.json); \
		echo "  Bastion: $$BASTION_HOST"; \
		echo "  Kubeconfig: $$KUBECONFIG_PATH"; \
		echo "" >> vars/state.env; \
		echo "# Phase 2: Jetlag (BYOL cluster - added $$(date))" >> vars/state.env; \
		echo "BASTION_HOST=\"$$BASTION_HOST\"" >> vars/state.env; \
		echo "KUBECONFIG_PATH=\"$$KUBECONFIG_PATH\"" >> vars/state.env; \
		echo "LAB=\"$$LAB\"" >> vars/state.env; \
		echo "JETLAG_IMPORT_COMPLETED=\"true\"" >> vars/state.env; \
	elif [ -f modules/quads/generated/state/current.env ]; then \
		source modules/quads/generated/state/current.env 2>/dev/null; \
		if [ "$$DEPLOYMENT_METHOD" = "imported" ]; then \
			echo -e "$(GREEN)✓ QUADS cluster imported, gathering cluster info$(NC)"; \
			echo "  Using existing cluster from import"; \
			BASTION_HOST=$$(jq -r '.jetlag.bastion_host' vars/config.json); \
			KUBECONFIG_PATH=$$(jq -r '.jetlag.kubeconfig_path' vars/config.json); \
			echo "  Bastion: $$BASTION_HOST"; \
			echo "  Kubeconfig: $$KUBECONFIG_PATH"; \
			echo "" >> vars/state.env; \
			echo "# Phase 2: Jetlag (imported cluster - added $$(date))" >> vars/state.env; \
			echo "BASTION_HOST=\"$$BASTION_HOST\"" >> vars/state.env; \
			echo "KUBECONFIG_PATH=\"$$KUBECONFIG_PATH\"" >> vars/state.env; \
			echo "JETLAG_IMPORT_COMPLETED=\"true\"" >> vars/state.env; \
		elif [ -f modules/jetlag/generated/state/current.env ]; then \
			source modules/jetlag/generated/state/current.env 2>/dev/null; \
			if [ "$$JETLAG_DEPLOY_COMPLETED" = "true" ] && [ -n "$$BASTION_HOST" ]; then \
				echo -e "$(GREEN)✓ Jetlag deployment already complete, skipping Phase 2$(NC)"; \
				echo "  Bastion: $$BASTION_HOST"; \
				echo "  Cluster: $$CLUSTER_TYPE"; \
			else \
				$(MAKE) -C modules/jetlag deploy; \
			fi; \
		else \
			$(MAKE) -C modules/jetlag deploy; \
		fi; \
	else \
		if [ "$$QUADS_MODE" = "allocate" ]; then \
			$(MAKE) -C modules/jetlag deploy; \
		else \
			echo -e "$(RED)Error: No QUADS state found and not BYOL mode$(NC)"; \
			exit 1; \
		fi; \
	fi; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "Phase 3: Crucible - Install on controller"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	$(MAKE) -C modules/crucible init; \
	AUTO_MODE=1 ./modules/phase-3-crucible-setup.sh; \
	echo ""; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	echo "Phase 4: Regulus - Setup workspace"; \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; \
	$(MAKE) -C modules/regulus init; \
	AUTO_MODE=1 ./modules/phase-4-regulus-setup.sh
	@echo ""
	@echo -e "$(GREEN)=========================================$(NC)"
	@echo -e "$(GREEN)Infrastructure Setup Complete!$(NC)"
	@echo -e "$(GREEN)=========================================$(NC)"
	@echo ""

#------------------------------------------------------------------------------
# Individual Phases
#------------------------------------------------------------------------------

quads:
	@./modules/phase-1-quads-reserve.sh

jetlag:
	@./modules/phase-2-jetlag-deploy.sh

crucible:
	@./modules/phase-3-crucible-setup.sh

regulus-setup:
	@./modules/phase-4-regulus-setup.sh

run:
	@# Require config.json (mandatory)
	@if [ ! -f vars/config.json ]; then \
		echo ""; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo -e "$(RED)ERROR: vars/config.json not found$(NC)"; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo ""; \
		echo "See: make deploy (for creating config.json)"; \
		echo ""; \
		exit 1; \
	fi
	@# Validate config.json before running tests
	@echo ""
	@echo -e "$(BLUE)Validating configuration...$(NC)"
	@if ! ./config/validate-config.sh vars/config.json; then \
		echo ""; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo -e "$(RED)Configuration validation failed$(NC)"; \
		echo -e "$(RED)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"; \
		echo ""; \
		echo "Fix the errors above before running tests."; \
		echo ""; \
		exit 1; \
	fi
	@./modules/phase-5-regulus-run.sh

validate:
	@./modules/phase-6-validate-results.sh

validate-config:
	@if [ -z "$(CONFIG_FILE)" ]; then \
		echo ""; \
		echo -e "$(RED)ERROR: CONFIG_FILE not specified$(NC)"; \
		echo ""; \
		echo "Usage:"; \
		echo "  make validate-config CONFIG_FILE=config/my-config.json"; \
		echo ""; \
		echo "Available configs:"; \
		ls -1 config/*.json 2>/dev/null | sed 's/^/  /' || echo "  (no JSON configs found)"; \
		echo ""; \
		exit 1; \
	fi
	@./config/validate-config.sh "$(CONFIG_FILE)"


#------------------------------------------------------------------------------
# Utilities
#------------------------------------------------------------------------------

status:
	@echo ""
	@echo -e "$(BLUE)=========================================$(NC)"
	@echo -e "$(BLUE)reg-agent Status$(NC)"
	@echo -e "$(BLUE)=========================================$(NC)"
	@if [ -f vars/config.json ]; then \
		echo "Configuration: vars/config.json"; \
		echo ""; \
		jq -r 'del(.. | .password? // empty)' vars/config.json 2>/dev/null || cat vars/config.json; \
	else \
		echo -e "$(YELLOW)No configuration found$(NC)"; \
	fi
	@echo ""
	@if [ -f vars/state.env ]; then \
		echo "State: vars/state.env"; \
		echo ""; \
		cat vars/state.env; \
	else \
		echo -e "$(YELLOW)No state found$(NC)"; \
	fi
	@echo ""

info:
	@echo ""
	@echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo -e "$(BLUE)                    reg-agent Module Status$(NC)"
	@echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@# Phase 1 - QUADS
	@echo -e "$(BLUE)Phase 1: QUADS Allocation$(NC)"
	@echo "────────────────────────────────────────────────────────────────────"
	@if [ -f modules/quads/generated/state/current.env ]; then \
		source modules/quads/generated/state/current.env; \
		echo -e "Status:      $(GREEN)✓ Active$(NC)"; \
		echo "Cloud:       $$CLOUD_NAME"; \
		echo "Assignment:  $$ASSIGNMENT_ID"; \
		echo "Lab:         $$LAB"; \
		echo "Hosts:       $$NUM_HOSTS"; \
		echo "Method:      $$QUADS_METHOD"; \
		[ -n "$$ALLOCATED_AT" ] && echo "Allocated:   $$ALLOCATED_AT" || true; \
	else \
		echo -e "Status:      $(RED)✗ Not allocated$(NC)"; \
		echo ""; \
		echo "Next: make test-quads"; \
	fi
	@echo ""
	@# Phase 2 - Jetlag
	@echo -e "$(BLUE)Phase 2: Jetlag Cluster Deployment$(NC)"
	@echo "────────────────────────────────────────────────────────────────────"
	@if [ -f modules/jetlag/generated/state/current.env ]; then \
		source modules/jetlag/generated/state/current.env; \
		if [ "$$JETLAG_DEPLOY_COMPLETED" = "true" ]; then \
			echo -e "Status:      $(GREEN)✓ Deployed$(NC)"; \
		else \
			echo -e "Status:      $(YELLOW)⚠ In progress$(NC)"; \
		fi; \
		echo "Bastion:     $$BASTION_HOST"; \
		echo "Cluster:     $$CLUSTER_TYPE"; \
		if [ -n "$$BASTION_HOST" ]; then \
			ACTUAL_KUBECONFIG=$$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$$BASTION_HOST 'find /root -name kubeconfig -type f 2>/dev/null | head -1' 2>/dev/null || echo "$$KUBECONFIG_PATH"); \
			if [ -n "$$ACTUAL_KUBECONFIG" ] && [ "$$ACTUAL_KUBECONFIG" != "$$KUBECONFIG_PATH" ]; then \
				echo "Kubeconfig:  $$ACTUAL_KUBECONFIG (detected)"; \
			else \
				echo "Kubeconfig:  $$KUBECONFIG_PATH"; \
			fi; \
		else \
			echo "Kubeconfig:  $$KUBECONFIG_PATH"; \
		fi; \
		echo "Method:      $$DEPLOYMENT_METHOD"; \
		[ -n "$$JETLAG_DEPLOY_TIMESTAMP" ] && echo "Deployed:    $$JETLAG_DEPLOY_TIMESTAMP" || true; \
	elif grep -q "BASTION_HOST" vars/state.env 2>/dev/null; then \
		source vars/state.env; \
		echo -e "Status:      $(GREEN)✓ Deployed (legacy state)$(NC)"; \
		echo "Bastion:     $$BASTION_HOST"; \
		[ -n "$$CLUSTER_TYPE" ] && echo "Cluster:     $$CLUSTER_TYPE" || true; \
		if [ -n "$$BASTION_HOST" ]; then \
			ACTUAL_KUBECONFIG=$$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$$BASTION_HOST 'find /root -name kubeconfig -type f 2>/dev/null | head -1' 2>/dev/null || echo "$$KUBECONFIG_PATH"); \
			if [ -n "$$ACTUAL_KUBECONFIG" ]; then \
				echo "Kubeconfig:  $$ACTUAL_KUBECONFIG"; \
			fi; \
		elif [ -n "$$KUBECONFIG_PATH" ]; then \
			echo "Kubeconfig:  $$KUBECONFIG_PATH"; \
		fi; \
	else \
		echo -e "Status:      $(RED)✗ Not deployed$(NC)"; \
		echo ""; \
		echo "Next: make test-jetlag"; \
	fi
	@echo ""
	@# Phase 3 - Crucible
	@echo -e "$(BLUE)Phase 3: Crucible Installation$(NC)"
	@echo "────────────────────────────────────────────────────────────────────"
	@if grep -q "CRUCIBLE_INSTALLED=true" vars/state.env 2>/dev/null; then \
		source vars/state.env; \
		echo -e "Status:      $(GREEN)✓ Installed$(NC)"; \
		echo "Path:        $$CRUCIBLE_PATH"; \
		[ -n "$$CRUCIBLE_INSTALL_TIME" ] && echo "Installed:   $$CRUCIBLE_INSTALL_TIME" || true; \
	else \
		echo -e "Status:      $(RED)✗ Not installed$(NC)"; \
		echo ""; \
		echo "Next: make test-crucible"; \
	fi
	@echo ""
	@# Phase 4 - Regulus Setup
	@echo -e "$(BLUE)Phase 4: Regulus Setup$(NC)"
	@echo "────────────────────────────────────────────────────────────────────"
	@if grep -q "REGULUS_SETUP_COMPLETED=true" vars/state.env 2>/dev/null; then \
		source vars/state.env; \
		echo -e "Status:      $(GREEN)✓ Setup complete$(NC)"; \
		echo "Path:        $$REGULUS_PATH"; \
		[ -n "$$REGULUS_SETUP_TIMESTAMP" ] && echo "Setup:       $$REGULUS_SETUP_TIMESTAMP" || true; \
	elif grep -q "REGULUS_PATH" vars/state.env 2>/dev/null; then \
		source vars/state.env; \
		echo -e "Status:      $(YELLOW)⚠ Partially configured$(NC)"; \
		echo "Path:        $$REGULUS_PATH"; \
	else \
		echo -e "Status:      $(RED)✗ Not setup$(NC)"; \
		echo ""; \
		echo "Next: make test-regulus-install"; \
	fi
	@echo ""
	@# Phase 5 & 6 - Test Execution
	@echo -e "$(BLUE)Phase 5-6: Test Execution & Validation$(NC)"
	@echo "────────────────────────────────────────────────────────────────────"
	@if grep -q "RUN_ID" vars/state.env 2>/dev/null; then \
		source vars/state.env; \
		echo -e "Status:      $(GREEN)✓ Tests executed$(NC)"; \
		echo "Run ID:      $$RUN_ID"; \
		[ -n "$$WORKLOAD_NAME" ] && echo "Workload:    $$WORKLOAD_NAME" || true; \
		[ -n "$$TEST_STATUS" ] && echo "Result:      $$TEST_STATUS" || true; \
	else \
		echo -e "Status:      $(RED)✗ Not run$(NC)"; \
		echo ""; \
		echo "Next: make test-run"; \
	fi
	@echo ""
	@echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "Commands:"
	@echo "  make status          - Show raw config and state files"
	@echo "  make validate-quads  - Validate QUADS allocation"
	@echo "  make validate-jetlag - Validate cluster access"
	@echo ""

save-config:
	@echo ""
	@echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo -e "$(BLUE)        Backup Current Configuration$(NC)"
	@echo -e "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@if [ ! -f vars/config.json ]; then \
		echo -e "$(RED)Error: No configuration found at vars/config.json$(NC)"; \
		echo ""; \
		exit 1; \
	fi
	@# Backup to timestamped file
	@BACKUP_FILE="vars/config-backup-$$(date +%Y%m%d-%H%M%S).json"; \
	cp vars/config.json $$BACKUP_FILE; \
	echo -e "$(GREEN)✓ Configuration backed up to: $$BACKUP_FILE$(NC)"
	@echo ""

clean:
	@echo ""
	@echo -e "$(BLUE)Cleaning generated files...$(NC)"
	@$(MAKE) -C modules/quads clean 2>&1 | grep -v "make:"
	@$(MAKE) -C modules/jetlag clean 2>&1 | grep -v "make:"
	@$(MAKE) -C modules/crucible clean 2>&1 | grep -v "make:"
	@rm -f vars/state.env /tmp/quads_output.log
	@rm -f repos/jetlag/ansible/vars/all.yml
	@rm -f repos/jetlag/ansible/inventory/*.local 2>/dev/null || true
	@echo ""
	@echo -e "$(GREEN)✓ Cleaned (config.json and test data preserved)$(NC)"
	@echo ""
	@echo "Note: config.json is preserved. To reset configuration:"
	@echo "  rm vars/config.json"
	@echo ""

clean-all: clean
	@echo -e "$(BLUE)Removing artifacts...$(NC)"
	@rm -rf artifacts/*
	@echo -e "$(GREEN)✓ Complete cleanup done$(NC)"
	@echo ""

clean-repos:
	@echo -e "$(RED)Warning: This will delete all cloned repositories$(NC)"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		rm -rf repos/; \
		echo -e "$(GREEN)Repositories cleaned. Run ./bootstrap.sh to re-clone$(NC)"; \
	else \
		echo "Cancelled"; \
	fi

#------------------------------------------------------------------------------
# Development
#------------------------------------------------------------------------------

update-repos:
	@echo "Updating local repositories..."
	@if [ -d repos/ansible-quads-ssm ]; then \
		echo "  Updating ansible-quads-ssm..."; \
		cd repos/ansible-quads-ssm && git pull; \
	fi
	@if [ -d repos/jetlag ]; then \
		echo "  Updating jetlag..."; \
		cd repos/jetlag && git pull; \
	fi
	@echo ""
	@echo -e "$(GREEN)✓ Local repositories updated$(NC)"
	@echo ""
	@echo -e "$(YELLOW)Note: Crucible and Regulus are on controller host$(NC)"
	@echo "Update them with:"
	@echo "  ssh root@\$$CRUCIBLE_CONTROLLER_HOST 'cd /root/crucible && git pull'"
	@echo "  (Regulus uses timestamped directories - clone new versions as needed)"
	@echo ""

test-llm:
	@if [ -n "$$REG_AGENT_LLM_URL" ]; then \
		echo "Testing LLM server at $$REG_AGENT_LLM_URL"; \
		curl -s $$REG_AGENT_LLM_URL/health | jq; \
	else \
		echo -e "$(YELLOW)REG_AGENT_LLM_URL not set$(NC)"; \
		echo "Set: export REG_AGENT_LLM_URL=http://localhost:8000"; \
	fi

#------------------------------------------------------------------------------
# Module-Specific Utility Targets
# These are delegations kept for backwards compatibility and convenience
# For individual phase execution, use: cd modules/<name> && make install
#------------------------------------------------------------------------------

# Test configuration
configure-tests:
	@$(MAKE) -C modules/regulus configure-tests

# Cleanup utilities
deallocate-quads:
	@$(MAKE) -C modules/quads deallocate

deallocate-by-cloud:
	@$(MAKE) -C modules/quads deallocate-by-cloud CLOUD_NAME=$(CLOUD_NAME)
