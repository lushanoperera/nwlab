# Ubuntu Desktop VM - Claude Code Workstation

## VM Specs

| Property        | Value                                          |
| --------------- | ---------------------------------------------- |
| **VMID**        | 103                                            |
| **Name**        | `ubuntu-desktop-103`                           |
| **OS**          | Lubuntu 26.04 LTS (LXQt desktop)                |
| **CPU**         | 2 cores, host type (q35 machine)               |
| **RAM**         | 2048 MB (balloon min 1536 MB)                  |
| **Swap**        | 512 MB zram (zstd, prio 100) + 512 MB swapfile  |
| **Swappiness**  | 100 (`/etc/sysctl.d/99-zram.conf`)             |
| **Disk**        | 32 GB on local-lvm (SSD)                       |
| **BIOS**        | OVMF (UEFI)                                    |
| **Display**     | VirtIO GPU                                     |
| **Network**     | virtio on vmbr0                                |
| **IP**          | 10.21.21.103 (static via netplan)              |
| **Guest Agent** | enabled, fstrim                                |
| **Autostart**   | NO (interactive workstation — start on demand) |
| **Tags**        | `desktop`, `claude-code`                       |

## Purpose

Lightweight desktop VM for running Claude Code CLI with Firefox for OAuth authentication. Not a server — start when needed, shut down when done.

## VM Connection

```bash
ssh disconnesso@10.21.21.103          # SSH (replace disconnesso with install username)
# Or use Proxmox console: https://10.21.21.99:8006 → VM 103 → Console
```

## Installed Software

| Package                     | Purpose                              |
| --------------------------- | ------------------------------------ |
| Firefox                     | OAuth authentication for Claude Code |
| Node.js 22 LTS              | Runtime for Claude Code CLI          |
| `@anthropic-ai/claude-code` | Claude Code CLI (npm global, auto-updates enabled) |
| openssh-server              | Remote SSH access                    |
| qemu-guest-agent            | PVE integration (IP, fs-freeze)      |
| zram-tools                  | Compressed RAM swap                  |

## Network Config

Static IP via netplan (`/etc/netplan/01-static.yaml`):

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 10.21.21.103/24
      routes:
        - to: default
          via: 10.21.21.1
      nameservers:
        addresses: [9.9.9.9, 8.8.8.8, 1.1.1.1]
        search: [station]
```

> **Note**: NIC was renamed from `enp6s18` to `ens18` during the 24.04→26.04 upgrade (kernel 7.0 naming).

## Common Commands

```bash
# Start/stop from PVE host
ssh root@10.21.21.99 "qm start 103"
ssh root@10.21.21.99 "qm shutdown 103"

# Check guest agent
ssh root@10.21.21.99 "qm agent 103 ping"
ssh root@10.21.21.99 "qm agent 103 network-get-interfaces"

# Update Claude Code
ssh disconnesso@10.21.21.103 "npm update -g @anthropic-ai/claude-code"

# Check node/claude versions
ssh disconnesso@10.21.21.103 "node --version && claude --version"
```

## Memory Budget

With balloon enabled, this VM returns up to 512 MB to the host when idle:

- **Max**: 2048 MB (Firefox + Claude Code + LXQt active)
- **Min**: 1536 MB (idle, balloon deflated)
- **Zram**: 512 MB compressed swap helps balloon work smoothly

## Known Issues

### Active

- **Remote desktop**: RustDesk and xrdp both failed (RustDesk: relay registration issue; xrdp: black screen with LXQt). Use Proxmox noVNC console for now. Revisit later.

### Notes

- LXQt was chosen over GNOME/KDE for lower memory footprint (~400 MB idle vs ~1.5 GB)
- Balloon min raised to 1536 MB (2026-04-09) — more headroom for Firefox + Claude Code under load
- No autostart — remember to `qm start 103` before use
