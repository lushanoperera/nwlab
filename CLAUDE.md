# NWLab - Proxmox Infrastructure

## Proxmox Host (thinkpad)
- **Hostname**: thinkpad
- **IP**: 10.21.21.99
- **Web UI**: https://10.21.21.99:8006
- **Location**: NWDesigns office
- **PVE Version**: 9.1.5 (kernel 6.17.4-1-pve)
- **CPU**: Intel i5-6200U (2C/4T @ 2.30GHz)
- **RAM**: 7.6 GB
- **SSH**: `ssh root@10.21.21.99`

## Network
- **Subnet**: `10.21.21.0/24`
- **Gateway**: `10.21.21.1`
- **Bridge**: `vmbr0` (port: `enp0s31f6`)
- **DNS**: 9.9.9.9, 8.8.8.8, 1.1.1.1
- **Firewall**: disabled

## Storage

| Name | Type | Size | Used | Content | Notes |
|------|------|------|------|---------|-------|
| local | dir | 70 GB | 44% | ISOs, backups, snippets | `/var/lib/vz` (SSD) |
| local-lvm | LVM-thin | 142 GB | 40% | VM/LXC disks | `pve/data` thinpool (SSD) |
| proxmox-storage | ZFS pool | 1.35 TB | <1% | VM/LXC disks | `storage/proxmox` (HDD mirror) |

### Disks
- **sda** (238.5 GB SSD): PVE boot, LVM (root + swap + thinpool)
- **sdb + sdc** (2x 2.7 TB): ZFS mirror pool `storage`
  - **sdc is USB** — has read/checksum errors, monitor with `zpool status storage`

### ZFS Datasets
| Dataset | Used | Avail | Mountpoint |
|---------|------|-------|------------|
| storage | 1.31 TB | 1.32 TB | /storage |
| storage/pbs | 231 GB | 24.5 GB | /storage/pbs |
| storage/proxmox | 1 GB | 1.32 TB | /storage/proxmox |
| storage/timemachine | 1.09 TB | 1.32 TB | /timemachine |

## Guests

| VMID | Type | Name | IP | Status | Cores | RAM | Disk | Storage | Autostart |
|------|------|------|----|--------|-------|-----|------|---------|-----------|
| 100 | LXC | wireguard | 10.21.21.100 | running | 1 | 512 MB | 8 GB | local-lvm | yes |
| 101 | LXC | proxmox-backup-server | 10.21.21.101 | running | 4 | 512 MB | 10 GB | local-lvm | yes |
| 102 | LXC | timemachine-samba | 10.21.21.102 | running | 1 | 512 MB | 8 GB | local-lvm | yes |
| 104 | VM | flatcar-portainer-104 | 10.21.21.104 | running | 2 | 4096 MB | 8.5 GB | local-lvm | yes |

### Guest Bind Mounts
| VMID | Host Path | Guest Mountpoint |
|------|-----------|------------------|
| 101 | /storage/pbs | /mnt/datastore |
| 102 | /timemachine | /timemachine |

### Guest Tags
| VMID | Tags |
|------|------|
| 100 | network, vpn |
| 101 | backup |

## Web UIs
| Service | URL |
|---------|-----|
| Proxmox VE | https://10.21.21.99:8006 |
| PBS | https://10.21.21.101:8007 |

## Project Structure
```
nwlab/
├── CLAUDE.md                  # This file — infrastructure overview
├── README.md                  # Human-readable project documentation
├── flatcar-nwdesigns/         # VM 104: Flatcar Docker services
│   ├── CLAUDE.md              # VM-specific docs & commands
│   ├── config/                # Docker Compose configs (mirror of VM)
│   └── docs/                  # Service documentation
└── (future VM/LXC dirs)
```

## Conventions
- Each VM/LXC gets its own subdirectory with a `CLAUDE.md`
- Configs stored locally mirror what's deployed on the guest
- Secrets never committed — use `.env.example` templates
- SSH access: `ssh <user>@<ip>` (user depends on guest OS)
- Most LXCs deployed via community-scripts (Helper-Scripts.com)

## Common Commands
```bash
# Proxmox host
ssh root@10.21.21.99
ssh root@10.21.21.99 "qm list && pct list"

# Guest shells
ssh root@10.21.21.100   # WireGuard
ssh root@10.21.21.101   # PBS
ssh root@10.21.21.102   # Time Machine
ssh core@10.21.21.104   # Flatcar (Docker)

# Storage
ssh root@10.21.21.99 "zpool status storage"        # ZFS health
ssh root@10.21.21.99 "zfs list"                     # Dataset usage
ssh root@10.21.21.99 "pvesm status"                 # PVE storage overview

# Guest management
ssh root@10.21.21.99 "pct start <VMID>"             # Start LXC
ssh root@10.21.21.99 "pct stop <VMID>"              # Stop LXC
ssh root@10.21.21.99 "pct enter <VMID>"             # Console into LXC
ssh root@10.21.21.99 "qm start <VMID>"              # Start VM
```

## Warnings
- **ZFS USB disk errors**: `usb-External_USB3.0_20170331000D1` has read/checksum errors. Monitor via `zpool status storage`. Consider replacing.
- **PBS quota near full**: `storage/pbs` — 231 GB used, only 24.5 GB free. Review retention or expand quota.
- **Firewall disabled**: PVE firewall is off. Rely on network-level controls or enable per-guest rules.

## Backup Strategy
- **PBS** (LXC 101 @ 10.21.21.101): Proxmox Backup Server
- **Datastore**: `/mnt/datastore` (bind mount from host `/storage/pbs`)
- **Web UI**: https://10.21.21.101:8007
- Schedule and retention policies: configure in PBS web UI
