#!/usr/bin/env bash
# cloud-detect.sh -- the ONE local-vs-cloud classifier for Devin sessions (TR1).
#
# Emits exactly one token on stdout:
#   local                -- positive this-host, plugin-sourced local-session evidence
#   not-local:<reason>   -- everything else; consumers MUST fail closed on it
#
# Reasons, in priority order (first match wins):
#   no-devin-env       -- no DEVIN / DEVIN_HOME / DEVIN_PROJECT_DIR / DEVIN_PLUGIN_ROOT /
#                         DEVIN_DIR set (measured: cloud VMs expose only DEVIN_DIR +
#                         DEVIN_DISABLE_HISTEXPAND in exec shells — probe 2026-09-15)
#   sentinel-absent    -- no .devin/soleur-local-session under the git root (or no git repo/git)
#   malformed          -- sentinel exists but is not a JSON object or lacks host/hook_source
#   foreign-host       -- sentinel host != `hostname` (handoff copy / committed sentinel)
#   non-plugin-source  -- sentinel hook_source != "plugin" (repo-level SessionStart firing in
#                         cloud must never read as a local session)
#
# Exit status is ALWAYS 0 for a classification outcome: a classifier that errors
# fails OPEN at consumers, and fail-open is exactly the defect this script exists
# to kill. (Usage errors — unknown flags — exit 2; that is not a classification.)
#
# --banner: when classification is not-local, also emit a reason-aware capability
# banner to STDERR naming the absent surfaces (plugin subagents, SessionStart /
# SessionEnd hooks) and what still works (skills, AGENTS.md rules, MCP). Emits
# nothing extra when local. Callers are expected to gate on positive Devin
# identity before invoking --banner (the contract in devin/INSTRUCTIONS.md), so a
# Claude Code session never sees cloud banners.
#
# Sentinel shape (written by hooks/devin-session-start.sh):
#   {"host":"<hostname>","ts":"<ISO8601 utc>","hook_source":"plugin"|"repo"}
#
# Deliberately jq- and python3-free: both may be absent on a minimal cloud VM, so
# the flat JSON is parsed with grep/sed, whitespace-tolerant and fail-closed.

set -euo pipefail

BANNER=0
for arg in "$@"; do
  case "$arg" in
    --banner) BANNER=1 ;;
    *)
      echo "cloud-detect.sh: unknown argument: $arg" >&2
      echo "usage: cloud-detect.sh [--banner]" >&2
      exit 2
      ;;
  esac
done

# Extract a top-level string field from the flat sentinel JSON — whitespace
# tolerant, no jq/python3 dependency. Prints the value (possibly empty); never
# fails, because an unreadable/unparseable file must classify malformed, not die.
sentinel_field() {
  local field="$1" file="$2"
  grep -oE "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
    | head -n 1 \
    | sed -E 's/^[^:]*:[[:space:]]*"//; s/"[[:space:]]*$//' \
    || true
}

classify() {
  # 1. Devin session env must be present at all.
  if [[ -z "${DEVIN:-}" && -z "${DEVIN_HOME:-}" && -z "${DEVIN_PROJECT_DIR:-}" && -z "${DEVIN_PLUGIN_ROOT:-}" && -z "${DEVIN_DIR:-}" ]]; then
    echo "not-local:no-devin-env"
    return
  fi

  # 2. Sentinel under the git root; outside a repo (or without git) there is
  #    nowhere for it to live.
  local root sentinel
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  if [[ -z "$root" ]]; then
    echo "not-local:sentinel-absent"
    return
  fi
  sentinel="${root}/.devin/soleur-local-session"
  if [[ ! -f "$sentinel" ]]; then
    echo "not-local:sentinel-absent"
    return
  fi

  # 3. Content-bearing sentinel: must look like a JSON object and carry both
  #    required fields, else malformed.
  local content host hook_source
  content="$(cat "$sentinel" 2>/dev/null || true)"
  if [[ ! "$content" =~ ^[[:space:]]*\{ ]] || [[ ! "$content" =~ \}[[:space:]]*$ ]]; then
    echo "not-local:malformed"
    return
  fi
  host="$(sentinel_field host "$sentinel")"
  hook_source="$(sentinel_field hook_source "$sentinel")"
  if [[ -z "$host" || -z "$hook_source" ]]; then
    echo "not-local:malformed"
    return
  fi

  # 4. Host must match — a sentinel that travelled (handoff worktree copy, a
  #    commit in a user repo that doesn't gitignore .devin/) is not evidence of
  #    THIS host's session. Same `hostname` invocation as the write side.
  local this_host
  this_host="$(hostname 2>/dev/null || true)"
  if [[ -z "$this_host" || "$host" != "$this_host" ]]; then
    echo "not-local:foreign-host"
    return
  fi

  # 5. Source must be the plugin registration — a repo-level SessionStart hook
  #    firing on a cloud VM (the undocumented arm the probe checks) writes a
  #    matching-host sentinel, which must NOT read as local.
  if [[ "$hook_source" != "plugin" ]]; then
    echo "not-local:non-plugin-source"
    return
  fi

  echo "local"
}

# Reason-aware capability banner — stderr only, never stdout. Silence about
# absent surfaces is the failure class this feature exists to kill.
emit_banner() {
  local reason="$1" detail
  case "$reason" in
    no-devin-env)
      detail="no Devin session environment (DEVIN, DEVIN_HOME, DEVIN_PROJECT_DIR, DEVIN_PLUGIN_ROOT, DEVIN_DIR all unset)"
      ;;
    sentinel-absent)
      detail="no local-session sentinel at .devin/soleur-local-session (plugin SessionStart never ran here)"
      ;;
    malformed)
      detail="local-session sentinel is unreadable, not a JSON object, or missing host/hook_source"
      ;;
    foreign-host)
      detail="local-session sentinel was written by a different host (handoff copy or committed file)"
      ;;
    non-plugin-source)
      detail="local-session sentinel was written by a repo-level hook, not the plugin registration"
      ;;
    *)
      detail="unrecognized classification"
      ;;
  esac
  {
    printf '=== Soleur Cloud Mode — reduced-capability session ===\n'
    printf 'This Devin session is NOT running the local Soleur surface (reason: %s — %s).\n' "$reason" "$detail"
    printf 'Absent surfaces:   plugin subagents (run_subagent / Task agent fan-out), SessionStart hooks, SessionEnd hooks\n'
    printf 'Still available:   /soleur:* skills, AGENTS.md rules, MCP servers\n'
    printf 'Degrade path:      spawn-site skills run agent roles sequentially inline and disclose with\n'
    printf '                   "Reviewed-Coverage: sequential-fallback" in the deliverable\n'
    printf 'Secrets/prod:      reads and mutations require an explicit cloud acknowledgement first\n'
  } >&2
}

RESULT="$(classify)"
echo "$RESULT"
if [[ "$RESULT" != "local" && "$BANNER" -eq 1 ]]; then
  emit_banner "${RESULT#not-local:}"
fi
exit 0
