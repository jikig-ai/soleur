#!/usr/bin/env bash
# PreToolUse hook on Write|Edit for plan/spec markdown.
# Blocks plan files that bake in manual infrastructure provisioning
# (operator SSH, `doppler secrets set`, vendor-dashboard click-paths, etc.)
# instead of routing through Terraform.
#
# Source rule: AGENTS.core.md `hr-all-infrastructure-provisioning-servers`.
# Routing target: plan Phase 2.8 (Infrastructure-as-Code Routing Gate) which
# auto-invokes `terraform-architect` and requires a `## Infrastructure (IaC)`
# section in the plan output.
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {permissionDecision, permissionDecisionReason}}.
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
  emit hr-all-infrastructure-provisioning-servers deny "iac-plan-write-guard: $reason"
  # jq -n -c keeps the JSON on a single line; --arg escapes safely.
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Only fire on Write/Edit to plan/spec markdown.
case "$tool_name" in
  Write|Edit) ;;
  *) allow ;;
esac

case "$file_path" in
  */knowledge-base/project/plans/*.md \
  | */knowledge-base/project/specs/*/spec.md \
  | */knowledge-base/project/specs/*/tasks.md \
  | knowledge-base/project/plans/*.md \
  | knowledge-base/project/specs/*/spec.md \
  | knowledge-base/project/specs/*/tasks.md) ;;
  *) allow ;;
esac

# Skip archived files — they are immutable historical records.
case "$file_path" in
  */archive/*|*archive/*) allow ;;
esac

# Extract the content being written (Write) or new_string being inserted (Edit).
# Both fields are best-effort: jq returns empty on missing field, which is safe
# (an empty string matches none of the patterns below and falls through to allow).
content="$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)"

# Empty edit (e.g. delete-only) — nothing to scan.
[ -z "$content" ] && allow

# Manual-infra pattern set. Each pattern is a strong indicator of bypassing IaC.
# Patterns are checked case-insensitively via grep -i.
# False-positive shielding: an IaC-shaped phrase like `terraform import` is
# excluded because importing a pre-existing resource INTO Terraform is the
# correct migration path, not a bypass.
matches=()
add_match() {
  matches+=("$1")
}

# (a) Operator-SSH framings.
echo "$content" | grep -qiE '(\bssh\s+(root|deploy|ubuntu|admin)@|\bssh\s+-[^[:space:]]*\s+[^[:space:]]+@)' \
  && add_match "ssh <user>@<host> in plan content"

# (b) Manual-install / out-of-band / operator-driven framings (whole-phrase).
# Tolerate verb inflection (install / installs / installing) and en-dash variants.
echo "$content" | grep -qiE '\b(manually install(s|ing)?|operator (runs|installs|configures|provisions|edits|manages)|operator[- ]driven|out[- ]of[- ]band)\b' \
  && add_match "manual-install / operator-driven framing"

# (c) Systemd state-changing commands embedded in plan prose.
# Split into two patterns: leading-\b for systemctl (word boundary works at
# whitespace/word junction), and pure substring for the /etc/systemd/system/
# path (\b does NOT match between two non-word chars like space and slash).
echo "$content" | grep -qiE '\bsystemctl\s+(enable|start|restart|stop|reload|daemon-reload)\b' \
  && add_match "systemctl state-change in plan prose"
echo "$content" | grep -qiE '/etc/systemd/system/[a-z0-9._-]+\.service' \
  && add_match "/etc/systemd/system/ unit path in plan prose"

# (d) `doppler secrets set` (writes). `doppler secrets get` (reads) is fine.
echo "$content" | grep -qiE '\bdoppler\s+secrets\s+set\b' \
  && add_match "doppler secrets set (writes must go through doppler_secret Terraform resource)"

# (e) Vendor-dashboard click-paths.
echo "$content" | grep -qiE '\b(go to|open|in|navigate to)\s+the\s+(cloudflare|hetzner|stripe|doppler|better\s*stack|sentry|r2|supabase|github)\s+(dashboard|console|ui)\b' \
  && add_match "vendor-dashboard click-path"

# (f) Cron/crontab manual edits.
echo "$content" | grep -qiE '\b(crontab\s+-e|sudo\s+crontab|edit\s+the\s+crontab)\b' \
  && add_match "manual crontab edit (use a scheduled GitHub Actions workflow or Terraform-managed cron)"

# Allowlist escape hatch: a plan author who has read Phase 2.8 and decided the
# manual step is genuinely required (e.g., one-time token mint, vendor-issued
# secret that cannot be Terraform-managed) can mark the section with a literal
# IaC-routing-acknowledgement comment. The plan must include the exact line
# below to bypass the gate — this forces a deliberate, auditable opt-out.
if echo "$content" | grep -qF '<!-- iac-routing-ack: plan-phase-2-8-reviewed -->'; then
  emit hr-all-infrastructure-provisioning-servers bypass "iac-plan-write-guard: acknowledged opt-out"
  allow
fi

# No matches → fall through to allow.
if [ ${#matches[@]} -eq 0 ]; then
  allow
fi

# Compose the deny reason. Keep it actionable.
reason="BLOCKED: plan/spec content includes manual-infrastructure patterns that violate hr-all-infrastructure-provisioning-servers. Detected: $(IFS='; '; echo "${matches[*]}"). Route through Terraform per plan Phase 2.8 (Infrastructure-as-Code Routing Gate): invoke terraform-architect, write a ## Infrastructure (IaC) section, and replace manual steps with .tf resources + cloud-init / bootstrap script. If you have already reviewed Phase 2.8 and the manual step is genuinely required, add the comment '<!-- iac-routing-ack: plan-phase-2-8-reviewed -->' to the plan to opt out."

deny "$reason"
