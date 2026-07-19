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
for b in losetup cryptsetup mkfs.ext4 mount umount findmnt blkid mountpoint rsync du df; do
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
