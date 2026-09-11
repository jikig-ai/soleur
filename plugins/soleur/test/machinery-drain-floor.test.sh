#!/usr/bin/env bash
# machinery-drain-floor.test.sh
#
# The closing floor is what makes the gate net-NEGATIVE instead of net-zero, so
# it must exist as ONE named constant that both the runner and this test read.
# This test DERIVES the value from the workflow rather than restating it: a
# second copy would be a second pin on one fact, which is the drift class the
# change this guards exists to remove.
#
# It also pins the WAIVER arm, because a floor without a candidate-supply waiver
# is unsatisfiable-by-construction once the backlog is actually drained -- a
# monitor whose steady state on success is RED, which trains the operator to
# ignore it.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$ROOT/.github/workflows/scheduled-machinery-drain.yml"
SKILL="$ROOT/plugins/soleur/skills/drain-labeled-backlog/SKILL.md"

PASS=0; FAIL=0; ASSERTED=0
pass() { PASS=$((PASS + 1)); echo "[ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
# ASSERTED is incremented at the CALL SITE, never inside a verdict helper, so a
# rewritten helper cannot keep the count moving while losing the verdict.
ck() { ASSERTED=$((ASSERTED + 1)); if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (want '$3', got '$2')"; fi; }
ckc() { ASSERTED=$((ASSERTED + 1)); if grep -qE -- "$2" "$3"; then pass "$1"; else fail "$1"; fi; }

[[ -r "$WF" ]]    || { printf 'FATAL: workflow unreadable at %s\n' "$WF" >&2; exit 2; }
[[ -r "$SKILL" ]] || { printf 'FATAL: skill unreadable at %s\n' "$SKILL" >&2; exit 2; }

# --- derive the constant, and refuse if the derivation itself failed ---
FLOOR="$(awk '/^env:/{e=1;next} e && /MACHINERY_DRAIN_CLOSING_FLOOR:/{gsub(/[^0-9]/,"");print;exit}' "$WF")"
if [[ ! "$FLOOR" =~ ^[0-9]+$ ]]; then
  printf 'FATAL: could not derive MACHINERY_DRAIN_CLOSING_FLOOR from %s (got %q).\n' "$WF" "${FLOOR:-<empty>}" >&2
  printf 'An empty derivation is not a clean run -- every assertion below would\n' >&2
  printf 'compare against nothing and pass vacuously.\n' >&2
  exit 2
fi
echo "derived MACHINERY_DRAIN_CLOSING_FLOOR=$FLOOR"

ck "the floor is the operator-approved value" "$FLOOR" "20"

# The skill prose must name the SAME number. Derived on both sides, so a change
# to the workflow that forgets the prose fails here rather than drifting.
SKILL_FLOOR="$(grep -oE 'closing floor of \*?\*?[0-9]+' "$SKILL" | grep -oE '[0-9]+' | head -1)"
ck "SKILL.md names the derived floor, not a restated literal" "$SKILL_FLOOR" "$FLOOR"

# --- the runner must actually READ the constant and carry BOTH arms ---
ckc "the workflow reads the constant into the enforcing step" \
  'FLOOR: \$\{\{ env\.MACHINERY_DRAIN_CLOSING_FLOOR \}\}' "$WF"
ckc "the enforcing step fails below the floor" \
  'verdict="BREACH: closed=\$closed, below the floor' "$WF"
ckc "the waiver arm exists and is gated on candidate supply" \
  'elif \[ "\$BEFORE" -lt "\$FLOOR" \]; then' "$WF"
ckc "the waiver is REPORTED, never silent" \
  'WAIVED-SUPPLY' "$WF"
ckc "closed is DERIVED as a delta, not self-reported by the agent" \
  'closed=\$\(\( BEFORE - after \)\)' "$WF"
ckc "a drain step actually exists (the workflow is named for it)" \
  'anthropics/claude-code-action' "$WF"

# --- the drain step must run in pipeline mode -------------------------------
# Without `--headless` the skill takes its interactive branch and waits to
# confirm a cluster with a human who is not there, so the step burns its budget
# and closes nothing while `continue-on-error` keeps the job green.
ckc "the drain prompt runs the skill in headless/pipeline mode" \
  "drain-labeled-backlog --label meta/machinery --headless" "$WF"

# --- an empty pool must not read as a drained one ---------------------------
# `pool < floor` has two causes that look identical in a green run: the ledger
# really was drained, or it was never populated (the backfill is propose-only,
# so the pool is 0 on merge and stays 0 until labels are applied). Reporting
# both the same way is the empty-telemetry-is-not-absence shape this change
# exists to remove, reproduced inside its own instrument.
ckc "a zero pool is reported as its own verdict, not as a supply waiver" \
  'WAIVED-EMPTY' "$WF"
ckc "the zero-pool verdict says it is NOT evidence of a drained backlog" \
  'NOT evidence of a drained backlog' "$WF"

# --- the standing measurement issue must never count itself ------------------
# The standing issue is created with `meta/machinery` (it IS machinery) and is
# therefore a drain candidate. It carries the `keep-open` kill-switch, and BOTH
# pool queries exclude that label -- otherwise the instrument sits in its own
# pool forever and reads as one undrained candidate every Monday.
KEEP_OPEN_POOL_QUERIES="$(grep -cE 'is:open\+label:%22meta/machinery%22\+-label:keep-open' "$WF")"
ck "both pool queries (pre-drain and post-drain) carry -label:keep-open" \
  "$([[ "$KEEP_OPEN_POOL_QUERIES" -ge 2 ]] && echo 'ge2' || echo "$KEEP_OPEN_POOL_QUERIES")" "ge2"

# --- the verdict must reach a DURABLE surface, not just the step log --------
ckc "the floor step publishes its verdict as an output" \
  'verdict<<SOLEUR_EOF_VERDICT' "$WF"
ckc "the standing issue carries the drain verdict" \
  'VERDICT: \$\{\{ steps\.floor\.outputs\.verdict \}\}' "$WF"
ckc "a skipped floor step reads as UNKNOWN, not as clean" \
  'UNKNOWN, not clean' "$WF"

# --- anti-vacuity: report DIRECTLY, never through the helpers being backstopped ---
MIN_ASSERTIONS=$((14 + 1))  # 14 pre-existing + 1 keep-open pool-query row
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FLOOR: only %s assertions ran, expected at least %s.\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [[ $((PASS + FAIL)) -ne "$ASSERTED" ]]; then
  printf 'ACCOUNTING: pass(%s) + fail(%s) != asserted(%s) -- a verdict was lost.\n' "$PASS" "$FAIL" "$ASSERTED" >&2
  exit 1
fi

echo "Total: $((PASS + FAIL)) passed=$PASS failed=$FAIL asserted=$ASSERTED"
[[ "$FAIL" -eq 0 ]] || exit 1
