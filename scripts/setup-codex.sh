#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
common_dir="$(git -C "$source_root" rev-parse --path-format=absolute --git-common-dir)"
if [[ "$(basename "$common_dir")" != ".git" ]]; then
  echo "Unsupported repository layout: expected a shared .git directory, got $common_dir" >&2
  exit 1
fi
shared_root="$(dirname "$common_dir")"
source_config="$source_root/.codex/config.toml"
target_config="$shared_root/.codex/config.toml"

if [[ -L "$shared_root/.codex" || -L "$target_config" ]]; then
  echo "Refusing to install Codex configuration through a symlink: $target_config" >&2
  exit 1
fi
if [[ -e "$target_config" ]] && ! cmp -s "$source_config" "$target_config"; then
  echo "Existing Codex configuration differs; merge the Soleur hook tables before retrying: $target_config" >&2
  exit 1
fi
if [[ ! -e "$target_config" ]]; then
  mkdir -p "$shared_root/.codex"
  install -m 0644 "$source_config" "$target_config"
fi

codex plugin marketplace add "$source_root"
codex plugin add soleur@soleur
echo "Soleur installed. Start a new Codex session and review project and plugin hooks in /hooks."
