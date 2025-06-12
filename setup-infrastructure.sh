#!/bin/bash

# WordPress Containerized Client Management System
# Infrastructure Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    log_info "Checking system requirements..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm get-docker.sh
    fi
    
    # Install Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        log_info "Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    # Install required tools
    apt-get update
    apt-get install -y git apache2-utils openssl
    
    log_info "Requirements installed"
}

setup_directories() {
    log_info "Setting up directory structure..."
    
    # Load environment variables
    if [[ ! -f .env ]]; then
        log_error ".env file not found. Please copy .env.template to .env and configure it."
        exit 1
    fi
    
    source .env
    
    # Create directories
    mkdir -p "$INFRASTRUCTURE_PATH"
    mkdir -p "$CLIENTS_PATH"
    mkdir -p "$BACKUPS_PATH"
    mkdir -p ./traefik/dynamic
    mkdir -p ./acme
    mkdir -p /var/log/deployments
    
    # Set permissions
    chmod 600 ./acme
    chmod 755 "$CLIENTS_PATH"
    chmod 755 /var/log/deployments
    
    log_info "Directories created"
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    # Install and configure UFW
    apt-get install -y ufw
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow "${WEBHOOK_PORT:-9000}/tcp"
    ufw --force enable
    
    log_info "Firewall configured"
}

setup_docker_network() {
    log_info "Setting up Docker network..."
    
    if ! docker network ls | grep -q traefik; then
        docker network create traefik
    fi
    
    log_info "Docker network ready"
}

deploy_traefik() {
    log_info "Deploying Traefik..."
    
    # Stop existing Traefik
    docker-compose -f docker-compose.traefik.yml down 2>/dev/null || true
    
    # Deploy Traefik
    docker-compose -f docker-compose.traefik.yml up -d
    
    # Wait and verify
    sleep 10
    if ! docker ps | grep -q traefik; then
        log_error "Traefik deployment failed"
        exit 1
    fi
    
    log_info "Traefik deployed successfully"
}

install_management_scripts() {
    log_info "Installing management scripts..."
    
    # Make scripts executable
    chmod +x ./manage-client.sh
    chmod +x ./webhook-receiver.sh
    chmod +x ./setup-traefik-middleware.sh
    
    # Create symlinks
    ln -sf "$(pwd)/manage-client.sh" /usr/local/bin/manage-client
    ln -sf "$(pwd)/webhook-receiver.sh" /usr/local/bin/webhook-receiver
    ln -sf "$(pwd)/setup-traefik-middleware.sh" /usr/local/bin/traefik-middleware
    
    log_info "Management scripts installed"
}

setup_webhook_service() {
    log_info "Setting up webhook service..."
    
    cat > /etc/systemd/system/webhook-receiver.service << EOF
[Unit]
Description=WordPress Client Webhook Receiver
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/webhook-receiver.sh start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable webhook-receiver
    systemctl start webhook-receiver
    
    log_info "Webhook service installed and started"
}

setup_middleware_system() {
    log_info "Setting up middleware system..."
    
    # Initialize middleware
    ./setup-traefik-middleware.sh init
    
    # Restart Traefik to load middleware
    docker-compose -f docker-compose.traefik.yml restart
    
    log_info "Middleware system ready"
}

show_completion_message() {
    log_info "✅ WordPress Infrastructure Setup Complete!"
    echo ""
    echo "🚀 Quick Start:"
    echo "1. Update manage-client.sh with your starter repository URL"
    echo "2. Create your first environment:"
    echo "   manage-client create-environment mycompany production"
    echo "3. Deploy it:"
    echo "   cd /opt/clients/mycompany/production"
    echo "   docker-compose up -d && ./setup.sh"
    echo ""
    echo "📊 System Access:"
    echo "- Traefik Dashboard: https://traefik.${DOMAIN}"
    echo "- Webhook Endpoint: https://$(hostname -f):${WEBHOOK_PORT:-9000}/webhook/CLIENT/ENV"
    echo ""
    echo "🔧 Management Commands:"
    echo "- manage-client status"
    echo "- webhook-receiver status"
    echo "- traefik-middleware list"
    echo ""
    echo "📋 System is ready for client environments!"
}

# Main execution
main() {
    log_info "Starting WordPress Infrastructure Setup..."
    
    check_requirements
    setup_directories
    configure_firewall
    setup_docker_network
    deploy_traefik
    install_management_scripts
    setup_webhook_service
    setup_middleware_system
    show_completion_message
}

# Run it
main "$@"