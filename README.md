# NWLab

Infrastructure-as-documentation for the NWDesigns office Proxmox homelab.

## Overview

A ThinkPad (i5-6200U, 8GB RAM) running **Proxmox VE 9.1.5** hosts the office infrastructure: VPN, backups, and Docker services.

```
┌──────────────────────────────────────────────────────────────┐
│  thinkpad (10.21.21.99) — Proxmox VE 9.1.5                  │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │ WireGuard│  │   PBS    │  │TimeMachine│                   │
│  │ LXC 100  │  │ LXC 101  │  │ LXC 102  │                   │
│  │ .100     │  │ .101     │  │ .102     │                   │
│  │ VPN      │  │ Backups  │  │ Samba/TM │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
│                                                              │
│  ┌──────────────────┐                                        │
│  │ Flatcar VM 104   │                                        │
│  │ .104             │                                        │
│  │ Docker:          │                                        │
│  │  Traefik         │                                        │
│  │  Vaultwarden     │                                        │
│  │  n8n             │                                        │
│  │  Evolution API   │                                        │
│  │  Portainer       │                                        │
│  │  CrowdSec        │                                        │
│  └──────────────────┘                                        │
└──────────────────────────────────────────────────────────────┘
```

## Hardware

| Component | Spec |
|-----------|------|
| Model | Lenovo ThinkPad (i5-6200U) |
| CPU | 2 cores / 4 threads @ 2.30 GHz |
| RAM | 7.6 GB |
| Boot disk | 238.5 GB SSD (LVM: root + swap + thinpool) |
| Data disks | 2x 2.7 TB in ZFS mirror (`storage` pool) |

## Network

| Host | IP | Purpose |
|------|----|---------|
| thinkpad (PVE) | 10.21.21.99 | Proxmox hypervisor |
| wireguard | 10.21.21.100 | VPN gateway |
| proxmox-backup-server | 10.21.21.101 | PBS for VM/LXC backups |
| timemachine-samba | 10.21.21.102 | macOS Time Machine over SMB |
| flatcar-portainer | 10.21.21.104 | Docker services (Flatcar Linux) |

- **Subnet**: 10.21.21.0/24
- **Gateway**: 10.21.21.1
- **Bridge**: vmbr0 (physical: enp0s31f6)

## Storage

### Boot SSD (238.5 GB)

| Volume | Size | Usage |
|--------|------|-------|
| /boot/efi | 1 GB | EFI partition |
| pve-root | 70 GB (44% used) | Proxmox OS |
| pve-swap | 7.6 GB | Swap |
| pve-data (thinpool) | 142 GB (40% used) | VM/LXC disks |

### ZFS Mirror (2x 2.7 TB)

Pool `storage` — two disks in mirror (one is USB-attached).

| Dataset | Used | Available | Mount | Purpose |
|---------|------|-----------|-------|---------|
| storage/pbs | 231 GB | 24.5 GB | /storage/pbs | PBS datastore |
| storage/proxmox | 1 GB | 1.32 TB | /storage/proxmox | ZFS-backed VM storage |
| storage/timemachine | 1.09 TB | 1.32 TB | /timemachine | Time Machine backups |

> **Warning**: The USB disk in the mirror has read/checksum errors. Run `zpool status storage` to monitor.

## Services by Category

### Networking
- **WireGuard** (LXC 100) — VPN gateway for remote access

### Backups & Storage
- **Proxmox Backup Server** (LXC 101) — VM/LXC backup with deduplication
- **Time Machine Samba** (LXC 102) — macOS backups via SMB

### Docker Platform (Flatcar VM 104)
- **Traefik** — Reverse proxy + Let's Encrypt
- **Cloudflared** — Cloudflare tunnel for public access
- **CrowdSec** — Intrusion prevention
- **Vaultwarden** — Password manager (vaultwarden.nwdesigns.it)
- **n8n** — Workflow automation (n8n.nwdesigns.it)
- **Evolution API** — WhatsApp API (evolution.nwdesigns.it)
- **Portainer** — Docker management (portainer.nwdesigns.it)

## Web Interfaces

| Service | URL |
|---------|-----|
| Proxmox VE | https://10.21.21.99:8006 |
| Proxmox Backup Server | https://10.21.21.101:8007 |
| Portainer | https://portainer.nwdesigns.it |
| Traefik Dashboard | https://traefik.nwdesigns.it |
| Vaultwarden | https://vaultwarden.nwdesigns.it |
| n8n | https://n8n.nwdesigns.it |
| Evolution API | https://evolution.nwdesigns.it |

## Quick Start

```bash
# SSH into Proxmox host
ssh root@10.21.21.99

# List all guests
qm list && pct list

# Start/stop a container
pct start 100    # start WireGuard
pct stop 100     # stop it

# Console into a container
pct enter 101    # drop into PBS shell

# Check ZFS health
zpool status storage

# Check storage usage
zfs list
pvesm status
```

## Repository Structure

```
nwlab/
├── CLAUDE.md                     # AI assistant context (full infra details)
├── README.md                     # This file
├── .gitignore
└── flatcar-nwdesigns/            # VM 104 — Docker services
    ├── CLAUDE.md                 # VM-specific docs
    ├── config/                   # Docker Compose files (local mirror)
    │   ├── infrastructure/       # Traefik + Cloudflared
    │   ├── crowdsec/             # CrowdSec + Bouncer
    │   ├── vaultwarden/
    │   ├── n8n/
    │   ├── evolution-api/
    │   └── portainer/
    └── docs/
        ├── infrastructure.md
        └── services.md
```

Each VM/LXC that needs configuration management gets its own subdirectory with a `CLAUDE.md` and mirrored configs.

## Known Issues

1. **ZFS USB disk errors** — The USB-attached disk in the mirror pool shows read/checksum errors. Monitor closely; plan replacement.
2. **PBS storage nearly full** — `storage/pbs` has only ~24 GB free (231/256 GB used). Review backup retention or expand the ZFS quota.
3. **PVE firewall disabled** — No host-level firewall active. Security relies on network segmentation and per-service controls.
