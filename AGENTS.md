# AGENTS.md — NWLab

**NWLab** — infrastructure-as-documentation for the NWDesigns office Proxmox homelab. A ThinkPad
(`thinkpad`, `10.21.21.99`) running Proxmox VE hosts VPN (WireGuard), backups (PBS + Time Machine),
a Flatcar Docker host (Traefik/CrowdSec/Vaultwarden/n8n/Evolution API/Portainer + an observability
stack), and an Ubuntu Claude Code workstation. There is no app build pipeline — the substance of this
repo is documentation validated against live SSH output and mirrored configs.

> Subdirectory `CLAUDE.md` files (`flatcar-nwdesigns/CLAUDE.md` for VM 104, `ubuntu-desktop/CLAUDE.md`
> for VM 103) plus the `docs/` and `flatcar-nwdesigns/docs/` notes carry deeper, scope-local detail
> and still apply when working in those trees. This file is the top-level source of truth.

## Production URLs

LAN-only services (office network `10.21.21.0/24`; `*.nwlab.nwdesigns.it` resolves internally via the
Caddy reverse proxy on VM 104 with a wildcard LE cert issued by Cloudflare DNS-01).

| Service       | URL                                   | Host                  |
| ------------- | ------------------------------------- | --------------------- |
| Proxmox VE    | https://10.21.21.99:8006              | thinkpad (10.21.21.99)|
| PBS           | https://10.21.21.101:8007             | LXC 101 (10.21.21.101)|
| Portainer     | https://10.21.21.104:9443 / https://portainer.nwdesigns.it | VM 104 |
| Traefik       | http://10.21.21.104:8080 / https://traefik.nwdesigns.it    | VM 104 |
| Vaultwarden   | https://vaultwarden.nwdesigns.it      | VM 104                |
| n8n           | https://n8n.nwdesigns.it              | VM 104                |
| Evolution API | https://evolution.nwdesigns.it        | VM 104                |
| Grafana       | https://grafana.nwlab.nwdesigns.it    | VM 104                |
| Prometheus    | https://prometheus.nwlab.nwdesigns.it / 127.0.0.1:9090 (SSH tunnel) | VM 104 |
| ntfy          | https://ntfy.nwlab.nwdesigns.it       | VM 104                |

## Repo layout

```
CLAUDE.md                    # slim pointer → this file
README.md                    # human-readable quick overview + ASCII topology
docs/
  backups.md                 # PBS architecture, schedule, retention, restore
  commands.md                # SSH, storage, guest management commands
flatcar-nwdesigns/           # VM 104 — Flatcar Docker host
  CLAUDE.md                  # VM-specific reference (specs, connection, ops)
  config/                    # Docker Compose configs (local mirror of what runs on the VM):
                             #   caddy/ crowdsec/ evolution-api/ grafana/ infrastructure/
                             #   n8n/ ntfy/ otel-collector/ portainer/ prometheus/ vaultwarden/
  docs/                      # infrastructure.md, services.md
ubuntu-desktop/              # VM 103 — Lubuntu 26.04 Claude Code workstation
  CLAUDE.md                  # VM-specific reference (specs, blog-publisher cron + observability)
.github/workflows/           # claude.yml + claude-code-review.yml (Claude Code GitHub Action only)
```

## Local development

No app build pipeline — validation is documentation- and infrastructure-driven. Confirm guest
inventory, storage health, and Flatcar service state against live state before editing docs:

```bash
rg --files
git diff --stat
ssh root@10.21.21.99 "qm list && pct list"                 # Proxmox guest inventory
ssh root@10.21.21.99 "zpool status storage && pvesm status" # ZFS + storage health
ssh core@10.21.21.104 "sudo docker ps"                      # Flatcar container state
```

If a command changes infrastructure state, document it separately instead of folding it into a
docs-only change. When a change affects both global and guest-specific docs, update both in the same
patch so `README.md`, `CLAUDE.md`, and the guest subtree do not drift.

### Credentials

**No secrets file in this repo.** No deploy tokens or credentials are stored here. SSH access uses the
operator's own keys (`ssh <user>@<ip>`, user depends on guest OS). If secrets are ever added, use a
gitignored `.env` populated from an `.env.example` template (varlock + rbw — see
`~/.claude/rules/secrets-management.md`). `.gitignore` already excludes `.env` and `.env.*` (keeping
`!.env.example`). Never commit secrets, tokens, or raw `.env` files, and sanitize copied command
output before pasting it into a doc.

## Proxmox host (thinkpad)

- **Hostname**: `thinkpad` (`thinkpad.nwdesigns.home.arpa`) · **IP**: `10.21.21.99` · **Web UI**: https://10.21.21.99:8006
- **Location**: NWDesigns office
- **PVE**: 9.2.2 (running kernel 7.0.2-6-pve; 6.17.13-11-pve retained as GRUB fallback)
- **CPU**: Intel i5-6200U (2C/4T @ 2.30GHz) · **RAM**: 15.5 GB dual-channel (~39% used)
- **SSH**: `ssh root@10.21.21.99`

### Network

- **Subnet** `10.21.21.0/24` · **Gateway** `10.21.21.1` · **Bridge** `vmbr0` (port `enp0s31f6`)
- **DNS** 9.9.9.9, 8.8.8.8, 1.1.1.1 · **DNS search** `station`
- **Firewall**: disabled (service running, policy disabled — no active rules)

### Storage

| Name            | Type     | Size    | Used | Content                 | Notes                            |
| --------------- | -------- | ------- | ---- | ----------------------- | -------------------------------- |
| local           | dir      | 70 GB   | 52%  | ISOs, backups, snippets | `/var/lib/vz` (SSD)              |
| local-lvm       | LVM-thin | 142 GB  | 28%  | VM/LXC disks            | `pve/data` thinpool (SSD)        |
| proxmox-storage | ZFS pool | 1.35 TB | <1%  | VM/LXC disks            | `storage/proxmox` (HDD mirror)   |
| pbs-nwlab       | PBS      | 500 GB  | 6%   | backups                 | PBS @ 10.21.21.101 `home-backup` |

**Disks** — `sda` (238.5 GB SSD): PVE boot, LVM (root + swap + thinpool). `sdb` + `sdc` (2× 2.7 TB):
ZFS mirror pool `storage`, ONLINE, both vdevs healthy. **`sdc` is USB** — currently ONLINE, 0 errors;
last scrub 2026-05-15 repaired 128K with 0 residual errors. Historically unstable — keep watch.

**ZFS datasets**

| Dataset              | Used    | Avail   | Quota  | Mountpoint            |
| -------------------- | ------- | ------- | ------ | --------------------- |
| storage              | 1.30 TB | 1.33 TB | none   | /storage              |
| storage/homelab-sync | 192 GB  | 108 GB  | 300 GB | /storage/homelab-sync |
| storage/pbs          | 29.7 GB | 470 GB  | 500 GB | /storage/pbs          |
| storage/proxmox      | 24 KB   | 1.33 TB | none   | /storage/proxmox      |
| storage/timemachine  | 1.09 TB | 1.33 TB | 2.5 TB | /timemachine          |

### Guests

| VMID | Type | Name                  | IP           | Status  | Cores | RAM                        | Disk    | Storage   | Autostart | Disk Used |
| ---- | ---- | --------------------- | ------------ | ------- | ----- | -------------------------- | ------- | --------- | --------- | --------- |
| 100  | LXC  | wireguard             | 10.21.21.100 | running | 1     | 128 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 46%       |
| 101  | LXC  | proxmox-backup-server | 10.21.21.101 | running | 1     | 256 MB (+512 swap)         | 10 GB   | local-lvm | yes       | 39%       |
| 102  | LXC  | timemachine-samba     | 10.21.21.102 | running | 1     | 192 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 14%       |
| 103  | VM   | ubuntu-desktop-103    | 10.21.21.103 | running | 2     | 2048 MB (balloon min 1536) | 32 GB   | local-lvm | yes       | —         |
| 104  | VM   | flatcar-portainer-104 | 10.21.21.104 | running | 2     | 4096 MB (balloon min 3072) | 28.5 GB | local-lvm | yes       | 33%       |

VM 103 runs five blog-publisher cron jobs (officine, ambrosiano, costanzo + refresh + brand-audit)
with stream-json + OTEL → flatcar-104 otel-collector + ntfy alerts. See
`ubuntu-desktop/CLAUDE.md#blog-publisher-observability`.

**Guest bind mounts** — 101: `/storage/pbs`→`/mnt/datastore`, `/storage/homelab-sync`→`/mnt/homelab-sync`;
102: `/timemachine`→`/timemachine`.

**Guest tags** — 100: community-script, network, vpn · 101: backup, community-script ·
102: samba, timemachine · 103: desktop, claude-code.

### Host services

| Service                  | Purpose                                                                     |
| ------------------------ | --------------------------------------------------------------------------- |
| wazuh-agent              | Security monitoring (SIEM) — reports to Wazuh manager                        |
| prometheus-node-exporter | System metrics exporter for Prometheus                                      |
| iperf3                   | Network speed testing (listening as a service)                              |
| chrony                   | NTP time synchronization                                                    |
| postfix                  | Local mail relay                                                            |
| smartmontools            | Disk health monitoring                                                      |
| ksmtuned                 | Kernel same-page merging for VMs (KSM_THRES_COEF=50, activates >50% usage)  |
| zfs-zed                  | ZFS event daemon                                                            |

### Observability (VM 104 containers — full stack co-located, no cross-WireGuard)

| Service        | Role                                                                                | Endpoint                                          |
| -------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------- |
| otel-collector | Ingests Claude Code telemetry from VM 103 publishers → NDJSON + Prometheus remote-write | `http://10.21.21.104:4317` (gRPC) / `:4318` (HTTP) |
| prometheus     | TSDB backend (remote_write from otel-collector on the `observability` Docker bridge) | `127.0.0.1:9090` (SSH tunnel) + Caddy https URL    |
| grafana        | Dashboard frontend (provisioned Prometheus DS + blog-publishers dashboard)          | `https://grafana.nwlab.nwdesigns.it` (LAN-only)   |
| ntfy           | Pub/sub alerts (`blog-publishers` topic) for cron failures + stale heartbeats       | `https://ntfy.nwlab.nwdesigns.it` (LAN-only)      |
| caddy          | Bridge-mode reverse proxy; wildcard LE cert for `*.nwlab.nwdesigns.it` (CF DNS-01)   | `https://*.nwlab.nwdesigns.it` (LAN-only)         |

The whole observability stack lives inside the nwlab segment — no metrics shipped over the WireGuard
tunnel to homelab. See `flatcar-nwdesigns/docs/services.md#ntfy` for details.

## Backup strategy

Daily @ 01:00 → GC @ 03:00 → remote sync @ 04:00 (push over WireGuard VPN). Retention: 7 daily /
4 weekly / 2 monthly. Full docs: `docs/backups.md`.

## Conventions

- Each VM/LXC gets its own subdirectory with a `CLAUDE.md`; configs stored locally mirror what's
  deployed on the guest.
- Write concise Markdown with factual, current values. Prefer tables for inventories and fenced `bash`
  blocks for commands. Keep filenames lowercase and hyphenated (e.g. `backups.md`, `services.md`).
- Preserve hostnames, VMIDs, IPs, and storage names exactly as they exist in Proxmox.
- SSH access: `ssh <user>@<ip>` (user depends on guest OS). Most LXCs deployed via community-scripts
  (Helper-Scripts.com).
- Validate every changed claim against live SSH output or the mirrored config files before committing.
- Commits: Conventional Commits scoped to one infrastructure change — `docs:`, `fix(vm104):`,
  `feat(pbs):`. Keep commits small. Use a Git worktree for implementation work instead of editing
  directly on `main`.

## Warnings / gotchas

- **homelab-sync approaching quota** — 192 GB used of 300 GB (108 GB remaining). Monitor growth.
- **Firewall disabled** — PVE firewall service running but policy disabled; no active rules.
- **PBS sync-job list bug** — `proxmox-backup-manager sync-job list` returns `[]` even though the
  `nwlab-to-homelab` push job exists and runs daily. Use `sync-job show nwlab-to-homelab` instead.
- **otel-collector healthcheck false-positive** — Docker healthcheck calls `wget`, which isn't in the
  `otel/opentelemetry-collector-contrib` image; container reports `unhealthy` but service is healthy
  and accepting OTLP traffic. Pre-existing config bug, not an outage signal.
- **USB ZFS vdev** — `sdc` (mirror member) is USB-attached and historically unstable; currently
  ONLINE with 0 errors. Keep monitoring; pause any scrub before cable/disk swap.

### Resolved

- ~~VM 104 disk~~ (2026-02-20): expanded 8.5→28.5 GB, now 33%.
- ~~LXC 101 disk~~ (2026-02-20): cleaned up, now 39%.
- ~~Host RAM pressure~~ (2026-02-25): LXCs right-sized, KSM re-enabled, zram-tuned swappiness, balloon enabled.
- ~~RAM upgrade~~ (2026-04-09): 8→16 GB dual-channel; zram 50%→15%, KSM threshold 95→50, balloon mins raised.
- ~~ZFS USB disk FAULTED~~ (2026-05-15): back ONLINE; scrub repaired 128K, 0 residual errors, mirror `storage` ONLINE.
- ~~Stale PBS self-backup~~ (2026-05-22): LXC 101 added to `nwlab-daily` job (vmid 100,101,102,103,104).
- ~~PVE 9.2.2 + kernel 7.0~~ (2026-05-27): 215 apt pkgs upgraded, `proxmox-ve` 9.0.0→9.2.0, kernel 7.0.2-6-pve installed (6.17.13-11-pve retained as GRUB fallback), ZFS userland 2.3.4→2.4.2, pool feature flags upgraded. All 5 guests verified post-reboot.
