#!/usr/bin/env bash
# Emitter coverage for the two-stage `fix-constraints` recovery dispatcher (#5814, ADR-074).
# Proves constraint-scaffold.sh emits BOTH stage workflows (Stage A = untrusted pull_request
# producer; Stage B = privileged workflow_run consumer) into the target, refuses to overwrite,
# fully substitutes __TARGET_DIR__, and that the security-load-bearing structural invariants
# hold: Stage A is NOT the privileged issue_comment/pull_request_target trigger; Stage B never
# checks out the untrusted tree / never bun-installs / never git-applies; and Stage A's `name:`
# is coupled to Stage B's `on: workflow_run: workflows:` filter (a mismatch silently disables
# recovery). Hermetic: every fixture is a throwaway `git init` repo under a mktemp dir targeted
# via CONSTRAINT_SCAFFOLD_REPO_ROOT; the real apps/web-platform tree is never touched. No
# dependency-cruiser needed — the emit (cp/sed) happens BEFORE baseline capture, so a
# default-mode run writes the workflows and then bails at the origin/main merge-base step.
#
# Runs in the scripts shard (scripts/test-all.sh globs
# plugins/soleur/skills/*/test/*.test.sh). Accumulate-then-exit; command-substitutions that
# run grep/sed are guarded with `|| true` so `set -e` does not abort before fail() prints.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
GEN="$REPO_ROOT/plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh"
FIX_A="apps/web-platform/.github/workflows/fix-constraints-stage-a.yml"
FIX_B="apps/web-platform/.github/workflows/fix-constraints-stage-b.yml"

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

# --- Emit: default mode writes BOTH stage workflows (before baseline capture) --------
FX="$(make_repo emit)"
set +e
CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX" bash "$GEN" >/dev/null 2>&1
EMIT_RC=$?
set -e
# The run intentionally fails at baseline capture (no origin/main merge-base in the
# fixture), but the workflows are emitted first. We assert on the artifacts, not the rc.
for pair in "A:$FIX_A" "B:$FIX_B"; do
  stage="${pair%%:*}"; rel="${pair#*:}"
  if [[ -f "$FX/$rel" ]]; then
    pass "emit: Stage $stage ($rel) written to the target"
  else
    fail "emit: Stage $stage ($rel) NOT written (run rc=$EMIT_RC)"
  fi
done

# __TARGET_DIR__ must be fully substituted (no residual placeholder) in both stages.
for pair in "A:$FIX_A" "B:$FIX_B"; do
  stage="${pair%%:*}"; rel="${pair#*:}"
  if grep -q '__TARGET_DIR__' "$FX/$rel" 2>/dev/null; then
    fail "emit: __TARGET_DIR__ left UNSUBSTITUTED in Stage $stage"
  else
    pass "emit: __TARGET_DIR__ fully substituted in Stage $stage"
  fi
done

# Runner path substituted to the target dir in Stage A (the gate it runs).
if grep -qF 'bash apps/web-platform/scripts/constraint-gates.sh' "$FX/$FIX_A" 2>/dev/null; then
  pass "emit: Stage A runner path substituted to the target dir (apps/web-platform)"
else
  fail "emit: substituted runner path not found in Stage A"
fi

# --- Trigger anchors (on syntactic `on:`-block keys, NOT header prose) ---------------
# Stage A is the UNTRUSTED pull_request producer — never the privileged issue_comment /
# pull_request_target trigger (the whole point of the redesign). Anchor on 2-space indent.
if grep -qE '^[[:space:]]{2}pull_request:' "$FX/$FIX_A" 2>/dev/null; then
  pass "trigger: Stage A fires on pull_request (anchored on:-block key)"
else
  fail "trigger: Stage A missing the pull_request trigger block"
fi
if grep -qE '^[[:space:]]{2}(issue_comment|pull_request_target|workflow_run):' "$FX/$FIX_A" 2>/dev/null; then
  fail "trigger: Stage A declares a privileged/consumer trigger (issue_comment/pull_request_target/workflow_run) — must not"
else
  pass "trigger: Stage A declares no privileged issue_comment/pull_request_target (nor workflow_run) trigger"
fi
# Stage B is the PRIVILEGED workflow_run consumer — never an untrusted PR trigger.
if grep -qE '^[[:space:]]{2}workflow_run:' "$FX/$FIX_B" 2>/dev/null; then
  pass "trigger: Stage B fires on workflow_run (anchored on:-block key)"
else
  fail "trigger: Stage B missing the workflow_run trigger block"
fi
if grep -qE '^[[:space:]]{2}(pull_request|pull_request_target|issue_comment):' "$FX/$FIX_B" 2>/dev/null; then
  fail "trigger: Stage B declares an untrusted PR trigger — must only be workflow_run"
else
  pass "trigger: Stage B declares no untrusted pull_request/issue_comment trigger"
fi

# --- Forbidden-pattern: Stage B never executes the untrusted tree --------------------
# Stage B builds the commit via the Git Data API — no checkout of head, no git apply, no
# bun install, no PR-script execution. The header/shell COMMENTS in Stage B legitimately
# NAME these constructs ("never git-applies", "never runs bun install"), so strip comment
# lines (both YAML `#` and shell `#`) before grepping the executable body.
B_CODE="$(grep -vE '^[[:space:]]*#' "$FX/$FIX_B" || true)"
# checkout is a `uses:` step — anchor on the action ref (comments have no `uses:`).
if grep -qE '(^|[[:space:]-])uses:[[:space:]]*actions/checkout' "$FX/$FIX_B" 2>/dev/null; then
  fail "forbidden: Stage B contains an actions/checkout step (must never check out any tree)"
else
  pass "forbidden: Stage B has no actions/checkout step (Git Data API only)"
fi
for tok in 'bun install' 'setup-bun' 'git apply'; do
  if printf '%s\n' "$B_CODE" | grep -qF "$tok" 2>/dev/null; then
    fail "forbidden: Stage B executable body contains '$tok' (must never run it)"
  else
    pass "forbidden: Stage B executable body has no '$tok'"
  fi
done

# --- Name-coupling: Stage A `name:` == Stage B `workflows:` filter string ------------
# The `workflows:` filter matches a workflow's `name:` field, NOT its filename — a mismatch
# makes Stage B silently NEVER trigger (no error). Load-bearing (architecture-strategist P1).
A_NAME="$(grep -E '^name:' "$FX/$FIX_A" 2>/dev/null | head -1 | sed -E 's/^name:[[:space:]]*//' || true)"
B_WF="$(grep -E '^[[:space:]]+workflows:' "$FX/$FIX_B" 2>/dev/null | head -1 | sed -E 's/.*workflows:[[:space:]]*\[[[:space:]]*"?([^]"]*)"?[[:space:]]*\].*/\1/' || true)"
if [[ -n "$A_NAME" && "$A_NAME" == "$B_WF" ]]; then
  pass "name-coupling: Stage A name: ('$A_NAME') == Stage B workflows: filter ('$B_WF')"
else
  fail "name-coupling: Stage A name: ('$A_NAME') != Stage B workflows: filter ('$B_WF') — Stage B would never trigger"
fi

# --- Refuse-if-exists: a pre-existing stage file blocks the emit (exit 66) -----------
FX2="$(make_repo refuse)"
mkdir -p "$(dirname "$FX2/$FIX_A")"
printf '# already here\n' > "$FX2/$FIX_A"
git -C "$FX2" add -A && git -C "$FX2" commit -q -m "pre-place fix-constraints-stage-a"
set +e
REFUSE_OUT="$(CONSTRAINT_SCAFFOLD_REPO_ROOT="$FX2" bash "$GEN" 2>&1)"
REFUSE_RC=$?
set -e
if [[ "$REFUSE_RC" == "66" ]] && printf '%s' "$REFUSE_OUT" | grep -q 'fix-constraints-stage-a.yml already present'; then
  pass "refuse: pre-existing fix-constraints-stage-a.yml triggers refuse-if-exists (exit 66)"
else
  fail "refuse: expected exit 66 naming fix-constraints-stage-a.yml, got rc=$REFUSE_RC: $REFUSE_OUT"
fi

echo "---"
echo "emit-fix-constraints.test.sh: $passes passed, $fails failed"
[[ "$fails" -eq 0 ]]
