#!/bin/bash

# WordPress Containerized Client Management System
# Environment Management Script - Phase 3

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - UPDATE THESE VALUES
STARTER_REPO_URL="https://github.com/yourusername/wordpress-starter.git"
DEFAULT_DOMAIN="yourdomain.com"

# Load from environment if available
if [[ -f .env ]]; then
    source .env
    STARTER_REPO_URL="${STARTER_REPO_URL:-$STARTER_REPO_URL}"
    DEFAULT_DOMAIN="${DEFAULT_DOMAIN:-$DEFAULT_DOMAIN}"
fi

CLIENTS_BASE_PATH="${CLIENTS_PATH:-/opt/clients}"

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

show_usage() {
    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  create-environment CLIENT_NAME ENVIRONMENT [CUSTOM_DOMAIN]"
    echo "  list-all"
    echo "  list-environments CLIENT_NAME"
    echo "  status"
    echo "  remove-environment CLIENT_NAME ENVIRONMENT"
    echo ""
    echo "Examples:"
    echo "  $0 create-environment acme production"
    echo "  $0 create-environment acme staging"
    echo "  $0 create-environment acme hotfix custom.acme.com"
    echo "  $0 list-environments acme"
    echo "  $0 remove-environment acme staging"
}

validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] || [[ ${#name} -lt 2 || ${#name} -gt 50 ]]; then
        return 1
    fi
}

generate_secure_password() { openssl rand -base64 32 | tr -d "=+/" | cut -c1-25; }
generate_deployment_token() { openssl rand -hex 32; }

generate_domain() {
    local client_name="$1" environment="$2" custom_domain="$3"
    
    if [[ -n "$custom_domain" ]]; then
        echo "$custom_domain"
    elif [[ "$environment" == "production" ]]; then
        echo "${client_name}.${DEFAULT_DOMAIN}"
    elif [[ "$environment" == "staging" ]]; then
        echo "staging.${client_name}.${DEFAULT_DOMAIN}"
    else
        echo "${environment}.${client_name}.${DEFAULT_DOMAIN}"
    fi
}

create_client_structure() {
    local client_name="$1" environment="$2"
    local client_path="${CLIENTS_BASE_PATH}/${client_name}"
    local env_path="${client_path}/${environment}"
    
    log_info "Creating directory structure for ${client_name}/${environment}..."
    
    mkdir -p "$env_path"
    mkdir -p "${client_path}/shared/uploads-sync"
    mkdir -p "${client_path}/shared/backups"
    mkdir -p "${client_path}/shared/tokens"
    
    if [[ ! -f "${client_path}/.client-config" ]]; then
        cat > "${client_path}/.client-config" << EOF
CLIENT_NAME=$client_name
CREATED_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    fi
}

generate_environment_config() {
    local client_name="$1" environment="$2" domain="$3"
    local env_path="${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    
    local db_password=$(generate_secure_password)
    local wp_admin_password=$(generate_secure_password)
    local deploy_token=$(generate_deployment_token)
    local staging_password=$(generate_secure_password)
    
    log_info "Generating environment configuration..."
    
    cat > "${env_path}/.env" << EOF
# Environment Configuration
CLIENT_NAME=$client_name
ENVIRONMENT=$environment
WP_DOMAIN=$domain
WP_TITLE=${client_name^} Website

# Container Configuration
CONTAINER_PREFIX=${client_name}

# Database Configuration
MYSQL_DATABASE=${client_name}_${environment}
MYSQL_USER=${client_name}_user
MYSQL_PASSWORD=$db_password
MYSQL_ROOT_PASSWORD=$db_password
MYSQL_HOST=database

# WordPress Configuration
WP_ADMIN_USER=admin
WP_ADMIN_PASSWORD=$wp_admin_password
WP_ADMIN_EMAIL=admin@${domain}

# File Paths
DOCUMENT_ROOT=./public_html
PHP_INI=./config/php/php.ini
LOG_DIR=./logs/apache2
MYSQL_DATA_DIR=./data/mysql
MYSQL_LOG_DIR=./logs/mysql

# Security
DEPLOYMENT_TOKEN=$deploy_token
STAGING_PASSWORD=$staging_password

# Build Configuration
NODE_ENV=production
REMOVE_DEFAULT_CONTENT=true
WP_TIMEZONE=${DEFAULT_TIMEZONE:-America/New_York}
EOF

    echo "$deploy_token" > "${CLIENTS_BASE_PATH}/${client_name}/shared/tokens/${environment}-deploy.token"
    chmod 600 "${CLIENTS_BASE_PATH}/${client_name}/shared/tokens/${environment}-deploy.token"
    
    echo ""
    log_info "=== Environment Details ==="
    echo "Client: $client_name"
    echo "Environment: $environment" 
    echo "Domain: $domain"
    echo "WordPress Admin: admin / $wp_admin_password"
    [[ "$environment" != "production" ]] && echo "Staging Password: $staging_password"
    echo "Deploy Token: $deploy_token"
    echo "==========================="
    echo ""
}

create_docker_network() {
    local client_name="$1"
    local network_name="${client_name}-network"
    
    if ! docker network ls | grep -q "$network_name"; then
        log_info "Creating Docker network: $network_name"
        docker network create "$network_name"
    fi
}

clone_starter_repository() {
    local client_name="$1" environment="$2"
    local env_path="${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    
    log_info "Cloning starter repository..."
    
    local temp_dir=$(mktemp -d)
    
    if git clone "$STARTER_REPO_URL" "$temp_dir/starter"; then
        cp -r "$temp_dir/starter/." "$env_path/"
        rm -rf "${env_path}/.git"
        rm -rf "$temp_dir"
        log_success "Starter repository cloned"
    else
        log_error "Failed to clone starter repository: $STARTER_REPO_URL"
        rm -rf "$temp_dir"
        return 1
    fi
}

update_docker_compose() {
    local client_name="$1" environment="$2"
    local env_path="${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    local compose_file="${env_path}/docker-compose.yml"
    
    if [[ -f "$compose_file" ]]; then
        log_info "Updating docker-compose.yml for client network..."
        sed -i "s/client-network/${client_name}-network/g" "$compose_file"
    fi
}

create_environment() {
    local client_name="$1" environment="$2" custom_domain="$3"
    
    if ! validate_name "$client_name" || ! validate_name "$environment"; then
        log_error "Invalid client or environment name. Use alphanumeric and hyphens only."
        return 1
    fi
    
    if [[ -d "${CLIENTS_BASE_PATH}/${client_name}/${environment}" ]]; then
        log_error "Environment ${client_name}/${environment} already exists"
        return 1
    fi
    
    local domain=$(generate_domain "$client_name" "$environment" "$custom_domain")
    
    log_info "Creating environment: ${client_name}/${environment} -> $domain"
    
    create_client_structure "$client_name" "$environment"
    generate_environment_config "$client_name" "$environment" "$domain"
    create_docker_network "$client_name"
    
    if ! clone_starter_repository "$client_name" "$environment"; then
        return 1
    fi
    
    update_docker_compose "$client_name" "$environment"
    
    log_success "Environment created successfully!"
    log_info "Next steps:"
    log_info "1. cd ${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    log_info "2. docker-compose up -d"
    log_info "3. ./setup.sh"
}

list_all_environments() {
    log_info "All client environments:"
    echo ""
    
    if [[ ! -d "$CLIENTS_BASE_PATH" ]]; then
        log_warn "No clients directory found"
        return 0
    fi
    
    for client_dir in "$CLIENTS_BASE_PATH"/*; do
        if [[ -d "$client_dir" ]]; then
            local client_name=$(basename "$client_dir")
            echo "📁 Client: $client_name"
            
            for env_dir in "$client_dir"/*; do
                if [[ -d "$env_dir" && "$(basename "$env_dir")" != "shared" ]]; then
                    local env_name=$(basename "$env_dir")
                    local env_file="${env_dir}/.env"
                    
                    if [[ -f "$env_file" ]]; then
                        local domain=$(grep "^WP_DOMAIN=" "$env_file" | cut -d'=' -f2)
                        local setup_status="⏳ Pending"
                        [[ -f "${env_dir}/.setup-complete-${env_name}" ]] && setup_status="✅ Complete"
                        echo "  └── 🌐 $env_name ($domain) - $setup_status"
                    else
                        echo "  └── ⚠️  $env_name (config missing)"
                    fi
                fi
            done
            echo ""
        fi
    done
}

list_client_environments() {
    local client_name="$1"
    local client_path="${CLIENTS_BASE_PATH}/${client_name}"
    
    if [[ ! -d "$client_path" ]]; then
        log_error "Client '$client_name' not found"
        return 1
    fi
    
    log_info "Environments for client: $client_name"
    echo ""
    
    for env_dir in "$client_path"/*; do
        if [[ -d "$env_dir" && "$(basename "$env_dir")" != "shared" ]]; then
            local env_name=$(basename "$env_dir")
            local env_file="${env_dir}/.env"
            
            if [[ -f "$env_file" ]]; then
                local domain=$(grep "^WP_DOMAIN=" "$env_file" | cut -d'=' -f2)
                local containers=$(docker ps --filter "name=${client_name}-" --filter "name=${env_name}" -q | wc -l)
                echo "🌐 Environment: $env_name"
                echo "   Domain: $domain"
                echo "   Containers: $containers running"
                echo "   Status: $([[ -f "${env_dir}/.setup-complete-${env_name}" ]] && echo "✅ Complete" || echo "⏳ Pending")"
                echo ""
            fi
        fi
    done
}

show_status() {
    log_info "System Status"
    echo ""
    
    echo "🐳 Docker:"
    docker system df
    echo ""
    
    echo "📦 Client Containers:"
    docker ps --filter "label=traefik.enable=true" --format "table {{.Names}}\t{{.Status}}" | grep -E "(webserver|mysql)" || echo "None running"
    echo ""
    
    echo "🌐 Client Networks:"
    docker network ls | grep -E "network$" || echo "No client networks"
    echo ""
    
    if [[ -d "$CLIENTS_BASE_PATH" ]]; then
        local clients=$(find "$CLIENTS_BASE_PATH" -maxdepth 1 -type d | tail -n +2 | wc -l)
        local envs=$(find "$CLIENTS_BASE_PATH" -name ".env" | wc -l)
        echo "📊 Summary: $clients clients, $envs environments"
    fi
}

remove_environment() {
    local client_name="$1" environment="$2"
    local env_path="${CLIENTS_BASE_PATH}/${client_name}/${environment}"
    
    if [[ ! -d "$env_path" ]]; then
        log_error "Environment ${client_name}/${environment} not found"
        return 1
    fi
    
    log_warn "This will permanently delete ${client_name}/${environment}"
    read -p "Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Cancelled"
        return 0
    fi
    
    log_info "Removing environment..."
    cd "$env_path" && docker-compose down -v 2>/dev/null || true
    rm -rf "$env_path"
    rm -f "${CLIENTS_BASE_PATH}/${client_name}/shared/tokens/${environment}-deploy.token"
    
    log_success "Environment removed"
}

# Main command handling
case "$1" in
    "create-environment")
        [[ $# -lt 3 ]] && { log_error "Usage: $0 create-environment CLIENT_NAME ENVIRONMENT [CUSTOM_DOMAIN]"; exit 1; }
        create_environment "$2" "$3" "$4"
        ;;
    "list-all") list_all_environments ;;
    "list-environments")
        [[ $# -lt 2 ]] && { log_error "Usage: $0 list-environments CLIENT_NAME"; exit 1; }
        list_client_environments "$2"
        ;;
    "status") show_status ;;
    "remove-environment")
        [[ $# -lt 3 ]] && { log_error "Usage: $0 remove-environment CLIENT_NAME ENVIRONMENT"; exit 1; }
        remove_environment "$2" "$3"
        ;;
    *) show_usage; exit 1 ;;
esac