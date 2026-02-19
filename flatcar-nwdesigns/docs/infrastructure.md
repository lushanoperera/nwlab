# Flatcar VM Infrastructure

## Overview

This document describes the Docker infrastructure running on the Flatcar Linux VM at `10.21.21.104`.

## Architecture

```
Internet → Cloudflare CDN → Cloudflare Tunnel → Traefik → CrowdSec Bouncer → Services
```

### Components

| Component | Purpose | Image |
|-----------|---------|-------|
| **Traefik** | Reverse proxy, routes traffic by hostname | `traefik:v3.3` |
| **Cloudflared** | Cloudflare Tunnel connector | `cloudflare/cloudflared:latest` |
| **CrowdSec** | Intrusion prevention system | `crowdsecurity/crowdsec:latest` |
| **CrowdSec Bouncer** | ForwardAuth middleware | `fbonalair/traefik-crowdsec-bouncer:latest` |
| **Vaultwarden** | Password manager (Bitwarden compatible) | `vaultwarden/server:latest` |
| **n8n** | Workflow automation | `docker.n8n.io/n8nio/n8n:latest` |
| **Portainer** | Docker management UI | `portainer/portainer-ce:2.20.3` |
| **PostgreSQL** | Database for n8n | `postgres:15-alpine` |

## Network Topology

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         traefik-public network                            │
│                                                                           │
│  ┌──────────┐  ┌────────────┐  ┌──────────┐  ┌─────────────────────────┐ │
│  │ traefik  │  │ cloudflared│  │ crowdsec │  │   crowdsec-bouncer      │ │
│  │  :80     │  │            │  │  :8080   │  │        :8080            │ │
│  │  :8080   │  │            │  │          │  │                         │ │
│  └──────────┘  └────────────┘  └──────────┘  └─────────────────────────┘ │
│                                                                           │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐                             │
│  │vaultwarden│  │    n8n    │  │ portainer │                             │
│  │   :80     │  │   :5678   │  │   :9000   │                             │
│  └───────────┘  └─────┬─────┘  └───────────┘                             │
│                       │                                                   │
│                ┌──────┴──────┐                                            │
│                │n8n-internal │                                            │
│                │  network    │                                            │
│                │ ┌─────────┐ │                                            │
│                │ │postgres │ │                                            │
│                │ │  :5432  │ │                                            │
│                │ └─────────┘ │                                            │
│                └─────────────┘                                            │
└──────────────────────────────────────────────────────────────────────────┘
```

## Public Endpoints

| Service | URL | Protocol |
|---------|-----|----------|
| Vaultwarden | https://vaultwarden.nwdesigns.it | HTTPS (via Cloudflare) |
| n8n | https://n8n.nwdesigns.it | HTTPS (via Cloudflare) |
| Portainer | https://portainer.nwdesigns.it | HTTPS (via Cloudflare) |
| Traefik Dashboard | https://traefik.nwdesigns.it | HTTPS (via Cloudflare) |

## VM File Structure

```
/opt/
├── infrastructure/           # Traefik + Cloudflared
│   ├── docker-compose.yml
│   └── .env                  # CLOUDFLARE_TUNNEL_TOKEN
├── crowdsec/                 # CrowdSec security
│   ├── docker-compose.yml
│   ├── acquis.yaml           # Log acquisition config
│   ├── .env                  # CROWDSEC_BOUNCER_API_KEY
│   ├── config/               # CrowdSec config
│   └── db/                   # CrowdSec database
├── vaultwarden/
│   ├── docker-compose.yml
│   └── data/                 # Persistent data
├── n8n/
│   └── docker-compose.yml
└── portainer/
    └── docker-compose.yml
```

## Docker Volumes

| Volume | Container | Mount Point |
|--------|-----------|-------------|
| `infrastructure_traefik_logs` | traefik, crowdsec | `/logs` |
| `n8n_n8n_data` | n8n | `/home/node/.n8n` |
| `n8n_postgres_data` | n8n_postgres | `/var/lib/postgresql/data` |
| `portainer_data` | portainer | `/data` |
| `/opt/vaultwarden/data` | vaultwarden | `/data` |
| `/opt/crowdsec/db` | crowdsec | `/var/lib/crowdsec/data` |
| `/opt/crowdsec/config` | crowdsec | `/etc/crowdsec` |

## Cloudflare Tunnel

- **Tunnel Name:** `office-flatcar`
- **Token Location:** `/opt/infrastructure/.env`
- **Ingress Rules:** Configured in Cloudflare Zero Trust Dashboard
- **Public Hostnames:** All point to `http://traefik:80`

## CrowdSec Security

### Overview
CrowdSec is an open-source security engine that analyzes Traefik access logs to detect and block malicious traffic.

### Collections Installed
- `crowdsecurity/traefik` - Traefik log parser and scenarios
- `crowdsecurity/http-cve` - HTTP CVE detection

### How It Works
1. Traefik writes access logs to `/logs/access.log`
2. CrowdSec reads and parses these logs via `acquis.yaml`
3. CrowdSec detects malicious patterns and creates "decisions" (bans)
4. The bouncer checks incoming requests against decisions via ForwardAuth
5. Blocked IPs receive a 403 Forbidden response

### Bouncer Middleware
All services are protected by the CrowdSec bouncer middleware:

```yaml
labels:
  - "traefik.http.routers.<service>.middlewares=crowdsec-bouncer@docker"
```

### Management Commands
```bash
# View metrics
sudo docker exec crowdsec cscli metrics

# List blocked IPs
sudo docker exec crowdsec cscli decisions list

# Manually ban an IP
sudo docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason "manual ban"

# Remove a ban
sudo docker exec crowdsec cscli decisions delete --ip 1.2.3.4

# List installed collections
sudo docker exec crowdsec cscli collections list

# Update hub (scenarios, parsers)
sudo docker exec crowdsec cscli hub update
```

## Traefik Routing

Traefik automatically discovers containers via Docker labels:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<service>.rule=Host(`<hostname>`)"
  - "traefik.http.routers.<service>.entrypoints=web"
  - "traefik.http.routers.<service>.middlewares=crowdsec-bouncer@docker"
  - "traefik.http.services.<service>.loadbalancer.server.port=<port>"
```

## Ports Exposed on Host

| Port | Service | Purpose |
|------|---------|---------|
| 80 | Traefik | HTTP ingress (used by Cloudflare tunnel) |
| 8080 | Traefik | Dashboard/API (local access only) |
| 8000 | Portainer | Edge agent |
| 9443 | Portainer | HTTPS UI (local access) |

## Startup Order

Services should be started in this order:

1. `traefik-public` network (must exist)
2. Infrastructure stack (Traefik + Cloudflared)
3. CrowdSec stack (depends on Traefik logs volume)
4. Application services (Vaultwarden, n8n, Portainer)

```bash
# Full restart sequence
cd /opt/infrastructure && sudo /opt/bin/docker-compose up -d
cd /opt/crowdsec && sudo /opt/bin/docker-compose up -d
cd /opt/vaultwarden && sudo /opt/bin/docker-compose up -d
cd /opt/n8n && sudo /opt/bin/docker-compose up -d
cd /opt/portainer && sudo /opt/bin/docker-compose up -d
```

## Backup Considerations

### Critical Data to Backup
| Path | Contains |
|------|----------|
| `/opt/vaultwarden/data` | Vaultwarden database and attachments |
| `/opt/crowdsec/db` | CrowdSec decisions database |
| `/opt/infrastructure/.env` | Cloudflare tunnel token |
| `/opt/crowdsec/.env` | CrowdSec bouncer API key |
| `/opt/vaultwarden/.env` | Vaultwarden SMTP password |
| Docker volume: `n8n_n8n_data` | n8n workflows and credentials |
| Docker volume: `n8n_postgres_data` | n8n PostgreSQL database |
| Docker volume: `portainer_data` | Portainer configuration |
