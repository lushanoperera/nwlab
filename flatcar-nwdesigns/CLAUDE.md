# Flatcar Linux VM - Docker Services

## VM Specs
| Property | Value |
|----------|-------|
| **VMID** | 104 |
| **OS** | Flatcar Container Linux 4459.2.3 (Oklo) |
| **Kernel** | 6.12.66-flatcar |
| **Docker** | 28.0.4 |
| **Docker Compose** | v2.27.0 (`/opt/bin/docker-compose`) |
| **CPU** | 2 cores (1 socket, q35 machine) |
| **RAM** | 4096 MB (balloon min 2560 MB — PVE can reclaim up to 1.5 GiB when idle) |
| **Swap** | 2 GB (`/swapfile`) + 1 GB zram (`/dev/zram0`, lzo-rle, priority 100) |
| **Swappiness** | 80 (`/etc/sysctl.d/99-swappiness.conf`) |
| **Disk** | 28.5 GB on local-lvm (EFI 4M + root 26.2 GB partition) |
| **BIOS** | OVMF (UEFI) |
| **Network** | virtio on vmbr0 |
| **Ignition** | `/var/lib/vz/snippets/flatcar-104.ign` (on PVE host) |

## VM Connection
```bash
ssh core@10.21.21.104
```

## Architecture
```
Internet → Cloudflare → cloudflared tunnel → Traefik (:80) → CrowdSec Bouncer → Services
```

## Services (12 containers, 6 stacks)
| Service | Internal Port | Public URL |
|---------|---------------|------------|
| Vaultwarden | 80 | https://vaultwarden.nwdesigns.it |
| n8n | 5678 | https://n8n.nwdesigns.it |
| Evolution API | 8080 | https://evolution.nwdesigns.it |
| Portainer | 9000 | https://portainer.nwdesigns.it |
| Traefik Dashboard | 8080 | https://traefik.nwdesigns.it |

Supporting containers: cloudflared, crowdsec, crowdsec-bouncer, n8n_postgres, evolution_postgres, evolution_redis.
Infrastructure containers: autoheal (auto-restarts unhealthy containers every 30s).

## Security
- All services protected via CrowdSec ForwardAuth middleware (`crowdsec-bouncer@docker`)
- Details: [docs/services.md — CrowdSec](docs/services.md#crowdsec)

## VM Paths
All stacks live under `/opt/<service>/` with `.env` files for secrets (not in docker-compose.yml).
Local mirrors: `config/*/docker-compose.yml` + `.env.example` templates.

| Stack | Path | Secret Vars |
|-------|------|-------------|
| Infrastructure | `/opt/infrastructure/` | `CLOUDFLARE_TUNNEL_TOKEN` |
| CrowdSec | `/opt/crowdsec/` | `CROWDSEC_BOUNCER_API_KEY` |
| Vaultwarden | `/opt/vaultwarden/` | `SMTP_PASSWORD` |
| n8n | `/opt/n8n/` | — |
| Evolution API | `/opt/evolution-api/` | `AUTHENTICATION_API_KEY`, `POSTGRES_PASSWORD` |
| Portainer | `/opt/portainer/` | — |

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

## Key Config Notes
- Docker network: `traefik-public` — all services must join for Traefik routing
- Cloudflare Tunnel: `office-flatcar` — managed via [Zero Trust Dashboard](https://one.dash.cloudflare.com/)
- Vaultwarden SMTP: Gmail (admin@nwdesigns.it) — app password in `.env`
- Full service docs: [docs/services.md](docs/services.md) | Architecture: [docs/infrastructure.md](docs/infrastructure.md)

## Known Issues

### Active
- Memory limits set on all containers (~3 GB total budget on 4 GB VM). Autoheal auto-restarts unhealthy containers.
- Balloon enabled (min 2560 MB), zram swap (1 GiB lzo-rle), swappiness 80. Persisted via `zram-swap.service` + `/etc/sysctl.d/99-swappiness.conf`.
- Monitor Docker data growth — `docker system df` to check image/volume sizes.

### Resolved
- ~~Root disk full~~ (2026-02-20): Expanded 8.5→28.5 GB. Now 33%.
- ~~No swap~~ (2026-02-24): 2 GB swapfile at `/swapfile` + 1 GB zram added.
- ~~Cascade OOM~~ (2026-02-24): Memory limits + autoheal prevent cascade failures.
