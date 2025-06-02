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
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        systemctl enable docker
        systemctl start docker
        rm get-docker.sh
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        log_warn "Docker Compose not found. Installing Docker Compose..."
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    
    log_info "Requirements check completed"
}

setup_directories() {
    log_info "Setting up directory structure..."
    
    # Load environment variables
    if [[ -f .env ]]; then
        source .env
    else
        log_error ".env file not found. Please copy .env.template to .env and configure it."
        exit 1
    fi
    
    # Create main directories
    mkdir -p "$INFRASTRUCTURE_PATH"
    mkdir -p "$CLIENTS_PATH"
    mkdir -p "$BACKUPS_PATH"
    mkdir -p ./traefik
    mkdir -p ./acme
    
    # Set permissions for ACME storage
    chmod 600 ./acme
    
    log_info "Directory structure created"
}

configure_firewall() {
    log_info "Configuring firewall..."
    
    # Install ufw if not present
    if ! command -v ufw &> /dev/null; then
        apt-get update
        apt-get install -y ufw
    fi
    
    # Reset firewall rules
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (be careful here!)
    ufw allow ssh
    
    # Allow HTTP and HTTPS
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable firewall
    ufw --force enable
    
    log_info "Firewall configured"
}

setup_docker_network() {
    log_info "Setting up Docker network..."
    
    # Create traefik network if it doesn't exist
    if ! docker network ls | grep -q traefik; then
        docker network create traefik
        log_info "Traefik network created"
    else
        log_info "Traefik network already exists"
    fi
}

deploy_traefik() {
    log_info "Deploying Traefik..."
    
    # Check if .env file exists
    if [[ ! -f .env ]]; then
        log_error ".env file not found"
        exit 1
    fi
    
    # Stop existing Traefik if running
    if docker ps | grep -q traefik; then
        log_info "Stopping existing Traefik container..."
        docker-compose -f docker-compose.traefik.yml down
    fi
    
    # Deploy Traefik
    docker-compose -f docker-compose.traefik.yml up -d
    
    # Wait for Traefik to be ready
    log_info "Waiting for Traefik to be ready..."
    sleep 10
    
    # Check if Traefik is running
    if docker ps | grep -q traefik; then
        log_info "Traefik deployed successfully"
    else
        log_error "Traefik deployment failed"
        exit 1
    fi
}

show_completion_message() {
    log_info "Infrastructure setup completed!"
    echo ""
    echo "Next steps:"
    echo "1. Access Traefik dashboard at: https://traefik.${DOMAIN}"
    echo "2. Verify SSL certificates are being generated"
    echo "3. Proceed to Phase 2: Starter Repository Development"
    echo ""
    echo "Useful commands:"
    echo "- View Traefik logs: docker logs traefik"
    echo "- Restart Traefik: docker-compose -f docker-compose.traefik.yml restart"
    echo "- Check running containers: docker ps"
}

# Main execution
main() {
    log_info "Starting WordPress Infrastructure Setup..."
    
    check_requirements
    setup_directories
    configure_firewall
    setup_docker_network
    deploy_traefik
    show_completion_message
}

# Run main function
main "$@"