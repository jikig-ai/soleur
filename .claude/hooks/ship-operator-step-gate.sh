#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge --auto` when the
# PR body contains undeferred operator-step accretions.
#
# Enforces hard rule `hr-never-label-any-step-as-manual-without` and workflow
# gate `wg-block-pr-ready-on-undeferred-operator-steps` at the
# `gh pr ready` / `gh pr merge --auto` boundary — closing the bypass class
# where the agent skips /ship Phase 5.5 (where the gate is documented) and
# goes straight to `gh pr ready`.
#
# Pattern source: ship/SKILL.md §Undeferred Operator-Step Gate, with broader
# detection regex covering phrasings observed in real PRs that slipped the
# narrower /ship version (PR #4227, 2026-05-21):
#   - `Operator: <noun>` (capitalised, with colon — bullet headings)
#   - `Operator (verify|confirm|set|file|check|...)`  (extended verb set)
#   - `T+<N><units>` verification bullets ("T+90 min", "T+24h")
#   - `Within <N>h of merge: (file|run|verify)`
#   - `**Post-merge**:` blocks with action verbs
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to working directory
#
# Fail-open conditions (exit 0 silently):
#   - input lacks .cwd or path is not an absolute existing directory
#   - command is not `gh pr ready` / `gh pr merge --auto`
#   - cannot read PR body (no PR exists yet, gh not authenticated, etc.)
#
# Fail-closed conditions (deny + emit_incident):
#   - PR body contains operator-step accretions without OPEN
#     `deferred-automation` / `automation gap` companion issues

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Match either `gh pr ready` or `gh pr merge` with --auto flag. The chained-
# operator clause catches `gh pr ready && gh pr merge --squash --auto` and
# similar. Word-boundary-anchored to avoid false positives on quoted strings.
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh pr ready` is not mistaken for one (#5192).
# incidents.sh is SOFT-sourced above (`2>/dev/null || true`); under `set -e` a
# bare `strip_command_bodies` call would abort + fail-OPEN if the lib failed to
# load, so guard on the helper and fall back to raw $CMD (fail-toward-firing).
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'; then
  exit 0
fi

# Validate WORK_DIR
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
cd "$WORK_DIR" 2>/dev/null || exit 0

# Allow override via env var (CI workflows, ultrareview, etc.)
if [[ "${SOLEUR_SKIP_OPERATOR_STEP_GATE:-}" == "1" ]]; then
  exit 0
fi

# Resolve the PR number. Try the command first (e.g., `gh pr ready 4227`),
# then fall back to the current branch's PR.
PR_NUM=$(echo "$CMD" | grep -oE 'gh\s+pr\s+(ready|merge[^|;&]*)\s+([0-9]+)' | grep -oE '[0-9]+$' | head -1 || true)
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || true)
fi
[[ -n "$PR_NUM" ]] || exit 0

PR_BODY=$(gh pr view "$PR_NUM" --json body --jq .body 2>/dev/null || true)
[[ -n "$PR_BODY" ]] || exit 0

PR_BODY_FILE=$(mktemp)
trap 'rm -f "$PR_BODY_FILE"' EXIT INT TERM

# Strip fenced code blocks — quotations of the gate's own regex inside
# ```...``` MUST NOT count as undeferred declarations. Fail-closed on
# unbalanced fence per /ship parity.
printf '%s' "$PR_BODY" | awk '
  /^```/ { in_fence = !in_fence; next }
  !in_fence { print }
  END { if (in_fence) exit 2 }
' > "$PR_BODY_FILE" || printf '%s' "$PR_BODY" > "$PR_BODY_FILE"

# Strip HTML-comment override blocks (operator attestation per /ship §687)
sed -i 's|<!--[^>]*-->||g' "$PR_BODY_FILE"

# Broader regex than ship/SKILL.md §Detection — covers the phrasings PR #4227
# slipped past. Anchored to list/bullet markers (no prose false-positives).
#
# Group A: explicit operator/manual declarations
#   - `Operator:` / `Operator <verb>` / `manual gate` / `post-merge operator`
#   - Extended verb set: run/create/provision/configure/paste/cop(y/ies)
#     PLUS verify/confirm/check/file/set/install/upload/audit/click
# Group B: time-anchored verification bullets
#   - `T+<N><units>` (e.g., T+90 min, T+24h, T+2 weeks)
# Group C: post-merge-clock bullets
#   - `Within <N><units> of merge: <verb>`
# Group D: AC-PM<N> tokens (legacy from ship gate)
GROUP_A='[Oo]perator\s*:|[Oo]perator\s+(run|create|provision|configure|paste|cop(y|ies)|verif(y|ies)|confirm|check|file|set|install|upload|audit|click)s?|manual\s+gate|post-merge\s+operator'
GROUP_B='T\+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?\b.*(verif|check|confirm|file|run)'
GROUP_C='[Ww]ithin\s+[0-9]+\s*(min|m|h|hour|d|day|wk|week)s?(\s+of\s+merge)?\s*:.*(file|run|verif|check|confirm|create|provision|set)'
GROUP_D='AC-PM[0-9]+'

DETECT_RE="^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\[[[:space:]xX]\][[:space:]]+)?(\*\*)?(${GROUP_A}|${GROUP_B}|${GROUP_C}|${GROUP_D})"

MATCHES=$(grep -niE "$DETECT_RE" "$PR_BODY_FILE" 2>/dev/null || true)

if [[ -z "$MATCHES" ]]; then
  exit 0
fi

# For each match, verify a `(Tracks|Refs) #NNNN` companion exists on the same,
# previous, or next line AND points to an OPEN issue whose body contains the
# `deferred-automation` or `automation gap` sentinel.
UNDEFERRED=()
while IFS= read -r match_line; do
  line_no=$(echo "$match_line" | awk -F: '{print $1}')
  [[ "$line_no" =~ ^[0-9]+$ ]] || continue
  prev=$((line_no > 1 ? line_no - 1 : 1))
  ctx=$(sed -n "${prev}p;${line_no}p;$((line_no+1))p" "$PR_BODY_FILE")
  refs=$(printf '%s' "$ctx" | grep -oE '(Tracks|Refs)[[:space:]]+#[0-9]+' || true)
  if [[ -z "$refs" ]]; then
    UNDEFERRED+=("$match_line"); continue
  fi
  ok=0
  for n in $(printf '%s' "$refs" | grep -oE '[0-9]+'); do
    state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "")
    [[ "$state" == "OPEN" ]] || continue
    body=$(gh issue view "$n" --json body --jq .body 2>/dev/null || echo "")
    if printf '%s' "$body" | grep -qiE 'deferred-automation|automation gap'; then
      ok=1; break
    fi
  done
  [[ "$ok" == 1 ]] || UNDEFERRED+=("$match_line")
done <<< "$MATCHES"

if [[ ${#UNDEFERRED[@]} -eq 0 ]]; then
  exit 0
fi

# Fail-closed: deny the tool call with a structured message.
declare -f emit_incident >/dev/null && \
  emit_incident wg-block-pr-ready-on-undeferred-operator-steps applied \
    "PreToolUse gate blocked gh pr ready/merge --auto for PR #${PR_NUM}" 2>/dev/null || true

REASON_LINES=()
REASON_LINES+=("PR #${PR_NUM} body contains ${#UNDEFERRED[@]} undeferred operator-step accretion(s) (see hr-never-label-any-step-as-manual-without).")
REASON_LINES+=("")
REASON_LINES+=("Matching lines:")
for m in "${UNDEFERRED[@]}"; do
  REASON_LINES+=("  $m")
done
REASON_LINES+=("")
REASON_LINES+=("Resolve via one of:")
REASON_LINES+=("  (a) Inline-execute each step now (Doppler/gh/Playwright/MCP — see hr-exhaust-all-automated-options-before).")
REASON_LINES+=("  (b) File a 'deferred-automation' tracked issue per match: gh issue create --label type/chore --title '...' --body 'deferred-automation backlog item; re-evaluate when: <criterion>' then add 'Tracks #N' next to each match in the PR body.")
REASON_LINES+=("  (c) Emergency override: SOLEUR_SKIP_OPERATOR_STEP_GATE=1 <cmd> (use sparingly; logged as gate-override).")

REASON=$(printf '%s\n' "${REASON_LINES[@]}")

jq -nc --arg r "$REASON" '{decision: "deny", reason: $r}'
exit 0
