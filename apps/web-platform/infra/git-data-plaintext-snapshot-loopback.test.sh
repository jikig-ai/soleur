#!/usr/bin/env bash
#
# REAL-DEVICE evidence for the git-data plaintext count through a device-mapper snapshot
# (#5274 Phase 3, ADR-239 amendment 2026-09-24).
#
# The retained plaintext volume is counted by the store-verify unit of git-data-bootstrap.sh. Its
# ext4 journal can be dirty (the predecessor host was destroyed while it was mounted rw), and a
# plain `mount -o ro` of a dirty ext4 REPLAYS the journal onto the device. The unit therefore sets
# the device kernel read-only (`blockdev --setro`), stacks a non-persistent dm `snapshot` on it
# whose copy-on-write store is a RAM file, and mounts the SNAPSHOT without `noload`, so the journal
# replays into the throwaway COW and the counted tree is the post-replay tree.
#
# That design rests on kernel facts that source reading supports and nothing had measured. The
# MECHANISM tier below measures them on this runner's kernel, independent of the SUT:
#   N0  negative control — a dirty origin set --setro REFUSES a direct `mount -o ro` (ext4 will not
#       replay onto a read-only bdev). If this does not hold, the ADR's "kernel ro backstop"
#       sentence is false, and the suite exits 2 (instrument), not 1.
#   M1  a dm `snapshot` target stacks on that read-only origin, the snapshot mounts ro WITHOUT
#       noload, the journal replays into the COW, the snapshot's superblock is clean while the
#       origin's still carries needs_recovery, and the origin's bytes are unchanged.
#
# The SUT tier then drives the REAL plaintext-count unit (extracted by its inner sentinels from
# git-data-bootstrap.sh, spanning the real _repo_count) against real loop devices, one child bash
# per arm: A clean; B dirty + empty; C dirty with a repository recorded ONLY in the journal (the
# discriminating arm: a noload read would miss it); Guard 1 row 4 (noload + no post-check) run
# against arm C's shape; D COW overflow; E a directory block that fails its checksum (ext4
# readdir skips it silently); F a torn last transaction checked against an independent rw
# replay of a copy. Every arm asserts the origin's sha256 is unchanged, it is still kernel-ro,
# and no loop, dm device or /dev/shm entry survives (against a per-arm baseline).
#
# IT LIVES IN ITS OWN FILE BECAUSE IT NEEDS ROOT. It is invoked as `sudo bash` inside a multi-line
# `run: |` block in infra-validation.yml and exempted in test-infra-suite-registration.sh — the
# same shape and reason as inngest-redis-luks-loopback.test.sh (#7076): it exits 2 unprivileged, so
# deriving it into run-registered-suites.sh would turn a mandated local gate permanently RED for any
# operator without passwordless sudo.
#
# NO SILENT SKIP. Without the device layer this suite exits NON-ZERO with the literal token
# LOOPBACK_UNAVAILABLE.
#
# Harness conventions (this repo's own post-mortems — load-bearing):
#   - NEVER pipe into an assertion predicate (SIGPIPE under pipefail fails a negative assert OPEN).
#   - Every setup command is rc-checked; a harness that fails to SET UP aborts (exit 2).
#   - Loop devices are recorded by DIRECT assignment, never through `$(fn)`: an append inside a
#     command substitution runs in a subshell and the teardown would own nothing.
#   - The dm names are fixed, so a concurrent run is REFUSED rather than raced.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/git-data-bootstrap.sh"

pass=0
fail=0
executed=0
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1"; }

# INSTRUMENT SELF-TEST — drive both counters once each and refuse to continue unless both moved.
_p0=$pass; _f0=$fail
ok "instrument self-test (expected)" >/dev/null
no "instrument self-test (expected)" >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ]; then
  echo "FATAL: instrument self-test did not move both counters" >&2; exit 2
fi
pass=$_p0; fail=$_f0; executed=0

unavailable() {
  echo "LOOPBACK_UNAVAILABLE: $*" >&2
  echo "git-data-plaintext-snapshot-loopback: LOOPBACK_UNAVAILABLE — real-device evidence was NOT collected." >&2
  echo "This is a FAILURE, not a skip: run as root on a host with losetup + dmsetup + mkfs.ext4 +" >&2
  echo "python3 + a dm-snapshot-capable kernel (GitHub-hosted ubuntu runners qualify, via sudo)." >&2
  exit 2
}
# instrument <msg> — the HARNESS could not establish a precondition it needs to measure anything.
instrument() { echo "INSTRUMENT: $*" >&2; exit 2; }

[ -f "$BOOTSTRAP" ] || unavailable "required file not found: $BOOTSTRAP"

# The canonical P1b guard (#7810): the one shape plugins/soleur/test/lib/fixture-scan.py accepts as
# proof that a write's operand is absolute. Duplicated per file by the repo's own convention.
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

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    exec sudo -n bash "${BASH_SOURCE[0]}" "$@"
  fi
  unavailable "not running as root and passwordless sudo is unavailable"
fi
for b in losetup dmsetup blockdev mkfs.ext4 dumpe2fs debugfs mount umount findmnt mountpoint truncate sha256sum python3 realpath; do
  command -v "$b" >/dev/null 2>&1 || unavailable "required binary '$b' not found on PATH"
done
[ -d /dev/shm ] || unavailable "/dev/shm is absent (the unit keeps its COW there)"

export TMPDIR="${TMPDIR:-/var/tmp}"
TMPROOT="$(mktemp -d -t gd-pt-snap.XXXXXXXX)" || unavailable "mktemp -d failed"
assert_fixture_dir "$TMPROOT"
CLEAN_MOUNTS=(); CLEAN_DMS=(); CLEAN_LOOPS=(); CLEAN_SHM=()
teardown() {
  local i
  for ((i = ${#CLEAN_MOUNTS[@]} - 1; i >= 0; i--)); do
    mountpoint -q "${CLEAN_MOUNTS[$i]}" 2>/dev/null && { umount "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1 || umount -l "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1; }
  done
  for ((i = ${#CLEAN_DMS[@]} - 1; i >= 0; i--)); do
    dmsetup info "${CLEAN_DMS[$i]}" >/dev/null 2>&1 && dmsetup remove --retry "${CLEAN_DMS[$i]}" >/dev/null 2>&1
  done
  for ((i = ${#CLEAN_LOOPS[@]} - 1; i >= 0; i--)); do losetup -d "${CLEAN_LOOPS[$i]}" >/dev/null 2>&1; done
  for ((i = ${#CLEAN_SHM[@]} - 1; i >= 0; i--)); do rm -rf "${CLEAN_SHM[$i]}" >/dev/null 2>&1; done
  rm -rf "$TMPROOT" >/dev/null 2>&1
  return 0
}
trap teardown EXIT

# The SUT's snapshot name is fixed (`git-data-pt-snap`); the mechanism tier uses its own. Refuse
# rather than race a concurrent run or a real host.
MECH_DM=gd-pt-mech
for _dm in git-data-pt-snap "$MECH_DM"; do
  if dmsetup info "$_dm" >/dev/null 2>&1; then
    unavailable "device-mapper name '$_dm' is already in use (another run, or a real host)"
  fi
done

# ── helpers ─────────────────────────────────────────────────────────────────────

# new_image <tag> — a fresh 256 MiB ext4 image on a loop device. Sets LOOP (global; NOT `$(fn)`).
new_image() {
  local tag="$1" backing="$TMPROOT/$1.img"
  truncate -s 256M "$backing" || instrument "truncate failed for $tag"
  mkfs.ext4 -q -F "$backing" >/dev/null 2>&1 || instrument "mkfs.ext4 failed for $tag"
  LOOP="$(losetup --find --show "$backing")" || instrument "losetup failed for $tag"
  CLEAN_LOOPS+=("$LOOP")
}

# needs_recovery <dev> — rc 0 iff dumpe2fs reports the needs_recovery feature.
needs_recovery() {
  local sb
  sb="$(dumpe2fs -h "$1" 2>/dev/null)" || return 2
  [[ "$sb" == *"Filesystem features:"*" needs_recovery"* ]]
}

# shutdown_fs <mountpoint> <flag> — EXT4_IOC_SHUTDOWN. _IOR('X', 125, __u32) = 0x8004587D.
# flag 1 = EXT4_GOING_FLAGS_LOGFLUSH (journal flushed, never checkpointed),
# flag 2 = EXT4_GOING_FLAGS_NOLOGFLUSH (the hot-unplug shape). After it, umount cannot clear
# needs_recovery (the journal is aborted), which is the predecessor's state.
shutdown_fs() {
  python3 - "$1" "$2" <<'PY'
import fcntl, os, struct, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
fcntl.ioctl(fd, 0x8004587D, struct.pack('I', int(sys.argv[2])))
os.close(fd)
PY
}

# make_dirty <loop> — mount rw, write a file OUTSIDE repositories/, mkdir+rmdir a probe INSIDE it,
# shut the filesystem down with LOGFLUSH, then unmount. Leaves needs_recovery set; asserts it.
make_dirty() {
  local loop="$1" mnt="$TMPROOT/dirty-mnt"
  mkdir -p "$mnt" || instrument "mkdir $mnt failed"
  mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
  CLEAN_MOUNTS+=("$mnt")
  printf 'seed\n' > "$mnt/seed-marker" || instrument "write seed-marker failed"
  mkdir -p "$mnt/repositories/probe.git" || instrument "mkdir probe failed"
  rmdir "$mnt/repositories/probe.git" || instrument "rmdir probe failed"
  shutdown_fs "$mnt" 1 || instrument "EXT4_IOC_SHUTDOWN failed on $mnt (ioctl number or kernel)"
  umount "$mnt" || instrument "umount after shutdown failed"
  needs_recovery "$loop" || instrument "the dirtied image does not carry needs_recovery — the fixture did not produce a dirty journal"
}

# cow_bytes <dev> — Total journal blocks * max(Block size, 4096) + 64 MiB (the unit's sizing rule).
cow_bytes() {
  local sb jb bs
  sb="$(dumpe2fs -h "$1" 2>/dev/null)" || return 1
  jb="$(printf '%s\n' "$sb" | sed -n 's/^Total journal blocks:[[:space:]]*\([0-9][0-9]*\)$/\1/p')"
  bs="$(printf '%s\n' "$sb" | sed -n 's/^Block size:[[:space:]]*\([0-9][0-9]*\)$/\1/p')"
  [[ "$jb" =~ ^[0-9]+$ && "$bs" =~ ^[0-9]+$ ]] || return 1
  [ "$bs" -ge 4096 ] || bs=4096
  printf '%s' $((jb * bs + 67108864))
}

# ═══ MECHANISM TIER (harness-driven; independent of the SUT) ════════════════════

# ── N0: negative control ────────────────────────────────────────────────────────
new_image n0; N0_LOOP="$LOOP"
make_dirty "$N0_LOOP"
blockdev --setro "$N0_LOOP" || instrument "blockdev --setro failed on $N0_LOOP"
[ "$(blockdev --getro "$N0_LOOP")" = 1 ] || instrument "blockdev --getro did not read back 1 on $N0_LOOP"
N0_MNT="$TMPROOT/n0-mnt"; mkdir -p "$N0_MNT" || instrument "mkdir $N0_MNT failed"
if mount -o ro "$N0_LOOP" "$N0_MNT" >/dev/null 2>&1; then
  CLEAN_MOUNTS+=("$N0_MNT")
  umount "$N0_MNT" >/dev/null 2>&1
  instrument "NEGATIVE CONTROL FAILED: ext4 mounted a needs_recovery filesystem ro on a kernel-read-only device; the 'ro flag refuses replay' claim does not hold on this kernel"
fi
ok "N0 a dirty ext4 on a --setro device refuses a direct ro mount (ext4 will not replay onto a read-only bdev)"
if needs_recovery "$N0_LOOP"; then ok "N0 the refused origin still carries needs_recovery"; else no "N0 the refused origin lost needs_recovery"; fi

# ── M1: snapshot over a --setro origin replays into the COW ─────────────────────
new_image m1; M1_LOOP="$LOOP"
make_dirty "$M1_LOOP"
M1_SHA_BEFORE="$(sha256sum < "$M1_LOOP")" || instrument "sha256sum of $M1_LOOP failed"
blockdev --setro "$M1_LOOP" || instrument "blockdev --setro failed on $M1_LOOP"
[ "$(blockdev --getro "$M1_LOOP")" = 1 ] || instrument "blockdev --getro did not read back 1 on $M1_LOOP"
M1_COW_BYTES="$(cow_bytes "$M1_LOOP")" || instrument "could not parse the journal geometry of $M1_LOOP"
M1_SHM="$(mktemp -d -p /dev/shm gd-pt-mech.XXXXXXXX)" || instrument "mktemp -d -p /dev/shm failed"
CLEAN_SHM+=("$M1_SHM")
truncate -s "$M1_COW_BYTES" "$M1_SHM/cow" || instrument "truncate COW failed"
M1_COW_LOOP="$(losetup --find --show "$M1_SHM/cow")" || instrument "losetup of the COW failed"
CLEAN_LOOPS+=("$M1_COW_LOOP")
M1_SZ="$(blockdev --getsz "$M1_LOOP")" || instrument "blockdev --getsz failed"
if dmsetup create "$MECH_DM" --table "0 $M1_SZ snapshot $M1_LOOP $M1_COW_LOOP N 8"; then
  CLEAN_DMS+=("$MECH_DM")
  ok "M1 a dm snapshot target stacks on a kernel-read-only origin"
else
  instrument "MECHANISM FAILED: dmsetup create of a snapshot over the --setro origin was refused on this kernel (Phase 0 decision point)"
fi
M1_MNT="$TMPROOT/m1-mnt"; mkdir -p "$M1_MNT" || instrument "mkdir $M1_MNT failed"
if mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$MECH_DM" "$M1_MNT"; then
  CLEAN_MOUNTS+=("$M1_MNT")
  ok "M1 the snapshot mounts read-only WITHOUT noload"
else
  instrument "MECHANISM FAILED: the snapshot of a dirty ext4 did not mount ro without noload"
fi
if needs_recovery "/dev/mapper/$MECH_DM"; then no "M1 the snapshot superblock still carries needs_recovery (the journal did not replay into the COW)"; else ok "M1 the journal replayed into the COW (snapshot superblock clear of needs_recovery)"; fi
if needs_recovery "$M1_LOOP"; then ok "M1 the origin still carries needs_recovery (the replay did not reach it)"; else no "M1 the origin lost needs_recovery — the replay reached the retained device"; fi
if [ -f "$M1_MNT/seed-marker" ]; then ok "M1 the post-replay tree holds the seed marker"; else no "M1 the post-replay tree lacks the seed marker"; fi
M1_N="$(find "$M1_MNT/repositories" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
if [ "$M1_N" = 0 ]; then ok "M1 repositories/ holds 0 entries after replay (the probe was removed in the journal)"; else no "M1 repositories/ holds $M1_N entries after replay, expected 0"; fi
M1_STATUS="$(dmsetup status "$MECH_DM" 2>/dev/null)" || M1_STATUS=unreadable
case "$M1_STATUS" in
  *Invalid*|unreadable) no "M1 the snapshot status reads '$M1_STATUS'" ;;
  *) ok "M1 the snapshot is valid after the replay ($M1_STATUS)" ;;
esac
umount "$M1_MNT" || instrument "umount of the snapshot failed"
dmsetup remove --retry "$MECH_DM" || instrument "dmsetup remove failed"
losetup -d "$M1_COW_LOOP" || instrument "losetup -d of the COW failed"
rm -f "$M1_SHM/cow" && rmdir "$M1_SHM" || instrument "COW cleanup failed"
M1_SHA_AFTER="$(sha256sum < "$M1_LOOP")" || instrument "sha256sum of $M1_LOOP failed"
if [ "$M1_SHA_BEFORE" = "$M1_SHA_AFTER" ]; then ok "M1 the origin's bytes are unchanged (sha256)"; else no "M1 the origin's bytes CHANGED — the snapshot wrote the retained device"; fi
if [ "$(blockdev --getro "$M1_LOOP")" = 1 ]; then ok "M1 the origin is still kernel read-only after teardown"; else no "M1 the origin is no longer read-only after teardown"; fi

# ═══ SUT TIER — the REAL extracted plaintext-count unit, on real loop devices ═══════
# The unit is extracted by its inner sentinels (it spans the real _repo_count definition through
# the end of the plaintext block, so arm C tests the real counter, not a copy). log() is copied out
# of the script. Each arm runs the unit in a CHILD bash (the unit `exit`s and arms an EXIT trap);
# the parent measures the origin's bytes, its read-only flag and the transient-device leaks.
PT_BEGIN='# ---- BEGIN plaintext-count unit ----'
PT_END='# ---- END plaintext-count unit ----'
PT_UNIT="$TMPROOT/pt-unit.sh"
awk -v b="$PT_BEGIN" -v e="$PT_END" '$0==b{f=1;next} $0==e{f=0} f' "$BOOTSTRAP" > "$PT_UNIT" || instrument "extraction failed"
_n=$(grep -c . "$PT_UNIT" || true)
[ "$_n" -ge 60 ] || instrument "the plaintext-count unit extracted only $_n lines (sentinels moved or deleted)"
bash -n "$PT_UNIT" || instrument "the extracted plaintext-count unit is not valid bash on its own"
PT_PRELUDE="$TMPROOT/pt-prelude.sh"
{
  printf 'GIT_DATA_EMIT=/nonexistent/git-data-emit\n'
  awk '/^log\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP"
} > "$PT_PRELUDE" || instrument "prelude write failed"
grep -q '^log() {' "$PT_PRELUDE" || instrument "log() was not copied out of the bootstrap"
PT_TRAILER="$TMPROOT/pt-trailer.sh"
printf 'printf "plaintext_journal=%%s\\n" "$_plaintext_journal"\nprintf "plaintext_volume=%%s\\n" "$_plaintext_volume"\n' > "$PT_TRAILER" || instrument "trailer write failed"

ARMS_RAN=0
leak_state() { { losetup -a 2>/dev/null | sort; echo ---; dmsetup ls 2>/dev/null | sort; echo ---; ls -A /dev/shm 2>/dev/null | sort; } }

# run_sut <arm> <origin-loop> [unit-file] — runs the unit as a child; sets SUT_RC, SUT_OUT, SUT_ERR,
# and asserts the four invariants every arm owes: bytes unchanged, still kernel-ro, no leak, and
# no snapshot device left behind.
run_sut() {
  local arm="$1" loop="$2" unit="${3:-$PT_UNIT}" sha0 sha1 leak0 leak1
  ARMS_RAN=$((ARMS_RAN + 1))
  SUT_OUT="$TMPROOT/$arm.out"; SUT_ERR="$TMPROOT/$arm.err"
  sync
  sha0="$(sha256sum < "$loop")" || instrument "sha256sum of $loop failed"
  leak0="$(leak_state)"
  SUT_RC=0
  env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin GIT_DATA_PLAINTEXT_VOLUME_ID=424242424 GIT_DATA_PLAINTEXT_DEV="$loop" \
    bash -c 'set -euo pipefail; . "$1"; _plaintext_volume=absent; . "$2"; . "$3"' _ "$PT_PRELUDE" "$unit" "$PT_TRAILER" \
    > "$SUT_OUT" 2> "$SUT_ERR" || SUT_RC=$?
  sha1="$(sha256sum < "$loop")" || instrument "sha256sum of $loop failed"
  leak1="$(leak_state)"
  if [ "$sha0" = "$sha1" ]; then ok "$arm the origin's bytes are unchanged (sha256)"; else no "$arm the origin's bytes CHANGED — the unit wrote the retained device"; fi
  if [ "$(blockdev --getro "$loop")" = 1 ]; then ok "$arm the origin is kernel read-only after the unit"; else no "$arm the origin is NOT read-only after the unit"; fi
  if [ "$leak0" = "$leak1" ]; then ok "$arm no loop, dm device or /dev/shm entry survives (baseline-relative)"; else no "$arm transient state leaked: $(diff <(printf '%s\n' "$leak0") <(printf '%s\n' "$leak1") | tr '\n' ' ')"; fi
  if dmsetup info git-data-pt-snap >/dev/null 2>&1; then
    no "$arm git-data-pt-snap still exists"; dmsetup remove --retry git-data-pt-snap >/dev/null 2>&1
  else
    ok "$arm no git-data-pt-snap device remains"
  fi
}
sut_field() { sed -n "s/^$1=//p" "$SUT_OUT"; }
sut_pass() { # <arm> <journal>
  if [ "$SUT_RC" = 0 ]; then ok "$1 the unit PASSES (rc 0)"; else no "$1 the unit failed (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"; fi
  if [ "$(sut_field plaintext_journal)" = "$2" ]; then ok "$1 plaintext_journal=$2"; else no "$1 plaintext_journal='$(sut_field plaintext_journal)', expected $2"; fi
}
sut_fatal() { # <arm> <literal FATAL substring>
  if [ "$SUT_RC" != 0 ] && grep -qF -- "$2" "$SUT_ERR"; then ok "$1 FATAL: $2"; else no "$1 expected FATAL '$2' (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"; fi
}

# populate <loop> <cmd…> — mount rw, run a shell snippet in the mount, unmount cleanly.
populate() {
  local loop="$1" snippet="$2" mnt="$TMPROOT/pop-mnt"
  mkdir -p "$mnt" || instrument "mkdir $mnt failed"
  mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
  ( cd "$mnt" && eval "$snippet" ) || { umount "$mnt"; instrument "populate snippet failed: $snippet"; }
  umount "$mnt" || instrument "umount after populate failed"
}

# journal_only_residue <loop> <flag> — arm C's deterministic build: a checkpointed anchor, then a
# repository created, its directory fsync'd and the filesystem shut down FROM THE SAME PROCESS with
# no sync in between, so the entry exists ONLY in the journal. The anchor is named like a lock
# dotfile so the unit's count excludes it, while debugfs still lists it (proving it read the right
# directory). Returns 1 when the precondition does not hold.
journal_only_residue() {
  local loop="$1" flag="$2" mnt="$TMPROOT/jor-mnt" ls
  populate "$loop" 'mkdir -p repositories && : > repositories/.anchor.init.lock'
  mkdir -p "$mnt" || instrument "mkdir $mnt failed"
  mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
  python3 - "$mnt" "$flag" <<'PY' || { umount "$mnt" 2>/dev/null; instrument "the journal-only build failed"; }
import fcntl, os, struct, sys
m, flag = sys.argv[1], int(sys.argv[2])
os.mkdir(os.path.join(m, "repositories", "ws-1.git"))
d = os.open(os.path.join(m, "repositories"), os.O_RDONLY)
os.fsync(d)
os.close(d)
fd = os.open(m, os.O_RDONLY)
fcntl.ioctl(fd, 0x8004587D, struct.pack('I', flag))
os.close(fd)
PY
  umount "$mnt" || instrument "umount after shutdown failed"
  needs_recovery "$loop" || return 1
  ls="$(debugfs -c -R 'ls -l /repositories' "$loop" 2>/dev/null)" || return 1
  [[ "$ls" == *".anchor.init.lock"* ]] || return 1
  [[ "$ls" != *"ws-1.git"* ]] || return 1
  return 0
}
# build_arm_c <tag> <flag> — up to 3 attempts, then an INSTRUMENT exit (never green).
build_arm_c() {
  local tag="$1" flag="$2" try
  for try in 1 2 3; do
    new_image "$tag-$try"
    if journal_only_residue "$LOOP" "$flag"; then ARM_LOOP="$LOOP"; return 0; fi
  done
  instrument "arm $tag: after 3 builds the entry was not journal-only (debugfs listed it, or did not list the anchor)"
}

# ── A: clean journal, empty tree ───────────────────────────────────────────────
new_image a; A_LOOP="$LOOP"
populate "$A_LOOP" 'mkdir -p repositories'
run_sut A "$A_LOOP"
sut_pass A clean

# ── B: dirty journal, empty post-replay tree (also the positive control) ────────
new_image b; B_LOOP="$LOOP"
make_dirty "$B_LOOP"
run_sut B "$B_LOOP"
sut_pass B dirty
if needs_recovery "$B_LOOP"; then ok "B the origin still carries needs_recovery (the replay stayed in the COW)"; else no "B the origin lost needs_recovery"; fi

# ── C: dirty journal whose ONLY record of a repository is in the journal (P3) ────
build_arm_c c 1; C_LOOP="$ARM_LOOP"
ok "C precondition: debugfs lists the checkpointed anchor and NOT the journal-only ws-1.git"
run_sut C "$C_LOOP"
sut_fatal C 'FATAL: plaintext_residue count=1'
if needs_recovery "$C_LOOP"; then ok "C the origin still carries needs_recovery"; else no "C the origin lost needs_recovery"; fi

# ── Guard 1 row 4: re-add noload AND drop the post-replay check → the stale tree reads empty ──
MUT4="$TMPROOT/pt-unit.mut4"
python3 - "$PT_UNIT" "$MUT4" <<'PY' || instrument "mutation 4 could not be written"
import sys
s = open(sys.argv[1]).read()
a = 'mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$_pt_snap"'
b = '  if _pt_has_nr "$_pt_ssb"; then'
assert s.count(a) == 1 and s.count(b) == 1
s = s.replace(a, 'mount -o ro,noload,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$_pt_snap"').replace(b, '  if false; then')
open(sys.argv[2], "w").write(s)
PY
if cmp -s "$PT_UNIT" "$MUT4"; then no "G1-4 the mutation did not land"; else ok "G1-4 the mutation landed (noload + no post-check)"; fi
build_arm_c c4 1; C4_LOOP="$ARM_LOOP"
run_sut G1-4 "$C4_LOOP" "$MUT4"
if [ "$SUT_RC" = 0 ]; then ok "G1-4 ROW 4: with noload the journal-only repository is missed and the mutant PASSES — the arm is live"; else no "G1-4 the mutant did not pass (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"; fi

# ── D: COW overflow → a named FATAL, never a residue verdict or a PASS ──────────
MUTD="$TMPROOT/pt-unit.cowtiny"
python3 - "$PT_UNIT" "$MUTD" <<'PY' || instrument "the arm-D rebinding could not be written"
import sys
s = open(sys.argv[1]).read()
a = '_pt_cow_bytes=$((_pt_jb * _pt_bs + 67108864))'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, '_pt_cow_bytes=65536'))
PY
cmp -s "$PT_UNIT" "$MUTD" && instrument "the arm-D COW rebinding did not land"
build_arm_c d 1; D_LOOP="$ARM_LOOP"
run_sut D "$D_LOOP" "$MUTD"
if [ "$SUT_RC" != 0 ] && grep -qE 'FATAL: plaintext_unverified reason=(snapshot|mount) ' "$SUT_ERR"; then
  ok "D a COW overflow is a named FATAL reason=snapshot|mount"
else
  no "D expected reason=snapshot|mount (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"
fi
if grep -qF 'plaintext_residue' "$SUT_ERR"; then no "D an overflow produced a residue verdict"; else ok "D no residue verdict on an overflow"; fi

# ── E: a directory block that fails its checksum → reason=journal, never a short-count PASS ──
new_image e; E_LOOP="$LOOP"
populate "$E_LOOP" 'mkdir -p repositories/ws-e.git'
E_BLK="$(debugfs -c -R 'blocks /repositories' "$E_LOOP" 2>/dev/null | awk 'NF{print $1; exit}')"
[[ "$E_BLK" =~ ^[0-9]+$ ]] || instrument "arm E: could not read the repositories/ directory block"
E_BS="$(dumpe2fs -h "$E_LOOP" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')"
[[ "$E_BS" =~ ^[0-9]+$ ]] || instrument "arm E: could not read the block size"
dd if=/dev/urandom of="$E_LOOP" bs="$E_BS" seek="$E_BLK" count=1 conv=notrunc,fsync status=none || instrument "arm E: corrupting the directory block failed"
blockdev --flushbufs "$E_LOOP" || instrument "arm E: flushbufs failed"
run_sut E "$E_LOOP"
sut_fatal E 'FATAL: plaintext_unverified reason=journal'

# ── F: torn last transaction (NOLOGFLUSH) — the verdict equals an independent replay ──
build_arm_c f 2 || true; F_LOOP="$ARM_LOOP"
F_COPY="$TMPROOT/f-oracle.img"
sha256sum < "$F_LOOP" >/dev/null || instrument "arm F: origin unreadable"
dd if="$F_LOOP" of="$F_COPY" bs=1M status=none || instrument "arm F: the oracle copy failed"
F_OLOOP="$(losetup --find --show "$F_COPY")" || instrument "arm F: losetup of the oracle copy failed"
CLEAN_LOOPS+=("$F_OLOOP")
F_OMNT="$TMPROOT/f-oracle-mnt"; mkdir -p "$F_OMNT" || instrument "arm F: mkdir failed"
mount -o rw "$F_OLOOP" "$F_OMNT" || instrument "arm F: the oracle rw mount (a real replay) failed"
CLEAN_MOUNTS+=("$F_OMNT")
F_ORACLE="$(find "$F_OMNT/repositories" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name lost+found 2>/dev/null | wc -l)"
umount "$F_OMNT" || instrument "arm F: oracle umount failed"
run_sut F "$F_LOOP"
if [ "$F_ORACLE" = 0 ]; then
  if [ "$SUT_RC" = 0 ]; then ok "F the unit PASSES and the independent replay counts 0"; else no "F the independent replay counts 0 but the unit failed: $(tr '\n' ' ' < "$SUT_ERR")"; fi
else
  sut_fatal F "FATAL: plaintext_residue count=$F_ORACLE"
fi

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only, reported by printf + exit and
# never through ok()/no() (ADR-193) — a floor routed through the helpers it backstops is silenced by
# the same edit that silences the arms. Each bound is a literal on the line directly above its `if`
# so guard-vacuity-floor.test.sh can construct the mutant.
# Projected, not yet measured for the SUT tier (the authoring machine has no passwordless sudo):
# mechanism N0 = 2, M1 = 9; SUT A = 6, B = 7, C = 7, G1-4 = 6, D = 6, E = 5, F = 5 (53 total). The
# mechanism tier's 11 was the only part that existed at the first CI run. Confirm against CI and
# account for any difference arm by arm before moving either literal.
EXPECTED_ARMS=7
if [ "$ARMS_RAN" -ne "$EXPECTED_ARMS" ]; then
  printf '[FATAL] anti-vacuity floor: %s SUT arms ran, expected exactly %s (A, B, C, G1-4, D, E, F)\n' "$ARMS_RAN" "$EXPECTED_ARMS" >&2
  exit 1
fi
MIN_ASSERTIONS=53
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s — arms were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf 'ok   - anti-vacuity floor: %s assertions over %s SUT arms (floors %s / %s)\n' "$executed" "$ARMS_RAN" "$MIN_ASSERTIONS" "$EXPECTED_ARMS"

echo ""
echo "=== git-data-plaintext-snapshot-loopback.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
