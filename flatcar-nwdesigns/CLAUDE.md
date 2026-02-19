# Flatcar Linux VM - Docker Services

## VM Connection
```bash
ssh core@10.21.21.104
```

## Architecture
```
Internet → Cloudflare → cloudflared tunnel → Traefik (:80) → CrowdSec Bouncer → Services
```

## Services
| Service | Internal Port | Public URL |
|---------|---------------|------------|
| Vaultwarden | 80 | https://vaultwarden.nwdesigns.it |
| n8n | 5678 | https://n8n.nwdesigns.it |
| Evolution API | 8080 | https://evolution.nwdesigns.it |
| Portainer | 9000 | https://portainer.nwdesigns.it |
| Traefik Dashboard | 8080 | https://traefik.nwdesigns.it |

## Security
- **CrowdSec** - Intrusion prevention system
- **CrowdSec Bouncer** - ForwardAuth middleware blocking malicious IPs
- All services protected via `crowdsec-bouncer@docker` middleware

## VM Paths
| Service | Config Path |
|---------|-------------|
| Infrastructure (Traefik + Cloudflared) | `/opt/infrastructure/` |
| CrowdSec | `/opt/crowdsec/` |
| Vaultwarden | `/opt/vaultwarden/` |
| Portainer | `/opt/portainer/` |
| n8n | `/opt/n8n/` |
| Evolution API | `/opt/evolution-api/` |

## Secrets / Environment Files

All sensitive data is stored in `.env` files on the VM (not in docker-compose.yml).

| Service | Env File | Variables |
|---------|----------|-----------|
| Infrastructure | `/opt/infrastructure/.env` | `CLOUDFLARE_TUNNEL_TOKEN` |
| CrowdSec | `/opt/crowdsec/.env` | `CROWDSEC_BOUNCER_API_KEY` |
| Vaultwarden | `/opt/vaultwarden/.env` | `SMTP_PASSWORD` |
| Evolution API | `/opt/evolution-api/.env` | `AUTHENTICATION_API_KEY`, `POSTGRES_PASSWORD` |

Local config mirrors include `.env.example` files showing required variables without actual secrets.

## Project Structure
```
./
├── CLAUDE.md                    # This file
├── config/                      # Mirror of VM configs
│   ├── infrastructure/
│   │   └── docker-compose.yml
│   ├── crowdsec/
│   │   ├── docker-compose.yml
│   │   └── acquis.yaml
│   ├── vaultwarden/
│   │   ├── docker-compose.yml
│   │   └── .env.example         # Template for secrets
│   ├── n8n/
│   │   └── docker-compose.yml
│   ├── evolution-api/
│   │   ├── docker-compose.yml
│   │   └── .env.example
│   └── portainer/
│       └── docker-compose.yml
├── docs/                        # Documentation
│   ├── infrastructure.md        # Architecture overview
│   └── services.md              # Service-specific docs
└── .claude/
    └── reports/                 # Session reports
```

## Common Commands
```bash
# Check all containers
ssh core@10.21.21.104 "sudo docker ps"

# View Traefik logs
ssh core@10.21.21.104 "sudo docker logs traefik -f"

# View cloudflared logs
ssh core@10.21.21.104 "sudo docker logs cloudflared -f"

# View CrowdSec metrics
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli metrics"

# View CrowdSec decisions (blocked IPs)
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli decisions list"

# Restart a service
ssh core@10.21.21.104 "cd /opt/<service> && sudo /opt/bin/docker-compose restart"

# Restart infrastructure stack
ssh core@10.21.21.104 "cd /opt/infrastructure && sudo /opt/bin/docker-compose restart"

# Restart CrowdSec stack
ssh core@10.21.21.104 "cd /opt/crowdsec && sudo /opt/bin/docker-compose restart"
```

## Network
- Docker network: `traefik-public`
- All services must be connected to this network for Traefik routing

## Cloudflare Tunnel
- Tunnel name: `office-flatcar`
- Token stored in: `/opt/infrastructure/.env`
- Dashboard: https://one.dash.cloudflare.com/ → Networks → Tunnels

## CrowdSec
- Bouncer API key stored in: `/opt/crowdsec/.env`
- Collections: `crowdsecurity/traefik`, `crowdsecurity/http-cve`
- Logs source: Traefik access logs (`/logs/access.log`)

## Vaultwarden
- SMTP configured via Gmail (admin@nwdesigns.it)
- App password stored in: `/opt/vaultwarden/.env`
- Emails sent from: `Vaultwarden <admin@nwdesigns.it>`
