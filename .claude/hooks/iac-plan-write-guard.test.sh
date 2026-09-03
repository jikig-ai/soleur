#!/usr/bin/env bash
# Fixture-based tests for iac-plan-write-guard.sh. Asserts the deny path
# fires for each manual-infra pattern, and the allow path fires for benign
# content, non-plan files, acknowledged opt-out, and archived files.
#
# Isolation: hook is invoked via stdin with synthetic Claude Code payloads;
# no real Write tool call is made. INCIDENTS_REPO_ROOT redirects
# emit_incident's writes into a per-test tmpdir.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

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

# ---------------------------------------------------------------------------
# #6992 regression suite — SIGPIPE race, Edit-scope ack, MultiEdit bypass.
#
# Measured 2026-07-27 against the pre-fix hook (GNU grep 3.12, bash 5.3.9,
# default 64 KiB pipe capacity). `echo "$content" | grep -q P` under
# `set -o pipefail` reports FAILURE on a successful match once $content
# exceeds what fits in the pipe: grep -q exits on first match, closing the
# read end; the still-writing producer takes SIGPIPE and exits 141; pipefail
# propagates 141 as the pipeline status. The `&& add_match` then never runs.
#
#   body   DENY/30 (violation at top, pre-fix)
#    4 KB    30      correct
#   50 KB    22      racing
#  128 KB     0      silent, total fail-open
#
# Direction matters: the policy checks fail OPEN (forbidden content allowed),
# and the ack check fails CLOSED (a valid opt-out read as absent).
# ---------------------------------------------------------------------------

ACK='<!-- iac-routing-ack: plan-phase-2-8-reviewed -->'

# T5 (AC-A6) — vacuity guard. In an agent Bash session `grep` resolves to a
# ugrep shim shell function whose -q DRAINS its input, so the race is
# invisible and every case below would pass without testing anything.
# Must run FIRST: it invalidates the rest of the suite.
TOTAL=$((TOTAL + 1))
grep_kind="$(type -t grep || echo "<none>")"
if [[ "$grep_kind" == "file" ]]; then
  PASS=$((PASS + 1))
  echo "PASS: T5 grep resolves to a binary ($(command -v grep)), not a shim"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T5 grep resolves to '$grep_kind', not a binary — the SIGPIPE cases"
  echo "      below would pass VACUOUSLY. Re-run with a clean PATH:"
  echo "      env -i PATH=/usr/bin:/bin bash --noprofile --norc $0"
fi

# Repeat-until-flake harness. A single run proves nothing about a race: the
# pre-fix hook is non-deterministic in the 50-96 KB band, so an assertion that
# runs once passes ~73% of the time at 50 KB. Every run must agree.
assert_decision_stable() {
  local label="$1" want="$2" payload="$3" runs="${4:-30}"
  TOTAL=$((TOTAL + 1))
  local i out decision mismatch=0 got_first=""
  for ((i = 0; i < runs; i++)); do
    out="$(printf '%s' "$payload" | bash "$HOOK" 2>/dev/null)"
    decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "<missing>"' 2>/dev/null || echo "<jq-fail>")"
    [[ -z "$got_first" ]] && got_first="$decision"
    [[ "$decision" == "$want" ]] || mismatch=$((mismatch + 1))
  done
  if [[ "$mismatch" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "PASS: $label → $want on all $runs runs"
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $label"
    echo "  want: $want on all $runs runs"
    echo "  got:  $mismatch/$runs disagreed (first was '$got_first')"
  fi
}

# Build a body of at least $1 KB with the caller's line placed at the very top,
# where an early grep match closes the pipe soonest.
mk_big_body() {
  local kb="$1" head_line="$2" i=0 lines
  lines=$((kb * 1024 / 40))
  printf '%s\n\n' "$head_line"
  while ((i < lines)); do
    printf 'filler prose line %d padding padding\n' "$i"
    i=$((i + 1))
  done
}

VIOLATION='Phase 1: ssh root@hetzner and run setup.'

# T1 (AC-A2) — EVERY policy check at scale, not just the first.
#
# The hook has six independent checks, each its own `<match> && add_match`
# pipeline, so each fails open independently. An arm that only drives the SSH
# pattern leaves the other five free to be reverted to the pipe form with the
# whole suite green — i.e. the filed bug restored, undetected. Measured: with
# the `doppler secrets set` check alone reverted, the hook denied 0 of 15 runs
# on a 128 KB body and the suite still reported 30/30.
#
# One arm per check, at a size where the pre-fix race is deterministic.
declare -a VIOLATION_CASES=(
  "ssh|Phase 1: ssh root@hetzner and run setup."
  "operator-driven|Phase 1: Operator runs the bootstrap by hand."
  "systemctl|Phase 1: Run systemctl enable soleur.service on the box."
  "systemd-path|Phase 1: Drop the unit at /etc/systemd/system/soleur.service"
  "doppler|Phase 1: Run doppler secrets set FOO=bar -p soleur -c prd"
  "dashboard|Phase 1: Go to the Cloudflare dashboard and add the record."
  "crontab|Phase 1: Add the entry via crontab -e on the host."
)
for _case in "${VIOLATION_CASES[@]}"; do
  _label="${_case%%|*}"
  _text="${_case#*|}"
  assert_decision_stable "T1[$_label] 128 KB body, violation at top, denies every run" "deny" \
    "$(mk_payload "$PLAN_PATH" "$(mk_big_body 128 "$_text")")"
done

# T1b — the size the issue reports (~50 KB), where the race is partial. This is
# the arm that reproduces the filed 9-deny/3-allow ratio.
assert_decision_stable "T1b 50 KB body, violation at top, denies every run" "deny" \
  "$(mk_payload "$PLAN_PATH" "$(mk_big_body 50 "$VIOLATION")")"

# T1c (AC-A5, registration half) — the hook only runs on the tools its matcher
# names. T4 below proves the hook HANDLES a MultiEdit payload, but a hook that
# is never invoked handles nothing: reverting the matcher in settings.json to
# `Write|Edit` restores the production bypass with T4 still green. Assert the
# registration itself.
TOTAL=$((TOTAL + 1))
_settings="$(cd "$SCRIPT_DIR/../.." && pwd)/.claude/settings.json"
_matcher="$(jq -r '
  [ .hooks.PreToolUse[]
    | select(any(.hooks[]?; .command | test("iac-plan-write-guard\\.sh")))
    | .matcher ] | first // "<not-registered>"
' "$_settings" 2>/dev/null || echo "<jq-fail>")"
if [[ "$_matcher" == *MultiEdit* ]]; then
  PASS=$((PASS + 1))
  echo "PASS: T1c settings.json registers the hook on MultiEdit (matcher: $_matcher)"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T1c the hook is not registered for MultiEdit — the bypass is open"
  echo "  matcher: $_matcher"
  echo "  a MultiEdit-written plan never reaches this hook, whatever its own case says"
fi

# T2 — the fail-CLOSED direction: a VALID acked plan must never be denied.
# Pre-fix this denied 22/30 at 50 KB — the symptom that surfaced the bug.
assert_decision_stable "T2 50 KB body, violation + ack, allows every run" "allow" \
  "$(mk_payload "$PLAN_PATH" "$ACK
$(mk_big_body 50 "$VIOLATION")")"

assert_decision_stable "T2b 128 KB body, violation + ack, allows every run" "allow" \
  "$(mk_payload "$PLAN_PATH" "$ACK
$(mk_big_body 128 "$VIOLATION")")"

# T6 — producer/size behaviour, the measurement that drives the fix. Asserts
# the RACE EXISTS in the pre-fix shape, so this test pins the mechanism itself
# rather than the hook. It must hold regardless of how the hook is written.
TOTAL=$((TOTAL + 1))
t6_big="$(mk_big_body 128 MATCHME)"
t6_fails=0
for _ in $(seq 1 20); do
  ( set -o pipefail; echo "$t6_big" | grep -q MATCHME ) || t6_fails=$((t6_fails + 1))
done
t6_safe_fails=0
for _ in $(seq 1 20); do
  ( set -o pipefail; grep -q MATCHME <<<"$t6_big" ) || t6_safe_fails=$((t6_safe_fails + 1))
done
if [[ "$t6_fails" -gt 0 && "$t6_safe_fails" -eq 0 ]]; then
  PASS=$((PASS + 1))
  echo "PASS: T6 pipe form races ($t6_fails/20 false failures), herestring does not (0/20)"
else
  FAIL=$((FAIL + 1))
  echo "FAIL: T6 expected pipe form to race and herestring not to"
  echo "  pipe form false failures:       $t6_fails/20 (want >0)"
  echo "  herestring false failures:      $t6_safe_fails/20 (want 0)"
fi

# T3 (AC-A4) — Edit-scope ack blindness. The hook scans only `new_string`, so
# an ack living elsewhere in the file is invisible and a valid plan is denied.
# Independent of the SIGPIPE race: deterministic, and reproduces at any size.
T3_DIR="$(mktemp -d)"
trap 'rm -rf "$T3_DIR"' EXIT
mkdir -p "$T3_DIR/knowledge-base/project/plans"
T3_FILE="$T3_DIR/knowledge-base/project/plans/2026-07-27-acked-plan.md"
printf '%s\n# Plan\n\nExisting prose the edit does not touch.\n' "$ACK" > "$T3_FILE"

assert_decision "T3 Edit with ack on disk outside the chunk allows" "allow" \
  "$(mk_edit_payload "$T3_FILE" "Now $VIOLATION")"

# T3b — the ack must not be conjured from a file that lacks it.
T3B_FILE="$T3_DIR/knowledge-base/project/plans/2026-07-27-unacked-plan.md"
printf '# Plan\n\nNo acknowledgement anywhere in this file.\n' > "$T3B_FILE"

assert_decision "T3b Edit with no ack on disk still denies" "deny" \
  "$(mk_edit_payload "$T3B_FILE" "Now $VIOLATION")"

# T4 (AC-A5) — MultiEdit bypass. The hook's matcher and its own tool_name case
# both omit MultiEdit, so a plan written that way skips the guard entirely.
mk_multiedit_payload() {
  local path="$1" new_string="$2"
  jq -nc --arg p "$path" --arg n "$new_string" \
    '{tool_name: "MultiEdit", tool_input: {file_path: $p, edits: [
       {old_string: "a", new_string: "harmless"},
       {old_string: "b", new_string: $n}
     ]}}'
}

assert_decision "T4 MultiEdit carrying a violation denies" "deny" \
  "$(mk_multiedit_payload "$PLAN_PATH" "$VIOLATION")"

assert_decision "T4b MultiEdit with benign edits allows" "allow" \
  "$(mk_multiedit_payload "$PLAN_PATH" "Add a column to the messages table.")"

assert_decision "T4c MultiEdit violation + ack in a sibling edit allows" "allow" \
  "$(jq -nc --arg p "$PLAN_PATH" --arg n "$VIOLATION" --arg a "$ACK" \
     '{tool_name: "MultiEdit", tool_input: {file_path: $p, edits: [
        {old_string: "a", new_string: $a},
        {old_string: "b", new_string: $n}
      ]}}')"

echo
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
