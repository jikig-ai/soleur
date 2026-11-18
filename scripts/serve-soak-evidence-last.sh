#!/usr/bin/env bash
# serve-soak-evidence-last.sh — read-only probe (#12849, G11): print the soak evidence of the newest cf-lb-overlay.yml
# run on main that carries any, so the soak a serve flip enforced can be read without opening the Actions UI.
#
#   usage: bash scripts/serve-soak-evidence-last.sh [--limit N]     (N = 1..50 runs, default 50, newest first)
#
# Output on a hit (exit 0): `run=<id> branch=<branch> sha=<sha>`, then at most 3 SOLEUR_SOAK_EVIDENCE lines and at most
# 1 SOLEUR_INSTANCE_SOAK line, each matched WHOLE against the grammar in scripts/lib/serve-soak-evidence.sh (a forged
# or truncated line is never printed). No evidence in the window: one line, exit 2. A gh/jq read fault: exit 3.
# Bad arguments: exit 64. Needs only the operator's GitHub repository read (gh auth); it dispatches nothing.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/serve-soak-evidence.sh
source "$here/lib/serve-soak-evidence.sh" || { echo "serve-soak-evidence helper not loaded" >&2; exit 3; }

limit=50
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)
      [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]?$ && "$2" -le 50 ]] || { echo "usage: $0 [--limit 1..50]" >&2; exit 64; }
      limit="$2"; shift 2 ;;
    *) echo "usage: $0 [--limit 1..50]" >&2; exit 64 ;;
  esac
done
command -v gh >/dev/null || { echo "gh not found" >&2; exit 3; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 3; }

list="$(gh run list --workflow cf-lb-overlay.yml --branch main --limit "$limit" --json databaseId,headBranch,headSha)" || exit 3
runs="$(jq -r '.[] | "\(.databaseId)\t\(.headBranch)\t\(.headSha)"' <<<"$list")" || exit 3

soak_re="^${SOAK_EV_RE}\$"
inst_re="^${INSTANCE_EV_RE}\$"
seen=0
while IFS=$'\t' read -r id branch sha; do
  [[ -n "$id" ]] || continue
  [[ "$seen" -lt "$limit" ]] || break
  seen=$((seen + 1))
  [[ "$id" =~ ^[0-9]+$ ]] || exit 3
  log="$(gh run view "$id" --log)" || exit 3
  out=(); ns=0; ni=0
  while IFS= read -r l; do
    # `gh run view --log` prefixes each line `<job>\t<step>\t<timestamp> `.
    l="${l#*$'\t'}"; l="${l#*$'\t'}"; l="${l#* }"; l="${l%$'\r'}"
    if [[ "$ns" -lt 3 && "$l" =~ $soak_re ]]; then out+=("$l"); ns=$((ns + 1))
    elif [[ "$ni" -lt 1 && "$l" =~ $inst_re ]]; then out+=("$l"); ni=$((ni + 1)); fi
  done <<<"$log"
  if [[ "${#out[@]}" -gt 0 ]]; then
    branch="${branch//[^A-Za-z0-9._\/-]/}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || sha=invalid
    printf 'run=%s branch=%s sha=%s\n' "$id" "${branch:-invalid}" "$sha"
    printf '%s\n' "${out[@]}"
    exit 0
  fi
done <<<"$runs"

echo "no soak evidence in the last ${seen} runs"
exit 2
