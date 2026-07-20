#!/usr/bin/env bash
#
# REAL-DEVICE evidence for workspaces-cutover.sh :: prepare_staging_target (#6588 / epic #6604).
#
# Every other workspaces-luks suite stubs the block layer. This one does NOT: it builds a real
# loopback device, runs a real `cryptsetup luksFormat` + `luksOpen`, and drives the REAL
# prepare_staging_target against the resulting mapper. That is the only way to prove the thing the
# 2026-07-19 incident disproved — that the bytes land on the MAPPER and not on the root disk.
#
# THE DEFECT BEING GUARDED (origin/main content anchor: the two lines
#   `mkdir -p "$STAGING"`
#   `[ "$DRY_RUN" = "1" ] || { mountpoint -q "$STAGING" || mount "$MAPPER" "$STAGING"; }`
# in the cutover main body, with NO mkfs anywhere): the script luksFormat'd and luksOpen'd but never
# ran mkfs, so the mapper carried no filesystem and `mount` failed with `wrong fs type, bad option,
# bad superblock`. Under `set -uo pipefail` with no `-e` that failure was SWALLOWED, and the
# `mkdir -p` immediately above had already created $STAGING as a plain directory ON THE ROOT DISK.
# Everything downstream rsynced onto the root disk and every gate certified it, because C1, the `du`
# assert and the G3 manifest are pure functions of the STRINGS "$MOUNT" and "$STAGING" — nothing in
# that closure anchors either string to a block device. Case L5a REPRODUCES that, verbatim, on a
# real mapper.
#
# NO SILENT SKIP. If losetup/cryptsetup/mkfs.ext4/mount are unavailable, or the run lacks the
# privileges to use them, this suite exits NON-ZERO with the literal token LOOPBACK_UNAVAILABLE.
# A conditional self-skip is the exact fail-open class this whole change exists to remove: a suite
# that greens without touching a device is indistinguishable from a suite that greened wrongly.
#
# Harness conventions (from this repo's own harness post-mortems — these are load-bearing):
#   - NEVER pipe into an assertion predicate. Under `set -o pipefail` an early `grep -q` match
#     SIGPIPEs the producer (141) and a NEGATIVE assertion then fails OPEN. Every assertion below
#     greps a FILE directly.
#   - Every happy-path case captures and asserts the case's REAL rc, so an assertion reading a file
#     populated before an unrelated die() cannot pass vacuously.
#   - mktemp for every path (parallel worktrees are this repo's normal workflow); dm names and
#     backing files are $$-scoped so two concurrent runs cannot collide.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

pass=0
fail=0
executed=0
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1"; }
note() { printf '     %s\n' "$*"; }

# unavailable — the fail-CLOSED exit. Exits non-zero with the literal token so CI reads it as a
# RED suite, never as a pass. Deliberately NOT `exit 0`.
unavailable() {
  echo "LOOPBACK_UNAVAILABLE: $*" >&2
  echo "workspaces-luks-loopback: LOOPBACK_UNAVAILABLE — real-device evidence was NOT collected." >&2
  echo "This is a FAILURE, not a skip: run this suite as root on a host with losetup + cryptsetup" >&2
  echo "+ mkfs.ext4 + a dm-crypt-capable kernel (GitHub-hosted ubuntu runners qualify, via sudo)." >&2
  exit 2
}

# --- Privilege ---------------------------------------------------------------
# losetup / cryptsetup / mount all require root. Self-elevate via passwordless sudo when available
# (GH-hosted runners have it); otherwise fail closed with the token.
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    # No -E: sudoers on GH-hosted runners does not necessarily grant SETENV, and this suite needs
    # nothing from the caller's environment.
    exec sudo -n bash "${BASH_SOURCE[0]}" "$@"
  fi
  unavailable "not running as root and passwordless sudo is unavailable"
fi

# --- Binaries ----------------------------------------------------------------
for b in losetup cryptsetup mkfs.ext4 mount umount findmnt blkid mountpoint rsync du df git; do
  command -v "$b" >/dev/null 2>&1 || unavailable "required binary '$b' not found on PATH"
done
[ -f "$CUTOVER" ] || unavailable "cutover script not found at $CUTOVER"

# --- Teardown ----------------------------------------------------------------
CLEAN_MOUNTS=()
CLEAN_MAPPERS=()
CLEAN_LOOPS=()
TMPROOT=""

teardown() {
  local i m
  for ((i = ${#CLEAN_MOUNTS[@]} - 1; i >= 0; i--)); do
    m="${CLEAN_MOUNTS[$i]}"
    # A mountpoint may be stacked (L5c mounts tmpfs where a mapper mount may also live), so drain
    # it rather than assuming a single umount suffices.
    for _ in 1 2 3; do
      mountpoint -q "$m" 2>/dev/null || break
      umount "$m" >/dev/null 2>&1 || umount -l "$m" >/dev/null 2>&1 || break
    done
  done
  for ((i = ${#CLEAN_MAPPERS[@]} - 1; i >= 0; i--)); do
    cryptsetup status "${CLEAN_MAPPERS[$i]}" >/dev/null 2>&1 && \
      cryptsetup close "${CLEAN_MAPPERS[$i]}" >/dev/null 2>&1
  done
  for ((i = ${#CLEAN_LOOPS[@]} - 1; i >= 0; i--)); do
    losetup -d "${CLEAN_LOOPS[$i]}" >/dev/null 2>&1
  done
  [ -n "$TMPROOT" ] && rm -rf "$TMPROOT" >/dev/null 2>&1
  return 0
}
trap teardown EXIT

TMPROOT="$(mktemp -d)" || unavailable "mktemp -d failed"
KEYFILE="$TMPROOT/luks.key"
# Synthesized test passphrase — never a real credential (cq-test-fixtures-synthesized-only).
printf 'loopback-suite-throwaway-passphrase-%s' "$$" > "$KEYFILE"
chmod 600 "$KEYFILE"

# new_session <tag> — backing file -> loop device -> luksFormat -> luksOpen. Sets LOOP_DEV,
# MAPPER_NAME, MAPPER, SRC_DIR, STAGING_DIR. Any failure is LOOPBACK_UNAVAILABLE (a device we
# cannot build is missing evidence, not a passing case).
#
# pbkdf2 + a low iteration count is a TEST-ONLY speed/memory knob on the harness's own luksFormat;
# the SUT (prepare_staging_target) never formats, so this cannot weaken what is under test. The
# default argon2id would otherwise burn seconds and hundreds of MB per session on a CI runner.
new_session() {
  local tag="$1" backing rc
  backing="$TMPROOT/backing-${tag}.img"
  truncate -s 320M "$backing" || unavailable "truncate of $backing failed"
  LOOP_DEV="$(losetup --find --show "$backing" 2>/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] && [ -n "${LOOP_DEV:-}" ] && [ -b "$LOOP_DEV" ] \
    || unavailable "losetup could not attach $backing (rc=$rc, dev='${LOOP_DEV:-}') — no loop support?"
  CLEAN_LOOPS+=("$LOOP_DEV")

  MAPPER_NAME="wsluks-lb-$$-${tag}"
  cryptsetup luksFormat --type luks2 --batch-mode \
    --pbkdf pbkdf2 --pbkdf-force-iterations 1000 \
    --key-file "$KEYFILE" "$LOOP_DEV" >/dev/null 2>&1 \
    || unavailable "cryptsetup luksFormat failed on $LOOP_DEV"
  cryptsetup luksOpen --key-file "$KEYFILE" "$LOOP_DEV" "$MAPPER_NAME" >/dev/null 2>&1 \
    || unavailable "cryptsetup luksOpen failed on $LOOP_DEV (no dm-crypt kernel support?)"
  CLEAN_MAPPERS+=("$MAPPER_NAME")
  MAPPER="/dev/mapper/$MAPPER_NAME"
  [ -b "$MAPPER" ] || unavailable "$MAPPER is not a block device after luksOpen"

  SRC_DIR="$(mktemp -d "$TMPROOT/src-${tag}.XXXXXX")"
  STAGING_DIR="$(mktemp -d "$TMPROOT/staging-${tag}.XXXXXX")"
  CLEAN_MOUNTS+=("$STAGING_DIR")
  # $MOUNT/workspaces is what the capacity gate `du`s — it must exist on every path.
  mkdir -p "$SRC_DIR/workspaces/ws1"
  printf 'fixture-alpha\n' > "$SRC_DIR/workspaces/ws1/a.txt"
  printf 'fixture-beta\n'  > "$SRC_DIR/workspaces/ws1/b.txt"
  mkdir -p "$SRC_DIR/workspaces/ws2/nested"
  head -c 65536 /dev/urandom > "$SRC_DIR/workspaces/ws2/nested/blob.bin" 2>/dev/null \
    || printf 'blob\n' > "$SRC_DIR/workspaces/ws2/nested/blob.bin"
}

# run_prepare — drive the REAL prepare_staging_target in a fresh subshell against the real mapper.
# Sets CASE_RC, CASE_OUT (file), MARKER_LOG (file), MKFS_LOG (file).
#
# `source "$CUTOVER"` hits the sourced-detection guard (BASH_SOURCE[0] != $0), so the functions are
# defined and neither the EXIT trap nor the cutover body runs. FRESH_DEV is a bare global in the
# cutover main body, so the harness must supply it or prepare_staging_target aborts under `set -u`.
CASE_N=0
run_prepare() {
  local suppress="${1:-0}"
  CASE_N=$((CASE_N + 1))
  CASE_OUT="$TMPROOT/out.$CASE_N"
  MARKER_LOG="$TMPROOT/marker.$CASE_N"
  MKFS_LOG="$TMPROOT/mkfs.$CASE_N"
  : > "$CASE_OUT"; : > "$MARKER_LOG"; : > "$MKFS_LOG"
  MARKER_LOG="$MARKER_LOG" MKFS_LOG="$MKFS_LOG" MKFS_SUPPRESS="$suppress" \
  CUTOVER="$CUTOVER" LOOP_DEV="$LOOP_DEV" \
  WORKSPACES_MOUNT="$SRC_DIR" WORKSPACES_STAGING="$STAGING_DIR" \
  WORKSPACES_MAPPER_NAME="$MAPPER_NAME" DRY_RUN=0 \
  bash -c '
    source "$CUTOVER"                 # sourced-detection guard => functions only
    FRESH_DEV="$LOOP_DEV"             # supplied by the cutover main body in production
    logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
    die()        { echo "DIE: $*"; exit 1; }
    emit_drift() { echo "EMIT_DRIFT: $1"; }
    # Records every mkfs invocation so "no mkfs on re-run" is an OBSERVATION, not an inference.
    # MKFS_SUPPRESS=1 reproduces the incident: the call is made and reports success, but no
    # filesystem is written — exactly the state origin/main left the mapper in.
    mkfs.ext4() {
      printf "mkfs.ext4 %s\n" "$*" >> "$MKFS_LOG"
      if [ "${MKFS_SUPPRESS:-0}" = "1" ]; then return 0; fi
      command mkfs.ext4 "$@"
    }
    prepare_staging_target
  ' > "$CASE_OUT" 2>&1
  CASE_RC=$?
}

echo "workspaces-luks-loopback: real-device suite (root, loopback + dm-crypt)"
echo

# ===========================================================================
# Session A — L1 fresh device, L2 idempotent re-run, L3 byte identity, L4 SOURCE form
# ===========================================================================
new_session a
note "session A: loop=$LOOP_DEV mapper=$MAPPER staging=$STAGING_DIR"

# --- L1: fresh mapper (no filesystem) -> real mkfs, real mount, findmnt reports the mapper -------
run_prepare 0
L1_RC="$CASE_RC"; L1_OUT="$CASE_OUT"; L1_MARKER="$MARKER_LOG"; L1_MKFS="$MKFS_LOG"
L1_FSTYPE="$(blkid -p -s TYPE -o value "$MAPPER" 2>/dev/null || true)"
L1_SRC="$(findmnt -no SOURCE "$STAGING_DIR" 2>/dev/null || true)"
if [ "$L1_RC" -eq 0 ] \
  && [ -s "$L1_MKFS" ] \
  && [ "$L1_FSTYPE" = "ext4" ] \
  && mountpoint -q "$STAGING_DIR" \
  && grep -qE -- 'result=ok reason=prepared' "$L1_MARKER" \
  && grep -qE -- ' reused=0 ' "$L1_MARKER" \
  && [ -n "$L1_SRC" ]; then
  ok "L1: fresh device — real mkfs.ext4 ran, mount succeeded, mapper carries ext4, marker result=ok reused=0 (rc=0)"
else
  no "L1: fresh-device prepare failed (rc=$L1_RC fstype='$L1_FSTYPE' mkfs_log_size=$(wc -c < "$L1_MKFS") src='$L1_SRC')"
  note "out:    $(tail -n 5 "$L1_OUT" 2>/dev/null)"
  note "marker: $(cat "$L1_MARKER" 2>/dev/null)"
fi

# --- L1b: the mount SOURCE is the mapper, established by device identity (not by string equality).
# `findmnt -no SOURCE` may report either /dev/mapper/<name> or /dev/dm-N (see L4) — comparing the
# two strings would be a coin flip, so compare canonicalized st_rdev-bearing paths.
L1_SRC_REAL="$(readlink -f -- "${L1_SRC:-/nonexistent}" 2>/dev/null || true)"
MAPPER_REAL="$(readlink -f -- "$MAPPER" 2>/dev/null || true)"
if [ -n "$L1_SRC_REAL" ] && [ -n "$MAPPER_REAL" ] && [ -b "$MAPPER_REAL" ] \
  && [ "$L1_SRC_REAL" = "$MAPPER_REAL" ]; then
  ok "L1b: findmnt SOURCE for the staging mount resolves to the LUKS mapper ('$L1_SRC' -> $L1_SRC_REAL)"
else
  no "L1b: staging mount is NOT backed by the mapper (findmnt='$L1_SRC' -> '$L1_SRC_REAL', mapper -> '$MAPPER_REAL')"
fi

# --- L2: idempotent re-run -> NO mkfs, reused=1, rc 0 -------------------------------------------
run_prepare 0
L2_RC="$CASE_RC"; L2_OUT="$CASE_OUT"; L2_MARKER="$MARKER_LOG"; L2_MKFS="$MKFS_LOG"
L2_MKFS_CALLS="$(wc -l < "$L2_MKFS" 2>/dev/null || echo 1)"
if [ "$L2_RC" -eq 0 ] \
  && [ "$L2_MKFS_CALLS" -eq 0 ] \
  && grep -qE -- 'result=ok reason=prepared' "$L2_MARKER" \
  && grep -qE -- ' reused=1 ' "$L2_MARKER" \
  && grep -qE -- 'fs=ext4' "$L2_MARKER" \
  && mountpoint -q "$STAGING_DIR"; then
  ok "L2: re-run is idempotent — ZERO mkfs invocations, marker reused=1 fs=ext4, mount still held (rc=0)"
else
  no "L2: re-run not idempotent (rc=$L2_RC mkfs_calls=$L2_MKFS_CALLS)"
  note "out:    $(tail -n 5 "$L2_OUT" 2>/dev/null)"
  note "marker: $(cat "$L2_MARKER" 2>/dev/null)"
fi

# --- L3: prepare -> rsync the fixture -> verify_byte_identity reports ZERO diffs -----------------
# `--delete` on the bulk copy removes ext4's lost+found, which the itemized verify would otherwise
# (correctly) report as a `*deleting` difference.
L3_COPY_ERR="$TMPROOT/l3-copy.err"
rsync -aHAX --numeric-ids --delete "$SRC_DIR"/ "$STAGING_DIR"/ 2>"$L3_COPY_ERR"
L3_COPY_RC=$?
L3_OUT="$TMPROOT/l3.out"
L3_MARKER="$TMPROOT/l3.marker"
: > "$L3_OUT"; : > "$L3_MARKER"
MARKER_LOG="$L3_MARKER" CUTOVER="$CUTOVER" SRC="$SRC_DIR" DST="$STAGING_DIR" \
WORKSPACES_MOUNT="$SRC_DIR" WORKSPACES_STAGING="$STAGING_DIR" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  verify_byte_identity "$SRC" "$DST"
' > "$L3_OUT" 2>&1
L3_RC=$?
if [ "$L3_COPY_RC" -eq 0 ] && [ "$L3_RC" -eq 0 ] \
  && ! grep -qE -- 'SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF' "$L3_MARKER" \
  && ! grep -qE -- 'SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF' "$L3_OUT" \
  && [ -f "$STAGING_DIR/workspaces/ws1/a.txt" ]; then
  ok "L3: fixture rsynced onto the real LUKS mapper and verify_byte_identity reports 0 diffs (rc=0)"
else
  no "L3: byte-identity through dm-crypt failed (copy_rc=$L3_COPY_RC verify_rc=$L3_RC)"
  note "copy_err: $(tail -n 3 "$L3_COPY_ERR" 2>/dev/null)"
  note "out:      $(tail -n 5 "$L3_OUT" 2>/dev/null)"
fi

# --- L3b: positive control for L3 — a deliberately corrupted byte MUST flip the verify to a diff.
# Without this, L3's "0 diffs" is indistinguishable from a verify that never compared anything.
printf 'corrupted\n' > "$STAGING_DIR/workspaces/ws1/a.txt"
L3B_OUT="$TMPROOT/l3b.out"
L3B_MARKER="$TMPROOT/l3b.marker"
: > "$L3B_OUT"; : > "$L3B_MARKER"
MARKER_LOG="$L3B_MARKER" CUTOVER="$CUTOVER" SRC="$SRC_DIR" DST="$STAGING_DIR" \
WORKSPACES_MOUNT="$SRC_DIR" WORKSPACES_STAGING="$STAGING_DIR" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  verify_byte_identity "$SRC" "$DST"
' > "$L3B_OUT" 2>&1
L3B_RC=$?
if [ "$L3B_RC" -ne 0 ] && grep -qE -- 'workspaces/ws1/a\.txt' "$L3B_MARKER"; then
  ok "L3b: positive control — a corrupted byte on the mapper flips verify_byte_identity RED and names the path"
else
  no "L3b: corrupted byte did NOT flip the verify (rc=$L3B_RC) — L3's '0 diffs' would be vacuous"
  note "marker: $(cat "$L3B_MARKER" 2>/dev/null)"
fi

# --- L4: RECORD the form `findmnt -no SOURCE` actually returns (deferred-decision evidence) ------
# The cutover compares mount sources via _same_dev (readlink -f + `[ -b ]`), which is agnostic to
# which of these two forms the kernel/util-linux reports. Whether any FUTURE gate may compare the
# raw string instead depends on this observation, so record it explicitly rather than assuming.
L4_SOURCE="$(findmnt -no SOURCE "$STAGING_DIR" 2>/dev/null || true)"
L4_FORM="unknown"
case "$L4_SOURCE" in
  /dev/mapper/*) L4_FORM="mapper-name (/dev/mapper/<name>)" ;;
  /dev/dm-*)     L4_FORM="dm-number (/dev/dm-N)" ;;
  '')            L4_FORM="EMPTY" ;;
  *)             L4_FORM="other" ;;
esac
echo
echo "===== L4 EVIDENCE (deferred decision: which SOURCE form does findmnt report?) ====="
echo "  findmnt -no SOURCE '$STAGING_DIR' => '$L4_SOURCE'"
echo "  form                              => $L4_FORM"
echo "  readlink -f of that               => $(readlink -f -- "${L4_SOURCE:-/nonexistent}" 2>/dev/null || echo '<unresolvable>')"
echo "  readlink -f of \$MAPPER            => $MAPPER_REAL"
echo "  kernel: $(uname -r 2>/dev/null)   util-linux findmnt: $(findmnt --version 2>/dev/null | head -1)"
echo "  => _same_dev canonicalizes both sides, so it is correct under EITHER form. A raw-string"
echo "     comparison against \$MAPPER would be correct ONLY under the mapper-name form."
echo "=================================================================================="
echo
# L4 is EVIDENCE RECORDING, not a behavior assertion: _same_dev canonicalizes both operands, so
# the suite's verdict must not depend on WHICH form findmnt happens to report on this kernel.
# Counting it as a pass would inflate the pass total with a tautology (it "passes" whenever
# findmnt returns any string at all), and counting it as a failure would red the suite over an
# environment observation with no bearing on correctness. It is therefore reported as ADVISORY and
# deliberately does NOT touch the pass/fail counters. The behavior that matters — that the mount
# source IS the mapper under either form — is asserted by L5c/L5d.
if [ -n "$L4_SOURCE" ] && [ "$L4_FORM" != "unknown" ] && [ "$L4_FORM" != "EMPTY" ]; then
  printf 'advisory - L4: findmnt SOURCE form RECORDED as %s (%s) — evidence only, not a pass/fail gate\n' "'$L4_SOURCE'" "$L4_FORM"
else
  printf 'advisory - L4: could not record a findmnt SOURCE form (got %s) — evidence only; L5c/L5d carry the behavior assertion\n' "'$L4_SOURCE'"
fi

# ===========================================================================
# Session B — L5a incident reproduction (origin/main shape), L5b fail-closed mount
# ===========================================================================
new_session b
note "session B: loop=$LOOP_DEV mapper=$MAPPER staging=$STAGING_DIR"

# --- L5a: INCIDENT REPRODUCTION against origin/main's exact shape --------------------------------
# Runs the pre-fix two lines VERBATIM (see the content anchor in this file's header) against a real
# no-filesystem mapper, in the same `set -uo pipefail` / no-`-e` regime the cutover uses. It must
# demonstrate BOTH halves of the defect: the mount fails, AND execution CONTINUES past it with
# $STAGING a plain root-disk directory. Inlined rather than `git show`n so the reproduction is
# deterministic in any checkout depth.
L5A_OUT="$TMPROOT/l5a.out"
: > "$L5A_OUT"
STAGING="$STAGING_DIR" MAPPER="$MAPPER" bash -c '
  set -uo pipefail
  DRY_RUN=0
  # >>> verbatim origin/main shape (no mkfs anywhere above it) >>>
  mkdir -p "$STAGING"
  [ "$DRY_RUN" = "1" ] || { mountpoint -q "$STAGING" || mount "$MAPPER" "$STAGING"; }
  # <<< end verbatim <<<
  echo "LEGACY_RC=$?"
  echo "LEGACY_REACHED_END=1"
' > "$L5A_OUT" 2>&1
L5A_RC=$?
L5A_SRC="$(findmnt -no SOURCE "$STAGING_DIR" 2>/dev/null || true)"
# LEGACY_RC is the captured status of the `mountpoint || mount` line itself. Asserting only that
# execution REACHED THE END cannot tell "mount ran and FAILED" (the incident) from "mount never ran
# at all" (e.g. the binary missing from PATH) — both leave $STAGING an empty root-disk directory
# with no source, so every other condition below is satisfied either way and the reproduction would
# be vacuous. A non-zero LEGACY_RC is what proves the mount was actually attempted and rejected.
L5A_LEGACY_RC="$(awk -F= '/^LEGACY_RC=/{print $2; exit}' "$L5A_OUT")"
if [ "$L5A_RC" -eq 0 ] \
  && grep -qE -- '^LEGACY_REACHED_END=1$' "$L5A_OUT" \
  && [ -n "$L5A_LEGACY_RC" ] && [ "$L5A_LEGACY_RC" -ne 0 ] \
  && ! mountpoint -q "$STAGING_DIR" \
  && [ -d "$STAGING_DIR" ] \
  && [ -z "$L5A_SRC" ]; then
  ok "L5a: INCIDENT REPRODUCED — the mount was ATTEMPTED and FAILED (rc=$L5A_LEGACY_RC), the origin/main lines swallowed it, execution continued, and \$STAGING is a plain ROOT-DISK directory (src='<none>')"
else
  no "L5a: could not reproduce the incident (rc=$L5A_RC legacy_rc='${L5A_LEGACY_RC:-<unread>}' mountpoint=$(mountpoint -q "$STAGING_DIR" && echo yes || echo no) src='$L5A_SRC')"
  note "out: $(cat "$L5A_OUT" 2>/dev/null)"
fi

# --- L5b: the FIX is fail-CLOSED — suppress mkfs, mount must fail LOUDLY -------------------------
# Same physical precondition as L5a (a mapper with no filesystem), driven through the real
# prepare_staging_target. It must die, emit result=fail reason=mount_failed on the marker channel,
# and route staging_mount_failed to the drift/Sentry channel.
run_prepare 1
L5B_RC="$CASE_RC"; L5B_OUT="$CASE_OUT"; L5B_MARKER="$MARKER_LOG"; L5B_MKFS="$MKFS_LOG"
if [ "$L5B_RC" -ne 0 ] \
  && [ -s "$L5B_MKFS" ] \
  && grep -qE -- 'result=fail reason=mount_failed' "$L5B_MARKER" \
  && grep -qE -- 'EMIT_DRIFT: staging_mount_failed' "$L5B_OUT" \
  && grep -qE -- 'DIE: cannot mount' "$L5B_OUT" \
  && ! mountpoint -q "$STAGING_DIR"; then
  ok "L5b: with mkfs suppressed the fixed prepare_staging_target FAILS CLOSED — dies, marker reason=mount_failed, drift staging_mount_failed"
else
  no "L5b: suppressed mkfs did not fail closed (rc=$L5B_RC)"
  note "out:    $(tail -n 5 "$L5B_OUT" 2>/dev/null)"
  note "marker: $(cat "$L5B_MARKER" 2>/dev/null)"
fi

# --- L5b-note: the two cases share a physical precondition; only the SUT differs. Assert that
# explicitly so the pair reads as one controlled experiment rather than two unrelated cases.
if [ "$L5A_RC" -eq 0 ] && [ "$L5B_RC" -ne 0 ]; then
  ok "L5b-control: same no-filesystem mapper — origin/main shape continues (rc=0), fixed prepare aborts (rc=$L5B_RC)"
else
  no "L5b-control: the pre/post contrast did not hold (legacy rc=$L5A_RC fixed rc=$L5B_RC)"
fi

# ===========================================================================
# Session C — L5c positive control: mount FORCED to a non-mapper target
# ===========================================================================
new_session c
note "session C: loop=$LOOP_DEV mapper=$MAPPER staging=$STAGING_DIR"

# Pre-mount a tmpfs at $STAGING. prepare_staging_target then mkfs's the mapper for real, finds
# $STAGING already a mountpoint and skips its own mount — so the ONLY thing standing between the
# copy and the wrong device is the positive control (`findmnt SOURCE` must BE the mapper). This is
# the shape the incident took: a real, writable, non-mapper $STAGING.
if ! mount -t tmpfs -o size=16M tmpfs "$STAGING_DIR" >/dev/null 2>&1; then
  unavailable "could not mount tmpfs at $STAGING_DIR for the L5c positive control"
fi
run_prepare 0
L5C_RC="$CASE_RC"; L5C_OUT="$CASE_OUT"; L5C_MARKER="$MARKER_LOG"
L5C_SRC="$(findmnt -no SOURCE "$STAGING_DIR" 2>/dev/null || true)"
if [ "$L5C_RC" -ne 0 ] \
  && grep -qE -- 'result=fail reason=source_not_mapper' "$L5C_MARKER" \
  && grep -qE -- 'EMIT_DRIFT: staging_not_mapper' "$L5C_OUT" \
  && grep -qE -- 'refusing to copy onto an unverified target' "$L5C_OUT"; then
  ok "L5c: POSITIVE CONTROL fires — a mounted-but-not-the-mapper \$STAGING (src='$L5C_SRC') aborts with reason=source_not_mapper"
else
  no "L5c: positive control did not catch a non-mapper staging target (rc=$L5C_RC src='$L5C_SRC')"
  note "out:    $(tail -n 5 "$L5C_OUT" 2>/dev/null)"
  note "marker: $(cat "$L5C_MARKER" 2>/dev/null)"
fi

# --- L5d: MUTATION — delete the positive control from a copy of the cutover; L5c MUST flip green.
# Proves the `_same_dev "$staging_src" "$MAPPER"` guard is load-bearing and not decorative: without
# it, prepare_staging_target certifies the tmpfs target and the copy proceeds onto the wrong device.
MUT="$(mktemp "$TMPROOT/mut-cutover.XXXXXX.sh")"
cp "$CUTOVER" "$MUT"
# TARGETED mutation: make ONLY the staging positive control vacuous, by turning its predicate into
# an unconditional `true`. Neutering _same_dev wholesale would be wrong — the SAME helper backs the
# already_cutover check, where `return 0` makes an EMPTY $MOUNT source compare equal to the mapper
# and the run dies as already_cutover, i.e. the mutant would go red for an unrelated reason and
# "prove" nothing. `%` is the sed delimiter: the PATTERN contains `|` and the REPLACEMENT contains
# `#`, so neither of the two obvious delimiters is usable here.
sed -i 's%^  _same_dev "\$staging_src" "\$MAPPER" || {$%  true || {  # MUTATED-vacuous-positive-control%' "$MUT"
if ! grep -qE -- '^  true \|\| \{  # MUTATED-vacuous-positive-control$' "$MUT"; then
  no "L5d: mutation sed did NOT land (_same_dev body unchanged) — treat as un-run, not as evidence"
else
  MUT_OUT="$TMPROOT/l5d.out"
  MUT_MARKER="$TMPROOT/l5d.marker"
  : > "$MUT_OUT"; : > "$MUT_MARKER"
  MARKER_LOG="$MUT_MARKER" MKFS_LOG="$TMPROOT/l5d.mkfs" MKFS_SUPPRESS=0 \
  CUTOVER="$MUT" LOOP_DEV="$LOOP_DEV" \
  WORKSPACES_MOUNT="$SRC_DIR" WORKSPACES_STAGING="$STAGING_DIR" \
  WORKSPACES_MAPPER_NAME="$MAPPER_NAME" DRY_RUN=0 \
  bash -c '
    source "$CUTOVER"
    FRESH_DEV="$LOOP_DEV"
    logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
    die()        { echo "DIE: $*"; exit 1; }
    emit_drift() { echo "EMIT_DRIFT: $1"; }
    mkfs.ext4()  { printf "mkfs.ext4 %s\n" "$*" >> "$MKFS_LOG"; command mkfs.ext4 "$@"; }
    prepare_staging_target
  ' > "$MUT_OUT" 2>&1
  MUT_RC=$?
  if [ "$MUT_RC" -eq 0 ] && ! grep -qE -- 'reason=source_not_mapper' "$MUT_MARKER"; then
    ok "L5d: mutation (staging positive control made vacuous) flips L5c GREEN — the guard is load-bearing"
  else
    no "L5d: mutation did not flip L5c (rc=$MUT_RC) — the positive control assertion may be vacuous"
    note "out: $(tail -n 5 "$MUT_OUT" 2>/dev/null)"
  fi
fi

# ===========================================================================
# SESSION D — verify_git_fsck_differential + fsck_advisory_probe (#6733 follow-up)
# ===========================================================================
# The gate this session guards replaced an rc-only, evidence-discarding loop
#   `git -C "$ws" fsck --full >/dev/null 2>&1 || { fsck_fail=…; log "FSCK FAIL: $ws"; }`
# which aborted real cutover 29725194755 on 8 of 10 workspaces with no way to tell a corrupt object
# from a benign pre-existing repo condition. Two properties are under test and they pull in OPPOSITE
# directions, which is exactly why both need cases:
#   (B) a pre-existing fault present on BOTH sides must NOT abort   (L6c)
#   (A) a probe that could not INSPECT must abort, never classify `preexisting` (L6e)
# Without (A), (B) degrades into a permanently blind gate that greens while inspecting zero objects.
#
# FIXTURE DISCIPLINE: production workspace repos are owned by uid 1001 (Dockerfile `USER soleur`)
# and the cutover runs as root, so every fixture repo is chown'd 1001:1001 on BOTH sides. A
# root-owned fixture would never exercise the per-repo `safe.directory`, and L6a–L6d would go green
# for a reason that cannot hold in production.
new_session d

D_SRC="$SRC_DIR"
D_DST="$STAGING_DIR"

# mk_repo — a real git repo with one commit, then handed to uid 1001 (production ownership).
mk_repo() {
  local d="$1"
  mkdir -p "$d"
  git init -q "$d" >/dev/null 2>&1
  printf 'content\n' > "$d/f.txt"
  git -C "$d" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$d" -c user.email=t@t -c user.name=t commit -q -m init >/dev/null 2>&1
  chown -R 1001:1001 "$d" 2>/dev/null || true
}

# corrupt_loose — truncate a loose object into garbage. Measured: yields `error:` on stderr +
# `missing blob` on stdout at rc 3 (NOT rc 1 — the exit code is a bitmask).
# corrupt_loose <repo> <kind>  — kind = commit | blob. NEVER pick "whatever find returns first":
# MEASURED (git 2.53.0) the shapes differ materially and select DIFFERENT classifier branches —
#   commit/tree -> rc 128 + `fatal: loose object <sha> … is corrupt`  (matches _FSCK_CONTENT_FATAL_RE)
#   blob        -> rc 3   + `missing blob <sha>` on STDOUT, ZERO fatal lines
# `find | head -n1` picked by readdir order, which on ext4 is a per-filesystem hash of the object
# name, so the branch under test was a coin flip per run and nothing asserted which one ran.
corrupt_loose() {
  local repo="$1" kind="${2:-commit}" sha f
  case "$kind" in
    commit) sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" ;;
    blob)   sha="$(git -C "$repo" rev-parse HEAD:f.txt 2>/dev/null)" ;;
    *)      echo "FIXTURE ERROR: unknown kind '$kind'" >&2; return 1 ;;
  esac
  [ -n "$sha" ] || { echo "FIXTURE ERROR: could not resolve $kind sha in $repo" >&2; return 1; }
  f="$repo/.git/objects/${sha:0:2}/${sha:2}"
  # Fail LOUD rather than returning a repo that was never corrupted: a silently-uncorrupted fixture
  # makes L6b/L6d/L6h pass vacuously (they would assert "no dst-only line" against no fault at all).
  [ -f "$f" ] || { echo "FIXTURE ERROR: $kind object not loose at $f" >&2; return 1; }
  # git writes loose objects 0444. Root can clobber them regardless (CAP_DAC_OVERRIDE), but the
  # chmod keeps the fixture honest if this ever runs non-root.
  chmod u+w "$f" 2>/dev/null || true
  printf 'garbage' > "$f" || { echo "FIXTURE ERROR: could not corrupt $f" >&2; return 1; }
  chown 1001:1001 "$f" 2>/dev/null || true
}

# break_alternates — N unresolvable alternates entries. Measured: `error: unable to normalize
# alternate object path: …` at rc **0**. This is the fixture that proves rc 0 does not short-circuit
# the set comparison (L6f) and, at volume, drives the truncation case (L6h).
break_alternates() {
  local repo="$1" n="${2:-1}" i
  mkdir -p "$repo/.git/objects/info"
  : > "$repo/.git/objects/info/alternates"
  for i in $(seq 1 "$n"); do
    printf '%s\n' "$repo/.git/nonexistent-alt-$i" >> "$repo/.git/objects/info/alternates"
  done
  chown -R 1001:1001 "$repo/.git/objects/info" 2>/dev/null || true
}

# run_gate — drive the REAL verify_git_fsck_differential with die/logger/emit_drift stubbed, exactly
# as L3/L3b drive verify_byte_identity. Called directly (never in $(…)) so die's exit reaches us.
# $1=out-file $2=marker-file $3=src-root $4=dst-root ; remaining env passed through by the caller.
run_gate() {
  local out="$1" marker="$2" src="$3" dst="$4"
  : > "$out"; : > "$marker"
  MARKER_LOG="$marker" CUTOVER="$CUTOVER" SRC="$src" DST="$dst" \
  WORKSPACES_MOUNT="$src" WORKSPACES_STAGING="$dst" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
  WORKSPACES_FSCK_MARKER_CAP="${FSCK_MARKER_CAP_OVERRIDE:-40}" \
  WORKSPACES_FSCK_OUT_CAP="${FSCK_OUT_CAP_OVERRIDE:-256}" \
  bash -c '
    source "$CUTOVER"
    logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
    die()        { echo "DIE: $*"; exit 1; }
    emit_drift() { echo "EMIT_DRIFT: $1"; }
    verify_git_fsck_differential "$SRC" "$DST"
  ' > "$out" 2>&1
}

# --- L6a: clean repos both sides + one non-repo dir + one linked worktree ------------------------
# Asserts the happy path AND that the two un-probeable shapes are DISTINGUISHED on the summary row.
# A linked worktree is not merely unreachable: measured, fsck'ing the COPY follows its absolute
# `gitdir:` pointer back across the mount and reports the SOURCE filesystem's state.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/aaaaaaaa-0000-0000-0000-000000000001"
mk_repo "$D_SRC/workspaces/ws with space"
mkdir -p "$D_SRC/workspaces/not-a-repo"; printf 'plain\n' > "$D_SRC/workspaces/not-a-repo/x.txt"
mk_repo "$D_SRC/workspaces/wt-parent"
git -C "$D_SRC/workspaces/wt-parent" -c user.email=t@t -c user.name=t \
  worktree add -q "$D_SRC/workspaces/linked-wt" -b wtbranch >/dev/null 2>&1
chown -R 1001:1001 "$D_SRC/workspaces" 2>/dev/null || true
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
L6A_OUT="$TMPROOT/l6a.out"; L6A_MARKER="$TMPROOT/l6a.marker"
run_gate "$L6A_OUT" "$L6A_MARKER" "$D_SRC" "$D_DST"
L6A_RC=$?
if [ ! -f "$D_SRC/workspaces/linked-wt/.git" ]; then
  no "L6a FIXTURE ERROR: git worktree add did not produce a .git FILE — the worktree_pointer branch is not being exercised; treat as un-run, not as evidence"
elif [ "$L6A_RC" -eq 0 ] \
  && grep -qE -- 'classification=ok .*ws=aaaaaaaa-0000-0000-0000-000000000001$' "$L6A_MARKER" \
  && grep -qE -- 'classification=ok .*ws=ws with space$' "$L6A_MARKER" \
  && grep -qE -- 'classification=skipped reason=worktree_pointer .*ws=linked-wt$' "$L6A_MARKER" \
  && grep -qE -- 'classification=skipped reason=no_git_dir .*ws=not-a-repo$' "$L6A_MARKER" \
  && grep -qE -- 'skipped_worktree=1 ' "$L6A_MARKER" \
  && grep -qE -- 'skipped_no_git_dir=1 ' "$L6A_MARKER" \
  && grep -qE -- 'skipped_alternates=0 ' "$L6A_MARKER" \
  && grep -qE -- 'phase=gate' "$L6A_MARKER" \
  && grep -qE -- 'SOLEUR_WORKSPACES_LUKS_FSCK .*phase=gate .*total=' "$L6A_OUT"; then
  ok "L6a: clean uid-1001 repos pass (rc=0) with a spaced ws= captured whole; the worktree pointer and the non-repo are each skipped with an ATTRIBUTABLE ws= and distinct reason=; markers reach STDOUT as well as the logger"
else
  no "L6a: clean-path gate did not behave (rc=$L6A_RC)"
  note "marker: $(head -n 4 "$L6A_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6A_OUT" 2>/dev/null)"
fi

# --- L6b: copy corruption STILL ABORTS (the property the differential must not weaken) -----------
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/bbbbbbbb-0000-0000-0000-000000000002"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
corrupt_loose "$D_DST/workspaces/bbbbbbbb-0000-0000-0000-000000000002" blob
L6B_OUT="$TMPROOT/l6b.out"; L6B_MARKER="$TMPROOT/l6b.marker"
run_gate "$L6B_OUT" "$L6B_MARKER" "$D_SRC" "$D_DST"
L6B_RC=$?
# Line-ANCHORED: `classification=` and `ws=` asserted on the SAME row. Independent whole-file greps
# would pass against a SUT that attached the classification to the wrong workspace.
if [ "$L6B_RC" -ne 0 ] \
  && grep -qE -- 'classification=copy_corruption .*ws=bbbbbbbb-0000-0000-0000-000000000002$' "$L6B_MARKER" \
  && grep -qE -- 'classification=copy_corruption .*first=[^ ]' "$L6B_MARKER" \
  && grep -qE -- 'regressed on 1 workspace' "$L6B_OUT" \
  && grep -qE -- 'SOLEUR_WORKSPACES_LUKS_FSCK .*classification=copy_corruption' "$L6B_OUT"; then
  ok "L6b: a blob corrupted ONLY on the LUKS copy still ABORTS as copy_corruption on that exact ws=, with the real fsck line in first=, and the marker reaches STDOUT (not just the logger)"
else
  no "L6b: copy corruption did NOT abort (rc=$L6B_RC) — the differential has weakened the gate"
  note "marker: $(grep -m2 SOLEUR "$L6B_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6B_OUT" 2>/dev/null)"
fi

# --- L6c: both-fail does NOT abort (the false-positive that aborted run 29725194755) -------------
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/cccccccc-0000-0000-0000-000000000003"
corrupt_loose "$D_SRC/workspaces/cccccccc-0000-0000-0000-000000000003" blob
mk_repo "$D_SRC/workspaces/cccccccc-0000-0000-0000-000000000013"
# A CONTENT fatal (corrupt commit -> rc 128 + `fatal: loose object … is corrupt`) on BOTH sides.
# This is the case the setup-vs-content taxonomy exists for: keying probe_failed on rc 128 or on any
# `fatal:` would abort here, reintroducing the exact false positive this change removes.
corrupt_loose "$D_SRC/workspaces/cccccccc-0000-0000-0000-000000000013" commit
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
L6C_OUT="$TMPROOT/l6c.out"; L6C_MARKER="$TMPROOT/l6c.marker"
run_gate "$L6C_OUT" "$L6C_MARKER" "$D_SRC" "$D_DST"
L6C_RC=$?
if [ "$L6C_RC" -eq 0 ] \
  && grep -qE -- 'classification=preexisting .*ws=cccccccc-0000-0000-0000-000000000003$' "$L6C_MARKER" \
  && grep -qE -- 'classification=preexisting .*ws=cccccccc-0000-0000-0000-000000000013$' "$L6C_MARKER" \
  && ! grep -qE -- 'classification=(copy_corruption|probe_failed|unclassified)' "$L6C_MARKER"; then
  ok "L6c: identical faults on BOTH sides classify preexisting and do NOT abort (rc=0) — for a blob fault (rc 3, no fatal) AND a commit fault (rc 128 WITH a content fatal), pinning the setup-vs-content taxonomy"
else
  no "L6c: a pre-existing both-sides fault still aborted (rc=$L6C_RC) — the false positive is not fixed"
  note "marker: $(grep -m2 SOLEUR "$L6C_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6C_OUT" 2>/dev/null)"
fi

# --- L6d: shared fault PLUS a dst-only fault aborts, and path normalization holds ----------------
# The two roots differ ($D_SRC vs $D_DST), so an un-normalized report would make EVERY line dst-only
# and this case would pass for the wrong reason. The shared-fault repo must therefore classify
# preexisting while only the genuinely-new fault drives the abort.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/dddddddd-0000-0000-0000-000000000004"
mk_repo "$D_SRC/workspaces/dddddddd-0000-0000-0000-000000000005"
corrupt_loose "$D_SRC/workspaces/dddddddd-0000-0000-0000-000000000004" blob
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
corrupt_loose "$D_DST/workspaces/dddddddd-0000-0000-0000-000000000005" blob
L6D_OUT="$TMPROOT/l6d.out"; L6D_MARKER="$TMPROOT/l6d.marker"
run_gate "$L6D_OUT" "$L6D_MARKER" "$D_SRC" "$D_DST"
L6D_RC=$?
# Line-ANCHORED with a NEGATIVE CONTROL. Four independent whole-file greps passed against a SUT
# that attached copy_corruption to 004 (the SHARED fault) and preexisting to 005 (the dst-only
# fault) — i.e. the case named "path prefixes normalized" went green under exactly the
# normalization hole it claims to exclude.
if [ "$L6D_RC" -ne 0 ] \
  && grep -qE -- 'classification=copy_corruption .*ws=dddddddd-0000-0000-0000-000000000005$' "$L6D_MARKER" \
  && grep -qE -- 'classification=preexisting .*ws=dddddddd-0000-0000-0000-000000000004$' "$L6D_MARKER" \
  && ! grep -qE -- 'classification=copy_corruption .*ws=dddddddd-0000-0000-0000-000000000004$' "$L6D_MARKER" \
  && grep -qE -- 'copy_corruption=1 ' "$L6D_MARKER"; then
  ok "L6d: the dst-only fault aborts on ITS OWN ws= while the shared fault stays preexisting on ITS OWN ws= (negative control on the inverse) — prefixes normalized, exactly ONE copy_corruption"
else
  no "L6d: mixed shared/dst-only faults misclassified (rc=$L6D_RC) — likely a prefix-normalization hole"
  note "marker: $(grep -c SOLEUR "$L6D_MARKER" 2>/dev/null) rows; $(grep -m3 'classification=' "$L6D_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6D_OUT" 2>/dev/null)"
fi

# --- L6e: probe_failed ABORTS — the anti-no-op proof (the H1 trap) -------------------------------
# ROOT-PROOF MECHANISM: an unterminated section header in .git/config yields
# `fatal: bad config line 1 in file .git/config` at rc 128 regardless of uid. A foreign-uid fixture
# would NOT work here (safe.directory is designed to defeat it, so the SUT would correctly pass) and
# neither would chmod 000 (a no-op under CAP_DAC_OVERRIDE, which this root harness holds).
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/eeeeeeee-0000-0000-0000-000000000006"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
printf '[core\n' > "$D_DST/workspaces/eeeeeeee-0000-0000-0000-000000000006/.git/config"
L6E_OUT="$TMPROOT/l6e.out"; L6E_MARKER="$TMPROOT/l6e.marker"
run_gate "$L6E_OUT" "$L6E_MARKER" "$D_SRC" "$D_DST"
L6E_RC=$?
if [ "$L6E_RC" -ne 0 ] \
  && grep -qE -- 'classification=probe_failed' "$L6E_MARKER" \
  && grep -qE -- 'could NOT INSPECT' "$L6E_OUT"; then
  ok "L6e: a probe that could not INSPECT aborts as probe_failed — NOT silently classified preexisting (the anti-no-op proof)"
else
  no "L6e: an un-inspectable repo did not abort (rc=$L6E_RC) — the gate is blind and green"
  note "marker: $(grep -m2 'classification=' "$L6E_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6E_OUT" 2>/dev/null)"
fi

# --- L6f: rc 0 WITH error lines still aborts (measured: broken alternates exit 0) ----------------
# v1's design short-circuited "both rc 0 -> ok" BEFORE comparing sets, which would have made the new
# gate weaker than the rc-only one it replaces. This case pins the comparison as unconditional.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/ffffffff-0000-0000-0000-000000000007"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
break_alternates "$D_DST/workspaces/ffffffff-0000-0000-0000-000000000007" 1
L6F_OUT="$TMPROOT/l6f.out"; L6F_MARKER="$TMPROOT/l6f.marker"
run_gate "$L6F_OUT" "$L6F_MARKER" "$D_SRC" "$D_DST"
L6F_RC=$?
# NOT an alternation. `classification=(copy_corruption|skipped)` was a permanent fail-open: it would
# have been satisfied by a SUT that skipped the workspace entirely and inspected nothing.
if [ "$L6F_RC" -ne 0 ] \
  && grep -qE -- 'classification=copy_corruption .*ws=ffffffff-0000-0000-0000-000000000007$' "$L6F_MARKER" \
  && grep -qE -- 'classification=copy_corruption .*dst_rc=0 ' "$L6F_MARKER"; then
  ok "L6f: a dst-only error line emitted at rc 0 still aborts as copy_corruption — rc never short-circuits the set comparison"
else
  no "L6f: rc-0-with-errors was treated as clean (rc=$L6F_RC) — the new gate is weaker than the old one"
  note "marker: $(grep -m2 'classification=' "$L6F_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6F_OUT" 2>/dev/null)"
fi

# --- L6g: non-zero rc with an EMPTY error set is unclassified and aborts (fail-closed) -----------
# An OOM-kill / SIGKILL / SIGPIPE'd probe matches no natural row. The natural shell shape
# (`classification=ok` initialized, overwritten by matching branches) would default it to GREEN.
# Driven by overriding _fsck_one after `source` — the classifier, not the prober, is under test.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/99999999-0000-0000-0000-000000000008"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
L6G_OUT="$TMPROOT/l6g.out"; L6G_MARKER="$TMPROOT/l6g.marker"
: > "$L6G_OUT"; : > "$L6G_MARKER"
MARKER_LOG="$L6G_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  # rc 9 with both capture files left EMPTY — the shape a killed probe leaves behind.
  _fsck_one()  { : > "$2"; : > "$3"; : > "$4"; printf "9" > "$2"; return 0; }
  verify_git_fsck_differential "$SRC" "$DST"
' > "$L6G_OUT" 2>&1
L6G_RC=$?
if [ "$L6G_RC" -ne 0 ] \
  && grep -qE -- 'classification=unclassified' "$L6G_MARKER" \
  && grep -qE -- 'cannot classify' "$L6G_OUT"; then
  ok "L6g: non-zero rc with empty output classifies unclassified and ABORTS — the classifier is total and fails closed"
else
  no "L6g: a killed probe did not fail closed (rc=$L6G_RC) — the classifier has a hole that defaults green"
  note "marker: $(grep -m2 'classification=' "$L6G_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6G_OUT" 2>/dev/null)"
fi

# --- L6h: caps bound EMISSION only — a dst-only line beyond the cap must STILL abort -------------
# The cap exists to stop a log flood, not to stop the comparison. If comparison consumed the capped
# capture, a pathological repo could hide the one line that matters behind 40 benign ones.
# THREE workspaces, so cap=1 genuinely truncates (the earlier single-workspace form was
# UNSATISFIABLE: `truncated` needs rows > cap, and 1 > 1 is false, so the case could never have been
# observed green). The corrupt one must still abort and must be the row that SURVIVES the cap.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/77777777-0000-0000-0000-000000000009"
mk_repo "$D_SRC/workspaces/77777777-0000-0000-0000-000000000019"
mk_repo "$D_SRC/workspaces/77777777-0000-0000-0000-000000000029"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
corrupt_loose "$D_DST/workspaces/77777777-0000-0000-0000-000000000009" blob
L6H_OUT="$TMPROOT/l6h.out"; L6H_MARKER="$TMPROOT/l6h.marker"
FSCK_MARKER_CAP_OVERRIDE=1 run_gate "$L6H_OUT" "$L6H_MARKER" "$D_SRC" "$D_DST"
L6H_RC=$?
L6H_ROWS="$(grep -c 'idx=' "$L6H_MARKER" 2>/dev/null || true)"
if [ "$L6H_RC" -ne 0 ] \
  && grep -qE -- 'classification=copy_corruption .*ws=77777777-0000-0000-0000-000000000009$' "$L6H_MARKER" \
  && grep -qE -- 'truncated=1 ' "$L6H_MARKER" \
  && grep -qE -- 'more=2 ' "$L6H_MARKER" \
  && [ "${L6H_ROWS:-0}" -eq 1 ]; then
  ok "L6h: the emission cap drops 2 of 3 rows (truncated=1 more=2) yet the ABORTING row is the one that survives, and the verdict is unchanged"
else
  no "L6h: capping changed the verdict or dropped the aborting row (rc=$L6H_RC rows=${L6H_ROWS:-?})"
  note "marker: $(grep -m3 'classification=' "$L6H_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6H_OUT" 2>/dev/null)"
fi

# --- L6h2: a capture that exceeds the BYTE ceiling fails CLOSED ---------------------------------
# The byte cap (FSCK_OUT_CAP*400) bounds the RAW capture that _fsck_normalize reads, so a truncated
# capture would make the differential compare PARTIAL sets — and truncation is asymmetric in the
# unsafe direction (dst paths are longer, so dst loses its tail first, preferentially discarding the
# dst-only lines that abort). The gate must refuse to compare rather than compare partially.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/88888888-0000-0000-0000-00000000000d"
break_alternates "$D_SRC/workspaces/88888888-0000-0000-0000-00000000000d" 400
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
L6H2_OUT="$TMPROOT/l6h2.out"; L6H2_MARKER="$TMPROOT/l6h2.marker"
FSCK_OUT_CAP_OVERRIDE=1 run_gate "$L6H2_OUT" "$L6H2_MARKER" "$D_SRC" "$D_DST"
L6H2_RC=$?
if [ "$L6H2_RC" -ne 0 ] \
  && grep -qE -- 'classification=unclassified reason=capture_capped' "$L6H2_MARKER" \
  && grep -qE -- 'cannot classify' "$L6H2_OUT"; then
  ok "L6h2: a capture that hit the byte ceiling fails CLOSED (reason=capture_capped) instead of comparing a partial set"
else
  no "L6h2: a byte-capped capture did NOT fail closed (rc=$L6H2_RC) — the differential is comparing truncated captures"
  note "marker: $(grep -m2 'classification=' "$L6H2_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 5 "$L6H2_OUT" 2>/dev/null)"
fi

# --- L6h3: object-count floor — loss with NO error line on either side ---------------------------
# An UNREFERENCED object is reported only as `dangling`, which the gate filters out as a notice. Its
# absence on the copy therefore produces ZERO error lines on either side, so the error-line
# differential is structurally blind to it. Only the per-side object count can see it — this is what
# makes `ok` mean "walked N objects and found nothing" rather than "walked nothing".
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/aaaaaaaa-0000-0000-0000-00000000000e"
L6H3_EXTRA="$(printf 'unreferenced payload\n' | git -C "$D_SRC/workspaces/aaaaaaaa-0000-0000-0000-00000000000e" hash-object -w --stdin 2>/dev/null)"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
if [ -z "$L6H3_EXTRA" ]; then
  no "L6h3 FIXTURE ERROR: hash-object did not produce an unreferenced blob — treat as un-run"
else
  rm -f "$D_DST/workspaces/aaaaaaaa-0000-0000-0000-00000000000e/.git/objects/${L6H3_EXTRA:0:2}/${L6H3_EXTRA:2}"
  L6H3_OUT="$TMPROOT/l6h3.out"; L6H3_MARKER="$TMPROOT/l6h3.marker"
  run_gate "$L6H3_OUT" "$L6H3_MARKER" "$D_SRC" "$D_DST"
  L6H3_RC=$?
  if [ "$L6H3_RC" -ne 0 ] \
    && grep -qE -- 'classification=copy_corruption reason=object_count_regression' "$L6H3_MARKER"; then
    ok "L6h3: an object lost on the copy that emits NO error line on either side is still caught, by the object-count floor — 'clean' now means 'inspected', not 'found nothing'"
  else
    no "L6h3: object loss with no error line went UNDETECTED (rc=$L6H3_RC) — the gate cannot distinguish a clean walk from a walk of nothing"
    note "marker: $(grep -m2 'classification=' "$L6H3_MARKER" 2>/dev/null)"
  fi
fi

# --- L6h4: instrument failure — zero enumeration against a non-zero G2 --------------------------
# An empty enumeration is a broken instrument, not an empty volume (DP-9 F10: floors derive from the
# OBSERVED count, never a hardcoded zero). G2_COUNT lives in the main body past the sourced-detection
# guard, so the harness must inject it — without that, this whole abort class is unreachable from
# any test and could be deleted with the suite green.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces" "$D_DST/workspaces"
L6H4_OUT="$TMPROOT/l6h4.out"; L6H4_MARKER="$TMPROOT/l6h4.marker"
: > "$L6H4_OUT"; : > "$L6H4_MARKER"
MARKER_LOG="$L6H4_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  G2_COUNT=7
  verify_git_fsck_differential "$SRC" "$DST"
' > "$L6H4_OUT" 2>&1
L6H4_RC=$?
if [ "$L6H4_RC" -ne 0 ] \
  && grep -qE -- 'total=0 ' "$L6H4_MARKER" \
  && grep -qE -- 'enumerated ZERO workspaces while G2 observed 7' "$L6H4_OUT"; then
  ok "L6h4: zero workspaces enumerated against G2=7 aborts as instrument failure — an empty enumeration is never read as emptiness"
else
  no "L6h4: zero enumeration did NOT abort (rc=$L6H4_RC) — the gate would certify a volume it never read"
  note "out: $(tail -n 5 "$L6H4_OUT" 2>/dev/null)"
fi

# --- L6k: H1 — `detected dubious ownership`, the leading hypothesis ------------------------------
# This is the failure the whole design is defensive about: the cutover runs as root, container repos
# are uid 1001, and git refuses with rc 128 BEFORE reading a single object.
#
# WHAT THIS CASE MAY AND MAY NOT ASSERT — measured, not assumed. Two independent attempts to provoke
# a REAL ownership refusal on the GH-hosted runner both failed, each producing src_rc=0 dst_rc=0:
#   - a foreign-uid fixture (chown 65534, neither 0 nor $SUDO_UID), and
#   - GIT_TEST_ASSUME_DIFFERENT_OWNER=1, a git *test-suite* knob carrying no compatibility promise.
#
# BOTH failures had ONE cause, and it was neither of the two guessed at the time (an earlier revision
# of this comment blamed git 2.54.0 vs 2.53.0; a still earlier one blamed the fixture uid). L6k-CAP
# measured it on its first CI run: the GitHub runner image ships `safe.directory = *` in the SYSTEM
# gitconfig, so git allowed every directory and no ownership check could ever fire. Neutralizing
# GIT_CONFIG_SYSTEM/GLOBAL makes the refusal fire on the runner — see L6m, which is the real
# load-bearing proof and DOES run in CI.
#
# The instrument found in one run what three commits of inference got wrong. That is the argument for
# L6k-CAP existing at all, and it is why the capability is re-measured every run rather than recorded
# here as a fact.
#
# So the two halves are split by what is actually provable HERE:
#   (i)  DETERMINISTIC, asserted below: given the H1 stderr shape, the gate must classify
#        probe_failed and ABORT — never `preexisting`, the no-op-disguised-as-a-fix this plan exists
#        to prevent. The stub SYNTHESIZES that stderr rather than trying to provoke it out of git,
#        so the case tests the SUT's classifier — which is what this repo owns — and not git's
#        ownership heuristics, which it does not. L6e already proves the same abort wiring end-to-end
#        against REAL git via `fatal: bad config`, uid-independently; this case pins the specific H1
#        alternative of _FSCK_SETUP_FATAL_RE.
#   (ii) A health CONTROL, not a proof: it shows the fixture is otherwise clean, so arm (i)'s abort
#        is attributable to the synthesized fatal. The "-c safe.directory= is load-bearing" proof
#        lives in L6m, against real git. A green L6k alone must never be read as evidence that the
#        flag was exercised — L6m is what carries that claim.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/44444444-0000-0000-0000-00000000000f"
# TWO workspaces, and the SECOND ONE IS THE POINT. Every other gate case (L6b, L6e, L6f, L6g, L6i)
# probes exactly one repo, under which 1-of-1 is indistinguishable from all-of-1 — so the gate's
# `elif [ "$n_probefail" -gt 0 ]` ANY threshold had NO test in the suite. Restoring the superseded
# ALL threshold (`&& [ "$n_probefail" -eq "$total" ]`) passed every single-workspace case while
# turning a 1-of-2 probe_failed into rc 0, "no copy-introduced regression". That is run
# 29725194755's 8-of-10 shape landing in the GATE path — inside the freeze, where a false green is
# followed by Phase 5 wiping the plaintext original. L6j guards the same threshold only for the
# pre-freeze advisory probe, which is the strictly less dangerous of the two locations.
mk_repo "$D_SRC/workspaces/66666666-0000-0000-0000-000000000011"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
# Foreign uid (neither 0 nor $SUDO_UID) is kept so L6k-CAP measures the REAL production shape. It is
# no longer load-bearing for the assertion — arm (i) synthesizes the refusal.
chown -R 65534:65534 "$D_SRC/workspaces/44444444-0000-0000-0000-00000000000f" 2>/dev/null || true
chown -R 65534:65534 "$D_DST/workspaces/44444444-0000-0000-0000-00000000000f" 2>/dev/null || true

# L6k-CAP — does real git on THIS host refuse an un-owned repo when safe.directory is absent? Emitted
# as evidence on EVERY run, green or red. Without it, "the refusal never fired" is indistinguishable
# from "nobody looked" — the exact blindness class this suite exists to remove. Not an assertion:
# a runner that cannot produce H1 is a fact about the runner, not a defect in the gate.
L6KCAP_REPO="$D_SRC/workspaces/44444444-0000-0000-0000-00000000000f"
# AMBIENT CONFIG IS NEUTRALIZED FOR THE PROBES, and that is the whole point. The first CI run of this
# block measured `rc=0 err=` for BOTH mechanisms and reported "this host CANNOT produce H1" — and the
# very next line it printed explained why: `safe.directory in scope  file:/etc/gitconfig  *`. The
# GitHub runner image ships a SYSTEM gitconfig that blanket-allows every directory, so an
# un-neutralized probe measures the runner's opt-out, not git's ownership behaviour, and reporting
# that as a property of the host is a measurement artifact dressed as a fact.
#
# GIT_CONFIG_SYSTEM/GLOBAL=/dev/null removes it. That also makes the probe FAITHFUL to production:
# web-1 has no blanket `safe.directory=*`, so the neutralized run is the one that resembles the
# cutover host. The ambient value is still reported below, because it is the diagnostic.
L6KCAP_ERR="$TMPROOT/l6kcap.err"
GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
  git --no-optional-locks -C "$L6KCAP_REPO" fsck --full --no-progress --no-dangling --no-reflogs \
  >/dev/null 2>"$L6KCAP_ERR"
L6KCAP_RC=$?
L6KCAP_ENVERR="$TMPROOT/l6kcap-env.err"
GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
  git --no-optional-locks -C "$L6KCAP_REPO" fsck --full --no-progress --no-dangling --no-reflogs \
  >/dev/null 2>"$L6KCAP_ENVERR"
L6KCAP_ENVRC=$?
note "L6k-CAP: git=$(git --version 2>/dev/null | awk '{print $3}') euid=$(id -u) SUDO_UID=${SUDO_UID:-<unset>} fixture_uid=$(stat -c %u "$L6KCAP_REPO" 2>/dev/null || echo '?')"
note "L6k-CAP: foreign-uid, cfg neutralized   rc=$L6KCAP_RC    err=$(head -n1 "$L6KCAP_ERR" 2>/dev/null || echo '<empty>')"
note "L6k-CAP: + ASSUME_DIFFERENT_OWNER=1     rc=$L6KCAP_ENVRC err=$(head -n1 "$L6KCAP_ENVERR" 2>/dev/null || echo '<empty>')"
L6KCAP_SD="$(git config --show-origin --get-all safe.directory 2>/dev/null | tr '\n' ' ')"
note "L6k-CAP: ambient safe.directory (NOT in effect above) ${L6KCAP_SD:-<none>}"
# CONDITIONAL ASSERTION, not a bare note. Synthesizing arm (i) forked this case from the contract it
# models: the only place git's real refusal wording appears is now a printf the test owns, so if git
# reworded it (say to `fatal: repository ownership is not trusted`), every real H1 in production
# would demote from probe_failed to unclassified — different marker, different emit_drift, different
# die string, operator pointed at "cannot classify" instead of "could not inspect" — and this suite
# would stay green forever. This re-joins the fork at zero flake cost: on a host that CANNOT produce
# H1 it stays a note; on any host that CAN (a dev laptop today, a future runner, a git that
# re-enables the knob) it becomes a hard assertion that real git's bytes still match the regex.
# It is the only check in the suite able to detect that drift.
if grep -qE 'detected dubious ownership' "$L6KCAP_ERR" "$L6KCAP_ENVERR" 2>/dev/null; then
  if CUTOVER="$CUTOVER" bash -c \
      'source "$CUTOVER" >/dev/null 2>&1; grep -qE "$_FSCK_SETUP_FATAL_RE" "$1" "$2"' \
      _ "$L6KCAP_ERR" "$L6KCAP_ENVERR" 2>/dev/null; then
    ok "L6k-CAP: this host CAN produce H1, and real git's refusal still matches _FSCK_SETUP_FATAL_RE — the synthesized arm (i) is faithful to git's actual wording"
  else
    no "L6k-CAP: real git refused but _FSCK_SETUP_FATAL_RE did NOT match it — the regex has drifted from git's wording, so every real H1 now demotes to unclassified and arm (i) is testing a string git no longer emits"
    note "real refusal: $(head -n1 "$L6KCAP_ERR" "$L6KCAP_ENVERR" 2>/dev/null | grep -m1 fatal:)"
  fi
else
  note "L6k-CAP: this host CANNOT produce H1 — arm (ii) (safe.directory is load-bearing) is UNPROVEN in CI, and the regex-vs-reality check above is vacuous here"
fi
L6K_OUT="$TMPROOT/l6k.out"; L6K_MARKER="$TMPROOT/l6k.marker"
: > "$L6K_OUT"; : > "$L6K_MARKER"
MARKER_LOG="$L6K_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  # SYNTHESIZE the H1 refusal rather than provoke it. Real git will not emit it on this runner (see
  # L6k-CAP), and a case that silently cannot produce its own precondition is the blindness this
  # suite removes. The byte shape is git\047s own, including the surrounding single quotes; \047 is
  # used because this stub body is single-quoted. rc 128 is what git exits with on a setup fatal.
  _fsck_one() {
    local repo="$1" rc_file="$2" raw_out="$3" raw_err="$4"
    # ONLY the 4444 workspace is un-inspectable; 6666 goes through the REAL prober. A stub that
    # synthesized for every repo would make total==probe_failed again and re-hide the ANY-vs-ALL
    # threshold this fixture exists to pin.
    case "$repo" in
      *44444444-*) : ;;
      *) git --no-optional-locks -c safe.directory="$repo" -C "$repo" \
           fsck --full --no-progress --no-dangling --no-reflogs >"$raw_out" 2>"$raw_err"
         printf "%s" "$?" > "$rc_file"
         { git --no-optional-locks -c safe.directory="$repo" -C "$repo" count-objects -v 2>/dev/null \
             | awk "/^count:|^in-pack:/ { s += \$2 } END { print s + 0 }"; } > "${rc_file%.rc}.objs" \
             2>/dev/null || printf "0" > "${rc_file%.rc}.objs"
         return 0 ;;
    esac
    : > "$raw_out"
    printf "fatal: detected dubious ownership in repository at \047%s\047\n" "$repo" > "$raw_err"
    printf "128" > "$rc_file"
    # NOT load-bearing for this case, and deliberately so: a setup fatal short-circuits to
    # probe_failed in _fsck_classify BEFORE the object-count floor is ever consulted, so the value
    # here cannot change the verdict (measured). Computed for real anyway so this stub differs from
    # the shipped _fsck_one in exactly ONE dimension — the synthesized stderr — and a future edit
    # that does reach the floor is not silently sitting on a hardcoded 0.
    #
    # What actually keeps this case honest is the `classification=probe_failed` grep in the
    # assertion, NOT this count. Measured: if _FSCK_SETUP_FATAL_RE ever stops matching the H1 line,
    # the run lands in `unclassified` and STILL aborts rc=1 — so an assertion that only checked "it
    # aborted" would stay green while proving nothing.
    #
    # NOTE: no apostrophes anywhere in this stub body — it is inside a single-quoted bash -c, and
    # one would terminate the string. That is why \047 is used for the quotes in the fatal above.
    #
    # For the record, because an earlier revision of this comment got it backwards: on main this
    # case was RED, not green. objs=0 tripped the object-count floor into `unclassified`, whose die
    # string is "cannot classify", so the `could NOT INSPECT` conjunct in the old assertion failed.
    # It failed for a reason unrelated to the one it names — worse than a clean failure, because the
    # recorded rc still looked like the trap had been sprung.
    { git --no-optional-locks -c safe.directory="$repo" -C "$repo" count-objects -v 2>/dev/null \
        | awk "/^count:|^in-pack:/ { s += \$2 } END { print s + 0 }"; } > "${rc_file%.rc}.objs" \
        2>/dev/null || printf "0" > "${rc_file%.rc}.objs"
    return 0
  }
  verify_git_fsck_differential "$SRC" "$DST"
' > "$L6K_OUT" 2>&1
L6K_SUPPRESSED_RC=$?
# (ii) CONTROL — the SAME fixture through the REAL prober must classify ok. This is a mutation
# control, NOT the load-bearing proof: since arm (i) now synthesizes the refusal, this arm shows only
# that the fixture is otherwise healthy, so arm (i)'s abort is attributable to the synthesized fatal
# and not to something wrong with the repo. Proving `-c safe.directory=` is what rescues a foreign-uid
# repo needs a real refusal, which this host cannot produce (see L6k-CAP).
L6K2_OUT="$TMPROOT/l6k2.out"; L6K2_MARKER="$TMPROOT/l6k2.marker"
: > "$L6K2_OUT"; : > "$L6K2_MARKER"
MARKER_LOG="$L6K2_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  verify_git_fsck_differential "$SRC" "$DST"
' > "$L6K2_OUT" 2>&1
L6K_REAL_RC=$?
# `could NOT INSPECT 1 workspace` — the COUNT is the load-bearing token, not the phrase. A bare
# 'could NOT INSPECT' grep passes under the superseded ALL threshold too (it would simply never be
# reached, and the case would fail on rc instead — for the wrong reason, which is how this case has
# already misreported once). Pinning `1` asserts that ONE un-inspectable repo out of two aborts.
if [ "$L6K_SUPPRESSED_RC" -ne 0 ] \
  && grep -qE -- 'classification=probe_failed .*first=.*detected dubious ownership' "$L6K_MARKER" \
  && grep -qE -- 'could NOT INSPECT 1 workspace' "$L6K_OUT" \
  && grep -qE -- 'classification=ok .*ws=66666666-0000-0000-0000-000000000011$' "$L6K_MARKER" \
  && [ "$L6K_REAL_RC" -eq 0 ] \
  && grep -qE -- 'classification=ok' "$L6K2_MARKER"; then
  ok "L6k: ONE un-inspectable repo out of two aborts the gate as probe_failed (never preexisting) while its healthy sibling classifies ok — pinning the ANY-not-ALL threshold; arm (ii) is a health control, NOT proof that -c safe.directory= is load-bearing (see L6k-CAP)"
else
  no "L6k: the H1 trap is not closed (suppressed_rc=$L6K_SUPPRESSED_RC real_rc=$L6K_REAL_RC) — either the synthesized ownership fatal did not classify probe_failed and abort, or the healthy control did not classify ok"
  note "suppressed: $(grep -m1 'classification=' "$L6K_MARKER" 2>/dev/null)"
  note "real:       $(grep -m1 'classification=' "$L6K2_MARKER" 2>/dev/null)"
fi

# --- L6m: THE LOAD-BEARING PROOF — `-c safe.directory=` is what rescues a foreign-uid repo --------
# This is the half of the H1 design that arm (i) cannot prove, because arm (i) synthesizes. It needs
# a REAL refusal out of REAL git, which the first CI run appeared to say was impossible here — until
# L6k-CAP printed `safe.directory  file:/etc/gitconfig  *` and the "impossibility" turned out to be
# the runner image blanket-allowing every directory. Neutralizing that (see L6k-CAP) makes the
# refusal fire, and also makes the fixture resemble the production cutover host, which has no such
# blanket entry.
#
# Two runs over the SAME foreign-uid (65534) repo, ambient config neutralized in both:
#   (A) WITHOUT `-c safe.directory=` -> real git refuses -> probe_failed -> ABORT
#   (B) WITH the SUT's real prober   -> the flag rescues it -> ok -> rc 0
# Only the flag differs, so (A)+(B) together attribute the rescue to the flag and nothing else. If
# either arm behaved the same as the other, the flag would be doing nothing and H1 would be live in
# production.
#
# GATED on L6k-CAP: if a host genuinely cannot produce a refusal even with config neutralized, this
# proof is unrunnable there and says so, rather than failing for an environmental reason.
if [ "$L6KCAP_RC" -ne 0 ] && grep -qE 'detected dubious ownership' "$L6KCAP_ERR" 2>/dev/null; then
  rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
  mkdir -p "$D_SRC/workspaces"
  mk_repo "$D_SRC/workspaces/77777777-0000-0000-0000-000000000012"
  rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
  chown -R 65534:65534 "$D_SRC/workspaces/77777777-0000-0000-0000-000000000012" 2>/dev/null || true
  chown -R 65534:65534 "$D_DST/workspaces/77777777-0000-0000-0000-000000000012" 2>/dev/null || true
  L6M_A_OUT="$TMPROOT/l6m-a.out"; L6M_A_MARKER="$TMPROOT/l6m-a.marker"
  : > "$L6M_A_OUT"; : > "$L6M_A_MARKER"
  MARKER_LOG="$L6M_A_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
  WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
  GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
  bash -c '
    source "$CUTOVER"
    logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
    die()        { echo "DIE: $*"; exit 1; }
    emit_drift() { echo "EMIT_DRIFT: $1"; }
    # The SUT prober with the -c safe.directory= REMOVED and nothing else changed.
    _fsck_one() {
      local repo="$1" rc_file="$2" raw_out="$3" raw_err="$4"
      git --no-optional-locks -C "$repo" \
        fsck --full --no-progress --no-dangling --no-reflogs >"$raw_out" 2>"$raw_err"
      printf "%s" "$?" > "$rc_file"
      { git --no-optional-locks -c safe.directory="$repo" -C "$repo" count-objects -v 2>/dev/null \
          | awk "/^count:|^in-pack:/ { s += \$2 } END { print s + 0 }"; } > "${rc_file%.rc}.objs" \
          2>/dev/null || printf "0" > "${rc_file%.rc}.objs"
      return 0
    }
    verify_git_fsck_differential "$SRC" "$DST"
  ' > "$L6M_A_OUT" 2>&1
  L6M_A_RC=$?
  L6M_B_OUT="$TMPROOT/l6m-b.out"; L6M_B_MARKER="$TMPROOT/l6m-b.marker"
  : > "$L6M_B_OUT"; : > "$L6M_B_MARKER"
  MARKER_LOG="$L6M_B_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
  WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
  GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
  bash -c '
    source "$CUTOVER"
    logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
    die()        { echo "DIE: $*"; exit 1; }
    emit_drift() { echo "EMIT_DRIFT: $1"; }
    verify_git_fsck_differential "$SRC" "$DST"
  ' > "$L6M_B_OUT" 2>&1
  L6M_B_RC=$?
  if [ "$L6M_A_RC" -ne 0 ] \
    && grep -qE -- 'classification=probe_failed .*first=.*detected dubious ownership' "$L6M_A_MARKER" \
    && grep -qE -- 'could NOT INSPECT' "$L6M_A_OUT" \
    && [ "$L6M_B_RC" -eq 0 ] \
    && grep -qE -- 'classification=ok' "$L6M_B_MARKER"; then
    ok "L6m: REAL git refuses a foreign-uid repo (probe_failed, ABORT) with -c safe.directory= removed, and the SAME repo classifies ok through the shipped prober — the flag is LOAD-BEARING, proven against real git, not synthesized"
  else
    no "L6m: the -c safe.directory= load-bearing proof FAILED (no_flag_rc=$L6M_A_RC shipped_rc=$L6M_B_RC) — either a foreign-uid repo does not abort without the flag, or the flag is not what makes the shipped prober able to inspect it"
    note "no-flag: $(grep -m1 'classification=' "$L6M_A_MARKER" 2>/dev/null)"
    note "shipped: $(grep -m1 'classification=' "$L6M_B_MARKER" 2>/dev/null)"
  fi
else
  note "L6m: SKIPPED — L6k-CAP reports this host cannot produce a real ownership refusal even with ambient git config neutralized, so the load-bearing proof is unrunnable here (rc=$L6KCAP_RC)"
fi

# --- L6l: (2b) FAIL-CLOSED — an UNRECOGNISED fatal, identical on BOTH sides, must NOT go green ---
# The single most dangerous input this gate can receive, and until #6759 nothing exercised it.
# _FSCK_SETUP_FATAL_RE is an ALLOWLIST, and three of its seven alternatives are unmeasured (see the
# per-alternative record on the regex). If a fatal shape neither allowlisted nor known-content
# reached the differential, and it appeared IDENTICALLY on both sides — which is exactly what a
# setup failure does, since both roots hit the same condition — `comm -13` would find no dst-only
# line, the verdict would be `preexisting`, the gate would return 0, and Phase 5 would wipe the
# plaintext original against a copy the probe never inspected. Branch (2b) is the only thing
# standing between that input and a green run.
#
# Synthesized deliberately: the point is a fatal git does NOT emit today, since any shape that IS
# emitted would be a candidate for the allowlist instead. This is the fail-closed default under
# test, not a specific git behaviour.
rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/55555555-0000-0000-0000-000000000010"
rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
L6L_OUT="$TMPROOT/l6l.out"; L6L_MARKER="$TMPROOT/l6l.marker"
: > "$L6L_OUT"; : > "$L6L_MARKER"
MARKER_LOG="$L6L_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" DST="$D_DST" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  _fsck_one() {
    local repo="$1" rc_file="$2" raw_out="$3" raw_err="$4"
    : > "$raw_out"
    printf "fatal: a shape no git version emits and no allowlist names\n" > "$raw_err"
    printf "128" > "$rc_file"
    { git --no-optional-locks -c safe.directory="$repo" -C "$repo" count-objects -v 2>/dev/null \
        | awk "/^count:|^in-pack:/ { s += \$2 } END { print s + 0 }"; } > "${rc_file%.rc}.objs" \
        2>/dev/null || printf "0" > "${rc_file%.rc}.objs"
    return 0
  }
  verify_git_fsck_differential "$SRC" "$DST"
' > "$L6L_OUT" 2>&1
L6L_RC=$?
# NOT `-ne 0` alone: probe_failed also aborts, and if the allowlist ever widened to swallow this
# shape the case would still "pass" while proving nothing about (2b). Pin the classification.
if [ "$L6L_RC" -ne 0 ] \
  && grep -qE -- 'classification=unclassified' "$L6L_MARKER" \
  && ! grep -qE -- 'classification=preexisting' "$L6L_MARKER"; then
  ok "L6l: an UNRECOGNISED fatal appearing identically on BOTH sides fails CLOSED as unclassified and ABORTS — never preexisting, the one outcome this design may not produce"
else
  no "L6l: (2b) did not fail closed (rc=$L6L_RC) — an unallowlisted fatal reached the differential, and a gate that green-lights it certifies a copy it never inspected"
  note "marker: $(grep -m2 'classification=' "$L6L_MARKER" 2>/dev/null)"
  note "out:    $(tail -n 3 "$L6L_OUT" 2>/dev/null)"
fi

# --- L6i: MUTATION CONTROL (L5d discipline) — prove L6b's abort is load-bearing ------------------
# Without this, L6b's "it aborted" is indistinguishable from a gate that aborts unconditionally.
L6I_MUT="$TMPROOT/cutover-l6i-mutated.sh"
sed 's/^\([[:space:]]*\)abort_fsck=1/\1abort_fsck=0/' "$CUTOVER" > "$L6I_MUT"
if ! grep -q 'abort_fsck=0' "$L6I_MUT"; then
  no "L6i: mutation sed did NOT land (no abort_fsck=1 assignment found) — treat as un-run, not as evidence"
else
  rm -rf "${D_SRC:?}/workspaces" "${D_DST:?}/workspaces"
  mkdir -p "$D_SRC/workspaces"
  mk_repo "$D_SRC/workspaces/11111111-0000-0000-0000-00000000000a"
  rsync -aHAX --numeric-ids --delete "$D_SRC"/ "$D_DST"/ >/dev/null 2>&1
  corrupt_loose "$D_DST/workspaces/11111111-0000-0000-0000-00000000000a"
  L6I_OUT="$TMPROOT/l6i.out"; L6I_MARKER="$TMPROOT/l6i.marker"
  CUTOVER="$L6I_MUT" run_gate "$L6I_OUT" "$L6I_MARKER" "$D_SRC" "$D_DST"
  L6I_RC=$?
  if [ "$L6I_RC" -eq 0 ]; then
    ok "L6i: mutation (abort predicate made vacuous) flips L6b GREEN — L6b's abort is load-bearing, not decorative"
  else
    no "L6i: mutation did NOT flip L6b (rc=$L6I_RC) — L6b's abort assertion may be vacuous"
    note "out: $(tail -n 5 "$L6I_OUT" 2>/dev/null)"
  fi
fi

# --- L6j: the pre-freeze ADVISORY probe ---------------------------------------------------------
# It runs in BOTH arms and is EVIDENCE, never the gate's comparand. It aborts on ANY un-inspectable
# source repo — under H1 that is the whole point: fail BEFORE the freeze rather than after the
# outage. A PARTIAL failure aborts too, and that is deliberate: run 29725194755 failed on 8 of 10,
# so an all-or-nothing threshold would have gone green, held the freeze, taken the outage and
# aborted at the gate anyway. Failing here costs zero downtime.
#
# (This header said the opposite — "its one aborting condition is every probed source repo" and
# "a partial failure must NOT abort" — until #6759. The SUT never behaved that way: `-gt 0` shipped
# in the same commit as the paragraph claiming `every`. Reading this header first was what made L6j
# look like a test-vs-SUT design contradiction rather than a stale comment.)
rm -rf "${D_SRC:?}/workspaces"
mkdir -p "$D_SRC/workspaces"
mk_repo "$D_SRC/workspaces/22222222-0000-0000-0000-00000000000b"
mk_repo "$D_SRC/workspaces/33333333-0000-0000-0000-00000000000c"
printf '[core\n' > "$D_SRC/workspaces/22222222-0000-0000-0000-00000000000b/.git/config"
L6J_OUT="$TMPROOT/l6j-partial.out"; L6J_MARKER="$TMPROOT/l6j-partial.marker"
: > "$L6J_OUT"; : > "$L6J_MARKER"
MARKER_LOG="$L6J_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  fsck_advisory_probe "$SRC"
' > "$L6J_OUT" 2>&1
L6J_PARTIAL_RC=$?
# Now make EVERY source repo un-inspectable -> must abort pre-freeze.
printf '[core\n' > "$D_SRC/workspaces/33333333-0000-0000-0000-00000000000c/.git/config"
L6J_ALL_OUT="$TMPROOT/l6j-all.out"; L6J_ALL_MARKER="$TMPROOT/l6j-all.marker"
: > "$L6J_ALL_OUT"; : > "$L6J_ALL_MARKER"
MARKER_LOG="$L6J_ALL_MARKER" CUTOVER="$CUTOVER" SRC="$D_SRC" \
WORKSPACES_MOUNT="$D_SRC" WORKSPACES_STAGING="$D_DST" WORKSPACES_MAPPER_NAME="$MAPPER_NAME" \
bash -c '
  source "$CUTOVER"
  logger()     { printf "%s\n" "$*" >> "$MARKER_LOG"; }
  die()        { echo "DIE: $*"; exit 1; }
  emit_drift() { echo "EMIT_DRIFT: $1"; }
  fsck_advisory_probe "$SRC"
' > "$L6J_ALL_OUT" 2>&1
L6J_ALL_RC=$?
# ANY probe_failed aborts pre-freeze — NOT only the all-of-them case. The all-or-nothing threshold
# did not cover the incident this probe was built for: run 29725194755 failed on 8 of 10, so an ALL
# threshold would have gone green, held the freeze, taken the outage, and aborted at the gate anyway.
# Failing here costs zero downtime. Both arms must therefore abort, and both must name the pre-freeze
# no-rollback language so an operator never reaches for ROLLBACK=1 after it.
if [ "$L6J_PARTIAL_RC" -ne 0 ] && [ "$L6J_ALL_RC" -ne 0 ] \
  && grep -qE -- 'phase=advisory' "$L6J_MARKER" \
  && ! grep -qE -- 'phase=gate' "$L6J_MARKER" \
  && grep -qE -- 'could not inspect 1 of 2' "$L6J_OUT" \
  && grep -qE -- 'could not inspect 2 of 2' "$L6J_ALL_OUT" \
  && grep -qE -- 'no freeze was held' "$L6J_OUT" \
  && grep -qE -- 'no freeze was held' "$L6J_ALL_OUT"; then
  ok "L6j: the advisory probe emits phase=advisory rows and aborts PRE-FREEZE on ANY un-inspectable source repo (1-of-2 and 2-of-2), naming the count and the no-rollback language"
else
  no "L6j: advisory probe misbehaved (partial_rc=$L6J_PARTIAL_RC all_rc=$L6J_ALL_RC)"
  note "partial marker: $(grep -m2 SOLEUR "$L6J_MARKER" 2>/dev/null)"
  note "all out:        $(tail -n 5 "$L6J_ALL_OUT" 2>/dev/null)"
fi

# ===========================================================================
echo
echo "workspaces-luks-loopback: $executed case(s) EXECUTED against real loopback+dm-crypt devices"
echo "workspaces-luks-loopback: $pass passed, $fail failed"
# An executed-count of zero is itself a failure: it means the suite greened without collecting any
# real-device evidence, which is the fail-open shape this suite exists to eliminate.
if [ "$executed" -eq 0 ]; then
  echo "workspaces-luks-loopback: ZERO cases executed — refusing to report success" >&2
  exit 3
fi
[ "$fail" -eq 0 ]
