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

echo "---"
echo "parity.test.sh: $passes passed, $fails failed"
[[ "$fails" -eq 0 ]]
