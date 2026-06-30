#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` and `gh pr merge --auto` when the
# PR (or its linked plan/spec) declares a post-deploy SOAK close-criterion for a
# tracker issue that is NOT enrolled in the follow-through sweeper.
#
# Mechanical twin of ship/SKILL.md §"Soak-Gated Follow-Through Enrollment Gate"
# (wg-pm-class-followthrough-for-operator-dogfood). Closes the bypass class where
# the agent skips /ship Phase 5.5 and goes straight to `gh pr ready`/`--auto`.
#
# Why: 2026-06-29 shipped TWO soak-gated closures in PROSE with no sweeper
# enrollment (PR #5675/#5689, PR #5671/#5673). Phase 7 Step 3.5's ⏳-only scan
# never fired and both trackers were left to rot open on human memory.
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command (string), .cwd (string)
#
# Fail-open conditions (exit 0 silently):
#   - input lacks .cwd or path is not an absolute existing directory
#   - command is not `gh pr ready` / `gh pr merge --auto`
#   - cannot read PR body (no PR yet / gh unauthenticated)
#   - PR body has no soak signal
#   - operator-attestation override present
#   - a referenced tracker cannot be resolved (gh error) — the SKILL gate +
#     agent remain the backstop for the ambiguous case
#
# Fail-closed condition (deny + emit_incident):
#   - a soak signal is present AND >=1 referenced OPEN tracker is definitively
#     NOT enrolled (missing follow-through label, directive, or on-disk script)

set -eo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh" 2>/dev/null || true

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Match `gh pr ready` or `gh pr merge ... --auto` (incl. chained forms). Scan
# with commit bodies/heredocs stripped so a commit message documenting the
# command is not mistaken for one (#5192). Soft-source guard per sibling hook.
if command -v strip_command_bodies >/dev/null 2>&1; then
  SCAN=$(strip_command_bodies "$CMD")
else
  SCAN="$CMD"
fi
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'; then
  exit 0
fi

if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
cd "$WORK_DIR" 2>/dev/null || exit 0

# Emergency override env (CI / ultrareview / known-non-mechanizable soak).
if [[ "${SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE:-}" == "1" ]]; then
  exit 0
fi

# Resolve PR number from the command, else the current branch's PR.
PR_NUM=$(echo "$CMD" | grep -oE 'gh\s+pr\s+(ready|merge[^|;&]*)\s+([0-9]+)' | grep -oE '[0-9]+$' | head -1 || true)
if [[ -z "$PR_NUM" ]]; then
  PR_NUM=$(gh pr view --json number --jq .number 2>/dev/null || true)
fi
[[ -n "$PR_NUM" ]] || exit 0

PR_BODY=$(gh pr view "$PR_NUM" --json body --jq .body 2>/dev/null || true)
[[ -n "$PR_BODY" ]] || exit 0

# Operator-attestation override in the PR body (soak genuinely non-mechanizable).
if printf '%s' "$PR_BODY" | grep -q 'gate-override: soak-followthrough-enrollment'; then
  exit 0
fi

# Build the scan corpus: PR body (fenced code stripped, fail-closed on unbalanced
# fence) + any linked plan/spec read from disk.
CORPUS=$(mktemp)
trap 'rm -f "$CORPUS"' EXIT INT TERM
printf '%s' "$PR_BODY" | awk '
  /^```/ { in_fence = !in_fence; next }
  !in_fence { print }
  END { if (in_fence) exit 2 }
' > "$CORPUS" || printf '%s' "$PR_BODY" > "$CORPUS"

PLAN=$(grep -oE 'knowledge-base/project/(plans|specs)/[^[:space:])"`]+\.md' "$CORPUS" | head -1 || true)
if [[ -n "$PLAN" && -f "$PLAN" ]]; then
  cat "$PLAN" >> "$CORPUS"
fi

# Soak signal — MUST stay byte-identical to ship/SKILL.md §Detection SOAK_RE.
SOAK_RE='soak|stays? (at )?(~?0|zero)|[0-9]+[- ]day[s]?( post-deploy| soak)|post-deploy (soak|verif|observ)|adopting[[:space:]]*(→|->|to)[[:space:]]*accepted|status[[:space:]]+flip'
if ! LC_ALL=C.UTF-8 grep -qiE "$SOAK_RE" "$CORPUS" 2>/dev/null && ! grep -qiE "$SOAK_RE" "$CORPUS" 2>/dev/null; then
  exit 0
fi

# Extract referenced trackers and verify sweeper enrollment.
REFS=$(grep -oiE '(Ref|Tracks|Closes|Fixes)[[:space:]]+#[0-9]+' "$CORPUS" | grep -oE '[0-9]+' | sort -u)
UNENROLLED=()
for n in $REFS; do
  state=$(gh issue view "$n" --json state --jq .state 2>/dev/null || echo "")
  [[ "$state" == "OPEN" ]] || continue   # closed/absent trackers need no enrollment
  labels=$(gh issue view "$n" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "__ERR__")
  body=$(gh issue view "$n" --json body --jq .body 2>/dev/null || echo "__ERR__")
  # Fail-open on a gh error for this tracker (cannot prove non-enrollment).
  [[ "$labels" == "__ERR__" || "$body" == "__ERR__" ]] && continue
  enrolled=0
  if [[ ",$labels," == *",follow-through,"* ]] \
     && printf '%s' "$body" | grep -q '<!-- soleur:followthrough' \
     && printf '%s' "$body" | grep -qE 'earliest='; then
    spath=$(printf '%s' "$body" | grep -oE 'script=scripts/followthroughs/[^[:space:]]+\.sh' | head -1 | sed 's/^script=//')
    [[ -n "$spath" && -f "$spath" ]] && enrolled=1
  fi
  [[ "$enrolled" == 1 ]] || UNENROLLED+=("$n")
done

if [[ ${#UNENROLLED[@]} -eq 0 ]]; then
  exit 0
fi

declare -f emit_incident >/dev/null && \
  emit_incident wg-pm-class-followthrough-for-operator-dogfood deny \
    "PRs adding operator-only routes, cross-origin form-POST, c" "$CMD" 2>/dev/null || true

REFLIST=$(printf '#%s ' "${UNENROLLED[@]}")
REASON="BLOCKED: PR #${PR_NUM} declares a post-deploy soak close-criterion, but referenced tracker(s) ${REFLIST}are not enrolled in the follow-through sweeper.

Each soak-gated tracker MUST carry: the 'follow-through' label + a '<!-- soleur:followthrough script=scripts/followthroughs/<x>.sh earliest=<deploy+Nd> secrets=... -->' directive + a committed scripts/followthroughs/<x>.sh probe (exit 0 when the soak holds).

Resolve via one of:
  (a) Enroll now — scaffold from plugins/soleur/skills/ship/references/followthrough-stub-template.sh (Sentry-rate soaks: mirror scripts/followthroughs/reconcile-ff-only-sentry-4977.sh), label + add the directive to each tracker, land the script, then re-issue.
  (b) Cite an existing enrollment PR/issue and add the directive.
  (c) Override (non-mechanizable soak): add '<!-- gate-override: soak-followthrough-enrollment -->' + a one-line justification to the PR body, or run with SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1.

See knowledge-base/engineering/operations/runbooks/followthrough-convention.md and ship/SKILL.md §Soak-Gated Follow-Through Enrollment Gate."

jq -n --arg r "$REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
