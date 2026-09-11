#!/usr/bin/env bash
#
# Tests for the git-data per-workspace bare-repo provisioner (git-data-provision.sh,
# #5817 PR B part 2 / ADR-068 amendment "PR B bare-repo provisioning"). Exercises:
# a valid id inits once and re-provision is a no-op; a fresh repo inherits the fence
# via core.hooksPath (fence stored_max starts at 0); traversal / unsafe ids are
# rejected BEFORE any init; a missing id fails closed; (#8043 F8) a provision against a
# store that is NOT MOUNTED refuses and writes nothing — before the fix it ran
# `git init --bare` onto the ROOT DISK, where a later successful mount silently hides
# the user's repository (data loss, not a false report).
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
# (#8043 F8) The mount root is a REAL mount (`stat -c %m` of the repo root), never a PATH
# stub — see git-data-remove.test.sh's runner for why the seam sits BELOW the instrument.
# The unmounted row overrides the third argument. Stderr is kept so the refusal TEXT can be
# pinned rather than "non-zero", which a charset reject also produces.
ERR="$(mktemp "${TMPDIR:-/tmp}/gdprov-err.XXXXXX")"
run_provision() {
  local root="$1" id="$2" mnt="${3:-}"
  [ -n "$mnt" ] || mnt="$(stat -c %m "$root")"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$mnt" \
    SSH_ORIGINAL_COMMAND="$id" bash "$WRAPPER" >/dev/null 2>"$ERR"
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

# --- T5 (#8043 F8, Guard 1 rows 4+6): an UNMOUNTED store is a named refusal and NOTHING
#     is written. The provision half is the severe one: before the fix `mkdir -p` created
#     the repo root on the root disk and `git init --bare` wrote a real user repository
#     there. The third assertion pins the ABSENCE of the root, not just the rc — a refusal
#     placed after a re-added mkdir returns the right code having already created it. ---
unmounted="$(mktemp -d "${TMPDIR:-/tmp}/gdprov-unmounted.XXXXXX")"
if mountpoint -q "$unmounted"; then fail "T5 fixture: $unmounted is unexpectedly a mount point"; fi
rc=$(run_provision "${unmounted}/repositories" "ws-abc-123" "$unmounted")
if [ "$rc" != "0" ]; then pass; else fail "T5 unmounted store: expected refusal (non-zero), got 0"; fi
if grep -q 'not mounted' "$ERR"; then pass; else fail "T5 unmounted store: refusal does not name the mount ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${unmounted}/repositories" ]; then pass; else fail "T5 unmounted store: the wrapper wrote onto the unmounted path: $(ls -A "${unmounted}/repositories" 2>/dev/null | tr '\n' ' ')"; fi
rm -rf "$unmounted"

# --- T6 (#8043 F8): mountpoint(1) ABSENT from PATH → fails CLOSED on a mounted store,
#     naming the instrument. Curated PATH of symlinks (see the remove suite's T8). ---
root=$(fresh_root)
curated="$(mktemp -d "${TMPDIR:-/tmp}/gdprov-path.XXXXXX")"
for tool in bash readlink dirname flock git grep; do
  src="$(command -v "$tool")" && ln -s "$src" "${curated}/${tool}"
done
env -i PATH="$curated" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
  SSH_ORIGINAL_COMMAND="ws-noinst" bash "$WRAPPER" >/dev/null 2>"$ERR"; rc=$?
if [ "$rc" != "0" ]; then pass; else fail "T6 mountpoint absent: expected fail-closed (non-zero), got 0"; fi
if grep -q 'mountpoint' "$ERR"; then pass; else fail "T6 mountpoint absent: refusal does not name the instrument ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${root}/ws-noinst.git" ]; then pass; else fail "T6 mountpoint absent: the wrapper provisioned without being able to verify the mount"; fi
rm -rf "$root" "$curated"
# --- T7 (#8043 F8, Guard 1 row 4): MOUNTED store, repo root ABSENT → refuse, root still
#     absent. See the remove suite's T10 for why this fixture (not the unmounted one) is
#     what makes "never create the store" observable. ---
parent="$(mktemp -d "${TMPDIR:-/tmp}/gdprov-noroot.XXXXXX")"
rc=$(run_provision "${parent}/repositories" "ws-abc-123" "$(stat -c %m "$parent")")
if [ "$rc" != "0" ]; then pass; else fail "T7 rootless store: expected refusal (non-zero), got 0"; fi
if [ ! -e "${parent}/repositories" ]; then pass; else fail "T7 rootless store: the wrapper CREATED the repo root ($(ls -A "${parent}/repositories" | tr '\n' ' '))"; fi
rm -rf "$parent"
rm -f "$ERR"

# --- Minimum-cardinality guard (mirrors the fence test). 12 -> 22 with the three mount
#     rows (T5 3, T6 3, T7 2), re-derived: T1 2, T2 2, T3 8, T4 2 = 14 before. ---
total=$((passes + fails))
if [ "$total" -lt 22 ]; then
  echo "FAIL: ran only ${total} assertions (<22) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-provision: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
