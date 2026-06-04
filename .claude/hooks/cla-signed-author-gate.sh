#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` / `gh pr merge` when any commit on
# the branch (origin/main..HEAD) is authored OR committed by the non-CLA-signed
# identity `noreply@anthropic.com`.
#
# wg-cla-signed-author-before-merge — the required `cla-check` CI status fails on
# any commit authored by an unsigned identity. SUBAGENTS that commit (e.g. the
# ux-design-lead agent's Pencil recovery-anchor stub) author as
# `Claude <noreply@anthropic.com>`, so a branch can pass local review yet block
# at merge time after a wasted CI cycle. This gate catches it BEFORE the cycle,
# with the filter-branch author-rewrite fix in the deny message. See
# knowledge-base/project/learnings/workflow-patterns/2026-06-04-subagent-commits-fail-cla-check.md
# (PR #4948 cla-check failure).
#
# PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command (string) — the bash command string
#   .cwd                (string) — absolute working directory
#
# Fail-open (exit 0 silently): missing/relative/nonexistent .cwd, bare-repo /
# non-worktree context, branch main/master/detached, refname fails validation,
# no upstream tracking ref (origin/<branch> absent — out of scope).
#
# Fail-closed (deny + emit_incident): any branch commit author/committer email
# equals noreply@anthropic.com.

set -eo pipefail
# -u (nounset) omitted: failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

UNSIGNED_EMAIL="noreply@anthropic.com"

INPUT=$(cat)
# Single jq fork via @sh-escaped eval (guardrails.sh pattern). @sh shell-escapes
# every value so attacker-controlled bytes land as quoted strings (no injection).
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "") WORK_DIR=\(.cwd // "")"' 2>/dev/null || echo 'CMD="" WORK_DIR=""')"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Fire on gh pr ready OR gh pr merge. Word-boundary + chain-operator anchored
# (matches sibling pre-merge-rebase.sh / ship-unpushed-commits-gate.sh style).
if ! echo "$CMD" | grep -qE '(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge)(\s|$)'; then
  exit 0
fi

# Validate WORK_DIR: absolute + existing dir (CWE-88 arg-injection defense).
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  exit 0
fi

CURRENT_BRANCH=$(git -C "$WORK_DIR" symbolic-ref --short -q HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi
# Refname validation (arg-injection defense into git rev-list).
if [[ ! "$CURRENT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$CURRENT_BRANCH" == -* ]]; then
  exit 0
fi

# No upstream → branch never pushed → out of scope (the merge fails earlier with
# a clearer error). Use the merge-base against origin/main as the commit range so
# the scan covers exactly the branch's own commits.
BASE_REF="origin/main"
git -C "$WORK_DIR" rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || exit 0

# Collect any branch commit whose AUTHOR or COMMITTER email is the unsigned id.
# %ae = author email, %ce = committer email; match either.
OFFENDERS=$(git -C "$WORK_DIR" log "${BASE_REF}..HEAD" --format='%h %ae %ce %s' 2>/dev/null \
  | awk -v e="$UNSIGNED_EMAIL" '$2 == e || $3 == e { print }' \
  | head -10 \
  | LC_ALL=C tr -d '\000-\010\013-\037\177' \
  | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g' \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

if [[ -z "$OFFENDERS" ]]; then
  exit 0
fi

emit_incident "wg-cla-signed-author-before-merge" deny \
  "Every branch commit MUST be authored by a CLA-sign" "$CMD"

FIX="FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
if [ \"\$GIT_AUTHOR_EMAIL\" = \"${UNSIGNED_EMAIL}\" ]; then export GIT_AUTHOR_NAME=\"<Your Name>\"; export GIT_AUTHOR_EMAIL=\"<you@domain>\"; fi
if [ \"\$GIT_COMMITTER_EMAIL\" = \"${UNSIGNED_EMAIL}\" ]; then export GIT_COMMITTER_NAME=\"<Your Name>\"; export GIT_COMMITTER_EMAIL=\"<you@domain>\"; fi
' ${BASE_REF}..HEAD   # then: git push --force-with-lease"

jq -n \
  --arg email "$UNSIGNED_EMAIL" \
  --arg offenders "$OFFENDERS" \
  --arg fix "$FIX" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: branch commit(s) authored by the non-CLA-signed identity " + $email + " — the required `cla-check` CI status will fail (typically a subagent commit, e.g. a Pencil recovery-anchor stub).\n\nOffending commits (h author committer subject):\n" + $offenders + "\n\nRewrite the author/committer to your CLA-signed identity, then re-push:\n" + $fix)
    }
  }'
exit 0
