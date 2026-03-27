# Repository Guidelines

## Project Structure & Module Organization
This repository is infrastructure-as-documentation for the NWLab Proxmox environment. Keep top-level context in `README.md` and the authoritative inventory in `CLAUDE.md`. Store cross-host procedures in `docs/` such as [`docs/backups.md`](docs/backups.md). Use `flatcar-nwdesigns/config/` for VM 104 mirrored service configs and `flatcar-nwdesigns/docs/` for service notes. Keep workstation-specific notes in `ubuntu-desktop/`.

## Build, Test, and Development Commands
There is no app build pipeline in this repo; validation is documentation- and infrastructure-driven. Useful commands:

```bash
rg --files
git diff --stat
ssh root@10.21.21.99 "qm list && pct list"
ssh root@10.21.21.99 "zpool status storage && pvesm status"
ssh core@10.21.21.104 "sudo docker ps"
```

Use these to confirm guest inventory, storage health, and Flatcar service state before editing docs. If a command changes infrastructure state, document it separately instead of folding it into a docs-only change.

## Coding Style & Naming Conventions
Write concise Markdown with factual, current values. Prefer tables for inventories and fenced `bash` blocks for commands. Keep filenames lowercase and hyphenated, matching existing docs such as `backups.md` and `services.md`. Preserve hostnames, VMIDs, IPs, and storage names exactly as they exist in Proxmox.

## Testing Guidelines
No automated test suite is present. Validate every changed claim against live SSH output or the mirrored config files. When a change affects both global and guest-specific docs, update both in the same patch so `README.md`, `CLAUDE.md`, and the guest subtree do not drift.

## Commit & Pull Request Guidelines
Follow the repository’s Conventional Commit pattern: `docs:`, `fix(vm104):`, `feat(pbs):`. Keep commits small and scoped to one infrastructure change. PRs should include a short summary, affected hosts or VMIDs, linked issues, and the verification commands you ran. Include screenshots only when updating web UI references or dashboard evidence.

## Security & Change Discipline
Never commit secrets, tokens, or raw `.env` files. Use templates such as `.env.example` when needed, and sanitize copied command output. Use a Git worktree for implementation work instead of editing directly on `main`.
