#!/usr/bin/env bash
# Shared Approach A isolation assert for Phase 2 open-weight dogfood (#6546).
# Sourced by grok-gpu-bootstrap.sh and grok-measure.sh.
# Fail-closed: requires `ss`; dies on any non-loopback listener on :11434.
#
# Usage (source):
#   # shellcheck source=scripts/dogfood/assert-ollama-loopback.sh
#   source "$(dirname "$0")/assert-ollama-loopback.sh"
#   assert_ollama_loopback_listen
#   assert_config_base_url_loopback /path/to/config.toml   # optional path
set -euo pipefail

assert_ollama_loopback_listen() {
  local port="${OLLAMA_PORT:-11434}"
  if ! command -v ss >/dev/null 2>&1; then
    printf 'ERROR: ss (iproute2) required for Approach A loopback exclusivity assert — install iproute2\n' >&2
    return 1
  fi
  local lines
  lines="$(ss -lnt 2>/dev/null | grep -E "[:.]${port}\\b" || true)"
  if [[ -z "$lines" ]]; then
    # No listener yet — caller may still curl-health; not a public-bind fail.
    return 0
  fi
  # Allowlist: every listen line for this port must bind 127.0.0.1 or [::1] only.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if echo "$line" | grep -qE "0\\.0\\.0\\.0:${port}|\\*:${port}|\\[::\\]:${port}"; then
      printf 'ERROR: Ollama appears bound to a public interface on :%s — Approach A requires loopback only\n%s\n' "$port" "$line" >&2
      return 1
    fi
    # Host-specific non-loopback: Local Address column typically ends with :port
    if echo "$line" | grep -qE "[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+:${port}" \
      && ! echo "$line" | grep -qE "127\\.0\\.0\\.1:${port}"; then
      printf 'ERROR: Ollama listen is not loopback-only on :%s\n%s\n' "$port" "$line" >&2
      return 1
    fi
  done <<<"$lines"
  return 0
}

assert_config_base_url_loopback() {
  local cfg="${1:-}"
  if [[ -z "$cfg" || ! -f "$cfg" ]]; then
    return 0
  fi
  # Any base_url line must use 127.0.0.1 or localhost only.
  local bad
  bad="$(grep -E '^\s*base_url\s*=' "$cfg" 2>/dev/null | grep -vE '127\.0\.0\.1|localhost' || true)"
  if [[ -n "$bad" ]]; then
    printf 'ERROR: non-loopback base_url in %s (Approach B forbidden):\n%s\n' "$cfg" "$bad" >&2
    return 1
  fi
  return 0
}
