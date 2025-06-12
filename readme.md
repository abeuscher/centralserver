# WordPress Containerized Client Management System - Infrastructure

This repository contains the complete infrastructure for managing multiple WordPress client environments using Docker containers, Traefik reverse proxy, automated SSL certificate management, and webhook-based deployments.

## System Overview

- **Phase 1**: Infrastructure Foundation (Traefik, SSL, Docker) ✅
- **Phase 2**: Starter Repository (completed separately) ✅  
- **Phase 3**: Multi-Environment Management & Automation ✅

## Quick Start

### 1. Initial Setup

```bash
# Clone to your DigitalOcean droplet
git clone <repository-url> wordpress-infrastructure
cd wordpress-infrastructure

# Configure environment variables
cp .env.template .env
nano .env  # Edit with your specific values

chmod +x *.sh
sudo ./setup-infrastructure.sh
```

### 2. Configure Your Settings

```bash
# Edit the management script with your starter repo URL
nano manage-client.sh
# Update: STARTER_REPO_URL="https://github.com/yourusername/wordpress-starter.git"
# Update: DEFAULT_DOMAIN="yourdomain.com"
```

### 3. Create Your First Environment

```bash
# Create a production environment
manage-client create-environment mycompany production

# Create a staging environment  
manage-client create-environment mycompany staging

# Create with custom domain
manage-client create-environment mycompany production mycompany.com
```

### 4. Deploy the Environment

```bash
# Navigate to environment
cd /opt/clients/mycompany/production

# Start containers and setup WordPress
docker-compose up -d
./setup.sh

# Your site is now live at the configured domain!
```

## File Structure

```
wordpress-infrastructure/
├── docker-compose.traefik.yml       # Traefik reverse proxy configuration
├── traefik/
│   ├── traefik.yml                  # Traefik static configuration
│   └── dynamic/                     # Dynamic middleware configs (auto-created)
├── acme/                            # SSL certificates storage (auto-created)
├── .env.template                    # Environment variables template
├── .env                             # Your environment configuration
├── setup-infrastructure.sh         # Complete setup script (Phase 1 + 3)
├── manage-client.sh                 # Client environment management
├── webhook-receiver.sh              # Deployment automation
├── setup-traefik-middleware.sh     # Security middleware management
└── README.md                        # This file
```

## Environment Configuration

Key variables in `.env`:

```bash
# Infrastructure
DOMAIN=yourdomain.com
ACME_EMAIL=admin@yourdomain.com
MYSQL_ROOT_PASSWORD=your_secure_password

# Phase 3 Configuration
STARTER_REPO_URL=https://github.com/yourusername/wordpress-starter.git
WEBHOOK_PORT=9000
CLIENTS_PATH=/opt/clients
```

## Management Commands

### Client Environment Management

```bash
# Create environments
manage-client create-environment CLIENT_NAME ENVIRONMENT [CUSTOM_DOMAIN]
manage-client list-all
manage-client list-environments CLIENT_NAME
manage-client status
manage-client remove-environment CLIENT_NAME ENVIRONMENT
```

### Webhook & Deployment Management

```bash
# Webhook server management
webhook-receiver start              # Start webhook server
webhook-receiver status             # Check server status
webhook-receiver logs CLIENT ENV    # View deployment logs
webhook-receiver test CLIENT ENV    # Test deployment

# Generate GitHub Actions workflow
webhook-receiver generate-workflow CLIENT ENV WEBHOOK_URL
```

### Security & Middleware Management

```bash
# Setup security for staging environments
traefik-middleware setup CLIENT ENV PASSWORD
traefik-middleware list
traefik-middleware remove CLIENT ENV
traefik-middleware restart
```

## Domain Strategy

The system supports flexible domain configurations:

### Agency Subdomain Hosting
```bash
# All clients under your domain
manage-client create-environment acme production    # → acme.yourdomain.com
manage-client create-environment acme staging       # → staging.acme.yourdomain.com
manage-client create-environment acme hotfix        # → hotfix.acme.yourdomain.com
```

### Client-Owned Domains
```bash
# Client provides their own domain
manage-client create-environment acme production acme.com
manage-client create-environment acme staging staging.acme.com
```

## Security Features

- **Firewall Configuration**: UFW configured for SSH, HTTP, HTTPS, and webhook port
- **SSL Certificates**: Automatic Let's Encrypt certificate generation and renewal
- **Container Isolation**: Each client runs in isolated Docker networks
- **Staging Protection**: HTTP Basic Auth + SEO blocking for non-production environments
- **Security Headers**: Automatic security headers via Traefik middleware

## Automated Deployments

### GitHub Webhook Setup

1. **Generate workflow file:**
   ```bash
   webhook-receiver generate-workflow mycompany staging https://your-server.com > .github/workflows/deploy-staging.yml
   ```

2. **Add deployment token to GitHub secrets:**
   - Go to your repo Settings → Secrets
   - Add secret: `DEPLOY_TOKEN_STAGING` with the token from environment creation

3. **Push to trigger deployment:**
   ```bash
   git push origin staging  # Automatically deploys to staging environment
   ```

### Webhook Endpoints

- Format: `https://your-server.com:9000/webhook/CLIENT_NAME/ENVIRONMENT`
- Example: `https://server.com:9000/webhook/acme/staging`

## Accessing Services

After setup:

- **Traefik Dashboard**: `https://traefik.yourdomain.com`
- **Client Production**: `https://client.yourdomain.com`
- **Client Staging**: `https://staging.client.yourdomain.com` (password protected)
- **Webhook Endpoint**: `https://your-server.com:9000/webhook/client/env`

## Service Management

### System Services

```bash
# Webhook receiver service
systemctl status webhook-receiver
systemctl start webhook-receiver
systemctl stop webhook-receiver
journalctl -u webhook-receiver -f

# Traefik service
docker-compose -f docker-compose.traefik.yml restart
docker logs traefik -f
```

### Monitoring

```bash
# System overview
manage-client status

# Webhook server status
webhook-receiver status

# Recent deployments
webhook-receiver logs CLIENT ENV 50

# Container status
docker ps
docker stats
```

## Directory Structure (Auto-Created)

```
/opt/clients/
├── client-name/
│   ├── production/              # Full WordPress environment
│   ├── staging/                 # Staging environment
│   ├── hotfix/                  # Feature branch environment
│   └── shared/
│       ├── uploads-sync/        # Content promotion staging
│       ├── backups/             # Environment backups
│       └── tokens/              # Secure deployment tokens
```

## Troubleshooting

### Common Issues

1. **Environment creation fails:**
   ```bash
   # Check starter repository URL
   nano manage-client.sh
   # Verify git access and repository exists
   ```

2. **Webhook deployments fail:**
   ```bash
   # Check webhook service
   systemctl status webhook-receiver
   # View deployment logs
   webhook-receiver logs CLIENT ENV
   ```

3. **SSL certificates not generating:**
   ```bash
   # Check domain DNS points to server
   # Verify domain in environment .env file
   docker logs traefik
   ```

4. **Staging environments not password protected:**
   ```bash
   # Check middleware configuration
   traefik-middleware list
   # Restart Traefik
   traefik-middleware restart
   ```

### Log Locations

- **Deployment logs**: `/var/log/deployments/`
- **Traefik logs**: `docker logs traefik`
- **Webhook service**: `journalctl -u webhook-receiver`
- **Environment logs**: `/opt/clients/CLIENT/ENV/logs/`

## Next Steps

### Phase 4: Content Management System
- WordPress XML export/import automation
- File synchronization between environments
- ACF Pro field group promotion
- Timed content launches

### Scaling Considerations
- Multi-server deployment
- Load balancing for high-traffic sites
- Centralized monitoring and alerting
- Automated backup strategies

## Support

For issues:

1. Check logs using the commands above
2. Verify environment configuration
3. Ensure services are running
4. Review firewall and DNS settings

## Contributing

This system provides a complete foundation for scalable WordPress client management. The modular design allows for easy extension and customization for specific agency needs.