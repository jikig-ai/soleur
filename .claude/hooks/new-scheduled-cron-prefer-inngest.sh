#!/usr/bin/env bash
# PreToolUse hook on Write|Edit.
# Blocks new .github/workflows/scheduled-*.yml files when the project's
# canonical pattern for scheduled work is Inngest (ADR-033).
#
# Source rule: ADR-033. Mechanical second-net to the deepen-plan Phase 4.4
# "Scheduled-work pattern check" precedent gate.
#
# Detection logic:
#   (1) Write of a new `.github/workflows/scheduled-*.yml` that does NOT
#       exist on origin/main AND contains a `schedule:` or `cron:` directive
#       in its body → DENY.
#   (2) New `.github/workflows/scheduled-*.yml` with only `workflow_dispatch:`
#       or other non-schedule triggers → ALLOW (filename pattern alone is
#       insufficient grounds; the gate fires on actual cron content).
#   (3) Edit of an existing scheduled workflow that ADDS a `schedule:` /
#       `cron:` directive → soft warn (still allow).
#
# Override hatch: add the literal HTML comment
# `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` near the top
# of the workflow YAML being written. (PreToolUse fires before any commit
# exists, so commit-message overrides are structurally unreachable here.)
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {permissionDecision, ...}}.
# Hook exit code: 0 always (JSON output controls the gate).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

allow() {
  echo '{"hookSpecificOutput":{"permissionDecision":"allow"}}'
  exit 0
}

deny() {
  local reason="$1"
  emit adr-033-inngest-cron-canonical deny "new-scheduled-cron-prefer-inngest: $reason"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

command -v jq >/dev/null 2>&1 || allow

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

case "$tool_name" in
  Write|Edit) ;;
  *) allow ;;
esac

# Only fire on .github/workflows/scheduled-*.yml (absolute or relative).
case "$file_path" in
  */.github/workflows/scheduled-*.yml \
  | */.github/workflows/scheduled-*.yaml \
  | .github/workflows/scheduled-*.yml \
  | .github/workflows/scheduled-*.yaml) ;;
  *) allow ;;
esac

# Extract content for the override-marker check below.
content="$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)"

# Override-marker escape hatch — must appear literally in the YAML body.
if echo "$content" | grep -qF '<!-- gate-override: new-scheduled-cron-prefer-inngest -->'; then
  emit adr-033-inngest-cron-canonical bypass "new-scheduled-cron-prefer-inngest: acknowledged opt-out via marker"
  allow
fi

# Strip a leading project-dir prefix so the on-main check sees a repo-rooted path.
rel_path="$file_path"
case "$rel_path" in
  "$PROJECT_DIR"/*) rel_path="${rel_path#"$PROJECT_DIR"/}" ;;
  /*/.github/workflows/*) rel_path=".github/workflows/$(basename "$rel_path")" ;;
esac

# Does the file already exist on origin/main? If so, it's an Edit of an
# existing scheduled workflow — allow (a soft-warn future enhancement could
# scan for newly-added cron: directives; out of scope for the mechanical gate).
exists_on_main=0
if git -C "$PROJECT_DIR" rev-parse --verify origin/main >/dev/null 2>&1; then
  if git -C "$PROJECT_DIR" cat-file -e "origin/main:$rel_path" 2>/dev/null; then
    exists_on_main=1
  fi
fi
if [ "$exists_on_main" -eq 1 ]; then
  allow
fi

# Content scan: only deny if the YAML body declares a schedule/cron directive.
# A file named `scheduled-release-notes.yml` that only triggers on
# `workflow_dispatch:` is NOT a scheduled cron — filename pattern alone is
# insufficient grounds to block. Match `schedule:` (workflow trigger block) or
# `cron:` (the cron-expression key inside it) as a YAML key (preceded by
# whitespace, escaped newline, or start-of-string; followed by newline,
# escaped newline, end-of-string, or whitespace).
if ! echo "$content" | grep -Eq '(^|[[:space:]]|\\n)(schedule|cron):([[:space:]]|\\n|$)'; then
  allow
fi

# Compose the deny reason — verbatim per PR #4457 plan spec.
reason="[new-scheduled-cron-prefer-inngest] New GH Actions scheduled workflow \`$rel_path\` is being created.

The project's canonical pattern for scheduled work is Inngest (ADR-033). Existing examples:
  apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts (non-agent cron)
  apps/web-platform/server/inngest/functions/cron-daily-triage.ts (agent-loop cron)

To proceed in Inngest:
  1. Add a new file under apps/web-platform/server/inngest/functions/cron-<name>.ts
  2. Register it in apps/web-platform/app/api/inngest/route.ts

To override this gate (rare — pure-GH ops like Dependabot, CodeQL, or release-only workflows):
  Add the literal HTML comment
  <!-- gate-override: new-scheduled-cron-prefer-inngest --> at the top of the workflow YAML."

deny "$reason"
