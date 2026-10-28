#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge` when a feature PR
# has not completed the Phase 5.5 CMO Content-Opportunity Gate.
#
# Enforces hard rule `hr-before-shipping-ship-phase-5-5-runs` at the
# `gh pr ready` / `gh pr merge` boundary — closing the bypass class where an agent
# skips /ship Phase 5.5 and directly arms or executes PR merge without the CMO
# content review.
#
# Pattern source: ship/SKILL.md §CMO Content-Opportunity Gate:
#   - Trigger: PR title normalized matches `^feat\b` OR diff introduces a new
#     skill/harness component.
#   - Resolution: diff touches plugins/soleur/docs/blog/** or knowledge-base/marketing/**,
#     or PR carries a `Reviewed-By-CMO:` trailer on the branch.
#   - Escape hatch: SOLEUR_SKIP_CMO_CONTENT_GATE=1.

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

# shellcheck source=lib/hook-input.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[ship-cmo-content-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
if ! hook_parse_input "$INPUT"; then
  hook_input_report "ship-cmo-content-gate"
  hook_input_should_ask && { hook_input_emit_ask "ship-cmo-content-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi

# Match `gh pr ready` or `gh pr merge` (with any flags or arguments)
if ! grep -qE '(^|&&|\|\||;)\s*('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh\s+pr\s+(ready|merge)(\s|$|&&|\|\||;)' <<<"$SCAN"; then
  exit 0
fi

if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
cd "$WORK_DIR" 2>/dev/null || exit 0

if [[ "${SOLEUR_SKIP_CMO_CONTENT_GATE:-}" == "1" ]]; then
  exit 0
fi

# Resolve the PR number
PR_NUM=$(echo "$CMD" | grep -oE 'gh\s+pr\s+(ready|merge[^|;&]*)\s+([0-9]+)' | grep -oE '[0-9]+$' | head -1 || true)
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || true)
fi
[[ -n "$PR_NUM" ]] || exit 0

PR_TITLE=$(gh pr view "$PR_NUM" --json title --jq .title 2>/dev/null || true)
[[ -n "$PR_TITLE" ]] || exit 0

# Strip draft/wip prefixes and check for ^feat\b
NORM_TITLE=$(echo "$PR_TITLE" | sed -E 's/^(WIP|Draft)[:\s-]+//I')
IS_FEAT=0
if [[ "$NORM_TITLE" =~ ^feat(\(.*\))?!?: ]]; then
  IS_FEAT=1
elif [[ "$NORM_TITLE" =~ ^feat\b ]]; then
  IS_FEAT=1
fi

# If not a feat PR, pass silently
if [[ "$IS_FEAT" -eq 0 ]]; then
  exit 0
fi

# Resolve base ref for log/diff scope
BASE_REF=""
for cand in origin/main origin/master main master; do
  if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then BASE_REF="$cand"; break; fi
done
[[ -n "$BASE_REF" ]] || BASE_REF="HEAD~1"

# Check if review trailer exists in branch commits
TRAILER_CMO=$(git log "${BASE_REF}..HEAD" --format='%(trailers:key=Reviewed-By-CMO,valueonly)' 2>/dev/null | tr -d '[:space:]' || true)
if [[ -n "$TRAILER_CMO" ]]; then
  exit 0
fi

# Check if diff touches marketing, content strategy, or blog
CHANGED_MARKETING=$(git diff --name-only "${BASE_REF}...HEAD" 2>/dev/null | grep -E '^(plugins/soleur/docs/blog/|knowledge-base/marketing/)' || true)
if [[ -n "$CHANGED_MARKETING" ]]; then
  exit 0
fi

# Fail-closed: deny the tool call
declare -f emit_incident >/dev/null && \
  emit_incident hr-before-shipping-ship-phase-5-5-runs applied \
    "PreToolUse gate blocked gh pr ready/merge for PR #${PR_NUM} without CMO content disposition" 2>/dev/null || true

REASON_LINES=()
REASON_LINES+=("PR #${PR_NUM} ('${PR_TITLE}') is a feature PR but has not run the Phase 5.5 CMO Content-Opportunity Gate (hr-before-shipping-ship-phase-5-5-runs).")
REASON_LINES+=("")
REASON_LINES+=("Resolve via one of:")
REASON_LINES+=("  (a) Run the CMO assessment to assess content and distribution opportunities, then draft content in plugins/soleur/docs/blog/ or update knowledge-base/marketing/content-strategy.md.")
REASON_LINES+=("  (b) If no external content is warranted, commit a CMO review trailer: git commit --allow-empty -m 'cmo: disposition' -m 'Reviewed-By-CMO: skip (<one-line rationale>)'.")
REASON_LINES+=("  (c) Emergency override: SOLEUR_SKIP_CMO_CONTENT_GATE=1 <cmd>.")

REASON=$(printf '%s\n' "${REASON_LINES[@]}")

jq -nc --arg r "$REASON" '{decision: "deny", reason: $r}'
exit 0
