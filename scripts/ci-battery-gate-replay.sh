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
# The gated arrays are DERIVED from the runner's own --pr-gated call sites, never listed here, so a
# sixth gated battery appears in this report without anyone remembering to add it.
gated=$(sed 's/[[:space:]]*#.*$//' scripts/test-all.sh | grep -oE '_diff_touches --pr-gated +"\$\{[A-Z0-9_]+' | sed 's/.*{//' | LC_ALL=C sort -u) || gated=""
[[ -n "$gated" ]] || { echo "no --pr-gated call site found in scripts/test-all.sh" >&2; exit 2; }
for arr in $gated; do
  # shellcheck disable=SC1087,SC2154  # eval is the bash-3.2 indirection by array NAME (derived above)
  eval "paths=( \${${arr}[@]+\"\${${arr}[@]}\"} )"
  # shellcheck disable=SC2154  # `paths` is assigned by the eval above
  awk -v arr="$arr" -v P="$(printf '%s\n' "${paths[@]}")" '
    BEGIN { k = split(P, a, "\n") }
    function done_commit() { if (c) { t++; if (h) r++ } c = 1; h = 0 }
    /^@@@$/ { done_commit(); next }
    { for (i = 1; i <= k; i++) if (a[i] != "" && index($0, a[i])) h = 1 }
    END { done_commit(); printf "%.0f%%\t%s\t(%d/%d commits arm it)\n", t ? 100 * r / t : 0, arr, r, t }
  ' <<<"$log"
done
