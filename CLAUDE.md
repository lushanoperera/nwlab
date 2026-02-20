# NWLab - Proxmox Infrastructure

## Proxmox Host (thinkpad)
- **Hostname**: thinkpad (`thinkpad.nwdesigns.home.arpa`)
- **IP**: 10.21.21.99
- **Web UI**: https://10.21.21.99:8006
- **Location**: NWDesigns office
- **PVE Version**: 9.1.5 (running kernel 6.17.4-1-pve, 6.17.9-1-pve installed — reboot pending)
- **CPU**: Intel i5-6200U (2C/4T @ 2.30GHz)
- **RAM**: 7.6 GB (85% used, 1.9 GiB swapped — under pressure)
- **SSH**: `ssh root@10.21.21.99`

## Network
- **Subnet**: `10.21.21.0/24`
- **Gateway**: `10.21.21.1`
- **Bridge**: `vmbr0` (port: `enp0s31f6`)
- **DNS**: 9.9.9.9, 8.8.8.8, 1.1.1.1
- **DNS search**: `station`
- **Firewall**: disabled (service running, policy disabled)

## Storage

| Name | Type | Size | Used | Content | Notes |
|------|------|------|------|---------|-------|
| local | dir | 70 GB | 44% | ISOs, backups, snippets | `/var/lib/vz` (SSD) |
| local-lvm | LVM-thin | 142 GB | 18% | VM/LXC disks | `pve/data` thinpool (SSD) |
| proxmox-storage | ZFS pool | 1.35 TB | <1% | VM/LXC disks | `storage/proxmox` (HDD mirror) |
| pbs-nwlab | PBS | 500 GB | 47% | backups | PBS @ 10.21.21.101 `home-backup` |

### Disks
- **sda** (238.5 GB SSD): PVE boot, LVM (root + swap + thinpool)
- **sdb + sdc** (2x 2.7 TB): ZFS mirror pool `storage`
  - **sdc is USB** — has read/checksum errors, monitor with `zpool status storage`

### ZFS Datasets
| Dataset | Used | Avail | Quota | Mountpoint |
|---------|------|-------|-------|------------|
| storage | 1.32 TB | 1.32 TB | none | /storage |
| storage/pbs | 235 GB | 265 GB | 500 GB | /storage/pbs |
| storage/proxmox | 24 KB | 1.32 TB | none | /storage/proxmox |
| storage/timemachine | 1.09 TB | 1.32 TB | 2.5 TB | /timemachine |

## Guests

| VMID | Type | Name | IP | Status | Cores | RAM | Disk | Storage | Autostart | Disk Used |
|------|------|------|----|--------|-------|-----|------|---------|-----------|-----------|
| 100 | LXC | wireguard | 10.21.21.100 | running | 1 | 512 MB | 8 GB | local-lvm | yes | 71% |
| 101 | LXC | proxmox-backup-server | 10.21.21.101 | running | 4 | 512 MB | 10 GB | local-lvm | yes | 89% |
| 102 | LXC | timemachine-samba | 10.21.21.102 | running | 1 | 512 MB | 8 GB | local-lvm | yes | 26% |
| 104 | VM | flatcar-portainer-104 | 10.21.21.104 | running | 2 | 4096 MB | 28.5 GB | local-lvm | yes | 25% |

### Guest Bind Mounts
| VMID | Host Path | Guest Mountpoint |
|------|-----------|------------------|
| 101 | /storage/pbs | /mnt/datastore |
| 102 | /timemachine | /timemachine |

### Guest Tags
| VMID | Tags |
|------|------|
| 100 | community-script, network, vpn |
| 101 | backup, community-script |
| 102 | samba, timemachine |

## Host Services
| Service | Purpose | Notes |
|---------|---------|-------|
| wazuh-agent | Security monitoring (SIEM) | Reports to Wazuh manager |
| prometheus-node-exporter | Metrics exporter | System metrics for Prometheus |
| iperf3 | Network speed testing | Listening as a service |
| chrony | NTP time synchronization | |
| postfix | Local mail relay | |
| smartmontools | Disk health monitoring | |
| ksmtuned | Kernel same-page merging | Memory deduplication for VMs |
| zfs-zed | ZFS event daemon | |

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
├── docs/                      # Infrastructure-wide documentation
│   └── backups.md             # Backup architecture, schedule, restore
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

# Backups
ssh root@10.21.21.99 "pvesh get /cluster/backup --output-format json-pretty"  # Job config
ssh root@10.21.21.99 "pvesm list pbs-nwlab"                                   # List backups
ssh root@10.21.21.99 "vzdump <VMID> --storage pbs-nwlab --mode snapshot --compress zstd"  # Manual backup
ssh root@10.21.21.99 "zfs list -o name,used,avail,quota storage/pbs"          # PBS quota
```

## Warnings
- **VM 104 disk expanded**: Root disk expanded from 8.5 GB to 28.5 GB (2026-02-20). Now at 25% usage. Docker recovered, all 11 containers running.
- **VM 101 disk at 89%**: PBS LXC root disk approaching capacity. Monitor and consider expanding.
- **Host RAM pressure**: 85% used (6.5/7.6 GiB), 1.9 GiB swapped. VM 104 alone takes 4 GiB.
- **Pending kernel update**: Running 6.17.4-1-pve, 6.17.9-1-pve installed. Reboot needed.
- **ZFS USB disk errors**: `usb-External_USB3.0_20170331000D1` has 4 read / 8 checksum errors. Last scrub repaired 21K. Monitor via `zpool status storage`. Consider replacing.
- **Orphaned backups**: 9 backups for deleted VMID 103 on PBS. Consider pruning to reclaim space.
- **Stale PBS self-backup**: Last LXC 101 backup is from 2025-10-06 (4+ months old, not in backup job).
- **Firewall disabled**: PVE firewall service running but policy disabled. No active rules.

## Backup Strategy
- **PBS** (LXC 101 @ 10.21.21.101): Proxmox Backup Server
- **Datastore**: `home-backup` at `/mnt/datastore` (bind mount from host `/storage/pbs`)
- **PVE storage**: `pbs-nwlab` (auth: `root@pam`)
- **Web UI**: https://10.21.21.101:8007
- **Job**: `nwlab-daily` — LXC 100, 102 + VM 104 @ 01:00, snapshot mode, zstd
- **Retention**: 7 daily, 4 weekly, 2 monthly (PVE prune + PBS prune job)
- **GC**: daily @ 03:00
- **ZFS quota**: 500 GB (`storage/pbs`)
- **Remote sync**: `nwlab-to-homelab` push job @ 04:00 → homelab PBS (`pbs-backups` @ 10.0.0.6 via WG)
- **Full docs**: [`docs/backups.md`](docs/backups.md)
