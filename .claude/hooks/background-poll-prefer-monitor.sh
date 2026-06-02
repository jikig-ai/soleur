#!/usr/bin/env bash
# PreToolUse hook on Bash.
# Blocks a backgrounded REMOTE-STATE POLL LOOP (Bash tool with
# run_in_background:true whose command polls CI / PR / release state) and
# redirects to the Monitor tool.
#
# Source rule: hr-monitor-not-run-in-background-for-polling (AGENTS.core.md).
# Mechanical backstop to the ship Phase 7 HARD GATE (ship/SKILL.md) — that gate
# is prose, scoped to ship's code path, so a run that never loads ship (e.g. a
# "compressed" one-shot that hand-rolls the merge wait) escapes it entirely.
# This hook is the only enforcement independent of which skills load.
#
# Why: PR #4512 — a backgrounded release poll failed silently (exit 1, zero
# state visibility); a `gh pr merge`+`gh run` background poll repeated the
# pattern on 2026-05-29. The Monitor tool streams each state transition.
#
# Detection (AND-gated to keep false positives near zero):
#   tool_name == Bash
#   AND .tool_input.run_in_background == true        (the load-bearing flag)
#   AND a poll signature:
#       (a) a LOOP keyword (while|until) AND a remote-READ token
#           (gh pr view|checks|list, gh run list|view|watch, gh api,
#            gh release view, curl, wget), OR
#       (b) an unconditional self-looping watch idiom
#           (gh run watch, gh pr checks … --watch), OR
#       (c) a `for` loop AND a `sleep` AND a remote-READ token — the bounded
#           `for i in $(seq …); do gh …; sleep N; done` poll that wears a
#           for-loop's clothes (the 2026-06-02 escape that motivated this branch)
#
# Deliberately NOT denied (fall through to allow):
#   - run_in_background single-shot wait-then-exit (no loop): `sleep 15 && gh pr view`
#   - background builds: `npm run build`, `cargo build`
#   - local-only background loops (no remote-read token)
#   - background remote WRITE fan-out in a loop (`gh issue create` … in a loop) —
#     not a read/poll; use the override marker if a rare write-loop trips it
#   - a bare `for` batch loop with NO sleep (iteration over a fixed list), even
#     with a remote-read — only `for`+sleep+remote-read reads as a poll
#   - sub-agent fan-out via run_in_background (no loop+remote-read signature)
#
# Override hatch: add the literal comment
#   # gate-override: background-poll-prefer-monitor
# anywhere in the bash command. (PreToolUse fires before any commit exists, so
# commit-message overrides are structurally unreachable here — mirrors
# new-scheduled-cron-prefer-inngest.sh.)
#
# Hook stdin: JSON payload with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, ...}}.
# Hook exit code: 0 always (JSON output controls the gate). Fail-open on any
# missing field — a no-op hook is never a false block.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

deny() {
  local reason="$1"
  emit hr-monitor-not-run-in-background-for-polling deny "background-poll-prefer-monitor: blocked backgrounded poll loop"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
# `|| true` on every jq pipeline: under `set -euo pipefail`, jq exits 5 on
# malformed/empty stdin and would otherwise abort the script before any
# allow/deny JSON is emitted — breaking the "exit 0 always / fail-open"
# invariant in the header. Degrade to empty → allow instead.
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool_name" = "Bash" ] || allow

bg="$(echo "$payload" | jq -r '.tool_input.run_in_background // false' 2>/dev/null || true)"
[ "$bg" = "true" ] || allow

cmd="$(echo "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$cmd" ] || allow

# Override-marker escape hatch — must appear literally in the command.
if echo "$cmd" | grep -qF '# gate-override: background-poll-prefer-monitor'; then
  emit hr-monitor-not-run-in-background-for-polling bypass "background-poll-prefer-monitor: acknowledged opt-out via marker"
  allow
fi

# Remote-READ token: the discriminator that separates a poll (reads remote
# state) from a local loop or a write fan-out. gh subcommands scoped to
# read/poll verbs so `gh issue create` / `gh pr merge` loops do not match.
REMOTE_READ='gh[[:space:]]+(pr[[:space:]]+(view|checks|list)|run[[:space:]]+(list|view|watch)|api|release[[:space:]]+view)|curl[[:space:]]|wget[[:space:]]'
# LOOP keyword. A bare `for` over a fixed list is iteration, not polling, so it
# is NOT in this pattern on its own — including it unconditionally would
# false-fire on legitimate background batch work (see the FOR_POLL branch below
# for the narrow `for`+`sleep`+remote-read poll form that DOES qualify).
LOOP='(^|[[:space:];&|])(while|until)([[:space:]]|$)'
# Self-looping watch idioms — deny on the bg flag alone (no explicit loop needed).
WATCH_IDIOM='gh[[:space:]]+run[[:space:]]+watch|gh[[:space:]]+pr[[:space:]]+checks[^|&;]*--watch'
# `for`-loop poll: a bounded `for i in $(seq …)` / `for … in …` that ALSO sleeps
# between iterations AND reads remote state is a poll wearing a for-loop's
# clothes (the 2026-06-02 escape: `for i in $(seq 1 40); do gh run view; gh pr
# view; sleep 45; done`). Gated on `sleep` + remote-read so batch for-loops that
# lack a sleep (or do remote WRITES, e.g. `for … gh issue create`) still fall
# through to allow. A backgrounded paginated fetch with a rate-limit `sleep`
# trips this too — that is acceptable: it should also use Monitor or run in the
# foreground, and the override marker covers the rare exception.
FOR_LOOP='(^|[[:space:];&|])for([[:space:]])'
SLEEP='(^|[[:space:];&|])sleep([[:space:]]|$)'

is_poll=0
if echo "$cmd" | grep -Eq "$WATCH_IDIOM"; then
  is_poll=1
elif echo "$cmd" | grep -Eq "$LOOP" && echo "$cmd" | grep -Eq "$REMOTE_READ"; then
  is_poll=1
elif echo "$cmd" | grep -Eq "$FOR_LOOP" && echo "$cmd" | grep -Eq "$SLEEP" && echo "$cmd" | grep -Eq "$REMOTE_READ"; then
  is_poll=1
fi
[ "$is_poll" -eq 1 ] || allow

reason="[background-poll-prefer-monitor] This Bash call uses run_in_background:true to POLL remote state (CI / PR / release). That is the banned anti-pattern: a backgrounded poll loop detaches from the harness, stays opaque until it exits, and fails SILENTLY (exit 1, zero state visibility) — exactly the PR #4512 failure mode.

Use the Monitor tool instead — it streams each state transition (e.g. OPEN BLOCKED -> OPEN BEHIND -> MERGED) as a notification.

  - For a PR merge / CI wait, use the canonical loop in plugins/soleur/skills/ship/SKILL.md Phase 7 (the phase-7-poll-block).
  - For a workflow-run wait, see ship/SKILL.md Step 3 (state-change + heartbeat).
  - Rule: hr-monitor-not-run-in-background-for-polling (AGENTS.core.md).

If you genuinely need a one-shot wait (no loop) or a non-poll background job, drop run_in_background or restructure. To override this gate in a rare legitimate case, add the literal comment on its own line:
  # gate-override: background-poll-prefer-monitor"

deny "$reason"
