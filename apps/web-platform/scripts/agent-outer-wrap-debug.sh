#!/usr/bin/env bash
# agent-outer-wrap-debug.sh — operator reproduction entry for a failing
# outer-wrap spawn (#5863). Given a workspace path it rebuilds the production
# argv and drops you (or a command) inside the same namespace.
#
# Usage:
#   scripts/agent-outer-wrap-debug.sh <workspace-path> [command...]
#
# With no command it opens an interactive bash inside the wrap. The emitted
# argv is also logged per-spawn via `op:"tenant-outer-wrap"` (secrets-free by
# construction — nothing on argv is a secret).
set -euo pipefail

WS="${1:?usage: agent-outer-wrap-debug.sh <workspace-path> [command...]}"
shift || true
[ "${1:-}" = "--" ] && shift  # tolerate a literal `--` separator

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Arm F argv is mount-only; on a host where /usr/bin/bwrap carries no file
# caps (dev machines), the mountns still builds via the userns path.
EXTRA=()
# Pin /usr/bin/bwrap, never PATH — the #8752 shim's NEWUSER-deny filter
# exists to reject the INNER sandbox's argv, not measure ours.
BWRAP="${BWRAP_PATH:-/usr/bin/bwrap}"
if ! grep -q cap_sys_admin < <(getcap "$BWRAP" 2>/dev/null); then
  EXTRA=(--unshare-user)
fi

mapfile -t ARGV < <(cd "$REPO_ROOT" && bun -e '
  import { buildOuterWrapArgv } from "./apps/web-platform/server/agent-outer-wrap.ts";
  const argv = buildOuterWrapArgv({ workspacePath: process.argv[1] });
  process.stdout.write(argv.join("\n") + "\n");
' -- "$WS")

echo "+ $BWRAP ${EXTRA[*]} <${#ARGV[@]} setup args> ${*:-/bin/bash}" >&2
exec "$BWRAP" "${EXTRA[@]}" "${ARGV[@]}" "${@:-/bin/bash}"
