#!/usr/bin/env bash
# Rule-incident telemetry helpers for PreToolUse hooks.
#
# Emits one JSON line per deny or bypass to a single flock-guarded file at
# <repo-root>/.claude/.rule-incidents.jsonl. Called BEFORE the hook's
# `jq -n '{hookSpecificOutput: ...}' && exit 0` response so the hook contract
# with Claude Code is unchanged (see ADR-2 in
# knowledge-base/project/plans/2026-04-14-feat-rule-utility-scoring-plan.md).
#
# Source from a hook via:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"
#
# Fire-and-forget: never blocks the hook (all jq invocations on external input
# wrapped in `2>/dev/null || true`, per learning 2026-03-18).

# --- Repo-root resolution --------------------------------------------------
# BASH_SOURCE[0] is the path to THIS file regardless of how it was sourced.
# From .claude/hooks/lib/incidents.sh, the repo root is three dirs up.
_incidents_repo_root() {
  (cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)
}

# --- emit_incident <rule_id> <event_type> <prefix> [command_snippet] -------
# event_type ∈ {deny, bypass}
# prefix: first ~50 chars of the rule text (redundant — aggregator uses
#         rule_id as the primary join key — but keeps forensic context if
#         AGENTS.md is ever rebased with new ids).
emit_incident() {
  local rule_id="${1:-}" event="${2:-}" prefix="${3:-}" cmd="${4:-}"
  [[ -z "$rule_id" || -z "$event" ]] && return 0

  local repo_root file ts
  repo_root="$(_incidents_repo_root)" || return 0
  file="$repo_root/.claude/.rule-incidents.jsonl"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Create parent dir (first run) and file (needed by flock on the file itself).
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  [[ -f "$file" ]] || : > "$file" 2>/dev/null || return 0

  # flock on the file itself; jq -nc emits single-line JSON.
  local line
  line=$(jq -nc \
    --arg ts "$ts" \
    --arg r "$rule_id" \
    --arg e "$event" \
    --arg p "$prefix" \
    --arg c "$cmd" \
    '{timestamp:$ts, rule_id:$r, event_type:$e, rule_text_prefix:$p, command_snippet:$c}' \
    2>/dev/null) || return 0

  (
    flock -x 9
    printf '%s\n' "$line" >&9
  ) 9>>"$file" 2>/dev/null || true
}

# --- detect_bypass <tool> <command> ---------------------------------------
# Echoes the rule_id of the bypassed rule when the command uses a v1 bypass
# flag. Empty output means no bypass detected.
#
# v1 scope is deliberately minimal to avoid false positives (see
# plan ADR-2 and R3):
#   --no-verify   → cq-never-skip-hooks
#   LEFTHOOK=0    → cq-lefthook-worktree-hang
# Deferred to v2: --force on main, --no-gpg-sign, --amend after a prior deny.
#
# Patterns anchor on bash-adjacent context ("git ", "git\t", LEFTHOOK=0 at
# command start or after a chain operator) to skip substrings embedded in
# echoed strings, heredoc bodies, PR body text, etc.
detect_bypass() {
  local cmd="${2:-}"
  # --no-verify: only recognize when it's a flag to a git invocation in the
  # command. Matches "git ... --no-verify" and "git -C foo commit --no-verify"
  # but not 'echo "avoid --no-verify"' or 'gh pr create --body "don\'t --no-verify"'.
  if [[ "$cmd" =~ (^|[[:space:]]|\&\&|\|\||\;)[[:space:]]*git[[:space:]].*--no-verify ]]; then
    echo "cq-never-skip-hooks"
    return
  fi
  # LEFTHOOK=0: recognize only when it's an environment prefix at the start
  # of the command (standard env-assign-before-command position) or after a
  # chain operator. Not `echo "LEFTHOOK=0 is bad"`.
  if [[ "$cmd" =~ (^|\&\&|\|\||\;)[[:space:]]*LEFTHOOK=0[[:space:]] ]]; then
    echo "cq-when-lefthook-hangs-in-a-worktree-60s"
    return
  fi
}
