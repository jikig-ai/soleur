#!/usr/bin/env bash
# community-router.sh — thin dispatch router for community platform scripts
# Single source of truth for platform detection and dispatch.
# Adding a new platform: add one entry to PLATFORMS and create the script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Platform registry: name|script|required_env_vars (comma-separated)|auth_command
# Empty env_vars + empty auth_command = always enabled (e.g., HN uses public API)
PLATFORMS=(
  "discord|discord-community.sh|DISCORD_BOT_TOKEN,DISCORD_GUILD_ID|"
  "github|github-community.sh||gh auth status 2>/dev/null"
  "x|x-community.sh|X_API_KEY,X_API_SECRET,X_ACCESS_TOKEN,X_ACCESS_TOKEN_SECRET|"
  "bsky|bsky-community.sh|BSKY_HANDLE,BSKY_APP_PASSWORD|"
  "linkedin|linkedin-community.sh|LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN|"
  "hn|hn-community.sh||"
)

check_auth() {
  local env_vars="$1" auth_cmd="$2"

  # If auth command specified, run it (suppress all output)
  if [[ -n "$auth_cmd" ]]; then
    eval "$auth_cmd" &>/dev/null && return 0 || return 1
  fi

  # If env vars specified, check all are set
  if [[ -n "$env_vars" ]]; then
    IFS=',' read -ra vars <<< "$env_vars"
    for var in "${vars[@]}"; do
      [[ -n "${!var:-}" ]] || return 1
    done
    return 0
  fi

  # No env vars and no auth command = always enabled
  return 0
}

cmd_platforms() {
  local name script env_vars auth_cmd status
  printf "%-10s %-8s %s\n" "PLATFORM" "STATUS" "SCRIPT"
  printf "%-10s %-8s %s\n" "--------" "------" "------"
  for entry in "${PLATFORMS[@]}"; do
    IFS='|' read -r name script env_vars auth_cmd <<< "$entry"
    if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
      status="missing"
    elif check_auth "$env_vars" "$auth_cmd"; then
      status="enabled"
    else
      status="disabled"
    fi
    printf "%-10s %-8s %s\n" "$name" "$status" "$script"
  done
}

dispatch() {
  local target="$1"; shift
  local name script env_vars auth_cmd
  for entry in "${PLATFORMS[@]}"; do
    IFS='|' read -r name script env_vars auth_cmd <<< "$entry"
    if [[ "$name" == "$target" ]]; then
      if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
        echo "Error: script '$script' not found for platform '$name'." >&2
        exit 1
      fi
      exec "$SCRIPT_DIR/$script" "$@"
    fi
  done
  echo "Error: unknown platform '$target'." >&2
  local names=()
  for entry in "${PLATFORMS[@]}"; do
    names+=("${entry%%|*}")
  done
  echo "Available platforms: ${names[*]}" >&2
  exit 1
}

main() {
  local command="${1:-}"
  shift || true

  case "$command" in
    platforms) cmd_platforms ;;
    "") echo "Usage: community-router.sh <platform> <command> [args...]" >&2
        echo "       community-router.sh platforms" >&2
        exit 1 ;;
    *) dispatch "$command" "$@" ;;
  esac
}

main "$@"
