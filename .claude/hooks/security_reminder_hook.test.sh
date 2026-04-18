#!/usr/bin/env bash
set -euo pipefail

# Tests for security_reminder_hook.py.
# Uses the same convention as apps/web-platform/infra/disk-monitor.test.sh:
# - Subshell isolation per test (implicit: we just capture stdout/exit)
# - PASS/FAIL/TOTAL counters
# - Inline JSON fixtures via printf

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/security_reminder_hook.py"

PASS=0
FAIL=0
TOTAL=0

# Preflight: skip with exit 0 if python3 or jq missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not on PATH"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not on PATH"
  exit 0
fi
if [[ ! -x "$HOOK" ]]; then
  echo "FAIL: $HOOK not executable or missing"
  exit 1
fi

# assert_allow: hook must exit 0 with empty stdout.
assert_allow() {
  local name="$1" payload="$2"
  local out exit_code
  out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  if [[ $exit_code -eq 0 && -z "$out" ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (exit=$exit_code, out=$out)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

# assert_deny: hook must exit 0 and emit JSON with permissionDecision=deny and
# reason containing expected_sink substring.
assert_deny() {
  local name="$1" payload="$2" expected_sink="$3"
  local out exit_code decision reason
  out=$(printf '%s' "$payload" | "$HOOK" 2>/dev/null) || exit_code=$?
  exit_code=${exit_code:-0}
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null || echo "")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
  if [[ $exit_code -eq 0 && "$decision" == "deny" && "$reason" == *"$expected_sink"* ]]; then
    echo "PASS: $name"; PASS=$((PASS+1))
  else
    echo "FAIL: $name (exit=$exit_code, decision=$decision, reason=$reason)"; FAIL=$((FAIL+1))
  fi
  TOTAL=$((TOTAL+1))
}

# ---------- Case 1: Benign env-only edit → allow ----------
PAYLOAD_1=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/web-platform-release.yml",
    new_string: "  STATUS_POLL_MAX_ATTEMPTS: 60\n  # Increased from 24 to allow longer polls\n"
  }
}')
assert_allow "case-1 benign env-only workflow edit" "$PAYLOAD_1"

# ---------- Case 2: Sink introduced in run block → deny ----------
PAYLOAD_2=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "jobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          echo \"${{ github.event.issue.title }}\"\n"
  }
}')
assert_deny "case-2 issue.title sink in run block" "$PAYLOAD_2" "github.event.issue.title"

# ---------- Case 3: Whitespace-only edit → allow ----------
PAYLOAD_3=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "   \n\n\t\n"
  }
}')
assert_allow "case-3 whitespace-only edit" "$PAYLOAD_3"

# ---------- Case 4: Comment-only edit → allow ----------
PAYLOAD_4=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "# This is a comment\n# Another line of commentary\n"
  }
}')
assert_allow "case-4 comment-only edit" "$PAYLOAD_4"

# ---------- Case 5: Non-workflow file → allow ----------
PAYLOAD_5=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: "apps/web-platform/lib/security-headers.ts",
    new_string: "// contrived: ${{ github.event.issue.title }} inside run: block\nconst x = 1;"
  }
}')
assert_allow "case-5 non-workflow file with sink literal" "$PAYLOAD_5"

# ---------- Case 6: Wildcard commits[0].message → deny ----------
PAYLOAD_6=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "      - run: echo \"${{ github.event.commits[0].message }}\"\n"
  }
}')
assert_deny "case-6 commits[0].message wildcard sink" "$PAYLOAD_6" "commits"

# ---------- Case 7: Wildcard pages[0].page_name → deny ----------
PAYLOAD_7=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "      - run: |\n          echo \"${{ github.event.pages[0].page_name }}\"\n"
  }
}')
assert_deny "case-7 pages[0].page_name wildcard sink" "$PAYLOAD_7" "page_name"

# ---------- Case 8: Sink in env: (no run:) → allow (safe pattern) ----------
PAYLOAD_8=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "    env:\n      TITLE: ${{ github.event.issue.title }}\n"
  }
}')
assert_allow "case-8 sink in env block without run: (safe pattern)" "$PAYLOAD_8"

# ---------- Case 9: Non-Edit tool (defense-in-depth) → allow ----------
PAYLOAD_9=$(jq -c -n '{
  tool_name: "Write",
  tool_input: {
    file_path: ".github/workflows/ci.yml",
    new_string: "      - run: echo \"${{ github.event.issue.title }}\"\n"
  }
}')
assert_allow "case-9 non-Edit tool name (defense-in-depth)" "$PAYLOAD_9"

# ---------- Case 10: Composite action edit → allow (known limitation) ----------
PAYLOAD_10=$(jq -c -n '{
  tool_name: "Edit",
  tool_input: {
    file_path: ".github/actions/notify-ops-email/action.yml",
    new_string: "      - run: echo \"${{ github.event.issue.title }}\"\n"
  }
}')
assert_allow "case-10 composite action path out of scope" "$PAYLOAD_10"

# ---------- Case 11: Malformed JSON → allow (fail-open) ----------
# Feed non-JSON bytes; hook must not crash or block.
out_11=$(printf '%s' "this is not json at all" | "$HOOK" 2>/dev/null) || exit_11=$?
exit_11=${exit_11:-0}
if [[ $exit_11 -eq 0 && -z "$out_11" ]]; then
  echo "PASS: case-11 malformed stdin fail-open"; PASS=$((PASS+1))
else
  echo "FAIL: case-11 malformed stdin fail-open (exit=$exit_11, out=$out_11)"; FAIL=$((FAIL+1))
fi
TOTAL=$((TOTAL+1))

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
[[ $FAIL -eq 0 ]] || exit 1
