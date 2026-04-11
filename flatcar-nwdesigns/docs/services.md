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

**URL:** https://ntfy.nwlab.nwdesigns.it (internal — LAN + WireGuard clients only, NOT exposed via Cloudflare tunnel)

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

Any ntfy client (ntfy iOS/Android, `ntfy subscribe`, or plain `curl`) can subscribe to `https://ntfy.nwlab.nwdesigns.it/blog-publishers` while connected to the office LAN or WireGuard. The hostname resolves on public Cloudflare DNS to the private 10.21.21.104 address, so any LAN resolver returns the correct IP without split-horizon tricks.

```bash
# Smoke test from VM 103
curl -fsS -d "smoke test" https://ntfy.nwlab.nwdesigns.it/blog-publishers
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

### Routing

**Primary path:** Caddy (see [Caddy](#caddy) below). Caddy joins the `traefik-public` network to reverse-proxy `https://ntfy.nwlab.nwdesigns.it` → `ntfy:80`. Wildcard LE cert via Cloudflare DNS-01, no CrowdSec bouncer (internal-only), no Cloudflare tunnel ingress — the hostname resolves on public DNS but points at the private 10.21.21.104 IP.

**Fallback path (soak only):** The original Traefik labels on the ntfy container remain in place for ~24h after the Caddy rollout so `http://ntfy.nwlab.home.arpa` keeps working as a rollback if Caddy cert issuance or the wildcard DNS record has any issue. Removed in a follow-up commit once the new path is proven.

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

**Prometheus fan-out:** metrics pipeline additionally remote-writes to the co-located Prometheus container on this same host at `http://prometheus:9090/api/v1/write` over the shared `observability` Docker bridge network (override via `PROMETHEUS_REMOTE_WRITE_URL` in `.env`). No cross-WireGuard or cross-host traffic. Retry + sending queue configured so brief Prometheus restarts do not drop metrics.

### Environment Variables

| File | Variable | Description |
|------|----------|-------------|
| `.env` | `PROMETHEUS_REMOTE_WRITE_URL` | Override Prometheus remote-write endpoint (default: `http://prometheus:9090/api/v1/write`) |

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

## Prometheus

**Purpose:** TSDB backend for the nwlab observability segment. Receives Claude Code metrics via `remote_write` from the co-located `otel-collector` container — both join the shared `observability` Docker bridge network so the collector targets `http://prometheus:9090/api/v1/write` directly. No scraping; no cross-WireGuard traffic.

**URL:** Internal-only. Bound to `127.0.0.1:9090` on the host for ad-hoc local debugging via SSH tunnel:

```bash
ssh -L 9090:127.0.0.1:9090 core@10.21.21.104
# then open http://localhost:9090 in a browser
```

**Container:** `prometheus` | **Config:** [`config/prometheus/docker-compose.yml`](../config/prometheus/docker-compose.yml), [`config/prometheus/prometheus.yml`](../config/prometheus/prometheus.yml)

**Data:** Docker volume `prometheus_prometheus_data` mounted at `/prometheus`. Retention: `--storage.tsdb.retention.time=30d` and `--storage.tsdb.retention.size=10GB` (whichever hits first).

**CLI flags of note:**
- `--web.enable-remote-write-receiver` — enables the `/api/v1/write` ingestion endpoint
- `--web.enable-lifecycle` — allows `POST /-/reload` for hot config reloads

### Reload after config edit

```bash
ssh core@10.21.21.104 "curl -X POST http://localhost:9090/-/reload"
```

### Management Commands

```bash
# View logs
ssh core@10.21.21.104 "sudo docker logs prometheus -f"

# Restart
ssh core@10.21.21.104 "cd /opt/prometheus && sudo /opt/bin/docker-compose restart"

# Quick remote_write smoke test (Grafana datasource path)
ssh core@10.21.21.104 "sudo docker exec grafana wget -qO- http://prometheus:9090/-/healthy"

# List active series count
ssh core@10.21.21.104 \
  "curl -s http://localhost:9090/api/v1/query?query=count\(\{__name__=~\\\".+\\\"\}\) | jq .data.result"
```

---

## Grafana

**Purpose:** Dashboard frontend for the nwlab Prometheus backend. Provisioned with a single Prometheus datasource (`http://prometheus:9090`) and a "Blog Publishers — Claude Code Observability" dashboard — run count per site, sessions vs API errors, token usage, cost per site, cost by site × model, last-run timestamps. Panel queries use the `instance` label (OTLP→Prom translation of `service.instance.id`).

**URL:** https://grafana.nwlab.nwdesigns.it (internal, LAN-only — served by Caddy with a wildcard LE cert via Cloudflare DNS-01, NOT exposed via the Cloudflare tunnel)

**Container:** `grafana` | **Config:** [`config/grafana/docker-compose.yml`](../config/grafana/docker-compose.yml)

**Data:** Docker volume `grafana_grafana_data` mounted at `/var/lib/grafana`.

### Provisioning

```
config/grafana/provisioning/
├── datasources/
│   └── prometheus.yml          # Static Prometheus datasource (default)
└── dashboards/
    ├── dashboards.yml          # File provider → folder "NWLab"
    └── blog-publishers.json    # Starter dashboard, uid `blog-publishers`
```

Edit JSON locally → rsync to flatcar-104 `/opt/grafana/provisioning/dashboards/` → Grafana reloads on its 30 s interval. The provisioned dashboard sets `allowUiUpdates: true` so live tweaks in the UI are not blown away on the next reload — but they are NOT persisted across container recreates unless saved back to the JSON file.

### Login

| Field | Value |
|---|---|
| URL | https://grafana.nwlab.nwdesigns.it |
| User | `admin` |
| Password | `${GRAFANA_ADMIN_PASSWORD}` from `/opt/grafana/.env` |

Bootstrap the password by writing `/opt/grafana/.env` with `GRAFANA_ADMIN_PASSWORD=<value>` before first `docker compose up -d`. Rotate from the Grafana UI (Server Admin → Users) afterward.

### Datasource

Static, provisioned, marked default and `editable: false`:

| Field | Value |
|---|---|
| Name | Prometheus |
| Type | prometheus |
| URL | `http://prometheus:9090` |
| Access | proxy |
| HTTP Method | POST |
| Time interval | 30s |

Resolves via the `observability` Docker bridge network. If grafana logs show `dial tcp: lookup prometheus`, the prometheus stack is down or the network was not created — bring `/opt/prometheus/` up first.

### Dashboard Panels

`blog-publishers.json` uses Claude Code native OTEL metrics as translated by the OTLP→Prom receiver — label is `instance` (NOT `service_instance_id`). Current panels:

1. **Run count per site (last 24h)** — `sum by (instance) (increase(claude_code_session_count_total{instance=~".*(officine|ambrosiano|costanzo).*"}[24h]))`
2. **Sessions vs API errors (last 24h)** — donut chart comparing `claude_code_session_count_total` against `claude_code_api_error_total`. Claude Code native OTEL has no per-session success/failure counter, so raw error counts are the best-effort signal.
3. **Token usage** — stacked bars by `instance` and `type` using `claude_code_token_usage_tokens_total`
4. **Total cost per site (USD)** — stat panel by `instance` using `claude_code_cost_usage_USD_total`, thresholds at $5 / $20
5. **Cost by site × model** — stacked bars by `instance` and `model` label (Claude Code tags every cost sample with the model name, e.g. `claude-haiku-4-5-20251001`, `claude-sonnet-4-6`)
6. **Last-run timestamp per site** — `timestamp(last_over_time(...))` surfaces silent gaps

The p95 API duration panel was removed — Claude Code native OTEL does not export a request-duration histogram. Re-add if/when `claude_code_api_request_duration_seconds_bucket` shows up in `http://localhost:9090/api/v1/label/__name__/values`.

### Management Commands

```bash
# View logs
ssh core@10.21.21.104 "sudo docker logs grafana -f"

# Restart
ssh core@10.21.21.104 "cd /opt/grafana && sudo /opt/bin/docker-compose restart"

# Force a dashboard rescan (provisioner runs every 30s normally)
ssh core@10.21.21.104 "sudo docker exec grafana curl -s http://localhost:3000/api/admin/provisioning/dashboards/reload \
  -u admin:\$GRAFANA_ADMIN_PASSWORD -X POST"
```

---

## Caddy

**Purpose:** Internal wildcard TLS reverse proxy for nwlab-only services (`*.nwlab.nwdesigns.it`). Sits alongside Traefik on flatcar-104 — Traefik keeps the public Cloudflare tunnel path for `*.nwdesigns.it`, Caddy serves the internal LAN with browser-trusted Let's Encrypt certificates so mobile ntfy subscribers and browsers stop seeing HTTP warnings.

**URL:** `https://*.nwlab.nwdesigns.it` (LAN + WireGuard only — A record points at private 10.21.21.104 on public Cloudflare DNS, grey-cloud / DNS-only, no proxy)

**Container:** `caddy` | **Stack:** [`config/caddy/`](../config/caddy/)

### Network & Port Layout

Caddy runs in **bridge mode**, NOT host mode — flatcar-104 already has Traefik owning host `:80`/`:8080` for the public tunnel. Caddy binds only `:443` on the host and joins two docker networks for backend DNS:

- `traefik-public` → reaches `ntfy`
- `observability` → reaches `grafana`, `prometheus`, `otel-collector`

The Caddyfile sets `http_port 8090` so Caddy's default :80 listener (which it opens for ACME HTTP-01 fallback even when DNS-01 is configured) parks on an unused internal port and does not collide with Traefik. ACME HTTP-01 is never used because the wildcard certificate is issued entirely via **Cloudflare DNS-01**.

### TLS

Single wildcard certificate for `*.nwlab.nwdesigns.it` issued by Let's Encrypt via the `caddy-dns/cloudflare` plugin. The plugin needs a scoped Cloudflare API token with `Zone:Read` + `DNS:Edit` on the `nwdesigns.it` zone — **not** the same token as `CLOUDFLARE_TUNNEL_TOKEN`.

The token lives as a Docker secret file at `/opt/caddy/secrets/cloudflare_api_token` (chmod 600, gitignored via `config/caddy/.gitignore`). `entrypoint.sh` reads `/run/secrets/cloudflare_api_token` into the `CF_API_TOKEN` env var that the Caddyfile's `tls { dns cloudflare {env.CF_API_TOKEN} }` directive interpolates.

Caddy's on-disk state (cert cache, OCSP staples, account data) lives in host-mounted volumes `/opt/caddy/data` and `/opt/caddy/config`.

### Sites

Per-subdomain matchers live in [`config/caddy/sites/nwlab.caddy`](../config/caddy/sites/nwlab.caddy):

| Hostname | Backend | Notes |
|---|---|---|
| `grafana.nwlab.nwdesigns.it` | `grafana:3000` | Via `observability` network |
| `ntfy.nwlab.nwdesigns.it` | `ntfy:80` | Via `traefik-public` network |
| `prometheus.nwlab.nwdesigns.it` | `prometheus:9090` | Via `observability` network |

Anything not matched falls through to `handle { respond "Not Found" 404 }` at the wildcard-site level. Add future services by appending a new `@name host ...` matcher to `sites/nwlab.caddy` and redeploying — no Caddyfile root edit required.

### Manual prerequisites (one-time)

Before the stack can come up:

1. **Cloudflare API token** at https://dash.cloudflare.com/profile/api-tokens → Create Custom token
   - Permissions: `Zone / Zone / Read` + `Zone / DNS / Edit`
   - Zone Resources: `Include / Specific zone / nwdesigns.it`
   - TTL: no expiry
2. **Wildcard DNS A record** in the Cloudflare `nwdesigns.it` zone
   - Name: `*.nwlab`, Type: `A`, IPv4: `10.21.21.104`, Proxy: DNS only (grey cloud)

### Management Commands

```bash
# Build + start (first deploy)
ssh core@10.21.21.104 "cd /opt/caddy && sudo /opt/bin/docker-compose build && sudo /opt/bin/docker-compose up -d"

# View logs (cert issuance + ACME challenge output)
ssh core@10.21.21.104 "sudo docker logs caddy -f"

# Validate Caddyfile
ssh core@10.21.21.104 "sudo docker exec caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile"

# Hot reload after editing Caddyfile / sites/*.caddy (no container recreate)
ssh core@10.21.21.104 "sudo docker exec caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile"

# Check issued cert metadata from a workstation
curl -sS -o /dev/null -w "http=%{http_code} tls=%{ssl_verify_result}\n" https://grafana.nwlab.nwdesigns.it/api/health
```

### Rollback

The original Traefik `Host('*.nwlab.home.arpa')` labels on ntfy + grafana are kept in place for ~24h after the initial Caddy rollout to give a clean fallback. During the soak both paths resolve:

- New: `https://*.nwlab.nwdesigns.it` via Caddy (Cloudflare DNS-01)
- Old: `http://*.nwlab.home.arpa` via Traefik + `/etc/hosts` overrides on flatcar-104 + VM 103

Once the new path is proven for 24h, a follow-up commit strips the Traefik labels from the ntfy/grafana compose files and removes the `/etc/hosts` overrides on both hosts.

### Observability

No self-metrics wired yet — Caddy exposes Prometheus metrics on its admin endpoint (`:2019/metrics`) but a dedicated scrape job is out of scope for this rollout. Follow-up: add a `caddy` scrape target to [`config/prometheus/prometheus.yml`](../config/prometheus/prometheus.yml) once the first cert-related incident happens.

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
