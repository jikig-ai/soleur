#!/usr/bin/env bash
# serve-soak-evidence-last.sh — read-only probe (#12849, G11): print the soak evidence of the newest completed
# cf-lb-overlay.yml run on main that carries any, so the soak a serve flip enforced, and why a serve was refused, can be
# read without opening the Actions UI.
#
#   usage: bash scripts/serve-soak-evidence-last.sh [--limit N]     (N = 1..50 runs, default 50, newest first)
#
# Output on a hit (exit 0; a hit = any soak evidence, instance or gate_fail line): `run=<id> branch=<branch>
# sha=<sha> conclusion=<conclusion>`, then at most 2 SOLEUR_SOAK_EVIDENCE lines (one per soak kind), the first
# `gate_fail sub_condition=<id>` line, and the LAST SOLEUR_INSTANCE_SOAK and `grade_text=` lines. Only lines printed by job ga_pool_update's `§(c) gate chain` and
# `per-instance soak grader` steps are read, and each must match WHOLE its grammar in scripts/lib/serve-soak-evidence.sh
# (a malformed or truncated line is never printed; a well-formed line is shape, not provenance).
# A run still in progress, or one whose log cannot be read (cancelled with no log, expired), is skipped and counted on
# stderr. No evidence in the readable runs: one line, exit 2. A gh/jq read fault on the run list, or no run log
# readable at all: exit 3. Bad arguments: exit 64. Needs only the operator's GitHub repository read (gh auth); it
# dispatches nothing. Exit 2 is the expected state until the first serve on this code has run.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/serve-soak-evidence.sh
# shellcheck disable=SC2015 # A && B || C is intended: any failed load step reaches the exit
# shellcheck disable=SC2090 # declare -p only tests that the names are set; their quoted values are never expanded here
source "$here/lib/serve-soak-evidence.sh" && declare -p SOAK_EV_RE INSTANCE_EV_RE GRADE_TEXT_RE >/dev/null 2>&1 \
  || { echo "serve-soak-evidence helper not loaded" >&2; exit 3; }

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

list="$(gh run list --workflow cf-lb-overlay.yml --branch main --limit "$limit" --json databaseId,headBranch,headSha,status,conclusion)" || exit 3
runs="$(jq -r '.[] | "\(.databaseId)\t\(.headBranch)\t\(.headSha)\t\(.status)\t\(.conclusion)"' <<<"$list")" || exit 3

soak_re="^${SOAK_EV_RE}\$"
inst_re="^${INSTANCE_EV_RE}\$"
fail_re='^gate_fail sub_condition=[A-Za-z0-9_]+$'
seen=0; readable=0; skipped=0
while IFS=$'\t' read -r id branch sha status conclusion; do
  [[ -n "$id" ]] || continue
  [[ "$seen" -lt "$limit" ]] || break
  seen=$((seen + 1))
  [[ "$id" =~ ^[0-9]+$ ]] || exit 3
  if [[ "$status" != completed ]]; then skipped=$((skipped + 1)); echo "skip run=${id} status=${status//[^a-z_]/}" >&2; continue; fi
  if ! log="$(gh run view "$id" --log 2>/dev/null)"; then skipped=$((skipped + 1)); echo "skip run=${id} log_unreadable" >&2; continue; fi
  readable=$((readable + 1))
  out=(); ns=0; nf=0; inst=""; grade=""; seen_k=","
  while IFS= read -r l; do
    # `gh run view --log` prefixes each line `<job>\t<step>\t<timestamp> `.
    job="${l%%$'\t'*}"; rest="${l#*$'\t'}"; step="${rest%%$'\t'*}"
    [[ "$job" == ga_pool_update && ( "$step" == "§(c) gate chain"* || "$step" == "per-instance soak grader"* ) ]] || continue
    l="${rest#*$'\t'}"; l="${l#* }"; l="${l%$'\r'}"
    # the first well-formed line PER KIND (one git_data, one workspaces_luks), never the first two lines
    if [[ "$l" =~ $soak_re ]]; then
      if [[ "$seen_k" != *",${BASH_REMATCH[1]},"* ]]; then seen_k="${seen_k}${BASH_REMATCH[1]},"; out+=("$l"); ns=$((ns + 1)); fi
    elif [[ "$nf" -lt 1 && "$l" =~ $fail_re ]]; then out+=("$l"); nf=$((nf + 1))
    # the LAST instance / grade_text line wins: the helper prints the real pair after the grader returns, so an
    # earlier well-formed line (the grader's own stderr, in the same step) is never shown as the verdict
    elif [[ "$l" =~ $inst_re ]]; then inst="$l"
    elif [[ "$l" == grade_text=* && ( "${l#grade_text=}" =~ $GRADE_TEXT_RE || "$l" == grade_text=unprintable ) ]]; then grade="$l"; fi
  done <<<"$log"
  [[ -z "$inst" ]] || out+=("$inst")
  [[ -z "$grade" ]] || out+=("$grade")
  # a refused serve with no evidence line (TOP, Condition A, gate_not_run_*) still answers "why was it refused"
  if [[ "$ns" -gt 0 || -n "$inst" || "$nf" -gt 0 ]]; then
    branch="${branch//[^A-Za-z0-9._\/-]/}"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || sha=invalid
    conclusion="${conclusion//[^a-z_]/}"
    printf 'run=%s branch=%s sha=%s conclusion=%s\n' "$id" "${branch:-invalid}" "$sha" "${conclusion:-none}"
    printf '%s\n' "${out[@]}"
    [[ "$skipped" -eq 0 ]] || echo "skipped ${skipped} newer run(s) (in progress or no readable log)" >&2
    exit 0
  fi
done <<<"$runs"

if [[ "$seen" -gt 0 && "$readable" -eq 0 ]]; then
  echo "no run log readable in the last ${seen} runs (${skipped} skipped)" >&2
  exit 3
fi
echo "no soak evidence in the last ${seen} runs"
[[ "$skipped" -eq 0 ]] || echo "skipped ${skipped} run(s) (in progress or no readable log)" >&2
exit 2
