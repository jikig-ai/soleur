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
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# 1. dependency-cruiser config — byte-identical to the template.
D="$(diff "$REF/depcruise-config.template" "$APP/.dependency-cruiser.cjs" 2>&1 || true)"
if [[ -z "$D" ]]; then
  pass ".dependency-cruiser.cjs is byte-identical to depcruise-config.template"
else
  fail ".dependency-cruiser.cjs DIVERGES from depcruise-config.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 2. shared runner — byte-identical to the template.
D="$(diff "$REF/shared-runner.template" "$APP/scripts/constraint-gates.sh" 2>&1 || true)"
if [[ -z "$D" ]]; then
  pass "scripts/constraint-gates.sh is byte-identical to shared-runner.template"
else
  fail "scripts/constraint-gates.sh DIVERGES from shared-runner.template"
  printf '%s\n' "$D" | sed 's/^/    /'
fi

# 3. apps/web-platform workflow == sed(__TARGET_DIR__ -> apps/web-platform) of the template.
SUBST="$(sed "s|__TARGET_DIR__|$TARGET_DIR|g" "$REF/constraint-gates-workflow.template")"
D="$(printf '%s\n' "$SUBST" | diff - "$APP/.github/workflows/constraint-gates.yml" 2>&1 || true)"
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
if [[ "$bfail" -eq 0 ]]; then
  pass "dogfood Stage B executes no untrusted tree (no checkout/bun-install/git-apply)"
else
  fail "dogfood Stage B contains a forbidden execution construct (checkout/bun-install/git-apply)"
fi

# 6c. Stage A (untrusted producer) is read-only: declares contents: read, never contents: write.
if grep -qE '^[[:space:]]*contents:[[:space:]]*read' "$A_ROOT" && ! grep -qE '^[[:space:]]*contents:[[:space:]]*write' "$A_ROOT"; then
  pass "dogfood Stage A is read-only (contents: read, no contents: write)"
else
  fail "dogfood Stage A permission drift: expected contents: read only, found a write scope"
fi

echo "---"
echo "parity.test.sh: $passes passed, $fails failed"
[[ "$fails" -eq 0 ]]
