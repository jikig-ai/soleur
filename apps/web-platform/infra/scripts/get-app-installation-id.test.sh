#!/usr/bin/env bash
# Smoke probe for get-app-installation-id.sh.
#
# Verifies the script (a) exists, (b) is executable, and (c) when invoked
# with valid GITHUB_APP_ID + GITHUB_APP_PRIVATE_KEY in env, prints a
# numeric installation ID to stdout. This is an integration smoke probe,
# not a unit test — it hits the real /orgs/jikig-ai/installation endpoint.
#
# Invoke:
#   doppler run -p soleur -c prd -- bash apps/web-platform/infra/scripts/get-app-installation-id.test.sh
#
# Exit codes:
#   0 — script exists, executable, prints numeric ID.
#   1 — smoke probe failed (script missing, non-executable, or non-numeric output).
#   2 — env vars missing (skip; not a failure of the script itself).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/get-app-installation-id.sh"

# (a) exists
if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: script not found at $SCRIPT" >&2
  exit 1
fi

# (b) executable
if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: script not executable: $SCRIPT" >&2
  exit 1
fi

# (c) env vars present (skip cleanly if not — operator may run without doppler)
if [[ -z "${GITHUB_APP_ID:-}" || -z "${GITHUB_APP_PRIVATE_KEY:-}" ]]; then
  echo "SKIP: GITHUB_APP_ID / GITHUB_APP_PRIVATE_KEY not in env. Run under: doppler run -p soleur -c prd -- bash <this>" >&2
  exit 2
fi

# (d) invocation returns numeric ID
OUT="$("$SCRIPT" 2>&1 | tail -1)"
if [[ "$OUT" =~ ^[0-9]+$ ]]; then
  echo "PASS: installation_id=$OUT"
  exit 0
fi

echo "FAIL: script output was not numeric. Last line: $OUT" >&2
exit 1
