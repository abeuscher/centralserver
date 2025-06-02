# WordPress Containerized Client Management System - Infrastructure

This repository contains the infrastructure foundation for managing multiple WordPress client environments using Docker containers, Traefik reverse proxy, and automated SSL certificate management.

## Quick Start

1. **Clone this repository to your DigitalOcean droplet:**
   ```bash
   git clone <repository-url> wordpress-infrastructure
   cd wordpress-infrastructure
   ```

2. **Configure environment variables:**
   ```bash
   cp .env.template .env
   nano .env  # Edit with your specific values
   ```

3. **Run the setup script:**
   ```bash
   chmod +x setup-infrastructure.sh
   sudo ./setup-infrastructure.sh
   ```

4. **Verify installation:**
   ```bash
   chmod +x manage-infrastructure.sh
   ./manage-infrastructure.sh status
   ```

## File Structure

```
wordpress-infrastructure/
├── docker-compose.traefik.yml    # Traefik reverse proxy configuration
├── traefik/
│   └── traefik.yml              # Traefik static configuration
├── acme/                        # SSL certificates storage (auto-created)
├── .env.template                # Environment variables template
├── .env                         # Your environment configuration (create from template)
├── setup-infrastructure.sh      # Initial setup script
├── manage-infrastructure.sh     # Management and monitoring script
└── README.md                    # This file
```

## Environment Configuration

Copy `.env.template` to `.env` and configure the following key variables:

- `DOMAIN`: Your primary domain (e.g., `yourdomain.com`)
- `ACME_EMAIL`: Email for Let's Encrypt SSL certificates
- `MYSQL_ROOT_PASSWORD`: Secure password for database root user
- `SERVER_IP`: Your DigitalOcean droplet IP address

## Management Commands

The `manage-infrastructure.sh` script provides the following commands:

- `./manage-infrastructure.sh status` - Show system status
- `./manage-infrastructure.sh restart` - Restart Traefik
- `./manage-infrastructure.sh logs` - View Traefik logs
- `./manage-infrastructure.sh ssl-status` - Check SSL certificates
- `./manage-infrastructure.sh backup` - Create infrastructure backup
- `./manage-infrastructure.sh update` - Update Traefik
- `./manage-infrastructure.sh clean` - Clean Docker resources
- `./manage-infrastructure.sh monitor` - Monitor container stats

## Security Features

- **Firewall Configuration**: Automatically configures UFW to allow only SSH, HTTP, and HTTPS
- **SSL Certificates**: Automatic Let's Encrypt certificate generation and renewal
- **Container Isolation**: Each client runs in isolated Docker containers
- **Secure Defaults**: HTTP traffic automatically redirects to HTTPS

## Accessing Services

After setup, you can access:

- **Traefik Dashboard**: `https://traefik.yourdomain.com`
- **Future Client Sites**: `https://client.yourdomain.com`
- **Staging Environments**: `https://staging.client.yourdomain.com`

## Next Steps

This completes **Phase 1** of the implementation plan. Next steps:

1. **Phase 2**: Create the standardized starter repository with WordPress and build system
2. **Phase 3**: Set up multi-environment templates
3. **Phase 4**: Implement content management and promotion workflows

## Troubleshooting

### Common Issues

1. **Traefik not starting:**
   - Check logs: `docker logs traefik`
   - Verify `.env` file configuration
   - Ensure port 80/443 are not in use

2. **SSL certificates not generating:**
   - Verify domain DNS points to your server
   - Check ACME email configuration
   - Review Traefik logs for certificate errors

3. **Permission issues:**
   - Ensure scripts are executable: `chmod +x *.sh`
   - Run setup script as root: `sudo ./setup-infrastructure.sh`

### Log Files

- Traefik logs: `docker logs traefik`
- Container stats: `docker stats`
- System logs: `journalctl -u docker`

## Support

For issues or questions:

1. Check the troubleshooting section above
2. Review Docker and Traefik logs
3. Verify firewall and DNS configuration
4. Ensure environment variables are properly set

## Contributing

This infrastructure is designed to be the foundation for a scalable WordPress client management system. Future enhancements will include automated client onboarding, centralized management tools, and advanced monitoring capabilities.