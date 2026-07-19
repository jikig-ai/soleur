#!/usr/bin/env bash
#
# Behavioral test for workspaces-cutover.sh :: prepare_staging_target / emit_staging_target /
# _same_dev, plus the fail-closures added alongside them at the L3 block-device gate, luksFormat,
# luksOpen and the repoint umount/mount (#6588 staging-target guards).
#
# Context: the 2026-07-19 real freeze (run 29695998561) safe-aborted on C1 with a single
# `.d..t...... ./`. C1 was RIGHT and the defect was one layer BELOW what C1 can report: the script
# luksFormat'd the device and luksOpen'd the mapper but never ran mkfs, so the mapper held no
# filesystem and `mount "$MAPPER" "$STAGING"` failed with `wrong fs type`. Under `set -uo pipefail`
# with no `-e` that failure was SWALLOWED, and the `mkdir -p "$STAGING"` above had already created
# /mnt/data-luks as a plain directory ON THE ROOT DISK. Every downstream gate then certified a
# byte-perfect copy onto the wrong block device.
#
# SCOPE — this suite covers the branches a real-device loopback suite cannot reach cheaply:
# every fail-closure, every marker reason, and the dry-run short-circuit, all against stubs. The
# real-device behaviour (an actual luksFormat/luksOpen/mkfs/mount over a loop file, and the
# /dev/mapper -> /dev/dm-N canonicalization `_same_dev` performs) belongs to
# workspaces-luks-loopback.test.sh and is deliberately NOT asserted here: on a CI box neither
# /dev/mapper/workspaces nor /dev/dm-N exists, so `readlink -f` returns the literal path and such a
# case would FALSE-FAIL.
#
# HARNESS: run_case, the stub set and every predicate come from workspaces-luks-harness.sh, shared
# with workspaces-luks-freeze.test.sh. Read the rule block at the top of that file before adding a
# case — in particular: never pipe into an assertion predicate.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

# shellcheck source=apps/web-platform/infra/workspaces-luks-harness.sh
. "$SCRIPT_DIR/workspaces-luks-harness.sh"

# `_same_dev` ends in `[ -b "$b" ]` and `[` is a builtin, so every case that needs it to return TRUE
# must be handed a path that really IS a block device. Nothing is written to it (mkfs/mount/blkid/
# cryptsetup/df/du are all stubbed); it is only an argument to `[ -b ]` and `readlink -f`.
BLKDEV="$(harness_blockdev || true)"
if [ -z "$BLKDEV" ]; then
  no "PRE: no block device found on this host — every _same_dev-positive case would false-fail"
  echo "workspaces-luks-staging.test.sh: $pass passed, $fail failed"
  exit 1
fi

# stage_case <script> [env assignments...] — invoke prepare_staging_target with $MAPPER and
# $FRESH_DEV bound to the discovered block device. FRESH_DEV is assigned in the script's MAIN BODY,
# which the sourced-detection guard skips, so it MUST be bound here or the function aborts on
# `unbound variable` before reaching any branch under test.
stage_case() {
  local script="$1"; shift
  run_case "$script" \
    'FRESH_DEV="$BLK"; MAPPER="$BLK"; prepare_staging_target' \
    'prepare_staging_target emit_staging_target _same_dev' \
    BLK="$BLKDEV" "$@"
}

# The default happy-path environment, spelled out once. MOUNTPOINT_RCS="1 1": $STAGING is not a
# mountpoint at the stray probe (so the ls -A arm runs) and still not one at the mount guard (so
# `mount` runs) — the two calls the single global MOUNTPOINT_RC could never tell apart.
happy() {
  stage_case "${1:-$CUTOVER}" DRY_RUN=0 MOUNTPOINT_RCS="1 1" \
    CRYPTSETUP_DEV="$BLKDEV" FINDMNT_STAGING_SRC="$BLKDEV" FINDMNT_MOUNT_SRC="" \
    BLKID_FS="" DU_SRC=1024 DF_AVAIL=999999999 "${@:2}"
}

# ---------------------------------------------------------------------------
# T0 — POSITIVE CONTROL. Every rc-non-zero case below asserts on a $CALLS file that is populated
# well before the die it expects; without a case proving the function can reach `return 0` at all,
# the whole matrix could pass against a function that never succeeds.
# ---------------------------------------------------------------------------
happy
ran && ok "T0 prepare_staging_target succeeds on the first-cutover happy path (positive control)" \
    || no "T0 prepare_staging_target did not exit 0 on the happy path: rc=$CASE_RC ${CASE_OUT:0:400}"
markerF 'result=ok reason=prepared' \
  && ok "T0b the success path emits result=ok reason=prepared (a green run PROVES the assert ran)" \
  || no "T0b no ok marker on the happy path — a green run cannot be distinguished from a skipped gate"

# ---------------------------------------------------------------------------
# T16 — the first-cutover arm must emit reused=0. STAGING_FS_REUSED is assigned ONLY in the ext4
# arm unless it is `local`-initialised at the top; without that init, `set -u` aborts the
# first-cutover path on `unbound variable` at the marker and emits NOTHING at all — the exact
# no-telemetry shape this whole change exists to remove.
# ---------------------------------------------------------------------------
markerF 'reused=0' \
  && ok "T16 the first-cutover (empty-fs) arm emits reused=0 — no set -u unbound-variable abort" \
  || no "T16 no reused=0 on the first-cutover path: STAGING_FS_REUSED is unset there (set -u aborts, zero markers)"

# T16b — the mirror arm: an existing ext4 is REUSED, never re-mkfs'd, and says so.
happy "$CUTOVER" BLKID_FS="ext4"
ran && markerF 'reused=1' && nhas '^mkfs\.ext4 ' \
  && ok "T16b an existing ext4 is reused (reused=1) and is NOT re-mkfs'd (idempotent re-run)" \
  || no "T16b the ext4 reuse arm is wrong (rc=$CASE_RC) — a re-run would wipe an already-good copy"

# ---------------------------------------------------------------------------
# T1 — an UNRECOGNISED filesystem on the mapper must refuse, never mkfs. This arm is what stops a
# re-run destroying an already-good copy, so "no mkfs" is the load-bearing half of the assertion.
# ---------------------------------------------------------------------------
happy "$CUTOVER" BLKID_FS="xfs"
died && ok "T1 an unexpected mapper filesystem aborts" \
     || no "T1 a mapper carrying xfs did NOT abort (rc=$CASE_RC)"
nhas '^mkfs\.ext4 ' \
  && ok "T1b the unexpected-fs arm runs NO mkfs.ext4 (refuses destructively, does not format over it)" \
  || no "T1b mkfs.ext4 ran over an unrecognised filesystem — the refusal arm formats anyway"
outF 'EMIT_DRIFT: staging_unexpected_fs' \
  && ok "T1c the refusal is reported as staging_unexpected_fs" \
  || no "T1c no staging_unexpected_fs drift — the abort is undiagnosable without SSH"

# ---------------------------------------------------------------------------
# T2 — a failed mkfs must abort AND leave evidence. The marker has to be emitted BEFORE die() or
# the abort reaches the operator's only no-SSH channel as nothing at all.
# ---------------------------------------------------------------------------
happy "$CUTOVER" MKFS_RC=1
died && ok "T2 a failed mkfs.ext4 aborts the prepare" \
     || no "T2 a failed mkfs.ext4 was swallowed (rc=$CASE_RC) — the 2026-07-19 defect, one layer up"
outF 'EMIT_DRIFT: staging_mkfs_failed' \
  && ok "T2b the reason is staging_mkfs_failed" \
  || no "T2b no staging_mkfs_failed drift emitted"
t2_emit="$(awk '/SOLEUR_WORKSPACES_LUKS_STAGING_TARGET/{print NR; exit}' <<<"$CASE_OUT")"
t2_die="$(awk '/^DIE:/{print NR; exit}' <<<"$CASE_OUT")"
if [ -n "$t2_emit" ] && [ -n "$t2_die" ] && [ "$t2_emit" -lt "$t2_die" ]; then
  ok "T2c the staging-target marker PRECEDES die (evidence survives the abort)"
else
  no "T2c the marker does not precede die (marker=$t2_emit die=$t2_die)"
fi

# ---------------------------------------------------------------------------
# T3 — DRY_RUN short-circuits BEFORE anything touches the mapper. The rehearsal arm never runs
# luksOpen, so asserting `[ -b "$MAPPER" ]` past this point would abort every rehearsal.
# ---------------------------------------------------------------------------
stage_case "$CUTOVER" DRY_RUN=1 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" BLKID_FS=""
ran && ok "T3 DRY_RUN=1 returns 0 (the rehearsal is not aborted by the mapper asserts)" \
    || no "T3 DRY_RUN=1 did not return 0 (rc=$CASE_RC ${CASE_OUT:0:300}) — every rehearsal would abort"
markerF 'result=dryrun' \
  && ok "T3b the rehearsal emits result=dryrun (it is visibly a rehearsal, not a silent skip)" \
  || no "T3b no dryrun marker — a rehearsal is indistinguishable from a gate that never ran"
nhas '^mkfs\.ext4 ' && nhas '^mount ' \
  && ok "T3c DRY_RUN=1 runs neither mkfs.ext4 nor mount (host-side-effect-free past the read-only asserts)" \
  || no "T3c DRY_RUN=1 touched the mapper — a rehearsal is mutating the host"

# ---------------------------------------------------------------------------
# T4 — a non-mountpoint, NON-EMPTY $STAGING is a stray plaintext copy on the ROOT DISK: exactly
# what the 2026-07-19 run left behind. DETECT and REFUSE. Deleting it is a separate single-purpose
# PR — it is user data (AP-009) — so "no rm anywhere" is as load-bearing as the abort itself.
# ---------------------------------------------------------------------------
run_case "$CUTOVER" \
  'FRESH_DEV="$BLK"; MAPPER="$BLK"; : > "$WORKSPACES_STAGING/stray-copy"; prepare_staging_target' \
  'prepare_staging_target emit_staging_target _same_dev' \
  BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" CRYPTSETUP_DEV="$BLKDEV" \
  FINDMNT_STAGING_SRC="$BLKDEV" FINDMNT_MOUNT_SRC="" BLKID_FS="" DU_SRC=1024 DF_AVAIL=999999999
died && ok "T4 a non-mountpoint, non-empty \$STAGING aborts the prepare" \
     || no "T4 a stray root-disk copy did NOT abort (rc=$CASE_RC) — the prepare would run over it"
outF 'EMIT_DRIFT: staging_stray_present' \
  && ok "T4b the reason is staging_stray_present" \
  || no "T4b no staging_stray_present drift emitted"
nhas '^rm ' \
  && ok "T4c the stray guard runs NO rm — it detects and refuses, it never deletes user data (AP-009)" \
  || no "T4c an rm was issued against the stray copy — that is user data and a separate PR"

# ---------------------------------------------------------------------------
# T9 — $MAPPER absent must be named ACCURATELY. Unguarded, an absent mapper falls through to the
# "no filesystem" arm and dies as staging_mkfs_failed — a MISLEADING reason on the operator's only
# no-SSH channel. The reason IS the deliverable here, not merely the non-zero rc.
# ---------------------------------------------------------------------------
run_case "$CUTOVER" \
  'FRESH_DEV="$BLK"; MAPPER="$WORKSPACES_STAGING/no-such-mapper"; prepare_staging_target' \
  'prepare_staging_target emit_staging_target _same_dev' \
  BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" BLKID_FS="" \
  DU_SRC=1024 DF_AVAIL=999999999
died && ok "T9 an absent \$MAPPER aborts the prepare" \
     || no "T9 an absent \$MAPPER did not abort (rc=$CASE_RC)"
if outF 'EMIT_DRIFT: staging_mapper_absent' && ! outF 'EMIT_DRIFT: staging_mkfs_failed'; then
  ok "T9b the reason is staging_mapper_absent, NOT staging_mkfs_failed (the reason is accurate)"
else
  no "T9b an absent mapper is reported as the wrong condition — the operator chases the wrong failure"
fi

# ---------------------------------------------------------------------------
# T10 — a stale mapper left open by a prior run and backed by a DIFFERENT container satisfies the
# call site's `[ ! -e "$MAPPER" ]` skip, so everything downstream would operate on the wrong
# container while reporting success. `cryptsetup status` is the only thing that establishes
# mapper -> device; anchor it pre-freeze, where an abort costs zero downtime.
# ---------------------------------------------------------------------------
happy "$CUTOVER" CRYPTSETUP_DEV="/dev/disk/by-id/some-other-volume"
died && ok "T10 a mapper backed by a device other than \$FRESH_DEV aborts" \
     || no "T10 a stale mapper backed by the WRONG container was accepted (rc=$CASE_RC)"
outF 'EMIT_DRIFT: staging_mapper_wrong_device' \
  && ok "T10b the reason is staging_mapper_wrong_device" \
  || no "T10b no staging_mapper_wrong_device drift emitted"
nhas '^mkfs\.ext4 ' \
  && ok "T10c the wrong-device refusal runs NO mkfs (it does not format the wrong container)" \
  || no "T10c mkfs.ext4 ran against a mapper backed by the wrong device — destructive"

# ---------------------------------------------------------------------------
# T11 — re-dispatch after a successful cutover is the most likely operator action and previously
# had NO defined outcome: post-cutover $MOUNT *is* the mapper, so the blkid probe hits the ext4
# reuse arm, $STAGING is not a mountpoint, and the mapper gets mounted a SECOND time at $STAGING
# while live at $MOUNT — making the bulk rsync a source-into-itself copy.
# ---------------------------------------------------------------------------
happy "$CUTOVER" FINDMNT_MOUNT_SRC="$BLKDEV"
died && ok "T11 a re-run against an already-cutover \$MOUNT aborts" \
     || no "T11 a re-run onto the LIVE mapper was allowed (rc=$CASE_RC) — rsync would copy into itself"
outF 'EMIT_DRIFT: staging_already_cutover' \
  && ok "T11b the reason is staging_already_cutover" \
  || no "T11b no staging_already_cutover drift emitted"
if nhas '^mount ' && nhas '^rsync '; then
  ok "T11c the already-cutover refusal mounts nothing and never reaches the copy"
else
  no "T11c the already-cutover path still mounted or copied — the live volume is being re-staged"
fi

# ---------------------------------------------------------------------------
# Tsm — THE STAGING MOUNT-SOURCE POSITIVE CONTROL. This is the primary regression guard for the
# 2026-07-19 incident and the only assert in the function that answers "WHERE DO THE BYTES GO?".
# Every other gate — C1 byte-identity, the `du` assert, `git fsck`, the G3 manifest — is a pure
# function of the two STRINGS "$MOUNT" and "$STAGING"; not one anchors either to a device, so
# nothing in that closure can distinguish "right bytes, wrong device". Deleting this control must
# turn the suite RED (mutation MS16 below), which it previously did not: the happy path fed
# findmnt the mapper, so the gate was always satisfied and never exercised negatively.
#
# The gate is reached AFTER the mount, so `mount` succeeding proves nothing about the target: a
# stale bind, a root-disk directory, or a second volume all mount fine.
# ---------------------------------------------------------------------------

# Tsm1 — findmnt reports NO source for $STAGING: the mount call "succeeded" but the target cannot
# be anchored to any device. _same_dev fails closed on the empty operand without needing `[ -b ]`
# on it, so this is the cheap, host-independent half of the control.
happy "$CUTOVER" FINDMNT_STAGING_SRC=""
died && ok "Tsm1 an unreadable \$STAGING mount source aborts (a successful mount is NOT proof of target)" \
     || no "Tsm1 an unanchorable staging target was accepted (rc=$CASE_RC) — the wrong-target guard is inert"
outF 'EMIT_DRIFT: staging_not_mapper' \
  && ok "Tsm1b the reason is staging_not_mapper" \
  || no "Tsm1b no staging_not_mapper drift emitted"
markerF 'reason=source_not_mapper' && markerF 'source=<none>' \
  && ok "Tsm1c the marker names reason=source_not_mapper and source=<none> (diagnosable off-box)" \
  || no "Tsm1c the staging-target marker does not carry the unanchored source"
if nhas '^df ' && nhas '^du ' && ! markerF 'result=ok'; then
  ok "Tsm1d the run does NOT proceed past the control (no capacity probe, no result=ok marker)"
else
  no "Tsm1d the run continued past an unverified target — the copy would be certified anyway"
fi

# Tsm2 — the TRUER analogue of the incident: $STAGING really is mounted, from a real block device,
# but NOT the mapper. Needs two distinct real block devices (see harness_blockdev_other).
OTHERDEV="$(harness_blockdev_other "$BLKDEV" || true)"
if [ -z "$OTHERDEV" ]; then
  printf 'skip - Tsm2 NOT RUN: this host exposes only one block device (%s), so "mounted from a real but WRONG device" cannot be modelled without faking the second operand. Tsm1 remains the load-bearing case here; the real-device form is L5c/L5d in the loopback suite.\n' "$BLKDEV"
else
  happy "$CUTOVER" FINDMNT_STAGING_SRC="$OTHERDEV"
  died && ok "Tsm2 \$STAGING mounted from a real but WRONG block device aborts (the 2026-07-19 shape)" \
       || no "Tsm2 a copy onto the WRONG device was certified (rc=$CASE_RC, src=$OTHERDEV) — the incident, unfixed"
  outF 'EMIT_DRIFT: staging_not_mapper' \
    && ok "Tsm2b the wrong-device refusal is reported as staging_not_mapper" \
    || no "Tsm2b no staging_not_mapper drift on a wrong-device staging mount"
  if nhas '^df ' && nhas '^du ' && ! markerF 'result=ok'; then
    ok "Tsm2c the wrong-device run does NOT proceed to the capacity probe or emit result=ok"
  else
    no "Tsm2c the run continued after mounting the wrong device — every downstream gate then lies"
  fi
fi

# ---------------------------------------------------------------------------
# T12 — the capacity gate. This change is what first makes ENOSPC REACHABLE: before the fix the
# copy landed on the root disk (where it fit); now it lands in the mapper, whose usable capacity is
# the volume MINUS the LUKS2 header MINUS ext4 metadata. The delta rsync is INSIDE the freeze,
# where an ENOSPC burns an irreversible-freeze approval.
# ---------------------------------------------------------------------------
happy "$CUTOVER" DU_SRC=4096 DF_AVAIL=100
died && ok "T12 a target smaller than the source aborts BEFORE the freeze" \
     || no "T12 an under-capacity target was accepted (rc=$CASE_RC) — ENOSPC lands inside the freeze"
outF 'EMIT_DRIFT: staging_insufficient_capacity' \
  && ok "T12b the reason is staging_insufficient_capacity" \
  || no "T12b no staging_insufficient_capacity drift emitted"

# T12b2 — the boundary. `-gt`, not `-ge`: an EXACTLY-equal target cannot hold the copy plus ext4
# metadata, and an off-by-one here is the difference between a pre-freeze abort and an in-freeze one.
happy "$CUTOVER" DU_SRC=4096 DF_AVAIL=4096
died && ok "T12c an exactly-equal avail/src is REFUSED (-gt, not -ge)" \
     || no "T12c avail == src was accepted — the LUKS header + ext4 metadata make that a guaranteed ENOSPC"

# ---------------------------------------------------------------------------
# T13 — a NON-NUMERIC capacity probe must abort, not pass vacuously. `[ "$avail_b" -gt "$src_b" ]`
# on garbage is a bash error, and a swallowed error here is the fail-open shape this whole change
# exists to remove. (df's output is filtered through `tr -dc 0-9`, so its garbage arrives as EMPTY;
# du's is not, so it arrives as literal garbage. Both must be caught.)
# ---------------------------------------------------------------------------
happy "$CUTOVER" DU_SRC="not-a-number" DF_AVAIL=999999999
died && ok "T13 a non-numeric du result aborts the capacity gate" \
     || no "T13 a non-numeric source size passed the capacity gate vacuously (rc=$CASE_RC)"
outF 'EMIT_DRIFT: staging_capacity_unreadable' \
  && ok "T13b the reason is staging_capacity_unreadable" \
  || no "T13b no staging_capacity_unreadable drift emitted"
happy "$CUTOVER" DU_SRC=1024 DF_AVAIL=""
died && outF 'EMIT_DRIFT: staging_capacity_unreadable' \
     && ok "T13c an EMPTY df result also aborts (each operand is checked separately)" \
     || no "T13c an empty avail was not caught — a combined \"\$a|\$b\" pattern gets this case wrong"

# ---------------------------------------------------------------------------
# T14 — _same_dev must fail CLOSED. The naive canonicalizer
#   [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
# fails OPEN: if readlink errors or is absent BOTH substitutions yield "" and "" = "" is TRUE,
# certifying a mount that was never verified.
# ---------------------------------------------------------------------------
run_case "$CUTOVER" '_same_dev "$BLK" "$BLK"' '_same_dev' BLK="$BLKDEV"
ran && ok "T14z _same_dev returns 0 for two paths naming the SAME block device (positive control)" \
    || no "T14z _same_dev rejected a genuine same-device pair (rc=$CASE_RC) — every case below is vacuous"
run_case "$CUTOVER" '_same_dev "$BLK" "$BLK"' '_same_dev' BLK="$BLKDEV" READLINK_RC=1
died && ok "T14 _same_dev returns non-zero when readlink FAILS (fails closed, not open)" \
     || no "T14 a failed readlink was read as 'same device' — the naive fail-open form is present"
run_case "$CUTOVER" '_same_dev "$BLK" "$BLK"' '_same_dev' BLK="$BLKDEV" READLINK_EMPTY=1
died && ok "T14b _same_dev returns non-zero when readlink prints NOTHING (\"\" = \"\" is not proof)" \
     || no "T14b an empty readlink result was read as 'same device' — the other half of the fail-open"
run_case "$CUTOVER" '_same_dev "" "$BLK"' '_same_dev' BLK="$BLKDEV"
died && ok "T14c _same_dev rejects an empty operand (an unreported findmnt SOURCE is not a match)" \
     || no "T14c an empty operand was accepted as a device match"
run_case "$CUTOVER" '_same_dev "$WORKSPACES_STAGING" "$WORKSPACES_STAGING"' '_same_dev' BLK="$BLKDEV"
died && ok "T14d _same_dev rejects two identical paths that are NOT block devices (\`[ -b \$b ]\` is load-bearing)" \
     || no "T14d two equal non-block paths were certified as the same block device"

# ---------------------------------------------------------------------------
# The repoint block — extracted verbatim from the SUT and executed against the same stubs. It lives
# in the main body, hundreds of lines past a freeze and a bulk rsync, so it is unreachable from a
# function-level invocation; extracting it keeps the assertions pinned to the REAL lines (a
# mutation to them flips these cases) without running the whole cutover.
# ---------------------------------------------------------------------------
extract_repoint() {  # <script> -> path to the extracted block, or empty when extraction missed
  local src="$1" out; out="$(mktemp -p "$RUN_SCRATCH" repoint.XXXXXX.sh)"
  awk '/^step "repoint_luks_mount/,/^step "docker start/' "$src" > "$out"
  # Drop the trailing `step "docker start` sentinel line that closed the awk range.
  sed -i '$d' "$out"
  # Did-the-extraction-land guard: an extraction that silently produced the wrong lines would make
  # every case below pass or fail for a reason unrelated to the code under test.
  # Anchored on constructs NO mutation below rewrites: MS7 replaces the staging_umount_failed
  # fail-closure, so anchoring the guard on that slug would make the extraction "miss" for the very
  # mutation it is meant to prove — reporting un-run instead of RED.
  if grep -qF 'umount "$STAGING"' "$out" \
     && grep -qF 'mount "$MAPPER" "$MOUNT"' "$out" \
     && grep -qF 'cryptsetup status "$MAPPER_NAME"' "$out" \
     && bash -n "$out" 2>/dev/null; then
    printf '%s\n' "$out"
  fi
}

repoint_case() {  # <script> [env...]
  local script="$1"; shift
  local blk; blk="$(extract_repoint "$script")"
  if [ -z "$blk" ]; then CASE_RC=98; CASE_OUT="REPOINT_EXTRACTION_MISSED"; CALLS=/dev/null; return; fi
  run_case "$script" \
    'DRY_RUN=0; FRESH_DEV="$BLK"; MAPPER="$BLK"; FLIP_DONE=0; CANARY_OK=0; source "$REPOINT_BLOCK"' \
    'emit_drift persist_state' \
    BLK="$BLKDEV" REPOINT_BLOCK="$blk" "$@"
}

# MOUNTPOINT_RCS="1 0" is the STATE TRANSITION: after `umount "$MOUNT"` the repoint asserts $MOUNT
# is NOT a mountpoint (rc 1), and after `mount "$MAPPER" "$MOUNT"` the canary asserts it IS (rc 0).
# One global rc cannot express that, and without it neither T5/T6 nor their control is writable.
repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS"
if [ "$CASE_OUT" = "REPOINT_EXTRACTION_MISSED" ]; then
  no "T5z repoint extraction MISSED — treat T5/T6 as un-run, not as evidence"
else
  ran && ok "T5z the repoint block completes and reaches the host canary (positive control)" \
      || no "T5z the repoint block did not complete on the happy path: rc=$CASE_RC ${CASE_OUT:0:300}"
  hasF 'cryptsetup status' \
    && ok "T5z2 the happy repoint reaches the C13 host canary" \
    || no "T5z2 the happy repoint never reached the canary — T6's negative assertion would be vacuous"
fi

# T5 — a swallowed umount here left $MAPPER mounted at $STAGING *and then* at $MOUNT. The
# post-repoint assert only checks $MOUNT, so it PASSED; rollback() then swallowed the resulting
# EBUSY, remounted plaintext and reported success — leaving plaintext live at $MOUNT and an open
# mapper holding a divergent full copy at $STAGING, with no telemetry at all.
repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS" \
  UMOUNT_FAIL_MATCH="/staging"
died && ok "T5 a failed \`umount \$STAGING\` aborts the repoint" \
     || no "T5 a failed staging umount was swallowed (rc=$CASE_RC) — two live divergent copies"
outF 'EMIT_DRIFT: staging_umount_failed' \
  && ok "T5b the reason is staging_umount_failed" \
  || no "T5b no staging_umount_failed drift emitted"
nhas '^mount ' \
  && ok "T5c the abort happens BEFORE \`mount \$MAPPER \$MOUNT\` (the mapper is never stacked over plaintext)" \
  || no "T5c the mapper was mounted at \$MOUNT despite the failed staging umount"

# T6 — a failed repoint mount must abort before the canary. The canary would otherwise run against
# whatever is still mounted at $MOUNT and certify it.
repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS" \
  MOUNT_RC=1
died && ok "T6 a failed \`mount \$MAPPER \$MOUNT\` aborts the repoint" \
     || no "T6 a failed repoint mount was swallowed (rc=$CASE_RC)"
outF 'EMIT_DRIFT: repoint_mount_failed' \
  && ok "T6b the reason is repoint_mount_failed" \
  || no "T6b no repoint_mount_failed drift emitted"
if nhas 'cryptsetup status' && nhas '^blkid '; then
  ok "T6c the run does NOT reach the C13 host canary after a failed repoint"
else
  no "T6c the canary ran after a failed repoint — it would certify whatever is still at \$MOUNT"
fi

# ---------------------------------------------------------------------------
# Whole-script cases (L3 gate, luksFormat) — these lines run in the MAIN BODY before any function
# the harness can invoke, so they are exercised by EXECUTING the script against PATH stubs.
#
# The script is copied ALONE into a scratch dir: with no sibling workspaces-luks-emit.sh and no
# /usr/local/bin/workspaces-luks-emit.sh, `command -v workspaces_luks_emit` fails and emit_drift
# takes its documented fallback branch, printing `DRIFT reason=<slug>` — which is what makes the
# reason assertable here at all.
# ---------------------------------------------------------------------------
SCRIPT_RC=0; SCRIPT_OUT=""; SCRIPT_CALLS=""
script_case() {  # <script> <findmnt-source> [env assignments...]
  local src="$1" fmsrc="$2"; shift 2
  local d; d="$(mktemp -d -p "$RUN_SCRATCH" script.XXXXXX)"
  mkdir -p "$d/bin"
  cp "$src" "$d/workspaces-cutover.sh"
  SCRIPT_CALLS="$d/calls"; : > "$SCRIPT_CALLS"
  local b
  for b in mountpoint blkid mount umount logger systemctl docker df du rsync lsof mkfs.ext4 install; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s $*" >> "$CALLS"\nexit 0\n' "$b" > "$d/bin/$b"
  done
  printf '#!/usr/bin/env bash\nprintf "findmnt %%s\\n" "$*" >> "$CALLS"\nprintf "%%s\\n" "$FINDMNT_SRC"\n' > "$d/bin/findmnt"
  printf '#!/usr/bin/env bash\nprintf "doppler %%s\\n" "$*" >> "$CALLS"\nprintf "test-passphrase\\n"\n' > "$d/bin/doppler"
  printf '#!/usr/bin/env bash\nprintf "cryptsetup %%s\\n" "$*" >> "$CALLS"\ncase "$*" in *luksFormat*) exit "${LUKSFORMAT_RC:-0}";; esac\nexit 0\n' > "$d/bin/cryptsetup"
  chmod +x "$d/bin"/*
  SCRIPT_OUT="$(
    env "$@" CALLS="$SCRIPT_CALLS" FINDMNT_SRC="$fmsrc" \
      PATH="$d/bin:$PATH" \
      WORKSPACES_MOUNT="$d/mnt" WORKSPACES_STAGING="$d/staging" \
      WORKSPACES_STATE_DIR="$d/state" \
    bash "$d/workspaces-cutover.sh" 2>&1
  )"
  SCRIPT_RC=$?
}
sout() { [[ "$SCRIPT_OUT" == *"$1"* ]]; }

# T7 — the L3 source-anchor. `$MOUNT` is the SOURCE OF EVERY BYTE and the path rollback() remounts;
# anchoring it only as a `log WARN` was a live counterexample to the invariant the staging guards
# enforce three functions above (a gate that certifies a path must first anchor it to a device).
script_case "$CUTOVER" "/proc/self/mounts" DRY_RUN=1
if [ "$SCRIPT_RC" -ne 0 ] && sout 'L3: '; then
  ok "T7 L3 aborts when \$MOUNT's findmnt SOURCE is not a block device (was a log WARN)"
else
  no "T7 a non-block \$MOUNT source did not abort at L3 (rc=$SCRIPT_RC) — the copy source is unanchored"
fi
# T7b — POSITIVE CONTROL: with a REAL block device the run must get PAST L3. Without this, T7 would
# also pass against a script that aborts at L3 unconditionally.
script_case "$CUTOVER" "$BLKDEV" DRY_RUN=1
if sout 'L3: '; then
  no "T7b the L3 gate aborts even on a genuine block device — T7 proves nothing"
else
  ok "T7b a genuine block-device source passes L3 (the gate discriminates, it does not just abort)"
fi

# T15 — a failed luksFormat must abort BEFORE luksOpen. Unguarded, the run continues, luksOpen
# fails too, $MAPPER stays absent, and prepare_staging_target then dies as staging_mkfs_failed —
# a misleading reason on the operator's only no-SSH channel.
script_case "$CUTOVER" "$BLKDEV" DRY_RUN=0 ROLLBACK=0 WORKSPACES_LUKS_DEV="$BLKDEV" LUKSFORMAT_RC=1
[ "$SCRIPT_RC" -ne 0 ] && ok "T15 a failed luksFormat aborts the run" \
                       || no "T15 a failed luksFormat did not abort (rc=$SCRIPT_RC)"
sout 'DRIFT reason=luksformat_failed' \
  && ok "T15b the reason is luksformat_failed" \
  || no "T15b no luksformat_failed drift emitted: ${SCRIPT_OUT:0:300}"
if grep -qF 'luksFormat' "$SCRIPT_CALLS" && ! grep -qE 'cryptsetup luksOpen' "$SCRIPT_CALLS"; then
  ok "T15c luksOpen is NOT reached after a failed luksFormat"
else
  no "T15c the run proceeded to luksOpen after luksFormat failed — the abort reason ends up wrong"
fi

# ---------------------------------------------------------------------------
# T8 — VACUITY GUARD. Deleting prepare_staging_target from a scratch copy must make every case
# above report HARNESS_UNDEFINED rather than pass. Without this the whole rc-non-zero matrix could
# be green against a script where the function does not exist: the subshell fails for the wrong
# reason and `died` cannot tell the difference.
# ---------------------------------------------------------------------------
VAC="$RUN_SCRATCH/vacuity.sh"
awk '/^prepare_staging_target\(\) \{$/{skip=1} skip && /^\}$/{skip=0; next} skip{next} 1' \
  "$CUTOVER" > "$VAC"
if grep -qE '^prepare_staging_target\(\) \{' "$VAC" || ! bash -n "$VAC" 2>/dev/null; then
  no "T8 the vacuity mutation did NOT land (function still present, or the copy no longer parses) — treat as un-run"
else
  vac_fail=""
  happy "$VAC";                                        undef || vac_fail="$vac_fail T0"
  happy "$VAC" BLKID_FS="xfs";                         undef || vac_fail="$vac_fail T1"
  happy "$VAC" MKFS_RC=1;                              undef || vac_fail="$vac_fail T2"
  stage_case "$VAC" DRY_RUN=1 MOUNTPOINT_RCS="1 1";    undef || vac_fail="$vac_fail T3"
  happy "$VAC" CRYPTSETUP_DEV="/dev/other";            undef || vac_fail="$vac_fail T10"
  happy "$VAC" FINDMNT_MOUNT_SRC="$BLKDEV";            undef || vac_fail="$vac_fail T11"
  happy "$VAC" DU_SRC=4096 DF_AVAIL=100;               undef || vac_fail="$vac_fail T12"
  happy "$VAC" DU_SRC="garbage";                       undef || vac_fail="$vac_fail T13"
  [ -z "$vac_fail" ] \
    && ok "T8 with prepare_staging_target deleted every case reports HARNESS_UNDEFINED (none is vacuous)" \
    || no "T8 these cases pass WITHOUT prepare_staging_target existing — they are vacuous:$vac_fail"
fi

# ---------------------------------------------------------------------------
# Mutation tests — break the SUT, confirm the case goes RED. Each carries the did-the-sed-land
# guard: a sed that silently missed reports as "un-run", never as evidence.
# ---------------------------------------------------------------------------
mutate() {
  local mut; mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"
  cp "$CUTOVER" "$mut"
  local e; for e in "$@"; do sed -i "$e" "$mut"; done
  printf '%s\n' "$mut"
}

# MS1 — fold the unexpected-fs refusal into the ext4 reuse arm => T1 must flip.
MS1="$(mutate 's|^  elif \[ "\$fs_type" = "ext4" \]; then$|  elif [ -n "$fs_type" ]; then|')"
if ! grep -qF 'elif [ -n "$fs_type" ]; then' "$MS1"; then
  no "mutation MS1 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS1" BLKID_FS="xfs"
  ran && ok "mutation MS1 (accept any non-empty fs as reusable): T1 flips (the refusal arm is load-bearing)" \
      || no "mutation MS1 did not flip T1 (rc=$CASE_RC)"
fi

# MS2 — swallow the mkfs failure => T2 must flip.
MS2="$(mutate 's|^      die "mkfs.ext4 failed on \$MAPPER.*$|      :|')"
if grep -qF 'die "mkfs.ext4 failed on $MAPPER' "$MS2"; then
  no "mutation MS2 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS2" MKFS_RC=1
  ran && ok "mutation MS2 (drop the mkfs die): T2 flips (the mkfs fail-closure is load-bearing)" \
      || no "mutation MS2 did not flip T2 (rc=$CASE_RC)"
fi

# MS3 — neuter the stray guard => T4 must flip.
MS3="$(mutate 's|^  if ! mountpoint -q "\$STAGING" && \[ -n "\$(ls -A "\$STAGING" 2>/dev/null)" \]; then$|  if false; then|')"
if ! grep -qE '^  if false; then$' "$MS3"; then
  no "mutation MS3 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MS3" \
    'FRESH_DEV="$BLK"; MAPPER="$BLK"; : > "$WORKSPACES_STAGING/stray-copy"; prepare_staging_target' \
    'prepare_staging_target emit_staging_target _same_dev' \
    BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" CRYPTSETUP_DEV="$BLKDEV" \
    FINDMNT_STAGING_SRC="$BLKDEV" FINDMNT_MOUNT_SRC="" BLKID_FS="" DU_SRC=1024 DF_AVAIL=999999999
  ran && ok "mutation MS3 (drop the stray guard): T4 flips (the guard is load-bearing)" \
      || no "mutation MS3 did not flip T4 (rc=$CASE_RC)"
fi

# MS4 — misreport an absent mapper as a mkfs failure => T9b must flip. This pins the REASON, not
# just the rc: the rc-only assertion stays green under this mutation.
MS4="$(mutate 's|emit_staging_target fail mapper_absent|emit_staging_target fail mkfs_failed|' \
              's|emit_drift staging_mapper_absent|emit_drift staging_mkfs_failed|')"
if grep -qF 'emit_drift staging_mapper_absent' "$MS4"; then
  no "mutation MS4 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MS4" \
    'FRESH_DEV="$BLK"; MAPPER="$WORKSPACES_STAGING/no-such-mapper"; prepare_staging_target' \
    'prepare_staging_target emit_staging_target _same_dev' \
    BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" BLKID_FS="" \
    DU_SRC=1024 DF_AVAIL=999999999
  if outF 'EMIT_DRIFT: staging_mapper_absent'; then
    no "mutation MS4 did not flip T9b — the reason is unpinned"
  else
    ok "mutation MS4 (report an absent mapper as mkfs_failed): T9b flips (the reason is load-bearing)"
  fi
fi

# MS5 — neuter the capacity comparison => T12 must flip.
MS5="$(mutate 's@^  \[ "\$avail_b" -gt "\$src_b" \] || {$@  [ 1 = 0 ] \&\& {@')"
if ! grep -qF '[ 1 = 0 ] && {' "$MS5"; then
  no "mutation MS5 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS5" DU_SRC=4096 DF_AVAIL=100
  ran && ok "mutation MS5 (drop the capacity comparison): T12 flips (the ENOSPC gate is load-bearing)" \
      || no "mutation MS5 did not flip T12 (rc=$CASE_RC)"
fi

# MS6 — restore the naive fail-OPEN canonicalizer => T14/T14b must flip.
MS6="$(mutate 's|^  \[ -n "\$a" \] && \[ -n "\$b" \] && \[ -b "\$b" \] && \[ "\$a" = "\$b" \]$|  [ "$a" = "$b" ]|')"
if ! grep -qE '^  \[ "\$a" = "\$b" \]$' "$MS6"; then
  no "mutation MS6 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MS6" '_same_dev "$BLK" "$BLK"' '_same_dev' BLK="$BLKDEV" READLINK_EMPTY=1
  ran && ok "mutation MS6 (naive readlink comparison): T14b flips (the fail-CLOSED form is load-bearing)" \
      || no "mutation MS6 did not flip T14b (rc=$CASE_RC)"
fi

# MS7 — swallow the repoint staging umount => T5 must flip (the mapper gets mounted at $MOUNT).
MS7="$(mutate 's@^  umount "\$STAGING" || { emit_drift staging_umount_failed.*$@  umount "$STAGING" || true@')"
if ! grep -qE '^  umount "\$STAGING" \|\| true$' "$MS7"; then
  no "mutation MS7 sed did NOT land — treat as un-run, not evidence"
else
  repoint_case "$MS7" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS" \
    UMOUNT_FAIL_MATCH="/staging"
  if [ "$CASE_OUT" = "REPOINT_EXTRACTION_MISSED" ]; then
    no "mutation MS7 repoint extraction MISSED — treat as un-run, not evidence"
  else
  has '^mount ' \
    && ok "mutation MS7 (swallow the staging umount): T5c flips (the fail-closure is load-bearing)" \
    || no "mutation MS7 did not flip T5c"
  fi
fi

# MS8 — revert the L3 anchor to the `log WARN` it used to be => T7 must flip.
MS8="$(mutate 's@^  || die "L3: \$MOUNT source is not a block device.*$@  || log "WARN: L3 source is not a block device"@')"
if ! grep -qF '|| log "WARN: L3 source is not a block device"' "$MS8"; then
  no "mutation MS8 sed did NOT land — treat as un-run, not evidence"
else
  script_case "$MS8" "/proc/self/mounts" DRY_RUN=1
  sout 'L3: ' \
    && no "mutation MS8 did not flip T7 — the L3 anchor is unpinned" \
    || ok "mutation MS8 (restore the L3 log WARN): T7 flips (the block-device anchor is load-bearing)"
fi

# MS9 — swallow the luksFormat failure => T15c must flip (luksOpen is reached).
MS9="$(mutate 's@^    || { emit_drift luksformat_failed;.*$@    || true@')"
if ! grep -qE '^    \|\| true$' "$MS9"; then
  no "mutation MS9 sed did NOT land — treat as un-run, not evidence"
else
  script_case "$MS9" "$BLKDEV" DRY_RUN=0 ROLLBACK=0 WORKSPACES_LUKS_DEV="$BLKDEV" LUKSFORMAT_RC=1
  grep -qE 'cryptsetup luksOpen' "$SCRIPT_CALLS" \
    && ok "mutation MS9 (swallow the luksFormat failure): T15c flips (the fail-closure is load-bearing)" \
    || no "mutation MS9 did not flip T15c"
fi

# MS10 — drop the `local STAGING_FS_REUSED=0` init => T16 must flip. Under `set -u` the
# first-cutover path then aborts on `unbound variable` at the marker and emits NOTHING.
MS10="$(mutate 's|^  local STAGING_FS_REUSED=0.*$|  local _dropped_init=0|')"
if grep -qF 'local STAGING_FS_REUSED=0' "$MS10"; then
  no "mutation MS10 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS10"
  if ran && markerF 'reused=0'; then
    no "mutation MS10 did not flip T16 — the STAGING_FS_REUSED init is unpinned"
  else
    ok "mutation MS10 (drop the STAGING_FS_REUSED init): T16 flips (set -u aborts the first cutover)"
  fi
fi

# MS11 — remove the DRY_RUN short-circuit => T3 must flip (the rehearsal now runs the mapper
# asserts it was deliberately placed above, and aborts).
MS11="$(mutate 's@^  if \[ "\$DRY_RUN" = "1" \]; then$@  if false; then@')"
if ! grep -qE '^  if false; then$' "$MS11"; then
  no "mutation MS11 sed did NOT land — treat as un-run, not evidence"
else
  stage_case "$MS11" DRY_RUN=1 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" BLKID_FS=""
  ran && no "mutation MS11 did not flip T3 — the dry-run short-circuit is unpinned" \
      || ok "mutation MS11 (drop the DRY_RUN short-circuit): T3 flips (every rehearsal would abort)"
fi

# MS12 — swallow the repoint mount failure => T6c must flip (the canary certifies whatever is
# still mounted at $MOUNT).
MS12="$(mutate 's@^    || { emit_drift repoint_mount_failed;.*$@    || true@')"
if ! grep -qE '^    \|\| true$' "$MS12"; then
  no "mutation MS12 sed did NOT land — treat as un-run, not evidence"
else
  repoint_case "$MS12" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS" MOUNT_RC=1
  if [ "$CASE_OUT" = "REPOINT_EXTRACTION_MISSED" ]; then
    no "mutation MS12 repoint extraction MISSED — treat as un-run, not evidence"
  else
    hasF 'cryptsetup status' \
      && ok "mutation MS12 (swallow the repoint mount failure): T6c flips (the fail-closure is load-bearing)" \
      || no "mutation MS12 did not flip T6c"
  fi
fi

# MS13 — drop the mapper->device anchor => T10 must flip (a stale mapper backed by a DIFFERENT
# container is accepted and everything downstream operates on the wrong container).
MS13="$(mutate 's@^  _same_dev "\$mapper_dev" "\$FRESH_DEV" || {$@  [ 1 = 0 ] \&\& {@')"
if ! grep -qF '[ 1 = 0 ] && {' "$MS13"; then
  no "mutation MS13 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS13" CRYPTSETUP_DEV="/dev/disk/by-id/some-other-volume"
  ran && ok "mutation MS13 (drop the mapper->device anchor): T10 flips (cryptsetup status is load-bearing)" \
      || no "mutation MS13 did not flip T10 (rc=$CASE_RC)"
fi

# MS14 — drop the already-cutover refusal => T11 must flip (a re-dispatch re-stages the LIVE volume).
MS14="$(mutate 's@^  if _same_dev "\$mount_src" "\$MAPPER"; then$@  if false; then@')"
if ! grep -qE '^  if false; then$' "$MS14"; then
  no "mutation MS14 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS14" FINDMNT_MOUNT_SRC="$BLKDEV"
  ran && ok "mutation MS14 (drop the already-cutover refusal): T11 flips (re-dispatch is load-bearing)" \
      || no "mutation MS14 did not flip T11 (rc=$CASE_RC)"
fi

# MS15 — drop the non-numeric capacity check => T13b must flip. The run still dies (bash errors on
# `[ garbage -gt 1024 ]`), but under the WRONG reason — so this pins the reason, not the rc.
MS15="$(mutate 's@^  if \[ "\$_capacity_bad" = "1" \]; then$@  if false; then@')"
if ! grep -qE '^  if false; then$' "$MS15"; then
  no "mutation MS15 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS15" DU_SRC="not-a-number" DF_AVAIL=999999999
  outF 'EMIT_DRIFT: staging_capacity_unreadable' \
    && no "mutation MS15 did not flip T13b — the capacity-unreadable reason is unpinned" \
    || ok "mutation MS15 (drop the non-numeric check): T13b flips (a garbage probe reports the wrong reason)"
fi

# MS16 — DELETE the staging mount-source positive control outright (the coordinator's independent
# mutation). This is the guard for the actual incident, and merge-time coverage for it lives ONLY
# here: infra-validation.yml is not in ruleset-ci-required.tf, so the loopback suite that also
# covers it (L5c/L5d, loop devices + sudo) is advisory at PR time. If this mutation stays green,
# the guard for the incident this PR exists to fix has no blocking coverage at all.
MS16="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"
# awk, not perl: keeps the mutation dependency-free on any runner. Deletes from the `_same_dev
# "$staging_src" ...` line through its closing `  }`.
awk '
  s==0 && /^  _same_dev "\$staging_src" "\$MAPPER" \|\| \{$/ { s=1; print "  : # MUTANT"; next }
  s==1 { if ($0 == "  }") s=0; next }
  1
' "$CUTOVER" > "$MS16"
if grep -qF '_same_dev "$staging_src" "$MAPPER"' "$MS16" || ! bash -n "$MS16" 2>/dev/null; then
  no "mutation MS16 did NOT land (control still present, or the mutant no longer parses) — treat as un-run"
else
  # Tsm1/Tsm2 assert `died`, so the mutation FLIPS them when the mutant returns 0 — i.e. `ran`.
  happy "$MS16" FINDMNT_STAGING_SRC=""
  ran && ok "mutation MS16 (delete the staging mount-source control): Tsm1 flips (the incident guard is load-bearing)" \
      || no "mutation MS16 did not flip Tsm1 — the control can be DELETED and this suite stays green (rc=$CASE_RC)"
  if [ -n "${OTHERDEV:-}" ]; then
    happy "$MS16" FINDMNT_STAGING_SRC="$OTHERDEV"
    ran && ok "mutation MS16b (delete the control): Tsm2 flips (the wrong-device case is load-bearing)" \
        || no "mutation MS16b did not flip Tsm2 — a wrong-device staging mount survives the control's deletion (rc=$CASE_RC)"
  fi
fi

# ---------------------------------------------------------------------------
echo
echo "workspaces-luks-staging.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
