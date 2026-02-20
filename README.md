# NWLab

Infrastructure-as-documentation for the NWDesigns office Proxmox homelab.

## Overview

A ThinkPad (i5-6200U, 8GB RAM) running **Proxmox VE 9.1.5** hosts the office infrastructure: VPN, backups, and Docker services.

```
┌──────────────────────────────────────────────────────────────┐
│  thinkpad (10.21.21.99) — Proxmox VE 9.1.5                  │
│  Kernel: 6.17.4-1-pve (6.17.9 installed, reboot pending)    │
│  RAM: 7.6 GB (85% used) │ Swap: 11 GB (1.9 GB used)        │
│  Uptime: 60+ days                                            │
│                                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │ WireGuard│  │   PBS    │  │TimeMachine│                   │
│  │ LXC 100  │  │ LXC 101  │  │ LXC 102  │                   │
│  │ .100     │  │ .101     │  │ .102      │                   │
│  │ VPN      │  │ Backups  │  │ Samba/TM  │                   │
│  │ disk: 71%│  │ disk: 89%│  │ disk: 26% │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
│                                                              │
│  ┌──────────────────────────────┐                            │
│  │ Flatcar VM 104               │                            │
│  │ .104 │ disk: 25% (28.5 GB)   │                            │
│  │ Docker 28.0.4 (11 running)   │                            │
│  │ 11 containers / 6 stacks:    │                            │
│  │  Traefik, Cloudflared,       │                            │
│  │  CrowdSec, Vaultwarden,      │                            │
│  │  n8n, Evolution API,         │                            │
│  │  Portainer + databases       │                            │
│  └──────────────────────────────┘                            │
│                                                              │
│  Host services: wazuh-agent, prometheus-node-exporter,       │
│  iperf3, chrony, postfix, smartmontools                      │
└──────────────────────────────────────────────────────────────┘
```

## Hardware

| Component | Spec | Live Status |
|-----------|------|-------------|
| Model | Lenovo ThinkPad (i5-6200U) | 60+ days uptime |
| CPU | 2 cores / 4 threads @ 2.30 GHz | Load avg: 2.18 |
| RAM | 7.6 GB + 11 GB swap (3.8 GB zram + 7.6 GB LVM) | 85% used, 1.9 GB swapped |
| Boot disk | 238.5 GB SSD (LVM: root + swap + thinpool) | root 44%, thinpool 18% |
| Data disks | 2x 2.7 TB in ZFS mirror (`storage` pool) | 48% capacity, 35% frag |

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
- **DNS**: 9.9.9.9, 8.8.8.8, 1.1.1.1 (search: `station`)
- **FQDN**: `thinkpad.nwdesigns.home.arpa`

## Storage

### Boot SSD (238.5 GB)

| Volume | Size | Usage |
|--------|------|-------|
| /boot/efi | 1 GB | EFI partition |
| pve-root | 70 GB (44% used) | Proxmox OS |
| pve-swap | 7.6 GB | Swap |
| pve-data (thinpool) | 142 GB (18% used) | VM/LXC disks |

### ZFS Mirror (2x 2.7 TB)

Pool `storage` — two disks in mirror (one is USB-attached, has 4 read / 8 checksum errors).

| Dataset | Used | Available | Quota | Mount | Purpose |
|---------|------|-----------|-------|-------|---------|
| storage/pbs | 235 GB | 265 GB | 500 GB | /storage/pbs | PBS datastore |
| storage/proxmox | 24 KB | 1.32 TB | none | /storage/proxmox | ZFS-backed VM storage |
| storage/timemachine | 1.09 TB | 1.32 TB | 2.5 TB | /timemachine | Time Machine backups |

## Services by Category

### Networking
- **WireGuard** (LXC 100) — VPN gateway for remote access

### Backups & Storage
- **Proxmox Backup Server** (LXC 101) — VM/LXC backup with deduplication
- **Time Machine Samba** (LXC 102) — macOS backups via SMB

### Host Services
- **wazuh-agent** — Security monitoring (SIEM)
- **prometheus-node-exporter** — System metrics
- **iperf3** — Network speed testing
- **chrony** — NTP time sync
- **postfix** — Local mail relay

### Docker Platform (Flatcar VM 104)

11 containers across 6 stacks:

| Stack | Containers | Purpose |
|-------|-----------|---------|
| Infrastructure | traefik, cloudflared | Reverse proxy + CF tunnel |
| CrowdSec | crowdsec, crowdsec-bouncer | Intrusion prevention |
| Vaultwarden | vaultwarden | Password manager |
| n8n | n8n, n8n_postgres | Workflow automation |
| Evolution API | evolution_api, evolution_postgres, evolution_redis | WhatsApp API |
| Portainer | portainer | Docker management |

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

## Backup Strategy

- **Daily @ 01:00**: vzdump snapshots of LXC 100, 102 + VM 104 to PBS (`pbs-nwlab`)
- **GC @ 03:00**: PBS garbage collection
- **Remote sync @ 04:00**: Push to homelab PBS (`pbs-backups` @ 10.0.0.6 via WireGuard)
- **Retention**: 7 daily / 4 weekly / 2 monthly
- **Full docs**: [docs/backups.md](docs/backups.md)

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

# SSH into Flatcar VM
ssh core@10.21.21.104

# Check Docker containers
ssh core@10.21.21.104 "sudo docker ps"

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
├── docs/
│   └── backups.md                # Backup architecture, schedule, restore
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

1. ~~**VM 104 root disk FULL**~~ — **RESOLVED** (2026-02-20). Expanded from 8.5 GB to 28.5 GB. Now 25% used, Docker running normally.
2. **VM 101 disk at 89%** — PBS LXC root disk approaching capacity. Monitor and plan expansion.
3. **Host RAM under pressure** — 85% used (6.5/7.6 GB), 1.9 GB swapped. VM 104 alone uses 4 GB.
4. **Pending kernel update** — Running 6.17.4-1-pve, 6.17.9-1-pve installed. Reboot needed.
5. **ZFS USB disk errors** — The USB-attached disk in the mirror pool has 4 read / 8 checksum errors. Plan replacement.
6. **Orphaned backups** — 9 backups for deleted VMID 103 on PBS. Should be pruned.
7. **Stale PBS self-backup** — Last LXC 101 backup is from 2025-10-06 (4+ months old).
8. **PVE firewall disabled** — Service running but policy disabled. No active rules.

---

*Last audited: 2026-02-20 via live SSH*
