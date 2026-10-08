#!/usr/bin/env bash
# Cursor hook-matcher parity — issue #9608 slice 2.
#
# Pins two captures:
#   2026-10-07 exited at authentication. That note has no loaded: line.
#   2026-10-08 ran scratch probes. The ledger rows below are that session.
# The repository guard file stays unmeasured. hooks-empty.json stays empty.
# detectHarness does not read CURSOR_INVOKED_AS or CURSOR_AGENT.
#
# Run: bash .claude/hooks/cursor-matcher-parity.test.sh

set -uo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOKS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd -P)"
SHAPE_AUTH="$REPO_ROOT/plugins/soleur/cursor/2026-10-07-cli-hook-shape.md"
SHAPE="$REPO_ROOT/plugins/soleur/cursor/2026-10-08-cli-hook-shape.md"
LEDGER="$HOOKS_DIR/cursor-dispositions.tsv"
EMPTY="$REPO_ROOT/plugins/soleur/cursor/hooks-empty.json"
HARNESS="$REPO_ROOT/plugins/soleur/lib/harness.ts"
EMIT="$REPO_ROOT/plugins/soleur/scripts/emit-decision.sh"

PASS=0
FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

note_has() {
  local file="$1" label="$2" needle="$3"
  if [ -f "$file" ] && grep -q "$needle" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}

note_lacks() {
  local file="$1" label="$2" needle="$3"
  if [ -f "$file" ] && grep -q "$needle" "$file"; then
    fail "$label"
  else
    pass "$label"
  fi
}

if [ -f "$SHAPE_AUTH" ]; then pass "2026-10-07 shape note exists"; else fail "2026-10-07 shape note missing"; fi
note_has "$SHAPE_AUTH" "2026-10-07 records the auth exit" "session-exited-at-auth"
note_has "$SHAPE_AUTH" "2026-10-07 quotes the support bar" "The plugin is called supported only when a Cursor CLI session shows"
note_has "$SHAPE_AUTH" "2026-10-07 does not call the plugin supported" "The plugin is not supported"
note_lacks "$SHAPE_AUTH" "2026-10-07 has no loaded: line" "^loaded:"
note_lacks "$SHAPE_AUTH" "2026-10-07 does not close #9608" "Closes #9608"
if [ -f "$SHAPE_AUTH" ] && grep -E -q 'user_email[[:space:]]*[:=][[:space:]]*[^[:space:]]+@' "$SHAPE_AUTH"; then
  fail "2026-10-07 stores an email"
else
  pass "2026-10-07 does not store an email"
fi

if [ -f "$SHAPE" ]; then pass "2026-10-08 shape note exists"; else fail "2026-10-08 shape note missing"; fi
note_has "$SHAPE" "2026-10-08 quotes the support bar" "The plugin is called supported only when a Cursor CLI session shows"
note_has "$SHAPE" "2026-10-08 does not call the plugin supported" "The plugin is not supported"
note_lacks "$SHAPE" "2026-10-08 has no loaded: line" "^loaded:"
note_lacks "$SHAPE" "2026-10-08 does not close #9608" "Closes #9608"
note_has "$SHAPE" "2026-10-08 records tool name Read" "tool_name\` value \`Read\`"
note_has "$SHAPE" "2026-10-08 records workspace_roots" "workspace_roots"
note_has "$SHAPE" "2026-10-08 records the missing cwd key" "no key named \`cwd\`"
note_has "$SHAPE" "2026-10-08 refuses CURSOR_INVOKED_AS" "CURSOR_INVOKED_AS\` is not the predicate"
if [ -f "$SHAPE" ] && grep -E -q 'user_email[[:space:]]*[:=][[:space:]]*[^[:space:]]+@' "$SHAPE"; then
  fail "2026-10-08 stores an email"
else
  pass "2026-10-08 does not store an email"
fi

expected=$'enterprise\t/etc/cursor/hooks.json\t(none)\t(none)\tabsent\tfile-absent\tshape-note-2026-10-08
team\t.cursor/managed/active-team-hooks/hooks.json\tsessionStart\t(none)\tnot-opened\tpresent-file-not-opened\tshape-note-2026-10-08
user\t~/.cursor/hooks.json\t(none)\t(none)\tabsent\tfile-absent\tshape-note-2026-10-08
project\t.cursor/hooks.json\tsessionStart\t(none)\tran\tprobe-command-ran\tshape-note-2026-10-08
project\t.cursor/hooks.json\tbeforeSubmitPrompt\t(none)\tnot-run\tsame-file-other-events-ran\tshape-note-2026-10-08
project\t.cursor/hooks.json\tpreToolUse\tRead\tran\tprobe-command-ran\tshape-note-2026-10-08
claude-user\t~/.claude/settings.json\tSessionStart\t(none)\topened\thome-settings-and-command-opened\tshape-note-2026-10-08
claude-project\t.claude/settings.json\tSessionStart\t.*\tran\tprobe-command-ran\tshape-note-2026-10-08
claude-project-local\t.claude/settings.local.json\tSessionStart\t.*\tran\tprobe-command-ran\tshape-note-2026-10-08
plugin-manifest\t./cursor/hooks-empty.json\tsessionStart\t(none)\tran\tprobe-command-ran\tshape-note-2026-10-08
plugin-default\thooks/hooks.json\tsessionStart\t(none)\tran\tprobe-command-ran\tshape-note-2026-10-08
repo-claude-project\t.claude/settings.json\t(none)\t(none)\tunmeasured\tsession-workspace-was-not-the-repo\tshape-note-2026-10-08'

rows=0
if [ -f "$LEDGER" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ""|\#*) continue ;;
    esac
    rows=$((rows + 1))
    tabs=$(printf '%s' "$line" | awk -F '\t' '{ print NF }')
    registry=$(printf '%s' "$line" | awk -F '\t' '{ print $1 }')
    event=$(printf '%s' "$line" | awk -F '\t' '{ print $3 }')
    if [ "$tabs" -ne 7 ]; then
      fail "ledger row does not have 7 fields: $registry $event"
      continue
    fi
    if printf '%s\n' "$expected" | grep -F -x -q -- "$line"; then
      pass "ledger row $registry $event"
    else
      fail "ledger row is not in the 2026-10-08 capture: $registry $event"
    fi
    disp=$(printf '%s' "$line" | awk -F '\t' '{ print $5 }')
    case "$disp" in
      already-fires|dead)
        fail "disposition $disp is not backed by this capture"
        ;;
    esac
  done < "$LEDGER"
else
  fail "ledger missing"
fi

if [ "$rows" -eq 12 ]; then
  pass "ledger has the twelve 2026-10-08 rows"
else
  fail "ledger row count is $rows, want 12"
fi

if [ -f "$EMPTY" ] && grep -q '"hooks"[[:space:]]*:[[:space:]]*{[[:space:]]*}' "$EMPTY"; then
  pass "hooks-empty.json hooks object is empty"
else
  fail "hooks-empty.json is not an empty hooks object"
fi

if [ -e "$REPO_ROOT/.cursor/hooks.json" ]; then
  fail "repo-level .cursor/hooks.json exists"
else
  pass "no repo-level .cursor/hooks.json"
fi

if grep -q 'CURSOR_INVOKED_AS\|CURSOR_AGENT' "$HARNESS"; then
  fail "harness.ts reads a Cursor marker this capture did not adopt"
else
  pass "harness.ts does not read CURSOR_INVOKED_AS or CURSOR_AGENT"
fi

if grep -q 'CURSOR_' "$EMIT"; then
  fail "emit-decision.sh reads a CURSOR_ marker"
else
  pass "emit-decision.sh does not read a CURSOR_ marker"
fi

# Anti-vacuity floor. pass() and fail() are the assertion machinery. Neutering
# them leaves PASS and FAIL at 0, and this bound exits 1 without calling fail().
# 34 is the measured count for the 2026-10-08 capture: twenty-two fixed checks
# plus one pass for each of the twelve ledger rows.
ASSERTED=$((PASS + FAIL))
if [ "$ASSERTED" -lt 34 ]; then
  printf '[FATAL] assertion floor: only %s assertion(s) ran\n' "$ASSERTED" >&2
  exit 1
fi

echo "cursor-matcher-parity: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
