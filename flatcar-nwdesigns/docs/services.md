# Services Documentation

## Vaultwarden

**Purpose:** Self-hosted password manager compatible with Bitwarden clients.

**URL:** https://vaultwarden.nwdesigns.it

**Container:** `vaultwarden`

**Data Location:** `/opt/vaultwarden/data`

### Configuration

```yaml
# /opt/vaultwarden/docker-compose.yml
services:
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - DOMAIN=https://vaultwarden.nwdesigns.it
      - SMTP_HOST=smtp.gmail.com
      - SMTP_PORT=587
      - SMTP_SECURITY=starttls
      - SMTP_USERNAME=admin@nwdesigns.it
      - SMTP_FROM=admin@nwdesigns.it
      - SMTP_FROM_NAME=Vaultwarden
    volumes:
      - ./data:/data
    networks:
      - traefik-public
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vaultwarden.rule=Host(`vaultwarden.nwdesigns.it`)"
      - "traefik.http.routers.vaultwarden.entrypoints=web"
      - "traefik.http.routers.vaultwarden.middlewares=crowdsec-bouncer@docker"
      - "traefik.http.services.vaultwarden.loadbalancer.server.port=80"
```

### Environment Variables

| File | Variable | Description |
|------|----------|-------------|
| `.env` | `SMTP_PASSWORD` | Gmail App Password |

### SMTP Configuration

Vaultwarden uses Gmail SMTP for sending emails (invitations, password resets, etc.):

| Setting | Value |
|---------|-------|
| Provider | Gmail (Google Workspace) |
| From Address | admin@nwdesigns.it |
| From Name | Vaultwarden |
| Port | 587 (STARTTLS) |

To update the SMTP password:
```bash
# Edit the .env file on the VM
ssh core@10.21.21.104 "nano /opt/vaultwarden/.env"

# Restart Vaultwarden
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

**Container:** `n8n` + `n8n_postgres`

**Database:** PostgreSQL 15

### Configuration

```yaml
# /opt/n8n/docker-compose.yml
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n_postgres
      - N8N_HOST=n8n.nwdesigns.it
      - WEBHOOK_URL=https://n8n.nwdesigns.it
    networks:
      - traefik-public
      - n8n-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`n8n.nwdesigns.it`)"
      - "traefik.http.routers.n8n.entrypoints=web"
      - "traefik.http.routers.n8n.middlewares=crowdsec-bouncer@docker"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  postgres:
    image: postgres:15-alpine
    networks:
      - n8n-internal
```

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

**Purpose:** WhatsApp Business API gateway - enables sending/receiving WhatsApp messages via REST API.

**URL:** https://evolution.nwdesigns.it

**Manager UI:** https://evolution.nwdesigns.it/manager

**Containers:** `evolution_api` + `evolution_postgres` + `evolution_redis`

**Database:** PostgreSQL 15 + Redis 7

### Configuration

```yaml
# /opt/evolution-api/docker-compose.yml
services:
  evolution-api:
    image: atendai/evolution-api:latest
    environment:
      - SERVER_URL=https://evolution.nwdesigns.it
      - AUTHENTICATION_TYPE=apikey
      - DATABASE_PROVIDER=postgresql
      - CACHE_REDIS_ENABLED=true
    networks:
      - traefik-public
      - evolution-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.evolution.rule=Host(`evolution.nwdesigns.it`)"
      - "traefik.http.routers.evolution.entrypoints=web"
      - "traefik.http.routers.evolution.middlewares=crowdsec-bouncer@docker"
      - "traefik.http.services.evolution.loadbalancer.server.port=8080"

  postgres:
    image: postgres:15-alpine
    networks:
      - evolution-internal

  redis:
    image: redis:7-alpine
    networks:
      - evolution-internal
```

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

### Management Commands

```bash
# View Evolution API logs
ssh core@10.21.21.104 "sudo docker logs evolution_api -f"

# View PostgreSQL logs
ssh core@10.21.21.104 "sudo docker logs evolution_postgres -f"

# Restart Evolution API stack
ssh core@10.21.21.104 "cd /opt/evolution-api && sudo /opt/bin/docker-compose restart"

# Check connection status
ssh core@10.21.21.104 "curl -s http://localhost:8080 -H 'Host: evolution.nwdesigns.it'"

# Database backup
ssh core@10.21.21.104 "sudo docker exec evolution_postgres pg_dump -U evolution evolution > /tmp/evolution-db-backup.sql"
```

### Integration with n8n

Evolution API integrates with n8n for workflow automation (e.g., GitLab → Slack → WhatsApp notifications):

1. Create n8n workflow with Webhook Trigger
2. Add HTTP Request node pointing to Evolution API
3. Configure with your instance name and API key via n8n variables

---

## Portainer

**Purpose:** Docker management web UI.

**URL:** https://portainer.nwdesigns.it

**Container:** `portainer`

### Configuration

```yaml
# /opt/portainer/docker-compose.yml
services:
  portainer:
    image: portainer/portainer-ce:2.20.3
    ports:
      - "8000:8000"   # Edge agent
      - "9443:9443"   # Local HTTPS access
    volumes:
      - portainer_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(`portainer.nwdesigns.it`)"
      - "traefik.http.routers.portainer.entrypoints=web"
      - "traefik.http.routers.portainer.middlewares=crowdsec-bouncer@docker"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
```

### Local Access

For local network access (without going through Cloudflare):
- HTTPS: `https://10.21.21.104:9443`

---

## Traefik

**Purpose:** Reverse proxy and load balancer.

**Dashboard URL:** https://traefik.nwdesigns.it

**Local Dashboard:** http://10.21.21.104:8080

**Container:** `traefik`

### Key Features
- Automatic Docker container discovery via labels
- Access logging for CrowdSec analysis
- CrowdSec ForwardAuth middleware integration

### View Configured Routers

```bash
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/routers | jq '.[] | {name, rule}'"
```

### View Services

```bash
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/services | jq '.[] | {name, status}'"
```

### View Middlewares

```bash
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/middlewares | jq '.[] | .name'"
```

---

## Cloudflared

**Purpose:** Cloudflare Tunnel connector - exposes services to internet securely.

**Container:** `cloudflared`

**Tunnel Name:** `office-flatcar`

### View Tunnel Status

```bash
ssh core@10.21.21.104 "sudo docker logs cloudflared 2>&1 | grep -E '(Registered|Updated)' | tail -10"
```

### Tunnel Configuration

Managed via Cloudflare Zero Trust Dashboard:
1. Go to https://one.dash.cloudflare.com/
2. Networks → Tunnels → `office-flatcar`
3. Public Hostname tab

### Public Hostnames
| Hostname | Service | Origin |
|----------|---------|--------|
| vaultwarden.nwdesigns.it | HTTP | http://traefik:80 |
| n8n.nwdesigns.it | HTTP | http://traefik:80 |
| evolution.nwdesigns.it | HTTP | http://traefik:80 |
| portainer.nwdesigns.it | HTTP | http://traefik:80 |
| traefik.nwdesigns.it | HTTP | http://traefik:80 |

---

## CrowdSec

**Purpose:** Intrusion prevention system - analyzes Traefik access logs and blocks malicious IPs.

**Containers:** `crowdsec` + `crowdsec-bouncer`

### Components

| Component | Purpose |
|-----------|---------|
| CrowdSec Engine | Parses logs, detects threats, creates decisions |
| CrowdSec Bouncer | ForwardAuth middleware that enforces decisions |

### Collections Installed
- `crowdsecurity/traefik` - Traefik log parser and attack scenarios
- `crowdsecurity/http-cve` - HTTP CVE detection

### Configuration Files

| File | Purpose |
|------|---------|
| `/opt/crowdsec/docker-compose.yml` | Stack definition |
| `/opt/crowdsec/acquis.yaml` | Log acquisition config |
| `/opt/crowdsec/.env` | Bouncer API key |
| `/opt/crowdsec/config/` | CrowdSec configuration |
| `/opt/crowdsec/db/` | Decisions database |

### How It Works
1. Traefik writes access logs to `/logs/access.log`
2. CrowdSec reads logs via shared Docker volume
3. Detects malicious patterns (brute force, CVE exploits, etc.)
4. Creates "decisions" (bans) for offending IPs
5. Bouncer checks all incoming requests against decisions
6. Blocked IPs receive 403 Forbidden response

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

# List installed collections
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli collections list"

# View parsers
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli parsers list"

# View scenarios
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli scenarios list"

# Update hub (download latest scenarios/parsers)
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli hub update"

# Upgrade all components
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli hub upgrade"
```

### Bouncer Health Check

```bash
# Check bouncer connectivity to CrowdSec
ssh core@10.21.21.104 "sudo docker logs crowdsec-bouncer 2>&1 | tail -20"

# Test bouncer API
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/v1/ping" # From within network
```

### Adding Protection to New Services

Add these labels to any new service's docker-compose.yml:
```yaml
labels:
  - "traefik.http.routers.<service>.middlewares=crowdsec-bouncer@docker"
```
