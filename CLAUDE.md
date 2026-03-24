# NWLab - Proxmox Infrastructure

## Proxmox Host (thinkpad)

- **Hostname**: thinkpad (`thinkpad.nwdesigns.home.arpa`)
- **IP**: 10.21.21.99
- **Web UI**: https://10.21.21.99:8006
- **Location**: NWDesigns office
- **PVE Version**: 9.1.6 (running kernel 6.17.4-1-pve, 6.17.9-1-pve installed — reboot pending)
- **CPU**: Intel i5-6200U (2C/4T @ 2.30GHz)
- **RAM**: 7.6 GB (~66% used, ~1.6 GiB swapped — optimized 2026-02-25)
- **SSH**: `ssh root@10.21.21.99`

## Network

- **Subnet**: `10.21.21.0/24`
- **Gateway**: `10.21.21.1`
- **Bridge**: `vmbr0` (port: `enp0s31f6`)
- **DNS**: 9.9.9.9, 8.8.8.8, 1.1.1.1
- **DNS search**: `station`
- **Firewall**: disabled (service running, policy disabled)

## Storage

| Name            | Type     | Size    | Used | Content                 | Notes                            |
| --------------- | -------- | ------- | ---- | ----------------------- | -------------------------------- |
| local           | dir      | 70 GB   | 52%  | ISOs, backups, snippets | `/var/lib/vz` (SSD)              |
| local-lvm       | LVM-thin | 142 GB  | 28%  | VM/LXC disks            | `pve/data` thinpool (SSD)        |
| proxmox-storage | ZFS pool | 1.35 TB | <1%  | VM/LXC disks            | `storage/proxmox` (HDD mirror)   |
| pbs-nwlab       | PBS      | 500 GB  | 6%   | backups                 | PBS @ 10.21.21.101 `home-backup` |

### Disks

- **sda** (238.5 GB SSD): PVE boot, LVM (root + swap + thinpool)
- **sdb + sdc** (2x 2.7 TB): ZFS mirror pool `storage`
  - **sdc is USB** — **FAULTED** (21 read / 14 checksum errors, too many errors). Mirror is DEGRADED. Replacement needed.

### ZFS Datasets

| Dataset              | Used    | Avail   | Quota  | Mountpoint            |
| -------------------- | ------- | ------- | ------ | --------------------- |
| storage              | 1.30 TB | 1.33 TB | none   | /storage              |
| storage/homelab-sync | 192 GB  | 108 GB  | 300 GB | /storage/homelab-sync |
| storage/pbs          | 29.7 GB | 470 GB  | 500 GB | /storage/pbs          |
| storage/proxmox      | 24 KB   | 1.33 TB | none   | /storage/proxmox      |
| storage/timemachine  | 1.09 TB | 1.33 TB | 2.5 TB | /timemachine          |

## Guests

| VMID | Type | Name                  | IP           | Status  | Cores | RAM                        | Disk    | Storage   | Autostart | Disk Used |
| ---- | ---- | --------------------- | ------------ | ------- | ----- | -------------------------- | ------- | --------- | --------- | --------- |
| 100  | LXC  | wireguard             | 10.21.21.100 | running | 1     | 128 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 46%       |
| 101  | LXC  | proxmox-backup-server | 10.21.21.101 | running | 1     | 256 MB (+512 swap)         | 10 GB   | local-lvm | yes       | 39%       |
| 102  | LXC  | timemachine-samba     | 10.21.21.102 | running | 1     | 192 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 14%       |
| 103  | VM   | ubuntu-desktop-103    | 10.21.21.103 | running | 2     | 2048 MB (balloon min 1024) | 32 GB   | local-lvm | no        | —         |
| 104  | VM   | flatcar-portainer-104 | 10.21.21.104 | running | 2     | 4096 MB (balloon min 2560) | 28.5 GB | local-lvm | yes       | 33%       |

### Guest Bind Mounts

| VMID | Host Path             | Guest Mountpoint  |
| ---- | --------------------- | ----------------- |
| 101  | /storage/pbs          | /mnt/datastore    |
| 101  | /storage/homelab-sync | /mnt/homelab-sync |
| 102  | /timemachine          | /timemachine      |

### Guest Tags

| VMID | Tags                           |
| ---- | ------------------------------ |
| 100  | community-script, network, vpn |
| 101  | backup, community-script       |
| 102  | samba, timemachine             |
| 103  | desktop, claude-code           |

## Host Services

| Service                  | Purpose                    | Notes                                                       |
| ------------------------ | -------------------------- | ----------------------------------------------------------- |
| wazuh-agent              | Security monitoring (SIEM) | Reports to Wazuh manager                                    |
| prometheus-node-exporter | Metrics exporter           | System metrics for Prometheus                               |
| iperf3                   | Network speed testing      | Listening as a service                                      |
| chrony                   | NTP time synchronization   |                                                             |
| postfix                  | Local mail relay           |                                                             |
| smartmontools            | Disk health monitoring     |                                                             |
| ksmtuned                 | Kernel same-page merging   | Memory deduplication for VMs (KSM_THRES_COEF=95, always-on) |
| zfs-zed                  | ZFS event daemon           |                                                             |

## Web UIs

| Service    | URL                        |
| ---------- | -------------------------- |
| Proxmox VE | https://10.21.21.99:8006   |
| PBS        | https://10.21.21.101:8007  |
| Portainer  | https://10.21.21.104:9443  |
| Traefik    | http://10.21.21.104:8080   |

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
└── ubuntu-desktop/            # VM 103: Lubuntu Claude Code workstation
    └── CLAUDE.md              # VM-specific docs & commands
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
ssh disconnesso@10.21.21.103  # Ubuntu Desktop (Claude Code)
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
ssh root@10.21.21.99 "zfs list -o name,used,avail,quota storage/pbs storage/homelab-sync"  # PBS quotas
```

## Warnings

- **Pending kernel update**: Running 6.17.4-1-pve, 6.17.9-1-pve installed. Reboot needed.
- **ZFS USB disk FAULTED**: `usb-External_USB3.0_20170331000D1` has 21 read / 14 checksum errors — marked FAULTED ("too many errors"). Mirror pool `storage` is **DEGRADED** but functional on single disk. **Replace urgently.** Last scrub (2026-03-08) repaired 2.41M with 0 residual errors.
- **homelab-sync approaching quota**: 192 GB used of 300 GB quota (108 GB remaining). Monitor growth.
- **Stale PBS self-backup**: Last LXC 101 backup is from 2025-09-29 (5+ months old, not in backup job).
- **Firewall disabled**: PVE firewall service running but policy disabled. No active rules.
- **PBS sync-job list bug**: `proxmox-backup-manager sync-job list` returns `[]` even though the `nwlab-to-homelab` push job exists and runs daily. Use `sync-job show nwlab-to-homelab` instead.

### Resolved

- ~~VM 104 disk~~ (2026-02-20): Expanded 8.5→28.5 GB. Now 33%.
- ~~LXC 101 disk~~ (2026-02-20): Cleaned up, now 39%.
- ~~Host RAM pressure~~ (2026-02-25): LXCs right-sized, KSM re-enabled, zram-tuned swappiness, balloon enabled. Now ~66% used.

## Backup Strategy

- **PBS** (LXC 101 @ 10.21.21.101): Proxmox Backup Server
- **Web UI**: https://10.21.21.101:8007
- **PVE storage**: `pbs-nwlab` (auth: `root@pam`)
- **Datastores**:
  - `home-backup` — nwlab local backups (`/mnt/datastore`, `storage/pbs`, 500 GB quota)
  - `homelab-sync` — incoming homelab syncs (`/mnt/homelab-sync`, `storage/homelab-sync`, 300 GB quota)
- **Job**: `nwlab-daily` — LXC 100, 102 + VM 103, 104 @ 01:00, snapshot mode, zstd
- **Retention**: 7 daily, 4 weekly, 2 monthly (PVE prune + PBS prune job on `home-backup`)
- **GC**: daily @ 03:00
- **Remote sync**: `nwlab-to-homelab` push job — daily @ 04:00, pushes `home-backup` → homelab `nwlab-backup` via WireGuard VPN
- **Full docs**: [`docs/backups.md`](docs/backups.md)
