#!/usr/bin/env bash
# Fixture-based tests for iac-plan-write-guard.sh. Asserts the deny path
# fires for each manual-infra pattern, and the allow path fires for benign
# content, non-plan files, acknowledged opt-out, and archived files.
#
# Isolation: hook is invoked via stdin with synthetic Claude Code payloads;
# no real Write tool call is made. INCIDENTS_REPO_ROOT redirects
# emit_incident's writes into a per-test tmpdir.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/iac-plan-write-guard.sh"

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

mk_payload() {
  local path="$1" content="$2" tool="${3:-Write}"
  jq -nc --arg p "$path" --arg c "$content" --arg t "$tool" \
    '{tool_name: $t, tool_input: {file_path: $p, content: $c}}'
}

mk_edit_payload() {
  local path="$1" new_string="$2"
  jq -nc --arg p "$path" --arg n "$new_string" \
    '{tool_name: "Edit", tool_input: {file_path: $p, old_string: "x", new_string: $n}}'
}

PLAN_PATH="knowledge-base/project/plans/2026-05-18-test.md"
SPEC_PATH="knowledge-base/project/specs/feat-x/spec.md"
ARCHIVED_PATH="knowledge-base/project/plans/archive/2026-05-18-test.md"
CODE_PATH="apps/web-platform/src/foo.ts"

# --- positive (deny) cases ---

assert_decision "operator-SSH framing denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Phase 1: ssh root@hetzner and run setup.")"

assert_decision "ssh deploy@host denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Phase 2: Operator runs: ssh deploy@host and applies changes.")"

assert_decision "manually install framing denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Operator manually installs the inngest-cli binary.")"

assert_decision "out-of-band denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "These secrets are set out-of-band by the operator.")"

assert_decision "systemctl enable denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Run systemctl enable foo.service to register the unit.")"

assert_decision "/etc/systemd/system path denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Drop the unit at /etc/systemd/system/inngest.service")"

assert_decision "doppler secrets set denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Run doppler secrets set INNGEST_KEY=... -p soleur -c prd")"

assert_decision "vendor-dashboard click-path denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Go to the Better Stack dashboard and create a heartbeat.")"

assert_decision "crontab -e denies" "deny" \
  "$(mk_payload "$PLAN_PATH" "Add a cron entry via crontab -e on the host.")"

assert_decision "Edit tool with deny content denies" "deny" \
  "$(mk_edit_payload "$PLAN_PATH" "Operator runs ssh root@host to set up the cron.")"

assert_decision "Spec file is gated too" "deny" \
  "$(mk_payload "$SPEC_PATH" "Operator runs: doppler secrets set FOO=bar.")"

# --- negative (allow) cases ---

assert_decision "benign plan content allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "Phase 1: Add a column to messages table. Phase 2: Run vitest.")"

assert_decision "doppler secrets get (read) allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "Verify with: doppler secrets get INNGEST_SIGNING_KEY -p soleur -c prd --plain")"

assert_decision "code file path allows even with ssh text" "allow" \
  "$(mk_payload "$CODE_PATH" "ssh root@host (in a comment)")"

assert_decision "archived plan allows" "allow" \
  "$(mk_payload "$ARCHIVED_PATH" "Operator runs ssh root@host and doppler secrets set.")"

assert_decision "non-Write/Edit tool allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "ssh root@host" "Bash")"

assert_decision "ack opt-out comment allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "Operator runs ssh root@host.\n<!-- iac-routing-ack: plan-phase-2-8-reviewed -->")"

assert_decision "terraform import (correct migration) allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "Run terraform import hcloud_server.web 12345 to bring the server under management.")"

assert_decision "empty content allows" "allow" \
  "$(mk_payload "$PLAN_PATH" "")"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
