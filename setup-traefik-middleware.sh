#!/bin/bash

# WordPress Containerized Client Management System
# Traefik Middleware Setup for Security and SEO Protection

set -e

# Configuration
TRAEFIK_CONFIG_PATH="./traefik"
MIDDLEWARE_PATH="$TRAEFIK_CONFIG_PATH/dynamic"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Setup directories
setup_directories() {
    log_info "Setting up middleware directories..."
    mkdir -p "$MIDDLEWARE_PATH"
}

# Create auth middleware
create_auth_middleware() {
    local client_name="$1" environment="$2" username="$3" password="$4"
    
    log_info "Creating auth middleware for ${client_name}-${environment}..."
    
    local auth_hash=$(htpasswd -nbB "$username" "$password")
    
    cat > "$MIDDLEWARE_PATH/${client_name}-${environment}-auth.yml" << EOF
http:
  middlewares:
    ${client_name}-${environment}-auth:
      basicAuth:
        users:
          - "${auth_hash}"
        realm: "Staging Environment - ${client_name^} ${environment^}"
        removeHeader: true
EOF
}

# Create SEO protection middleware
create_seo_middleware() {
    local client_name="$1" environment="$2"
    
    log_info "Creating SEO middleware for ${client_name}-${environment}..."
    
    cat > "$MIDDLEWARE_PATH/${client_name}-${environment}-seo.yml" << EOF
http:
  middlewares:
    ${client_name}-${environment}-seo:
      headers:
        customRequestHeaders:
          X-Robots-Tag: "noindex,nofollow,noarchive,nosnippet"
        customResponseHeaders:
          X-Robots-Tag: "noindex,nofollow,noarchive,nosnippet"
          X-Environment: "${environment}"
EOF
}

# Create security headers middleware
create_security_middleware() {
    if [[ ! -f "$MIDDLEWARE_PATH/security-headers.yml" ]]; then
        log_info "Creating security headers middleware..."
        
        cat > "$MIDDLEWARE_PATH/security-headers.yml" << EOF
http:
  middlewares:
    security-headers:
      headers:
        customResponseHeaders:
          X-Frame-Options: "SAMEORIGIN"
          X-Content-Type-Options: "nosniff"
          X-XSS-Protection: "1; mode=block"
          Referrer-Policy: "strict-origin-when-cross-origin"
        contentTypeNosniff: true
        frameDeny: false
        customFrameOptionsValue: "SAMEORIGIN"
    
    rate-limit:
      rateLimit:
        burst: 100
        average: 50
EOF
    fi
}

# Setup client middleware
setup_client_middleware() {
    local client_name="$1" environment="$2" password="$3"
    local username="${4:-staging}"
    
    if [[ -z "$password" && "$environment" != "production" ]]; then
        log_error "Password required for non-production environments"
        return 1
    fi
    
    log_info "Setting up middleware for ${client_name}/${environment}..."
    
    setup_directories
    create_security_middleware
    
    # Create auth and SEO middleware for non-production
    if [[ "$environment" != "production" ]]; then
        create_auth_middleware "$client_name" "$environment" "$username" "$password"
        create_seo_middleware "$client_name" "$environment"
        
        # Create middleware chain
        cat > "$MIDDLEWARE_PATH/${client_name}-${environment}-chain.yml" << EOF
http:
  middlewares:
    ${client_name}-${environment}-chain:
      chain:
        middlewares:
          - ${client_name}-${environment}-auth
          - ${client_name}-${environment}-seo
          - security-headers
          - rate-limit
EOF
    else
        # Production only gets security headers
        cat > "$MIDDLEWARE_PATH/${client_name}-${environment}-chain.yml" << EOF
http:
  middlewares:
    ${client_name}-${environment}-chain:
      chain:
        middlewares:
          - security-headers
          - rate-limit
EOF
    fi
    
    log_info "Middleware configured for ${client_name}/${environment}"
}

# Remove client middleware
remove_client_middleware() {
    local client_name="$1" environment="$2"
    
    log_info "Removing middleware for ${client_name}/${environment}..."
    rm -f "$MIDDLEWARE_PATH/${client_name}-${environment}-"*.yml
}

# List middleware
list_middleware() {
    log_info "Active middleware configurations:"
    echo ""
    
    if [[ -d "$MIDDLEWARE_PATH" ]]; then
        for config in "$MIDDLEWARE_PATH"/*.yml; do
            if [[ -f "$config" ]]; then
                local name=$(basename "$config")
                local size=$(stat -c%s "$config" 2>/dev/null || echo "0")
                echo "  📄 $name ($size bytes)"
            fi
        done
    else
        log_warn "No middleware directory found"
    fi
}

# Restart Traefik
restart_traefik() {
    log_info "Restarting Traefik..."
    
    if docker ps | grep -q traefik; then
        docker restart traefik
        sleep 3
        
        if docker ps | grep -q traefik; then
            log_info "✅ Traefik restarted"
        else
            log_error "❌ Traefik restart failed"
            return 1
        fi
    else
        log_warn "Traefik not running"
    fi
}

# Initialize middleware system
init_middleware() {
    log_info "Initializing middleware system..."
    
    setup_directories
    create_security_middleware
    
    # Update traefik.yml if needed
    if [[ -f "$TRAEFIK_CONFIG_PATH/traefik.yml" ]] && ! grep -q "directory:" "$TRAEFIK_CONFIG_PATH/traefik.yml"; then
        log_info "Adding dynamic configuration to traefik.yml..."
        cat >> "$TRAEFIK_CONFIG_PATH/traefik.yml" << EOF

# Dynamic configuration for client middleware
providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
EOF
    fi
    
    restart_traefik
    log_info "✅ Middleware system initialized"
}

# Main command handling
case "$1" in
    "setup")
        [[ $# -lt 4 ]] && { echo "Usage: $0 setup CLIENT ENV PASSWORD [USERNAME]"; exit 1; }
        setup_client_middleware "$2" "$3" "$4" "$5"
        restart_traefik
        ;;
    "remove")
        [[ $# -lt 3 ]] && { echo "Usage: $0 remove CLIENT ENV"; exit 1; }
        remove_client_middleware "$2" "$3"
        restart_traefik
        ;;
    "list") list_middleware ;;
    "restart") restart_traefik ;;
    "init") init_middleware ;;
    *)
        echo "Traefik Middleware Setup"
        echo ""
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  init                              Initialize middleware system"
        echo "  setup CLIENT ENV PASSWORD [USER] Setup middleware for environment"
        echo "  remove CLIENT ENV                Remove middleware"
        echo "  list                             List middleware configs"
        echo "  restart                          Restart Traefik"
        echo ""
        echo "Examples:"
        echo "  $0 init"
        echo "  $0 setup acme staging mypass123"
        echo "  $0 remove acme staging"
        exit 1
        ;;
esac