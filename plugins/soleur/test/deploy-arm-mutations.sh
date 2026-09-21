#!/usr/bin/env bash
# Hand-run mutation driver for plugins/soleur/scripts/deploy-arm.sh (#8492).
# Not a *.test.sh, so scripts/test-all.sh does not pick it up.
#
# Each row applies one Guard Contract mutation (plan §Guard Contract) to a SCRATCH
# copy of the script, asserts the mutant text actually changed, and runs
# deploy-arm.test.sh against it through DEPLOY_ARM_SUT. The unmutated control runs
# first and must be green, or every row is void. H3 re-runs row G1-2 with a stub that
# serves logs without --allow-escape-sequences: that row must SURVIVE, proving the
# stub's flag check is what kills it.
# shellcheck disable=SC2016  # the rows are literal source text, not expansions
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SRC="$REPO_ROOT/plugins/soleur/scripts/deploy-arm.sh"
SUITE="$HERE/deploy-arm.test.sh"
SCRATCH="$(mktemp -d -t deploy-arm-mut.XXXXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

run_suite() { # run_suite <sut> [env...] -> rc
  local sut="$1"; shift
  env "$@" DEPLOY_ARM_SUT="$sut" bash "$SUITE" > "$SCRATCH/last.log" 2>&1
}

run_suite "$SRC"; rc=$?
if [[ "$rc" != 0 ]]; then
  echo "CONTROL: unmutated suite is RED (rc=$rc) — every row would be void. Aborting."
  tail -5 "$SCRATCH/last.log"; exit 2
fi
echo "CONTROL: unmutated suite green"

# mutate <row> <python: old> <python: new> [count] — writes $SCRATCH/<row>.sh
mutate() {
  local out="$SCRATCH/$1.sh"
  ROW_OLD="$2" ROW_NEW="$3" ROW_COUNT="${4:-1}" SRC="$SRC" OUT="$out" python3 - <<'PY' || return 1
import os
s = open(os.environ["SRC"]).read()
count = int(os.environ["ROW_COUNT"])
m = s
# "|||" separates several (old, new) pairs applied to one mutant.
for old, new in zip(os.environ["ROW_OLD"].split("|||"), os.environ["ROW_NEW"].split("|||")):
    assert old in m, "anchor not found: " + old[:60]
    m = m.replace(old, new, count)
assert m != s, "mutation did not land"
open(os.environ["OUT"], "w").write(m)
PY
  printf '%s' "$out"
}

killed=0; survived=0
row() { # row <id> <want KILLED|SURVIVED> <old> <new> [count] [env...]
  local id="$1" want="$2" old="$3" new="$4" count="${5:-1}"; shift 5 2>/dev/null || shift $#
  local m verdict
  if ! m="$(mutate "$id" "$old" "$new" "$count")"; then echo "$id: MUTATION DID NOT LAND (anchor drift)"; survived=$((survived+1)); return; fi
  if run_suite "$m" "$@"; then verdict=SURVIVED; else verdict=KILLED; fi
  printf '%-6s %-9s (expected %s)\n' "$id" "$verdict" "$want"
  [[ "$verdict" == "$want" ]] && killed=$((killed+1)) || survived=$((survived+1))
}

# Guard 1 — selection.
row G1-1 KILLED 'done < <(sort -r "$fg")|||if [[ "${C_CLASS[n]}" == "exact" ]] && delivering "${C_DEPLOY[n]}"; then arm_line "$n"; return 0; fi' \
  'done < "$fg"|||C_CLASS[n]=exact; C_SHA[n]=$MERGE; C_DEPLOY[n]=success; arm_line "$n"; return 0' 1
row G1-2 KILLED 'gh api --allow-escape-sequences ' 'gh api ' 1
row G1-3 KILLED 'C_CLASS[i]="unresolved"; C_CAUSE[i]="log_read_failed"' 'C_CLASS[i]="reject"; C_CAUSE[i]="log_read_failed"' 1
row G1-4 KILLED 'rc="$(ancestry "$MERGE" "$d")"' 'rc="$(ancestry "$d" "$MERGE")"' 1
row G1-5 KILLED 'pending) blk_pending=1 ;;' 'pending) : ;;' 1
row G1-6 KILLED '    (( C_CREATED[i] >= ci_started_e )) || continue
    delivering "${C_DEPLOY[i]}" && best="$i"' '    delivering "${C_DEPLOY[i]}" && (( best < 0 )) && best="$i"' 1
row G1-7 KILLED 'if gh api --allow-escape-sequences "repos/{owner}/{repo}/actions/jobs/$rt/logs" > "$lf" 2>>"$TMP/gh.err"; then' \
  'if gh api --allow-escape-sequences "repos/{owner}/{repo}/actions/jobs/$rt/logs" 2>>"$TMP/gh.err" | grep -m1 -E "depth=1 origin|resolving deploy target" > "$lf"; then' 1
row G1-8 KILLED '  fetch_default
  while IFS=' '  while IFS=' 1
row G1-9 KILLED '[[ "$wc" == "failure" || "$wc" == "timed_out" ]] && { printf '"'"'blocked'"'"'; return 0; }' \
  '[[ "$wc" == "failure" || "$wc" == "timed_out" ]] && { printf '"'"'skipped'"'"'; return 0; }' 1
row G1-10 KILLED '^(success|failure|blocked|pending)$' '^(success|failure|blocked|pending|superseded)$' 1

# Guard 2 — containment.
row G2-1 KILLED '  fetch_default
  rc="$(ancestry "$m" "$b")"' '  rc=1' 1
row G2-2 KILLED 'then CV_LINE="UNRESOLVED"; CV_RC=3; return 0; fi' 'then CV_LINE="NOT_CONTAINED"; CV_RC=1; return 0; fi' 1
row G2-3 KILLED 'rc="$(ancestry "$m" "$b")"' 'rc="$(ancestry "$b" "$m")"' 1
row G2-4 KILLED '  if [[ -n "$body" ]]; then
    bsha=' '  [[ -n "$body" ]] || emit "NOT_CONTAINED BUILD_SHA=-" 1
  if [[ -n "$body" ]]; then
    bsha=' 1

# H3 — the stub's flag check is load-bearing: with a lax stub, G1-2 survives.
row H3 SURVIVED 'gh api --allow-escape-sequences ' 'gh api ' 1 STUB_LAX_ESCAPES=1

echo
echo "as expected: $killed   unexpected: $survived"
[[ "$survived" == 0 ]]
