#!/usr/bin/env bash
# Fixture tests for the #8281 follow-through probe.
#
# The load-bearing arms are CONTAMINATION and DARKNESS. `betterstack-query.sh
# --grep` compiles to an unanchored `raw LIKE '%…%'` over the single source
# every host multiplexes into, and GitHub webhook payloads reach it — so the
# probe's first revision, which `grep -c`'d the marker name over undecoded rows,
# would have PASSed on an echo of THIS PR's own body and auto-closed #8281 with
# the scheduled path dark. Tests 5/5b assert the shipped probe does not; tests
# 9/10 MUTATE each guard out and require the corresponding fixture to flip, so
# neither arm is vacuous. Test 4 asserts a dark channel cannot read as a clean
# zero: no control rows ⇒ FAIL, never NOT YET.
set -uo pipefail

TMP_ROOT=$(mktemp -d -t ft8281root.XXXXXXXX) || {
  echo "FATAL: could not create scratch root" >&2; exit 1; }
: "${TMP_ROOT:?}"
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || {
  echo "FATAL: scratch root is not an absolute real directory: $TMP_ROOT" >&2; exit 1; }
readonly TMP_ROOT
export TMPDIR="$TMP_ROOT"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_SRC="$REPO_ROOT/scripts/followthroughs/compound-promote-outcome-8281.sh"
[[ -f "$PROBE_SRC" ]] || { echo "FATAL: probe not found at $PROBE_SRC" >&2; exit 1; }

passes=0; fails=0
# Append-only ledger: the verdict below reads THIS, not the counter, so a
# redirected counter increment cannot silence a real failure.
FAILURES=()
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; fails=$((fails + 1)); FAILURES+=("$1"); }

# --- sandbox: a stub query helper that simulates the server-side LIKE ---------
# The stub greps the fixture for the `--grep` pattern, exactly as the real
# helper's SQL does — so a row that merely QUOTES the marker is returned, and
# the probe's DECODE is what must reject it.
make_sandbox() { # make_sandbox <fixture-file> [probe]
  local fixture="$1" probe="${2:-$PROBE_SRC}" d
  d=$(mktemp -d -t ft8281.XXXXXXXX); : "${d:?}"
  mkdir -p "$d/scripts/followthroughs"
  cp "$probe" "$d/scripts/followthroughs/compound-promote-outcome-8281.sh"
  chmod +x "$d/scripts/followthroughs/compound-promote-outcome-8281.sh"
  cp "$fixture" "$d/rows.jsonl"
  cat > "$d/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
# Simulated betterstack-query.sh: honours --grep as a substring over raw rows
# (the real helper compiles it to `raw LIKE '%…%'`). Exit 3 when asked to.
pat=""
while [ $# -gt 0 ]; do case "$1" in --grep) pat="$2"; shift 2;; *) shift;; esac; done
[ -n "${STUB_EXIT3:-}" ] && { echo "You are NOT missing Better Stack access" >&2; exit 3; }
grep -F -- "$pat" "$(dirname "$0")/../rows.jsonl" || true
STUB
  chmod +x "$d/scripts/betterstack-query.sh"
  echo "$d"
}

# A row is {dt, raw}, where raw is a JSON STRING whose decoded object carries the
# pino payload under `.message` — the measured live shape (runbook §row shape).
row() { # row <inner-json> [dt]
  local inner="$1" dt="${2:-2026-09-20 00:05:00}"
  jq -c -n --arg dt "$dt" --arg raw "$(jq -c -n --argjson m "$inner" '{message:$m}')" '{dt:$dt, raw:$raw}'
}

run_probe() { # run_probe <dir> [env...]  → echoes rc
  local dir="$1"; shift
  ( cd "$dir" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" \
      BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
      FT8281_MERGE_FLOOR=2026-09-18T00:00:00Z "$@" \
      bash scripts/followthroughs/compound-promote-outcome-8281.sh >/dev/null 2>&1 )
  echo $?
}

CONTROL='{"SOLEUR_CLAUDE_COST":true,"component":"claude-cost","fn":"cron-x","cost_usd":1}'
SCHED='{"SOLEUR_COMPOUND_PROMOTE_OUTCOME":true,"fn":"cron-compound-promote","trigger":"cron","status":"completed","clusters_opened":0,"refusals":["diff-structural-op"]}'
MANUAL='{"SOLEUR_COMPOUND_PROMOTE_OUTCOME":true,"fn":"cron-compound-promote","trigger":"manual","status":"completed"}'
# A realistic webhook echo: the marker text appears ONLY as nested string
# content of a payload field. `fn` is the webhook producer, not the cron.
ECHO_ROW='{"fn":"github-webhook","msg":"issue opened","body":"the marker is SOLEUR_COMPOUND_PROMOTE_OUTCOME and it carries trigger=cron and status=completed"}'
# Adversarial: the marker KEY is present at top level but `fn` is wrong.
ECHO_ADVERSARIAL='{"SOLEUR_COMPOUND_PROMOTE_OUTCOME":true,"fn":"github-webhook","trigger":"cron","status":"completed"}'

fx() { f=$(mktemp -t ft.XXXXXXXX); printf '%s\n' "$@" > "$f"; echo "$f"; }

echo "1. scheduled marker + live control → PASS (0)"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$SCHED")")")
rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "rc=0"; else fail "expected 0, got $rc"; fi

echo "2. only a MANUAL marker + live control → NOT YET (2), never PASS"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$MANUAL")")")
rc=$(run_probe "$d"); if [[ "$rc" == 2 ]]; then pass "rc=2"; else fail "expected 2, got $rc"; fi

echo "3. zero markers + live control → NOT YET (2)"
d=$(make_sandbox "$(fx "$(row "$CONTROL")")")
rc=$(run_probe "$d"); if [[ "$rc" == 2 ]]; then pass "rc=2"; else fail "expected 2, got $rc"; fi

echo "4. DARK channel: marker present but NO control rows → FAIL (1), not a clean zero"
d=$(make_sandbox "$(fx "$(row "$SCHED")")")
rc=$(run_probe "$d"); if [[ "$rc" == 1 ]]; then pass "rc=1 (refused to grade through a dead instrument)"; else fail "expected 1, got $rc"; fi

echo "5. ECHO: a webhook body QUOTING the marker + control → NOT YET (2), never PASS"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$ECHO_ROW")")")
rc=$(run_probe "$d"); if [[ "$rc" == 2 ]]; then pass "rc=2"; else fail "expected 2, got $rc — an echo of the PR body closed the tracker"; fi

echo "5b. ECHO_ADVERSARIAL: marker key at top level, wrong fn → NOT YET (2)"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$ECHO_ADVERSARIAL")")")
rc=$(run_probe "$d"); if [[ "$rc" == 2 ]]; then pass "rc=2"; else fail "expected 2, got $rc"; fi

echo "6. missing credential → CANNOT ESTABLISH (3)"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$SCHED")")")
rc=$( cd "$d" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u \
       bash scripts/followthroughs/compound-promote-outcome-8281.sh >/dev/null 2>&1; echo $? )
if [[ "$rc" == 3 ]]; then pass "rc=3"; else fail "expected 3, got $rc"; fi

echo "7. query helper exits 3 (nothing was queried) → forwarded as 3, not folded into transient"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$SCHED")")")
rc=$(run_probe "$d" STUB_EXIT3=1); if [[ "$rc" == 3 ]]; then pass "rc=3"; else fail "expected 3, got $rc"; fi

echo "8. unparsable merge floor → CANNOT ESTABLISH (3)"
d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$SCHED")")")
rc=$(run_probe "$d" FT8281_MERGE_FLOOR=not-a-date); if [[ "$rc" == 3 ]]; then pass "rc=3"; else fail "expected 3, got $rc"; fi

# --- mutation arms: each guard must be LOAD-BEARING --------------------------
echo "9. MUTATION: drop the .fn field-isolation → ECHO_ADVERSARIAL must flip to PASS"
m=$(mktemp -t ft8281mut.XXXXXXXX)
sed 's/ and \.fn == "cron-compound-promote"//' "$PROBE_SRC" > "$m"
if cmp -s "$m" "$PROBE_SRC"; then fail "mutation 9 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$ECHO_ADVERSARIAL")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "guard is load-bearing (mutant PASSes on the echo)"; else fail "mutant did not flip (rc=$rc) — test 5b is not pinning the fn check"; fi
fi

echo "10. MUTATION: drop the trigger==cron requirement → MANUAL-only must flip to PASS"
m=$(mktemp -t ft8281mut.XXXXXXXX)
sed "s/grep '^cron\t'/grep ./" "$PROBE_SRC" > "$m"
if cmp -s "$m" "$PROBE_SRC"; then fail "mutation 10 did not land (anchor drifted)"; else
  d=$(make_sandbox "$(fx "$(row "$CONTROL")" "$(row "$MANUAL")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 0 ]]; then pass "guard is load-bearing (mutant PASSes on a manual fire)"; else fail "mutant did not flip (rc=$rc) — test 2 is not pinning the trigger check"; fi
fi

echo "11. MUTATION: drop the positive control → DARK channel must flip from FAIL to NOT YET"
m=$(mktemp -t ft8281mut.XXXXXXXX)
python3 - "$PROBE_SRC" "$m" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
a = 'if ! numeric "$ctl_n" || [ "$ctl_n" -eq 0 ]; then'
assert src.count(a) == 1
open(sys.argv[2], "w").write(src.replace(a, "if false; then", 1))
PYEOF
if cmp -s "$m" "$PROBE_SRC"; then fail "mutation 11 did not land"; else
  d=$(make_sandbox "$(fx "$(row "$MANUAL")")" "$m")
  rc=$(run_probe "$d"); if [[ "$rc" == 2 ]]; then pass "control is load-bearing (mutant reads a dark channel as still-soaking)"; else fail "mutant did not flip (rc=$rc)"; fi
fi

# --- verdict: floor + conservation reported DIRECTLY, never via pass()/fail() --
MIN_CASES=12
total=$((passes + fails))
if (( total < MIN_CASES )); then
  printf 'FATAL: only %d case(s) ran; floor is %d — the suite asserted nothing\n' "$total" "$MIN_CASES" >&2
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
