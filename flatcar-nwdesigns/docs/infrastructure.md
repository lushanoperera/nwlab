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
| **OTel Collector** | Ingests telemetry from VM 103 blog-publisher cron jobs; exports to NDJSON files + co-located Prometheus remote-write | `otel/opentelemetry-collector-contrib:latest` |
| **ntfy** | Pub/sub alert channel for blog-publisher failures + stale heartbeats (topic `blog-publishers`) | `binwiederhier/ntfy:latest` |
| **Prometheus** | TSDB backend for blog-publisher metrics; receives via remote_write from co-located otel-collector | `prom/prometheus:latest` |
| **Grafana** | Dashboard frontend for the blog-publisher Prometheus backend; provisioned datasource + dashboard | `grafana/grafana:latest` |

## Network Topology

16 containers across 10 stacks:

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

┌──────────────────────────────────────────────────────────────────────────┐
│                     observability network (bridge)                        │
│                                                                           │
│   ┌─────────────────┐  remote_write   ┌────────────┐  query   ┌────────┐ │
│   │ otel-collector  │ ──────────────► │ prometheus │ ◄─────── │grafana │ │
│   │ :4317 / :4318   │                 │   :9090    │          │ :3000  │ │
│   └────────┬────────┘                 └────────────┘          └────────┘ │
│            │                                                              │
│            │ also joins traefik-public                                    │
│            │ for healthcheck access                                       │
│            ▼                                                              │
│   (OTLP from VM 103 cron jobs via host port binds 4317/4318)              │
└──────────────────────────────────────────────────────────────────────────┘

  caddy joins both traefik-public + observability (bridge mode, :443 only)
    → wildcard LE cert for *.nwlab.nwdesigns.it via Cloudflare DNS-01
    → reverse-proxies ntfy, grafana, prometheus over internal docker DNS
  ntfy joins traefik-public; routed at https://ntfy.nwlab.nwdesigns.it
  grafana joins both networks; routed at https://grafana.nwlab.nwdesigns.it
  prometheus stays on observability; routed at https://prometheus.nwlab.nwdesigns.it
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
├── portainer/
│   └── docker-compose.yml
├── otel-collector/           # Blog-publisher telemetry ingest
│   ├── docker-compose.yml
│   ├── config.yaml
│   ├── .env                  # PROMETHEUS_REMOTE_WRITE_URL (optional)
│   └── data/                 # NDJSON file exporter output (metrics/traces/logs)
├── ntfy/                     # Blog-publisher alert channel
│   ├── docker-compose.yml
│   ├── server.yml
│   └── .env                  # NTFY_ADMIN_TOKEN (optional)
├── prometheus/               # TSDB backend (remote_write target)
│   ├── docker-compose.yml
│   └── prometheus.yml
├── grafana/                  # Dashboard frontend
│   ├── docker-compose.yml
│   ├── .env                  # GRAFANA_ADMIN_PASSWORD
│   └── provisioning/
│       ├── datasources/prometheus.yml
│       └── dashboards/{dashboards.yml,blog-publishers.json}
└── caddy/                    # Internal wildcard TLS reverse proxy
    ├── docker-compose.yml    # Bridge mode, :443 only (no :80 — http_port 8090)
    ├── Dockerfile            # caddy:2 + caddy-dns/cloudflare plugin
    ├── entrypoint.sh         # Reads /run/secrets/cloudflare_api_token → CF_API_TOKEN
    ├── Caddyfile             # *.nwlab.nwdesigns.it wildcard site block
    ├── sites/nwlab.caddy     # Per-subdomain matchers (ntfy, grafana, prometheus)
    ├── secrets/cloudflare_api_token  # 0600; scoped CF token (Zone:Read + DNS:Edit on nwdesigns.it)
    ├── data/                 # Caddy on-disk state (cert cache, OCSP staples)
    └── config/               # Caddy runtime config cache
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
| `ntfy_ntfy_cache` | ntfy | `/var/cache/ntfy` |
| `ntfy_ntfy_etc` | ntfy | `/etc/ntfy` |
| `/opt/otel-collector/data` | otel-collector | `/data` |
| `prometheus_prometheus_data` | prometheus | `/prometheus` |
| `grafana_grafana_data` | grafana | `/var/lib/grafana` |

## Cloudflare Tunnel

- **Tunnel Name:** `office-flatcar`
- **Token Location:** `/opt/infrastructure/.env`
- **Ingress Rules:** Configured in Cloudflare Zero Trust Dashboard
- **Public Hostnames:** All point to `http://traefik:80`

## CrowdSec Security

CrowdSec analyzes Traefik access logs to detect and block malicious traffic. All services are protected via `crowdsec-bouncer@docker` ForwardAuth middleware.

For details (healthcheck, commands, bouncer config): see [services.md — CrowdSec](services.md#crowdsec).

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
| — | Traefik | Dashboard/API only via https://traefik.nwdesigns.it (basic auth); `:8080` unpublished |
| 443 | Caddy | Internal wildcard TLS for `*.nwlab.nwdesigns.it` (LE via Cloudflare DNS-01) |
| 8000 | Portainer | Edge agent |
| 9443 | Portainer | HTTPS UI (local access) |
| 4317 | OTel Collector | OTLP gRPC — blog-publisher telemetry from VM 103 |
| 4318 | OTel Collector | OTLP HTTP — blog-publisher telemetry from VM 103 |
| 9090 (loopback) | Prometheus | `127.0.0.1:9090` — kept for SSH-tunnel debugging; Caddy + Grafana + collector use the `observability` Docker network hostname |
| 3000 (internal) | Grafana | Via Caddy at `https://grafana.nwlab.nwdesigns.it` (LAN-only, NOT in Cloudflare tunnel) |

**Port collision note:** Caddy binds `:443` but NOT `:80` — the Caddyfile's `http_port 8090` parks Caddy's otherwise-default :80 listener on an unused host-internal port so it doesn't collide with Traefik. Traefik keeps sole ownership of host :80 + :8080 and the Cloudflare tunnel for public `*.nwdesigns.it` services. ACME HTTP-01 fallback is never used because the wildcard cert is issued via DNS-01.

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
