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
# Presence under apps/web-platform/infra/ IS registration — derived and run by run-registered-suites.sh (#8736).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
# The C1 rows below clean up through this rather than a bare `rm -rf "$root"`, so the P1b
# fixture-relative ratchet has a guard correlated with the operand and the new rows add no
# grandfathered residue to its baseline.
drop_fixture() { assert_fixture_dir "$1"; rm -rf "$1"; }

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
#
# (#8211, ADR-239) THE STORE ASSERTION (C1). The wrapper also refuses unless findmnt's SOURCE
# for the mount root EQUALS GIT_DATA_STORE_DEVICE and GIT_DATA_STORE_VERIFIED holds that
# filesystem's UUID. Both seams are DERIVED from the real temp root: `--mountpoint` of the
# `stat -c %m` mount (never -T), and whatever findmnt prints for it — btrfs prints a
# `[/subvol]` suffix, and a hand-typed device would be a second source of truth.
# A filesystem with no probe-able UUID (tmpfs; a runner whose / is `/dev/root`) cannot give
# the must-PASS row a real one. Only then does a findmnt PATH stub answer UUID for that one
# mountpoint (SOURCE and everything else exec the real findmnt), and the suite says so. The
# off-store rows use /proc, which never has a UUID: the stub answers it with the same value
# so those rows still reach the containment guard they exist to test.
FM_REAL="$(command -v findmnt)" || { echo "FAIL SETUP: findmnt(8) not on PATH" >&2; exit 1; }
SEAMS="$(mktemp -d "${TMPDIR}/gdrm-seams.XXXXXX")"
trap 'rm -f "$ERR"; rm -rf "$SEAMS"' EXIT
MNT0="$(stat -c %m "$SEAMS")"
STORE_SRC="$(findmnt -n -o SOURCE --mountpoint "$MNT0")" || STORE_SRC=""
STORE_UUID="$(findmnt -n -o UUID --mountpoint "$MNT0")" || STORE_UUID=""
[ -n "$STORE_SRC" ] || { echo "FAIL SETUP: findmnt prints no SOURCE for $MNT0" >&2; exit 1; }
mkdir -p "$SEAMS/fm"; : > "$SEAMS/uuids"
if [ -z "$STORE_UUID" ]; then
  STORE_UUID="0b1d0000-8211-4000-8000-000000000001"
  printf '%s %s\n' "$MNT0" "$STORE_UUID" >> "$SEAMS/uuids"
  echo "NOTE: $MNT0 ($STORE_SRC) has no filesystem UUID — findmnt UUID stub in use for it"
fi
printf '/proc %s\n' "$STORE_UUID" >> "$SEAMS/uuids"
cat > "$SEAMS/fm/findmnt" <<STUB
#!/usr/bin/env bash
if [ "\$#" = 5 ] && [ "\$1 \$2 \$3 \$4" = "-n -o UUID --mountpoint" ]; then
  while read -r m u; do [ "\$m" = "\$5" ] && { printf '%s\n' "\$u"; exit 0; }; done < "$SEAMS/uuids"
fi
exec "$FM_REAL" "\$@"
STUB
chmod +x "$SEAMS/fm/findmnt"
printf '%s\n' "$STORE_UUID" > "$SEAMS/marker"
SPATH="$SEAMS/fm:$PATH"
# The device seam for a mount root: what findmnt prints for it (empty for a non-mount, which
# the mountpoint refusal rejects first).
dev_for() { findmnt -n -o SOURCE --mountpoint "$1" 2>/dev/null || true; }
run_remove() {
  local root="$1" id="$2" mnt="${3:-}"
  [ -n "$mnt" ] || mnt="$(stat -c %m "$root")"
  env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$mnt" \
    GIT_DATA_STORE_DEVICE="$(dev_for "$mnt")" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
    SSH_ORIGINAL_COMMAND="$id" bash "$WRAPPER" >/dev/null 2>"$ERR"
  echo $?
}
# C1 variant: the seams are explicit (device, marker, PATH) so a row can set one to refuse.
run_remove_c1() {
  local root="$1" id="$2" dev="$3" marker="$4" path="${5:-$SPATH}"
  env -i PATH="$path" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
    GIT_DATA_STORE_DEVICE="$dev" GIT_DATA_STORE_VERIFIED="$marker" \
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
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
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
#     The sentinel lives at the MOUNT root in production, which a suite cannot own; the path
#     seam is the same GIT_DATA_CUTOVER_FREEZE the pre-receive fence carries, and the DEFAULT
#     is pinned on the line so the seam cannot drift. The sentinel WRITER
#     (git-data-cutover.sh FREEZE_SENTINEL) was deleted with the cutover body in #8189; the
#     <mount root>/.cutover-freeze path contract is honoured by its four readers, no writer
#     exists today, and PR2 of #8211 defines the next one. ---
root=$(fresh_root); make_repo "$root" "ws-frozen"
: > "${root}/.frozen"
rc=$(env -i PATH="$SPATH" GIT_DATA_REPO_ROOT="$root" GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" \
  GIT_DATA_STORE_DEVICE="$STORE_SRC" GIT_DATA_STORE_VERIFIED="$SEAMS/marker" \
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
# ── (#8211, ADR-239) C1 — only a verified, mapper-served store is erased (Guard 1) ─────────
# Every refusal is the wrapper's `reject`: exit 1, never 0 (a false Art. 17 success) and never
# 255 (the app reads 255 as ssh itself failing — "unreachable", not "refused"). Every refusal
# row also asserts the ORDER: the fixture repo is intact afterwards, so a check moved below the
# `rm -rf` reddens here even though the exit code would still be 1.
c1_refused() { # c1_refused <row> <rc> <anchor> <root> <id>
  if [ "$2" = "1" ]; then pass; else fail "$1: expected exit 1 (reject), got $2 ($(head -c 200 "$ERR"))"; fi
  if grep -qF "$3" "$ERR"; then pass; else fail "$1: refusal does not carry '$3' ($(head -c 200 "$ERR"))"; fi
  if [ -e "${4}/${5}.git/HEAD" ]; then pass; else fail "$1: ORDER — the repo was erased before (or despite) the store refusal"; fi
}

# C1a MUST-PASS: the seam is the temp root's own --mountpoint SOURCE and the marker holds its
# UUID — the erasure runs and removes the fixture repo. A suite edit that sets the seam to a
# refusing value everywhere reddens THIS row (the census drives that mutation).
root=$(fresh_root); make_repo "$root" "ws-c1"
rc=$(run_remove_c1 "$root" "ws-c1" "$STORE_SRC" "$SEAMS/marker")
if [ "$rc" = "0" ]; then pass; else fail "C1a must-PASS: expected 0 with the store verified, got $rc ($(head -c 200 "$ERR"))"; fi
if [ ! -e "${root}/ws-c1.git" ]; then pass; else fail "C1a must-PASS: the fixture repo was not erased"; fi
if grep -qF "erased bare repo for 'ws-c1'" "$ERR"; then pass; else fail "C1a must-PASS: no erasure report ($(head -c 200 "$ERR"))"; fi
drop_fixture "$root"

# C1b mismatch: the production default device is not what serves the temp root.
root=$(fresh_root); make_repo "$root" "ws-c1"
rc=$(run_remove_c1 "$root" "ws-c1" "/dev/mapper/git-data" "$SEAMS/marker")
c1_refused "C1b device mismatch" "$rc" "is not served by /dev/mapper/git-data" "$root" "ws-c1"
drop_fixture "$root"

# C1c prefix look-alikes, DERIVED from the real SOURCE (never hand-typed): one is a prefix of
# the real device, the other extends it. A prefix/glob comparison in either direction lets one
# of them through; equality refuses both.
for look in "${STORE_SRC%?}" "${STORE_SRC}-old"; do
  root=$(fresh_root); make_repo "$root" "ws-c1"
  rc=$(run_remove_c1 "$root" "ws-c1" "$look" "$SEAMS/marker")
  c1_refused "C1c look-alike '$look'" "$rc" "is not served by $look" "$root" "ws-c1"
  drop_fixture "$root"
done

# C1d marker absent, and C1e marker present but EMPTY.
root=$(fresh_root); make_repo "$root" "ws-c1"
rc=$(run_remove_c1 "$root" "ws-c1" "$STORE_SRC" "$SEAMS/no-such-marker")
c1_refused "C1d marker absent" "$rc" "store not verified" "$root" "ws-c1"
: > "$SEAMS/marker-empty"
rc=$(run_remove_c1 "$root" "ws-c1" "$STORE_SRC" "$SEAMS/marker-empty")
c1_refused "C1e marker empty" "$rc" "store not verified" "$root" "ws-c1"
drop_fixture "$root"

# C1f marker UUID mismatch: a marker written for ANOTHER volume (a mapper reopened elsewhere).
root=$(fresh_root); make_repo "$root" "ws-c1"
printf '%s\n' "ffffffff-8211-4000-8000-00000000dead" > "$SEAMS/marker-other"
rc=$(run_remove_c1 "$root" "ws-c1" "$STORE_SRC" "$SEAMS/marker-other")
c1_refused "C1f marker UUID mismatch" "$rc" "store not verified" "$root" "ws-c1"
drop_fixture "$root"

# C1g findmnt(8) ABSENT from a curated PATH that still has mountpoint(1): fails closed on the
# wrapper's OWN text (bash's "findmnt: command not found" would also contain the bare token).
root=$(fresh_root); make_repo "$root" "ws-c1"
curated="$(mktemp -d "${TMPDIR}/gdrm-path.XXXXXX")"
for tool in bash readlink dirname flock rm grep stat head mountpoint; do
  src="$(command -v "$tool")" && ln -s "$src" "${curated}/${tool}"
done
rc=$(run_remove_c1 "$root" "ws-c1" "$STORE_SRC" "$SEAMS/marker" "$curated")
c1_refused "C1g findmnt absent" "$rc" "findmnt unavailable" "$root" "ws-c1"
drop_fixture "$root"; drop_fixture "$curated"

# C1h CONTRACT ROW (C5): the bootstrap's erasure probe runs exactly this — `env -i
# PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0` — and passes only on exit 0 plus
# `not present (no-op)`. Seams set to pass; stderr must be that one line, byte for byte.
root=$(fresh_root)
_probe_path=/usr/bin:/bin
[ -s "$SEAMS/uuids" ] && grep -qvx "/proc $STORE_UUID" "$SEAMS/uuids" && _probe_path="$SEAMS/fm:/usr/bin:/bin"
rc=$(env -i PATH="$_probe_path" SSH_ORIGINAL_COMMAND=boot-probe-0 GIT_DATA_REPO_ROOT="$root" \
  GIT_DATA_MOUNT_ROOT="$(stat -c %m "$root")" GIT_DATA_STORE_DEVICE="$STORE_SRC" \
  GIT_DATA_STORE_VERIFIED="$SEAMS/marker" bash "$WRAPPER" >/dev/null 2>"$ERR"; echo $?)
if [ "$rc" = "0" ]; then pass; else fail "C1h probe contract: expected exit 0, got $rc ($(head -c 200 "$ERR"))"; fi
if [ "$(cat "$ERR")" = "remote: git-data remove: 'boot-probe-0' not present (no-op)" ]; then pass; else fail "C1h probe contract: stderr is not exactly the not-present line ($(head -c 200 "$ERR"))"; fi
drop_fixture "$root"

# C1i the two outcome strings the probe (and PR2's app-side sentinel) key on stay byte-exact.
# shellcheck disable=SC2016 # literal source lines under test
if grep -qxF 'echo "remote: git-data remove: erased bare repo for '"'"'$workspace_id'"'"'" >&2' "$WRAPPER"; then pass; else fail "C1i the 'erased bare repo' line changed"; fi
# shellcheck disable=SC2016
if grep -qxF '  echo "remote: git-data remove: '"'"'$workspace_id'"'"' not present (no-op)" >&2' "$WRAPPER"; then pass; else fail "C1i the 'not present (no-op)' line changed"; fi

rm -f "$ERR"

# --- Minimum-cardinality guard (mirrors the provision/fence tests). 13 -> 29 with the
#     six mount rows (T6 2, T7 3, T8 3, T9 2, T10 2, T11 2), re-derived from the rows rather
#     than incremented by memory (T1 2, T2 1, T3 8, T4 2, T5 2 = 15 before). 29 -> 37 at
#     review: T10 +1 (message pin), T12 3, T13 2, T14 3. 38 -> 66 with the C1 store rows
#     (#8211): C1a 3, C1b 3, C1c 2x3, C1d 3, C1e 3, C1f 3, C1g 3, C1h 2, C1i 2 = 28 (measured:
#     66 ran). ---
total=$((passes + fails))
if [ "$total" -lt 66 ]; then
  echo "FAIL: ran only ${total} assertions (<66) — suite did not execute fully" >&2
  exit 1
fi

echo "git-data-remove: ${passes} passed, ${fails} failed (${total} assertions)"
[ "$fails" -eq 0 ]
