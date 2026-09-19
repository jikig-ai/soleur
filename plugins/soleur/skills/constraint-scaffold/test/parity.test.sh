#!/usr/bin/env bash
# Template <-> emission parity for the constraint-scaffold L1 gate (ADR-071).
#
# The dependency-cruiser config and the shared runner are emitted as
# BYTE-IDENTICAL copies of the skill's templates; the CI workflow is a single
# `sed __TARGET_DIR__ -> apps/web-platform` substitution of the workflow
# template; and the repo-root `.github/workflows/constraint-gates.yml` shares the
# substituted YAML body (different header comment only). ANY edit to a template
# MUST be mirrored into every emitted copy (and vice-versa), or the gate Soleur
# ships diverges from the gate Soleur tests. This test fails loud on any drift.
#
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Accumulate-then-exit; diff
# command-substitutions are guarded with `|| true` so `set -e` does not abort
# before fail() prints.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
REF="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/references"
APP="$REPO_ROOT/apps/web-platform"
TARGET_DIR="apps/web-platform"

passes=0
fails=0
# The INDEPENDENT row counter (ADR-193 #2). Incremented at every CALL SITE, never inside
# pass()/fail() — the VERDICT helpers touch only the verdict counters — so a stubbed fail() drops
# a verdict without dropping its count and the conservation check below notices. Top level only,
# never inside a `$( … )`.
cases=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# 1. dependency-cruiser config — byte-identical to the template.
D="$(diff "$REF/depcruise-config.template" "$APP/.dependency-cruiser.cjs" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass ".dependency-cruiser.cjs is byte-identical to depcruise-config.template"
else
  fail ".dependency-cruiser.cjs DIVERGES from depcruise-config.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 2. shared runner — byte-identical to the template.
D="$(diff "$REF/shared-runner.template" "$APP/scripts/constraint-gates.sh" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "scripts/constraint-gates.sh is byte-identical to shared-runner.template"
else
  fail "scripts/constraint-gates.sh DIVERGES from shared-runner.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 3. apps/web-platform workflow == sed(__TARGET_DIR__ -> apps/web-platform) of the template.
SUBST="$(sed "s|__TARGET_DIR__|$TARGET_DIR|g" "$REF/constraint-gates-workflow.template")"
D="$(printf '%s\n' "$SUBST" | diff - "$APP/.github/workflows/constraint-gates.yml" 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "apps/web-platform workflow == sed(__TARGET_DIR__) of the workflow template"
else
  fail "apps/web-platform workflow DIVERGES from the substituted template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 4. repo-root workflow BODY (header comment + blank lines stripped) == the
#    substituted template body (same strip). The two carry different header
#    comments by design; the executable YAML body must match exactly.
strip_body() { grep -vE '^[[:space:]]*#' | grep -vE '^[[:space:]]*$' || true; }
ROOT_BODY="$(strip_body < "$REPO_ROOT/.github/workflows/constraint-gates.yml")"
TMPL_BODY="$(printf '%s\n' "$SUBST" | strip_body)"
D="$(diff <(printf '%s\n' "$ROOT_BODY") <(printf '%s\n' "$TMPL_BODY") 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "repo-root workflow body (comment-stripped) == substituted template body"
else
  fail "repo-root workflow body DIVERGES from the substituted template body"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 5. repo-root dogfood Stage B == sed(__TARGET_DIR__) of the Stage B template (comment-stripped
#    body). Stage B is the PRIVILEGED, write-capable recovery consumer and carries the entire
#    fork-defense (isCrossRepository gate, path allowlist, sha256 round-trip, mandatory
#    base_tree); it has NO intentional dogfood divergence, so its body must match the tenant
#    template exactly. Guards the silent-drift class the emit test — which only inspects emitted
#    tenant fixtures, never the committed repo-root dogfood — structurally cannot catch (#5814).
B_ROOT="$REPO_ROOT/.github/workflows/fix-constraints-stage-b.yml"
STAGE_B_SUBST="$(sed "s|__TARGET_DIR__|$TARGET_DIR|g" "$REF/fix-constraints-stage-b.template")"
ROOT_B_BODY="$(strip_body < "$B_ROOT")"
TMPL_B_BODY="$(printf '%s\n' "$STAGE_B_SUBST" | strip_body)"
D="$(diff <(printf '%s\n' "$ROOT_B_BODY") <(printf '%s\n' "$TMPL_B_BODY") 2>&1 || true)"
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "repo-root fix-constraints-stage-b body == substituted Stage B template body"
else
  fail "repo-root fix-constraints-stage-b DIVERGES from the substituted template body"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 6. Dogfood security invariants on the two repo-root recovery workflows. Stage A intentionally
#    diverges from its template (dogfood-only api-spend steps + a richer anthropic-preflight
#    composite), so it gets invariant assertions rather than a body diff.
A_ROOT="$REPO_ROOT/.github/workflows/fix-constraints-stage-a.yml"

# 6a. Name-coupling: Stage A `name:` == Stage B `workflows:` filter (workflow_run matches by the
#     workflow's name, NOT its filename — a drift makes Stage B silently never trigger).
A_NAME="$(grep -E '^name:' "$A_ROOT" | head -1 | sed -E 's/^name:[[:space:]]*//' || true)"
B_WF="$(grep -E '^[[:space:]]+workflows:' "$B_ROOT" | head -1 | sed -E 's/.*workflows:[[:space:]]*\[[[:space:]]*"?([^]"]*)"?[[:space:]]*\].*/\1/' || true)"
cases=$((cases + 1))
if [[ -n "$A_NAME" && "$A_NAME" == "$B_WF" ]]; then
  pass "dogfood name-coupling: Stage A name: ('$A_NAME') == Stage B workflows: filter"
else
  fail "dogfood name-coupling BROKEN: Stage A name: ('$A_NAME') != Stage B workflows: ('$B_WF') — Stage B would never trigger"
fi

# 6b. Stage B (privileged) executes no untrusted tree: no checkout-of-head / bun install /
#     git apply in its executable body (full-line comments stripped so the header's prose that
#     NAMES these constructs cannot false-match).
B_CODE="$(grep -vE '^[[:space:]]*#' "$B_ROOT" || true)"
bfail=0
if grep -qE '(^|[[:space:]-])uses:[[:space:]]*actions/checkout' "$B_ROOT"; then bfail=1; fi
for tok in 'bun install' 'setup-bun' 'git apply'; do
  if printf '%s\n' "$B_CODE" | grep -qF "$tok"; then bfail=1; fi
done
cases=$((cases + 1))
if [[ "$bfail" -eq 0 ]]; then
  pass "dogfood Stage B executes no untrusted tree (no checkout/bun-install/git-apply)"
else
  fail "dogfood Stage B contains a forbidden execution construct (checkout/bun-install/git-apply)"
fi

# 6c. Stage A (untrusted producer) is read-only: declares contents: read, never contents: write.
cases=$((cases + 1))
if grep -qE '^[[:space:]]*contents:[[:space:]]*read' "$A_ROOT" && ! grep -qE '^[[:space:]]*contents:[[:space:]]*write' "$A_ROOT"; then
  pass "dogfood Stage A is read-only (contents: read, no contents: write)"
else
  fail "dogfood Stage A permission drift: expected contents: read only, found a write scope"
fi

# 7. Dogfood README block == the EMITTER's transform of boundary-readme.template (first-line
#    attribution stripped, __TARGET_DIR__ substituted). `-s` FIRST: a `diff` of two empty
#    operands passes, which is the parity vacuity that matters. The strip expression is pinned by
#    `grep -cF` against the script so the two copies of the one transform cannot diverge silently.
README_TMPL="$REF/boundary-readme.template"
README_DOG="$APP/server/README.md"
STRIP_EXPR="sed -e '1{/^<!-- Inspired by /d}' -e \"s|__TARGET_DIR__|\$TARGET_REL|g\""
GEN_SCRIPT="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
STRIP_PIN="$(grep -cF -- "$STRIP_EXPR" "$GEN_SCRIPT" 2>/dev/null || true)"
D=""
if [[ ! -s "$README_TMPL" ]]; then
  D="template $README_TMPL is missing or empty"
elif [[ ! -s "$README_DOG" ]]; then
  D="dogfood $README_DOG is missing or empty"
elif [[ "$STRIP_PIN" != "1" ]]; then
  D="strip expression pin: the script contains the literal emitter expression $STRIP_PIN time(s), expected exactly 1"
elif ! head -1 "$README_TMPL" | grep -q '^<!-- Inspired by '; then
  D="template line 1 is not the attribution comment (the emitter strips exactly that line)"
else
  D="$(sed -e '1{/^<!-- Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_DIR|g" "$README_TMPL" | diff - "$README_DOG" 2>&1 || true)"
fi
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "apps/web-platform/server/README.md == emitter transform of boundary-readme.template (non-empty; strip expression pinned)"
else
  fail "apps/web-platform/server/README.md DIVERGES from the template transform"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 8. Repo-root CLAUDE.md carries the pointer marker EXACTLY once, on a line naming the dogfood
#    README path, with no `@apps/` import form (an `@path` line is a Claude Code import and would
#    load the README into every session). Four selections for a four-dimension claim.
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
POINTER_MARKER='<!-- constraint-scaffold:pointer -->'
PTR_CT="$(grep -c -- "$POINTER_MARKER" "$CLAUDE_MD" 2>/dev/null || true)"
PTR_LINE="$(grep -- "$POINTER_MARKER" "$CLAUDE_MD" 2>/dev/null | head -1 || true)"
D=""
if [[ ! -s "$CLAUDE_MD" ]]; then
  D="CLAUDE.md is missing or empty"
elif [[ "$PTR_CT" != "1" ]]; then
  D="pointer marker appears $PTR_CT time(s), expected exactly 1"
elif [[ "$PTR_LINE" != *"apps/web-platform/server/README.md"* ]]; then
  D="pointer line does not name apps/web-platform/server/README.md: '$PTR_LINE'"
elif [[ "$PTR_LINE" == *"@apps/"* ]]; then
  D="pointer line uses the forbidden @apps/ import form: '$PTR_LINE'"
fi
cases=$((cases + 1))
if [[ -z "$D" ]]; then
  pass "CLAUDE.md carries the constraint-scaffold pointer once, naming the README path, without @apps/"
else
  fail "CLAUDE.md pointer: $D"
fi

echo "---"

# --- Accounting conservation (ADR-193 #3) --------------------------------------------------
# Ordered BEFORE the floor (ADR-193 #4): a neutered fail()/pass() deflates the verdict counters, so
# the floor below would ALSO trip and would report the misleading "arms were deleted". This says
# "a verdict was discarded" instead. Reported with `printf >&2` + `exit 1` DIRECTLY, never
# through fail(): a check that reports by calling the verdict helper increments the very counter
# the exit status reads, so neutering fail() silences the rows AND the check meant to notice the
# silence. Every row records exactly one verdict, so passes+fails MUST equal cases; because
# `cases` moves at the CALL SITE and not inside the verdict helpers, the identity is a real
# constraint rather than a tautology. The literal `[FATAL] accounting` is load-bearing —
# guard-vacuity-floor's ARM 10 builds its conservation population by grepping that exact string.
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' "$((passes + fails))" "$cases" >&2
  if [[ $((passes + fails)) -lt "$cases" ]]; then
    printf '  A row was counted but its verdict was not recorded — that is what a neutered pass()/fail() looks like.\n' >&2
  else
    printf '  A verdict was recorded at a call site with no `cases=$((cases + 1))` before it. This is a harness bug, not a product failure: add the increment at that call site.\n' >&2
  fi
  echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

# --- Anti-vacuity floor (ADR-193 #1) -------------------------------------------------------
# Reads the INDEPENDENT `cases` counter, and reports with `printf >&2` + `exit 1` DIRECTLY.
# This suite previously carried NO suite-level floor at all: a harness that silently asserted
# nothing printed a clean smaller total and exited 0. MIN_ROWS is derived at commit time by
# counting the `cases=$((cases + 1))` call sites in this file: 8 pre-existing verdict sites (rows
# 1, 2, 3, 4, 5, 6a, 6b, 6c) + rows 7–8 = 10. The literal sits on the line directly above the `if`
# because guard-vacuity-floor's backward slice carries only contiguous simple assignments into
# its neutered-machinery mutant; bound anywhere else, the mutant dies unbound and the floor
# scores CONSTRUCTION instead of FIRES.
MIN_ROWS=10
if [[ "$cases" -lt "$MIN_ROWS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ROWS" >&2
  printf '  Rows were deleted or skipped; a green run here would be a coverage loss.\n' >&2
  echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
  exit 1
fi

echo "parity.test.sh: $passes passed, $fails failed ($cases rows)"
[[ "$fails" -eq 0 ]]
