# Common Commands

## Proxmox Host

```bash
ssh root@10.21.21.99
ssh root@10.21.21.99 "qm list && pct list"
```

## Guest Shells

```bash
ssh root@10.21.21.100   # WireGuard
ssh root@10.21.21.101   # PBS
ssh root@10.21.21.102   # Time Machine
ssh disconnesso@10.21.21.103  # Ubuntu Desktop (Claude Code)
ssh core@10.21.21.104   # Flatcar (Docker)
```

## Storage

```bash
ssh root@10.21.21.99 "zpool status storage"        # ZFS health
ssh root@10.21.21.99 "zfs list"                     # Dataset usage
ssh root@10.21.21.99 "pvesm status"                 # PVE storage overview
```

## Guest Management

```bash
ssh root@10.21.21.99 "pct start <VMID>"             # Start LXC
ssh root@10.21.21.99 "pct stop <VMID>"              # Stop LXC
ssh root@10.21.21.99 "pct enter <VMID>"             # Console into LXC
ssh root@10.21.21.99 "qm start <VMID>"              # Start VM
```

## Backups

```bash
ssh root@10.21.21.99 "pvesh get /cluster/backup --output-format json-pretty"  # Job config
ssh root@10.21.21.99 "pvesm list pbs-nwlab"                                   # List backups
ssh root@10.21.21.99 "vzdump <VMID> --storage pbs-nwlab --mode snapshot --compress zstd"  # Manual backup
ssh root@10.21.21.99 "zfs list -o name,used,avail,quota storage/pbs storage/homelab-sync"  # PBS quotas
```
