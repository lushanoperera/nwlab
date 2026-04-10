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

## Blog publisher observability

Five cron jobs run on this VM as the `disconnesso` user. Each shells out to
`claude --print` (Max-subscription OAuth) via a Python wrapper.

### Cron inventory

| Schedule | Project | Script |
|---|---|---|
| `0 6 * * *` | officinewordpress.it | `~/Projects/officinewordpress.it/scripts/blog-publisher/publisher.py` (via `scripts/cron-wrap.sh`) |
| `0 7 * * *` | ambrosianomilano.it | `~/Projects/ambrosianomilano.it/blog-publisher/publisher.py` (via `scripts/cron-wrap.sh`) |
| `0 9 * * *` | old.costanzogoldtraders.com | `~/Projects/costanzogoldtraders.com/blog-publisher/publisher.py` (via `scripts/cron-wrap.sh`) |
| `0 10 * * 0` | officinewordpress refresh | `publisher.py --refresh` (via `scripts/cron-wrap.sh`) |
| `0 8 1 * *` | officine brand-audit | `~/Projects/officinewordpress.it/scripts/brand-audit/audit.py` (via `scripts/cron-wrap.sh`) |

Plus 3× `*/5 * * * * scripts/check-publisher-health.sh` and the `*/15 * * * *`
brand-audit health check.

### Heartbeat + last-run files

Each project writes observability artifacts into its own `logs/` directory:

| File | Written by | Purpose |
|---|---|---|
| `logs/heartbeat.json` | `generator.py` while Claude is streaming | `{stage, session_id, started_at, last_event_at, elapsed_s}` — cleared on clean exit |
| `logs/last-run.json` | `publisher.py` at pipeline start | `{start_ts, pid, cron_tag, git_rev}` |
| `logs/publisher.log` | Python orchestrator | Per-stage session IDs, token counts, retries |

### Session replay

Every stage of every run captures the Claude `session_id`. Resume the transcript
locally via Claude Code's on-disk project history under `~/.claude/projects/`:

```bash
# Resume the most recent officine publisher run
claude --resume "$(jq -r .session_id \
  ~/Projects/officinewordpress.it/scripts/blog-publisher/logs/heartbeat.json)"
```

### Telemetry env

Shared OTEL env lives in `/etc/profile.d/claude-telemetry.sh` (root-owned,
sourced by each `scripts/cron-wrap.sh`):

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://10.21.21.104:4318
# service.instance.id is set per-site inside each scripts/cron-wrap.sh
```

### Alert + telemetry endpoints (flatcar-nwdesigns VM 104)

| Service | URL | Role |
|---|---|---|
| OTel Collector (gRPC) | `http://10.21.21.104:4317` | Preferred for headless Claude Code |
| OTel Collector (HTTP) | `http://10.21.21.104:4318` | Fallback / debug |
| ntfy | `http://ntfy.nwlab.home.arpa/blog-publishers` | Failure + stale-heartbeat alerts |

### Monitor tool does not apply

**Note:** The Claude Code `Monitor` tool (CC ≥ 2.1.98) is **interactive-only** —
it lets an active CC session react to lines from a background `Bash` process
it launched itself. It does **not** help headless `claude --print` cron runs,
and there is no way for a headless `claude -p` process to expose a
Monitor-compatible stream to any outside observer. We use `--output-format
stream-json --include-partial-messages --verbose` parsing plus native OTEL
telemetry instead. Do not re-investigate.

## Known Issues

### Active

- **Remote desktop**: RustDesk and xrdp both failed (RustDesk: relay registration issue; xrdp: black screen with LXQt). Use Proxmox noVNC console for now. Revisit later.

### Notes

- LXQt was chosen over GNOME/KDE for lower memory footprint (~400 MB idle vs ~1.5 GB)
- Balloon min raised to 1536 MB (2026-04-09) — more headroom for Firefox + Claude Code under load
- No autostart — remember to `qm start 103` before use
