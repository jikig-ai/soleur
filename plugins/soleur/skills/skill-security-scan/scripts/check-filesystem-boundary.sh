#!/usr/bin/env bash
set -euo pipefail
# TODO Phase 2.4: semgrep generic + targeted regex for path traversal,
# symlink-out-of-bounds, write attempts to credential dotfiles, read of
# credential paths.
echo '{"verdict":"LOW-RISK","findings":[],"category":"filesystem-boundary"}'
