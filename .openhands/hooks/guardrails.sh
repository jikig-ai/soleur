#!/usr/bin/env bash
# PreToolUse guardrail hook for terminal AND file_editor tools (OpenHands port).
# Terminal: blocks commits on main, rm -rf on worktrees, a hardened recursive-
# delete ownership proof (repo/worktree roots, $HOME, /, .git-bearing checkouts),
# --delete-branch with active worktrees, commits with conflict markers, gh issue
# create without --milestone, git stash in worktrees.
# file_editor: enforces the freeze edit-lock (edits restricted to an active
# freeze prefix). Registered on both matchers in .openhands/hooks.json.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Input: HookEvent JSON on stdin with tool_input.command (terminal) /
# tool_input.path (file_editor) and working_dir.
#
# Corresponding prose rules: see .claude/hooks/guardrails.sh

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
HOOK_CWD=$(echo "$INPUT" | jq -r '.working_dir // ""')
# OpenHands file_editor uses "path"; fall back to "file_path" for compatibility.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.path // .tool_input.file_path // ""')

# Freeze reader — cross-tree to the shared helper. freeze-lock.sh resolves the
# freeze state file from its OWN BASH_SOURCE (three dirs up from
# .claude/hooks/lib/ = repo root), so both harnesses read the SAME state. Source
# FAIL-SOFT: a missing/broken freeze helper must never disarm the guards below.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/lib/freeze-lock.sh" 2>/dev/null || true

deny() {
  jq -n --arg reason "$1" '{"decision":"deny","reason":$reason}'
  exit 2
}

# guardrails:freeze-edit-lock — directory-scoped edit-lock for file_editor.
# Gated on BOTH file_path present AND command empty: a terminal payload carries
# .tool_input.command and no path, so this is skipped for terminal calls and
# cannot shadow the delete guards (TR3); requiring `-z COMMAND` too is defense-
# in-depth against a future payload forwarding both fields. Fail-open when no
# active freeze or a malformed state file (OQ2 blast-radius).
if [[ -n "$FILE_PATH" && -z "$COMMAND" ]] && declare -f freeze_active_prefix >/dev/null 2>&1; then
  ALLOWED=$(freeze_active_prefix) || ALLOWED=""
  if [[ -n "$ALLOWED" ]]; then
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    case "$RESOLVED" in
      "$ALLOWED"|"$ALLOWED"/*) : ;;   # inside the allowed prefix — allow
      *) deny "BLOCKED: a freeze is active — edits are restricted to $ALLOWED. Target $RESOLVED is outside the allowed prefix. Edit within the prefix, or clear the freeze: bash .claude/hooks/lib/freeze-lock.sh clear" ;;
    esac
  fi
  # file_editor payloads carry no terminal command — the sentinels below do not
  # apply. Exit here so no path a terminal command reaches carries a bare exit.
  exit 0
fi

# guardrails:block-commit-on-main — Block git commit on main branch
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit'; then
  GIT_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    GIT_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  elif [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    BRANCH=$(git -C "$HOOK_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    deny "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
if echo "$COMMAND" | grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/'; then
  deny "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
fi

# guardrails:block-recursive-delete — hardened ownership proof for rm -rf.
# Runs AFTER the narrow .worktrees/ gate (kept as a fast subset). Model:
# default-allow-except-protected. DENY when an rm -rf target RESOLVES onto the
# repo root, a git worktree root (or ancestor), $HOME, /, or a .git-bearing
# checkout — catching symlink/relative-path obfuscation the literal grep misses.
# The realpath here is a DENY-DECISION resolver (strengthens the block), the
# OPPOSITE direction from the constitution.md bulk-cleanup delete-executor rule
# (which forbids realpath before removal). See .claude/hooks/guardrails.sh for
# the canonical implementation + the full SCOPE note (lexical pre-exec guard:
# covers literal/relative/symlink targets, the common protected shell refs
# ~/$HOME/${HOME}/$PWD/${PWD}, and bare/path-qualified/escaped/sudo/env/command
# `rm`; does NOT see arbitrary $VAR, aliases, xargs/find-exec, or glob-expanded
# entries). This OpenHands port detects on the raw $COMMAND (it has no
# strip_command_bodies helper), so — consistent with its sibling terminal gates
# — a commit MESSAGE documenting `rm -rf` on a feature branch can over-match; the
# tokenizer (which acts only on a real `rm`/`*/rm` token) prevents false-denies
# in the common quoted-body case.
if echo "$COMMAND" | grep -qE '(^|[[:space:]]|&&|\|\||;|\|)[^[:space:]]*rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)'; then
  _rd_cwd=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    _rd_cwd=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    _rd_cwd=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$_rd_cwd" ] || [ ! -d "$_rd_cwd" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then _rd_cwd="$HOOK_CWD"; else _rd_cwd="$PWD"; fi
  fi

  _protected_roots=()
  while IFS= read -r _wl; do
    [[ "$_wl" == worktree\ * ]] && _protected_roots+=("${_wl#worktree }")
  done < <(git -C "$_rd_cwd" worktree list --porcelain 2>/dev/null || true)
  [[ -n "${HOME:-}" ]] && _protected_roots+=("$HOME")

  _rd_toks=()
  mapfile -t _rd_toks < <(printf '%s\n' "$COMMAND" | xargs -n1 2>/dev/null) || true
  _in_rm=0
  _targets=()
  _ti=0
  while (( _ti < ${#_rd_toks[@]} )); do
    _t="${_rd_toks[$_ti]}"
    _ti=$((_ti + 1))
    _t="${_t#\\}"   # normalize a backslash-escaped `\rm` → `rm`
    case "$_t" in
      rm|*/rm)           _in_rm=1; continue ;;   # bare, /bin/rm, ./rm, \rm
      "&&"|"||"|";"|"|") _in_rm=0; continue ;;
    esac
    [[ "$_in_rm" == 1 && "$_t" != -* ]] && _targets+=("$_t")
  done

  _tj=0
  while (( _tj < ${#_targets[@]} )); do
    _tg="${_targets[$_tj]}"
    _tj=$((_tj + 1))
    # Expand the common protected shell references before realpath (see canonical
    # hook). xargs has already stripped surrounding quotes.
    # shellcheck disable=SC2088  # case PATTERNS matching the literal `~` token.
    case "$_tg" in
      "~")          _tg="${HOME:-}" ;;
      "~/"*)        _tg="${HOME:-}/${_tg#\~/}" ;;
      '$HOME'|'${HOME}') _tg="${HOME:-}" ;;
      '$HOME/'*)    _tg="${HOME:-}/${_tg#\$HOME/}" ;;
      '${HOME}/'*)  _tg="${HOME:-}/${_tg#'${HOME}'/}" ;;
      '$PWD'|'${PWD}')   _tg="$_rd_cwd" ;;
      '$PWD/'*)     _tg="$_rd_cwd/${_tg#\$PWD/}" ;;
      '${PWD}/'*)   _tg="$_rd_cwd/${_tg#'${PWD}'/}" ;;
    esac
    _res=$( (cd "$_rd_cwd" 2>/dev/null && realpath -m "$_tg" 2>/dev/null) || echo "" )
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
        if [[ "$_res" == "$_pr" || "$_pr" == "$_res"/* ]]; then _deny=1; break; fi
      done
    fi
    [[ "$_deny" == 0 && -e "$_res/.git" ]] && _deny=1
    if [[ "$_deny" == 1 ]]; then
      deny "BLOCKED: rm -rf resolves onto a protected location ($_res). Repo roots, git worktree roots, \$HOME, /, and any .git-bearing checkout are protected. Delete a specific non-protected subdirectory instead, or use git worktree remove."
    fi
  done
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
if echo "$COMMAND" | grep -qE 'gh\s+pr\s+merge.*--delete-branch'; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    deny "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)'; then
  CONFLICT_MARKERS_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$CONFLICT_MARKERS_DIR" ] || [ ! -d "$CONFLICT_MARKERS_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      CONFLICT_MARKERS_DIR="$HOOK_CWD"
    fi
  fi
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    STAGED_DIFF=$(git -C "$CONFLICT_MARKERS_DIR" diff --cached 2>/dev/null || true)
  else
    STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
  fi
  if echo "$STAGED_DIFF" | grep -qE '^\+(<{7}|={7}|>{7})'; then
    deny "BLOCKED: Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create'; then
  if ! echo "$COMMAND" | grep -qF -- '--milestone'; then
    deny "BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash in worktrees
if echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+stash'; then
  STASH_GUARD_DIR=""
  if echo "$COMMAND" | grep -qE '^\s*cd\s+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif echo "$COMMAND" | grep -qoE 'git\s+-C\s+\S+'; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$STASH_GUARD_DIR" ] || [ ! -d "$STASH_GUARD_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      STASH_GUARD_DIR="$HOOK_CWD"
    fi
  fi
  RESOLVE_DIR="${STASH_GUARD_DIR:-.}"
  if echo "$(cd "$RESOLVE_DIR" 2>/dev/null && pwd)" | grep -qF '.worktrees'; then
    deny "BLOCKED: git stash in worktrees is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
  fi
fi

# All checks passed
exit 0
