#!/usr/bin/env bash
# cloud-detect.sh -- the ONE local-vs-cloud classifier for Devin sessions (TR1).
#
# Emits exactly one token on stdout:
#   local                -- positive this-host, plugin-sourced local-session evidence
#   not-local:<reason>   -- everything else; consumers MUST fail closed on it
#
# Reasons, in priority order (first match wins):
#   sentinel-absent    -- no .devin/soleur-local-session under the git root (or no git
#                         repo/git) on a box that IS Devin-marked (some DEVIN* var set)
#   no-devin-env       -- no sentinel AND no DEVIN / DEVIN_HOME / DEVIN_PROJECT_DIR /
#                         DEVIN_PLUGIN_ROOT / DEVIN_DIR set. This means "not a Devin
#                         session at all" — local Devin exec shells expose ZERO DEVIN*
#                         vars (probe 2026-09-15, both arms), so env cannot gate the
#                         `local` verdict; the sentinel carries it. Callers treat
#                         no-devin-env like `local` (a Claude Code session must not
#                         activate the cloud contract).
#   malformed          -- sentinel exists but is not a JSON object or lacks host/hook_source
#   foreign-host       -- sentinel host != `hostname` (handoff copy / committed sentinel)
#   non-plugin-source  -- sentinel hook_source != "plugin" (repo-level SessionStart firing in
#                         cloud must never read as a local session)
#   conflicting-evidence -- valid plugin-sourced, this-host sentinel on a box whose env
#                         marks it as a cloud VM (DEVIN_DIR / DEVIN_DISABLE_HISTEXPAND are
#                         measured cloud-only in exec shells). The upstream-convergence arm:
#                         if Cognition ships plugin-hook dispatch in cloud (#8160) before
#                         plugin subagents, the hook fires and writes a sentinel while the
#                         capability gap persists — that must NOT read as local.
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

# Any DEVIN* marker present — used only to pick the reason when the sentinel is
# missing; it never gates `local` (local exec shells expose no DEVIN* vars).
devin_env_present() {
  [[ -n "${DEVIN:-}" || -n "${DEVIN_HOME:-}" || -n "${DEVIN_PROJECT_DIR:-}" || -n "${DEVIN_PLUGIN_ROOT:-}" || -n "${DEVIN_DIR:-}" ]]
}

classify() {
  # 1. Sentinel under the git root; outside a repo (or without git) there is
  #    nowhere for it to live. Absent sentinel: Devin-marked box → sentinel-absent;
  #    no Devin env at all → no-devin-env (likely not a Devin session — callers
  #    proceed normally).
  local root sentinel
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  sentinel="${root:+$root/.devin/soleur-local-session}"
  if [[ -z "$root" || ! -f "$sentinel" ]]; then
    if devin_env_present; then
      echo "not-local:sentinel-absent"
    else
      echo "not-local:no-devin-env"
    fi
    return
  fi

  # 2. Content-bearing sentinel: must look like a JSON object and carry both
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

  # 3. Host must match — a sentinel that travelled (handoff worktree copy, a
  #    commit in a user repo that doesn't gitignore .devin/) is not evidence of
  #    THIS host's session. Same `hostname` invocation as the write side.
  local this_host
  this_host="$(hostname 2>/dev/null || true)"
  if [[ -z "$this_host" || "$host" != "$this_host" ]]; then
    echo "not-local:foreign-host"
    return
  fi

  # 4. Source must be the plugin registration — a repo-level SessionStart hook
  #    firing on a cloud VM (the undocumented arm the probe checks) writes a
  #    matching-host sentinel, which must NOT read as local.
  if [[ "$hook_source" != "plugin" ]]; then
    echo "not-local:non-plugin-source"
    return
  fi

  # 5. Conflicting evidence: everything above attests "plugin SessionStart fired
  #    on this host" — but a cloud-only env marker is present. If Cognition ships
  #    plugin-hook dispatch in cloud (#8160) before plugin subagents, this arm is
  #    what keeps the gap fail-closed instead of silently reading as local.
  if [[ -n "${DEVIN_DIR:-}" || -n "${DEVIN_DISABLE_HISTEXPAND:-}" ]]; then
    echo "not-local:conflicting-evidence"
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
    conflicting-evidence)
      detail="plugin-sourced sentinel on a cloud-marked VM (DEVIN_DIR set) — plugin hooks may partially dispatch here; the capability gap persists"
      ;;
    *)
      detail="unrecognized classification"
      ;;
  esac
  {
    printf '=== Soleur Cloud Mode — reduced-capability session ===\n'
    printf 'This Devin session is NOT running the local Soleur surface (reason: %s — %s).\n' "$reason" "$detail"
    printf 'Absent surfaces:   plugin subagents (run_subagent / Task agent fan-out), ALL hooks\n'
    printf '                   (SessionStart / SessionEnd / PreToolUse / PostToolUse / Stop — incl.\n'
    printf '                   the credential guard, guardrails, and DONE-marker stop-gate)\n'
    printf 'Still available:   /soleur:* skills, AGENTS.md rules, MCP servers\n'
    printf 'Degrade path:      spawn-site skills run agent roles sequentially inline and disclose with\n'
    printf '                   "Reviewed-Coverage: sequential-fallback" in the deliverable\n'
    printf 'Secrets/prod:      reads and mutations require an explicit cloud acknowledgement first\n'
  } >&2
}

RESULT="$(classify)"
echo "$RESULT"
# --banner is suppressed for no-devin-env as well as local: that reason means
# "no Devin markers at all" (e.g. a Claude Code session), and the banner asserts
# "This Devin session…" — emitting it there would be a false claim.
if [[ "$RESULT" != "local" && "$RESULT" != "not-local:no-devin-env" && "$BANNER" -eq 1 ]]; then
  emit_banner "${RESULT#not-local:}"
fi
exit 0
