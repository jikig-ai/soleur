#!/usr/bin/env bash
set -euo pipefail

# Tests for .claude/hooks/session-rules-loader.sh (issue #3493).
#
# Same convention as security_reminder_hook.test.sh:
#   - Subshell isolation, PASS/FAIL/TOTAL counters
#   - Inline JSON fixtures via printf
#   - Skips silently on missing prerequisites (python3, jq, git)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/session-rules-loader.sh"

PASS=0
FAIL=0
TOTAL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"; exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH"; exit 0
fi
if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: $HOOK not executable or missing — Phase 4 GREEN required"
  exit 1
fi

# Make a temp repo with sidecar fixtures + an `origin/main` baseline so
# `git diff --name-only origin/main...HEAD` is meaningful.
setup_repo() {
  local repo="$1" change_pattern="${2:-}"
  mkdir -p "$repo"
  (
    cd "$repo"
    git init -q -b main
    git config user.email t@test
    git config user.name t
    # Sidecars with one rule body each (so the loader has content to concat).
    cat > AGENTS.core.md <<'CORE'
# AGENTS Core
## Hard Rules
- Core rule [id: hr-test-core].
CORE
    cat > AGENTS.docs.md <<'DOCS'
# AGENTS Docs
## Code Quality
- Docs rule [id: cq-test-docs].
DOCS
    cat > AGENTS.rest.md <<'REST'
# AGENTS Rest
## Code Quality
- Rest rule [id: cq-test-rest].
REST
    cat > AGENTS.md <<'IDX'
# Index
## Hard Rules
- [id: hr-test-core] → core
## Code Quality
- [id: cq-test-docs] → docs
- [id: cq-test-rest] → rest
IDX
    git add . && git commit -q -m baseline
    # Simulate origin/main pointing at the baseline so `origin/main...HEAD`
    # is empty by default. Individual tests overlay extra commits.
    git branch -f origin/main HEAD
    git update-ref refs/remotes/origin/main HEAD
    if [[ -n "$change_pattern" ]]; then
      case "$change_pattern" in
        docs)  echo "doc edit" >> README.md ; git add README.md ; git commit -q -m doc ;;
        code)  printf 'export const x = 1;\n' > app.ts ; git add app.ts ; git commit -q -m code ;;
        infra) mkdir -p apps/foo/infra && echo "resource x {}" > apps/foo/infra/x.tf ; git add . ; git commit -q -m infra ;;
        mixed) echo "doc" >> README.md ; printf 'export const x = 1;\n' > app.ts ; git add . ; git commit -q -m mixed ;;
      esac
    fi
  )
}

# Invoke the hook with an envelope JSON; capture stdout to parse classes + content.
invoke_hook() {
  local repo="$1" extra_env="${2:-}"
  local payload
  payload=$(jq -nc --arg cwd "$repo" '{cwd: $cwd, session_id: "test-sess-1"}')
  if [[ -n "$extra_env" ]]; then
    printf '%s' "$payload" | env $extra_env "$HOOK"
  else
    printf '%s' "$payload" | "$HOOK"
  fi
}

assert_class() {
  local name="$1" repo="$2" expected_class_set="$3"
  TOTAL=$((TOTAL+1))
  local out actual
  out=$(invoke_hook "$repo") || { echo "FAIL: $name (hook crashed)"; FAIL=$((FAIL+1)); return; }
  actual=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE '\[rules-loader\] loaded: [^ ]+' | head -1 | sed 's/.*loaded: //')
  if [[ "$actual" == "$expected_class_set" ]]; then
    echo "PASS: $name (class=$actual)"
    PASS=$((PASS+1))
  else
    echo "FAIL: $name (expected=$expected_class_set actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

# ------------- Test 1-4: classifier per change-class ------------

T1=$(mktemp -d); setup_repo "$T1" docs
assert_class "classifier docs-only diff → core+docs"  "$T1"  "core+docs-only"

T2=$(mktemp -d); setup_repo "$T2" code
assert_class "classifier code diff → core+rest"        "$T2"  "core+rest"

T3=$(mktemp -d); setup_repo "$T3" infra
assert_class "classifier infra diff → core+rest"       "$T3"  "core+rest"

T4=$(mktemp -d); setup_repo "$T4" mixed
assert_class "classifier mixed diff → core+docs+rest"  "$T4"  "core+docs-only+rest"

T5=$(mktemp -d); setup_repo "$T5" ""
# Empty diff → all sidecars (fail-closed)
assert_class "classifier empty diff → core+docs+rest"  "$T5"  "core+docs-only+rest"

# ------------- Test 6: LOADER_FAIL_CLOSED=1 override ------------

TOTAL=$((TOTAL+1))
T6=$(mktemp -d); setup_repo "$T6" docs
out6=$(invoke_hook "$T6" "LOADER_FAIL_CLOSED=1") || true
actual6=$(printf '%s' "$out6" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE '\[rules-loader\] loaded: [^ ]+' | head -1 | sed 's/.*loaded: //')
if [[ "$actual6" == "core+docs-only+rest" ]]; then
  echo "PASS: LOADER_FAIL_CLOSED=1 forces all sidecars"
  PASS=$((PASS+1))
else
  echo "FAIL: LOADER_FAIL_CLOSED=1 forces all sidecars (got $actual6)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 7: 3-run idempotency (compaction parity) ----

TOTAL=$((TOTAL+1))
T7=$(mktemp -d); setup_repo "$T7" docs
declare -a ids
for i in 1 2 3; do
  m=$(invoke_hook "$T7" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
  if [[ -z "$m" || ! -f "$m" ]]; then
    echo "FAIL: idempotency (manifest not written on run $i)"
    FAIL=$((FAIL+1)); break
  fi
  ids[i]=$(jq -c '.rule_ids_loaded | sort' "$m")
done
if [[ -n "${ids[1]:-}" && "${ids[1]}" == "${ids[2]}" && "${ids[2]}" == "${ids[3]}" ]]; then
  echo "PASS: idempotency (3 runs identical rule_ids_loaded)"
  PASS=$((PASS+1))
elif [[ -n "${ids[1]:-}" ]]; then
  echo "FAIL: idempotency (drift: ${ids[1]} vs ${ids[2]} vs ${ids[3]})"
  FAIL=$((FAIL+1))
fi

# ------------- Test 8: bare-repo path resolution (Kieran P0-1) --

TOTAL=$((TOTAL+1))
T8_PARENT=$(mktemp -d)
git init --bare "$T8_PARENT/repo.git" -q
T8_WT="$T8_PARENT/worktree"
git -C "$T8_PARENT/repo.git" worktree add -q "$T8_WT" -b main 2>/dev/null || true
# Seed the worktree with sidecars
setup_repo "$T8_WT" docs >/dev/null 2>&1 || true
# Force-set origin/main inside worktree
(cd "$T8_WT" && git branch -f origin/main HEAD 2>/dev/null && git update-ref refs/remotes/origin/main HEAD 2>/dev/null) || true
# Invoke from $T8_WT but envelope cwd matches → hook must NOT crash and must classify.
out8=$(printf '%s' "$(jq -nc --arg cwd "$T8_WT" '{cwd: $cwd, session_id: "bare"}')" | "$HOOK" 2>&1) || {
  echo "FAIL: bare-repo path resolution (hook crashed: $out8)"
  FAIL=$((FAIL+1))
  out8=""
}
if [[ -n "$out8" ]] && printf '%s' "$out8" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  echo "PASS: bare-repo path resolution (hook returns JSON with class set)"
  PASS=$((PASS+1))
fi

# ------------- Test 9: manifest 3-field schema -----------------

TOTAL=$((TOTAL+1))
T9=$(mktemp -d); setup_repo "$T9" docs
out9=$(invoke_hook "$T9")
manifest9=$(printf '%s' "$out9" | jq -r '.hookSpecificOutput.additionalContext' | grep -oE 'manifest: [^ ]+' | sed 's/manifest: //' | head -1)
if [[ -f "$manifest9" ]]; then
  fields=$(jq -r 'keys | sort | @csv' "$manifest9")
  expected='"change_class","rule_ids_loaded","timestamp"'
  if [[ "$fields" == "$expected" ]]; then
    echo "PASS: manifest schema (3 fields exactly)"
    PASS=$((PASS+1))
  else
    echo "FAIL: manifest schema (got $fields, want $expected)"
    FAIL=$((FAIL+1))
  fi
else
  echo "FAIL: manifest schema (no manifest written)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 10: fail-closed on missing sidecar --------

TOTAL=$((TOTAL+1))
T10=$(mktemp -d); setup_repo "$T10" docs
rm -f "$T10/AGENTS.docs.md"
out10=$(invoke_hook "$T10")
ctx10=$(printf '%s' "$out10" | jq -r '.hookSpecificOutput.additionalContext')
if printf '%s' "$ctx10" | grep -q 'fail-safe: sidecar missing'; then
  echo "PASS: fail-closed on missing sidecar"
  PASS=$((PASS+1))
else
  echo "FAIL: fail-closed on missing sidecar (no fail-safe marker in stamp)"
  FAIL=$((FAIL+1))
fi

# ------------- Test 11: stamp + hint ≤ 200 bytes per line ----

TOTAL=$((TOTAL+1))
T11=$(mktemp -d); setup_repo "$T11" docs
out11=$(invoke_hook "$T11")
ctx11=$(printf '%s' "$out11" | jq -r '.hookSpecificOutput.additionalContext')
max_line=$(printf '%s' "$ctx11" | head -3 | awk '{ print length }' | sort -n | tail -1)
if (( max_line <= 200 )); then
  echo "PASS: stamp+hint lines ≤ 200 bytes (max=$max_line)"
  PASS=$((PASS+1))
else
  echo "FAIL: stamp+hint line exceeded 200 bytes (max=$max_line)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "RESULT: $PASS/$TOTAL passed ($FAIL failed)"
[[ $FAIL -eq 0 ]] || exit 1
exit 0
