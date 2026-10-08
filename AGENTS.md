# AGENTS.md — NWLab

**NWLab** — infrastructure-as-documentation for the NWDesigns office Proxmox homelab. A ThinkPad
(`thinkpad`, `10.21.21.99`) running Proxmox VE hosts VPN (WireGuard), backups (PBS + Time Machine),
a Flatcar Docker host (Traefik/CrowdSec/Vaultwarden/n8n/OpenWA/Portainer + an observability
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
| Traefik       | https://traefik.nwdesigns.it (basic auth, `admin`)           | VM 104 |
| Vaultwarden   | https://vaultwarden.nwdesigns.it      | VM 104                |
| n8n           | https://n8n.nwdesigns.it              | VM 104                |
| OpenWA        | https://wa.nwlab.nwdesigns.it         | VM 104                |
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
                             #   caddy/ crowdsec/ grafana/ infrastructure/
                             #   n8n/ ntfy/ openwa/ otel-collector/ portainer/ prometheus/ vaultwarden/
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
gitignored `.env` populated from an `.env.example` template (plain `.env` policy — see
`~/.claude/rules/secrets-management.md`). `.gitignore` already excludes `.env` and `.env.*` (keeping
`!.env.example`). Never commit secrets, tokens, or raw `.env` files, and sanitize copied command
output before pasting it into a doc.

## Proxmox host (thinkpad)

- **Hostname**: `thinkpad` (`thinkpad.nwdesigns.home.arpa`) · **IP**: `10.21.21.99` · **Web UI**: https://10.21.21.99:8006
- **Location**: NWDesigns office
- **PVE**: 9.2.21 (running kernel 7.0.14-14-pve; 7.0.2-6-pve + 6.17.13-21-pve retained as fallbacks)
- **CPU**: Intel i5-6200U (2C/4T @ 2.30GHz) · **RAM**: 15.5 GB dual-channel (~67% used)
- **SSH**: `ssh root@10.21.21.99`

### Network

- **Subnet** `10.21.21.0/24` · **Gateway** `10.21.21.1` · **Bridge** `vmbr0` (port `enp0s31f6`)
- **DNS** 9.9.9.9, 8.8.8.8, 1.1.1.1 · **DNS search** `station`
- **Firewall**: disabled (service running, policy disabled — no active rules)

### Storage

| Name            | Type     | Size    | Used | Content                 | Notes                            |
| --------------- | -------- | ------- | ---- | ----------------------- | -------------------------------- |
| local           | dir      | 70 GB   | 46%  | ISOs, backups, snippets | `/var/lib/vz` (SSD)              |
| local-lvm       | LVM-thin | 142 GB  | 52%  | VM/LXC disks            | `pve/data` thinpool (SSD)        |
| proxmox-storage | ZFS pool | 1.35 TB | <1%  | VM/LXC disks            | `storage/proxmox` (HDD mirror)   |
| pbs-nwlab       | PBS      | 500 GB  | 9%   | backups                 | PBS @ 10.21.21.101 `home-backup` |

**Disks** — `sda` (238.5 GB SSD): PVE boot, LVM (root + swap + thinpool). `sdb` + `sdc` (2× 2.7 TB):
ZFS mirror pool `storage`, ONLINE. **`sdc` is USB** — ONLINE, 0 ZFS errors; last scrub 2026-10-01
repaired 0B with 0 errors. **SMART degrading (2026-10-07)**: `sdc` 6 pending + 5 offline-uncorrectable
sectors and its short self-tests fail with a read error at LBA 103760144. `sdb` has 2 pending sectors
(self-tests pass). Both disks are at ~68,000 power-on hours. Plan to replace `sdc`.

**ZFS datasets**

| Dataset              | Used    | Avail   | Quota  | Mountpoint            |
| -------------------- | ------- | ------- | ------ | --------------------- |
| storage              | 1.30 TB | 1.34 TB | none   | /storage              |
| storage/homelab-sync | 170 GB  | 230 GB  | 400 GB | /storage/homelab-sync |
| storage/pbs          | 43.6 GB | 456 GB  | 500 GB | /storage/pbs          |
| storage/proxmox      | 24 KB   | 1.34 TB | none   | /storage/proxmox      |
| storage/timemachine  | 1.09 TB | 1.34 TB | 2.5 TB | /timemachine          |

### Guests

| VMID | Type | Name                  | IP           | Status  | Cores | RAM                        | Disk    | Storage   | Autostart | Disk Used |
| ---- | ---- | --------------------- | ------------ | ------- | ----- | -------------------------- | ------- | --------- | --------- | --------- |
| 100  | LXC  | wireguard             | 10.21.21.100 | running | 1     | 128 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 46%       |
| 101  | LXC  | proxmox-backup-server | 10.21.21.101 | running | 1     | 256 MB (+512 swap)         | 10 GB   | local-lvm | yes       | 39%       |
| 102  | LXC  | timemachine-samba     | 10.21.21.102 | running | 1     | 192 MB (+256 swap)         | 8 GB    | local-lvm | yes       | 14%       |
| 103  | VM   | ubuntu-desktop-103    | 10.21.21.103 | running | 3     | 4096 MB (balloon min 1536) | 32 GB   | local-lvm | yes       | —         |
| 104  | VM   | flatcar-portainer-104 | 10.21.21.104 | running | 2     | 4096 MB (balloon min 3072) | 28.5 GB | local-lvm | yes       | 33%       |
| 105  | LXC  | netbird-gw            | 10.21.21.105 | running | 1     | 512 MB (+256 swap)         | 4 GB    | local-lvm | yes       | 23%       |

LXC 105 is the NetBird routing peer for `10.21.21.0/24` (server `https://vpn.disconnesso.com` on homelab
VM 109; migration from WireGuard started 2026-10-04). Unprivileged, `nesting=1`, `/dev/net/tun`
passthrough, unattended-upgrades (Debian security only). LXC 100 (WireGuard) stays until the homelab
NetBird plan Phase 5. The PBS push still runs over WireGuard until Phase 4.

The three daily blog publishers (officine, ambrosiano, costanzo) moved to Claude Routines on
2026-05-20. Their VM 103 cron lines and the weekly refresh are disabled. VM 103 still runs the monthly
officine brand-audit, the monthly costanzo SEO audit and the brand-audit health check, with
stream-json + OTEL → flatcar-104 otel-collector + ntfy alerts. See
`ubuntu-desktop/CLAUDE.md#blog-publisher-observability`.

**Guest bind mounts** — 101: `/storage/pbs`→`/mnt/datastore`, `/storage/homelab-sync`→`/mnt/homelab-sync`;
102: `/timemachine`→`/timemachine`.

**Guest tags** — 100: community-script, network, vpn · 101: backup, community-script ·
102: samba, timemachine · 103: desktop, claude-code.

### Host services

| Service                  | Purpose                                                                     |
| ------------------------ | --------------------------------------------------------------------------- |
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

- **homelab-sync retention** (fixed 2026-10-04) — the datastore had no prune job and never ran GC, so it
  filled its quota and every homelab push failed with `Disk quota exceeded` from 2026-09-19. Now: prune
  job `homelab-sync-retention` daily 02:00 (keep 7 daily / 4 weekly / 2 monthly), GC daily 03:00, quota
  400 GB. The push job keeps `remove-vanished false`, so the prune job is the only cleanup — do not delete it.
- **Firewall disabled** — PVE firewall service running but policy disabled; no active rules.
- **PBS sync-job list bug** — `proxmox-backup-manager sync-job list` returns `[]` even though the
  `nwlab-to-homelab` push job exists and runs daily. Use `sync-job show nwlab-to-homelab` instead.
- **otel-collector healthcheck** — the contrib image has no `wget`/shell. The old `wget` healthcheck
  reported `unhealthy` and `autoheal` restarted the collector every ~90 s (telemetry loss). Healthcheck is
  now `disable: true` in the compose file. Do not re-add a shell-based healthcheck.
- **Vaultwarden must track Bitwarden clients** (2026-10-08) — `:latest` was never re-pulled, so 1.35.2
  stayed live; 2026.x clients call `POST /identity/accounts/prelogin/password` (added in 1.36.0) → 404 →
  "unexpected error" on login. Now pinned to `1.37.4`. Bump the tag when clients update; back up
  `/opt/vaultwarden/data` first (schema migrates forward only). Pre-upgrade copy: `data.bak-20261008`.
- **USB ZFS vdev** — `sdc` (mirror member) is USB-attached and historically unstable. 2026-08-25:
  7 READ / 3 CKSUM errors accumulated after the clean Aug 9 scrub (USB resets in dmesg); counters cleared
  with `zpool clear storage`, no data errors. Check the USB cable. Pause any scrub before cable/disk swap.
- **SSH is key-only** (2026-08-25) — `PasswordAuthentication no` + `PermitRootLogin prohibit-password` via
  `/etc/ssh/sshd_config.d/10-hardening.conf` on the host, LXC 100, LXC 101, and VM 103. LXC 100/101 carry
  the host root `authorized_keys`. Add your key before removing an old one.
- **WireGuard ACL** — traffic from the routed homelab subnet `192.168.100.0/24` may only reach
  `10.21.21.101:8007` (PBS) and ICMP on the office LAN (iptables in `wg0.conf` PostUp). Peers with a
  single `/32` are not filtered.

### Resolved

- ~~VM 104 disk~~ (2026-02-20): expanded 8.5→28.5 GB, now 33%.
- ~~LXC 101 disk~~ (2026-02-20): cleaned up, now 39%.
- ~~Host RAM pressure~~ (2026-02-25): LXCs right-sized, KSM re-enabled, zram-tuned swappiness, balloon enabled.
- ~~RAM upgrade~~ (2026-04-09): 8→16 GB dual-channel; zram 50%→15%, KSM threshold 95→50, balloon mins raised.
- ~~ZFS USB disk FAULTED~~ (2026-05-15): back ONLINE; scrub repaired 128K, 0 residual errors, mirror `storage` ONLINE.
- ~~Stale PBS self-backup~~ (2026-05-22): LXC 101 added to `nwlab-daily` job (vmid 100,101,102,103,104).
- ~~PVE 9.2.2 + kernel 7.0~~ (2026-05-27): 215 apt pkgs upgraded, `proxmox-ve` 9.0.0→9.2.0, kernel 7.0.2-6-pve installed (6.17.13-11-pve retained as GRUB fallback), ZFS userland 2.3.4→2.4.2, pool feature flags upgraded. All 5 guests verified post-reboot.
- ~~Host root disk 90%~~ (2026-08-25): purged 43 old kernels (35 GB in `/usr/lib/modules`), `/` now 35%.
- ~~PVE 9.2.11 + kernel 7.0.14-14~~ (2026-08-25): 150 apt pkgs upgraded (57 security), rebooted.
- ~~Public hardening~~ (2026-08-25): Traefik `api.insecure=false` + basic-auth dashboard, `:8080` unpublished;
  `forwardedHeaders.trustedIPs=172.20.0.0/16` so CrowdSec sees real client IPs behind cloudflared;
  Vaultwarden `SIGNUPS_ALLOWED=false` + `ADMIN_TOKEN`; n8n DB password moved to `/opt/n8n/.env`;
  `/opt/*/.env` are 0600; 2 stale WireGuard peers (10.0.0.2, 10.0.0.4) removed.
- ~~VM 103 brand-audit never ran~~ (2026-10-08): `brand-audit/scripts/cron-wrap.sh` + `check-audit-health.sh`
  were 0644 (cron `Permission denied` since April); now 0755. First real run 2026-11-01 08:00.
