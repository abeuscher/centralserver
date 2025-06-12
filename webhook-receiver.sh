#!/bin/bash

# WordPress Containerized Client Management System
# Webhook Receiver for Automated Deployments

set -e

# Configuration
CLIENTS_BASE_PATH="${CLIENTS_PATH:-/opt/clients}"
LOG_BASE_PATH="/var/log/deployments"
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') $1"; }

mkdir -p "$LOG_BASE_PATH"

# HTTP Response function
send_response() {
    local status="$1" message="$2"
    local status_text="OK"
    case "$status" in
        400) status_text="Bad Request" ;;
        404) status_text="Not Found" ;;
        500) status_text="Internal Server Error" ;;
    esac
    
    echo "HTTP/1.1 $status $status_text"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\": \"$status\", \"message\": \"$message\"}"
}

# Process deployment
process_deployment() {
    local client_name="$1" environment="$2"
    local env_path="${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    local log_file="${LOG_BASE_PATH}/${client_name}-${environment}-$(date +%Y%m%d-%H%M%S).log"
    
    exec > >(tee -a "$log_file") 2>&1
    
    log_info "Starting deployment for ${client_name}/${environment}"
    
    if [[ ! -d "$env_path" ]]; then
        log_error "Environment not found: $env_path"
        send_response 404 "Environment not found"
        return 1
    fi
    
    cd "$env_path"
    
    if [[ ! -d ".git" ]]; then
        log_error "Not a git repository"
        send_response 400 "Not a git repository"
        return 1
    fi
    
    # Git pull
    log_info "Pulling latest changes..."
    if git pull origin HEAD; then
        log_info "Git pull successful"
    else
        log_error "Git pull failed"
        send_response 500 "Git pull failed"
        return 1
    fi
    
    # Build process
    if [[ -f "package.json" ]]; then
        log_info "Running build process..."
        
        if [[ ! -d "node_modules" ]]; then
            log_info "Installing dependencies..."
            if ! npm install; then
                log_error "npm install failed"
                send_response 500 "Build failed - dependencies"
                return 1
            fi
        fi
        
        if ! npm run production; then
            log_error "Build failed"
            send_response 500 "Build failed"
            return 1
        fi
        
        log_info "Build completed"
    fi
    
    # Fix permissions
    local webserver_container="${client_name}-webserver-${environment}"
    docker exec "$webserver_container" chown -R www-data:www-data /var/www/html 2>/dev/null || log_warn "Permission update failed"
    
    log_info "Deployment completed successfully"
    send_response 200 "Deployment successful"
}

# HTTP request handler
handle_request() {
    local request_line headers=""
    read -r request_line
    
    # Read headers
    while IFS= read -r line; do
        line=$(echo "$line" | tr -d '\r')
        [[ -z "$line" ]] && break
        headers="$headers$line\n"
    done
    
    # Parse URL
    local path=$(echo "$request_line" | cut -d' ' -f2)
    
    if [[ "$path" =~ ^/webhook/([^/]+)/([^/]+)$ ]]; then
        local client_name="${BASH_REMATCH[1]}"
        local environment="${BASH_REMATCH[2]}"
        
        log_info "Webhook received: ${client_name}/${environment}"
        process_deployment "$client_name" "$environment"
    else
        log_error "Invalid path: $path"
        send_response 404 "Invalid webhook path"
    fi
}

# Start webhook server
start_server() {
    log_info "Starting webhook server on port $WEBHOOK_PORT"
    
    while true; do
        { handle_request; } | nc -l -p $WEBHOOK_PORT
        sleep 0.1
    done
}

# Generate GitHub workflow
generate_workflow() {
    local client_name="$1" environment="$2" webhook_url="$3"
    
    cat << EOF
name: Deploy to ${environment^}

on:
  push:
    branches: 
      - ${environment}
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Deploy to ${environment}
      run: |
        curl -X POST \\
          -H "Content-Type: application/json" \\
          -d '{"ref": "\${{ github.ref }}", "repository": "\${{ github.repository }}"}' \\
          ${webhook_url}/webhook/${client_name}/${environment}
          
    - name: Deployment Status
      run: echo "Deployment triggered for ${client_name}/${environment}"
EOF
}

# Show deployment logs
show_logs() {
    local client_name="$1" environment="$2" lines="${3:-50}"
    local pattern="${LOG_BASE_PATH}/${client_name}-${environment}-*.log"
    local latest=$(ls -t $pattern 2>/dev/null | head -1)
    
    if [[ -f "$latest" ]]; then
        log_info "Last $lines lines from: $(basename "$latest")"
        tail -n "$lines" "$latest"
    else
        log_warn "No logs found for ${client_name}/${environment}"
    fi
}

# Test deployment
test_deployment() {
    local client_name="$1" environment="$2"
    log_info "Testing deployment for ${client_name}/${environment}"
    process_deployment "$client_name" "$environment"
}

# Show status
show_status() {
    log_info "Webhook Server Status"
    echo ""
    
    if pgrep -f "webhook-receiver.sh start" > /dev/null; then
        log_info "✅ Webhook server running (PID: $(pgrep -f "webhook-receiver.sh start"))"
    else
        log_warn "❌ Webhook server not running"
    fi
    
    echo ""
    log_info "Recent Deployments:"
    if [[ -d "$LOG_BASE_PATH" ]]; then
        ls -lt "$LOG_BASE_PATH"/*.log 2>/dev/null | head -5 || echo "  No logs found"
    fi
    
    echo ""
    if netstat -ln 2>/dev/null | grep -q ":$WEBHOOK_PORT "; then
        log_info "✅ Port $WEBHOOK_PORT listening"
    else
        log_warn "❌ Port $WEBHOOK_PORT not listening"
    fi
}

# Install systemd service
install_service() {
    log_info "Installing webhook receiver service..."
    
    cat > /etc/systemd/system/webhook-receiver.service << EOF
[Unit]
Description=WordPress Client Webhook Receiver
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$(dirname "$(realpath "$0")")
ExecStart=$(realpath "$0") start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable webhook-receiver
    
    log_info "Service installed. Start with: systemctl start webhook-receiver"
}

# Main command handling
case "$1" in
    "start") start_server ;;
    "generate-workflow")
        [[ $# -lt 4 ]] && { echo "Usage: $0 generate-workflow CLIENT ENV WEBHOOK_URL"; exit 1; }
        generate_workflow "$2" "$3" "$4"
        ;;
    "logs")
        [[ $# -lt 3 ]] && { echo "Usage: $0 logs CLIENT ENV [LINES]"; exit 1; }
        show_logs "$2" "$3" "$4"
        ;;
    "test")
        [[ $# -lt 3 ]] && { echo "Usage: $0 test CLIENT ENV"; exit 1; }
        test_deployment "$2" "$3"
        ;;
    "status") show_status ;;
    "install-service") install_service ;;
    *)
        echo "Webhook Receiver for WordPress Client Management"
        echo ""
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  start                           Start webhook server"
        echo "  generate-workflow CLIENT ENV URL   Generate GitHub Actions workflow"
        echo "  logs CLIENT ENV [LINES]         Show deployment logs"
        echo "  test CLIENT ENV                 Test deployment"
        echo "  status                          Show server status"
        echo "  install-service                 Install systemd service"
        exit 1
        ;;
esac