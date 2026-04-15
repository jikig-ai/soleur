#!/usr/bin/env bash
# Boot the apps/web-platform dev server with Doppler env + correct CWD.
#
# Usage:
#   ./scripts/dev.sh          # binds to PORT=3000
#   ./scripts/dev.sh 3001     # binds to PORT=3001 (use when 3000 is held
#                             # by a concurrent worktree)
#
# Why this wrapper exists (see learning
# knowledge-base/project/learnings/2026-04-15-next-server-actions-allowed-origins-port-fallback.md):
# three failure modes hit agents repeatedly when they hand-roll the command
#   (a) skipping `doppler run`  -> "Missing SUPABASE_URL" at boot
#   (b) `doppler run -- tsx ...` -> `tsx` not on PATH outside npm scripts
#   (c) relying on CWD from a prior Bash call -> shell state does not persist
# This script collapses the three gotchas into one entry point.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
APP_DIR="${REPO_ROOT}/apps/web-platform"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: ${APP_DIR} not found — run from a checkout that contains apps/web-platform" >&2
  exit 1
fi

export PORT="${1:-3000}"

cd "${APP_DIR}"
exec doppler run -p soleur -c dev -- npm run dev
