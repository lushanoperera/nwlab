# Backup Architecture

## Overview

```
PVE (thinkpad)            PBS Local (LXC 101)                  Homelab PBS (10.0.0.6)
+------------+  vzdump    +----------------------+  push        +----------------------+
| LXC 100    |---------->| home-backup          |--04:00-WG-->| nwlab-backup         |
| LXC 102    |  01:00     | /mnt/datastore       |              | (nwlab offsite copy) |
| VM  104    |  snapshot  | storage/pbs (500 GB) |              +----------------------+
+------------+  zstd      +----------------------+
                              GC @ 03:00                <--push-WG--+
                              7d / 4w / 2m retention                |
                                                       +----------------------+
                          +----------------------+     | homelab push job     |
                          | homelab-sync         |<----| (reconfigured)       |
                          | /mnt/homelab-sync    |     +----------------------+
                          | storage/homelab-sync |
                          | (300 GB quota)       |
                          +----------------------+
```

### Datastore Separation

nwlab PBS has two datastores to keep local and remote backups separate:

| Datastore | Purpose | Path | ZFS Dataset | Quota | Content |
|-----------|---------|------|-------------|-------|---------|
| `home-backup` | nwlab local backups | `/mnt/datastore` | `storage/pbs` | 500 GB | ct/100, ct/101, ct/102, vm/104 |
| `homelab-sync` | Incoming homelab syncs | `/mnt/homelab-sync` | `storage/homelab-sync` | 300 GB | Homelab backup groups (received via push) |

This prevents VMID collisions (both environments use 100-104) and ensures nwlab's prune job only affects nwlab backups.

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
| 03:00 | Garbage Collection | PBS removes unreferenced chunks from `home-backup` |
| 04:00 | Remote Sync (push) | PBS pushes `home-backup` → homelab `nwlab-backup` |

## Backed-Up Guests

| VMID | Name | Type | Disk | Notes |
|------|------|------|------|-------|
| 100 | wireguard | LXC | 8 GB | VPN gateway |
| 102 | timemachine-samba | LXC | 8 GB | Excludes `/timemachine` bind mount (not a volume) |
| 104 | flatcar-portainer-104 | VM | 28.5 GB | QEMU Guest Agent active (fs-freeze/thaw) |

**Not backed up**: LXC 101 (PBS itself) — it's the backup server; restore from PBS ISO + config.

> **Warning**: The last manual backup of LXC 101 is from **2025-10-06** (4+ months stale). It is not included in the `nwlab-daily` job. Consider periodic manual backups or a separate job.

## Retention Policy

| Level | Keep | Applied By |
|-------|------|-----------|
| Daily | 7 | PVE prune-backups + PBS prune job |
| Weekly | 4 | PVE prune-backups + PBS prune job |
| Monthly | 2 | PVE prune-backups + PBS prune job |

Retention applies only to `home-backup` (nwlab's own backups). The `homelab-sync` datastore is managed by homelab's push job retention.

## Storage

### home-backup (nwlab local)

- **PVE storage name**: `pbs-nwlab`
- **PBS datastore**: `home-backup`
- **Path**: `/mnt/datastore` (bind mount from host `/storage/pbs`)
- **ZFS dataset**: `storage/pbs` with 500 GB quota
- **Auth**: `root@pam` password (stored in `/etc/pve/priv/storage/pbs-nwlab.pw`)

### homelab-sync (incoming from homelab)

- **PBS datastore**: `homelab-sync`
- **Path**: `/mnt/homelab-sync` (bind mount from host `/storage/homelab-sync`)
- **ZFS dataset**: `storage/homelab-sync` with 300 GB quota
- **Content**: Homelab backup groups pushed from homelab PBS

## Remote Sync (nwlab → homelab)

- **Sync job**: `nwlab-to-homelab` (push direction)
- **Source datastore**: `home-backup`
- **Remote name**: `homelab-pbs`
- **Remote host**: `10.0.0.6:8007` (WireGuard overlay IP)
- **Remote datastore**: `nwlab-backup`
- **Auth**: `root@pam` password
- **Schedule**: daily at 04:00
- **remove-vanished**: false (safe — won't delete remote-only backups)

> **Note**: The sync job pushes only nwlab's backup groups (ct/100, ct/101, ct/102, vm/104) to homelab's dedicated `nwlab-backup` datastore.

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
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager datastore list"
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager datastore show home-backup"
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager datastore show homelab-sync"

# Prune job status
ssh root@10.21.21.99 "pct exec 101 -- proxmox-backup-manager prune-job list"

# ZFS quota check
ssh root@10.21.21.99 "zfs list -o name,used,avail,quota storage/pbs storage/homelab-sync"

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
