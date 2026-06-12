#!/usr/bin/env bash
# PreToolUse guardrail hook for Bash commands.
# Blocks: commits on main, rm -rf on worktrees, --delete-branch with active worktrees,
# commits with conflict markers in staged content, gh issue create without --milestone,
# git stash in worktrees.
# NOTE: When adding or modifying guards, update the corresponding prose rule comments below.
#
# Corresponding prose rules:
#   guardrails:block-commit-on-main — constitution.md "Never allow agents to work directly on the default branch"
#   guardrails:block-rm-rf-worktrees — constitution.md "Never rm -rf on the current directory, a worktree path, or the repo root"
#   guardrails:block-delete-branch — constitution.md "Never use --delete-branch with gh pr merge"
#   guardrails:block-conflict-markers — constitution.md "grep staged content for conflict markers"
#   guardrails:require-milestone — constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"
#   guardrails:block-stash-in-worktrees — AGENTS.md "Never git stash in worktrees"

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
# Single jq fork: @sh shell-escapes both fields so eval is safe for embedded
# quotes, newlines ($'\n' ANSI-C form), and shell metacharacters. Previously
# two jq forks ran on every Bash tool invocation; collapsing to one halves
# the hook's hot-path overhead.
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "")"' 2>/dev/null || echo 'COMMAND="" TOOL_NAME=""')"
# Belt-and-braces against set -u: a partial eval (jq succeeded on one
# field, failed on the other) could leave either variable undefined.
: "${COMMAND:=}"
: "${TOOL_NAME:=}"

# Derive a quote/heredoc-stripped view of the command ONCE (one perl fork per
# Bash invocation, alongside the existing jq + grep overhead). PHRASE-detecting
# gates (require-milestone, block-stash) scan $SCAN so a commit whose MESSAGE
# documents `gh issue create` / `git stash` is not mistaken for the real
# command (#5192). Gates that fire on `git commit` itself keep scanning
# $COMMAND — a commit that mentions "git commit" in its body still IS a commit.
SCAN=$(strip_command_bodies "$COMMAND")

# Bypass preflight — records (does NOT block) when a known bypass flag is used.
# Scope: --no-verify, -c core.hooksPath=…, HUSKY=0, --no-gpg-sign,
# -c commit.gpgsign=false, LEFTHOOK=0. See detect_bypass in lib/incidents.sh.
_bypass_rid=$(detect_bypass "$TOOL_NAME" "$COMMAND")
if [[ -n "$_bypass_rid" ]]; then
  emit_incident "$_bypass_rid" "bypass" "${COMMAND:0:50}" "$COMMAND"
fi

# guardrails:block-commit-on-main — Block git commit on main branch
# Match git commit at start of string OR after chain operators (&&, ||, ;)
# so chained commands like "git add && git commit" are caught.
# Scans $COMMAND (NOT $SCAN): this gates the REAL commit, so a message body
# mentioning "git commit" still IS a commit — no false-positive class here.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  # Resolve the branch from the command's working directory, not the hook's CWD.
  # resolve_command_cwd (lib/incidents.sh) covers: "cd /worktree && ...",
  # "git -C /worktree commit", and hook-input .cwd. Falls through to the
  # hook's own CWD if none resolve.
  GIT_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    emit_incident "guardrails-block-commit-on-main" "deny" "Never allow agents to work directly on default branch" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
# Match rm with recursive-force flags followed by a worktree path as an argument.
# Uses a single pattern to avoid false positives when .worktrees/ appears in
# unrelated text (e.g., inside a gh issue comment body or heredoc).
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
  emit_incident "guardrails-block-rm-rf-worktrees" "deny" "Never rm -rf on a worktree path" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
    }
  }'
  exit 0
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh pr merge --delete-branch` is not mistaken for
# one (#5192 sweep — same phrase-class FP as require-milestone).
if echo "$SCAN" | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    emit_incident "guardrails-block-delete-branch" "deny" "Never use --delete-branch with gh pr merge" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
# Matches git commit and git merge --continue (which internally commits).
# Allows optional -C <path> between git and commit/merge.
# Checks only added lines (^\+) to avoid blocking removal of markers.
# CWD resolution mirrors guardrails:block-commit-on-main via resolve_command_cwd.
# Scans $COMMAND (NOT $SCAN): gates the REAL commit / merge --continue.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)'; then
  CONFLICT_MARKERS_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    STAGED_DIFF=$(git -C "$CONFLICT_MARKERS_DIR" diff --cached 2>/dev/null || true)
  else
    STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
  fi
  if echo "$STAGED_DIFF" | grep -qE '^\+(<{7}|={7}|>{7})'; then
    emit_incident "guardrails-block-conflict-markers" "deny" "Resolve conflicts before committing" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."
      }
    }'
    exit 0
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh issue create` is not mistaken for one (#5192).
# The --repo/--milestone flag checks below intentionally read $COMMAND: on a
# real create those flags live OUTSIDE quotes and survive the strip, and on a
# commit-body FP this `if` never fires so they are never reached.
if echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'; then
  # Exempt issue creation targeting an EXTERNAL repo (--repo owner/name where
  # owner is not our org). The constitution backlog-hygiene rule applies only to
  # OUR issues; external/vendor repos (e.g. upstream bug reports) have their own
  # milestone sets and forcing --milestone would fail against them.
  # Quote-aware tokenization: `xargs -n1` honors shell quoting, so a `--repo`
  # substring embedded in a quoted --title/--body value is NOT mistaken for a
  # real flag (it stays inside one token), and a quoted `--repo "jikig-ai/soleur"`
  # is recognized correctly. Only a standalone --repo/-R/--repo=/-R= token counts.
  # Fail toward GATING: if xargs errors (unbalanced quotes → empty tokens) or no
  # external target is found, the milestone gate stays on. If our own repo appears
  # in ANY --repo/-R flag, the gate stays on regardless of other tokens.
  _repo_toks=(); _our_repo=0; _ext_repo=0
  mapfile -t _repo_toks < <(printf '%s\n' "$COMMAND" | xargs -n1 2>/dev/null) || true
  _ri=0
  while (( _ri < ${#_repo_toks[@]} )); do
    _rt="${_repo_toks[$_ri]}"; _rv=""
    case "$_rt" in
      --repo|-R) _rv="${_repo_toks[$((_ri + 1))]:-}" ;;
      --repo=*)  _rv="${_rt#--repo=}" ;;
      -R=*)      _rv="${_rt#-R=}" ;;
    esac
    case "$_rv" in
      jikig-ai/*) _our_repo=1 ;;
      */*)        _ext_repo=1 ;;
    esac
    _ri=$((_ri + 1))
  done
  # Gate only when no external target was named AND our own repo wasn't named
  # (our repo appearing anywhere wins, so an external token can't ungate it).
  if [[ "$_our_repo" == 1 || "$_ext_repo" == 0 ]] && ! echo "$COMMAND" | grep -qF -- '--milestone'; then
    emit_incident "guardrails-require-milestone" "deny" "gh issue create must include --milestone" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: gh issue create must include --milestone. Default to '\''Post-MVP / Later'\'' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash unconditionally
# Unconditional: CWD detection is unreliable in subagent contexts where the shell
# CWD is a worktree but no explicit "cd" prefix appears in the command. Blocking
# git stash everywhere is safe — AGENTS.md requires "commit WIP first" and there
# is no legitimate automated use case for git stash in this repo.
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting "never git stash" is not mistaken for one (#5192).
if echo "$SCAN" | grep -qE '(^|&&|\|\||;)\s*git\s+stash'; then
  emit_incident "hr-never-git-stash-in-worktrees" "deny" "Never git stash in worktrees" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: git stash is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
    }
  }'
  exit 0
fi

# All checks passed
exit 0
