#!/usr/bin/env bash
# Freeze edit-lock control + reader helper for the guardrails.sh PreToolUse hook.
#
# A "freeze" scopes all Write/Edit tool calls to a single allowed path prefix:
# while a freeze is active, guardrails.sh DENIES any file edit whose resolved
# path falls outside that prefix. This file owns the freeze STATE (a single
# worktree-local, gitignored line) and the reader guardrails.sh sources.
#
# Agent-native: the CLI is Bash-invocable, so an agent can freeze/clear exactly
# as an operator can (`bash .claude/hooks/lib/freeze-lock.sh set <path>`).
#
# Dual use:
#   - Sourced by guardrails.sh: exposes `freeze_active_prefix` (reader only).
#   - Run as a CLI: `set <path> | status | clear`.
#
# State file: <repo-root>/.claude/.freeze-lock — a SINGLE line holding the
# absolute allowed path prefix. Runtime state (gitignored, per the
# .claude/.rule-incidents* precedent).
#
# Fail-open contract (OQ2 blast-radius): absent, empty, or malformed state
# (not exactly one well-formed absolute-path line) reads as NO active freeze —
# `freeze_active_prefix` echoes nothing. A corrupt state file must NEVER brick
# every edit. Only a VALID active freeze denies out-of-scope edits.
#
# Repo-root resolution mirrors lib/incidents.sh (`cd -P` + `pwd -P`, three dirs
# up from lib/). Tests set FREEZE_LOCK_REPO_ROOT to redirect state off the
# operator's real .claude/.freeze-lock — same override shape as
# INCIDENTS_REPO_ROOT.

# --- Repo-root + state-file resolution ------------------------------------
_freeze_repo_root() {
  if [[ -n "${FREEZE_LOCK_REPO_ROOT:-}" ]]; then
    echo "$FREEZE_LOCK_REPO_ROOT"
    return 0
  fi
  # BASH_SOURCE[0] is THIS file regardless of how it was sourced. From
  # .claude/hooks/lib/freeze-lock.sh the repo root is three dirs up.
  (cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)
}

_freeze_state_file() {
  echo "$(_freeze_repo_root)/.claude/.freeze-lock"
}

# --- freeze_active_prefix (reader; sourced by guardrails.sh) ---------------
# Echoes the active absolute allowed-path prefix ONLY when the state file holds
# exactly one well-formed absolute path; otherwise echoes nothing (fail-open).
# Always returns 0 so a caller running under `set -e` never aborts on a read.
freeze_active_prefix() {
  local f; f="$(_freeze_state_file)"
  [[ -n "$f" && -f "$f" ]] || return 0
  local lines=()
  mapfile -t lines < "$f" 2>/dev/null || return 0
  # Malformed unless exactly one line.
  [[ ${#lines[@]} -eq 1 ]] || return 0
  local p="${lines[0]}"
  # Trim a trailing CR (CRLF-authored/foreign-edited state) and trailing
  # whitespace before validating. Without this, `/path\r` or `/path   ` reads as
  # a valid-looking active prefix that no realpath output can ever match →
  # every edit denied (a fail-CLOSED brick, the opposite of the fail-open
  # contract). Trimming makes such a state activate the INTENDED prefix instead.
  p="${p%$'\r'}"
  p="${p%"${p##*[![:space:]]}"}"
  # Non-empty and absolute (leading slash). A relative or blank line is
  # malformed → fail-open.
  [[ -n "$p" && "$p" == /* ]] || return 0
  echo "$p"
}

# --- CLI verbs -------------------------------------------------------------
freeze_set() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "usage: freeze-lock.sh set <path>" >&2
    return 2
  fi
  # realpath -m resolves symlinks + `..` and does NOT require the path to exist,
  # so the freeze prefix is canonical and matches the same-resolution check in
  # guardrails.sh.
  local abs; abs="$(realpath -m "$target" 2>/dev/null)" || abs=""
  if [[ -z "$abs" ]]; then
    echo "freeze-lock: cannot resolve path: $target" >&2
    return 2
  fi
  local f; f="$(_freeze_state_file)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  printf '%s\n' "$abs" > "$f"
  echo "freeze active: edits restricted to $abs"
}

freeze_status() {
  local p; p="$(freeze_active_prefix)"
  if [[ -n "$p" ]]; then echo "$p"; else echo "inactive"; fi
}

freeze_clear() {
  local f; f="$(_freeze_state_file)"
  rm -f "$f" 2>/dev/null || true
  echo "freeze cleared"
}

# --- CLI dispatch (only when executed directly, not when sourced) ----------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  cmd="${1:-status}"
  case "$cmd" in
    set)    shift; freeze_set "$@" ;;
    status) freeze_status ;;
    clear)  freeze_clear ;;
    *)      echo "usage: freeze-lock.sh {set <path>|status|clear}" >&2; exit 2 ;;
  esac
fi
