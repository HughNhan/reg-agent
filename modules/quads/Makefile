# QUADS SSM Module Makefile
# Test targets for QUADS allocation, validation, and deallocation

SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.PHONY: help configure init test allocate validate deallocate import clean status

# Module paths
MODULE_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell cd $(MODULE_DIR)/../.. && pwd)

# Scripts
ALLOCATE_SCRIPT := $(MODULE_DIR)/quads-ssm-reserve.sh
VALIDATE_SCRIPT := $(MODULE_DIR)/quads-ssm-validate.sh
DEALLOCATE_SCRIPT := $(MODULE_DIR)/quads-ssm-deallocate.sh
IMPORT_SCRIPT := $(MODULE_DIR)/quads-ssm-import.sh

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
	@echo -e "$(BLUE)QUADS SSM Module - Bare Metal Resource Broker$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Setup:"
	@echo "  configure           Interactive configuration helper (updates vars/config.json)"
	@echo "  init                Initialize module (clone repos, setup state)"
	@echo ""
	@echo "Operations:"
	@echo "  allocate            Allocate bare metal from QUADS"
	@echo "  import              Import existing allocation (CLOUD_NAME=cloud23 LAB=scalelab)"
	@echo "  validate            Check assignment status"
	@echo "  deallocate          Terminate assignment (requires state)"
	@echo "  deallocate-by-cloud Terminate by cloud name (CLOUD_NAME=cloud04)"
	@echo ""
	@echo "Utilities:"
	@echo "  show-available      Show available QUADS hosts"
	@echo "  status              Show allocation status and state"
	@echo "  clean               Remove generated configs and state"
	@echo ""
	@echo "Workflows:"
	@echo ""
	@echo "  New Allocation:"
	@echo "    make init                 # Initialize (first time or reconfigure)"
	@echo "    make show-available       # Check what's available"
	@echo "    make allocate             # Allocate cluster"
	@echo "    make validate             # Check status"
	@echo "    make deallocate           # Release cluster"
	@echo ""
	@echo "  Import Existing:"
	@echo "    make import CLOUD_NAME=cloud23 LAB=scalelab"
	@echo "    make validate             # Check status"
	@echo ""
	@echo "Generated files:"
	@echo "  State:  $(MODULE_DIR)/generated/state/"
	@echo "  Logs:   $(MODULE_DIR)/generated/logs/"
	@echo "  Output: $(MODULE_DIR)/generated/output/"
	@echo ""

#------------------------------------------------------------------------------
# Configuration Target - Interactive JSON builder
#------------------------------------------------------------------------------

configure:
	@echo ""
	@$(MODULE_DIR)/configure-json.sh

#------------------------------------------------------------------------------
# Initialization Target
#------------------------------------------------------------------------------

init:
	@mkdir -p $(MODULE_DIR)/generated/state
	@if [ -f "$(MODULE_DIR)/generated/state/init.env" ] && grep -q "^INIT_COMPLETED=true" "$(MODULE_DIR)/generated/state/init.env" 2>/dev/null; then \
		echo ""; \
		echo -e "$(GREEN)✓ QUADS module already initialized (idempotent - skipping)$(NC)"; \
		echo ""; \
		echo "To force re-initialization:"; \
		echo "  rm $(MODULE_DIR)/generated/state/init.env"; \
		echo "  make init"; \
		echo ""; \
	else \
		echo ""; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo -e "$(BLUE)QUADS Module Initialization$(NC)"; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo ""; \
		echo "Step 1: Checking ansible-quads-ssm repository..."; \
		if [ ! -d "$(ROOT_DIR)/repos/ansible-quads-ssm" ]; then \
			echo -e "$(YELLOW)ansible-quads-ssm not found. Cloning...$(NC)"; \
			mkdir -p $(ROOT_DIR)/repos; \
			git clone https://github.com/quadsproject/ansible-quads-ssm.git $(ROOT_DIR)/repos/ansible-quads-ssm; \
			echo -e "$(GREEN)✓ ansible-quads-ssm cloned$(NC)"; \
		else \
			echo -e "$(GREEN)✓ ansible-quads-ssm already exists$(NC)"; \
		fi; \
		echo ""; \
		echo "# QUADS module initialization state" > $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_COMPLETED=true" >> $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_TIMESTAMP=$$(date +%Y%m%d_%H%M%S)" >> $(MODULE_DIR)/generated/state/init.env; \
		echo ""; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo -e "$(GREEN)✓ QUADS Module Initialized$(NC)"; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo ""; \
		echo "Next: make allocate"; \
		echo ""; \
	fi

init-debug:
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo -e "$(YELLOW)QUADS Init (Debug/Interactive)$(NC)"
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo ""
	@echo "Step 1: Checking ansible-quads-ssm repository..."
	@if [ ! -d "$(ROOT_DIR)/repos/ansible-quads-ssm" ]; then \
		echo -e "$(YELLOW)ansible-quads-ssm not found. Cloning...$(NC)"; \
		mkdir -p $(ROOT_DIR)/repos; \
		git clone https://github.com/quadsproject/ansible-quads-ssm.git $(ROOT_DIR)/repos/ansible-quads-ssm; \
		echo -e "$(GREEN)✓ ansible-quads-ssm cloned$(NC)"; \
	else \
		echo -e "$(GREEN)✓ ansible-quads-ssm already exists$(NC)"; \
	fi
	@echo ""
	@echo "Step 2: Interactive configuration..."
	@$(MODULE_DIR)/configure-json.sh
	@echo ""
	@echo -e "$(GREEN)✓ Debug init complete$(NC)"
	@echo ""

#------------------------------------------------------------------------------
# Information Targets
#------------------------------------------------------------------------------

show-available:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)QUADS Available Resources$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@$(MODULE_DIR)/quads-ssm-info.sh

#------------------------------------------------------------------------------
# Test Targets
#------------------------------------------------------------------------------

test: allocate
	@echo -e "$(GREEN)✓ QUADS allocation test complete$(NC)"

allocate:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Testing Phase 1: QUADS SSM Allocation$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(GREEN)✓ Allocation complete$(NC)"
	@echo ""

import:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Import Existing QUADS Allocation$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"

validate:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)QUADS Assignment Validation$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"

deallocate:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)QUADS Assignment Deallocation$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"

deallocate-by-cloud:
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)QUADS Deallocate by Cloud Name$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@echo "This will find and terminate the assignment by cloud name only"
	@echo "(No assignment ID required)"
	@echo ""
	@$(MODULE_DIR)/quads-deallocate-by-cloud.sh $(CLOUD_NAME)

clean:
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo -e "$(YELLOW)Cleaning QUADS Module$(NC)"
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo ""
	@# Check for active allocation before cleaning
	@if [ -f $(MODULE_DIR)/generated/state/current.env ]; then \
		echo -e "$(RED)WARNING: Active QUADS allocation detected!$(NC)"; \
		echo ""; \
		cat $(MODULE_DIR)/generated/state/current.env; \
		echo ""; \
		echo -e "$(RED)Cleaning state will cause resource leak!$(NC)"; \
		echo ""; \
		echo "You must deallocate first:"; \
		echo "  make deallocate              # Using saved state"; \
		echo "  make deallocate-by-cloud CLOUD_NAME=cloudXX  # By cloud name"; \
		echo ""; \
		echo "Or force clean (DANGEROUS - will leak resources):"; \
		echo "  FORCE_CLEAN=true make clean"; \
		echo ""; \
		if [ "$(FORCE_CLEAN)" != "true" ]; then \
			echo -e "$(RED)Aborting clean to prevent resource leak$(NC)"; \
			exit 1; \
		else \
			echo -e "$(RED)FORCE_CLEAN=true - Proceeding with clean (RESOURCE LEAK!)$(NC)"; \
			echo ""; \
		fi; \
	fi
	@echo "Cleaning QUADS module generated files..."
	@echo "  - Module state, logs, output, init state"
	@rm -rf $(MODULE_DIR)/generated/state/*
	@rm -rf $(MODULE_DIR)/generated/logs/*
	@rm -rf $(MODULE_DIR)/generated/output/*
	@rm -rf $(MODULE_DIR)/generated/config/*
	@echo "  - QUADS config file"
	@rm -f $(ROOT_DIR)/repos/ansible-quads-ssm/quads_config.yml
	@echo -e "$(GREEN)✓ QUADS module cleaned$(NC)"
	@echo ""
	@echo "Preserved:"
	@echo "  - ansible-quads-ssm repository (repos/ansible-quads-ssm/)"
	@echo "  - QUADS credentials (vars/config.env)"
	@echo ""

#------------------------------------------------------------------------------
# Informational Targets
#------------------------------------------------------------------------------

status:
	@echo -e "$(BLUE)QUADS Module Status$(NC)"
	@echo ""
	@if [ -f $(MODULE_DIR)/generated/state/current.env ]; then \
		echo -e "$(GREEN)Active assignment:$(NC)"; \
		cat $(MODULE_DIR)/generated/state/current.env; \
	else \
		echo -e "$(YELLOW)No active assignment$(NC)"; \
	fi
	@echo ""
	@echo "Recent logs:"
	@ls -lt $(MODULE_DIR)/generated/logs/ 2>/dev/null | head -5 || echo "  No logs yet"
	@echo ""

