#!/usr/bin/env bash
# Cursor hook-matcher parity — issue #9608 slice 2.
#
# Pins three captures:
#   2026-10-07 exited at authentication. That note has no loaded: line.
#   2026-10-08 ran scratch probes. The historical ledger rows below are that session.
#   2026-10-11 measured this repository's .claude/settings.json.
#   2026-10-11 edit-tool session classified /go and refused one agent.
# SessionStart commands, Bash matchers, and the Edit matcher on
# security_reminder_hook.py are already-fires.
# Matchers one exec cannot separate stay unmeasured. They are not dead.
# hooks-empty.json stays empty.
# detectHarness returns cursor for nonempty CURSOR_INVOKED_AS.
# CURSOR_AGENT is not the predicate.
#
# Run: bash .claude/hooks/cursor-matcher-parity.test.sh

set -uo pipefail

. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

HOOKS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$HOOKS_DIR/../.." && pwd -P)"
SHAPE_AUTH="$REPO_ROOT/plugins/soleur/cursor/2026-10-07-cli-hook-shape.md"
SHAPE="$REPO_ROOT/plugins/soleur/cursor/2026-10-08-cli-hook-shape.md"
SHAPE_REPO="$REPO_ROOT/plugins/soleur/cursor/2026-10-11-repo-settings-shape.md"
SHAPE_EDIT="$REPO_ROOT/plugins/soleur/cursor/2026-10-11-edit-tool-shape.md"
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

if [ -f "$SHAPE_REPO" ]; then pass "2026-10-11 settings note exists"; else fail "2026-10-11 settings note missing"; fi
note_has "$SHAPE_REPO" "2026-10-11 settings note quotes the support bar" "The plugin is called supported only when a Cursor CLI session shows"
note_has "$SHAPE_REPO" "2026-10-11 settings note does not call the plugin supported" "The plugin is not supported"
note_lacks "$SHAPE_REPO" "2026-10-11 settings note has no loaded: line" "^loaded:"
note_lacks "$SHAPE_REPO" "2026-10-11 settings note does not close #9608" "Closes #9608"
note_has "$SHAPE_REPO" "2026-10-11 settings note keeps the hooks object empty" 'hooks-empty.json` stays `{ "hooks": {} }`'
note_has "$SHAPE_REPO" "2026-10-11 settings note refuses a dead mark" "They are not \`dead\`."
note_has "$SHAPE_REPO" "2026-10-11 settings note records the plugin SessionStart exec" "codex-session-start.sh"
note_has "$SHAPE_REPO" "2026-10-11 settings note records the home command" "herdr-agent-state.sh"
if [ -f "$SHAPE_REPO" ] && grep -E -q 'user_email[[:space:]]*[:=][[:space:]]*[^[:space:]]+@' "$SHAPE_REPO"; then
  fail "2026-10-11 settings note stores an email"
else
  pass "2026-10-11 settings note does not store an email"
fi

if [ -f "$SHAPE_EDIT" ]; then pass "2026-10-11 edit-tool note exists"; else fail "2026-10-11 edit-tool note missing"; fi
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note quotes the support bar" "The plugin is called supported only when a Cursor CLI session shows"
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note does not call the plugin supported" "The plugin is not supported"
note_lacks "$SHAPE_EDIT" "2026-10-11 edit-tool note has no loaded: line" "^loaded:"
note_lacks "$SHAPE_EDIT" "2026-10-11 edit-tool note does not close #9608" "Closes #9608"
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note keeps the hooks object empty" 'hooks-empty.json` stays `{ "hooks": {} }`'
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note refuses a dead mark" "They are not \`dead\`."
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note records the classification" "ROUTE brainstorm"
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note records the refusal" "SPAWN refused"
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note records the Edit exec" "security_reminder_hook.py"
note_has "$SHAPE_EDIT" "2026-10-11 edit-tool note records the unseparated alternation" "alternation is not separated"
if [ -f "$SHAPE_EDIT" ] && grep -E -q 'user_email[[:space:]]*[:=][[:space:]]*[^[:space:]]+@' "$SHAPE_EDIT"; then
  fail "2026-10-11 edit-tool note stores an email"
else
  pass "2026-10-11 edit-tool note does not store an email"
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
plugin-default\thooks/hooks.json\tsessionStart\t(none)\tran\tprobe-command-ran\tshape-note-2026-10-08'

rows=0
repo_af=0
repo_um=0
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
    disp=$(printf '%s' "$line" | awk -F '\t' '{ print $5 }')
    reason=$(printf '%s' "$line" | awk -F '\t' '{ print $6 }')
    evidence=$(printf '%s' "$line" | awk -F '\t' '{ print $7 }')
    if printf '%s\n' "$expected" | grep -F -x -q -- "$line"; then
      pass "ledger row $registry $event"
    elif [ "$registry" = "repo-claude-project" ] && [ "$evidence" = "shape-note-2026-10-11-repo-settings" ] && grep -F -x -q -- "$line" "$SHAPE_REPO"; then
      pass "ledger row $registry $event"
      case "$disp:$reason" in
        already-fires:session-start-command-execd|already-fires:bash-matcher-execd-on-shell-tool)
          repo_af=$((repo_af + 1))
          ;;
        unmeasured:matcher-not-exercised|unmeasured:script-ran-via-another-matcher)
          repo_um=$((repo_um + 1))
          ;;
        *)
          fail "repo disposition is not backed: $disp $reason"
          ;;
      esac
    elif [ "$registry" = "repo-claude-project" ] && [ "$evidence" = "shape-note-2026-10-11-edit-tool" ] && grep -F -x -q -- "$line" "$SHAPE_EDIT"; then
      pass "ledger row $registry $event"
      case "$disp:$reason" in
        already-fires:edit-matcher-execd-on-edit-tool)
          repo_af=$((repo_af + 1))
          ;;
        unmeasured:script-execd-matcher-unseparated)
          repo_um=$((repo_um + 1))
          ;;
        *)
          fail "edit-tool disposition is not backed: $disp $reason"
          ;;
      esac
    else
      fail "ledger row is not in a pinned capture: $registry $event"
    fi
    case "$disp" in
      dead)
        fail "disposition dead is not backed by a capture"
        ;;
    esac
  done < "$LEDGER"
else
  fail "ledger missing"
fi

if [ "$rows" -eq 71 ]; then
  pass "ledger has 71 rows"
else
  fail "ledger row count is $rows, want 71"
fi

if [ "$repo_af" -eq 28 ]; then
  pass "28 repository commands are already-fires"
else
  fail "already-fires repository rows are $repo_af, want 28"
fi

if [ "$repo_um" -eq 32 ]; then
  pass "32 repository matchers stay unmeasured"
else
  fail "unmeasured repository rows are $repo_um, want 32"
fi

edit_row=$'repo-claude-project\t.claude/hooks/security_reminder_hook.py\tPreToolUse\tEdit\talready-fires\tedit-matcher-execd-on-edit-tool\tshape-note-2026-10-11-edit-tool'
if grep -F -x -q -- "$edit_row" "$LEDGER" && grep -F -x -q -- "$edit_row" "$SHAPE_EDIT"; then
  pass "Edit matcher on security_reminder_hook.py already fires"
else
  fail "Edit matcher on security_reminder_hook.py is not already-fires"
fi

write_row=$'repo-claude-project\t.claude/hooks/skill-security-scan-write.sh\tPreToolUse\t^write$\tunmeasured\tscript-execd-matcher-unseparated\tshape-note-2026-10-11-edit-tool'
if grep -F -x -q -- "$write_row" "$LEDGER" && grep -F -x -q -- "$write_row" "$SHAPE_EDIT"; then
  pass "^write$ on skill-security-scan-write.sh stays unmeasured"
else
  fail "^write$ on skill-security-scan-write.sh was separated without evidence"
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

if grep -q 'if (env.CURSOR_INVOKED_AS)' "$HARNESS"; then
  pass "harness.ts returns cursor for nonempty CURSOR_INVOKED_AS"
else
  fail "harness.ts does not read nonempty CURSOR_INVOKED_AS"
fi

if grep -q 'if (env.CURSOR_AGENT)' "$HARNESS"; then
  fail "harness.ts uses CURSOR_AGENT as a predicate"
else
  pass "harness.ts does not use CURSOR_AGENT as a predicate"
fi

if grep -q 'CURSOR_INVOKED_AS' "$EMIT"; then
  pass "emit-decision.sh reads CURSOR_INVOKED_AS"
else
  fail "emit-decision.sh does not read CURSOR_INVOKED_AS"
fi

if grep -q 'CURSOR_AGENT' "$EMIT"; then
  fail "emit-decision.sh reads CURSOR_AGENT"
else
  pass "emit-decision.sh does not read CURSOR_AGENT"
fi

while IFS= read -r base; do
  [ -n "$base" ] || continue
  if awk -F '\t' -v b="$base" '$1=="repo-claude-project" && $5=="already-fires" && $2 ~ ("/" b "$") { found=1 } END { exit !found }' "$LEDGER"; then
    pass "already-fires script $base"
  else
    fail "missing already-fires script $base"
  fi
done <<'EOF'
session-rules-loader.sh
supabase-loopback-warn.sh
memory-backstop-resolve.sh
ensure-kb-index.sh
guardrails.sh
pre-merge-rebase.sh
pre-merge-auto-close-scan.sh
ship-unpushed-commits-gate.sh
ship-operator-step-gate.sh
ship-soak-followthrough-gate.sh
ship-net-issue-flow-gate.sh
follow-through-directive-gate.sh
context-reviewed-gate.sh
cla-signed-author-gate.sh
ship-runbook-ssh-gate.sh
prod-write-defer-gate.sh
git-commit-secret-scan.sh
brand-hex-commit-gate.sh
doppler-secrets-delete-redirect.sh
background-poll-prefer-monitor.sh
pkill-self-match-guard.sh
browser-snapshot-credential-guard.sh
no-memory-write.sh
kb-domain-allowlist-guard.sh
grep-rewrite.sh
security_reminder_hook.py
rule-incident-marker-capture.sh
post-dispatch-watch-gate.sh
EOF

while IFS= read -r base; do
  [ -n "$base" ] || continue
  if awk -F '\t' -v b="$base" '$1=="repo-claude-project" && $5=="already-fires" && $2 ~ ("/" b "$") { found=1 } END { exit found }' "$LEDGER" \
    && awk -F '\t' -v b="$base" '$1=="repo-claude-project" && $5=="unmeasured" && $2 ~ ("/" b "$") { found=1 } END { exit !found }' "$LEDGER"; then
    pass "unmeasured script $base"
  else
    fail "script $base is not an unmeasured matcher"
  fi
done <<'EOF'
monitor-supersede-guard.sh
worktree-write-guard.sh
skill-security-scan-write.sh
iac-plan-write-guard.sh
new-scheduled-cron-prefer-inngest.sh
durable-reminder-prefer-inngest.sh
pencil-open-guard.sh
skill-invocation-logger.sh
pre-ask-technical-fork-gate.sh
docs-cli-verification.sh
agent-token-tee.sh
pencil-collapse-guard.sh
phase-surface-hint.sh
skill-context-queries.sh
monitor-arm-recorder.sh
EOF

# Anti-vacuity floor. pass() and fail() are the assertion machinery. Neutering
# them leaves PASS and FAIL at 0, and this bound exits 1 without calling fail().
# 164 is the measured count after the 2026-10-11 edit-tool rows.
ASSERTED=$((PASS + FAIL))
if [ "$ASSERTED" -lt 164 ]; then
  printf '[FATAL] assertion floor: only %s assertion(s) ran\n' "$ASSERTED" >&2
  exit 1
fi

echo "cursor-matcher-parity: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
