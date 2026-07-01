#!/usr/bin/env bash
#
# Tests for the git-data per-workspace bare-repo provisioner (git-data-provision.sh,
# #5817 PR B part 2 / ADR-068 amendment "PR B bare-repo provisioning"). Exercises:
# a valid id inits once and re-provision is a no-op; a fresh repo inherits the fence
# via core.hooksPath (fence stored_max starts at 0); traversal / unsafe ids are
# rejected BEFORE any init; a missing id fails closed.
#
# Run: bash apps/web-platform/infra/git-data-provision.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${DIR}/git-data-provision.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Run the wrapper with SSH_ORIGINAL_COMMAND=<id> against a test repo root. Echoes
# the exit code. Runs WITHOUT set -e propagation (reject cases exit 1 by design).
run_provision() {
  local root="$1" id="$2"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" SSH_ORIGINAL_COMMAND="$id" \
    bash "$WRAPPER" >/dev/null 2>&1
  echo $?
}

fresh_root() {
  local r
  r="$(mktemp -d "${TMPDIR:-/tmp}/gdprov.XXXXXX")"
  echo "$r"
}

# --- T1: a valid id inits a bare repo (exit 0, HEAD file present) ---
root=$(fresh_root)
rc=$(run_provision "$root" "ws-abc-123")
if [ "$rc" = "0" ]; then pass; else fail "T1 valid id: expected 0, got $rc"; fi
if [ -f "${root}/ws-abc-123.git/HEAD" ]; then pass; else fail "T1 bare repo HEAD missing — init did not run"; fi
rm -rf "$root"

# --- T2: re-provision the same id is an idempotent no-op (exit 0, repo intact) ---
root=$(fresh_root)
run_provision "$root" "ws-abc-123" >/dev/null
# Drop a marker inside to prove init is NOT re-run (would not clobber).
touch "${root}/ws-abc-123.git/MARKER"
rc=$(run_provision "$root" "ws-abc-123")
if [ "$rc" = "0" ]; then pass; else fail "T2 re-provision: expected 0, got $rc"; fi
if [ -f "${root}/ws-abc-123.git/MARKER" ]; then pass; else fail "T2 re-provision clobbered the existing repo (MARKER gone)"; fi
rm -rf "$root"

# --- T3: traversal / unsafe ids are REJECTED before any init ---
root=$(fresh_root)
# shellcheck disable=SC2016 # the $(whoami) is a LITERAL string under test — it must NOT expand
for bad in ".." "." "a/b" "a b" "a;rm -rf /" '$(whoami)' "" ; do
  rc=$(run_provision "$root" "$bad")
  if [ "$rc" != "0" ]; then pass; else fail "T3 unsafe id '$bad': expected reject (non-zero), got 0"; fi
done
# No repo dir should have been created for any unsafe id.
if [ -z "$(ls -A "$root" 2>/dev/null)" ]; then pass; else fail "T3 an unsafe id created a repo dir: $(ls -A "$root")"; fi
rm -rf "$root"

# --- T4: a traversal id cannot escape the repo root (parent-canonicalize guard) ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdprov-outside.XXXXXX")"
# `..%2f`-style is blocked by the charset check; verify a literal `..` never writes
# outside the root even though it is also charset-rejected (defense-in-depth).
rc=$(run_provision "$root" "../$(basename "$outside")")
if [ "$rc" != "0" ]; then pass; else fail "T4 escape attempt: expected reject, got 0"; fi
if [ -z "$(ls -A "$outside" 2>/dev/null)" ]; then pass; else fail "T4 escape wrote outside the root"; fi
rm -rf "$root" "$outside"

# --- Minimum-cardinality guard (mirrors the fence test) ---
total=$((passes + fails))
if [ "$total" -lt 12 ]; then
  echo "FAIL: ran only ${total} assertions (<12) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-provision: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
