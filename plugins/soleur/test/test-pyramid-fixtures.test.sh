#!/usr/bin/env bash
# Pin suite for the test-pyramid review mechanism (#9762).
#
# What this pins (plan Guard Contract, Guard 1):
#   - CENSUS: `plugins/soleur/test/fixtures/test-pyramid/` holds EXACTLY the
#     fixture pair — glob census over ALL entries (not only `*.diff`), so a
#     third fixture landing unclassified under any name reds the suite.
#   - PARSE: each fixture parses as a unified diff ADDING one test file
#     (`+++ b/` header, `@@` hunk, `--- /dev/null`).
#   - ROLE: the e2e fixture still exercises the FAIL path (adds an e2e-layer
#     test carrying slow-cost signals and NO `pyramid-justified:` marker); the
#     unit fixture still exercises the PASS path (positive unit signals, no
#     e2e or slow-cost signals).
#   - DRIFT: `test-design-reviewer.md` still defines the marker token, the
#     layer/verdict vocabulary, and the FAIL rule the fixtures key on — and
#     the four restatement sites (review/SKILL.md, review.workflow.js,
#     plan-issue-templates.md, work/SKILL.md) still carry the contract.
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
REVIEW_SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"
REVIEW_WF="$REPO_ROOT/plugins/soleur/skills/review/workflows/review.workflow.js"
PLAN_TPL="$REPO_ROOT/plugins/soleur/skills/plan/references/plan-issue-templates.md"
WORK_SKILL="$REPO_ROOT/plugins/soleur/skills/work/SKILL.md"
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
# target (a definition plus its uses): prints 1 = found, 0 = absent — the same
# polarity as count() so adjacent assertions read consistently. The `&& ||`
# list keeps a no-match grep from tripping `set -e` in the substitution.
found() { grep -qE "$2" "$1" && printf '1' || printf '0'; }

# ---------------------------------------------------------------------------
# CENSUS — glob count over ALL entries AND over `*.diff`, not a name list.
# A fixture under a different extension, a dotfile, or a nested dir all count.
# ---------------------------------------------------------------------------
shopt -s nullglob
all_entries=( "$FIX_DIR"/* )
diff_entries=( "$FIX_DIR"/*.diff )
hidden_entries=( "$FIX_DIR"/.[!.]* "$FIX_DIR"/..?* )
shopt -u nullglob
cases=$((cases + 1)); assert_eq "2" "${#all_entries[@]}" "fixture census: exactly 2 entries under fixtures/test-pyramid/"
cases=$((cases + 1)); assert_eq "2" "${#diff_entries[@]}" "fixture census: exactly 2 .diff files under fixtures/test-pyramid/"
cases=$((cases + 1)); assert_eq "0" "${#hidden_entries[@]}" "fixture census: no hidden entries under fixtures/test-pyramid/"

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
# ROLE — the e2e fixture exercises the FAIL path. Positive signals are
# `^\+`-anchored: they must appear in ADDED code, not prose about the fixture.
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^\+\+\+ b/apps/web-platform/e2e/checkout-flow\.e2e\.ts')" "e2e fixture: adds apps/web-platform/e2e/checkout-flow.e2e.ts"
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^\+.*@playwright/test')" "e2e fixture: @playwright/test import signal"
cases=$((cases + 1)); assert_eq "1" "$(count "$E2E_FIX" '^\+.*waitForTimeout\(')" "e2e fixture: slow-cost signal (waitForTimeout call)"
cases=$((cases + 1)); assert_eq "0" "$(count "$E2E_FIX" 'pyramid-justified')" "e2e fixture: NO pyramid-justified marker (must exercise FAIL path)"
cases=$((cases + 1)); assert_eq "0" "$(count "$E2E_FIX" '## Test Pyramid')" "e2e fixture: NO PR-body justification block"

# ---------------------------------------------------------------------------
# ROLE — the unit fixture exercises the PASS path: positive unit signals AND
# absence of e2e/slow signals (both `^\+`-anchored, call-shaped where a call
# is what the checklist keys on).
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_eq "1" "$(count "$UNIT_FIX" '^\+\+\+ b/apps/web-platform/test/order-total\.test\.ts')" "unit fixture: adds apps/web-platform/test/order-total.test.ts"
cases=$((cases + 1)); assert_eq "1" "$(count "$UNIT_FIX" '^\+.*from "vitest"')" "unit fixture: vitest import present (positive unit signal)"
cases=$((cases + 1)); assert_eq "1" "$(found "$UNIT_FIX" '^\+.*(describe|test)\(')" "unit fixture: describe()/test() case present"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" '^\+.*(playwright|cypress|puppeteer|webdriverio|selenium)')" "unit fixture: no e2e-framework signal"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" '^\+.*(waitForTimeout|cy\.wait|browser\.pause|sleep)\s*\(')" "unit fixture: no slow-cost call"
cases=$((cases + 1)); assert_eq "0" "$(count "$UNIT_FIX" 'pyramid-justified')" "unit fixture: no justification marker needed or present"

# ---------------------------------------------------------------------------
# DRIFT PIN — the agent still defines the vocabulary the fixtures key on:
# section headings, marker token+definition shape, layer cells, the FAIL rule
# itself, and the review-time boundary line. Anchored where the token is
# structural; `found` presence where the token legitimately repeats.
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_file_exists "$AGENT" "test-design-reviewer.md exists"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^## Pyramid & Fast-Feedback Check')" "agent: '## Pyramid & Fast-Feedback Check' section present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^### Layer classification')" "agent: '### Layer classification' present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^### Justification marker')" "agent: '### Justification marker' present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^### Verdict rules')" "agent: '### Verdict rules' present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^### Pyramid')" "agent: '### Pyramid' verdict block present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '\| \*\*unit\*\*')" "agent: unit layer row present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '\| \*\*integration\*\*')" "agent: integration layer row present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '\| \*\*e2e\*\*')" "agent: e2e layer row present"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" 'pyramid-justified: <reason>')" "agent: 'pyramid-justified: <reason>' marker definition shape"
cases=$((cases + 1)); assert_eq "1" "$(count "$AGENT" '^\s*-\s*\*\*FAIL\*\* — the diff adds an e2e-layer test')" "agent: FAIL rule line present (verdict semantics, not just tokens)"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" '`## Test Pyramid`')" "agent: '## Test Pyramid' PR-body marker defined"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" 'no measured runtime')" "agent: review-time boundary line present (measured budgets belong to local-speed work)"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" 'gh pr view <N> --json body')" "agent: PR-body fetch instruction present (marker is checkable)"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" 'waitForTimeout')" "agent: cost-signal vocabulary (waitForTimeout) present"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" 'PASS \(justified\)')" "agent: 'PASS (justified)' verdict token present (exempted files stay visible)"
cases=$((cases + 1)); assert_eq "1" "$(found "$AGENT" 'no added test files')" "agent: no-added-files emission string present"

# ---------------------------------------------------------------------------
# DRIFT PIN — restatement sites still carry the contract (the three places a
# reader meets the rule without opening the agent body, plus the two
# instruction surfaces that warn authors upstream).
# ---------------------------------------------------------------------------
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_SKILL" 'pyramid-justified')" "review/SKILL.md: agent-13 text still names the marker"
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_SKILL" 'or `## Test Pyramid` PR-body block')" "review/SKILL.md: PR-body disjunct shape preserved in restatement"
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_SKILL" '\*\.e2e\*')" "review/SKILL.md: e2e conventions in the spawn trigger list"
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_WF" 'pyramid-justified')" "review.workflow.js: lens still names the marker"
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_WF" "'## Test Pyramid' PR-body block")" "review.workflow.js: PR-body disjunct shape preserved in lens"
cases=$((cases + 1)); assert_eq "1" "$(found "$REVIEW_WF" '\\.e2e')" "review.workflow.js: hasTests regex covers e2e conventions"
tpl_blocks="$(awk '/^## Test Scenarios/{inblock=1; blocks++} /^## / && !/^## Test Scenarios/{inblock=0} inblock && /pyramid-justified/{seen[blocks]=1} END{n=0; for(i=1;i<=blocks;i++) if(seen[i]) n++; print blocks":"n}' "$PLAN_TPL")"
cases=$((cases + 1)); assert_eq "3" "$(count "$PLAN_TPL" '^## Test Scenarios')" "plan-issue-templates.md: exactly 3 Test Scenarios blocks (a 4th unlabeled block reds)"
cases=$((cases + 1)); assert_eq "3:3" "$tpl_blocks" "plan-issue-templates.md: EVERY Test Scenarios block carries the marker line (per-block, not just count)"
cases=$((cases + 1)); assert_eq "1" "$(found "$WORK_SKILL" 'RED\(unit\|integration\|e2e\)')" "work/SKILL.md: RED-task layer naming present"
cases=$((cases + 1)); assert_eq "1" "$(found "$WORK_SKILL" 'pyramid-justified')" "work/SKILL.md: e2e marker warning present"

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
MIN_ASSERTIONS=49
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
