#!/usr/bin/env bash
# Fixture-based tests for new-scheduled-cron-prefer-inngest.sh.
#
# Coverage:
#   (a) new scheduled YAML being Write'd triggers deny.
#   (b) Edit-existing scheduled YAML passes (file is on origin/main).
#   (c) override-marker (HTML comment) passes.
#   (d) non-scheduled YAML (e.g., pr-checks.yml) passes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/new-scheduled-cron-prefer-inngest.sh"

PASS=0
FAIL=0
TOTAL=0

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq missing"; exit 0; }

assert_decision() {
  local label="$1" want="$2" payload="$3"
  TOTAL=$((TOTAL + 1))
  local out decision
  out="$(echo "$payload" | bash "$HOOK" 2>/dev/null)"
  decision="$(echo "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<missing>"' 2>/dev/null || echo "<jq-fail>")"
  if [[ "$decision" == "$want" ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label → $decision"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  want: $want"
    echo "  got:  $decision"
    echo "  raw:  $out"
  fi
}

mk_write_payload() {
  local path="$1" content="$2"
  jq -nc --arg p "$path" --arg c "$content" \
    '{tool_name: "Write", tool_input: {file_path: $p, content: $c}}'
}

mk_edit_payload() {
  local path="$1" new_string="$2"
  jq -nc --arg p "$path" --arg n "$new_string" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: "x", new_string: $n}}'
}

# --- (a) new scheduled YAML denies ----------------------------------------

NEW_PATH=".github/workflows/scheduled-fake-cron-for-tests.yml"
assert_decision "Write new scheduled workflow denies" "deny" \
  "$(mk_write_payload "$NEW_PATH" "name: Scheduled fake\non:\n  schedule:\n    - cron: '0 0 * * *'\njobs:\n  fake:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi")"

# Also test absolute path form.
ABS_NEW_PATH="$PWD/.github/workflows/scheduled-fake-cron-for-tests.yml"
assert_decision "Write new scheduled workflow (absolute path) denies" "deny" \
  "$(mk_write_payload "$ABS_NEW_PATH" "name: Scheduled fake\non:\n  schedule:\n    - cron: '0 0 * * *'")"

# --- (b) Edit of existing scheduled YAML allows ---------------------------
# Find a scheduled-*.yml that exists on origin/main; skip the assertion if
# the worktree's origin doesn't have any (unusual in CI, but defensive).
EXISTING_PATH="$(git ls-tree origin/main --name-only -r .github/workflows 2>/dev/null | grep -E '^\.github/workflows/scheduled-.+\.yml$' | head -1 || true)"
if [ -n "$EXISTING_PATH" ]; then
  assert_decision "Edit existing scheduled workflow allows" "allow" \
    "$(mk_edit_payload "$EXISTING_PATH" "  schedule:\n    - cron: '0 6 * * *'")"
else
  echo "SKIP: no scheduled-*.yml on origin/main to test edit-allow path"
fi

# --- (c) override-marker allows -------------------------------------------

assert_decision "override-marker comment allows" "allow" \
  "$(mk_write_payload ".github/workflows/scheduled-with-marker.yml" "<!-- gate-override: new-scheduled-cron-prefer-inngest -->\nname: Test\non:\n  schedule:\n    - cron: '0 0 * * *'")"

# --- (d) non-scheduled YAML allows ----------------------------------------

assert_decision "non-scheduled workflow path allows (pr-checks.yml)" "allow" \
  "$(mk_write_payload ".github/workflows/pr-checks.yml" "name: PR\non:\n  pull_request:\njobs: {}")"

assert_decision "release workflow allows" "allow" \
  "$(mk_write_payload ".github/workflows/release.yml" "name: Release\non:\n  push:\n    tags: ['v*']\njobs: {}")"

# --- Sanity: non-Write/Edit tool calls pass through -----------------------

assert_decision "non-Write/Edit tool allows (Bash)" "allow" \
  "$(jq -nc '{tool_name: "Bash", tool_input: {command: "echo hi"}}')"

# --- Sanity: empty content with .yaml extension also fires on new file ---

assert_decision "Write new scheduled (.yaml extension) denies" "deny" \
  "$(mk_write_payload ".github/workflows/scheduled-other.yaml" "name: x\non:\n  schedule:\n    - cron: '0 0 * * *'")"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
