#!/bin/bash
# LLM Server Control Script
# Start, stop, and manage the reg-agent LLM server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG_AGENT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PID_FILE="${SCRIPT_DIR}/.llm-server.pid"
LOG_FILE="${SCRIPT_DIR}/llm-server.log"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Helper functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if server is running
is_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            return 0
        else
            # Stale PID file
            rm -f "$PID_FILE"
            return 1
        fi
    fi
    return 1
}

# Start server
start_server() {
    if is_running; then
        warn "Server already running (PID: $(cat $PID_FILE))"
        return 1
    fi

    info "Starting LLM server..."

    # Check if config exists
    if [ ! -f "$CONFIG_FILE" ]; then
        error "Configuration not found: $CONFIG_FILE"
        exit 1
    fi

    # Activate Python environment
    if [ -f "${REG_AGENT_ROOT}/.venv/bin/activate" ]; then
        source "${REG_AGENT_ROOT}/.venv/bin/activate"
    else
        warn "Python virtualenv not found - using system Python"
    fi

    # Check dependencies
    if ! python3 -c "import flask" 2>/dev/null; then
        error "Flask not installed. Run: pip install -r ../requirements.txt"
        exit 1
    fi

    # Start server in background
    cd "$SCRIPT_DIR"
    nohup python3 server.py > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!

    # Save PID
    echo "$SERVER_PID" > "$PID_FILE"

    # Wait a bit and check if it's running
    sleep 2
    if is_running; then
        info "Server started successfully (PID: $SERVER_PID)"
        info "Logs: $LOG_FILE"

        # Get server config
        BACKEND=$(grep -A1 "^backend:" "$CONFIG_FILE" | grep "type:" | awk '{print $2}')
        PORT=$(grep -A2 "^server:" "$CONFIG_FILE" | grep "port:" | awk '{print $2}')

        info "Backend: $BACKEND"
        info "Listening on: http://0.0.0.0:${PORT}"
        echo ""
        info "Test with: curl http://localhost:${PORT}/health"
    else
        error "Server failed to start. Check logs: $LOG_FILE"
        exit 1
    fi
}

# Stop server
stop_server() {
    if ! is_running; then
        warn "Server not running"
        return 1
    fi

    PID=$(cat "$PID_FILE")
    info "Stopping LLM server (PID: $PID)..."

    kill "$PID"

    # Wait for shutdown
    for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            rm -f "$PID_FILE"
            info "Server stopped"
            return 0
        fi
        sleep 1
    done

    # Force kill if still running
    warn "Server did not stop gracefully, forcing..."
    kill -9 "$PID" 2>/dev/null || true
    rm -f "$PID_FILE"
    info "Server stopped (forced)"
}

# Restart server
restart_server() {
    info "Restarting LLM server..."
    stop_server || true
    sleep 2
    start_server
}

# Show status
show_status() {
    if is_running; then
        PID=$(cat "$PID_FILE")
        info "Server is running (PID: $PID)"

        # Get config
        BACKEND=$(grep -A1 "^backend:" "$CONFIG_FILE" | grep "type:" | awk '{print $2}')
        PORT=$(grep -A2 "^server:" "$CONFIG_FILE" | grep "port:" | awk '{print $2}')

        echo ""
        echo "Backend: $BACKEND"
        echo "Port: $PORT"
        echo "Logs: $LOG_FILE"
        echo "PID file: $PID_FILE"

        # Try health check
        echo ""
        info "Health check:"
        curl -s "http://localhost:${PORT}/health" | python3 -m json.tool 2>/dev/null || echo "Health check failed"
    else
        warn "Server is not running"
    fi
}

# Show logs
show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        warn "No log file found"
        return 1
    fi

    tail -f "$LOG_FILE"
}

# Main command router
case "${1:-}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the LLM server"
        echo "  stop    - Stop the LLM server"
        echo "  restart - Restart the LLM server"
        echo "  status  - Show server status"
        echo "  logs    - Tail server logs"
        exit 1
        ;;
esac
