# Regulus Module Makefile
# Phase 4: Regulus configuration and testing

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

MODULE_DIR := $(shell pwd)
ROOT_DIR := $(shell cd ../.. && pwd)
VARS_DIR := $(ROOT_DIR)/vars

# Colors
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;36m
NC := \033[0m

.PHONY: help configure init clean status install test check configure-tests

#------------------------------------------------------------------------------
# Help Target
#------------------------------------------------------------------------------

help:
	@echo ""
	@echo -e "$(BLUE)Regulus Module - Performance Test Framework$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Phase 4 - Setup:"
	@echo "  configure           Interactive configuration helper (updates vars/config.json)"
	@echo "  check               Run dependency checks only (no installation)"
	@echo "  install             Install and setup Regulus on target host"
	@echo "  configure-tests     Interactively select test jobs to run"
	@echo ""
	@echo "Phase 5 - Execute Tests:"
	@echo "  test                Execute run_cpt.sh (handles all initialization and testing)"
	@echo ""
	@echo "Utilities:"
	@echo "  status              Show Regulus configuration status"
	@echo "  clean               Clean Regulus configuration"
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
		echo -e "$(GREEN)✓ Regulus module already initialized (idempotent - skipping)$(NC)"; \
		echo ""; \
		echo "To force re-initialization:"; \
		echo "  rm $(MODULE_DIR)/generated/state/init.env"; \
		echo "  make init"; \
		echo ""; \
	else \
		echo ""; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo -e "$(BLUE)Regulus Module Initialization$(NC)"; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo ""; \
		echo "# Regulus module initialization state" > $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_COMPLETED=true" >> $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_TIMESTAMP=$$(date +%Y%m%d_%H%M%S)" >> $(MODULE_DIR)/generated/state/init.env; \
		echo ""; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo -e "$(GREEN)✓ Regulus Module Initialized$(NC)"; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo ""; \
	fi

#------------------------------------------------------------------------------
# Status Target
#------------------------------------------------------------------------------

status:
	@echo ""
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Regulus Module Status$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@if [ -f "$(VARS_DIR)/config.json" ]; then \
		echo "Configuration:"; \
		echo ""; \
		source $(VARS_DIR)/config.json 2>/dev/null; \
		if [ -n "$$REGULUS_INSTALL_SUBDIR" ]; then \
			echo "  Installation path: /root/$$REGULUS_INSTALL_SUBDIR/cpt-regulus-<datetime>"; \
		else \
			echo "  Installation path: /root/cpt-regulus-<datetime>"; \
		fi; \
		if [ -n "$$REGULUS_TEST_SUITE" ]; then \
			echo "  Test suite: $$REGULUS_TEST_SUITE"; \
		fi; \
		if [ -n "$$REGULUS_DURATION" ]; then \
			echo "  Duration: $$REGULUS_DURATION"; \
		fi; \
		echo ""; \
	else \
		echo -e "$(YELLOW)No configuration found$(NC)"; \
		echo "Run: make init"; \
		echo ""; \
	fi
	@if [ -f "$(VARS_DIR)/state.env" ]; then \
		source $(VARS_DIR)/state.env 2>/dev/null; \
		if [ -n "$$REGULUS_PATH" ]; then \
			echo "Deployment:"; \
			echo "  Path: $$REGULUS_PATH"; \
			if [ -n "$$REGULUS_INSTALLED" ]; then \
				echo "  Installed: $$REGULUS_INSTALLED"; \
			fi; \
			if [ -n "$$REGULUS_INSTALL_TIME" ]; then \
				echo "  Install time: $$REGULUS_INSTALL_TIME"; \
			fi; \
			echo ""; \
		fi; \
	fi

#------------------------------------------------------------------------------
# Clean Target
#------------------------------------------------------------------------------

clean:
	@echo ""
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo -e "$(YELLOW)Cleaning Regulus Module$(NC)"
	@echo -e "$(YELLOW)=====================================$(NC)"
	@echo ""
	@echo "This will remove:"
	@echo "  - Regulus configuration from vars/config.json"
	@echo "  - Regulus state from vars/state.env"
	@echo ""
	@echo -e "$(GREEN)Note: Regulus installations on target host will NOT be deleted$(NC)"
	@echo -e "$(GREEN)      (preserving invaluable test data)$(NC)"
	@echo ""
	@read -p "Continue? (y/N): " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo ""; \
		echo "Cleaning Regulus configuration..."; \
		if [ -f "$(VARS_DIR)/config.json" ]; then \
			sed -i '/^REGULUS_INSTALL_SUBDIR=/d' $(VARS_DIR)/config.json 2>/dev/null || true; \
			sed -i '/^REGULUS_TEST_SUITE=/d' $(VARS_DIR)/config.json 2>/dev/null || true; \
			sed -i '/^REGULUS_DURATION=/d' $(VARS_DIR)/config.json 2>/dev/null || true; \
			echo -e "$(GREEN)✓ Configuration cleaned$(NC)"; \
		fi; \
		if [ -f "$(VARS_DIR)/state.env" ]; then \
			source $(VARS_DIR)/state.env 2>/dev/null; \
			if [ -n "$$REGULUS_PATH" ]; then \
				echo -e "$(YELLOW)Note: Regulus installation preserved at: $$REGULUS_PATH$(NC)"; \
			fi; \
			sed -i '/^REGULUS_PATH=/d' $(VARS_DIR)/state.env 2>/dev/null || true; \
			sed -i '/^REGULUS_INSTALLED=/d' $(VARS_DIR)/state.env 2>/dev/null || true; \
			sed -i '/^REGULUS_INSTALL_TIME=/d' $(VARS_DIR)/state.env 2>/dev/null || true; \
			echo -e "$(GREEN)✓ State cleaned$(NC)"; \
		fi; \
		echo ""; \
		echo -e "$(GREEN)✓ Regulus module cleaned (installations preserved)$(NC)"; \
		echo ""; \
	else \
		echo "Cancelled"; \
	fi

#------------------------------------------------------------------------------
# Install Target
#------------------------------------------------------------------------------

install:
	@echo ""
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Installing Regulus$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@export REGULUS_TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	$(ROOT_DIR)/modules/phase-4-regulus-setup.sh

#------------------------------------------------------------------------------
# Check Target (Dependency Checks Only)
#------------------------------------------------------------------------------

check:
	@echo ""
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Regulus Dependency Checks$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@echo "Running dependency checks without installation..."
	@echo ""
	@export CHECK_ONLY=true; \
	export REGULUS_TIMESTAMP=$$(date +%Y%m%d-%H%M%S); \
	$(ROOT_DIR)/modules/phase-4-regulus-setup.sh

#------------------------------------------------------------------------------
# Test Target
#------------------------------------------------------------------------------

test:
	@echo ""
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Running Regulus Tests$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@$(ROOT_DIR)/modules/phase-5-regulus-run.sh

#------------------------------------------------------------------------------
# Configure Tests Target
#------------------------------------------------------------------------------

configure-tests:
	@echo ""
	@$(MODULE_DIR)/configure-tests.sh
