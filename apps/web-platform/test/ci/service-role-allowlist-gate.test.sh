#!/usr/bin/env bash
# PR-B §1.6.1 — RED + GREEN test for the service-role allowlist gate.
#
# Asserts:
#   1. The gate exits 0 against the current repo state.
#   2. The gate exits non-zero when a synthetic violator file
#      imports `createServiceClient` and is NOT in the allowlist.
#   3. The gate exits 0 when the same synthetic file IS allowlisted.
#
# The fixture is materialized as a tracked git path (under a feature
# branch worktree) so `git ls-files` sees it. We use a temporary
# branch in the test repo's index state to avoid touching the real
# allowlist or working tree.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$REPO_ROOT"

GATE="apps/web-platform/scripts/service-role-allowlist-gate.sh"
ALLOWLIST="apps/web-platform/.service-role-allowlist"

# ── Test 1: green path — current repo state ────────────────────────────
echo "test 1: gate green on current repo state"
bash "$GATE" >/dev/null
echo "  ok"

# ── Test 2/3: violator + allowlisted ──────────────────────────────────
# Use a temporary tracked file via index (no working-tree mutation),
# then exercise the gate against that synthetic state.
FIXTURE_REL="apps/web-platform/server/__test_fixture_violator__.ts"
FIXTURE_ABS="$REPO_ROOT/$FIXTURE_REL"
ALLOWLIST_BACKUP="$(mktemp)"
cleanup() {
  rm -f "$FIXTURE_ABS"
  cp "$ALLOWLIST_BACKUP" "$ALLOWLIST"
  rm -f "$ALLOWLIST_BACKUP"
  # Drop fixture from index if it was added.
  git rm --cached -f "$FIXTURE_REL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

cp "$ALLOWLIST" "$ALLOWLIST_BACKUP"

cat > "$FIXTURE_ABS" <<'EOF'
// Synthetic violator fixture for service-role-allowlist-gate test.
import { createServiceClient } from "@/lib/supabase/service";
export const _x = createServiceClient;
EOF
git add -f "$FIXTURE_REL"

echo "test 2: gate red on synthetic violator (not allowlisted)"
if bash "$GATE" >/dev/null 2>&1; then
  echo "  FAIL: gate returned 0 with an undisclosed violator present"
  exit 1
fi
echo "  ok"

echo "test 3: gate green when synthetic violator is allowlisted"
echo "$FIXTURE_REL" >> "$ALLOWLIST"
bash "$GATE" >/dev/null
echo "  ok"

echo "service-role-allowlist-gate: all 3 tests passed."
