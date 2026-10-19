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
# escapes and must be printed as `unknown`). Probe MUTATIONS prove the field
# isolation and the floor filter are load-bearing.
#
# Floor rows (F-*, U-*, V-*, Q-*, B-*, X-*): the sweeper runs the probe under `env -i`
# with only the three BETTERSTACK_QUERY_* names, so the deploy floor is DERIVED from git
# (oldest commit that added the script + 3h). Those rows build throwaway git repos
# (scrubbed env, fixed identity and dates), run the probe with ONLY PATH and the three
# credential names, pin the closed cause vocabulary of every unresolvable floor, record
# the query helper's argv (the --since window and both --limit values), freeze the
# probe's clock with a PATH-shimmed `date` for the 35-day boundary pair, and prove
# nothing raw from the query helper's stderr reaches the output. Mutation rows M-5 ..
# M-13 prove each of those guards is load-bearing.
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

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

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
# real helper compiles it to `raw LIKE '%...%'`), ignores --since for FILTERING (the
# probe's own floor filter is what is under test) but RECORDS its whole argv, one line
# per call, in ../argv.log so the suite can pin the --since window and --limit values.
# Exit 3 when asked to; STUB_MSG is the (possibly hostile) stderr it prints.
pat=""
printf '%s\n' "$*" >> "$(dirname "$0")/../argv.log"
while [ $# -gt 0 ]; do case "$1" in --grep) pat="$2"; shift 2;; *) shift;; esac; done
[ -n "${STUB_EXIT3:-}" ] && { printf '%s' "${STUB_MSG:-You are NOT missing Better Stack access}" >&2; exit 3; }
[ -n "${STUB_EXIT7:-}" ] && { printf '%s' "${STUB_MSG:-clickhouse exploded}" >&2; exit 7; }
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
  assert_fixture_dir "$dir"
  ( cd "$dir" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" GIT_CEILING_DIRECTORIES="$TMP_ROOT" \
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
for r in byte-budget-overflow not-committed-pr-create; do
  probe_rows -- "$C" "$(row "$(marker cron completed 0 "[\"$r\"]")" "$D1")"
  expect_rc "P-5 ($r)" 0 "$PROBE_RC"
  if [[ "$(out_of)" == "PASS" ]]; then pass "P-5 ($r): stdout is exactly PASS"; else fail "P-5 ($r): stdout '$(out_of)'"; fi
done

echo "P-5b. a refusal only a DEFECTIVE derivation can cause is class F -> exit 1, never 0 (CTO ruling)"
for r in diff-path-off-target corpus-shrink-refused agents-core-hr-rule-edit-refused; do
  probe_rows -- "$C" "$(row "$(marker cron completed 0 "[\"$r\"]")" "$D1")"
  expect_rc "P-5b ($r)" 1 "$PROBE_RC"
  if [[ "$(out_of)" != "PASS" ]]; then pass "P-5b ($r): stdout is not PASS"; else fail "P-5b ($r): printed PASS"; fi
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
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" GIT_CEILING_DIRECTORIES="$TMP_ROOT" \
        BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        bash "$PROBE_REL" >/dev/null 2>"$d/err"; echo $? )
expect_rc "P-7 (floor unset, not a repository: no default)" 3 "$rc"
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
assert_fixture_dir "$d"
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
        BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=sentinel-secret \
        FT10552_DEPLOY_FLOOR="$FLOOR_ISO" bash -x "$PROBE_REL" >"$d/out" 2>"$d/err"; echo $? )
expect_rc "P-7 (xtrace refusal)" 78 "$rc"
if grep -q 'sentinel-secret' "$d/err" "$d/out"; then fail "P-7: the credential leaked under xtrace"; else pass "P-7: the credential is not echoed under xtrace"; fi
probe_rows STUB_EXIT7=1 -- "$C"
expect_rc "P-7 (query helper transient failure is NOT YET, not a verdict)" 2 "$PROBE_RC"
# Hygiene on the OTHER failure path: hostile helper stderr (ANSI, newline-led forged verdict) at rc 7.
probe_rows STUB_EXIT7=1 "STUB_MSG=$(printf '\033[31mFORGED\nINJECTED: all clear')" -- "$C"
expect_rc "P-7 (hostile helper stderr at rc 7 is still NOT YET)" 2 "$PROBE_RC"
if grep -q -P '\x1b' "$PROBE_DIR/err" "$PROBE_DIR/out"; then fail "P-7: an ESC byte from the helper reached the output"; else pass "P-7: no ESC byte from the helper in the output"; fi
if grep -q '^INJECTED' "$PROBE_DIR/err" "$PROBE_DIR/out"; then fail "P-7: a newline-led forged line reached the output"; else pass "P-7: no forged line reached the output"; fi
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
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["byte-budget-overflow"]')" "$D1")" \
  "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D3")"
expect_rc "H-3 P then quiet" 0 "$PROBE_RC"
probe_rows -- "$C" "$(row "$(marker cron no-qualifying-clusters 0 '[]')" "$D1")" \
  "$(row "$(marker cron completed 0 '["byte-budget-overflow"]')" "$D3")"
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

# --- derived-floor rows -----------------------------------------------------------
# Hermetic git for the fixtures: env -i scrubs every GIT_* name (so a surrounding hook or
# worktree cannot redirect the repo), system/global config are off, identity and both
# dates are fixed. $1 is the git date ("<epoch> <tz>").
FXHOME="$TMP_ROOT/fxhome"; mkdir -p "$FXHOME"
fx_git() { # fx_git <date> <dir> <git args...>
  local at="$1" d="$2"; shift 2
  env -i HOME="$FXHOME" PATH="$PATH" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CEILING_DIRECTORIES="$TMP_ROOT" \
    GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@invalid GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@invalid \
    GIT_AUTHOR_DATE="${FX_AUTHOR_AT:-$at}" GIT_COMMITTER_DATE="$at" \
    git -C "$d" -c init.defaultBranch=main -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
# mk_repo <dir> <epoch> [tz]: <dir> becomes a repo whose single commit ADDS the probe path
# (a copy of the shipped probe unless the sandbox already holds one) at <epoch>.
mk_repo() {
  local d="$1" at="$2 ${3:-+0000}"
  assert_fixture_dir "$d"
  mkdir -p "$d/$(dirname "$PROBE_REL")"
  [[ -f "$d/$PROBE_REL" ]] || cp "$PROBE_SRC" "$d/$PROBE_REL"
  fx_git "$at" "$d" init -q >/dev/null
  fx_git "$at" "$d" add -- "$PROBE_REL" >/dev/null
  fx_git "$at" "$d" commit -q -m "add probe" >/dev/null
}
# Probe under the SWEEPER's env: env -i, PATH and the three credential names, nothing else
# (no HOME, no TMPDIR, no floor, no repo-dir seam).
run_bare() { # run_bare <dir> [env...] -> rc; out/err in <dir>
  local dir="$1"; shift
  assert_fixture_dir "$dir"
  ( cd "$dir" && env -i PATH="$PATH" \
      BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p "$@" \
      bash "$PROBE_REL" >"$dir/out" 2>"$dir/err" )
  echo $?
}
# A PATH-shimmed `date` that freezes ONLY the probe's `date -u +%s` (its "now") and
# delegates everything else, so boundary rows are exact rather than racing the wall clock.
add_date_shim() { # add_date_shim <dir> <now-epoch>
  mkdir -p "$1/bin"
  printf '#!/usr/bin/env bash\nif [ "$#" -eq 2 ] && [ "$1" = "-u" ] && [ "$2" = "+%%s" ]; then echo %s; exit 0; fi\nexec %s "$@"\n' \
    "$2" "$(command -v date)" > "$1/bin/date"
  chmod +x "$1/bin/date"
}
# add_git_shim <dir> <date|fail>: `git log` prints $FAKE_GIT_DATE (date) or fails (fail);
# every other git command is delegated.
add_git_shim() {
  mkdir -p "$1/bin"
  local body='echo "$FAKE_GIT_DATE"; exit 0'
  [[ "$2" == fail ]] && body='exit 1'
  printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = log ] && { %s; }; done\nexec %s "$@"\n' \
    "$body" "$(command -v git)" > "$1/bin/git"
  chmod +x "$1/bin/git"
}
win_for() { echo "$(( ($1 - $2) / 86400 + 2 ))d"; }   # win_for <now> <floor>
# argv_is <dir> <window> <outcome-limit>: the recorded query calls are exactly the two the
# probe must make.
argv_is() {
  local want
  want="--since $2 --grep SOLEUR_CLAUDE_COST --limit 5"$'\n'"--since $2 --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit $3"
  [[ "$(cat "$1/argv.log" 2>/dev/null)" == "$want" ]]
}

PROOF_ROW() { row "$(marker cron completed 0 '["byte-budget-overflow"]')" "$1"; }
F_ROW() { row "$(marker cron completed 0 '["diff-underivable-apply"]')" "$1"; }
FLOOR_DERIVED_S=$((FLOOR_S + 10800))           # commit time + the 3h deploy-lag allowance
FLOOR_DERIVED_ISO="$(floor_iso "$FLOOR_DERIVED_S")"

# Scenarios (shared by the assertion rows and the mutation rows). Each takes the probe to
# run and leaves its rc in SC_RC and its sandbox in SC_DIR.
sc_derive() { # sweeper env, repo sandbox whose adding commit is 10 days old, one proof row
  SC_DIR=$(make_sandbox "$(fx "$C" "$(PROOF_ROW "$D2")")" "$1"); mk_repo "$SC_DIR" "$FLOOR_S"
  SC_RC=$(run_bare "$SC_DIR")
}
sc_lag() { # sc_lag <probe> <hours-after-commit>: one class-F row at that offset
  SC_DIR=$(make_sandbox "$(fx "$C" "$(F_ROW "$(dt_at "$FLOOR_S" "$2")")")" "$1"); mk_repo "$SC_DIR" "$FLOOR_S"
  SC_RC=$(run_bare "$SC_DIR")
}
sc_oldest() { # two ADDING commits (the file is removed and re-added 5 days later)
  SC_DIR=$(make_sandbox "$(fx "$C" "$(F_ROW "$(dt_at "$FLOOR_S" 4)")")" "$1"); mk_repo "$SC_DIR" "$FLOOR_S"
  assert_fixture_dir "$SC_DIR"
  cp "$SC_DIR/$PROBE_REL" "$SC_DIR/probe.keep"   # the probe under test (a mutant in M-7), restored below
  fx_git "$((FLOOR_S + 86400)) +0000" "$SC_DIR" rm -q -- "$PROBE_REL" >/dev/null
  fx_git "$((FLOOR_S + 86400)) +0000" "$SC_DIR" commit -q -m "remove probe" >/dev/null
  mkdir -p "$SC_DIR/$(dirname "$PROBE_REL")"   # git rm pruned the emptied directory
  assert_fixture_dir "$SC_DIR"
  cp "$SC_DIR/probe.keep" "$SC_DIR/$PROBE_REL"
  fx_git "$((FLOOR_S + 5 * 86400)) +0000" "$SC_DIR" add -- "$PROBE_REL" >/dev/null
  fx_git "$((FLOOR_S + 5 * 86400)) +0000" "$SC_DIR" commit -q -m "re-add probe" >/dev/null
  SC_RC=$(run_bare "$SC_DIR")
}
sc_argv() { # sc_argv <probe> [env...]: frozen clock = NOW_S; derived floor = FLOOR_S + 3h
  local probe="$1"; shift
  SC_DIR=$(make_sandbox "$(fx "$C" "$(PROOF_ROW "$D2")")" "$probe"); mk_repo "$SC_DIR" "$FLOOR_S"
  add_date_shim "$SC_DIR" "$NOW_S"
  SC_RC=$(run_bare "$SC_DIR" PATH="$SC_DIR/bin:$PATH" "$@")
}
# The boundary pair: adding commit E_C; clock frozen at derived floor + <offset> seconds.
E_C=$((NOW_S - 60 * 86400)); E_F=$((E_C + 10800))
sc_boundary() { # sc_boundary <probe> <seconds-after-derived-floor>
  local ed; ed="$(dt_at "$E_F" 24)"
  SC_DIR=$(make_sandbox "$(fx "$(row "$CONTROL" "$ed")" "$(row "$(marker cron completed 0 '["edit-invalid"]')" "$ed")")" "$1"); mk_repo "$SC_DIR" "$E_C"
  add_date_shim "$SC_DIR" "$((E_F + $2))"
  SC_RC=$(run_bare "$SC_DIR" PATH="$SC_DIR/bin:$PATH")
}
HOSTILE=$'\x1b[31mRAW-HELPER-LEAK-d41d8\x1b[0m\nINJECTED: all clear'
sc_hygiene() {
  SC_DIR=$(make_sandbox "$(fx "$C" "$(PROOF_ROW "$D2")")" "$1")
  SC_RC=$(run_probe "$SC_DIR" STUB_EXIT3=1 "STUB_MSG=$HOSTILE")
}

echo "F-1. sweeper env (env -i, PATH + the three BETTERSTACK_QUERY names only): the floor is DERIVED from git -> exit 0, never 3"
sc_derive "$PROBE_SRC"
expect_rc "F-1" 0 "$SC_RC"
if [[ "$(cat "$SC_DIR/out")" == "PASS" ]]; then pass "F-1: stdout is exactly PASS"; else fail "F-1: stdout '$(cat "$SC_DIR/out")'"; fi
if grep -q -F -- "since $FLOOR_DERIVED_ISO" "$SC_DIR/err"; then pass "F-1: the derived floor is commit time + 3h ($FLOOR_DERIVED_ISO)"; else fail "F-1: derived floor not reported: $(cat "$SC_DIR/err")"; fi

echo "F-2. the 3h deploy-lag allowance: an old-code run inside the lag is not graded, one after it is"
sc_lag "$PROBE_SRC" 2
expect_rc "F-2 (class-F row 2h after the adding commit: inside the lag, ungraded)" 2 "$SC_RC"
sc_lag "$PROBE_SRC" 4
expect_rc "F-2 (class-F row 4h after the adding commit: graded)" 1 "$SC_RC"

echo "F-3. a non-UTC committer offset is the same instant"
SC_DIR=$(make_sandbox "$(fx "$C" "$(PROOF_ROW "$D2")")"); mk_repo "$SC_DIR" "$FLOOR_S" +0530
SC_RC=$(run_bare "$SC_DIR")
expect_rc "F-3 (+0530)" 0 "$SC_RC"
if grep -q -F -- "since $FLOOR_DERIVED_ISO" "$SC_DIR/err"; then pass "F-3: same derived floor as UTC"; else fail "F-3: floor differs: $(cat "$SC_DIR/err")"; fi

echo "F-6. the floor reads the COMMITTER date, not the author date (a rebase-merge keeps an older author date)"
SC_DIR=$(make_sandbox "$(fx "$C" "$(F_ROW "$(dt_at "$FLOOR_S" 2)")")"); FX_AUTHOR_AT="$((FLOOR_S - 2592000)) +0000" mk_repo "$SC_DIR" "$FLOOR_S"
SC_RC=$(run_bare "$SC_DIR")
expect_rc "F-6 (author date 30d older; a row 2h after the committer date is inside the lag, ungraded)" 2 "$SC_RC"

echo "F-4. the OLDEST adding commit is the floor (the file was removed and re-added later)"
sc_oldest "$PROBE_SRC"
expect_rc "F-4" 1 "$SC_RC"

echo "F-5. FT10552_DEPLOY_FLOOR stays an OVERRIDE, used verbatim (no lag, no git)"
SC_DIR=$(make_sandbox "$(fx "$C" "$(F_ROW "$(dt_at "$FLOOR_S" 24)")")"); mk_repo "$SC_DIR" "$FLOOR_S"
SC_RC=$(run_bare "$SC_DIR" "FT10552_DEPLOY_FLOOR=$(floor_iso $((FLOOR_S + 2 * 86400)))")
expect_rc "F-5 (override later than every row: nothing graded)" 2 "$SC_RC"
SC_RC=$(run_bare "$SC_DIR" "FT10552_DEPLOY_FLOOR=$(floor_iso $((FLOOR_S + 3600)))")
expect_rc "F-5 (override 1h after the commit: no lag added, row graded)" 1 "$SC_RC"

echo "U-1. unresolvable floor -> exit 3 naming a closed-vocabulary cause, never 0 or 1"
unres() { # unres <label> <cause> <dir> [env...]
  local label="$1" cause="$2" d="$3" rc; shift 3
  rc=$(run_probe "$d" FT10552_DEPLOY_FLOOR= "$@")
  expect_rc "U-1 ($label)" 3 "$rc"
  if grep -q -F -- "($cause)" "$d/err"; then pass "U-1 ($label): names $cause"; else fail "U-1 ($label): cause '$cause' missing from: $(cat "$d/err")"; fi
  if [[ "$(cat "$d/out")" != "PASS" ]]; then pass "U-1 ($label): stdout is not PASS"; else fail "U-1 ($label): PASS on an unresolvable floor"; fi
}
BASE_FX="$(fx "$C" "$(PROOF_ROW "$D2")")"
mkdir -p "$TMP_ROOT/nonrepo"
d=$(make_sandbox "$BASE_FX"); unres "not a repository" not-a-repository "$d" "FT10552_REPO_DIR=$TMP_ROOT/nonrepo"
d=$(make_sandbox "$BASE_FX"); unres "repo dir does not exist" not-a-repository "$d" "FT10552_REPO_DIR=$TMP_ROOT/no-such-dir"
# A repo that never contained the probe path.
mkdir -p "$TMP_ROOT/norecord"; echo x > "$TMP_ROOT/norecord/README"
fx_git "$FLOOR_S +0000" "$TMP_ROOT/norecord" init -q >/dev/null
fx_git "$FLOOR_S +0000" "$TMP_ROOT/norecord" add -- README >/dev/null
fx_git "$FLOOR_S +0000" "$TMP_ROOT/norecord" commit -q -m unrelated >/dev/null
d=$(make_sandbox "$BASE_FX"); unres "history lacks the adding commit" adding-commit-not-in-history "$d" "FT10552_REPO_DIR=$TMP_ROOT/norecord"
# A SHALLOW clone: the boundary commit looks like it added every file, so it must be refused.
mk_repo "$TMP_ROOT/origin" "$FLOOR_S"
echo more > "$TMP_ROOT/origin/README"
fx_git "$((FLOOR_S + 86400)) +0000" "$TMP_ROOT/origin" add -- README >/dev/null
fx_git "$((FLOOR_S + 86400)) +0000" "$TMP_ROOT/origin" commit -q -m later >/dev/null
fx_git "$FLOOR_S +0000" "$TMP_ROOT" clone -q --depth 1 "file://$TMP_ROOT/origin" "$TMP_ROOT/shallow" >/dev/null 2>&1
if [[ "$(fx_git "$FLOOR_S +0000" "$TMP_ROOT/shallow" rev-parse --is-shallow-repository)" == "true" ]]; then pass "U-1: the shallow fixture is shallow"; else fail "U-1: shallow fixture is not shallow"; fi
d=$(make_sandbox "$BASE_FX"); unres "shallow history" shallow-history "$d" "FT10552_REPO_DIR=$TMP_ROOT/shallow"
# Unparsable adding-commit dates (a git shim prints them) and a failing git log.
mk_repo "$TMP_ROOT/shimrepo" "$FLOOR_S"
for bad in not-a-date "2026-13-45T99:99:99+00:00"; do
  d=$(make_sandbox "$BASE_FX"); add_git_shim "$d" date
  unres "unparsable date '$bad'" date-unparsable "$d" "FT10552_REPO_DIR=$TMP_ROOT/shimrepo" "PATH=$d/bin:$PATH" "FAKE_GIT_DATE=$bad"
done
d=$(make_sandbox "$BASE_FX"); add_git_shim "$d" fail
unres "git log fails" git-log-failed "$d" "FT10552_REPO_DIR=$TMP_ROOT/shimrepo" "PATH=$d/bin:$PATH"
# git unavailable: a PATH that has the probe's tools but no git.
TOOLBIN="$TMP_ROOT/toolbin"; mkdir -p "$TOOLBIN"
for t in bash dirname date mktemp rm head tail tr grep sort awk cat jq; do ln -sf "$(command -v "$t")" "$TOOLBIN/$t"; done
d=$(make_sandbox "$BASE_FX"); unres "git unavailable" git-unavailable "$d" "PATH=$TOOLBIN"
# The unset-floor default (the script directory, a sandbox that is no repository) is also exit 3.
d=$(make_sandbox "$BASE_FX"); unres "default repo dir is not a repository" not-a-repository "$d"

echo "Q-1. the query helper's argv: the --since window and both --limit values are pinned"
sc_argv "$PROBE_SRC"
expect_rc "Q-1" 0 "$SC_RC"
want_win="$(win_for "$NOW_S" "$FLOOR_DERIVED_S")"
if argv_is "$SC_DIR" "$want_win" 200; then pass "Q-1: --since $want_win, control --limit 5, outcome --limit 200"; else fail "Q-1: argv was: $(cat "$SC_DIR/argv.log")"; fi
sc_argv "$PROBE_SRC" FT10552_LIMIT=77
if argv_is "$SC_DIR" "$want_win" 77; then pass "Q-1: FT10552_LIMIT reaches the outcome query only"; else fail "Q-1 (limit 77): argv was: $(cat "$SC_DIR/argv.log")"; fi

echo "B-1. the 35-day boundary (clock frozen, derived floor): 34d23h -> NOT YET (2), exactly 35d -> ACTION REQUIRED (5)"
sc_boundary "$PROBE_SRC" $((35 * 86400 - 3600))
expect_rc "B-1 (floor + 34d23h)" 2 "$SC_RC"
if grep -q 'NOT YET' "$SC_DIR/err" && ! grep -q 'ACTION REQUIRED' "$SC_DIR/err"; then pass "B-1: 34d23h says NOT YET"; else fail "B-1: 34d23h message: $(cat "$SC_DIR/err")"; fi
sc_boundary "$PROBE_SRC" $((35 * 86400))
expect_rc "B-1 (floor + exactly 35d)" 5 "$SC_RC"
if grep -q 'ACTION REQUIRED' "$SC_DIR/err"; then pass "B-1: 35d says ACTION REQUIRED"; else fail "B-1: 35d message: $(cat "$SC_DIR/err")"; fi
if argv_is "$SC_DIR" "37d" 200; then pass "B-1: the window follows the frozen clock (37d)"; else fail "B-1: argv was: $(cat "$SC_DIR/argv.log")"; fi

echo "X-1. a MIXED run (class-P and class-F reasons in ONE run) -> exit 0 with the F reasons in the stderr NOTE; class P outranks class F"
probe_rows -- "$C" "$(row "$(marker cron completed 0 '["byte-budget-overflow","git-apply-check-failed"]')" "$D1")"
expect_rc "X-1 (P reason + F reason)" 0 "$PROBE_RC"
if [[ "$(out_of)" == "PASS" ]]; then pass "X-1: stdout is exactly PASS"; else fail "X-1: stdout '$(out_of)'"; fi
if grep -q 'NOTE:.*git-apply-check-failed' "$PROBE_DIR/err"; then pass "X-1: the F reason is in the NOTE"; else fail "X-1: NOTE missing the F reason: $(err_of)"; fi
probe_rows -- "$C" "$(row "$(marker cron completed 1 '["diff-underivable-apply"]')" "$D1")"
expect_rc "X-1 (PR opened + F reason in the same run)" 0 "$PROBE_RC"
if grep -q 'NOTE:.*diff-underivable-apply' "$PROBE_DIR/err"; then pass "X-1: the F reason is in the NOTE (opened run)"; else fail "X-1: NOTE missing: $(err_of)"; fi
probe_rows -- "$C" "$(row "$(marker cron completed 1 '[]')" "$D1")"
if ! grep -q 'NOTE:' "$PROBE_DIR/err"; then pass "X-1: no NOTE without a class-F reason"; else fail "X-1: spurious NOTE: $(err_of)"; fi

echo "Y-1. hygiene: the query helper's raw stderr (ANSI, newlines) never reaches the output on the rc-3 path"
sc_hygiene "$PROBE_SRC"
expect_rc "Y-1" 3 "$SC_RC"
if grep -q 'CANNOT ESTABLISH: betterstack-query.sh exited 3' "$SC_DIR/err"; then pass "Y-1: a closed-vocabulary classification is printed"; else fail "Y-1: no classification: $(cat "$SC_DIR/err")"; fi
if grep -q -P '\x1b' "$SC_DIR/err" "$SC_DIR/out"; then fail "Y-1: an ESC byte reached the output"; else pass "Y-1: no ESC byte in the output"; fi
if grep -q 'RAW-HELPER-LEAK\|INJECTED' "$SC_DIR/err" "$SC_DIR/out"; then fail "Y-1: raw helper text reached the output"; else pass "Y-1: nothing raw from the helper was echoed"; fi
if [[ "$(grep -c . "$SC_DIR/err")" == 1 ]]; then pass "Y-1: the message is a single line"; else fail "Y-1: multi-line message: $(cat "$SC_DIR/err")"; fi

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

# --- mutation arms for the floor / argv / boundary / hygiene guards ------------------
# Each healthy predicate returns 0 only when EVERY expectation of its scenario holds, so a
# mutant is "caught" exactly when the predicate turns false. The unmutated control runs
# first and must be healthy, and the mutation must have landed (single anchor, file differs).
h_derive() { sc_derive "$1"; [[ "$SC_RC" == 0 && "$(cat "$SC_DIR/out")" == "PASS" ]]; }
h_lag() { sc_lag "$1" 2; [[ "$SC_RC" == 2 ]]; }
h_oldest() { sc_oldest "$1"; [[ "$SC_RC" == 1 ]]; }
h_argv() { sc_argv "$1"; [[ "$SC_RC" == 0 ]] && argv_is "$SC_DIR" "$(win_for "$NOW_S" "$FLOOR_DERIVED_S")" 200; }
h_exact35() { sc_boundary "$1" $((35 * 86400)); [[ "$SC_RC" == 5 ]]; }
h_not_yet34() { sc_boundary "$1" $((35 * 86400 - 3600)); [[ "$SC_RC" == 2 ]]; }
h_hygiene() { sc_hygiene "$1"; [[ "$SC_RC" == 3 ]] && ! grep -q 'RAW-HELPER-LEAK\|INJECTED' "$SC_DIR/err"; }

mut_row() { # mut_row <id> <description> <old> <new> <healthy-predicate>
  local id="$1" desc="$2" m
  echo "$id. MUTATION: $desc"
  m="$(mutate "$id" "$3" "$4")"
  if [[ -z "$m" ]]; then fail "$id did not land (anchor drifted or not unique)"; return; fi
  if "$5" "$PROBE_SRC"; then pass "$id: the unmutated control is green"; else fail "$id: the unmutated control is NOT green - the row proves nothing"; return; fi
  if "$5" "$m"; then fail "$id: the mutant SURVIVED - no row pins this guard"; else pass "$id: the mutant is caught"; fi
}
# shellcheck disable=SC2016  # the anchors are literal probe source text, never expanded
{
mut_row M-5 "derivation removed -> the sweeper-env run must stop being exit 0" \
  $'  derive_deploy_floor\nfi' $'  no_floor mutant "derivation removed."\nfi' h_derive
mut_row M-6 "deploy-lag allowance dropped (3h -> 0) -> a run inside the lag gets graded" \
  'DEPLOY_LAG_S=10800' 'DEPLOY_LAG_S=0' h_lag
mut_row M-7 "newest adding commit instead of the oldest" \
  '| tail -n 1)"' '| head -n 1)"' h_oldest
mut_row M-8 "--since window slack +2d -> +3d" \
  '/ 86400 + 2 ))d"' '/ 86400 + 3 ))d"' h_argv
mut_row M-9 "control query --limit 5 -> 6" \
  'run_query control SOLEUR_CLAUDE_COST 5' 'run_query control SOLEUR_CLAUDE_COST 6' h_argv
mut_row M-10 "outcome query default --limit 200 -> 201" \
  'LIMIT="${FT10552_LIMIT:-200}"' 'LIMIT="${FT10552_LIMIT:-201}"' h_argv
mut_row M-11 "escalation comparison >= -> > (exactly 35d stops being exit 5)" \
  'if (( age_s >= ESCALATE_AFTER_DAYS * 86400 )); then' 'if (( age_s > ESCALATE_AFTER_DAYS * 86400 )); then' h_exact35
mut_row M-12 "escalation budget 35 -> 34 days (34d23h stops being NOT YET)" \
  'ESCALATE_AFTER_DAYS=35' 'ESCALATE_AFTER_DAYS=34' h_not_yet34
mut_row M-13 "rc-3 path echoes the helper's raw output again" \
  $'exited 3 (%s): the query never ran (credentials not injected into the helper).\\n\' "$label" >&2' \
  $'exited 3 (%s): %s\\n\' "$label" "$(head -c 400 "$QOUT")" >&2' h_hygiene
}


# --- verdict: floor + conservation reported DIRECTLY, never via pass()/fail() --
MIN_CASES=175
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
