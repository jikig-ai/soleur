#!/usr/bin/env bash
# Replay each --pr-gated battery's relevance array against the last N first-parent commits (#9323,
# ADR-262). Read-only, no fetch. Matches the way _diff_touches does: a substring match over the
# commit's name-status blob (rename sources included). Prints `run_rate` per battery.
#   bash scripts/ci-battery-gate-replay.sh [--commits N]     (default 300)
set -uo pipefail
n=300
if [[ "${1:-}" == "--commits" && "${2:-}" =~ ^[0-9]+$ ]]; then n="$2"; fi
cd "$(git rev-parse --show-toplevel)" || exit 2
# shellcheck source=scripts/lib/test-relevance-paths.sh
source scripts/lib/test-relevance-paths.sh
base=origin/main
git rev-parse --verify -q "$base" >/dev/null 2>&1 || base=HEAD   # sandboxed checkouts carry no origin/main
log=$(git log --first-parent -n "$n" --format='tformat:@@@' --name-status -M "$base" 2>/dev/null) || exit 2
printf 'run_rate\tbattery\t(base=%s commits=%s)\n' "$base" "$(grep -c '^@@@$' <<<"$log")"
for arr in REGISTRY_BATTERY_PATHS CF_TUNNEL_BATTERY_PATHS LINT_ORPHAN_BATTERY_PATHS \
           TAG_AUTHORSHIP_BATTERY_PATHS TEST_ALL_AFFECTED_BATTERY_PATHS; do
  eval "paths=( \${$arr[@]+\"\${$arr[@]}\"} )"
  awk -v arr="$arr" -v P="$(printf '%s\n' "${paths[@]}")" '
    BEGIN { k = split(P, a, "\n") }
    function done_commit() { if (c) { t++; if (h) r++ } c = 1; h = 0 }
    /^@@@$/ { done_commit(); next }
    { for (i = 1; i <= k; i++) if (a[i] != "" && index($0, a[i])) h = 1 }
    END { done_commit(); printf "%.0f%%\t%s\t(%d/%d commits arm it)\n", t ? 100 * r / t : 0, arr, r, t }
  ' <<<"$log"
done
