#!/bin/bash
# Shared logging functions for all phases
# Usage: source modules/lib/logging.sh

# Initialize logging for a phase
# Arguments: $1 = module_name, $2 = phase_name
init_logging() {
    local module_name="$1"
    local phase_name="$2"

    LOG_DIR="${REG_AGENT_ROOT}/modules/${module_name}/logs"
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/${phase_name}-$(date +%Y%m%d-%H%M%S).log"

    # Create 'latest' symlink to this log file
    cd "${LOG_DIR}"
    if [ -L "latest" ]; then
        rm "latest"
    fi
    ln -s "$(basename ${LOG_FILE})" "latest"
    cd - > /dev/null

    # Log initialization
    log "Starting ${phase_name}"
    log "Log file: ${LOG_FILE}"
    log "Latest log symlink: ${LOG_DIR}/latest"
}

# Log message to file only (no console output)
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" >> "${LOG_FILE}"
}

# Log message to file only (no console output)
log_cmd() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $*" >> "${LOG_FILE}"
}

# Log error and exit
log_error() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ERROR: $*" | tee -a "${LOG_FILE}"
}

# Log completion
log_complete() {
    log "========================================"
    log "✅ $* Complete"
    log "========================================"
    log "Log file saved at: ${LOG_FILE}"
    log "========================================"
}
