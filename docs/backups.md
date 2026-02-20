# Backup Architecture

## Overview

```
PVE (thinkpad)            PBS Local (10.21.21.101)           PBS Remote (10.0.0.6)
+------------+  vzdump    +----------------------+  push     +-------------------------+
| LXC 100    |----------->| home-backup          |---------->| pbs-backups             |
| LXC 102    |  01:00     | /mnt/datastore       |  04:00    | Homelab PBS (QNAP)      |
| VM  104    |  snapshot  | 500 GB quota (ZFS)   |  WG VPN   | 192.168.100.187 (LAN)   |
+------------+  zstd      +----------------------+           +-------------------------+
                              GC @ 03:00
                              7d / 4w / 2m retention
```

## Components

| Component | Location | Role |
|-----------|----------|------|
| PVE vzdump | thinkpad (10.21.21.99) | Creates snapshot backups of guests |
| PBS Local | LXC 101 (10.21.21.101) | Stores, deduplicates, and manages backups |
| PBS Remote | 10.0.0.6 / 192.168.100.187 | Offsite copy via push sync job |

## Schedule

| Time | Operation | Details |
|------|-----------|---------|
| 01:00 | vzdump | Backs up LXC 100, 102 + VM 104 to `pbs-nwlab` |
| 03:00 | Garbage Collection | PBS removes unreferenced chunks |
| 04:00 | Remote Sync (push) | PBS pushes `home-backup` to homelab `pbs-backups` |

## Backed-Up Guests

| VMID | Name | Type | Disk | Notes |
|------|------|------|------|-------|
| 100 | wireguard | LXC | 8 GB | VPN gateway |
| 102 | timemachine-samba | LXC | 8 GB | Excludes `/timemachine` bind mount (not a volume) |
| 104 | flatcar-portainer-104 | VM | 8.5 GB | QEMU Guest Agent active (fs-freeze/thaw) |

**Not backed up**: LXC 101 (PBS itself) — it's the backup server; restore from PBS ISO + config.

> **Warning**: The last manual backup of LXC 101 is from **2025-10-06** (4+ months stale). It is not included in the `nwlab-daily` job. Consider periodic manual backups or a separate job.

> **Warning**: **9 orphaned backups for deleted VMID 103** exist on PBS. These consume space and should be pruned:
> ```bash
> ssh root@10.21.21.99 "pvesm list pbs-nwlab --vmid 103"  # List them
> # Prune via PBS UI or CLI after confirming they're no longer needed
> ```

## Retention Policy

| Level | Keep | Applied By |
|-------|------|-----------|
| Daily | 7 | PVE prune-backups + PBS prune job |
| Weekly | 4 | PVE prune-backups + PBS prune job |
| Monthly | 2 | PVE prune-backups + PBS prune job |

## Storage

- **PVE storage name**: `pbs-nwlab`
- **PBS datastore**: `home-backup`
- **Path**: `/mnt/datastore` (bind mount from host `/storage/pbs`)
- **ZFS dataset**: `storage/pbs` with 500 GB quota (235 GB used, 265 GB free — 47%)
- **Auth**: `root@pam` password (stored in `/etc/pve/priv/storage/pbs-nwlab.pw`)

## Remote Sync

- **Sync job**: `nwlab-to-homelab` (push direction)
- **Remote name**: `homelab-pbs`
- **Remote host**: `10.0.0.6:8007` (WireGuard overlay IP)
- **Remote datastore**: `pbs-backups`
- **Auth**: `root@pam` password
- **Schedule**: daily at 04:00
- **remove-vanished**: false (safe — won't delete remote-only backups)

## VPN Routing

PBS LXC (101) reaches the homelab PBS via WireGuard overlay network:

```
PBS LXC (10.21.21.101)
  |
  | route: 10.0.0.0/24 via 10.21.21.100
  v
WG LXC (10.21.21.100)
  |
  | IP forwarding + FORWARD ACCEPT on wg0
  | wg0 tunnel (no MASQUERADE — homelab AllowedIPs includes 10.21.21.0/24)
  v
Homelab PBS (wg0: 10.0.0.6, LAN: 192.168.100.187)
  AllowedIPs: 10.21.21.0/24, 10.0.0.0/24
```

**Config locations**:
- PBS route: `/etc/network/interfaces` on LXC 101 (`up ip route add 10.0.0.0/24 via 10.21.21.100`)
- WG forwarding: `/etc/wireguard/wg0.conf` PostUp on LXC 100 (FORWARD + eth0 MASQUERADE)
- Homelab WG AllowedIPs: `/etc/wireguard/wg0.conf` on homelab PBS (includes `10.21.21.0/24, 10.0.0.0/24`)

## Commands

```bash
# View backup job
ssh root@10.21.21.99 "pvesh get /cluster/backup --output-format json-pretty"

# Manual backup (single guest)
ssh root@10.21.21.99 "vzdump <VMID> --storage pbs-nwlab --mode snapshot --compress zstd"

# List backups in PBS
ssh root@10.21.21.99 "pvesm list pbs-nwlab"

# PBS datastore status
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager datastore show home-backup"

# Prune job status
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager prune-job list"

# ZFS quota check
ssh root@10.21.21.99 "zfs list -o name,used,avail,quota storage/pbs"

# Remote sync status
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager sync-job list"
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager remote list"

# Manual sync trigger
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager sync-job run nwlab-to-homelab"

# PBS task history
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager task list --all 1 --limit 10"

# Test VPN connectivity to homelab PBS
ssh root@10.21.21.99 "pct exec 101 -- curl -sk https://10.0.0.6:8007/api2/json/version"
```

## Restore

```bash
# Restore LXC from PBS (creates new CT with next available VMID)
ssh root@10.21.21.99 "pct restore <NEW_VMID> <BACKUP_VOLID> --storage local-lvm"

# Restore VM from PBS
ssh root@10.21.21.99 "qmrestore <BACKUP_VOLID> <NEW_VMID> --storage local-lvm"

# List available backups to find VOLID
ssh root@10.21.21.99 "pvesm list pbs-nwlab --vmid <VMID>"
```
