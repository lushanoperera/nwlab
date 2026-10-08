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
| **OpenWA** | WhatsApp API gateway + dashboard (Baileys engine, SQLite); replaced Evolution API 2026-10-02 | `ghcr.io/rmyndharis/openwa:0.23.7` |
| **PostgreSQL** | Database for n8n | `postgres:15-alpine` |
| **Autoheal** | Auto-restarts unhealthy containers every 30s | `willfarrell/autoheal:latest` |
| **OTel Collector** | Ingests telemetry from VM 103 blog-publisher cron jobs; exports to NDJSON files + co-located Prometheus remote-write | `otel/opentelemetry-collector-contrib:latest` |
| **ntfy** | Pub/sub alert channel for blog-publisher failures + stale heartbeats (topic `blog-publishers`) | `binwiederhier/ntfy:latest` |
| **Prometheus** | TSDB backend for blog-publisher metrics; receives via remote_write from co-located otel-collector | `prom/prometheus:latest` |
| **Grafana** | Dashboard frontend for the blog-publisher Prometheus backend; provisioned datasource + dashboard | `grafana/grafana:latest` |

## Network Topology

16 containers across 12 stacks:

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
│  │vaultwarden│  │    n8n    │  │  openwa-api   │  │ portainer │         │
│  │   :80     │  │   :5678   │  │     :2785     │  │   :9000   │         │
│  └───────────┘  └─────┬─────┘  └───────────────┘  └───────────┘         │
│                       │         (SQLite in openwa_openwa-data volume)     │
│                ┌──────┴──────┐                                           │
│                │n8n-internal │                                           │
│                │  network    │                                           │
│                │ ┌─────────┐ │                                           │
│                │ │postgres │ │                                           │
│                │ │  :5432  │ │                                           │
│                │ └─────────┘ │                                           │
│                └─────────────┘                                           │
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
    → reverse-proxies ntfy, grafana, prometheus, openwa over internal docker DNS
  openwa-api joins traefik-public (no Traefik labels); routed at https://wa.nwlab.nwdesigns.it
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
├── openwa/                   # WhatsApp API gateway (LAN-only via Caddy)
│   ├── docker-compose.yml
│   └── .env                  # API_MASTER_KEY, API_KEY_PEPPER (0600)
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
    ├── sites/wa.caddy        # wa.nwlab.nwdesigns.it → openwa-api:2785
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
| `openwa_openwa-data` | openwa-api | `/app/data` |
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
| 8787 (loopback) | context-hub | `127.0.0.1:8787` — PROVISIONAL MCP spike, reached only through `ssh -N -L 8787:127.0.0.1:8787` from Lushano's Mac |
| 3000 (internal) | Grafana | Via Caddy at `https://grafana.nwlab.nwdesigns.it` (LAN-only, NOT in Cloudflare tunnel) |

**Port collision note:** Caddy binds `:443` but NOT `:80` — the Caddyfile's `http_port 8090` parks Caddy's otherwise-default :80 listener on an unused host-internal port so it doesn't collide with Traefik. Traefik keeps sole ownership of host :80 + :8080 and the Cloudflare tunnel for public `*.nwdesigns.it` services. ACME HTTP-01 fallback is never used because the wildcard cert is issued via DNS-01.

## Startup Order

Services should be started in this order:

1. `traefik-public` network (must exist)
2. Infrastructure stack (Traefik + Cloudflared + Autoheal)
3. CrowdSec stack (depends on Traefik logs volume; bouncer waits for LAPI healthcheck)
4. Application services (Vaultwarden, n8n, OpenWA, Portainer)

```bash
# Full restart sequence
cd /opt/infrastructure && sudo /opt/bin/docker-compose up -d
cd /opt/crowdsec && sudo /opt/bin/docker-compose up -d
cd /opt/vaultwarden && sudo /opt/bin/docker-compose up -d
cd /opt/n8n && sudo /opt/bin/docker-compose up -d
cd /opt/openwa && sudo /opt/bin/docker-compose up -d
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
| `/opt/openwa/.env` | OpenWA master key + key pepper |
| Docker volume: `openwa_openwa-data` | OpenWA SQLite DB + WhatsApp session data |

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
| openwa-api | 512m | OpenWA |
| portainer | 256m | Portainer |
| context-hub | 128m | context-hub (PROVISIONAL spike) |
| **Total** | **stale, see live `free -m`** | |

**Stale table (2026-09-26):** the rows above omit caddy (192m), grafana (512m), prometheus (768m), ntfy (128m), and otel-collector (256m), per live `docker stats`. The VM balloon can reclaim up to 1 GiB, so read `free -m` for headroom. Follow-up: add the missing rows and recompute the total.

**CPU type (2026-09-27):** the VM CPU is Proxmox `kvm64` ("Common KVM processor", no SSE4.1/4.2, POPCNT, AVX, AVX2). Bun 1.4.2 hangs on any `.ts` import here; Node (n8n 22, context-hub 24) runs fine. Check CPU flags before adding a runtime that needs x86-64-v2 or newer.
