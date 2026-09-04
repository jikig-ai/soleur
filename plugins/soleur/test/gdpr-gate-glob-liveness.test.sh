#!/usr/bin/env bash
# gdpr-gate-glob-liveness.test.sh — Guard 2's second chokepoint (#7710).
#
# The scan-completion line in gdpr-gate.sh witnesses "the scan ran and matched
# nothing". It structurally CANNOT witness "the hook never ran": a line
# emitted by the script is silent precisely when the script does not execute.
#
# If the `gdpr-gate-advisory` glob in lefthook.yml stops matching regulated
# paths, lefthook prints `(skip)`, the script is never invoked, and NO line of
# any kind is emitted. Every in-script assertion stays green. This repo has
# shipped that trap twice (2026-03-21-lefthook-gobwas-glob-double-star.md), and
# gobwas `**` semantics — `**` matches 1+ intermediate dirs, never 0+ — make it
# easy to reintroduce with an edit that reads as a simplification.
#
# So this test drives the REAL lefthook binary over the REAL lefthook.yml with
# a materialised regulated path staged, and asserts the command actually ran.
#
# Run: bash plugins/soleur/test/gdpr-gate-glob-liveness.test.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LEFTHOOK_YML="$REPO_ROOT/lefthook.yml"

echo "=== gdpr-gate glob-liveness tests ==="
echo ""

if ! command -v lefthook >/dev/null 2>&1; then
  echo "  SKIP: lefthook binary not on PATH — cannot exercise the glob"
  SKIPPED=$((SKIPPED + 1))
  print_results
fi

assert_file_exists "$LEFTHOOK_YML" "lefthook.yml exists"

# Build an isolated repo carrying ONLY the gdpr-gate-advisory stanza and the
# real script, so the probe cannot be perturbed by (or perturb) sibling hooks.
SANDBOX="$(mktemp -d -t gdpr-glob.XXXXXXXX)"
assert_fixture_dir "$SANDBOX"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

# Extract the live glob list for `gdpr-gate-advisory` from the real
# lefthook.yml. Reading the real file is the point: a hand-copied glob list in
# this test would pass while the shipped one rotted.
GLOBS="$(awk '
  /^    gdpr-gate-advisory:/ { in_cmd=1; next }
  in_cmd && /^    [a-z]/ { in_cmd=0 }
  in_cmd && /^        - "/ { print }
' "$LEFTHOOK_YML")"

GLOB_COUNT="$(printf '%s\n' "$GLOBS" | grep -c '^        - "' || true)"
if (( GLOB_COUNT < 5 )); then
  echo "  FAIL: extracted $GLOB_COUNT globs for gdpr-gate-advisory (expected >= 5) — the awk range is broken, not the glob"
  FAIL=$((FAIL + 1))
  print_results
else
  echo "  PASS: extracted $GLOB_COUNT globs for gdpr-gate-advisory from the live lefthook.yml"
  PASS=$((PASS + 1))
fi

build_sandbox() {
  # $1 = the glob block to install (allows the mutation case to narrow it)
  rm -rf "$SANDBOX/repo"
  mkdir -p "$SANDBOX/repo"
  git -C "$SANDBOX/repo" init -q -b main
  git -C "$SANDBOX/repo" config user.email t@t
  git -C "$SANDBOX/repo" config user.name t
  git -C "$SANDBOX/repo" config commit.gpgsign false

  mkdir -p "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts/"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/scripts/"
  cp "$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE" \
     "$SANDBOX/repo/plugins/soleur/skills/gdpr-gate/"

  {
    printf 'pre-commit:\n  parallel: false\n  commands:\n    gdpr-gate-advisory:\n      glob:\n'
    printf '%s\n' "$1"
    printf '      run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}\n'
  } > "$SANDBOX/repo/lefthook.yml"
}

stage_regulated_path() {
  # A path the CANONICAL_REGEX in gdpr-gate.sh matches. Depth-1 under
  # lib/auth/ deliberately: that is the depth a bare `**` glob silently drops.
  mkdir -p "$SANDBOX/repo/apps/web-platform/lib/auth"
  printf 'export const probe = 1;\n' > "$SANDBOX/repo/apps/web-platform/lib/auth/probe.ts"
  git -C "$SANDBOX/repo" add -A
}

run_hook() {
  ( cd "$SANDBOX/repo" && LEFTHOOK_VERBOSE=0 lefthook run pre-commit 2>&1 ) || true
}

# --- TS1: the live glob matches a regulated path and the command RUNS ------
echo ""
echo "TS1: live gdpr-gate-advisory glob -> command runs on a staged regulated path"
build_sandbox "$GLOBS"
stage_regulated_path
OUT="$(run_hook)"

if grep -q 'path scan complete' <<<"$OUT"; then
  echo "  PASS: gdpr-gate.sh executed via lefthook (scan-completion line observed)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: gdpr-gate.sh did NOT run — the glob no longer matches a regulated path"
  echo "        lefthook output was:"
  printf '%s\n' "$OUT" | sed 's/^/          /'
  FAIL=$((FAIL + 1))
fi

if grep -qE 'gdpr-gate-advisory.*\(skip\)' <<<"$OUT"; then
  echo "  FAIL: lefthook reported gdpr-gate-advisory as skipped"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: lefthook did not report gdpr-gate-advisory as skipped"
  PASS=$((PASS + 1))
fi

# --- TS2: own dispatch — a narrowed glob must be DETECTED ------------------
# Guard 2 mutation 5. This is the control that proves TS1 can fail: without
# it, TS1 passing tells you the harness works, not that the glob does.
echo ""
echo "TS2: narrowed glob (matches nothing) -> the probe reports the silence"
build_sandbox '        - "no/such/path/*.nomatch"'
stage_regulated_path
OUT_MUT="$(run_hook)"

if grep -q 'path scan complete' <<<"$OUT_MUT"; then
  echo "  FAIL: scan line appeared under a glob that matches nothing — the probe cannot detect a dead glob"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no scan line under a non-matching glob (the failure the script cannot self-report)"
  PASS=$((PASS + 1))
fi

print_results 5
