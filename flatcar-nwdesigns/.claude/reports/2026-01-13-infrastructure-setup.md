# Infrastructure Setup Report

**Date:** 2026-01-13
**Session:** Initial infrastructure deployment + CrowdSec security

## Summary

Deployed a complete Docker infrastructure on Flatcar Linux VM with Traefik reverse proxy, Cloudflare Tunnel for public access, and CrowdSec intrusion prevention system.

## Work Completed

### 1. Vaultwarden Installation
- Installed Vaultwarden password manager
- Configured with persistent data storage at `/opt/vaultwarden/data`
- Integrated with Traefik for routing
- Protected by CrowdSec bouncer middleware

### 2. Traefik Reverse Proxy
- Deployed Traefik v3.3 as central reverse proxy
- Configured automatic Docker container discovery
- Dashboard exposed on port 8080 (local access)
- Access logging enabled for CrowdSec analysis
- CrowdSec ForwardAuth middleware configured

### 3. Cloudflare Tunnel
- Created tunnel `office-flatcar` via Cloudflare Zero Trust
- Deployed cloudflared container connected to Traefik
- Configured public hostnames (first-level subdomains for SSL compatibility):
  - vaultwarden.nwdesigns.it
  - n8n.nwdesigns.it
  - portainer.nwdesigns.it
  - traefik.nwdesigns.it

### 4. CrowdSec Security
- Deployed CrowdSec security engine
- Installed collections: `crowdsecurity/traefik`, `crowdsecurity/http-cve`
- Deployed traefik-crowdsec-bouncer for ForwardAuth
- Generated bouncer API key
- All services protected via middleware

### 5. Service Reconfiguration
- **n8n:** Reconfigured with Traefik labels, updated webhook URL to `https://n8n.nwdesigns.it`
- **Portainer:** Added to traefik-public network with routing labels

### 6. Project Structure
- Created local config mirror in `./config/`
- Created CLAUDE.md for project context
- Created documentation in `./docs/`

## Files Created/Modified

### On VM (`core@10.21.21.104`)
| Path | Action |
|------|--------|
| `/opt/infrastructure/docker-compose.yml` | Created (Traefik + Cloudflared) |
| `/opt/infrastructure/.env` | Created (tunnel token) |
| `/opt/crowdsec/docker-compose.yml` | Created |
| `/opt/crowdsec/acquis.yaml` | Created |
| `/opt/crowdsec/.env` | Created (bouncer API key) |
| `/opt/vaultwarden/docker-compose.yml` | Created |
| `/opt/n8n/docker-compose.yml` | Created |
| `/opt/portainer/docker-compose.yml` | Modified |

### Local Project
| Path | Action |
|------|--------|
| `CLAUDE.md` | Created/Updated |
| `config/infrastructure/docker-compose.yml` | Created |
| `config/crowdsec/docker-compose.yml` | Created |
| `config/crowdsec/acquis.yaml` | Created |
| `config/vaultwarden/docker-compose.yml` | Created |
| `config/n8n/docker-compose.yml` | Created |
| `config/portainer/docker-compose.yml` | Created |
| `docs/infrastructure.md` | Created |
| `docs/services.md` | Created |

## Container Status (End of Session)

| Container | Status | Network |
|-----------|--------|---------|
| traefik | Running | traefik-public |
| cloudflared | Running | traefik-public |
| crowdsec | Running (healthy) | traefik-public |
| crowdsec-bouncer | Running (healthy) | traefik-public |
| vaultwarden | Running (healthy) | traefik-public |
| n8n | Running | traefik-public, n8n-internal |
| n8n_postgres | Running | n8n-internal |
| portainer | Running | traefik-public |

## Public URLs (All Working)

- https://vaultwarden.nwdesigns.it ✓
- https://n8n.nwdesigns.it ✓
- https://portainer.nwdesigns.it ✓
- https://traefik.nwdesigns.it ✓

## Issues Resolved

### SSL Handshake Failure
- **Cause:** Cloudflare Universal SSL doesn't cover second-level subdomains (`*.office.nwdesigns.it`)
- **Fix:** Changed to first-level subdomains (`*.nwdesigns.it`)

## Verification Commands

```bash
# Check all containers
ssh core@10.21.21.104 "sudo docker ps"

# Test HTTPS
curl -s -o /dev/null -w "%{http_code}" https://vaultwarden.nwdesigns.it

# Check Traefik routers
ssh core@10.21.21.104 "curl -s http://localhost:8080/api/http/routers | jq '.[] | .name'"

# Check CrowdSec metrics
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli metrics"

# Check blocked IPs
ssh core@10.21.21.104 "sudo docker exec crowdsec cscli decisions list"
```

## Next Steps

1. Configure Vaultwarden admin settings
2. Set up backup procedures for data volumes
3. Consider adding Metabase dashboard for CrowdSec visualization
4. Monitor CrowdSec decisions for false positives
