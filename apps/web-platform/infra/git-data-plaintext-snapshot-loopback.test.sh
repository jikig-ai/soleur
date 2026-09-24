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

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only, reported by printf + exit and
# never through ok()/no() (ADR-193) — a floor routed through the helpers it backstops is silenced by
# the same edit that silences the arms. The bound is a literal on the line directly above its `if`
# so guard-vacuity-floor.test.sh can construct the mutant.
# Projected, not yet measured (the authoring machine has no passwordless sudo): N0 = 2, M1 = 9.
# Confirm against the first CI run and account for any difference arm by arm before moving it.
MIN_ASSERTIONS=11
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s — arms were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf 'ok   - anti-vacuity floor: %s assertions ran (floor %s)\n' "$executed" "$MIN_ASSERTIONS"

echo ""
echo "=== git-data-plaintext-snapshot-loopback.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
