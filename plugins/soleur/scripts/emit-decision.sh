#!/usr/bin/env bash
#
# emit-decision.sh -- append one field-allowlisted decision record to
# .soleur/decisions.jsonl at the project git root.
#
# Usage:
#   emit-decision.sh --event route_decision --label work [--skill X] [--agent_domain D]
#   emit-decision.sh --event tool_invocation --label flag-list [--skill X]
#   emit-decision.sh --selfcheck
#
# NO-ECHO contract (the sole writer chokepoint -- everything funnels here):
# the record carries metadata ONLY. Never prompt text, args, file contents,
# repo names, or free-text reasons. `repo_hash` is a sha256 prefix of the git
# root path -- correlatable across runs, never the path itself.
#
# Portability contract: runs on tester machines (stock macOS). No flock,
# timeout, jq, python3, date -d, sed -i, stat, or readlink -f. bash 3.2-safe.
# A single `printf >>` under PIPE_BUF is atomic on POSIX -- no lock.
#
# Fail-open everywhere: exit 0 is the only exit. Kill switch:
# SOLEUR_DISABLE_DECISION_LOG=1 disables all writes.

set -uo pipefail

SOCK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "${SOLEUR_DISABLE_DECISION_LOG:-}" = "1" ] && exit 0

EVENT=""; LABEL=""; SKILL=""; AGENT_DOMAIN=""; SELFCHECK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --event)        EVENT="${2:-}"; shift 2 ;;
    --label)        LABEL="${2:-}"; shift 2 ;;
    --skill)        SKILL="${2:-}"; shift 2 ;;
    --agent_domain) AGENT_DOMAIN="${2:-}"; shift 2 ;;
    --selfcheck)    SELFCHECK=1; shift ;;
    *)              shift ;;   # unknown args are ignored: never fatal
  esac
done

# shellcheck source=plugins/soleur/scripts/resolve-git-root.sh
. "$SOCK_DIR/resolve-git-root.sh" 2>/dev/null || exit 0
[ -d "${GIT_ROOT:-}" ] || exit 0

if [ -n "$SELFCHECK" ]; then
  echo "SOLEUR_EMIT_OK"
  exit 0
fi

[ -n "$EVENT" ] || exit 0

# --- derived fields ---------------------------------------------------------

harness="unknown"
if [ -n "${CLAUDECODE:-}" ]; then
  harness="claude"
elif [ -n "${GROK_HOME:-}" ] || [ -n "${GROK_AGENT:-}" ] || [ -n "${GROK_DEFAULT_MODEL:-}" ] || [ -n "${GROK_SUBAGENTS:-}" ]; then
  harness="grok"
elif [ -n "${CODEX_THREAD_ID:-}" ]; then
  harness="codex"
elif [ -n "${DEVIN:-}" ] || [ -n "${DEVIN_HOME:-}" ]; then
  harness="devin"
fi

session_id="${CLAUDE_SESSION_ID:-${DEVIN_SESSION_ID:-${CODEX_THREAD_ID:-${GROK_SESSION_ID:-}}}}"
[ -n "$session_id" ] || session_id="unknown"

plugin_sha="unknown"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _sha="$(git -C "$CLAUDE_PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)"
  [ -n "$_sha" ] && plugin_sha="$_sha"
fi
[ "$plugin_sha" = "unknown" ] && {
  _sha="$(git -C "$SOCK_DIR/.." rev-parse --short HEAD 2>/dev/null)"
  [ -n "$_sha" ] && plugin_sha="$_sha"
}

repo_hash="unknown"
if command -v sha256sum >/dev/null 2>&1; then
  repo_hash="$(printf '%s' "$GIT_ROOT" | sha256sum | cut -c1-12)"
elif command -v shasum >/dev/null 2>&1; then
  repo_hash="$(printf '%s' "$GIT_ROOT" | shasum -a 256 | cut -c1-12)"
fi

# --- emit -------------------------------------------------------------------

SOLEUR_DIR="$GIT_ROOT/.soleur"
LOG="$SOLEUR_DIR/decisions.jsonl"

mkdir -p "$SOLEUR_DIR" 2>/dev/null || exit 0
[ -f "$SOLEUR_DIR/.gitignore" ] || printf '*\n' > "$SOLEUR_DIR/.gitignore" 2>/dev/null || true

# rotate at ~5 MB (wc -c is portable; stat is not)
if [ -f "$LOG" ]; then
  size="$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')"
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt 5242880 ]; then
    mv "$LOG" "$LOG.1" 2>/dev/null || true
  fi
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"

# minimal JSON-string escape: backslash and double-quote only (fields are
# allowlisted tokens, not free text -- reject anything containing a quote or
# backslash outright rather than escaping attacker text)
jesc() {
  case "$1" in
    *\"*|*\\*) printf '__REDACTED__' ;;
    *) printf '%s' "$1" ;;
  esac
}

printf '{"v":1,"ts":"%s","event":"%s","label":"%s","skill":"%s","agent_domain":"%s","harness":"%s","session_id":"%s","plugin_sha":"%s","repo_hash":"%s"}\n' \
  "$ts" "$(jesc "$EVENT")" "$(jesc "$LABEL")" "$(jesc "$SKILL")" "$(jesc "$AGENT_DOMAIN")" \
  "$harness" "$(jesc "$session_id")" "$(jesc "$plugin_sha")" "$repo_hash" >> "$LOG" 2>/dev/null || true

exit 0
