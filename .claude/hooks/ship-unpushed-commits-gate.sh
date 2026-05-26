#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr merge` when local commits are not pushed
# to origin/<branch>.
#
# wg-ship-push-before-merge — counts `git rev-list origin/<branch>..HEAD` and
# denies the tool call when non-zero. Closes the fail-open class that produced
# the #3624 → #3627 → #3630 incident chain, where 2 of 5 local commits never
# reached origin and the squash-merge consumed only the pushed planning files.
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity, 2026-05-12):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to the working directory
#   .tool_name           ("Bash") — confirms matcher dispatched correctly
# Shape verified by parity with the existing PreToolUse(Bash) hooks
# (pre-merge-rebase.sh, guardrails.sh, worktree-write-guard.sh, etc.) — any
# drift would have visibly broken those production-fired hooks first.
#
# Fail-open conditions (exit 0 silently):
#   - hook input lacks .cwd or path is not an absolute existing directory
#   - not in a git work-tree (bare repo context)
#   - branch is main / master / detached HEAD
#   - branch name fails refname validation (defense against argument injection)
#   - no upstream tracking ref (origin/<branch> does not exist; branch never pushed)
#
# Fail-closed conditions (deny + emit_incident):
#   - git fetch origin <branch> fails — cannot verify state against a stale
#     tracking ref, and silent-miss is the exact class this gate exists to
#     prevent. The deny prompts the operator to fetch + push manually.
#   - git rev-list origin/<branch>..HEAD --count > 0
#
# Hook ordering: this hook is wired AFTER pre-merge-rebase.sh in
# .claude/settings.json so that any auto-sync push performed by the rebase
# hook has already updated the upstream tracking ref by the time this gate
# runs. T11 in the test file enforces the ordering.

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
# Single jq fork via @sh-escaped eval. Pattern from guardrails.sh — halves
# hot-path overhead vs. two forks. @sh shell-escapes every value so any
# attacker-controlled bytes in .tool_input.command / .cwd land as quoted
# strings (no command injection through this surface).
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Word-boundary anchored regex prevents false positives on substrings like
# `echo "gh pr merge example"`. Chain-operator clause `(^|&&|\|\||;)` catches
# chained invocations. Pattern matches the sibling pre-merge-rebase.sh verbatim.
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

# Validate WORK_DIR: absolute path AND existing directory. Defense against
# argument injection — `git -C "-x"` would treat the arg as a flag (CWE-88).
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
# --is-inside-work-tree returns non-zero outside a repo AND in a bare-repo
# context, subsuming a separate `rev-parse --git-dir` check.
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  exit 0
fi

# `symbolic-ref --short -q HEAD` returns the branch name and exits non-zero
# on detached HEAD (vs. `rev-parse --abbrev-ref HEAD` which returns literal
# "HEAD" and exits zero). The non-zero exit makes the empty-string fallthrough
# unambiguous across git versions.
CURRENT_BRANCH=$(git -C "$WORK_DIR" symbolic-ref --short -q HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi
# Refname validation: defense against argument injection into git fetch /
# rev-list. Git's check-ref-format disallows leading `-`, but a manually
# crafted ref could bypass that. Allow only standard refname characters.
if [[ ! "$CURRENT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$CURRENT_BRANCH" == -* ]]; then
  exit 0
fi

# No upstream tracking ref → branch was never pushed → out of this gate's
# scope (gh pr merge against a never-pushed branch fails earlier with a
# clearer error than anything we could emit).
if ! git -C "$WORK_DIR" rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1; then
  exit 0
fi

# Refresh remote-tracking ref. Redirect BOTH stdout and stderr (learning
# 2026-03-03: git fetch prints progress to stderr; mixing with hook JSON
# corrupts the harness-side `jq` parse).
#
# Fail-CLOSED: a fetch failure means the local view of origin/<branch>
# cannot be trusted, and the bug this gate exists to prevent IS the silent-
# miss class. Failing-open here re-introduces the regression window. The
# deny prompts the operator to retry the fetch (which usually surfaces the
# underlying network issue) and re-issue.
if ! git -C "$WORK_DIR" fetch origin "$CURRENT_BRANCH" >/dev/null 2>&1; then
  emit_incident "wg-ship-push-before-merge" deny \
    "Before \`gh pr merge\`, all local commits MUST be" "$CMD"
  jq -n --arg branch "$CURRENT_BRANCH" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: `git fetch origin " + $branch + "` failed; cannot verify unpushed commits against a stale tracking ref. Run `git fetch origin " + $branch + " && git push` manually, then re-issue.")
    }
  }'
  exit 0
fi

# Count unpushed commits. --count returns a single integer; empty range
# returns 0, no error.
UNPUSHED_COUNT=$(git -C "$WORK_DIR" rev-list "origin/${CURRENT_BRANCH}..HEAD" --count 2>/dev/null || echo 0)
UNPUSHED_COUNT=${UNPUSHED_COUNT:-0}

if [[ "$UNPUSHED_COUNT" -le 0 ]]; then
  # Sibling-convention silent exit on pass — additionalContext on every
  # gh pr merge is noise, not signal.
  exit 0
fi

# Cap commit list at 10 entries and 80 chars/line. Sanitize:
#   - C0 control bytes except \t and \n (CWE-117 log injection)
#   - DEL (0x7f)
#   - Unicode line / paragraph separators U+2028 / U+2029 (CWE-117; see
#     knowledge-base learning on unicode-line-separator log injection)
#   - Long subjects truncated to defend against CWE-532 secret leakage in
#     `WIP: testing with SUPABASE_KEY=...` commit titles rendered to the
#     operator transcript.
# 50-char rule-text prefix gate enforced by lib/incidents.sh; matched by T12.
COMMIT_LIST=$(git -C "$WORK_DIR" log "origin/${CURRENT_BRANCH}..HEAD" --oneline 2>/dev/null \
  | head -10 \
  | LC_ALL=C tr -d '\000-\010\013-\037\177' \
  | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g' \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

emit_incident "wg-ship-push-before-merge" deny \
  "Before \`gh pr merge\`, all local commits MUST be" "$CMD"

jq -n \
  --arg n "$UNPUSHED_COUNT" \
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
