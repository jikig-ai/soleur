#!/usr/bin/env bash
# Emitter coverage for the `/soleur fix constraints` recovery dispatcher (#5791,
# ADR-071). Proves constraint-scaffold.sh emits `.github/workflows/fix-constraints.yml`
# into the target and refuses to overwrite an existing one. Hermetic: every fixture is
# a throwaway `git init` repo under a mktemp dir targeted via CONSTRAINT_SCAFFOLD_REPO_ROOT;
# the real apps/web-platform tree is never touched. No dependency-cruiser needed — the
# emit (cp/sed) happens BEFORE baseline capture, so a default-mode run writes the workflow
# and then bails at the origin/main merge-base step (no remote in the fixture).
#
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Accumulate-then-exit.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
GEN="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
FIXREL="apps/web-platform/.github/workflows/fix-constraints.yml"

passes=0
fails=0
pass() { printf 'ok   - %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Throwaway git repo with a valid Next.js-shaped app dir, committed clean (no origin/main).
make_repo() {
  local fx="$TMPROOT/$1"
  mkdir -p "$fx/apps/web-platform/app"
  git -C "$fx" init -q
  git -C "$fx" config user.email "test@example.com"
  git -C "$fx" config user.name "test"
  printf 'module.exports = {};\n' > "$fx/apps/web-platform/next.config.js"
  printf '{ "dependencies": { "next": "15.0.0" } }\n' > "$fx/apps/web-platform/package.json"
  git -C "$fx" add -A
  git -C "$fx" commit -q -m "seed app"
  printf '%s' "$fx"
}

# --- Emit: default mode writes fix-constraints.yml (before baseline capture) --------
FX="$(make_repo emit)"
set +e
CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX" bash "$GEN" >/dev/null 2>&1
EMIT_RC=$?
set -e
# The run intentionally fails at baseline capture (no origin/main merge-base in the
# fixture), but the workflow file is emitted first. We assert on the artifact, not the rc.
if [[ -f "$FX/$FIXREL" ]]; then
  pass "emit: fix-constraints.yml written to the target (.github/workflows/)"
else
  fail "emit: fix-constraints.yml NOT written (run rc=$EMIT_RC)"
fi
if grep -q 'issue_comment' "$FX/$FIXREL" 2>/dev/null; then
  pass "emit: emitted workflow is the issue_comment dispatcher"
else
  fail "emit: emitted workflow missing the issue_comment trigger"
fi
# __TARGET_DIR__ must be substituted to the real target dir (no residual placeholder).
if grep -q '__TARGET_DIR__' "$FX/$FIXREL" 2>/dev/null; then
  fail "emit: __TARGET_DIR__ placeholder left UNSUBSTITUTED in the emitted workflow"
else
  pass "emit: __TARGET_DIR__ fully substituted in the emitted workflow"
fi
if grep -qF 'bash apps/web-platform/scripts/constraint-gates.sh' "$FX/$FIXREL" 2>/dev/null; then
  pass "emit: runner path substituted to the target dir (apps/web-platform)"
else
  fail "emit: substituted runner path not found in the emitted workflow"
fi

# --- Refuse-if-exists: a pre-existing fix-constraints.yml blocks the emit (exit 66) --
FX2="$(make_repo refuse)"
mkdir -p "$(dirname "$FX2/$FIXREL")"
printf '# already here\n' > "$FX2/$FIXREL"
git -C "$FX2" add -A && git -C "$FX2" commit -q -m "pre-place fix-constraints"
set +e
REFUSE_OUT="$(CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX2" bash "$GEN" 2>&1)"
REFUSE_RC=$?
set -e
if [[ "$REFUSE_RC" == "66" ]] && printf '%s' "$REFUSE_OUT" | grep -q 'fix-constraints.yml already present'; then
  pass "refuse: pre-existing fix-constraints.yml triggers refuse-if-exists (exit 66)"
else
  fail "refuse: expected exit 66 naming fix-constraints.yml, got rc=$REFUSE_RC: $REFUSE_OUT"
fi

echo "---"
echo "emit-fix-constraints.test.sh: $passes passed, $fails failed"
[[ "$fails" -eq 0 ]]
