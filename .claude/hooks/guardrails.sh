#!/usr/bin/env bash
# PreToolUse guardrail hook for Bash AND Write|Edit commands.
# Bash: blocks commits on main, rm -rf on worktrees, a hardened recursive-delete
# ownership proof (repo/worktree roots, $HOME, /, .git-bearing checkouts),
# --delete-branch with active worktrees, commits with conflict markers in staged
# content, gh issue create without --milestone, git stash in worktrees.
# Write|Edit: enforces the freeze edit-lock (edits restricted to an active
# freeze prefix). Registered on both matchers in .claude/settings.json.
# NOTE: When adding or modifying guards, update the corresponding prose rule comments below.
#
# Corresponding prose rules:
#   guardrails:block-commit-on-main — constitution.md "Never allow agents to work directly on the default branch"
#   guardrails:block-rm-rf-worktrees — constitution.md "Never rm -rf on the current directory, a worktree path, or the repo root"
#   guardrails:block-recursive-delete — constitution.md "Never rm -rf a target that resolves onto a repo/worktree root, $HOME, /, or a .git-bearing checkout"
#   guardrails:freeze-edit-lock — constitution.md "When a freeze is active, deny Write/Edit outside the allowed path prefix"
#   guardrails:block-delete-branch — constitution.md "Never use --delete-branch with gh pr merge"
#   guardrails:block-conflict-markers — constitution.md "grep staged content for conflict markers"
#   guardrails:require-milestone — constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"
#   guardrails:block-stash-in-worktrees — AGENTS.md "Never git stash in worktrees"

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"
# shellcheck source=lib/freeze-lock.sh
# Provides freeze_active_prefix (reader) for the freeze edit-lock branch below.
# Sourced (not run): its CLI-dispatch guard is BASH_SOURCE[0]==$0, which is
# false here, so no verb runs on source. FAIL-SOFT (|| true): freeze is an
# OPTIONAL feature — a missing/broken freeze helper must NEVER disarm the
# critical delete/commit/stash guards below (which do not depend on it). The
# freeze branch itself is additionally gated on `declare -f freeze_active_prefix`.
source "$(dirname "${BASH_SOURCE[0]}")/lib/freeze-lock.sh" 2>/dev/null || true

INPUT=$(cat)
# Single jq fork: @sh shell-escapes each field so eval is safe for embedded
# quotes, newlines ($'\n' ANSI-C form), and shell metacharacters. Previously
# two jq forks ran on every Bash tool invocation; collapsing to one halves
# the hook's hot-path overhead. FILE_PATH is extracted here too so the freeze
# edit-lock branch (Write/Edit) shares the same single fork.
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") TOOL_NAME=\(.tool_name // "") FILE_PATH=\(.tool_input.file_path // "")"' 2>/dev/null || echo 'COMMAND="" TOOL_NAME="" FILE_PATH=""')"
# Belt-and-braces against set -u: a partial eval (jq succeeded on one
# field, failed on another) could leave a variable undefined.
: "${COMMAND:=}"
: "${TOOL_NAME:=}"
: "${FILE_PATH:=}"

# guardrails:freeze-edit-lock — directory-scoped edit-lock for file-editing
# tools (Write/Edit). Placed ABOVE the Bash sentinels and gated on file_path
# presence: a Bash payload carries .tool_input.command and NO file_path, so this
# branch is skipped entirely for Bash rm-rf calls and CANNOT shadow the delete
# guards (TR3 — payload-shape disjointness). Fail-open: no active freeze (or a
# malformed state file) => freeze_active_prefix echoes nothing => edit allowed
# (OQ2 blast-radius — a parse bug must not brick every edit).
if [[ -n "$FILE_PATH" ]] && declare -f freeze_active_prefix >/dev/null 2>&1; then
  ALLOWED=$(freeze_active_prefix)
  if [[ -n "$ALLOWED" ]]; then
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    case "$RESOLVED" in
      "$ALLOWED"|"$ALLOWED"/*) : ;;   # inside the allowed prefix — allow
      *)
        emit_incident "guardrails-freeze-edit-lock" "deny" "Edit outside the active freeze prefix" "$FILE_PATH"
        jq -n --arg p "$RESOLVED" --arg a "$ALLOWED" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",            permissionDecision: "deny",
            permissionDecisionReason: ("BLOCKED: a freeze is active — edits are restricted to " + $a + ". Target " + $p + " is outside the allowed prefix. Edit within the prefix, or clear the freeze: bash .claude/hooks/lib/freeze-lock.sh clear")
          }
        }'
        exit 0
        ;;
    esac
  fi
  # Write/Edit payloads do not carry a Bash command — the sentinels below
  # (all keyed on $COMMAND) do not apply. Exit here so no Bash-reachable path
  # ever hits a bare `exit 0` that could shadow the delete guard (TR3).
  exit 0
fi

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

# guardrails:block-recursive-delete — hardened ownership proof for rm -rf.
# Runs AFTER the narrow .worktrees/ gate above (kept as a fast, regression-
# covered subset). Model: default-allow-except-protected — every non-protected
# recursive delete (rm -rf build/, node_modules, /tmp/x) passes through; the
# hardening only ADDS deny cases for a protected class that a literal-substring
# grep misses: a symlink- or relative-path-obfuscated target that RESOLVES onto
# the repo root, a git worktree root (or an ancestor of either), $HOME, /, or a
# .git-bearing checkout.
#
# The realpath here is a DENY-DECISION resolver (resolving symlinks makes the
# guard STRONGER — it catches `rm -rf ./link` → repo root). This is the OPPOSITE
# direction from constitution.md:306, which forbids realpath in a delete-
# EXECUTOR (resolving before removal weakens it, CWE-59). Different code paths;
# do not conflate them.
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;|\|)[[:space:]]*(sudo[[:space:]]+)?rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)'; then
  # Resolve the command's working directory so relative targets resolve the same
  # way the shell would (cd <dir> && ..., git -C <dir>, hook .cwd, else $PWD).
  _rd_cwd=$(resolve_command_cwd "$COMMAND" "$INPUT")
  [[ -n "$_rd_cwd" && -d "$_rd_cwd" ]] || _rd_cwd="$PWD"

  # Enumerate protected roots. git worktree list yields the main checkout + all
  # worktree roots; best-effort (git may not resolve from a non-repo cwd). $HOME
  # is always protected.
  _protected_roots=()
  while IFS= read -r _wl; do
    [[ "$_wl" == worktree\ * ]] && _protected_roots+=("${_wl#worktree }")
  done < <(git -C "$_rd_cwd" worktree list --porcelain 2>/dev/null || true)
  [[ -n "${HOME:-}" ]] && _protected_roots+=("$HOME")

  # Quote-aware tokenization (xargs -n1 honors shell quoting; chain operators
  # &&/||/;/| survive as their own tokens). Walk rm invocations, collecting
  # non-flag args as delete targets and resetting at each chain boundary.
  _rd_toks=()
  mapfile -t _rd_toks < <(printf '%s\n' "$COMMAND" | xargs -n1 2>/dev/null) || true
  _in_rm=0
  _targets=()
  _ti=0
  while (( _ti < ${#_rd_toks[@]} )); do
    _t="${_rd_toks[$_ti]}"
    _ti=$((_ti + 1))
    case "$_t" in
      rm)                _in_rm=1; continue ;;
      "&&"|"||"|";"|"|") _in_rm=0; continue ;;
    esac
    [[ "$_in_rm" == 1 && "$_t" != -* ]] && _targets+=("$_t")
  done

  _tj=0
  while (( _tj < ${#_targets[@]} )); do
    _tg="${_targets[$_tj]}"
    _tj=$((_tj + 1))
    _res=$( (cd "$_rd_cwd" 2>/dev/null && realpath -m "$_tg" 2>/dev/null) || echo "" )
    # Fail-closed: an unresolvable target still gets checked in its raw form.
    [[ -z "$_res" ]] && _res="$_tg"
    _deny=0
    [[ "$_res" == "/" ]] && _deny=1
    [[ "$_deny" == 0 && -n "${HOME:-}" && "$_res" == "$HOME" ]] && _deny=1
    if [[ "$_deny" == 0 ]]; then
      _pi=0
      while (( _pi < ${#_protected_roots[@]} )); do
        _pr="${_protected_roots[$_pi]}"
        _pi=$((_pi + 1))
        [[ -z "$_pr" ]] && continue
        # Deny when the target IS a protected root OR an ancestor of one
        # (rm -rf of a parent dir destroys the checkout under it).
        if [[ "$_res" == "$_pr" || "$_pr" == "$_res"/* ]]; then _deny=1; break; fi
      done
    fi
    # A .git entry at the target root means it is a repository checkout.
    [[ "$_deny" == 0 && -e "$_res/.git" ]] && _deny=1
    if [[ "$_deny" == 1 ]]; then
      emit_incident "guardrails-block-recursive-delete" "deny" "Never rm -rf a protected root or checkout" "$COMMAND"
      jq -n --arg t "$_res" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",          permissionDecision: "deny",
          permissionDecisionReason: ("BLOCKED: rm -rf resolves onto a protected location (" + $t + "). Repo roots, git worktree roots, $HOME, /, and any .git-bearing checkout are protected. Delete a specific non-protected subdirectory instead, or use git worktree remove.")
        }
      }'
      exit 0
    fi
  done
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
