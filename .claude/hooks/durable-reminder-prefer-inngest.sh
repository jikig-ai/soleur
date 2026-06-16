#!/usr/bin/env bash
# PreToolUse hook on CronCreate.
# Blocks use of the in-session CronCreate scheduler for DURABLE / future-dated
# reminders and redirects to the Inngest reminder primitive (server-side).
#
# Source rule: hr-durable-reminders-use-inngest-primitive (AGENTS.core.md).
# Mechanical backstop to the soleur:schedule Step 0 execution-substrate gate and
# the runbook decision matrix (inngest-oneshot-and-reminder-patterns.md), both of
# which are prose scoped to one code path — a run that hand-rolls a reminder via
# CronCreate (or ScheduleWakeup, then CronCreate as the durable fallback) escapes
# them. This hook is the only enforcement independent of which skills load.
#
# Why: CronCreate fires ONLY while a Claude Code session is alive and idle, so a
# reminder armed for hours/days out silently never fires once the session exits
# (even with durable:true — that persists the job to disk but still needs a live
# REPL to fire). The Inngest reminder primitive (POST /api/internal/schedule-
# reminder) is genuinely server-side and zero-deploy for an issue-comment / named-
# check. See knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md.
#
# Detection (AND-gated to keep false positives near zero):
#   tool_name == CronCreate
#   AND a future-fire-reminder signature:
#       (a) .tool_input.durable == true        (explicit cross-session intent), OR
#       (b) .tool_input.recurring == false      (one-shot "remind me at X" — a
#           future-dated fire, not a continuous in-session poll loop)
#
# Deliberately NOT denied (fall through to allow):
#   - recurring in-session polling (recurring:true, durable:false) — the legit
#     CronCreate use: a watch loop you'll observe within this session
#   - CronList / CronDelete (matcher is CronCreate only)
#
# Override hatch: include the literal comment
# `<!-- gate-override: durable-reminder-prefer-inngest -->` anywhere in the
# CronCreate `prompt` field (the only free-text input on this tool). Use it only
# for a genuinely session-scoped one-shot (e.g. "remind me in 5 min while I keep
# this session open").
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, ...}}.
# Hook exit code: 0 always (JSON output controls the gate).

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
  emit durable-reminder-prefer-inngest deny "durable-reminder-prefer-inngest: $reason"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
# `|| true` on every jq pipeline: under `set -euo pipefail`, jq exits 5 on
# malformed/empty stdin and would otherwise abort before any allow/deny JSON is
# emitted — breaking the "exit 0 always / fail-open" invariant. Degrade to
# empty → allow. Mirrors new-scheduled-cron-prefer-inngest.sh (#4600).
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null || true)"

case "$tool_name" in
  CronCreate) ;;
  *) allow ;;
esac

# NB: jq's `//` treats `false` as empty, so `.recurring // true` would wrongly
# yield true when recurring:false is explicitly set. Use has() to distinguish
# "absent" (apply default) from "present and false".
durable="$(echo "$payload" | jq -r 'if (.tool_input|type=="object") and (.tool_input|has("durable")) then (.tool_input.durable|tostring) else "false" end' 2>/dev/null || true)"
recurring="$(echo "$payload" | jq -r 'if (.tool_input|type=="object") and (.tool_input|has("recurring")) then (.tool_input.recurring|tostring) else "true" end' 2>/dev/null || true)"
prompt="$(echo "$payload" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)"

# Override-marker escape hatch — must appear literally in the prompt body.
if echo "$prompt" | grep -qF '<!-- gate-override: durable-reminder-prefer-inngest -->'; then
  emit durable-reminder-prefer-inngest bypass "durable-reminder-prefer-inngest: acknowledged opt-out via marker"
  allow
fi

# Only fire on the future-fire-reminder signature.
if [ "$durable" != "true" ] && [ "$recurring" != "false" ]; then
  allow
fi

reason="[durable-reminder-prefer-inngest] CronCreate is being used for a durable / future-dated reminder (durable=$durable, recurring=$recurring).

CronCreate fires ONLY while a Claude Code session is alive and idle — a reminder armed for hours/days out silently never fires once this session exits (durable:true persists the job but still needs a live REPL). The project's canonical pattern for future-dated reminders is the Inngest reminder primitive (server-side, no per-reminder deploy):

  SECRET=\$(doppler secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain)
  curl -fsS -X POST https://app.soleur.ai/api/internal/schedule-reminder \\
    -H \"Authorization: Bearer \$SECRET\" -H 'Content-Type: application/json' \\
    -d '{\"reminder_id\":\"<slug>\",\"fire_at\":\"<ISO8601 UTC>\",\"actor\":\"platform\",
         \"action\":{\"type\":\"issue-comment\",\"issue\":<N>,\"body\":\"<text>\"}}'

  action is an allowlisted union: issue-comment | named-check (e.g. sentry-issue-rate).
  See knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md.

For bespoke fire-time logic (repo writes, multi-step), ship a self-armed Inngest oneshot (ADR-046) instead.

Override (rare — a genuinely session-scoped one-shot you'll keep this session open for):
  add the literal comment <!-- gate-override: durable-reminder-prefer-inngest --> to the CronCreate prompt."

deny "$reason"
