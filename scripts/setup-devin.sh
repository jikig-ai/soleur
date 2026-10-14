#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
common_dir="$(git -C "$source_root" rev-parse --path-format=absolute --git-common-dir)"
if [[ "$(basename "$common_dir")" != ".git" ]]; then
  echo "Unsupported repository layout: expected a shared .git directory, got $common_dir" >&2
  exit 1
fi
shared_root="$(dirname "$common_dir")"
source_config="$source_root/.devin/config.json"
target_config="$shared_root/.devin/config.json"

if [[ -L "$shared_root/.devin" || -L "$target_config" ]]; then
  echo "Refusing to install Devin configuration through a symlink: $target_config" >&2
  exit 1
fi
if [[ -e "$target_config" ]] && ! cmp -s "$source_config" "$target_config"; then
  echo "Existing Devin configuration differs; merge the Soleur hook tables before retrying: $target_config" >&2
  exit 1
fi
if [[ ! -e "$target_config" ]]; then
  mkdir -p "$shared_root/.devin"
  install -m 0644 "$source_config" "$target_config"
fi

devin plugins install --local "$source_root/plugins/soleur" -y
echo "Soleur installed. Start a new Devin session and review plugin hooks in /hooks."
