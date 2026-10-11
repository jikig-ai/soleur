#!/usr/bin/env bash
# Local install. Prints the next session command. Does not add a
# marketplace and does not run hooks.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
plugin_dir="${repo_root}/plugins/soleur"

if ! command -v agent >/dev/null 2>&1; then
  printf '%s\n' "agent is not on PATH"
  exit 1
fi

printf '%s\n' "agent --plugin-dir ${plugin_dir}"
printf '%s\n' "A nonempty CURSOR_INVOKED_AS classifies the session as cursor. This does not run hooks, and this does not block a commit."
