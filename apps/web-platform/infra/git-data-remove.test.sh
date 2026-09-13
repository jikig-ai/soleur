#!/usr/bin/env bash
#
# Tests for the git-data per-workspace bare-repo ERASURE wrapper
# (git-data-remove.sh, #5274 Phase 3 / ADR-068 GDPR Art. 17). Exercises: a valid id
# erases the repo (and its in-repo fence sidecar); erasing an absent id is an
# idempotent no-op; traversal / unsafe ids are rejected BEFORE any rm and never
# touch an existing repo; a symlink planted at the repo path cannot redirect the rm
# outside the root; a missing id fails closed; (#8043 F8) an erasure against a store that
# is NOT MOUNTED is a named refusal, never a "not present (no-op)" success, and the
# wrapper never creates the store.
#
# Run: bash apps/web-platform/infra/git-data-remove.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${DIR}/git-data-remove.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

# Run the wrapper with SSH_ORIGINAL_COMMAND=<id> against a test repo root. Echoes
# the exit code. Runs WITHOUT set -e propagation (reject cases exit 1 by design).
#
# (#8043 F8) THE MOUNT ROOT IS A REAL MOUNT, NOT A STUB. The wrapper refuses to act unless
# GIT_DATA_MOUNT_ROOT is a mount point (mountpoint(1) is the instrument, resolved from PATH
# and fail-closed when absent). A PATH stub for `mountpoint` would put the fixture seam ABOVE
# the instrument under test, so this runner points GIT_DATA_MOUNT_ROOT at the mount the repo
# root actually lives on — `stat -c %m` — which is what production looks like: REPO_ROOT is a
# plain subdirectory of the mounted store. The unmounted rows override the third argument
# with a directory that is NOT a mount point. Stderr goes to $ERR so a row can pin the
# refusal TEXT and not merely "non-zero" (a charset reject is also non-zero).
ERR="$(mktemp "${TMPDIR:-/tmp}/gdrm-err.XXXXXX")"
trap 'rm -f "$ERR"' EXIT
run_remove() {
  local root="$1" id="$2" mnt="${3:-}"
  [ -n "$mnt" ] || mnt="$(stat -c %m "$root")"
  env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$mnt" \
    SSH_ORIGINAL_COMMAND="$id" bash "$WRAPPER" >/dev/null 2>"$ERR"
  echo $?
}

fresh_root() {
  local r
  r="$(mktemp -d "${TMPDIR:-/tmp}/gdrm.XXXXXX")"
  echo "$r"
}

# Fabricate a "bare repo" dir with an in-repo fence sidecar to prove both go.
make_repo() {
  local root="$1" id="$2"
  mkdir -p "${root}/${id}.git/fence"
  touch "${root}/${id}.git/HEAD" "${root}/${id}.git/fence/primary.gen"
}

# --- T1: a valid id erases the repo AND its fence sidecar (exit 0, gone) ---
root=$(fresh_root)
make_repo "$root" "ws-abc-123"
rc=$(run_remove "$root" "ws-abc-123")
if [ "$rc" = "0" ]; then pass; else fail "T1 valid id: expected 0, got $rc"; fi
if [ ! -e "${root}/ws-abc-123.git" ]; then pass; else fail "T1 repo still present after erase"; fi
rm -rf "$root"

# --- T2: erasing an absent id is an idempotent no-op (exit 0) ---
root=$(fresh_root)
rc=$(run_remove "$root" "ws-never-existed")
if [ "$rc" = "0" ]; then pass; else fail "T2 absent id: expected idempotent 0, got $rc"; fi
rm -rf "$root"

# --- T3: traversal / unsafe ids are REJECTED and never erase a real repo ---
root=$(fresh_root)
make_repo "$root" "ws-keep"
# shellcheck disable=SC2016 # the $(whoami) is a LITERAL string under test — must NOT expand
for bad in ".." "." "a/b" "a b" "a;rm -rf /" '$(whoami)' "" ; do
  rc=$(run_remove "$root" "$bad")
  if [ "$rc" != "0" ]; then pass; else fail "T3 unsafe id '$bad': expected reject (non-zero), got 0"; fi
done
if [ -e "${root}/ws-keep.git/HEAD" ]; then pass; else fail "T3 an unsafe id erased the real repo"; fi
rm -rf "$root"

# --- T4: a traversal id cannot escape the repo root (parent-canonicalize guard) ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-outside.XXXXXX")"
touch "${outside}/SENTINEL"
rc=$(run_remove "$root" "../$(basename "$outside")")
if [ "$rc" != "0" ]; then pass; else fail "T4 escape attempt: expected reject, got 0"; fi
if [ -e "${outside}/SENTINEL" ]; then pass; else fail "T4 escape erased outside the root"; fi
rm -rf "$root" "$outside"

# --- T5: a symlink planted AT the repo path cannot redirect rm outside the root ---
root=$(fresh_root)
outside="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-sym.XXXXXX")"
touch "${outside}/SENTINEL"
ln -s "$outside" "${root}/ws-sym.git" # repo_path is a symlink to outside
rc=$(run_remove "$root" "ws-sym")
if [ "$rc" != "0" ]; then pass; else fail "T5 symlink repo: expected reject, got 0"; fi
if [ -e "${outside}/SENTINEL" ]; then pass; else fail "T5 symlink rm escaped and erased the target"; fi
rm -rf "$root" "$outside"

# --- T6 (#8043 F8, Guard 1 row 2): a CORRECTLY MOUNTED store still erases. Written
#     FIRST among the mount rows: it is the one that reds when the assertion is pointed at
#     $REPO_ROOT (a subdirectory, rc=1 from mountpoint on a healthy host) instead of the
#     mount root — the shape that "looks right" and fails every Art. 17 erasure closed. ---
root=$(fresh_root)
make_repo "$root" "ws-mounted"
rc=$(run_remove "$root" "ws-mounted" "$(stat -c %m "$root")")
if [ "$rc" = "0" ]; then pass; else fail "T6 mounted store: expected 0, got $rc ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${root}/ws-mounted.git" ]; then pass; else fail "T6 mounted store: repo still present after erase"; fi
rm -rf "$root"

# --- T7 (#8043 F8, Guard 1 rows 1+3): an UNMOUNTED store is a named refusal, and the
#     wrapper does not create the store. Before the fix this printed "not present (no-op)"
#     and exited 0 — an Article 17 success over a store nobody looked at — because
#     `readlink -f` succeeds on an absent path and `mkdir -p` then created it. The third
#     assertion (REPO_ROOT still absent) is what catches a refusal that fires AFTER a
#     re-added mkdir: the rc would be right and the store would already exist. ---
unmounted="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-unmounted.XXXXXX")"
if mountpoint -q "$unmounted"; then fail "T7 fixture: $unmounted is unexpectedly a mount point"; fi
rc=$(run_remove "${unmounted}/repositories" "ws-abc-123" "$unmounted")
if [ "$rc" != "0" ]; then pass; else fail "T7 unmounted store: expected refusal (non-zero), got 0"; fi
if grep -q 'not mounted' "$ERR"; then pass; else fail "T7 unmounted store: refusal does not name the mount ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${unmounted}/repositories" ]; then pass; else fail "T7 unmounted store: the wrapper CREATED the repo root on the unmounted path"; fi
rm -rf "$unmounted"

# --- T8 (#8043 F8, Test Scenario 13): mountpoint(1) ABSENT from PATH → fails CLOSED on a
#     mounted store, naming the instrument. util-linux lives in /usr/bin on both the
#     workstation and the runner, so "absent from PATH" cannot be produced by trimming;
#     the fixture is a curated PATH of symlinks to everything else the wrapper needs. ---
root=$(fresh_root)
make_repo "$root" "ws-noinst"
curated="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-path.XXXXXX")"
for tool in bash readlink dirname flock rm grep; do
  src="$(command -v "$tool")" && ln -s "$src" "${curated}/${tool}"
done
env -i PATH="$curated" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
  SSH_ORIGINAL_COMMAND="ws-noinst" bash "$WRAPPER" >/dev/null 2>"$ERR"; rc=$?
if [ "$rc" != "0" ]; then pass; else fail "T8 mountpoint absent: expected fail-closed (non-zero), got 0"; fi
# The anchor is the wrapper's OWN refusal text: a bare `mountpoint` is also satisfied by bash's
# "mountpoint: command not found" when the `command -v` guard is deleted (measured).
if grep -qF 'mountpoint(1) not on PATH' "$ERR"; then pass; else fail "T8 mountpoint absent: refusal does not name the instrument ($(head -c 200 "$ERR"))"; fi
if [ -e "${root}/ws-noinst.git/HEAD" ]; then pass; else fail "T8 mountpoint absent: the wrapper erased without being able to verify the mount"; fi
rm -rf "$root" "$curated"

# --- T9 (#8043 F8, Guard 1 row 7, MUST-PASS): a SYMLINKED $REPO_ROOT whose target sits on
#     the mount still erases — the assertion is on the mount root, not on the link. ---
root=$(fresh_root)
make_repo "$root" "ws-via-link"
link="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-link.XXXXXX")/repositories"
ln -s "$root" "$link"
rc=$(run_remove "$link" "ws-via-link" "$(stat -c %m "$root")")
if [ "$rc" = "0" ]; then pass; else fail "T9 symlinked root: expected 0, got $rc ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${root}/ws-via-link.git" ]; then pass; else fail "T9 symlinked root: repo still present after erase"; fi
rm -rf "$root" "$(dirname "$link")"
# --- T10 (#8043 F8, Guard 1 row 3): MOUNTED store, repo root ABSENT → refuse, and the
#     root is still absent afterwards. This is the fixture that makes "never create the
#     store" observable: on the unmounted rows the mount refusal fires first, so a mkdir
#     re-added BELOW the mount assertion can never run there. Only a mounted-but-rootless
#     store reaches the path guards, and a mkdir placed ABOVE them would create the root. ---
parent="$(mktemp -d "${TMPDIR:-/tmp}/gdrm-noroot.XXXXXX")"
rc=$(run_remove "${parent}/repositories" "ws-abc-123" "$(stat -c %m "$parent")")
if [ "$rc" != "0" ]; then pass; else fail "T10 rootless store: expected refusal (non-zero), got 0"; fi
if [ ! -e "${parent}/repositories" ]; then pass; else fail "T10 rootless store: the wrapper CREATED the repo root"; fi
if grep -q 'is not present' "$ERR"; then pass; else fail "T10 rootless store: refusal does not name the absent root ($(head -c 200 "$ERR"))"; fi
rm -rf "$parent"

# --- T11 (#8043 review): a MOUNTED store whose repo root is NOT ON IT → refuse. "A store is
#     mounted" and "a root exists" are facts about two paths; nothing else binds them, so a
#     root on the root disk beside a healthy /mnt/git-data mount would pass both and put the
#     erasure on the wrong disk. /proc is a mount on every Linux host; the root is elsewhere. ---
root=$(fresh_root)
make_repo "$root" "ws-offstore"
rc=$(run_remove "$root" "ws-offstore" /proc)
if [ "$rc" != "0" ]; then pass; else fail "T11 off-store root: expected refusal (non-zero), got 0"; fi
if grep -q 'not on the store' "$ERR" && [ -e "${root}/ws-offstore.git/HEAD" ]; then pass; else fail "T11 off-store root: refusal does not name containment, or the repo was erased ($(head -c 200 "$ERR"))"; fi
rm -rf "$root"

# --- T12 (#8043 review): the CUTOVER FREEZE sentinel refuses the erasure, nothing erased.
#     The sentinel lives at the MOUNT root in production (git-data-cutover.sh
#     FREEZE_SENTINEL), which a suite cannot own; the path seam is the same
#     GIT_DATA_CUTOVER_FREEZE the pre-receive fence carries, and the DEFAULT is pinned on
#     the line so the seam cannot drift from the cutover's sentinel path. ---
root=$(fresh_root); make_repo "$root" "ws-frozen"
: > "${root}/.frozen"
rc=$(env -i PATH="$PATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
  GIT_DATA_CUTOVER_FREEZE="${root}/.frozen" SSH_ORIGINAL_COMMAND="ws-frozen" bash "$WRAPPER" >/dev/null 2>"$ERR"; echo $?)
if [ "$rc" != "0" ]; then pass; else fail "T12 cutover freeze: expected refusal (non-zero), got 0"; fi
if grep -q 'frozen for cutover' "$ERR" && [ -e "${root}/ws-frozen.git/HEAD" ]; then pass; else fail "T12 cutover freeze: refusal does not name the freeze, or the repo was erased ($(head -c 200 "$ERR"))"; fi
if grep -qF 'cutover_freeze="${GIT_DATA_CUTOVER_FREEZE:-${MOUNT_ROOT}/.cutover-freeze}"' "$WRAPPER"; then pass; else fail "T12 the freeze sentinel default is not <mount root>/.cutover-freeze"; fi
rm -rf "$root"

# --- T13 (#8043 review): a SYMLINK planted at the lock path is refused BEFORE `exec 9>`
#     truncates its target (same uid can plant it: the root is git-owned). ---
root=$(fresh_root); make_repo "$root" "ws-lock"
victim="$(mktemp "${TMPDIR:-/tmp}/gdrm-victim.XXXXXX")"; printf 'keep\n' > "$victim"
ln -s "$victim" "${root}/.ws-lock.init.lock"
rc=$(run_remove "$root" "ws-lock")
if [ "$rc" != "0" ]; then pass; else fail "T13 lock symlink: expected refusal (non-zero), got 0"; fi
if grep -q 'lock path is a symlink' "$ERR" && [ "$(cat "$victim")" = "keep" ]; then pass; else fail "T13 lock symlink: refusal does not name it, or the target was truncated ($(head -c 200 "$ERR"))"; fi
rm -rf "$root" "$victim"

# --- T14 (#8043 review): the lock file is NEVER unlinked (unlink-while-held lets the next
#     opener hold a fresh inode concurrently), and the destructive rm carries
#     --one-file-system (a bind mount inside <id>.git would otherwise have its SOURCE erased
#     — root-only to plant, so pinned on the line rather than reproduced here). ---
root=$(fresh_root); make_repo "$root" "ws-keep"
rc=$(run_remove "$root" "ws-keep")
if [ "$rc" = "0" ] && [ -e "${root}/.ws-keep.init.lock" ]; then pass; else fail "T14 lock retained: expected rc 0 with the lock file still present (rc=$rc)"; fi
if grep -qE '^rm -rf --one-file-system "\$repo_real" \|\| reject ' "$WRAPPER"; then pass; else fail "T14 the destructive rm does not carry --one-file-system"; fi
if ! grep -qE '^[[:space:]]*rm -f "\$lock_file"' "$WRAPPER"; then pass; else fail "T14 the wrapper still unlinks the lock file"; fi
rm -rf "$root"
rm -f "$ERR"

# --- Minimum-cardinality guard (mirrors the provision/fence tests). 13 -> 29 with the
#     six mount rows (T6 2, T7 3, T8 3, T9 2, T10 2, T11 2), re-derived from the rows rather
#     than incremented by memory (T1 2, T2 1, T3 8, T4 2, T5 2 = 15 before). 29 -> 37 at
#     review: T10 +1 (message pin), T12 3, T13 2, T14 3. ---
total=$((passes + fails))
if [ "$total" -lt 38 ]; then
  echo "FAIL: ran only ${total} assertions (<38) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-remove: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
