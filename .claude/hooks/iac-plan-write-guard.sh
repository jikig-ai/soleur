#!/usr/bin/env bash
# PreToolUse hook on Write|Edit|MultiEdit for plan/spec markdown.
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
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 always (JSON output controls the gate) — every exit path
# below runs through allow() or deny(), both of which exit 0.
#
# NEVER match content by piping `echo "$x"` into a quiet grep here (#6992).
# (The forbidden shape is spelled out in prose rather than quoted verbatim so
# that the AC-A1 sweep, which greps this file's body, cannot match its own
# documentation and report a violation that does not exist.) Under
# `set -o pipefail` that reports FAILURE on a successful match once $x exceeds
# the pipe capacity: grep -q exits on the first match and closes the read end,
# the still-writing producer takes SIGPIPE and exits 141, and pipefail
# propagates 141 as the pipeline's status. Because every check below is shaped
# `<match> && add_match`, the `&&` then does not fire and the forbidden content
# is ALLOWED THROUGH — silently, and more often the earlier the match appears.
# Measured pre-fix at 128 KB: 0 denies in 30 runs on a body whose first line
# was `ssh root@...`. Use a herestring (`grep -q P <<<"$x"`) — no pipe, no
# SIGPIPE — or `grep -c`, which reads all input and never early-closes.

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
  emit hr-all-infrastructure-provisioning-servers deny "iac-plan-write-guard: $reason"
  # jq -n -c keeps the JSON on a single line; --arg escapes safely.
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"
file_path="$(echo "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Only fire on Write/Edit/MultiEdit to plan/spec markdown.
# MultiEdit was absent until #6992: the matcher in .claude/settings.json and
# this case both omitted it, so ANY plan written via MultiEdit skipped the
# guard entirely. Siblings (guardrails.sh, no-memory-write.sh,
# kb-domain-allowlist-guard.sh) already register Write|Edit|MultiEdit|NotebookEdit.
case "$tool_name" in
  Write|Edit|MultiEdit) ;;
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

# Extract the content being written: `content` (Write), `new_string` (Edit), or
# every `edits[].new_string` joined (MultiEdit). All are best-effort: jq returns
# empty on a missing field, which is safe (an empty string matches none of the
# patterns below and falls through to allow).
content="$(jq -r '
  .tool_input.content
  // .tool_input.new_string
  // ([.tool_input.edits[]? | .new_string // empty] | join("\n"))
  // empty
' <<<"$payload" 2>/dev/null)"

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

# Every check below feeds $content to grep by HERESTRING, never by pipe.
# See the SIGPIPE note in the header — a pipe here makes the check fail OPEN.

# (a) Operator-SSH framings.
grep -qiE '(\bssh\s+(root|deploy|ubuntu|admin)@|\bssh\s+-[^[:space:]]*\s+[^[:space:]]+@)' <<<"$content" \
  && add_match "ssh <user>@<host> in plan content"

# (b) Manual-install / out-of-band / operator-driven framings (whole-phrase).
# Tolerate verb inflection (install / installs / installing) and en-dash variants.
grep -qiE '\b(manually install(s|ing)?|operator (runs|installs|configures|provisions|edits|manages)|operator[- ]driven|out[- ]of[- ]band)\b' <<<"$content" \
  && add_match "manual-install / operator-driven framing"

# (c) Systemd state-changing commands embedded in plan prose.
# Split into two patterns: leading-\b for systemctl (word boundary works at
# whitespace/word junction), and pure substring for the /etc/systemd/system/
# path (\b does NOT match between two non-word chars like space and slash).
grep -qiE '\bsystemctl\s+(enable|start|restart|stop|reload|daemon-reload)\b' <<<"$content" \
  && add_match "systemctl state-change in plan prose"
grep -qiE '/etc/systemd/system/[a-z0-9._-]+\.service' <<<"$content" \
  && add_match "/etc/systemd/system/ unit path in plan prose"

# (d) `doppler secrets set` (writes). `doppler secrets get` (reads) is fine.
grep -qiE '\bdoppler\s+secrets\s+set\b' <<<"$content" \
  && add_match "doppler secrets set (writes must go through doppler_secret Terraform resource)"

# (e) Vendor-dashboard click-paths.
grep -qiE '\b(go to|open|in|navigate to)\s+the\s+(cloudflare|hetzner|stripe|doppler|better\s*stack|sentry|r2|supabase|github)\s+(dashboard|console|ui)\b' <<<"$content" \
  && add_match "vendor-dashboard click-path"

# (f) Cron/crontab manual edits.
grep -qiE '\b(crontab\s+-e|sudo\s+crontab|edit\s+the\s+crontab)\b' <<<"$content" \
  && add_match "manual crontab edit (use a scheduled GitHub Actions workflow or Terraform-managed cron)"

# Allowlist escape hatch: a plan author who has read Phase 2.8 and decided the
# manual step is genuinely required (e.g., one-time token mint, vendor-issued
# secret that cannot be Terraform-managed) can mark the section with a literal
# IaC-routing-acknowledgement comment. The plan must include the exact line
# below to bypass the gate — this forces a deliberate, auditable opt-out.
#
# The ack is looked up in the incoming content AND in the file on disk. On an
# Edit, the incoming text is only the replacement chunk, so an ack that lives
# anywhere else in the plan is invisible to a content-only check — the author
# sees an apparently random deny while editing successive regions of a plan
# they already acked (#6992). The on-disk read is deliberately narrow: it
# answers "has this file been acked?", and does NOT rescan the whole document
# for violations. Whole-document scanning would deny every future edit to the
# 274 live plan/spec files that contain a violation and no ack.
ACK_LITERAL='<!-- iac-routing-ack: plan-phase-2-8-reviewed -->'

acked() {
  grep -qF "$ACK_LITERAL" <<<"$content" && return 0

  # The on-disk fallback applies to PARTIAL writes only. A `Write` replaces the
  # whole document, so its content is the complete post-write state: consulting
  # the pre-write file there would allow a Write that DELETES the ack while
  # adding a violation, using the very ack it is removing as the justification.
  case "$tool_name" in
    Edit|MultiEdit) ;;
    *) return 1 ;;
  esac

  # Resolve a repo-relative file_path the same way the rest of the hook does.
  local resolved="$file_path"
  case "$resolved" in
    /*) ;;
    *) resolved="$PROJECT_DIR/$resolved" ;;
  esac

  # Guarded so an unreadable path cannot trip `set -e` and change the
  # "exit 0 always" contract.
  [ -f "$resolved" ] && grep -qF "$ACK_LITERAL" "$resolved" 2>/dev/null
}

if acked; then
  emit hr-all-infrastructure-provisioning-servers bypass "iac-plan-write-guard: acknowledged opt-out"
  allow
fi

# No matches → fall through to allow.
if [ ${#matches[@]} -eq 0 ]; then
  allow
fi

# Compose the deny reason. Keep it actionable.
reason="BLOCKED: plan/spec content includes manual-infrastructure patterns that violate hr-all-infrastructure-provisioning-servers. Detected: $(IFS='; '; echo "${matches[*]}"). Route through Terraform per plan Phase 2.8 (Infrastructure-as-Code Routing Gate): invoke terraform-architect, write a ## Infrastructure (IaC) section, and replace manual steps with .tf resources + cloud-init / bootstrap script. If you have already reviewed Phase 2.8 and the manual step is genuinely required, add the comment '${ACK_LITERAL}' to the plan to opt out."

deny "$reason"
