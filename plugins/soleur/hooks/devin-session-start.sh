#!/usr/bin/env bash
set -euo pipefail

[[ -n "${DEVIN:-}" || -n "${DEVIN_HOME:-}" || -n "${DEVIN_PROJECT_DIR:-}" || -n "${DEVIN_PLUGIN_ROOT:-}" ]] || exit 0
SOLEUR_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
jq -n --arg root "$SOLEUR_PLUGIN_ROOT" \
  --rawfile instructions "$SOLEUR_PLUGIN_ROOT/devin/INSTRUCTIONS.md" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext:
    ("Soleur plugin root: " + $root + "\n" + $instructions)}}'

# --- Local-session sentinel (Soleur Cloud Mode, FR1) ---
# Content-bearing proof-of-local for scripts/cloud-detect.sh: SessionStart is the
# one plugin hook event documented absent in Devin Cloud, so a plugin-sourced
# sentinel on this host is what distinguishes a local Devin session. The write is
# UNCONDITIONAL under the Devin-env guard above — no plugins/soleur dir check:
# user repos consuming via requiredPlugins don't vendor the plugin dir, and a
# scope guard there would invert detection into permanent false-cloud.
#
# hook_source records which registration fired, because a repo-level SessionStart
# firing on a cloud VM writes a matching-host sentinel that must NOT classify
# local. Resolution order:
#   1. SOLEUR_HOOK_SOURCE env override (a registration may inject it explicitly)
#   2. CLAUDE_PLUGIN_ROOT set and resolving to this script's plugin root → plugin
#   3. otherwise → repo (the fail-safe direction for detection)
#
# Canonical copy of test-helpers.sh's assert_fixture_dir — P1a requires every
# tracked copy be byte-equal, and the P1b scanner recognises ONLY this name.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
{
  _sentinel_root="$(git rev-parse --show-toplevel 2>/dev/null)" && \
  _sentinel_source="${SOLEUR_HOOK_SOURCE:-}" && \
  if [[ -z "$_sentinel_source" ]]; then
    _sentinel_source="repo"
    if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && \
       [[ "$(cd "${CLAUDE_PLUGIN_ROOT}" 2>/dev/null && pwd)" == "$SOLEUR_PLUGIN_ROOT" ]]; then
      _sentinel_source="plugin"
    fi
  fi && \
  mkdir -p "$_sentinel_root/.devin" && \
  _sentinel="$_sentinel_root/.devin/soleur-local-session" && \
  # Dual registration (plugin hooks.json + repo .devin/config.json) fires this
  # hook twice on local sessions; write order is undefined. A repo-sourced write
  # must never mask an existing plugin-sourced sentinel on this host — that
  # sentinel is proof-of-local, and masking it reads as permanent false-cloud.
  if [[ "$_sentinel_source" == "repo" && -f "$_sentinel" ]] && \
     grep -q '"hook_source"[[:space:]]*:[[:space:]]*"plugin"' "$_sentinel" 2>/dev/null; then
    :
  else
    assert_fixture_dir "$_sentinel" && \
    printf '{"host":"%s","ts":"%s","hook_source":"%s"}\n' \
      "$(hostname)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$_sentinel_source" \
      > "$_sentinel"
  fi
} || true
