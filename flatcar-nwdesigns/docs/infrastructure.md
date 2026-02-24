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
| **Evolution API** | WhatsApp Business API gateway | `atendai/evolution-api:latest` |
| **PostgreSQL** (×2) | Databases for n8n and Evolution API | `postgres:15-alpine` |
| **Redis** | Cache for Evolution API | `redis:7-alpine` |
| **Autoheal** | Auto-restarts unhealthy containers every 30s | `willfarrell/autoheal:latest` |

## Network Topology

12 containers across 6 stacks:

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
│  ┌───────────┐  ┌───────────┐  ┌───────────────┐  ┌───────────┐         │
│  │vaultwarden│  │    n8n    │  │ evolution_api │  │ portainer │         │
│  │   :80     │  │   :5678   │  │     :8080     │  │   :9000   │         │
│  └───────────┘  └─────┬─────┘  └───────┬───────┘  └───────────┘         │
│                       │                │                                  │
│                ┌──────┴──────┐  ┌──────┴────────────┐                    │
│                │n8n-internal │  │evolution-internal  │                    │
│                │  network    │  │  network           │                    │
│                │ ┌─────────┐ │  │ ┌────────┐┌─────┐ │                    │
│                │ │postgres │ │  │ │postgres││redis│ │                    │
│                │ │  :5432  │ │  │ │ :5432  ││:6379│ │                    │
│                │ └─────────┘ │  │ └────────┘└─────┘ │                    │
│                └─────────────┘  └───────────────────┘                    │
└──────────────────────────────────────────────────────────────────────────┘

  ┌───────────┐  (host-only, no network — mounts Docker socket)
  │ autoheal  │
  └───────────┘
```

## Public Endpoints

| Service | URL | Protocol |
|---------|-----|----------|
| Vaultwarden | https://vaultwarden.nwdesigns.it | HTTPS (via Cloudflare) |
| n8n | https://n8n.nwdesigns.it | HTTPS (via Cloudflare) |
| Portainer | https://portainer.nwdesigns.it | HTTPS (via Cloudflare) |
| Evolution API | https://evolution.nwdesigns.it | HTTPS (via Cloudflare) |
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
├── evolution-api/
│   ├── docker-compose.yml
│   └── .env                  # AUTHENTICATION_API_KEY, POSTGRES_PASSWORD
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
| `evolution_evolution_instances` | evolution_api | `/evolution/instances` |
| `evolution_evolution_store` | evolution_api | `/evolution/store` |
| `evolution_postgres_data` | evolution_postgres | `/var/lib/postgresql/data` |
| `evolution_redis_data` | evolution_redis | `/data` |
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

### Healthcheck & Startup
CrowdSec has a LAPI healthcheck (`cscli lapi status`) that runs every 30s. The bouncer uses `depends_on: service_healthy` so it only starts after CrowdSec's LAPI is confirmed healthy. This prevents zombie process scenarios where CrowdSec appears running but LAPI is dead.

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
2. Infrastructure stack (Traefik + Cloudflared + Autoheal)
3. CrowdSec stack (depends on Traefik logs volume; bouncer waits for LAPI healthcheck)
4. Application services (Vaultwarden, n8n, Evolution API, Portainer)

```bash
# Full restart sequence
cd /opt/infrastructure && sudo /opt/bin/docker-compose up -d
cd /opt/crowdsec && sudo /opt/bin/docker-compose up -d
cd /opt/vaultwarden && sudo /opt/bin/docker-compose up -d
cd /opt/n8n && sudo /opt/bin/docker-compose up -d
cd /opt/evolution-api && sudo /opt/bin/docker-compose up -d
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
| `/opt/evolution-api/.env` | Evolution API key + Postgres password |
| Docker volume: `evolution_evolution_instances` | WhatsApp session data |
| Docker volume: `evolution_evolution_store` | Evolution store data |
| Docker volume: `evolution_postgres_data` | Evolution PostgreSQL database |

## Resource Limits

All containers have memory limits (~3 GB total on a 4 GB VM). Autoheal monitors healthchecks and restarts unhealthy containers every 30s.

| Container | mem_limit | Stack |
|-----------|-----------|-------|
| traefik | 256m | Infrastructure |
| cloudflared | 128m | Infrastructure |
| autoheal | 64m | Infrastructure |
| crowdsec | 256m | CrowdSec |
| crowdsec-bouncer | 128m | CrowdSec |
| vaultwarden | 256m | Vaultwarden |
| n8n | 512m | n8n |
| n8n_postgres | 256m | n8n |
| evolution_api | 512m | Evolution API |
| evolution_postgres | 256m | Evolution API |
| evolution_redis | 128m | Evolution API |
| portainer | 256m | Portainer |
| **Total** | **3008m** | |
