# NWLab

Infrastructure-as-documentation for the NWDesigns office Proxmox homelab.

## Overview

A ThinkPad (i5-6200U, 8GB RAM) running **Proxmox VE 9.1.6** hosts the office infrastructure: VPN, backups, and Docker services.

```
┌──────────────────────────────────────────────────────────────┐
│  thinkpad (10.21.21.99) — Proxmox VE 9.1.6                  │
│  7.6 GB RAM │ 11 GB swap (3.8 GB zram + 7.6 GB LVM)         │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │ WireGuard│  │   PBS    │  │TimeMachine│                   │
│  │ LXC 100  │  │ LXC 101  │  │ LXC 102  │                   │
│  │ .100     │  │ .101     │  │ .102      │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
│                                                              │
│  ┌──────────────────────────────┐  ┌─────────────────┐       │
│  │ Flatcar VM 104               │  │ Ubuntu VM 103   │       │
│  │ .104 │ Docker 28.0.4         │  │ .103 │ 26.04LTS │       │
│  │ 14 containers / 8 stacks     │  │ Claude Code CLI │       │
│  │ Traefik, CrowdSec,          │  │ + blog-publisher│       │
│  │ Vaultwarden, n8n,           │  │   cron jobs     │       │
│  │ Evolution API, Portainer,   │  └─────────────────┘       │
│  │ OTel Collector, ntfy        │                            │
│  └──────────────────────────────┘                            │
│                                                              │
│  Host: wazuh-agent, prometheus, chrony, postfix, ksmtuned    │
└──────────────────────────────────────────────────────────────┘
```

## Network

| Host                  | IP           | Purpose                             |
| --------------------- | ------------ | ----------------------------------- |
| thinkpad              | 10.21.21.99  | Proxmox hypervisor                  |
| wireguard             | 10.21.21.100 | VPN gateway                         |
| proxmox-backup-server | 10.21.21.101 | PBS for VM/LXC backups              |
| timemachine-samba     | 10.21.21.102 | macOS Time Machine over SMB         |
| ubuntu-desktop        | 10.21.21.103 | Claude Code workstation + blog-publisher cron jobs |
| flatcar-portainer     | 10.21.21.104 | Docker services (Flatcar Linux)     |
| ntfy                  | 10.21.21.104 (http://ntfy.nwlab.home.arpa) | Blog-publisher alert channel (LAN-only) |
| otel-collector        | 10.21.21.104 (:4317 / :4318) | Blog-publisher telemetry ingest (→ NDJSON + homelab Prometheus) |

## Web Interfaces

| Service       | URL                              |
| ------------- | -------------------------------- |
| Proxmox VE    | https://10.21.21.99:8006         |
| PBS           | https://10.21.21.101:8007        |
| Portainer     | https://portainer.nwdesigns.it   |
| Traefik       | https://traefik.nwdesigns.it     |
| Vaultwarden   | https://vaultwarden.nwdesigns.it |
| n8n           | https://n8n.nwdesigns.it         |
| Evolution API | https://evolution.nwdesigns.it   |
| ntfy          | http://ntfy.nwlab.home.arpa      |

## Quick Start

```bash
ssh root@10.21.21.99          # Proxmox host
ssh core@10.21.21.104         # Flatcar VM (Docker)

qm list && pct list            # List all guests
pct enter 101                  # Console into PBS
zpool status storage           # ZFS health
ssh core@10.21.21.104 "sudo docker ps"  # Docker containers
```

## Repository Structure

```
nwlab/
├── CLAUDE.md                     # Full infrastructure reference (AI + human)
├── README.md                     # This file — quick overview
├── docs/
│   └── backups.md                # Backup architecture, schedule, restore
├── flatcar-nwdesigns/            # VM 104 — Docker services
│   ├── CLAUDE.md                 # VM-specific reference
│   ├── config/                   # Docker Compose files (local mirror)
│   └── docs/                     # infrastructure.md, services.md
└── ubuntu-desktop/               # VM 103 — Lubuntu 26.04 Claude Code workstation
    └── CLAUDE.md                 # VM-specific reference
```

## Backup Strategy

Daily @ 01:00 → GC @ 03:00 → Remote sync @ 04:00 (push over WireGuard VPN).
Retention: 7 daily / 4 weekly / 2 monthly. Full docs: [docs/backups.md](docs/backups.md)

## Known Issues

1. **Pending kernel update** — Running 6.17.4-1-pve, 6.17.9-1-pve installed. Reboot needed.
2. **ZFS USB disk errors** — USB-attached mirror disk has 4 read / 8 checksum errors. Plan replacement.
3. **Stale PBS self-backup** — Last LXC 101 backup from 2025-09-29 (5+ months old).
4. **PVE firewall disabled** — Service running but policy disabled. No active rules.

---

_Last audited: 2026-04-08 via live SSH_
