#!/usr/bin/env bash
#
# blog-publishers-cost-rollup.sh — Cross-publisher Claude usage aggregator.
#
# Reads logs/cost-tracking.jsonl from each blog publisher (ambrosianomilano.it,
# officinewordpress.it, costanzogoldtraders.com) on VM 103 and sums the
# active Anthropic billing-cycle window against the Max-plan Agent SDK
# monthly credit ceiling ($100 on Max 5x, effective 2026-06-15).
#
# Usage:
#   CREDIT_PERIOD_START=2026-06-19T00:00:00Z \
#   CREDIT_PERIOD_END=2026-07-19T00:00:00Z \
#     ./blog-publishers-cost-rollup.sh
#
#   ./blog-publishers-cost-rollup.sh --threshold-check 100
#       Exit 0 if grand total cost in window < $100, exit 1 if >=.
#
#   ./blog-publishers-cost-rollup.sh --ceiling-usd 200
#       Override default $100 ceiling (also via CREDIT_CEILING_USD env).
#
# Env overrides:
#   JSONL_PATHS         Colon-separated list of cost-tracking.jsonl paths.
#   CREDIT_PERIOD_START ISO-8601 UTC start of billing window.
#   CREDIT_PERIOD_END   ISO-8601 UTC end of billing window.
#   CREDIT_CEILING_USD  Monthly credit ceiling in USD (default 100).
#
# If CREDIT_PERIOD_START/END are unset, falls back to the calendar UTC month
# of "now" and emits a stderr warning — the calendar month is NOT the same
# as the Anthropic billing cycle, which resets on the 19th.
#
# Robust to malformed JSONL lines (jq `fromjson?`), null total_cost_usd
# values (treated as 0.0), and missing/unreadable JSONL files (contribute 0
# with an `info:` line on stderr). LC_ALL=C forces decimal point under IT
# locale on VM 103.

set -u
set -o pipefail

export LC_ALL=C

DEFAULT_JSONL_PATHS=(
    "$HOME/Projects/ambrosianomilano.it/blog-publisher/logs/cost-tracking.jsonl"
    "$HOME/Projects/officinewordpress.it/scripts/blog-publisher/logs/cost-tracking.jsonl"
    "$HOME/Projects/costanzogoldtraders.com/blog-publisher/logs/cost-tracking.jsonl"
)

threshold=""
ceiling_usd="${CREDIT_CEILING_USD:-100}"

while (("$#")); do
    case "$1" in
    --threshold-check)
        threshold="${2:-}"
        shift 2
        ;;
    --ceiling-usd)
        ceiling_usd="${2:-}"
        shift 2
        ;;
    -h | --help)
        sed -n '2,35p' "$0" >&2
        exit 0
        ;;
    *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
    esac
done

# Resolve JSONL paths: env override (colon-separated) or defaults.
if [[ -n "${JSONL_PATHS:-}" ]]; then
    IFS=':' read -r -a JSONL_FILES <<<"$JSONL_PATHS"
else
    JSONL_FILES=("${DEFAULT_JSONL_PATHS[@]}")
fi

# Period envelope — explicit env vars override the calendar-month fallback.
if [[ -z "${CREDIT_PERIOD_START:-}" || -z "${CREDIT_PERIOD_END:-}" ]]; then
    echo "warn: CREDIT_PERIOD_START/END unset — falling back to calendar UTC month" >&2
    CREDIT_PERIOD_START="$(date -u +%Y-%m-01T00:00:00Z)"
    if date -u -v+1m -j +%Y-%m-01T00:00:00Z >/dev/null 2>&1; then
        CREDIT_PERIOD_END="$(date -u -v+1m +%Y-%m-01T00:00:00Z)"
    else
        CREDIT_PERIOD_END="$(date -u -d '+1 month' +%Y-%m-01T00:00:00Z)"
    fi
fi

export CREDIT_PERIOD_START
export CREDIT_PERIOD_END

# Derive publisher label from the path: basename of the parent of `logs/`.
# e.g. /home/x/Projects/ambrosianomilano.it/blog-publisher/logs/cost-tracking.jsonl
#   -> blog-publisher's parent is ambrosianomilano.it (use that as label).
publisher_label() {
    local jsonl="$1"
    local logs_dir parent grand
    logs_dir="$(dirname "$jsonl")"
    parent="$(dirname "$logs_dir")"
    grand="$(dirname "$parent")"
    # If parent is "blog-publisher" or "scripts/blog-publisher", climb one more.
    local base
    base="$(basename "$parent")"
    if [[ "$base" == "blog-publisher" ]]; then
        # If grandparent is "scripts", climb again to reach the project dir.
        local grandbase
        grandbase="$(basename "$grand")"
        if [[ "$grandbase" == "scripts" ]]; then
            basename "$(dirname "$grand")"
        else
            basename "$grand"
        fi
    else
        echo "$base"
    fi
}

# Per-file count + sum, robust to corrupt lines and null cost.
sum_file() {
    local jsonl="$1"
    if [[ ! -r "$jsonl" ]]; then
        echo "info: missing or unreadable: $jsonl (contributes 0)" >&2
        printf '0\t0\n'
        return 0
    fi
    jq -R 'fromjson? | select(type == "object")' "$jsonl" |
        jq -rs '
          [ .[]
            | select(.ts_utc >= env.CREDIT_PERIOD_START and .ts_utc < env.CREDIT_PERIOD_END)
          ] as $rows
          | [
              ($rows | length),
              ($rows | map(.total_cost_usd // 0) | add // 0)
            ] | @tsv
        '
}

grand_total="0"
grand_count="0"
declare -a labels counts totals

for jsonl in "${JSONL_FILES[@]}"; do
    label="$(publisher_label "$jsonl")"
    read -r c t < <(sum_file "$jsonl")
    c="${c:-0}"
    t="${t:-0}"
    labels+=("$label")
    counts+=("$c")
    totals+=("$t")
    grand_count=$((grand_count + c))
    grand_total=$(awk -v a="$grand_total" -v b="$t" 'BEGIN { printf "%.10f", a + b }')
done

# Threshold-check mode: just compare grand total and exit.
if [[ -n "$threshold" ]]; then
    over=$(awk -v t="$grand_total" -v th="$threshold" 'BEGIN { print (t >= th) ? 1 : 0 }')
    if [[ "$over" == "1" ]]; then
        exit 1
    fi
    exit 0
fi

# Compute utilization_pct = (grand_total / ceiling_usd) * 100.
utilization_pct=$(awk -v t="$grand_total" -v c="$ceiling_usd" 'BEGIN {
    if (c+0 == 0) { print "0.00" } else { printf "%.2f", (t / c) * 100 }
}')

# Per-publisher lines.
for i in "${!labels[@]}"; do
    printf '%-25s count=%-5s total_cost_usd=%.2f\n' \
        "${labels[$i]}" "${counts[$i]}" "${totals[$i]}"
done

printf -- '---\n'
printf 'grand_total_cost_usd=%.2f\n' "$grand_total"
printf 'ceiling_usd=%.2f\n' "$ceiling_usd"
printf 'utilization_pct=%s\n' "$utilization_pct"
printf 'period_start=%s\n' "$CREDIT_PERIOD_START"
printf 'period_end=%s\n' "$CREDIT_PERIOD_END"
