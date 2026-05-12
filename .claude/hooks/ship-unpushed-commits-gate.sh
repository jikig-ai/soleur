#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr merge` when local commits are not pushed
# to origin/<branch>.
#
# wg-ship-push-before-merge — counts `git rev-list origin/<branch>..HEAD` and
# denies the tool call when non-zero. Closes the fail-open class that produced
# the #3624 → #3627 → #3630 incident chain, where 2 of 5 local commits never
# reached origin and the squash-merge consumed only the pushed planning files.
#
# Empirically-verified PreToolUse(Bash) input shape (2026-05-12, shape
# inherited verbatim from sibling hooks pre-merge-rebase.sh:30 and
# guardrails.sh, both production-fired against this same matcher):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to the working directory
#   .tool_name           ("Bash") — confirms matcher dispatched correctly
#
# Fail-open conditions (exit 0 silently):
#   - hook input lacks .cwd or path is not a directory
#   - not in a git work-tree (bare repo context)
#   - branch is main / master
#   - detached HEAD
#   - no upstream tracking ref (`origin/<branch>` does not exist)
#   - `git fetch origin <branch>` fails (network)
#
# Fail-closed condition (deny + emit_incident):
#   - `git rev-list origin/<branch>..HEAD --count` > 0

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Word-boundary anchored regex prevents false positives on substrings like
# `echo "gh pr merge example"`. Chain-operator clause `(^|&&|\|\||;)` catches
# chained invocations. Pattern copied verbatim from pre-merge-rebase.sh:30.
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""')
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  exit 0
fi

CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]] || [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  exit 0
fi

# No upstream tracking ref → branch was never pushed → out of this gate's scope.
if ! git -C "$WORK_DIR" rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
  exit 0
fi

# Refresh remote-tracking ref. Redirect BOTH stdout and stderr (git fetch prints
# progress to stderr; mixing with hook JSON corrupts the `jq` parse on the
# harness side — learning 2026-03-03).
if ! git -C "$WORK_DIR" fetch origin "$CURRENT_BRANCH" >/dev/null 2>&1; then
  echo "[ship-unpushed-commits-gate] warn: git fetch origin $CURRENT_BRANCH failed; proceeding with stale tracking ref." >&2
  exit 0
fi

# Count unpushed commits. `--count` returns a single integer; empty range
# returns 0, no error.
UNPUSHED=$(git -C "$WORK_DIR" rev-list "origin/${CURRENT_BRANCH}..HEAD" --count 2>/dev/null || echo 0)
UNPUSHED=${UNPUSHED:-0}

if [[ "$UNPUSHED" -le 0 ]]; then
  jq -n --arg branch "$CURRENT_BRANCH" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: ("Pre-merge unpushed-commits gate: origin/" + $branch + " is current (0 unpushed).")
    }
  }'
  exit 0
fi

# Cap commit list at 10 entries to keep deny reason readable.
COMMIT_LIST=$(git -C "$WORK_DIR" log "origin/${CURRENT_BRANCH}..HEAD" --oneline 2>/dev/null | head -10)

emit_incident "wg-ship-push-before-merge" deny \
  "Before \`gh pr merge\`, all local commits MUST be" "$CMD"

jq -n \
  --arg n "$UNPUSHED" \
  --arg branch "$CURRENT_BRANCH" \
  --arg commits "$COMMIT_LIST" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: " + $n + " local commit(s) not pushed to origin/" + $branch + ". Run `git push` before queuing auto-merge.\n\nUnpushed commits:\n" + $commits)
    }
  }'
exit 0
