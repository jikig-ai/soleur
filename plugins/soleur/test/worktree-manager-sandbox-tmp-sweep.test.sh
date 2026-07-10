#!/usr/bin/env bash

# Tests for worktree-manager.sh cleanup_stale_sandbox_tmp() — the session-start
# sweep that reaps stale Claude Code Bash-sandbox temp the harness orphans directly
# under /tmp (no config lever exists to relocate/auto-clean it; verified 2026-07-11).
#
# Pins the two safety invariants that make an unconditional session-start sweep safe:
#   - AGE gate: a fresh (in-flight) sandbox dir is NEVER reaped, only stale ones;
#   - SIGNATURE gate: only known sandbox shapes (repo/apps/plugins/NOTICE/ssr child,
#     or claude-creds-copy*) are reaped — a random non-empty tmp dir another tool
#     owns is spared, and node-compile-cache (a reusable cache) is spared;
#   - PATTERN gate: only /tmp/<15+-char> children match, and reaping uses
#     find -delete / rmdir (never rm -rf), staying inside the repo rm-guardrail.
#
# The tmp root + age thresholds are env-overridable purely so this test can drive a
# synthesized fixture instead of the real /tmp.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-sandbox-tmp-sweep.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh cleanup_stale_sandbox_tmp() sweep ==="
echo ""

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Source the script inside a valid work-tree so the repo-readiness gate at the
#     top passes. The BASH_SOURCE==$0 guard means main() does NOT run on source. ---
WORKSPACE="$TMP/workspace"
git init -q -b main "$WORKSPACE"
git -C "$WORKSPACE" config user.email "test@test.local"
git -C "$WORKSPACE" config user.name "Test"
cd "$WORKSPACE"
# shellcheck source=/dev/null
source "$SCRIPT"

OLD_MTIME='2020-01-01T00:00:00'   # unambiguously stale vs any sane threshold

# Fixture tmp root the sweep operates on (NOT the real /tmp).
FAKE_TMP="$TMP/faketmp"
mkdir -p "$FAKE_TMP"

exists() { [[ -e "$1" ]] && echo true || echo false; }

# --- Build the fixture. A 15+-char basename is required to match the pattern gate.
#     Parent dir mtime is stamped LAST (adding a child bumps it), so the age gate
#     sees the intended value. ---

# (a) empty stale shell -> REAPED
mk_empty_stale="$FAKE_TMP/emptyStaleShell01"
mkdir -p "$mk_empty_stale"; touch -d "$OLD_MTIME" "$mk_empty_stale"

# (b) empty FRESH shell -> PRESERVED (in-flight safety; mtime = now)
mk_empty_fresh="$FAKE_TMP/emptyFreshShell01"
mkdir -p "$mk_empty_fresh"

# (c) stale repo-copy sandbox (plugins/ child) -> REAPED
mk_repo="$FAKE_TMP/repoCopySandbox01"
mkdir -p "$mk_repo/plugins"; touch -d "$OLD_MTIME" "$mk_repo"

# (d) stale ssr bundler dir -> REAPED
mk_ssr="$FAKE_TMP/ssrBundlerDir00001"
mkdir -p "$mk_ssr/ssr"; touch -d "$OLD_MTIME" "$mk_ssr"

# (e) stale creds copy (name-matched) -> REAPED
mk_creds="$FAKE_TMP/claude-creds-copy9"
mkdir -p "$mk_creds/.claude"; touch -d "$OLD_MTIME" "$mk_creds"

# (f) stale FRESH repo-copy -> PRESERVED (in-flight safety; mtime = now)
mk_repo_fresh="$FAKE_TMP/repoCopyFresh0001"
mkdir -p "$mk_repo_fresh/apps"

# (g) stale node-compile-cache -> SPARED (reusable cache, not a leak)
mk_ncc="$FAKE_TMP/node-compile-cache"
mkdir -p "$mk_ncc/v22.22.2-x64-abc"; touch -d "$OLD_MTIME" "$mk_ncc"

# (h) stale random NON-signature dir -> SPARED (unknown owner's data)
mk_other="$FAKE_TMP/unknownToolDir0001"
mkdir -p "$mk_other/somedata"; touch -d "$OLD_MTIME" "$mk_other"

# (i) short-name empty stale dir (< 15 chars) -> SPARED (pattern gate)
mk_short="$FAKE_TMP/shortEmpty"
mkdir -p "$mk_short"; touch -d "$OLD_MTIME" "$mk_short"

# --- Run the sweep against the fixture with default thresholds (60m empty / 24h stale).
set +e
SWEEP_OUT="$(SOLEUR_SANDBOX_TMP_ROOT="$FAKE_TMP" cleanup_stale_sandbox_tmp 2>"$TMP/sweep.err")"
SWEEP_RC=$?
set -e

echo "Test 1: stale empty shell reaped"
assert_eq "false" "$(exists "$mk_empty_stale")" "stale empty shell removed"

echo "Test 2: FRESH empty shell preserved (in-flight safety)"
assert_eq "true" "$(exists "$mk_empty_fresh")" "fresh empty shell preserved"

echo "Test 3: stale repo-copy sandbox reaped (plugins/ signature)"
assert_eq "false" "$(exists "$mk_repo")" "stale repo-copy removed"

echo "Test 4: stale ssr bundler dir reaped"
assert_eq "false" "$(exists "$mk_ssr")" "stale ssr dir removed"

echo "Test 5: stale creds-copy reaped (name signature)"
assert_eq "false" "$(exists "$mk_creds")" "stale creds-copy removed"

echo "Test 6: FRESH repo-copy preserved (in-flight safety)"
assert_eq "true" "$(exists "$mk_repo_fresh")" "fresh repo-copy preserved"

echo "Test 7: node-compile-cache spared (reusable cache, not a leak)"
assert_eq "true" "$(exists "$mk_ncc")" "node-compile-cache spared"

echo "Test 8: unknown non-signature dir spared (safety)"
assert_eq "true" "$(exists "$mk_other")" "unknown tool dir spared"

echo "Test 9: short-name dir spared (pattern gate: <15 chars)"
assert_eq "true" "$(exists "$mk_short")" "short-name dir spared"

echo "Test 10: summary line reports the reap counts"
assert_contains "$SWEEP_OUT" "Reaped" "summary line printed"
# 1 empty (a) + 3 stale (c,d,e) reaped this run.
assert_contains "$SWEEP_OUT" "1 empty + 3 stale" "counts: 1 empty + 3 stale"
assert_eq "0" "$SWEEP_RC" "sweep returns 0"

echo "Test 11: missing tmp root -> no-op, rc 0"
set +e
NOOP_OUT="$(SOLEUR_SANDBOX_TMP_ROOT="$TMP/does-not-exist" cleanup_stale_sandbox_tmp 2>&1)"
NOOP_RC=$?
set -e
assert_eq "0" "$NOOP_RC" "missing tmp root returns 0"
assert_eq "" "$NOOP_OUT" "missing tmp root prints nothing"

echo "Test 12: second run is idempotent (nothing left to reap, no summary)"
set +e
SECOND_OUT="$(SOLEUR_SANDBOX_TMP_ROOT="$FAKE_TMP" cleanup_stale_sandbox_tmp 2>&1)"
set -e
if [[ "$SECOND_OUT" == *"Reaped"* ]]; then
  echo "  FAIL: second run still reaped something"; FAIL=$((FAIL + 1))
else
  echo "  PASS: second run is a clean no-op"; PASS=$((PASS + 1))
fi

echo ""
print_results
