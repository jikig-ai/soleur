#!/usr/bin/env bash
# version-banner.sh — SessionStart (matcher: startup) one-line Soleur version banner.
#
# Prints ONE JSON object on stdout: {"systemMessage": "Soleur <vX.Y.Z | commit <sha12>>[ — newer release vA.B.C available]"}
# `systemMessage` is shown to the user and costs zero model tokens (no additionalContext).
#
# The banner itself is ON by default and makes NO network call. Only the "newer release"
# check is opt-in: with SOLEUR_UPDATE_CHECK=1 (exactly `1`; `0`, empty and any other value
# are off) the hook reads the per-install release cache and, when that cache is stale,
# missing or corrupt, spawns ONE detached background refresh. The hook itself never touches
# the network and never waits on it: it prints the cached answer now.
#
# Skips silently (exit 0, no output) when CLAUDE_PLUGIN_ROOT is unset, on the non-Claude
# harness markers hooks/welcome-hook.sh uses (CODEX_THREAD_ID, PLUGIN_ROOT), when
# SOLEUR_DISABLE_VERSION_BANNER=1, and when the installed version cannot be determined.
#
# Fails open: every path exits 0 and any error prints nothing. Plugin hooks are GLOBAL
# (they fire in every project), so a banner that errors or blocks would hit every session.
set -uo pipefail
# `set -u` aborts with status 1 and no ERR trap on an unbound variable; force a clean exit.
trap 'exit 0' EXIT

# Refresh dedupe: an atomic mkdir lock under the cache dir. It is deliberately never
# removed by the refresh; it simply ages out, which also rate-limits repeated attempts
# while offline (one attempt per LOCK_TTL_S instead of one per session).
LOCK_TTL_S=600

json_escape() { # escape a string for use inside a JSON string literal
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"
  s="${s//$'\r'/ }"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

# Spawn at most one detached background refresh. Never blocks, never prints.
spawn_refresh() { # <resolver> <cache_dir>
  local resolver="$1" cache_dir="$2" lock now mtime v
  # The resolver reports an absolute cache dir or none (HOME unset, relative XDG).
  [[ "$cache_dir" == /* ]] || return 0
  lock="$cache_dir/refresh.lock"
  ( umask 077; mkdir -p "$cache_dir" ) 2>/dev/null || return 0
  if [[ -d "$lock" ]]; then
    now="$(date +%s)"
    mtime="$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || echo "$now")"
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime="$now"
    # A future-dated lock (clock change) counts as expired, like a future-dated cache.
    if (( now - mtime >= LOCK_TTL_S || mtime > now + 60 )); then rmdir "$lock" 2>/dev/null || true; fi
  fi
  # mkdir is the atomic claim: of two concurrent starts exactly one succeeds.
  ( umask 077; mkdir "$lock" ) 2>/dev/null || return 0
  # The child gets an allowlisted environment (no inherited secrets) and stdin, stdout and
  # stderr all on /dev/null, or the hook's pipes stay open through the child and the
  # session waits on it.
  local -a childenv=(env -i "PATH=${PATH:-/usr/bin:/bin}" "HOME=${HOME:-}")
  for v in XDG_CACHE_HOME CLAUDE_PLUGIN_ROOT TMPDIR SOLEUR_FETCH_TIMEOUT \
           http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY; do
    [[ -n "${!v:-}" ]] && childenv+=("$v=${!v}")
  done
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "${childenv[@]}" bash "$resolver" --latest --refresh </dev/null >/dev/null 2>&1 &
  else
    nohup "${childenv[@]}" bash "$resolver" --latest --refresh </dev/null >/dev/null 2>&1 &
  fi
  disown 2>/dev/null || true
  return 0
}

main() {
  [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] || return 0
  [[ -n "${CODEX_THREAD_ID:-}" || -n "${PLUGIN_ROOT:-}" ]] && return 0
  [[ "${SOLEUR_DISABLE_VERSION_BANNER:-}" == "1" ]] && return 0

  local here resolver mode="--installed"
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  resolver="$here/../scripts/plugin-version.sh"
  [[ -f "$resolver" ]] || return 0
  # One resolver call per start: --cached-latest also prints the installed keys, reads the
  # cache only and makes no network call.
  [[ "${SOLEUR_UPDATE_CHECK:-}" == "1" ]] && mode="--cached-latest"

  local k v source="" version="" commit="" cache="" cache_dir="" latest="" relation="" label=""
  while IFS='=' read -r k v; do
    case "$k" in
      source) source="$v" ;; version) version="$v" ;; commit) commit="$v" ;;
      cache) cache="$v" ;; cache_dir) cache_dir="$v" ;; latest) latest="$v" ;; relation) relation="$v" ;;
    esac
  done < <(bash "$resolver" "$mode" 2>/dev/null)
  case "$source" in
    manifest) [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0; label="v$version" ;;
    commit)   [[ "$commit" =~ ^[0-9a-f]{12}$ ]] || return 0; label="commit $commit" ;;
    *) return 0 ;;
  esac

  local msg="Soleur $label"

  if [[ "$mode" == "--cached-latest" ]]; then
    # A stale value is still shown below; the refresh only helps the NEXT session.
    case "$cache" in stale|missing|corrupt) spawn_refresh "$resolver" "$cache_dir" ;; esac

    if [[ "$relation" == "older" && "$latest" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      local warn=1
      if [[ "$source" == "manifest" ]]; then
        # Never warn a downgrade: re-check the order here rather than trust the cached relation alone.
        [[ "$(bash "$resolver" --cmp "$version" "${latest#v}" 2>/dev/null)" == "older" ]] || warn=0
      fi
      (( warn )) && msg="$msg — newer release $latest available"
    fi
  fi

  printf '{"systemMessage": "%s"}\n' "$(json_escape "$msg")"
  return 0
}

main "$@" 2>/dev/null
exit 0
