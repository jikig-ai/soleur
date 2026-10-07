#!/usr/bin/env bash
# Slice 1 local install. Prints the next session command. Does not add a
# marketplace, does not classify the session, and does not run hooks.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
plugin_dir="${repo_root}/plugins/soleur"

if ! command -v agent >/dev/null 2>&1; then
  printf '%s\n' "agent is not on PATH"
  exit 1
fi

printf '%s\n' "agent --plugin-dir ${plugin_dir}"
printf '%s\n' "This slice does not classify the session as cursor, does not run hooks, and does not block a commit."
