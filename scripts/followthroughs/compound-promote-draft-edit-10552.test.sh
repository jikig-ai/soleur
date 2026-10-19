#!/usr/bin/env bash
# Fixture tests for the #10552 follow-through probe (Guard 2 of the plan
# 2026-10-19-fix-compound-promote-diff-underivable-apply-plan.md).
#
# The probe must exit 0 ONLY on positive evidence that a server-derived diff was
# consumed: a draft PR opened (clusters_opened >= 1) or a refusal that can occur
# only AFTER `checkDiffPaths` accepted the derived diff (class P). Silence, a dark
# channel, a repeat of the old refusal, a week of model-side `edit-*` refusals, and
# refusals that fire without touching the derived diff must never exit 0.
#
# Rows P-1 .. P-10 are the Guard 2 mutation matrix, one behavioural row each (some
# with several fixtures). The harness rows follow: an assertion-count floor reported
# with printf+exit (never through pass()/fail()), an instrument self-test, and
# must-PASS inputs that are NOT the canonical happy path (a manual-trigger row, two
# runs where one is class P and one quiet, an unknown reason that carries ANSI
# escapes and must be printed as `unknown`). Two probe MUTATIONS prove the field
# isolation and the floor filter are load-bearing.
#
# All fixtures are synthesized. Nothing here talks to a network or reads a secret.
set -uo pipefail

TMP_ROOT=$(mktemp -d -t ft10552root.XXXXXXXX) || {
  echo "FATAL: could not create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || {
  echo "FATAL: scratch root is not an absolute real directory: $TMP_ROOT" >&2; exit 1; }
readonly TMP_ROOT
export TMPDIR="$TMP_ROOT"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_SRC="$REPO_ROOT/scripts/followthroughs/compound-promote-draft-edit-10552.sh"
PROBE_REL="scripts/followthroughs/compound-promote-draft-edit-10552.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

passes=0; fails=0
# Append-only ledger: the verdict below reads THIS, not the counter, so a redirected
# counter increment cannot silence a real failure.
FAILURES=()
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); FAILURES+=("$1"); }

# expect_rc <label> <expected> <actual>: the single assertion instrument.
expect_rc() {
  if [[ "$3" == "$2" ]]; then pass "$1: rc=$3"; else fail "$1: expected rc=$2, got rc=$3"; fi
}

# --- time model: every fixture is positioned relative to a floor we choose -----
NOW_S="$(date -u +%s)"
floor_iso() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }
FLOOR_S=$((NOW_S - 10 * 86400))          # a floor 10 days ago: inside the 35-day budget
FLOOR_ISO="$(floor_iso "$FLOOR_S")"
# dt_at <floor-seconds> <hours-after-floor> -> the Better Stack `dt` shape.
dt_at() { date -u -d "@$(($1 + $2 * 3600))" '+%Y-%m-%d %H:%M:%S'; }

# --- sandbox: a stub query helper that simulates the server-side LIKE ----------
make_sandbox() { # make_sandbox <fixture-file> [probe]
  local fixture="$1" probe="${2:-$PROBE_SRC}" d
  d=$(mktemp -d -t ft10552.XXXXXXXX); : "${d:?}"
  mkdir -p "$d/scripts/followthroughs"
  cp "$probe" "$d/$PROBE_REL"
  chmod +x "$d/$PROBE_REL"
  cp "$fixture" "$d/rows.jsonl"
  cat > "$d/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
# Simulated betterstack-query.sh: honours --grep as a substring over raw rows (the
# real helper compiles it to `raw LIKE '%...%'`), ignores --since (the probe's own
# floor filter is what is under test). Exit 3 when asked to.
pat=""
while [ $# -gt 0 ]; do case "$1" in --grep) pat="$2"; shift 2;; *) shift;; esac; done
[ -n "${STUB_EXIT3:-}" ] && { echo "You are NOT missing Better Stack access" >&2; exit 3; }
[ -n "${STUB_EXIT7:-}" ] && { echo "clickhouse exploded" >&2; exit 7; }
grep -F -- "$pat" "$(dirname "$0")/../rows.jsonl" || true
STUB
  chmod +x "$d/scripts/betterstack-query.sh"
  echo "$d"
}

# A row is {dt, raw}; raw is a JSON STRING whose decoded object carries the pino
# payload under `.message` - the measured live shape (runbook, row shape).
row() { # row <inner-json> <dt>
  local inner="$1" dt="$2"
  jq -c -n --arg dt "$dt" --arg raw "$(jq -c -n --argjson m "$inner" '{message:$m}')" '{dt:$dt, raw:$raw}'
}

# marker <trigger> <status> <opened> <refusals-json-array>
marker() {
  jq -c -n --arg t "$1" --arg s "$2" --argjson o "$3" --argjson r "$4" \
    '{SOLEUR_COMPOUND_PROMOTE_OUTCOME:true, fn:"cron-compound-promote", trigger:$t, status:$s, clusters_opened:$o, refusals:$r}'
}

CONTROL='{"SOLEUR_CLAUDE_COST":true,"component":"claude-cost","fn":"cron-x","cost_usd":1}'

fx() { f=$(mktemp -t ft.XXXXXXXX); printf '%s\n' "$@" > "$f"; echo "$f"; }

# run_probe <dir> [env...] -> echoes the rc; stdout/stderr land in $dir/out and $dir/err.
run_probe() {
  local dir="$1"; shift
  ( cd "$dir" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
      BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      FT10552_DEPLOY_FLOOR="$FLOOR_ISO" "$@" \
      bash "$PROBE_REL" >"$dir/out" 2>"$dir/err" )
  echo $?
}
# A sandbox + run in one step. Callers pass the fixture rows as arguments.
probe_rows() { # probe_rows <env-assignments-or-empty> -- rows...
  local envs=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  PROBE_DIR=$(make_sandbox "$(fx "$@")")
  PROBE_RC=$(run_probe "$PROBE_DIR" "${envs[@]}")
}
out_of() { cat "$PROBE_DIR/out"; }
err_of() { cat "$PROBE_DIR/err"; }

D1="$(dt_at "$FLOOR_S" 24)"      # one day after the floor
D2="$(dt_at "$FLOOR_S" 48)"
D3="$(dt_at "$FLOOR_S" 72)"
DPRE="$(dt_at "$FLOOR_S" -48)"   # two days BEFORE the floor (old code)
C="$(row "$CONTROL" "$D1")"

echo "P-1. window contains only no-qualifying-clusters rows -> exit 2, never 0"
probe_rows -- "$C" "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D1")" \
  "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D2")"
expect_rc "P-1" 2 "$PROBE_RC"
if [[ "$(out_of)" != "PASS" ]]; then pass "P-1: stdout is not PASS"; else fail "P-1: stdout was PASS on a quiet window"; fi

echo "P-2. every post-floor refusal is diff-underivable-apply -> exit 1"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["diff-underivable-apply","diff-underivable-apply"]')" "$D2")"
expect_rc "P-2" 1 "$PROBE_RC"
if grep -q 'diff-underivable-apply' "$PROBE_DIR/err"; then pass "P-2: the defect reason is printed"; else fail "P-2: reason not printed: $(err_of)"; fi
for r in git-apply-check-failed edit-derive-failed diff-underivable-structural; do
  probe_rows -- "$C" "$(row "$(marker cron completed 0 "[\"$r\"]")" "$D1")"
  expect_rc "P-2 (class F: $r)" 1 "$PROBE_RC"
done

echo "P-3. clusters_opened >= 1 -> exit 0, stdout is the literal PASS"
probe_rows -- "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")"
expect_rc "P-3" 0 "$PROBE_RC"
if [[ "$(out_of)" == "PASS" ]]; then pass "P-3: stdout is exactly PASS"; else fail "P-3: stdout was '$(out_of)'"; fi
probe_rows -- "$C" "$(row "$(marker cron completed 0 '[]')" "$D1")"
expect_rc "P-3 (completed, zero opened, no refusals is not proof)" 2 "$PROBE_RC"

echo "P-4. refusals are all model-side edit-* -> exit 2 with the reasons printed"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["edit-anchor-not-found","edit-invalid","edit-anchor-ambiguous","edit-target-unreadable","edit-target-too-large","edit-target-duplicate"]')" "$D1")"
expect_rc "P-4" 2 "$PROBE_RC"
for r in edit-anchor-not-found edit-invalid edit-anchor-ambiguous edit-target-unreadable edit-target-too-large edit-target-duplicate; do
  if grep -q -- "$r" "$PROBE_DIR/err"; then pass "P-4: prints $r"; else fail "P-4: $r missing from: $(err_of)"; fi
done

echo "P-5. a class-P refusal and no class-F refusal -> exit 0"
for r in diff-path-off-target byte-budget-overflow corpus-shrink-refused agents-core-hr-rule-edit-refused not-committed-pr-create; do
  probe_rows -- "$C" "$(row "$(marker cron completed 0 "[\"$r\"]")" "$D1")"
  expect_rc "P-5 ($r)" 0 "$PROBE_RC"
  if [[ "$(out_of)" == "PASS" ]]; then pass "P-5 ($r): stdout is exactly PASS"; else fail "P-5 ($r): stdout '$(out_of)'"; fi
done

echo "P-6. only skill-conflict-guard / target-path-refused (and the other N-class reasons) -> exit 2, never 0"
for r in skill-conflict-guard target-path-refused target-missing branch-name-shape-failed diff-size-exceeded; do
  probe_rows -- "$C" "$(row "$(marker cron completed 0 "[\"$r\"]")" "$D1")"
  expect_rc "P-6 ($r)" 2 "$PROBE_RC"
  if grep -q -- "$r" "$PROBE_DIR/err"; then pass "P-6 ($r): printed"; else fail "P-6 ($r): not printed"; fi
done
for s in week-cap-reached deduped disabled empty-corpus anthropic-truncated error; do
  probe_rows -- "$C" "$(row "$(marker cron "$s" 0 '[]')" "$D1")"
  expect_rc "P-6 (status $s)" 2 "$PROBE_RC"
done

echo "P-7. floor unset or unparsable, or no positive-control rows -> exit 3, never 0 or 1"
d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")")")
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
        BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        bash "$PROBE_REL" >/dev/null 2>"$d/err"; echo $? )
expect_rc "P-7 (floor unset: no default)" 3 "$rc"
for bad in not-a-date yesterday "2026-13-45T99:99:99Z" "2026-09-18" ""; do
  d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")")")
  rc=$(run_probe "$d" FT10552_DEPLOY_FLOOR="$bad")
  expect_rc "P-7 (floor '$bad')" 3 "$rc"
done
probe_rows -- "$(row "$(marker cron completed 1 '[]')" "$D1")"
expect_rc "P-7 (control rows absent, a would-be PASS present)" 3 "$PROBE_RC"
probe_rows -- "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D1")"
expect_rc "P-7 (control rows absent, a would-be FAIL present)" 3 "$PROBE_RC"
probe_rows STUB_EXIT3=1 -- "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")"
expect_rc "P-7 (query helper exits 3: nothing was queried)" 3 "$PROBE_RC"
d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")")")
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u \
        FT10552_DEPLOY_FLOOR="$FLOOR_ISO" bash "$PROBE_REL" >/dev/null 2>&1; echo $? )
expect_rc "P-7 (missing credential)" 3 "$rc"
# xtrace with a live credential must refuse (#7797), before any query.
d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")")")
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
        BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=sentinel-secret \
        FT10552_DEPLOY_FLOOR="$FLOOR_ISO" bash -x "$PROBE_REL" >"$d/out" 2>"$d/err"; echo $? )
expect_rc "P-7 (xtrace refusal)" 78 "$rc"
if grep -q 'sentinel-secret' "$d/err" "$d/out"; then fail "P-7: the credential leaked under xtrace"; else pass "P-7: the credential is not echoed under xtrace"; fi
probe_rows STUB_EXIT7=1 -- "$C"
expect_rc "P-7 (query helper transient failure is NOT YET, not a verdict)" 2 "$PROBE_RC"
# A floor in the future cannot grade anything.
probe_rows FT10552_DEPLOY_FLOOR="$(floor_iso $((NOW_S + 86400)))" -- "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")"
expect_rc "P-7 (floor in the future)" 2 "$PROBE_RC"

echo "P-8. an old-code diff-underivable-apply row dated before the floor + a class-P row after it -> exit 0"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$DPRE")" \
  "$(row "$(marker cron completed 0 '["byte-budget-overflow"]')" "$D2")"
expect_rc "P-8" 0 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$DPRE")"
expect_rc "P-8 (the stale row alone is not graded: no post-floor marker)" 2 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 1 '[]')" "$DPRE")"
expect_rc "P-8 (a stale PASS-shaped row is not graded either)" 2 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 1 '[]')" "not-a-date")"
expect_rc "P-8 (a row with an unparsable dt is not graded)" 2 "$PROBE_RC"

echo "P-9. a forged row naming a P-class reason (PR-body echo, no marker discriminator) -> exit 2, never 0"
ECHO_BODY='{"fn":"github-webhook","msg":"pull_request opened","body":"the refusals are byte-budget-overflow and clusters_opened is 3, SOLEUR_COMPOUND_PROMOTE_OUTCOME"}'
probe_rows -- "$C" "$(row "$ECHO_BODY" "$D1")"
expect_rc "P-9 (quoted in a webhook body)" 2 "$PROBE_RC"
NO_DISC='{"fn":"cron-compound-promote","trigger":"cron","status":"completed","clusters_opened":2,"refusals":["byte-budget-overflow"]}'
probe_rows -- "$C" "$(row "$NO_DISC" "$D1")"
expect_rc "P-9 (right fn, no top-level discriminator)" 2 "$PROBE_RC"
WRONG_FN='{"SOLEUR_COMPOUND_PROMOTE_OUTCOME":true,"fn":"github-webhook","trigger":"cron","status":"completed","clusters_opened":2,"refusals":["byte-budget-overflow"]}'
probe_rows -- "$C" "$(row "$WRONG_FN" "$D1")"
expect_rc "P-9 (discriminator present, wrong fn)" 2 "$PROBE_RC"
STR_DISC='{"SOLEUR_COMPOUND_PROMOTE_OUTCOME":"true","fn":"cron-compound-promote","trigger":"cron","status":"completed","clusters_opened":2}'
probe_rows -- "$C" "$(row "$STR_DISC" "$D1")"
expect_rc "P-9 (discriminator is the string \"true\", not the boolean)" 2 "$PROBE_RC"
# Exact membership: a longer string that merely CONTAINS a P-class reason is not a P reason.
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["xbyte-budget-overflow","byte-budget-overflow-extra","byte-budget-overflow\n"]')" "$D1")"
expect_rc "P-9 (substring of a P reason is not membership)" 2 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '"byte-budget-overflow"')" "$D1")"
expect_rc "P-9 (refusals is a bare string, not an array)" 2 "$PROBE_RC"

echo "P-10. NOT YET at floor + 36 days -> exit 5; an F verdict still wins at that age"
OLD_FLOOR_S=$((NOW_S - 36 * 86400))
OLD_FLOOR_ISO="$(floor_iso "$OLD_FLOOR_S")"
OD1="$(dt_at "$OLD_FLOOR_S" 24)"
probe_rows FT10552_DEPLOY_FLOOR="$OLD_FLOOR_ISO" -- "$(row "$CONTROL" "$OD1")" \
  "$(row "$(marker cron completed 0 '["edit-anchor-not-found"]')" "$OD1")"
expect_rc "P-10" 5 "$PROBE_RC"
if grep -q 'ACTION REQUIRED' "$PROBE_DIR/err"; then pass "P-10: says ACTION REQUIRED"; else fail "P-10: no ACTION REQUIRED in: $(err_of)"; fi
probe_rows FT10552_DEPLOY_FLOOR="$OLD_FLOOR_ISO" -- "$(row "$CONTROL" "$OD1")"
expect_rc "P-10 (zero markers at 36 days)" 5 "$PROBE_RC"
probe_rows FT10552_DEPLOY_FLOOR="$(floor_iso $((NOW_S - 30 * 86400)))" -- "$(row "$CONTROL" "$D1")"
expect_rc "P-10 (30 days is still NOT YET, not 5)" 2 "$PROBE_RC"
probe_rows FT10552_DEPLOY_FLOOR="$OLD_FLOOR_ISO" -- "$(row "$CONTROL" "$OD1")" \
  "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$OD1")"
expect_rc "P-10 (a defect at 36 days is still exit 1)" 1 "$PROBE_RC"
probe_rows FT10552_DEPLOY_FLOOR="$OLD_FLOOR_ISO" -- "$(row "$CONTROL" "$OD1")" \
  "$(row "$(marker cron completed 1 '[]')" "$OD1")"
expect_rc "P-10 (proof at 36 days is still exit 0)" 0 "$PROBE_RC"

echo "precedence: any P row -> PASS; otherwise the LATEST post-floor run decides"
probe_rows -- "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D3")"
expect_rc "P earlier, F later -> PASS (a P row anywhere wins)" 0 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["edit-invalid"]')" "$D3")"
expect_rc "F earlier, N later -> NOT YET (the latest run decides)" 2 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["edit-invalid"]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D3")"
expect_rc "N earlier, F later -> FAIL" 1 "$PROBE_RC"
# The fixture file order is deliberately the REVERSE of time order.
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["edit-invalid"]')" "$D3")" \
  "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$D1")"
expect_rc "rows listed newest-first: F is the OLDER run, N the latest -> NOT YET" 2 "$PROBE_RC"

# --- harness rows -----------------------------------------------------------
echo "H-1. instrument self-test: the assertion helper must be able to FAIL"
before_fails=$fails; before_passes=$passes; before_ledger=${#FAILURES[@]}
expect_rc "self-test (deliberate mismatch, discarded below)" 0 1 >/dev/null
if (( fails == before_fails + 1 && ${#FAILURES[@]} == before_ledger + 1 && passes == before_passes )); then
  fails=$before_fails; unset 'FAILURES[${#FAILURES[@]}-1]'; FAILURES=("${FAILURES[@]}")
  pass "H-1: expect_rc records a mismatch in both the counter and the ledger"
else
  fail "H-1: expect_rc did not register a deliberate mismatch - the suite cannot fail"
fi
# The stub must honour --grep: a fixture with no control row yields no control rows.
d=$(make_sandbox "$(fx "$(row "$(marker cron completed 1 '[]')" "$D1")")")
stub_out="$(cd "$d" && bash scripts/betterstack-query.sh --grep SOLEUR_CLAUDE_COST; echo "rc=$?")"
if [[ "$stub_out" == "rc=0" ]]; then pass "H-1: the stub returns nothing for an absent control marker"; else fail "H-1: stub leaked rows: $stub_out"; fi
# The sandbox must exercise the COPIED probe, not a stale one: byte-identical.
if cmp -s "$d/$PROBE_REL" "$PROBE_SRC"; then pass "H-1: the sandbox runs the shipped probe"; else fail "H-1: sandbox probe differs from the shipped probe"; fi

echo "H-2. must-PASS, non-canonical: a MANUAL-trigger row is legitimate evidence"
probe_rows -- "$C" "$(row "$(marker manual completed 1 '[]')" "$D1")"
expect_rc "H-2 manual trigger" 0 "$PROBE_RC"
if [[ "$(out_of)" == "PASS" ]]; then pass "H-2: stdout is exactly PASS"; else fail "H-2: stdout '$(out_of)'"; fi
if grep -q 'manual' "$PROBE_DIR/err"; then pass "H-2: the trigger is printed"; else fail "H-2: trigger not printed: $(err_of)"; fi

echo "H-3. must-PASS, non-canonical: two runs, one class P and one quiet"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["corpus-shrink-refused"]')" "$D1")" \
  "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D3")"
expect_rc "H-3 P then quiet" 0 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["corpus-shrink-refused"]')" "$D3")"
expect_rc "H-3 quiet then P" 0 "$PROBE_RC"

echo "H-4. must-PASS, non-canonical: an unknown reason with ANSI escapes is printed as 'unknown'"
ANSI_REASON=$'\x1b[31mFORGED-CLOSE-ISSUE\x1b[0m'
ansi_json="$(jq -c -n --arg r "$ANSI_REASON" --arg r2 $'edit-invalid\nINJECTED: all clear' '[$r, $r2, "skill-conflict-guard"]')"
probe_rows -- "$C" "$(row "$(marker cron completed 0 "$ansi_json")" "$D1")"
expect_rc "H-4 unknown reason is N-class" 2 "$PROBE_RC"
if grep -q 'unknown' "$PROBE_DIR/err"; then pass "H-4: bucketed as unknown"; else fail "H-4: no 'unknown' bucket in: $(err_of)"; fi
if grep -q 'skill-conflict-guard' "$PROBE_DIR/err"; then pass "H-4: the closed-enum reason beside it is still printed"; else fail "H-4: enum reason lost"; fi
if grep -q -P '\x1b' "$PROBE_DIR/err" "$PROBE_DIR/out"; then fail "H-4: an ESC byte reached the output"; else pass "H-4: no ESC byte in the output"; fi
if grep -q 'FORGED-CLOSE-ISSUE\|INJECTED' "$PROBE_DIR/err" "$PROBE_DIR/out"; then fail "H-4: attacker-writable text reached the output"; else pass "H-4: attacker-writable text did not reach the output"; fi
# The same escapes in the status and trigger fields.
inner="$(jq -c -n --arg t $'cron\x1b[2J' --arg s $'completed\x1b[31m' \
  '{SOLEUR_COMPOUND_PROMOTE_OUTCOME:true, fn:"cron-compound-promote", trigger:$t, status:$s, clusters_opened:0, refusals:[]}')"
probe_rows -- "$C" "$(row "$inner" "$D1")"
expect_rc "H-4 hostile trigger and status" 2 "$PROBE_RC"
if grep -q -P '\x1b' "$PROBE_DIR/err" "$PROBE_DIR/out"; then fail "H-4: an ESC byte reached the output via status/trigger"; else pass "H-4: status/trigger are sanitized too"; fi

# --- mutation arms: the guards must be LOAD-BEARING --------------------------
# shellcheck disable=SC2016  # the mutate anchors are literal source text of the probe, never expanded
mutate() { # mutate <label> <python-old> <python-new>  -> echoes the mutant path, "" if it did not land
  local m; m=$(mktemp -t ft10552mut.XXXXXXXX)
  python3 - "$PROBE_SRC" "$m" "$2" "$3" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3], sys.argv[4]
if src.count(old) != 1:
    open(sys.argv[2], "w").write(src)
else:
    open(sys.argv[2], "w").write(src.replace(old, new, 1))
PYEOF
  if cmp -s "$m" "$PROBE_SRC"; then echo ""; else echo "$m"; fi
}

echo "M-1. MUTATION: drop the fn field-isolation -> the wrong-fn forged row must flip to PASS"
# shellcheck disable=SC2016  # literal probe source text, not an expansion
m="$(mutate fn ' and $m.fn == "cron-compound-promote"' '')"
if [[ -z "$m" ]]; then fail "M-1 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$C" "$(row "$WRONG_FN" "$D1")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "fn isolation is load-bearing (mutant PASSes on a forged row)"; else fail "mutant did not flip (rc=$rc): P-9 is not pinning .fn"; fi
fi

echo "M-2. MUTATION: drop the floor filter -> the stale row must be graded (P-8 flips)"
# shellcheck disable=SC2016  # literal probe source text, not an expansion
m="$(mutate floor '| select($d19 >= $floor)' '')"
if [[ -z "$m" ]]; then fail "M-2 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$DPRE")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 1 ]]; then pass "floor filter is load-bearing (mutant grades the pre-floor row)"; else fail "mutant did not flip (rc=$rc): P-8 is not pinning the floor"; fi
fi

echo "M-3. MUTATION: grade PASS as the complement of the failure set -> a skill-conflict-guard-only window must flip to PASS"
# shellcheck disable=SC2016  # literal probe source text, not an expansion
m="$(mutate complement 'elif ($rs | any(isF)) then "F" else "N" end' 'elif ($rs | any(isF)) then "F" elif ($rs | length) > 0 then "P" else "N" end')"
if [[ -z "$m" ]]; then fail "M-3 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$C" "$(row "$(marker cron completed 0 '["skill-conflict-guard"]')" "$D1")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "the allowlist is load-bearing (a complement passes silence)"; else fail "mutant did not flip (rc=$rc): P-6 is not pinning the allowlist"; fi
fi

echo "M-4. MUTATION: drop the positive control -> a dark channel must stop being exit 3"
# shellcheck disable=SC2016  # literal probe source text, not an expansion
m="$(mutate control 'if ! numeric "$ctl_n" || [ "$ctl_n" -eq 0 ]; then' 'if false; then')"
if [[ -z "$m" ]]; then fail "M-4 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$(row "$(marker cron completed 1 '[]')" "$D1")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "the control is load-bearing (mutant PASSes through a dark channel)"; else fail "mutant did not flip (rc=$rc)"; fi
fi

# --- verdict: floor + conservation reported DIRECTLY, never via pass()/fail() --
MIN_CASES=90
total=$((passes + fails))
if (( total < MIN_CASES )); then
  printf 'FATAL: only %d case(s) ran; floor is %d - the suite asserted nothing\n' "$total" "$MIN_CASES" >&2
  exit 1
fi
if (( ${#FAILURES[@]} != fails )); then
  printf 'FATAL: failure ledger (%d) and counter (%d) disagree\n' "${#FAILURES[@]}" "$fails" >&2
  exit 1
fi
echo
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILED: %d\n' "${#FAILURES[@]}"; printf '  - %s\n' "${FAILURES[@]}"; exit 1
fi
printf 'All fixtures passed (%d cases).\n' "$total"
