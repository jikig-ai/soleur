#!/usr/bin/env bash
# Local fixture tests for check-settings-integrity.sh (#2905).
#
# Runs without `gh` or any GitHub state — composes synthetic git refs in a
# temp repo and asserts the script exit codes + output contain the expected
# violation lines. Run from the repo root or anywhere; the script resolves
# its sibling via $0.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SUT="$SCRIPT_DIR/check-settings-integrity.sh"
[[ -x "$SUT" ]] || { echo "FAIL: $SUT not executable"; exit 1; }

PASS=0
FAIL=0

run_case() {
  local name="$1" base_json="$2" head_json="$3" expect_exit="$4" expect_grep="$5"
  local tmp
  tmp=$(mktemp -d)
  pushd "$tmp" >/dev/null
  git init -q
  git config user.email "test@test.com"
  git config user.name "test"
  mkdir -p .claude
  printf '%s' "$base_json" > .claude/settings.json
  git add . && git commit -q -m base
  local base; base=$(git rev-parse HEAD)
  printf '%s' "$head_json" > .claude/settings.json
  git add . && git commit -q -m head --allow-empty
  local head_; head_=$(git rev-parse HEAD)
  local out exit_code
  out=$(BASE_REF="$base" HEAD_REF="$head_" bash "$SUT" 2>&1)
  exit_code=$?
  popd >/dev/null
  rm -rf "$tmp"
  local ok=1
  if [[ "$exit_code" -ne "$expect_exit" ]]; then
    echo "FAIL [$name]: exit $exit_code, expected $expect_exit"
    echo "  output: $out"
    ok=0
  elif [[ -n "$expect_grep" ]] && ! grep -qE "$expect_grep" <<<"$out"; then
    echo "FAIL [$name]: missing expected pattern '$expect_grep'"
    echo "  output: $out"
    ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS [$name]"
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
}

# Case 1: full wipe — three violations
run_case "full-wipe" \
  '{"permissions":{"allow":["Bash(git status)","Bash(git diff)"]},"hooks":{"PreToolUse":[]},"enabledMcpjsonServers":["playwright"],"env":{"CLAUDE_CODE_EFFORT_LEVEL":"high"}}' \
  '{"permissions":{"allow":[]},"sandbox":{"enabled":true}}' \
  1 \
  "Deleted top-level settings keys|Introduced unrecognized top-level keys|Deleted permissions.allow entries"

# Case 2: unchanged settings — exit 0 (the only file changed is unrelated)
# Implementation detail: check-settings-integrity short-circuits when the
# settings file at base and head are byte-identical. We synthesize that by
# making both commits write the same JSON.
run_case "unchanged" \
  '{"permissions":{"allow":["Bash(git status)"]}}' \
  '{"permissions":{"allow":["Bash(git status)"]}}' \
  0 \
  ""

# Case 3: introduce unknown key only
run_case "unknown-key-only" \
  '{"permissions":{"allow":["X"]}}' \
  '{"permissions":{"allow":["X"]},"sandbox":{"enabled":true}}' \
  1 \
  "Introduced unrecognized top-level keys: sandbox"

# Case 4: delete one allow entry only
run_case "allow-deleted" \
  '{"permissions":{"allow":["A","B"]}}' \
  '{"permissions":{"allow":["A"]}}' \
  1 \
  "Deleted permissions.allow entries: B"

# Case 5: legitimate addition (should pass) — add a new permission entry
run_case "permission-added" \
  '{"permissions":{"allow":["A"]}}' \
  '{"permissions":{"allow":["A","B"]}}' \
  0 \
  ""

# Case 6: malformed head JSON — should fail
run_case "malformed-head" \
  '{"permissions":{"allow":[]}}' \
  '{not valid json' \
  1 \
  "Head .claude/settings.json is not valid JSON"

echo ""
echo "Results: $PASS pass, $FAIL fail"
[[ "$FAIL" -eq 0 ]] || exit 1
