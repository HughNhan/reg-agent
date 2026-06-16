# Crucible Module Makefile

SHELL := /bin/bash
.SHELLFLAGS := -e -o pipefail -c
.PHONY: help configure init install clean status

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
	@echo -e "$(BLUE)Crucible Module - Performance Benchmark Framework$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Setup:"
	@echo "  configure    Interactive configuration helper (updates vars/config.json)"
	@echo "  init         Initialize Crucible module"
	@echo ""
	@echo "Operations:"
	@echo "  install      Install Crucible on controller host"
	@echo ""
	@echo "Utilities:"
	@echo "  status       Show Crucible installation status"
	@echo "  clean        Remove Crucible state"
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
		echo -e "$(GREEN)✓ Crucible module already initialized (idempotent - skipping)$(NC)"; \
		echo ""; \
		echo "To force re-initialization:"; \
		echo "  rm $(MODULE_DIR)/generated/state/init.env"; \
		echo "  make init"; \
		echo ""; \
	else \
		echo ""; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo -e "$(BLUE)Crucible Module Initialization$(NC)"; \
		echo -e "$(BLUE)=====================================$(NC)"; \
		echo ""; \
		echo "# Crucible module initialization state" > $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_COMPLETED=true" >> $(MODULE_DIR)/generated/state/init.env; \
		echo "INIT_TIMESTAMP=$$(date +%Y%m%d_%H%M%S)" >> $(MODULE_DIR)/generated/state/init.env; \
		echo ""; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo -e "$(GREEN)✓ Crucible module initialized$(NC)"; \
		echo -e "$(GREEN)=====================================$(NC)"; \
		echo ""; \
		echo "Note: Crucible will be installed on the controller host during deployment."; \
		echo "See modules/crucible/CLAUDE.md for installation details."; \
		echo ""; \
	fi

#------------------------------------------------------------------------------
# Install Target
#------------------------------------------------------------------------------

install:
	@echo ""
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo -e "$(BLUE)Installing Crucible$(NC)"
	@echo -e "$(BLUE)=====================================$(NC)"
	@echo ""
	@$(ROOT_DIR)/modules/phase-3-crucible-setup.sh

#------------------------------------------------------------------------------
# Clean
#------------------------------------------------------------------------------

clean:
	@echo ""
	@echo -e "$(BLUE)=========================================$(NC)"
	@echo -e "$(BLUE)Cleaning Phase 3: Crucible$(NC)"
	@echo -e "$(BLUE)=========================================$(NC)"
	@echo ""
	@echo "This will remove:"
	@echo "  - Crucible state from vars/state.env"
	@echo ""
	@echo -e "$(GREEN)Note: Crucible installation on controller host will NOT be deleted$(NC)"
	@echo ""
	@# Remove Crucible state
	@if [ -f "$(ROOT_DIR)/vars/state.env" ]; then \
		if grep -q "CRUCIBLE_PATH" $(ROOT_DIR)/vars/state.env; then \
			source $(ROOT_DIR)/vars/state.env; \
			echo -e "$(YELLOW)Crucible installation preserved at: $$CRUCIBLE_PATH$(NC)"; \
			echo ""; \
		fi; \
		sed -i '/CRUCIBLE_PATH=/d' $(ROOT_DIR)/vars/state.env 2>/dev/null || true; \
		sed -i '/CRUCIBLE_INSTALLED=/d' $(ROOT_DIR)/vars/state.env 2>/dev/null || true; \
		sed -i '/CRUCIBLE_INSTALL_TIME=/d' $(ROOT_DIR)/vars/state.env 2>/dev/null || true; \
		echo -e "$(GREEN)✓ Crucible state removed from vars/state.env$(NC)"; \
	else \
		echo -e "$(YELLOW)⚠ No state file found$(NC)"; \
	fi
	@echo ""
	@echo -e "$(GREEN)=========================================$(NC)"
	@echo -e "$(GREEN)✅ Phase 3 Cleaned (installation preserved)$(NC)"
	@echo -e "$(GREEN)=========================================$(NC)"
	@echo ""

#------------------------------------------------------------------------------
# Status
#------------------------------------------------------------------------------

status:
	@echo ""
	@echo -e "$(BLUE)Crucible Status$(NC)"
	@echo "────────────────────────────────────────"
	@if [ -f "$(ROOT_DIR)/vars/state.env" ]; then \
		if grep -q "CRUCIBLE_INSTALLED=true" $(ROOT_DIR)/vars/state.env; then \
			source $(ROOT_DIR)/vars/state.env; \
			echo -e "Status:      $(GREEN)✓ Installed$(NC)"; \
			echo "Path:        $$CRUCIBLE_PATH"; \
			[ -n "$$CRUCIBLE_INSTALL_TIME" ] && echo "Installed:   $$CRUCIBLE_INSTALL_TIME" || true; \
		else \
			echo -e "Status:      $(RED)✗ Not installed$(NC)"; \
		fi; \
	else \
		echo -e "Status:      $(RED)✗ Not installed$(NC)"; \
	fi
	@echo ""
