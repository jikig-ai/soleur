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
  '::error::machinery drain closed .*below the floor' "$WF"
ckc "the waiver arm exists and is gated on candidate supply" \
  'if \[ "\$BEFORE" -lt "\$FLOOR" \]; then' "$WF"
ckc "the waiver is REPORTED, never silent" \
  'floor waived: pool < floor' "$WF"
ckc "closed is DERIVED as a delta, not self-reported by the agent" \
  'closed=\$\(\( BEFORE - after \)\)' "$WF"
ckc "a drain step actually exists (the workflow is named for it)" \
  'anthropics/claude-code-action' "$WF"

# --- anti-vacuity: report DIRECTLY, never through the helpers being backstopped ---
MIN_ASSERTIONS=8
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
