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
# against arm C's shape; D COW overflow (the FATAL must say overflow); E a linear directory block
# that fails its checksum (readdir skips it silently: the errors_count FATAL) and its G1-9 mutant
# without the post-count check (which then PASSES on a count of 0); E2 the same corruption under
# dir_index (a named FATAL either way); F a torn transaction (its commit block zeroed) checked
# against independent rw replays of the torn and the intact journal; W a mutant that writes the
# origin between --setro and the release (the sysfs sector-counter FATAL); L a `repositories`
# symlink (refused, never followed). Every arm asserts the origin's backing-file sha256 and its
# sectors-written/discarded counters are unchanged, it is still kernel-ro, and none of this
# suite's loop, dm or /dev/shm apparatus survives (against a per-arm baseline).
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

# Every loop device's backing file, so the origin's bytes are hashed from the FILE (see run_sut).
declare -A LOOP_IMG=()

# attach <img> — a loop device over <img>. Sets LOOP (global; NOT `$(fn)`). Buffered (no
# --direct-io), so the backing file's page cache is coherent with every write the loop makes.
attach() {
  LOOP="$(losetup --find --show "$1")" || instrument "losetup failed for $1"
  CLEAN_LOOPS+=("$LOOP")
  LOOP_IMG[$LOOP]="$1"
}
# detach <loop> — detach and forget it, so the EXIT teardown never detaches a reused loop number.
detach() {
  local i
  losetup -d "$1" || instrument "losetup -d $1 failed"
  for i in "${!CLEAN_LOOPS[@]}"; do [ "${CLEAN_LOOPS[$i]}" != "$1" ] || unset 'CLEAN_LOOPS[i]'; done
  CLEAN_LOOPS=("${CLEAN_LOOPS[@]}")
  unset 'LOOP_IMG[$1]'
}

# new_image <tag> [mkfs option…] — a fresh 256 MiB ext4 image on a loop device. Sets LOOP and IMG.
new_image() {
  local tag="$1"; shift
  IMG="$TMPROOT/$tag.img"
  truncate -s 256M "$IMG" || instrument "truncate failed for $tag"
  mkfs.ext4 -q -F "$@" "$IMG" >/dev/null 2>&1 || instrument "mkfs.ext4 failed for $tag"
  attach "$IMG"
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
# (It needs a dirty journal, not a journal-only entry: its post-replay tree is empty either way.)
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

# Both run inside `$( )`, so their `instrument` only ends the subshell: every call site re-checks.
# origin_sha <loop> — sha256 of the loop's BACKING FILE, after flushing the loop's page cache. A
# write that reaches the origin through the dm layer is a bio: it bypasses the loop device's page
# cache, so a hash read through /dev/loopN could be served stale pages that an earlier read filled.
origin_sha() {
  local img="${LOOP_IMG[$1]:-}"
  [ -f "$img" ] || instrument "no backing file recorded for $1"
  blockdev --flushbufs "$1" || instrument "blockdev --flushbufs $1 failed"
  sha256sum < "$img"
}
# origin_wstat <loop> — "<sectors written> <sectors discarded>" (sysfs stat fields 7 and 14).
origin_wstat() {
  local f
  read -r -a f < "/sys/class/block/${1##*/}/stat" || instrument "the sysfs stat of $1 is unreadable"
  [ "${#f[@]}" -ge 14 ] || instrument "the sysfs stat of $1 has no discard fields (${#f[@]} fields)"
  printf '%s %s' "${f[6]}" "${f[13]}"
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
M1_SHA_BEFORE="$(origin_sha "$M1_LOOP")" || instrument "hashing the M1 origin failed"
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
M1_SHA_AFTER="$(origin_sha "$M1_LOOP")" || instrument "hashing the M1 origin failed"
if [ "$M1_SHA_BEFORE" = "$M1_SHA_AFTER" ]; then ok "M1 the origin's bytes are unchanged (sha256 of the backing file)"; else no "M1 the origin's bytes CHANGED — the snapshot wrote the retained device"; fi
if [ "$(blockdev --getro "$M1_LOOP")" = 1 ]; then ok "M1 the origin is still kernel read-only after teardown"; else no "M1 the origin is no longer read-only after teardown"; fi

# ═══ SUT TIER — the REAL extracted plaintext-count unit, on real loop devices ═══════
# The unit is extracted by its inner sentinels (it spans the real _repo_count definition through
# the end of the plaintext block, so arm C tests the real counter, not a copy). log() is copied out
# of the script. Each arm runs the unit in a CHILD bash (the unit `exit`s and arms an EXIT trap);
# the parent measures the origin's bytes, its sector counters, its read-only flag and the
# transient-device leaks.
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
printf 'printf "plaintext_journal=%%s\\n" "$_plaintext_journal"\nprintf "plaintext_volume=%%s\\n" "$_plaintext_volume"\nprintf "plaintext_count=%%s\\n" "${_pt_n:-}"\n' > "$PT_TRAILER" || instrument "trailer write failed"

# pt_mutant <name> <old> <new> — the unit with exactly one occurrence of <old> replaced. Sets MUT.
pt_mutant() {
  MUT="$TMPROOT/pt-unit.$1"
  python3 - "$PT_UNIT" "$MUT" "$2" "$3" <<'PY' || instrument "mutant $1: the anchor is not unique in the unit"
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
assert s.count(old) == 1
open(dst, "w").write(s.replace(old, new))
PY
  if cmp -s "$PT_UNIT" "$MUT"; then no "$1 the mutation did not land"; else ok "$1 the mutation landed"; fi
}

ARMS_RAN=0
# Only THIS suite's own apparatus is compared, never the whole host: loop devices backed by this
# run's images or by a /dev/shm COW, the two dm names this suite and the unit use, and /dev/shm
# directories carrying the unit's cow/mnt shape. A shared runner's unrelated /dev/shm churn cannot
# flake the row, and a leak of ours still shows.
leak_state() {
  { losetup -a 2>/dev/null | grep -E "\\(($TMPROOT/|/dev/shm/)" | sort || true
    echo ---
    dmsetup ls 2>/dev/null | grep -E '^(git-data-pt-snap|gd-pt-mech)[[:space:]]' | sort || true
    echo ---
    ls -d /dev/shm/*/cow /dev/shm/*/mnt 2>/dev/null | sort || true; }
}

# run_sut <arm> <origin-loop> [unit-file] — runs the unit as a child; sets SUT_RC, SUT_OUT, SUT_ERR,
# and asserts the five invariants every arm owes: bytes and sector counters unchanged, still
# kernel-ro, no leak, and no snapshot device left behind. SUT_EXPECT_WRITE=1 (the write mutant)
# inverts the first two: there they are the instrument proving the write landed.
SUT_EXPECT_WRITE=0
run_sut() {
  local arm="$1" loop="$2" unit="${3:-$PT_UNIT}" sha0 sha1 w0 w1 leak0 leak1
  ARMS_RAN=$((ARMS_RAN + 1))
  SUT_OUT="$TMPROOT/$arm.out"; SUT_ERR="$TMPROOT/$arm.err"
  sync
  sha0="$(origin_sha "$loop")" || instrument "$arm: hashing the origin failed"
  w0="$(origin_wstat "$loop")" || instrument "$arm: the origin's sysfs stat is unreadable"
  leak0="$(leak_state)"
  SUT_RC=0
  env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin GIT_DATA_PLAINTEXT_VOLUME_ID=424242424 GIT_DATA_PLAINTEXT_DEV="$loop" \
    bash -c 'set -euo pipefail; . "$1"; _plaintext_volume=absent; . "$2"; . "$3"' _ "$PT_PRELUDE" "$unit" "$PT_TRAILER" \
    > "$SUT_OUT" 2> "$SUT_ERR" || SUT_RC=$?
  sha1="$(origin_sha "$loop")" || instrument "$arm: hashing the origin failed"
  w1="$(origin_wstat "$loop")" || instrument "$arm: the origin's sysfs stat is unreadable"
  leak1="$(leak_state)"
  if [ "$SUT_EXPECT_WRITE" = 1 ]; then
    if [ "$sha0" != "$sha1" ]; then ok "$arm instrument: the mutant's write reached the origin's backing file"; else no "$arm instrument: the mutant's write never reached the origin — the arm proves nothing"; fi
    if [ "$w0" != "$w1" ]; then ok "$arm instrument: the origin's sector counters moved ($w0 -> $w1)"; else no "$arm instrument: the origin's sector counters did not move ($w0)"; fi
  else
    if [ "$sha0" = "$sha1" ]; then ok "$arm the origin's bytes are unchanged (sha256 of the backing file)"; else no "$arm the origin's bytes CHANGED — the unit wrote the retained device"; fi
    if [ "$w0" = "$w1" ]; then ok "$arm the origin's sectors written/discarded are unchanged ($w0)"; else no "$arm the origin's sector counters moved ($w0 -> $w1)"; fi
  fi
  if [ "$(blockdev --getro "$loop")" = 1 ]; then ok "$arm the origin is kernel read-only after the unit"; else no "$arm the origin is NOT read-only after the unit"; fi
  if [ "$leak0" = "$leak1" ]; then ok "$arm no loop, dm device or /dev/shm entry of this suite survives (baseline-relative)"; else no "$arm transient state leaked: $(diff <(printf '%s\n' "$leak0") <(printf '%s\n' "$leak1") | tr '\n' ' ')"; fi
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
no_residue() { # <arm>
  if grep -qF 'plaintext_residue' "$SUT_ERR"; then no "$1 produced a residue verdict"; else ok "$1 no residue verdict"; fi
}

# populate <loop> <cmd…> — mount rw, run a shell snippet in the mount, unmount cleanly.
populate() {
  local loop="$1" snippet="$2" mnt="$TMPROOT/pop-mnt"
  mkdir -p "$mnt" || instrument "mkdir $mnt failed"
  mount -o rw "$loop" "$mnt" || instrument "rw mount of $loop failed"
  ( cd "$mnt" && eval "$snippet" ) || { umount "$mnt"; instrument "populate snippet failed: $snippet"; }
  umount "$mnt" || instrument "umount after populate failed"
}

# journal_only_residue <tag> <flag> — arm C's deterministic build: a checkpointed anchor, then a
# repository created, its directory fsync'd and the filesystem shut down FROM THE SAME PROCESS, and
# the backing file COPIED BEFORE the umount. The fsync commits the transaction to the journal, but
# the directory block's HOME copy is only a dirty buffer in the loop device's page cache: umount's
# sync_blockdev (and the last-close flush) would write it home, which is why a build that umounted
# first found ws-1.git in the home blocks on every attempt (CI runs 35988639183, 35990774557). The
# copy is taken while those writes have not happened, and it — not the original — becomes the arm's
# image, on a FRESH loop device (empty page cache). The anchor is named like a lock dotfile so the
# unit's count excludes it, while debugfs still lists it (proving it read the right directory).
# Sets ARM_LOOP / ARM_IMG. Returns 1 when the precondition does not hold.
journal_only_residue() {
  local tag="$1" flag="$2" mnt="$TMPROOT/jor-mnt" ls orig_loop orig_img copy="$TMPROOT/$1.jo.img"
  new_image "$tag"; orig_loop="$LOOP"; orig_img="$IMG"
  populate "$orig_loop" 'mkdir -p repositories && : > repositories/.anchor.init.lock'
  mkdir -p "$mnt" || instrument "mkdir $mnt failed"
  mount -o rw "$orig_loop" "$mnt" || instrument "rw mount of $orig_loop failed"
  CLEAN_MOUNTS+=("$mnt")
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
  cp --sparse=always "$orig_img" "$copy" || instrument "copying the shut-down image failed"
  umount "$mnt" || instrument "umount after shutdown failed"
  detach "$orig_loop"
  rm -f "$orig_img"
  attach "$copy"
  ARM_LOOP="$LOOP"; ARM_IMG="$copy"
  needs_recovery "$ARM_LOOP" || return 1
  ls="$(debugfs -c -R 'ls -l /repositories' "$ARM_LOOP" 2>/dev/null)" || return 1
  [[ "$ls" == *".anchor.init.lock"* ]] || return 1
  [[ "$ls" != *"ws-1.git"* ]] || return 1
  return 0
}
# build_arm_c <tag> <flag> — up to 3 attempts, then an INSTRUMENT exit (never green).
build_arm_c() {
  local tag="$1" flag="$2" try
  for try in 1 2 3; do
    if journal_only_residue "$tag-$try" "$flag"; then return 0; fi
  done
  instrument "arm $tag: after 3 builds the entry was not journal-only (debugfs listed it, or did not list the anchor)"
}

# build_bad_dirblock <tag> [mkfs option…] — repositories/ws-e.git, then the repositories/ directory
# block overwritten with random bytes so it fails its metadata checksum. Sets ARM_LOOP.
build_bad_dirblock() {
  local tag="$1" blk bs; shift
  new_image "$tag" "$@"; ARM_LOOP="$LOOP"
  populate "$ARM_LOOP" 'mkdir -p repositories/ws-e.git'
  blk="$(debugfs -c -R 'blocks /repositories' "$ARM_LOOP" 2>/dev/null | awk 'NF{print $1; exit}')"
  [[ "$blk" =~ ^[0-9]+$ ]] || instrument "arm $tag: could not read the repositories/ directory block"
  bs="$(dumpe2fs -h "$ARM_LOOP" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')"
  [[ "$bs" =~ ^[0-9]+$ ]] || instrument "arm $tag: could not read the block size"
  dd if=/dev/urandom of="$ARM_LOOP" bs="$bs" seek="$blk" count=1 conv=notrunc,fsync status=none || instrument "arm $tag: corrupting the directory block failed"
  blockdev --flushbufs "$ARM_LOOP" || instrument "arm $tag: flushbufs failed"
}

# oracle_count <img> — an INDEPENDENT replay: a rw mount of a copy (the kernel replays the journal
# onto the copy), counted with the unit's exclusions. Sets ORACLE_N (global; NOT `$(fn)`).
oracle_count() {
  local copy="$TMPROOT/oracle.img" mnt="$TMPROOT/oracle-mnt" oloop
  cp --sparse=always "$1" "$copy" || instrument "oracle: copying $1 failed"
  attach "$copy"; oloop="$LOOP"
  mkdir -p "$mnt" || instrument "oracle: mkdir failed"
  mount -o rw "$oloop" "$mnt" || instrument "oracle: the rw mount (a real replay) of $1 failed"
  CLEAN_MOUNTS+=("$mnt")
  ORACLE_N="$(find "$mnt/repositories" -mindepth 1 -maxdepth 1 ! -name '.*.init.lock' ! -name lost+found 2>/dev/null | wc -l)"
  umount "$mnt" || instrument "oracle: umount failed"
  detach "$oloop"
  rm -f "$copy"
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

# ── D: COW overflow → a named FATAL that SAYS overflow, never a residue verdict or a PASS ──
# 8192 bytes is two 4 KiB chunks: arm C's replay writes more blocks than that, so the snapshot
# must invalidate (65536 = 16 chunks could hold the whole replay and never overflow).
MUTD="$TMPROOT/pt-unit.cowtiny"
python3 - "$PT_UNIT" "$MUTD" <<'PY' || instrument "the arm-D rebinding could not be written"
import sys
s = open(sys.argv[1]).read()
a = '_pt_cow_bytes=$((_pt_jb * _pt_bs + 67108864))'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, '_pt_cow_bytes=8192'))
PY
cmp -s "$PT_UNIT" "$MUTD" && instrument "the arm-D COW rebinding did not land"
build_arm_c d 1; D_LOOP="$ARM_LOOP"
run_sut D "$D_LOOP" "$MUTD"
if [ "$SUT_RC" != 0 ] && grep -qE 'FATAL: plaintext_unverified reason=(snapshot|mount) .*(kernel=overflow|cow=Invalid)' "$SUT_ERR"; then
  ok "D a COW overflow is a named FATAL carrying the overflow classifier or the Invalid snapshot status"
else
  no "D expected reason=snapshot|mount with kernel=overflow or cow=Invalid (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"
fi
no_residue D

# ── E: a LINEAR directory block that fails its checksum → the errors_count FATAL, not a short count ──
# dir_index off, so readdir takes the linear path, which SKIPS a checksum-failed block with only an
# "EXT4-fs error" log line and returns success: find exits 0 on a short count. Only errors_count
# moving across the count can see it.
build_bad_dirblock e -O ^dir_index; E_LOOP="$ARM_LOOP"
run_sut E "$E_LOOP"
sut_fatal E 'FATAL: plaintext_unverified reason=journal — ext4 logged an error during the count (errors_count 0 -> '

# ── G1-9 (real kernel): drop the post-count errors_count check → that short count PASSES as 0 ──
pt_mutant G1-9 '  [ "$_pt_e1" = "$_pt_e0" ] || {' '  true || {'
build_bad_dirblock e9 -O ^dir_index; E9_LOOP="$ARM_LOOP"
run_sut G1-9 "$E9_LOOP" "$MUT"
if [ "$SUT_RC" = 0 ]; then ok "G1-9 ROW 9: without the post-count check the mutant PASSES (the skip was silent) — the arm is live"; else no "G1-9 the mutant did not pass (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"; fi
if [ "$(sut_field plaintext_count)" = 0 ]; then ok "G1-9 and it counted 0 entries on a volume holding repositories/ws-e.git"; else no "G1-9 count '$(sut_field plaintext_count)', expected the silent-skip 0"; fi

# ── E2: the same corruption with the default features (dir_index on) → a named FATAL either way ──
# A single-block directory under dir_index is read in hash order through the htree path, which may
# return the checksum error to readdir instead of skipping; then find fails and the unit reports
# reason=mount. Both are refusals; what may never happen is a PASS or a residue verdict.
build_bad_dirblock e2; E2_LOOP="$ARM_LOOP"
run_sut E2 "$E2_LOOP"
if [ "$SUT_RC" != 0 ] && grep -qE 'FATAL: plaintext_unverified reason=(journal|mount) ' "$SUT_ERR"; then
  ok "E2 a checksum-failed dir_index directory is a named FATAL reason=journal|mount"
else
  no "E2 expected reason=journal|mount (rc=$SUT_RC): $(tr '\n' ' ' < "$SUT_ERR")"
fi
no_residue E2

# ── F: a TORN transaction — the commit block of the transaction that recorded ws-1.git is zeroed ──
# jbd2 treats a transaction without a valid commit block as the end of the log, so replay stops
# before it and the post-replay tree is the OLDER one, without ws-1.git. Two independent rw replays
# of copies pin both sides: the intact journal yields 1 entry, the torn one 0. The unit must agree
# with the torn replay (PASS, dirty, count 0). The first commit block in the log is zeroed: after
# the populate's clean unmount every transaction in the log belongs to the build's second mount,
# so ending the log there discards the mkdir whichever transaction carried it.
build_arm_c f 1; F_LOOP="$ARM_LOOP"; F_IMG="$ARM_IMG"
detach "$F_LOOP"
oracle_count "$F_IMG"; F_ORACLE_INTACT="$ORACLE_N"
[ "$F_ORACLE_INTACT" = 1 ] || instrument "arm F: an rw replay of the intact journal counts $F_ORACLE_INTACT, expected 1 — the journal does not carry ws-1.git"
F_JB="$(debugfs -c -R 'logdump' "$F_IMG" 2>/dev/null | awk '/type 2 \(commit block\) at block/{print $NF; exit}')"
[[ "$F_JB" =~ ^[0-9]+$ ]] || instrument "arm F: debugfs logdump shows no commit block"
F_PB="$(debugfs -c -R "bmap <8> $F_JB" "$F_IMG" 2>/dev/null)"
[[ "$F_PB" =~ ^[0-9]+$ ]] || instrument "arm F: could not map journal block $F_JB to a disk block"
F_BS="$(dumpe2fs -h "$F_IMG" 2>/dev/null | sed -n 's/^Block size:[[:space:]]*//p')"
[[ "$F_BS" =~ ^[0-9]+$ ]] || instrument "arm F: could not read the block size"
dd if=/dev/zero of="$F_IMG" bs="$F_BS" seek="$F_PB" count=1 conv=notrunc,fsync status=none || instrument "arm F: zeroing the commit block failed"
oracle_count "$F_IMG"; F_ORACLE_TORN="$ORACLE_N"
[ "$F_ORACLE_TORN" = 0 ] || instrument "arm F: an rw replay of the torn journal still counts $F_ORACLE_TORN — the tear did not land"
attach "$F_IMG"; F_LOOP="$LOOP"
run_sut F "$F_LOOP"
sut_pass F dirty
if [ "$(sut_field plaintext_count)" = "$F_ORACLE_TORN" ] && [ "$F_ORACLE_TORN" != "$F_ORACLE_INTACT" ]; then
  ok "F the unit counts $F_ORACLE_TORN like the independent replay of the torn journal (the intact one counts $F_ORACLE_INTACT)"
else
  no "F count '$(sut_field plaintext_count)' vs torn replay $F_ORACLE_TORN / intact replay $F_ORACLE_INTACT"
fi

# ── W: a write that reaches the origin between --setro and the release → the counter FATAL ──
# The block layer only WARNS (once per device) when a write bio reaches a read-only disk, so the ro
# flag is not what stops this; the sysfs counter comparison is. The mutant clears the flag, writes
# one sector of the (unused) boot area, and sets it again, so the arm isolates the counter check.
pt_mutant W '  _pt_valid
  _pt_release
' '  _pt_valid
  blockdev --setrw "$_pt_dev"; dd if=/dev/urandom of="$_pt_dev" bs=512 count=1 oflag=direct status=none; blockdev --setro "$_pt_dev"
  _pt_release
'
new_image w; W_LOOP="$LOOP"
populate "$W_LOOP" 'mkdir -p repositories'
SUT_EXPECT_WRITE=1
run_sut W "$W_LOOP" "$MUT"
SUT_EXPECT_WRITE=0
sut_fatal W 'reason=snapshot — '"$W_LOOP"' was written or discarded (sectors '

# ── L: repositories is a SYMLINK on the volume → refused, never followed, never counted as 0 ──
new_image l; L_LOOP="$LOOP"
populate "$L_LOOP" 'mkdir -p real/ws-l.git && ln -s real repositories'
run_sut L "$L_LOOP"
sut_fatal L "FATAL: plaintext_unverified reason=source — the snapshot's repositories is not a directory"
no_residue L

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only, reported by printf + exit and
# never through ok()/no() (ADR-193) — a floor routed through the helpers it backstops is silenced by
# the same edit that silences the arms. Each bound is a literal on the line directly above its `if`
# so guard-vacuity-floor.test.sh can construct the mutant.
# COUNTED FROM THE SOURCE, NOT YET MEASURED ON CI (the authoring machine has no passwordless
# sudo): mechanism N0 = 2, M1 = 9; every run_sut arm owes 5; SUT A = 7, B = 8, C = 8, G1-4 = 7,
# D = 7, E = 6, G1-9 = 8, E2 = 7, F = 8, W = 7, L = 7 (91 total, 11 arms). CI measures both; the
# first green run confirms or corrects them, arm by arm, before either literal moves again.
EXPECTED_ARMS=11
if [ "$ARMS_RAN" -ne "$EXPECTED_ARMS" ]; then
  printf '[FATAL] anti-vacuity floor: %s SUT arms ran, expected exactly %s (A, B, C, G1-4, D, E, G1-9, E2, F, W, L)\n' "$ARMS_RAN" "$EXPECTED_ARMS" >&2
  exit 1
fi
MIN_ASSERTIONS=91
if [ "$executed" -lt "$MIN_ASSERTIONS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s — arms were deleted, skipped, or the suite exited early\n' "$executed" "$MIN_ASSERTIONS" >&2
  exit 1
fi
printf 'ok   - anti-vacuity floor: %s assertions over %s SUT arms (floors %s / %s)\n' "$executed" "$ARMS_RAN" "$MIN_ASSERTIONS" "$EXPECTED_ARMS"

echo ""
echo "=== git-data-plaintext-snapshot-loopback.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
