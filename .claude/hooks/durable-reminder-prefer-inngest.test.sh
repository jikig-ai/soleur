#!/usr/bin/env bash
# Fixture-based tests for durable-reminder-prefer-inngest.sh.
#
# Coverage:
#   (a) CronCreate durable:true → deny.
#   (b) CronCreate recurring:false (one-shot future reminder) → deny.
#   (c) CronCreate recurring:true, durable:false (in-session poll) → allow.
#   (d) CronCreate recurring omitted (defaults true), durable omitted → allow.
#   (e) override-marker in prompt → allow (even with durable:true).
#   (f) non-CronCreate tool (Bash) → allow.
#   (g) malformed / empty stdin → allow (fail-open invariant).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/durable-reminder-prefer-inngest.sh"

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

mk_cron_payload() {
  # args: durable recurring prompt
  jq -nc --argjson d "$1" --argjson r "$2" --arg p "$3" \
    '{tool_name: "CronCreate", tool_input: {cron: "7 18 18 6 *", prompt: $p, durable: $d, recurring: $r}}'
}

# --- (a) durable:true denies ----------------------------------------------
assert_decision "CronCreate durable:true denies" "deny" \
  "$(mk_cron_payload true false "remind me on the 18th")"

# --- (b) recurring:false one-shot denies (durable omitted) ----------------
assert_decision "CronCreate recurring:false denies" "deny" \
  "$(jq -nc '{tool_name:"CronCreate", tool_input:{cron:"7 18 18 6 *", prompt:"one-shot future reminder", recurring:false}}')"

# --- (c) recurring:true durable:false (in-session poll) allows -------------
assert_decision "CronCreate recurring:true durable:false allows" "allow" \
  "$(mk_cron_payload false true "poll CI every 5 min this session")"

# --- (d) both fields omitted (defaults: recurring true, durable false) -----
assert_decision "CronCreate defaults allow" "allow" \
  "$(jq -nc '{tool_name:"CronCreate", tool_input:{cron:"*/5 * * * *", prompt:"poll"}}')"

# --- (e) override marker in prompt allows (even durable:true) --------------
assert_decision "CronCreate override-marker allows" "allow" \
  "$(mk_cron_payload true false "session-scoped <!-- gate-override: durable-reminder-prefer-inngest --> keep open")"

# --- (f) non-CronCreate tool allows ---------------------------------------
assert_decision "Bash tool allows" "allow" \
  "$(jq -nc '{tool_name:"Bash", tool_input:{command:"echo hi"}}')"

# --- (g) malformed stdin fails open (allow) -------------------------------
assert_decision "empty stdin fails open" "allow" ""

echo ""
echo "── durable-reminder-prefer-inngest: $PASS/$TOTAL passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
