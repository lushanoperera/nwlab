# ops/

Operational scripts shared across the nwlab fleet.

## `blog-publishers-cost-rollup.sh`

Cross-publisher Claude headless cost aggregator. Sums `logs/cost-tracking.jsonl`
from each of the three blog publishers (ambrosianomilano.it,
officinewordpress.it, costanzogoldtraders.com) on VM 103 over the active
Anthropic billing-cycle window and compares against the Max-plan Agent SDK
monthly credit ceiling ($100 on Max 5x, effective 2026-06-15).

Each publisher's `scripts/cron-wrap.sh` invokes it post-run with
`--threshold-check $CREDIT_CEILING_USD` (fail-open: missing rollup binary
or any subprocess failure silently no-ops). The rollup is also queried
manually from the dashboard server for ad-hoc audits.

**Install on VM 103**: symlink or rsync this file into
`~/Projects/blog-publishers-rollup` so each publisher's `cron-wrap.sh` can
locate it on `$PATH`. Do not commit a deploy script here — the install is
a one-time manual step and the source of truth stays in this repo.

Run `./blog-publishers-cost-rollup.sh --help` for full usage.
