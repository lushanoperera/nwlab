# Services Documentation

## Vaultwarden

**Purpose:** Self-hosted password manager compatible with Bitwarden clients.

**URL:** https://vaultwarden.nwdesigns.it

**Container:** `vaultwarden` | **Config:** [`config/vaultwarden/docker-compose.yml`](../config/vaultwarden/docker-compose.yml)

**Data Location:** `/opt/vaultwarden/data`

### Environment Variables

| File | Variable | Description |
|------|----------|-------------|
| `.env` | `SMTP_PASSWORD` | Gmail App Password |

### SMTP Configuration

| Setting | Value |
|---------|-------|
| Provider | Gmail (Google Workspace) |
| From Address | admin@nwdesigns.it |
| From Name | Vaultwarden |
| Port | 587 (STARTTLS) |

To update the SMTP password:
```bash
ssh core@10.21.21.104 "nano /opt/vaultwarden/.env"
ssh core@10.21.21.104 "cd /opt/vaultwarden && sudo /opt/bin/docker-compose restart"
```

### Management Commands

```bash
# View logs
ssh core@10.21.21.104 "sudo docker logs vaultwarden -f"

# Restart
ssh core@10.21.21.104 "cd /opt/vaultwarden && sudo /opt/bin/docker-compose restart"

# Backup data
ssh core@10.21.21.104 "sudo tar -czf /tmp/vaultwarden-backup.tar.gz -C /opt/vaultwarden data"
```

---

## n8n

**Purpose:** Workflow automation platform.

**URL:** https://n8n.nwdesigns.it

**Containers:** `n8n` + `n8n_postgres` | **Config:** [`config/n8n/docker-compose.yml`](../config/n8n/docker-compose.yml)

**Database:** PostgreSQL 15

### Management Commands

```bash
# View n8n logs
ssh core@10.21.21.104 "sudo docker logs n8n -f"

# View postgres logs
ssh core@10.21.21.104 "sudo docker logs n8n_postgres -f"

# Restart n8n stack
ssh core@10.21.21.104 "cd /opt/n8n && sudo /opt/bin/docker-compose restart"

# Database backup
ssh core@10.21.21.104 "sudo docker exec n8n_postgres pg_dump -U n8n n8n > /tmp/n8n-db-backup.sql"
```

---

## Evolution API

**Purpose:** WhatsApp Business API gateway — sending/receiving WhatsApp messages via REST API.

**URL:** https://evolution.nwdesigns.it | **Manager UI:** https://evolution.nwdesigns.it/manager

**Containers:** `evolution_api` + `evolution_postgres` + `evolution_redis` | **Config:** [`config/evolution-api/docker-compose.yml`](../config/evolution-api/docker-compose.yml)

**Database:** PostgreSQL 15 + Redis 7

### Environment Variables

| File | Variable | Description |
|------|----------|-------------|
| `.env` | `AUTHENTICATION_API_KEY` | API key for authenticating requests |
| `.env` | `POSTGRES_PASSWORD` | PostgreSQL database password |

### WhatsApp Setup

1. Access the manager UI: https://evolution.nwdesigns.it/manager
2. Create a new instance (e.g., `nwteam`)
3. Scan the QR code with your WhatsApp
4. Use the instance name and API key for API calls

### API Usage

```bash
# List all groups
curl -X GET "https://evolution.nwdesigns.it/group/fetchAllGroups/INSTANCE_NAME" \
  -H "apikey: YOUR_API_KEY"

# Send text message to group
curl -X POST "https://evolution.nwdesigns.it/message/sendText/INSTANCE_NAME" \
  -H "apikey: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "GROUP_ID@g.us",
    "text": "Hello from Evolution API!"
  }'
```

### Integration with n8n

Evolution API integrates with n8n for workflow automation (e.g., GitLab → Slack → WhatsApp notifications):

1. Create n8n workflow with Webhook Trigger
2. Add HTTP Request node pointing to Evolution API
3. Configure with your instance name and API key via n8n variables

### Management Commands

```bash
# View Evolution API logs
ssh core@10.21.21.104 "sudo docker logs evolution_api -f"

# Restart Evolution API stack
ssh core@10.21.21.104 "cd /opt/evolution-api && sudo /opt/bin/docker-compose restart"

# Check connection status
ssh core@10.21.21.104 "curl -s http://localhost:8080 -H 'Host: evolution.nwdesigns.it'"

# Database backup
ssh core@10.21.21.104 "sudo docker exec evolution_postgres pg_dump -U evolution evolution > /tmp/evolution-db-backup.sql"
```

---

## Portainer

**Purpose:** Docker management web UI.

**URL:** https://portainer.nwdesigns.it | **Local:** https://10.21.21.104:9443

**Container:** `portainer` | **Config:** [`config/portainer/docker-compose.yml`](../config/portainer/docker-compose.yml)

---

## Traefik

**Purpose:** Reverse proxy and load balancer with automatic Docker container discovery.

**Dashboard:** https://traefik.nwdesigns.it | **Local:** http://10.21.21.104:8080

**Container:** `traefik` | **Config:** [`config/infrastructure/docker-compose.yml`](../config/infrastructure/docker-compose.yml)

### Adding a New Service

Add these labels to any new service's docker-compose.yml:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<service>.rule=Host(`<hostname>`)"
  - "traefik.http.routers.<service>.entrypoints=web"
  - "traefik.http.routers.<service>.middlewares=crowdsec-bouncer@docker"
  - "traefik.http.services.<service>.loadbalancer.server.port=<port>"
```

### Inspect Commands

```bash
# View configured routers
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/routers | jq '.[] | {name, rule}'"

# View services
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/services | jq '.[] | {name, status}'"

# View middlewares
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/middlewares | jq '.[] | .name'"
```

---

## Cloudflared

**Purpose:** Cloudflare Tunnel connector — exposes services to internet securely.

**Container:** `cloudflared` | **Tunnel Name:** `office-flatcar`

**Config:** Managed via [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/) → Networks → Tunnels → `office-flatcar`

### Public Hostnames

| Hostname | Origin |
|----------|--------|
| vaultwarden.nwdesigns.it | http://traefik:80 |
| n8n.nwdesigns.it | http://traefik:80 |
| evolution.nwdesigns.it | http://traefik:80 |
| portainer.nwdesigns.it | http://traefik:80 |
| traefik.nwdesigns.it | http://traefik:80 |

```bash
# View tunnel status
ssh core@10.21.21.104 "sudo docker logs cloudflared 2>&1 | grep -E '(Registered|Updated)' | tail -10"
```

---

## CrowdSec

**Purpose:** Intrusion prevention — analyzes Traefik access logs and blocks malicious IPs.

**Containers:** `crowdsec` + `crowdsec-bouncer` | **Config:** [`config/crowdsec/docker-compose.yml`](../config/crowdsec/docker-compose.yml)

**Collections:** `crowdsecurity/traefik`, `crowdsecurity/http-cve`

### How It Works

1. Traefik writes access logs to `/logs/access.log`
2. CrowdSec reads logs via shared Docker volume (`acquis.yaml`)
3. Detects malicious patterns (brute force, CVE exploits, etc.)
4. Creates "decisions" (bans) for offending IPs
5. Bouncer checks all incoming requests via ForwardAuth middleware
6. Blocked IPs receive 403 Forbidden

### LAPI Healthcheck

CrowdSec has a healthcheck (`cscli lapi status`, every 30s). The bouncer uses `depends_on: service_healthy` — prevents zombie process scenarios where CrowdSec appears running but LAPI is dead.

### Management Commands

```bash
# View metrics
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli metrics"

# List blocked IPs
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli decisions list"

# Manually ban an IP
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 24h --reason 'manual ban'"

# Remove a ban
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli decisions delete --ip 1.2.3.4"

# Update hub (download latest scenarios/parsers)
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli hub update && sudo docker exec crowdsec cscli hub upgrade"
```

---

## ntfy

**Purpose:** LAN-only pub/sub alert channel for blog-publisher failures and stale-heartbeat warnings emitted by cron jobs on `ubuntu-desktop` (VM 103).

**URL:** http://ntfy.nwlab.home.arpa (internal — LAN + WireGuard clients only, NOT exposed via Cloudflare tunnel)

**Container:** `ntfy` | **Config:** [`config/ntfy/docker-compose.yml`](../config/ntfy/docker-compose.yml)

**Data:** Docker volumes `ntfy_ntfy_cache` (message cache) + `ntfy_ntfy_etc` (optional auth DB). Server config at [`config/ntfy/server.yml`](../config/ntfy/server.yml).

### Topics

| Topic | Producers | Consumers | Purpose |
|-------|-----------|-----------|---------|
| `blog-publishers` | `scripts/cron-wrap.sh` and `scripts/check-publisher-health.sh` in each blog-publisher project on VM 103 | Subscribed mobile/desktop ntfy clients | Non-zero-exit alerts (high priority, tag `rotating_light`) + stale-heartbeat warnings (tag `hourglass_flowing_sand`) |

### Auth Posture

v1 is intentionally `auth-default-access: read-write` — producers on the trusted 10.21.21.0/24 segment POST unauthenticated. If abuse ever becomes an issue, flip to `deny-all` and issue a token:

```bash
ssh core@10.21.21.104 "sudo docker exec -it ntfy ntfy user add publisher"
ssh core@10.21.21.104 "sudo docker exec -it ntfy ntfy access publisher blog-publishers rw"
```

### Subscribing

Any ntfy client (ntfy iOS/Android, `ntfy subscribe`, or plain `curl`) can subscribe to `http://ntfy.nwlab.home.arpa/blog-publishers` while connected to the office LAN or WireGuard.

```bash
# Smoke test from VM 103
curl -fsS -d "smoke test" http://ntfy.nwlab.home.arpa/blog-publishers
```

### Management Commands

```bash
# View logs
ssh core@10.21.21.104 "sudo docker logs ntfy -f"

# Restart
ssh core@10.21.21.104 "cd /opt/ntfy && sudo /opt/bin/docker-compose restart"

# List topics currently cached
ssh core@10.21.21.104 "sudo docker exec ntfy ntfy subscribe --poll blog-publishers | tail"
```

### Traefik Route

Routed via the existing `traefik-public` network on the `web` entrypoint. Rule: `Host('ntfy.nwlab.home.arpa')`. No CrowdSec bouncer middleware (internal-only). No Cloudflare tunnel ingress — this hostname resolves on LAN only.

---

## OTel Collector

**Purpose:** Ingests OpenTelemetry metrics, traces and logs emitted by `claude --print` (Claude Code native telemetry) running inside blog-publisher cron jobs on `ubuntu-desktop` (VM 103). Fans out to local NDJSON files for forensics and to homelab Prometheus for dashboarding.

**Endpoints:**

| Protocol | URL | Notes |
|---|---|---|
| OTLP gRPC | `http://10.21.21.104:4317` | Preferred for headless Claude Code runs |
| OTLP HTTP | `http://10.21.21.104:4318` | Fallback / debug |
| Health check | `http://10.21.21.104:13133/` | Used by container healthcheck |

**Container:** `otel-collector` | **Config:** [`config/otel-collector/docker-compose.yml`](../config/otel-collector/docker-compose.yml), [`config/otel-collector/config.yaml`](../config/otel-collector/config.yaml)

**Data Location:** `/opt/otel-collector/data/` on flatcar-nwdesigns — rotating NDJSON files:
- `metrics.jsonl` — Claude Code session count, token usage, cost, API error counters
- `traces.jsonl` — spans from Claude Code runs
- `logs.jsonl` — Claude Code structured log events

Each file rotates at 50 MB, keeps 5 backups, and expires after 14 days.

**Prometheus fan-out:** metrics pipeline additionally remote-writes to homelab Prometheus at `http://192.168.100.100:9090/api/v1/write` (override via `PROMETHEUS_REMOTE_WRITE_URL` in `.env`). Retry + sending queue configured so a homelab outage does not drop metrics permanently.

### Environment Variables

| File | Variable | Description |
|------|----------|-------------|
| `.env` | `PROMETHEUS_REMOTE_WRITE_URL` | Override Prometheus remote-write endpoint (default: homelab flatcar-media) |

### VM 103 client config

Blog-publisher cron wrappers source `/etc/profile.d/claude-telemetry.sh` which exports:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://10.21.21.104:4318
```

Per-site `service.instance.id` is set by each project's `scripts/cron-wrap.sh` via `OTEL_RESOURCE_ATTRIBUTES`.

### jq Forensics

Query a specific site's logs from the NDJSON file exporter output:

```bash
# All log events for officinewordpress
ssh core@10.21.21.104 \
  "sudo jq 'select(.resourceLogs[].resource.attributes[] | select(.key==\"service.instance.id\" and .value.stringValue==\"officinewordpress\"))' \
   /opt/otel-collector/data/logs.jsonl"

# Last N metric points for costanzogoldtraders
ssh core@10.21.21.104 \
  "sudo tail -n 500 /opt/otel-collector/data/metrics.jsonl | \
   jq 'select(.resourceMetrics[].resource.attributes[] | select(.key==\"service.instance.id\" and .value.stringValue==\"costanzogoldtraders\"))'"

# Count API errors across all sites in the last file
ssh core@10.21.21.104 \
  "sudo jq '.resourceLogs[].scopeLogs[].logRecords[] | select(.severityText==\"ERROR\") | .body.stringValue' \
   /opt/otel-collector/data/logs.jsonl | wc -l"
```

### Management Commands

```bash
# View logs (debug exporter verbosity=basic)
ssh core@10.21.21.104 "sudo docker logs otel-collector -f"

# Restart after config changes
ssh core@10.21.21.104 "cd /opt/otel-collector && sudo /opt/bin/docker-compose restart"

# Probe the OTLP HTTP endpoint (should return 400 Bad Request — endpoint live)
ssh disconnesso@10.21.21.103 "curl -v http://10.21.21.104:4318/v1/traces \
  -H 'content-type: application/json' -d '{}' 2>&1 | tail -5"
```

### Note on Claude Code `Monitor` tool

The interactive-mode `Monitor` tool (CC ≥ 2.1.98) does **not** help headless `claude --print` runs — it cannot be hooked from outside a subprocess. Blog-publisher observability is instead built on `--output-format stream-json` parsing plus native OTEL telemetry emitted to this collector. See `ubuntu-desktop/CLAUDE.md` for the full pipeline notes.

---

## Autoheal

**Purpose:** Monitors all containers with healthchecks and auto-restarts unhealthy ones every 30s.

**Container:** `autoheal` | **Stack:** Infrastructure

- Checks all containers (`AUTOHEAL_CONTAINER_LABEL=all`)
- Waits 60s after startup before first check
- Requires Docker socket access (read-only), no network needed

```bash
# View restart events
ssh core@10.21.21.104 "sudo docker logs autoheal -f"

# Check which containers have healthchecks
ssh core@10.21.21.104 "sudo docker ps --format '{{.Names}}: {{.Status}}' | grep -i health"
```
