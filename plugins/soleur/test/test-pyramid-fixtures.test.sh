#!/usr/bin/env bash
# Pin suite for the test-pyramid review mechanism (#9762).
#
# What this pins (plan Guard Contract, Guard 1):
#   - CENSUS: `plugins/soleur/test/fixtures/test-pyramid/*.diff` is a GLOB census
#     with a `== 2` count — a third fixture landing unclassified reds the suite.
#   - PARSE: each fixture parses as a unified diff ADDING one test file
#     (`+++ b/` header, `@@` hunk, `--- /dev/null`).
#   - ROLE: the e2e fixture still exercises the FAIL path (adds an e2e-layer
#     test carrying slow-cost signals and NO `pyramid-justified:` marker); the
#     unit fixture still exercises the PASS path (unit-layer, no e2e or
#     slow-cost signals).
#   - DRIFT: `test-design-reviewer.md` still defines the marker token and
#     layer/boundary vocabulary the fixtures and checklist key on.
#
# Chokepoint: every assertion flows through the helpers in test-helpers.sh.
# `cases` is the INDEPENDENT counter, incremented at every assertion CALL SITE
# and never inside a helper, so a neutered helper cannot keep the count moving
# while losing the verdict (ADR-193; issue-flow-measure.test.sh shape).
#
# Convention notes: pure sub-second greps only (#3531); NOT named
# `*.mutation.sh` (#7942); sources test-helpers.sh so the composed EXIT trap
# governs sandbox cleanup (#8659) — this suite allocates no sandbox of its own.

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

FIX_DIR="$REPO_ROOT/plugins/soleur/test/fixtures/test-pyramid"
AGENT="$REPO_ROOT/plugins/soleur/agents/engineering/review/test-design-reviewer.md"
E2E_FIX="$FIX_DIR/slow-e2e-no-justification.diff"
UNIT_FIX="$FIX_DIR/fast-unit.diff"

cases=0

echo "=== test-pyramid fixture pin suite ==="
echo ""

# ---------------------------------------------------------------------------
# INSTRUMENT SELF-TEST. Drive BOTH verdict directions once and require each to
# move its OWN counter before any real assertion runs. A helper neutered to
# always-pass leaves FAIL unmoved on the deliberate mismatch; a fail counter
# that cannot increment is caught the same way. Reported with printf + exit 1
# DIRECTLY, never through the helpers: a check enforced through the suspect
# cannot witness the suspect (ADR-193). Not counted in `cases`.
# ---------------------------------------------------------------------------
_p0=$PASS; _f0=$FAIL
assert_eq "instrument-mismatch-a" "instrument-mismatch-b" "instrument self-test: a failing assert_eq must increment FAIL" >/dev/null
assert_eq "instrument-match" "instrument-match" "instrument self-test: a passing assert_eq must increment PASS" >/dev/null
if [[ $((FAIL - _f0)) -ne 1 || $((PASS - _p0)) -ne 1 ]]; then
  printf '\n[FATAL] verdict helpers are neutered: FAIL moved %d (want 1), PASS moved %d (want 1).\n' \
    "$((FAIL - _f0))" "$((PASS - _p0))" >&2
  printf '  Every verdict this suite records is therefore unreliable; refusing to report a result.\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0

# grep -c prints 0 and exits 1 on no match; `|| true` keeps the count without
# tripping `set -e` inside the command substitution.
count() { grep -cE "$2" "$1" || true; }
# Presence check for tokens that legitimately appear more than once in the
# target (a definition plus its uses): prints 0 = found, 1 = absent. The
# `&& ||` list keeps a no-match grep from tripping `set -e` in the
# command substitution before the status can be printed.
has() { grep -qE "$2" "$1" && printf '0' || printf '1'; }

# ---------------------------------------------------------------------------
# CENSUS — glob count, not a name list.
# ---------------------------------------------------------------------------
shopt -s nullglob
fixtures=( "$FIX_DIR"/*.diff )
shopt -u nullglob
cases=$((cases + 1)); assert_eq "2" "${#fixtures[@]}" "fixture census: exactly 2 .diff files under fixtures/test-pyramid/"

cases=$((cases + 1)); assert_file_exists "$E2E_FIX" "slow-e2e fixture exists"
cases=$((cases + 1)); assert_file_exists "$UNIT_FIX" "fast-unit fixture exists"

# ---------------------------------------------------------------------------
# PARSE — each fixture is a unified diff ADDING exactly one test file.
# ---------------------------------------------------------------------------
for f in "$E2E_FIX" "$UNIT_FIX"; do
  cases=$((cases + 1)); assert_eq "1" "$(count "$f" '^\+\+\+ b/')" "$(basename "$f"): exactly one +++ b/ header"
  cases=$((cases + 1)); assert_eq "1" "$(count "$f" '^--- /dev/null$')" "$(basename "$f"): adds a new file (--- /dev/null)"
done
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^@@ ')" "e2e fixture: hunk present"
cases=$((cases + 1)); assert_eq "1" "$(count "$UNIT_FIX" '^@@ ')" "unit fixture: hunk present"

# ---------------------------------------------------------------------------
# ROLE — the e2e fixture exercises the FAIL path.
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^\+\+\+ b/apps/web-platform/e2e/checkout-flow\.e2e\.ts')" "e2e fixture: adds apps/web-platform/e2e/checkout-flow.e2e.ts"
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^\+.*@playwright/test')" "e2e fixture: @playwright/test import signal"
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" 'waitForTimeout')" "e2e fixture: slow-cost signal (waitForTimeout)"
cases=$((cases + 1)); assert_eq "0" "$(count "$E2E_FIX" 'pyramid-justified')" "e2e fixture: NO pyramid-justified marker (must exercise FAIL path)"
cases=$((cases + 1)); assert_eq "0" "$(count "$E2E_FIX" '## Test Pyramid')" "e2e fixture: NO PR-body justification block"

# ---------------------------------------------------------------------------
# ROLE — the unit fixture exercises the PASS path.
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_eq "1" "$(count "$UNIT_FIX" '^\+\+\+ b/apps/web-platform/test/order-total\.test\.ts')" "unit fixture: adds apps/web-platform/test/order-total.test.ts"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" 'playwright|cypress|puppeteer')" "unit fixture: no e2e-framework signal"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" 'waitForTimeout|sleep')" "unit fixture: no slow-cost signal"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" 'pyramid-justified')" "unit fixture: no justification marker needed or present"

# ---------------------------------------------------------------------------
# DRIFT PIN — the agent still defines the vocabulary the fixtures key on.
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_file_exists "$AGENT" "test-design-reviewer.md exists"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^## Pyramid & Fast-Feedback Check')" "agent: '## Pyramid & Fast-Feedback Check' section present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^### Pyramid')" "agent: '### Pyramid' verdict block present"
cases=$((cases + 1)); assert_eq "0" "$(has "$AGENT" 'pyramid-justified')" "agent: 'pyramid-justified' marker token defined"
cases=$((cases + 1)); assert_eq "0" "$(has "$AGENT" '## Test Pyramid')" "agent: '## Test Pyramid' PR-body marker defined"
cases=$((cases + 1)); assert_eq "0" "$(has "$AGENT" 'no measured runtime')" "agent: review-time boundary line present (measured budgets belong to local-speed work)"
cases=$((cases + 1)); assert_eq "0" "$(has "$AGENT" 'waitForTimeout')" "agent: cost-signal vocabulary (waitForTimeout) present"

# ---------------------------------------------------------------------------
# CONSERVATION: PASS+FAIL must equal cases. Reported DIRECTLY (printf + exit),
# never through the helpers — the helpers are what is being conserved.
# ---------------------------------------------------------------------------
if [[ $((PASS + FAIL)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: PASS+FAIL (%d) != cases (%d).\n' \
    "$((PASS + FAIL))" "$cases" >&2
  printf 'test-pyramid-fixtures.test.sh: %d FAILED (%d passed, %d cases)\n' "$FAIL" "$PASS" "$cases" >&2
  exit 1
fi

# ANTI-VACUITY FLOOR. Set AT the running count, never below it; reads `cases`,
# the counter no helper can move.
MIN_ASSERTIONS=25
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi

if [[ "$FAIL" -gt 0 ]]; then
  printf 'test-pyramid-fixtures.test.sh: %d failed (%d passed, %d assertions)\n' "$FAIL" "$PASS" "$cases" >&2
  exit 1
fi
printf 'test-pyramid-fixtures.test.sh: ALL PASS (%d assertions, %d failed)\n' "$cases" "$FAIL"
