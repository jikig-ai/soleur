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

# drift_n — how many drift markers this case emitted. Every emit_drift assertion in this suite is
# positive ("X happened"), which cannot catch a case that fires the RIGHT drift plus a spurious
# second one, nor a happy path that emits drift at all. Counted, not grepped.
drift_n() { awk '/^EMIT_DRIFT: /{c++} END{print c+0}' <<<"$CASE_OUT"; }
one_drift()  { [ "$(drift_n)" = "1" ]; }
zero_drift() { [ "$(drift_n)" = "0" ]; }

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
zero_drift \
  && ok "T0c the success path emits NO drift at all (the drift channel is not noisy on green runs)" \
  || no "T0c the happy path emitted $(drift_n) drift marker(s) — a green cutover would page the operator"

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
# That separate PR has since landed as clean_stray() (T4d-T4j below, ADR-119 "Addendum
# (2026-07-19): the stray-copy carve-out"); T4c's scope is prepare_staging_target ONLY and is
# deliberately left byte-identical — it is not a whole-file prohibition on rm.
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
# T4d-T4j — clean_stray(), the CLEAN_STRAY=1 operator entrypoint. This is the "separate
# single-purpose PR" T4c's comment anticipated: the ONE sanctioned deletion of the stray, a
# documented AP-009 deviation (ADR-119 "Addendum (2026-07-19): the stray-copy carve-out").
#
# T4c above is deliberately NOT edited and NOT weakened. Its run_case invokes
# prepare_staging_target ONLY, which still issues no rm on any path — so "detect and refuse"
# stays mechanically enforced for every arm that is not this explicit entrypoint. Read T4c as a
# prohibition on prepare_staging_target, NOT on the whole file.
#
# ASSERTION IDIOM: these cases must NOT reuse T4c's bare `^rm ` — the harness makes rm a
# PASSTHROUGH RECORDER (`rm() { rec "rm $*"; command rm "$@"; }`), so every rm in traced scope is
# recorded including incidental temp cleanup. Refusal assertions are $STAGING-scoped.
# T4d carries the POSITIVE CONTROL (`has "^rm -rf .*$STG"` — $STG is the harness stub $STAGING
# in the OUTER shell; $WORKSPACES_STAGING exists only INSIDE the case subshell): without it, a
# clean_stray() that deleted via `find -exec rm` (invoking the real /bin/rm binary rather than the
# harness shell function) would be invisible to the recorder and EVERY negative assertion below
# would pass vacuously.
# ---------------------------------------------------------------------------

# FIXTURE LAYOUT MIRRORS THE REAL HOST. On web-1 the top level of $MOUNT is INFRASTRUCTURE
# (`workspaces/`, `plugins/`, `redis/`) and per-user trees live at `workspaces/<id>/`. An earlier
# revision of these fixtures put entries at depth 1 (`ws-a`, `ws-ORPHAN`), which made the subset
# check LOOK covered while, on the real host, it reduced to "does $MOUNT contain a directory named
# workspaces?" — true in every reachable state, including one where the stray held a user's only
# surviving copy. T4f below is the case that pins the difference: its depth-1 view is IDENTICAL on
# both sides, so a depth-1 check passes it and only a depth-2 check refuses.

# T4d — the happy path: non-mountpoint non-empty $STAGING, healthy $MOUNT, subset holds.
# Fixture deliberately includes a DOTFILE: `rm -rf "$STAGING"/*` misses dotfiles, which would
# leave the stray guard correctly still firing after a "successful" cleanup.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1" "$WORKSPACES_MOUNT/redis"; : > "$WORKSPACES_MOUNT/.cache"; \
   mkdir -p "$WORKSPACES_STAGING/workspaces/u1" "$WORKSPACES_STAGING/redis"; : > "$WORKSPACES_STAGING/.cache"; \
   clean_stray; echo "REMAIN:[$(ls -A "$WORKSPACES_STAGING" 2>/dev/null | tr "\n" " ")]"' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
ran && ok "T4d clean_stray removes a provenance-established stray and returns 0" \
    || no "T4d clean_stray did not return 0 (rc=$CASE_RC ${CASE_OUT:0:300})"
outF 'REMAIN:[]' \
  && ok "T4d-b the removal is DOTFILE-INCLUSIVE (\$STAGING empty afterwards, .cache gone)" \
  || no "T4d-b \$STAGING is not empty after clean_stray — a dotfile survived and the guard still fires"
# POSITIVE CONTROL, and deliberately stronger than "an rm mentioning \$STAGING happened": it pins
# that EVERY top-level entry was passed to the observable seam in ONE call. A weaker presence-only
# assertion is satisfiable by an implementation that rm's a sentinel through the shell and does the
# bulk removal via `find -exec rm` (the real /bin/rm binary, invisible to the harness recorder) —
# which would silently restore vacuity to every negative assertion below.
has "^rm -rf -- .*$STG/workspaces" && has "^rm -rf -- .*$STG/.cache" \
  && ok "T4d-c POSITIVE CONTROL: every top-level entry went through the recorded shell rm" \
  || no "T4d-c the deletion did not pass all entries through the observable seam — every negative assertion below is VACUOUS"
markerF 'SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY' \
  && ok "T4d-d emits under its OWN marker name, not the STAGING_TARGET vocabulary" \
  || no "T4d-d no CLEAN_STRAY marker — the deletion has no operator-visible receipt"
markerF 'AP-009' \
  && ok "T4d-e the receipt names the AP-009 deviation" \
  || no "T4d-e the receipt does not name AP-009 — the deviation is not legible at run time"
markerF 'result=start reason=deleting' && markerF 'result=ok reason=cleaned' \
  && ok "T4d-f the pre-rm row is result=start, not a second result=ok (terminal vocabulary stays distinct)" \
  || no "T4d-f the pre-deletion receipt overloads result=ok — a failed run leaves a success-keyed row"

# T4e — $STAGING is a MOUNTPOINT: that is the real LUKS volume, not a root-disk stray.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_STAGING/workspaces"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && ok "T4e a MOUNTPOINT \$STAGING refuses (that is the real volume, not a stray)" \
     || no "T4e clean_stray did not refuse on a mountpoint \$STAGING — it would delete the LUKS volume"
nhas "^rm -rf .*$STG" \
  && ok "T4e-b no \$STAGING-scoped rm was issued on the mountpoint refusal" \
  || no "T4e-b an rm reached \$STAGING while it was a mountpoint — catastrophic"
outF 'EMIT_DRIFT: clean_stray_staging_is_mountpoint' \
  && ok "T4e-c the reason is clean_stray_staging_is_mountpoint" \
  || no "T4e-c no clean_stray_staging_is_mountpoint drift emitted"

# T4f — THE DEPTH TEST. Provenance falsified at depth 2: the stray holds workspaces/ORPHAN, a user
# tree canonical does not have. Note the depth-1 views are IDENTICAL (`workspaces` on both sides),
# so a -maxdepth 1 subset check PASSES this fixture and deletes a user's only copy. This case is
# the reason the check runs to $SUBSET_DEPTH.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1"; \
   mkdir -p "$WORKSPACES_STAGING/workspaces/u1" "$WORKSPACES_STAGING/workspaces/ORPHAN"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && ok "T4f a depth-2 entry absent from \$MOUNT refuses (provenance falsified where identity lives)" \
     || no "T4f clean_stray deleted a stray holding a user tree canonical does not have — the depth-1 blind spot"
nhas "^rm -rf .*$STG" \
  && ok "T4f-b no \$STAGING-scoped rm on the not-subset refusal" \
  || no "T4f-b an rm was issued despite the subset check failing"
outF 'EMIT_DRIFT: clean_stray_not_subset' \
  && ok "T4f-c the reason is clean_stray_not_subset" \
  || no "T4f-c no clean_stray_not_subset drift emitted"
markerF 'unique_count=1' \
  && ok "T4f-d the marker carries a COUNT, so per-user ids do not reach the drift channel" \
  || no "T4f-d the not-subset marker does not carry unique_count"
! markerF 'ORPHAN' \
  && ok "T4f-e the offending entry NAME is withheld from the marker (it is a user identifier)" \
  || no "T4f-e a per-user workspace id leaked into the marker channel"

# T4g — requirement 2 at the script layer: CLEAN_STRAY=1 must never ride the dry-run arm.
# It REFUSES rather than forcing DRY_RUN=0 the way ROLLBACK does — forcing is precisely what
# makes ROLLBACK's ungated arm dangerous.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_STAGING/workspaces"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=1 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && ok "T4g CLEAN_STRAY=1 with DRY_RUN=1 refuses (requirement 2, script layer)" \
     || no "T4g a dry-run dispatch reached the deletion path — requirement 2 is violated"
nhas "^rm -rf .*$STG" \
  && ok "T4g-b no \$STAGING-scoped rm on the dry-run refusal" \
  || no "T4g-b an rm was issued from the dry_run=true arm"
outF 'EMIT_DRIFT: clean_stray_dryrun_conflict' \
  && ok "T4g-c the reason is clean_stray_dryrun_conflict" \
  || no "T4g-c no clean_stray_dryrun_conflict drift emitted"

# T4h — mode mutual exclusion. The ROLLBACK block ends `exit 0`, so without this guard an
# operator who ticks BOTH gets a rollback (umount $MOUNT, cryptsetup close, docker stop) on a
# host where no freeze was held — a gratuitous outage — the run exits GREEN, and the stray is
# still there.
run_case "$CUTOVER" \
  'assert_mode_exclusive' \
  'assert_mode_exclusive' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 ROLLBACK=1
died && ok "T4h ROLLBACK=1 + CLEAN_STRAY=1 refuses" \
     || no "T4h both modes were accepted — the rollback would silently win and report green"
outF 'EMIT_DRIFT: clean_stray_mode_conflict' \
  && ok "T4h-b the reason is clean_stray_mode_conflict" \
  || no "T4h-b no clean_stray_mode_conflict drift emitted"
# A THIRD mode is already declared (CONFIRM_WIPE) and its block lands in the Phase-5 converge
# dispatch. A pairwise rollback-vs-clean_stray test would stop covering the invariant the moment
# that block exists, so the guard counts set modes and this case pins the count form.
run_case "$CUTOVER" \
  'assert_mode_exclusive' \
  'assert_mode_exclusive' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 CONFIRM_WIPE=1
died && ok "T4h-c CLEAN_STRAY=1 + CONFIRM_WIPE=1 also refuses (the guard counts modes, not one pair)" \
     || no "T4h-c a non-rollback mode pair slipped past the exclusion guard"
run_case "$CUTOVER" \
  'assert_mode_exclusive; echo SOLE_MODE_OK' \
  'assert_mode_exclusive' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1
outF 'SOLE_MODE_OK' \
  && ok "T4h-d POSITIVE CONTROL: exactly one mode is ACCEPTED (the guard is not refuse-everything)" \
  || no "T4h-d the exclusion guard refuses a single-mode dispatch — CLEAN_STRAY is unreachable"

# T4h-e/f — CALL-SITE ORDER. Every case above invokes the functions DIRECTLY; the harness's
# BASH_SOURCE guard means no test ever executes the main body, so the guard can be deleted from it,
# or moved BELOW the ROLLBACK block whose `exit 0` shadows everything after it, and every
# behavioral assertion above still passes. That mutation is verbatim the failure T4h describes.
# These assert the wiring against the file itself, which is the only reachable seam.
ame_ln=$(grep -n '^assert_mode_exclusive$' "$CUTOVER" | head -1 | cut -d: -f1)
rb_ln=$(grep -n '^if \[ "\$ROLLBACK" = "1" \]; then$' "$CUTOVER" | head -1 | cut -d: -f1)
cs_ln=$(grep -n '^if \[ "\$CLEAN_STRAY" = "1" \]; then$' "$CUTOVER" | head -1 | cut -d: -f1)
if [ -n "$ame_ln" ] && [ -n "$rb_ln" ] && [ -n "$cs_ln" ]; then
  [ "$ame_ln" -lt "$rb_ln" ] \
    && ok "T4h-e assert_mode_exclusive is CALLED, and above the ROLLBACK block whose exit 0 would shadow it" \
    || no "T4h-e assert_mode_exclusive is called at line $ame_ln, at/below the ROLLBACK block at $rb_ln — the guard is bypassed"
  [ "$cs_ln" -gt "$rb_ln" ] \
    && ok "T4h-f the CLEAN_STRAY mode block is wired into the main body" \
    || no "T4h-f could not locate the CLEAN_STRAY mode block after the ROLLBACK block"
else
  no "T4h-e/f could not locate the mode-block call sites (ame=$ame_ln rollback=$rb_ln clean_stray=$cs_ln) — the anchors drifted and this guard is blind"
fi

# T4i — $MOUNT and $STAGING on the SAME FILESYSTEM: deleting the "stray" would be deleting
# canonical. Compared via `stat -c %d` on the directories, because findmnt cannot answer this for
# a non-mountpoint (which the guard above has already guaranteed $STAGING is).
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1" "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" STAT_DEV_SAME=1 DU_SRC=4096
died && ok "T4i \$MOUNT and \$STAGING on the same filesystem refuses (that is canonical, not a stray)" \
     || no "T4i clean_stray would have deleted from the canonical filesystem"
nhas "^rm -rf .*$STG" \
  && ok "T4i-b no \$STAGING-scoped rm on the same-filesystem refusal" \
  || no "T4i-b an rm was issued against the canonical filesystem"
outF 'EMIT_DRIFT: clean_stray_same_device' \
  && ok "T4i-c the reason is clean_stray_same_device" \
  || no "T4i-c no clean_stray_same_device drift emitted"
# An unreadable device id must fail CLOSED: it is not proof the two are distinct.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1" "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" STAT_RC=1 DU_SRC=4096
died && nhas "^rm -rf .*$STG" \
  && ok "T4i-d an unreadable st_dev fails CLOSED (a failed probe is not proof of distinctness)" \
  || no "T4i-d a stat failure was treated as 'different filesystems' and the deletion proceeded"

# T4j — an ALREADY-EMPTY $STAGING is a SUCCESS, not a failure.
run_case "$CUTOVER" \
  'clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV"
ran && ok "T4j an already-empty \$STAGING returns 0 (idempotent re-dispatch, no false alarm)" \
    || no "T4j a re-dispatch over an already-clean \$STAGING failed (rc=$CASE_RC) — cries wolf"
markerF 'reason=already_clean' \
  && ok "T4j-b the no-op is NAMED already_clean, not silently indistinguishable from a deletion" \
  || no "T4j-b no already_clean marker — a no-op looks like a successful deletion"
nhas "^rm -rf .*$STG" \
  && ok "T4j-c no rm issued when there was nothing to remove" \
  || no "T4j-c an rm was issued against an empty \$STAGING"

# T4k — CANONICAL NOT MOUNTED. The single most consequential guard in the function: with $MOUNT
# unmounted the stray is no longer a duplicate, it is the ONLY copy. Deleting the guard left the
# whole suite green before this case existed.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 1" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && ok "T4k an UNMOUNTED \$MOUNT refuses — the stray may be the only copy left" \
     || no "T4k clean_stray deleted the stray while canonical was not mounted"
nhas "^rm -rf .*$STG" \
  && ok "T4k-b no rm was issued while canonical was unmounted" \
  || no "T4k-b the only surviving copy was deleted"
outF 'EMIT_DRIFT: clean_stray_mount_unhealthy' \
  && ok "T4k-c the reason is clean_stray_mount_unhealthy" \
  || no "T4k-c no clean_stray_mount_unhealthy drift emitted"

# T4l — $MOUNT mounted but its source is NOT a block device: an unverified mount is not proof the
# canonical copy exists.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="/not/a/block/device" DU_SRC=4096
died && nhas "^rm -rf .*$STG" \
  && ok "T4l a non-block-device \$MOUNT source refuses, with no rm" \
  || no "T4l an unverified mount was accepted as proof canonical exists"

# T4m — the removal FAILS. The receipt must say so rather than reporting a clean run.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1" "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" RM_RC=1 DU_SRC=4096
died && ok "T4m a failed rm refuses rather than reporting success" \
     || no "T4m the removal failed and the run still returned 0"
outF 'EMIT_DRIFT: clean_stray_rm_failed' \
  && ok "T4m-b the reason is clean_stray_rm_failed" \
  || no "T4m-b a failed removal emitted no named reason"
! markerF 'result=ok reason=cleaned' \
  && ok "T4m-c NO success receipt is emitted for a failed removal" \
  || no "T4m-c the permanent record claims 'cleaned' for a run whose rm failed"

# T4n — a SYMLINK $STAGING gets its own reason. `ls -A` follows a symlink and `find` does not, so
# without this the run enumerates nothing and dies blaming a partial removal — identically on
# every re-dispatch, sending the operator after a nonexistent rogue writer.
run_case "$CUTOVER" \
  'rmdir "$WORKSPACES_STAGING"; ln -s "$WORKSPACES_MOUNT" "$WORKSPACES_STAGING"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && ok "T4n a symlinked \$STAGING refuses" \
     || no "T4n a symlinked \$STAGING was accepted"
outF 'EMIT_DRIFT: clean_stray_staging_is_symlink' \
  && ok "T4n-b the reason names the SYMLINK, not a phantom partial removal" \
  || no "T4n-b a symlinked \$STAGING produced a misleading reason"

# T4o — a MISSING PROBE BINARY must refuse. `mountpoint -q` on an absent binary exits 127, so the
# catastrophic-mode `if` reads FALSE and the refusal silently does not fire. Running blind is the
# failure; refusing is correct.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_STAGING/workspaces/u1"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" TOOL_ABSENT=mountpoint DU_SRC=4096
died && nhas "^rm -rf .*$STG" \
  && ok "T4o an absent 'mountpoint' binary refuses instead of deleting with a blind guard" \
  || no "T4o clean_stray ran with a missing probe — the catastrophic-mode guard was inert"
outF 'EMIT_DRIFT: clean_stray_tool_missing' \
  && ok "T4o-b the reason is clean_stray_tool_missing" \
  || no "T4o-b a missing probe emitted no named reason"

# T4p — a mount BENEATH $STAGING. Every guard above tests $STAGING itself; rm -rf would descend
# through a nested bind-mount into live data and fail only the final rmdir with EBUSY.
run_case "$CUTOVER" \
  'mkdir -p "$WORKSPACES_MOUNT/workspaces/u1" "$WORKSPACES_STAGING/workspaces/u1"; \
   FINDMNT_TARGETS="$WORKSPACES_STAGING/workspaces"; clean_stray' \
  'clean_stray emit_clean_stray' \
  BLK="$BLKDEV" DRY_RUN=0 CLEAN_STRAY=1 MOUNTPOINT_RCS="1 0" \
  FINDMNT_MOUNT_SRC="$BLKDEV" DU_SRC=4096
died && nhas "^rm -rf .*$STG" \
  && ok "T4p a mount nested BENEATH \$STAGING refuses, with no rm" \
  || no "T4p rm -rf would have descended through a nested mount into live data"
outF 'EMIT_DRIFT: clean_stray_nested_mount' \
  && ok "T4p-b the reason is clean_stray_nested_mount" \
  || no "T4p-b a nested mount emitted no named reason"

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
# Tmk — the mkdir fail-closure. `mkdir -p "$STAGING"` is the FIRST thing prepare_staging_target
# does and it is what created /mnt/data-luks as a plain ROOT-DISK directory on 2026-07-19. A
# swallowed failure here means every later gate operates on a path that does not exist.
# ---------------------------------------------------------------------------
happy "$CUTOVER" MKDIR_RC=1
died && ok "Tmk a failed \`mkdir -p \$STAGING\` aborts the prepare" \
     || no "Tmk a failed mkdir was swallowed (rc=$CASE_RC) — every later gate targets a missing path"
outF 'EMIT_DRIFT: staging_mkdir_failed' && markerF 'reason=mkdir_failed' \
  && ok "Tmkb the reason is mkdir_failed on BOTH the drift and marker channels" \
  || no "Tmkb no mkdir_failed reason emitted"
if nhas '^mountpoint ' && nhas '^mkfs\.ext4 ' && nhas '^mount '; then
  ok "Tmkc the run stops immediately (no mountpoint probe, no mkfs, no mount)"
else
  no "Tmkc the run continued after a failed mkdir"
fi

# ---------------------------------------------------------------------------
# Tbk — A FAILED PROBE IS NOT PROOF OF AN EMPTY DEVICE. `blkid ... || true` collapsed every blkid
# failure (absent binary, rc 4 usage, rc 8 ambivalent, ENOENT, EACCES, EIO) into fs_type="", which
# takes the DESTRUCTIVE mkfs arm. Concrete loss: a prior run completed the hours-long bulk rsync
# and died later; a re-dispatch whose blkid fails then mkfs's over the complete good copy.
# ---------------------------------------------------------------------------
happy "$CUTOVER" BLKID_ABSENT=1
died && ok "Tbk1 an absent blkid aborts rather than mkfs-ing blind" \
     || no "Tbk1 blkid missing from PATH took the DESTRUCTIVE mkfs arm (rc=$CASE_RC)"
outF 'EMIT_DRIFT: staging_blkid_absent' && markerF 'reason=blkid_absent' \
  && ok "Tbk1b the reason is blkid_absent" \
  || no "Tbk1b no blkid_absent reason emitted"
nhas '^mkfs\.ext4 ' \
  && ok "Tbk1c NO mkfs runs when blkid is absent (an unprobed mapper is never formatted)" \
  || no "Tbk1c mkfs ran without any filesystem probe — this is the data-destroying arm"

happy "$CUTOVER" BLKID_RC=4
died && ok "Tbk2 a FAILED blkid probe (rc 4) aborts — a failed probe is not an empty device" \
     || no "Tbk2 a failed blkid probe was read as 'no filesystem' (rc=$CASE_RC) — mkfs over a good copy"
outF 'EMIT_DRIFT: staging_blkid_probe_failed' && markerF 'reason=blkid_probe_failed' \
  && ok "Tbk2b the reason is blkid_probe_failed" \
  || no "Tbk2b no blkid_probe_failed reason emitted"
nhas '^mkfs\.ext4 ' \
  && ok "Tbk2c NO mkfs runs after a failed probe" \
  || no "Tbk2c mkfs ran after a failed probe — the destructive arm is reachable from an error"
# Tbk2d — rc 2 ("nothing detected") is the ONLY empty that means "no filesystem", and it MUST
# still reach mkfs. Without this the guard could be satisfied by refusing every empty device,
# which would break the first cutover entirely.
happy "$CUTOVER" BLKID_RC=2 BLKID_FS=""
ran && has '^mkfs\.ext4 ' \
  && ok "Tbk2d rc 2 (nothing detected) still takes the mkfs arm — the first cutover is not broken" \
  || no "Tbk2d rc 2 no longer reaches mkfs (rc=$CASE_RC) — the guard broke the first-cutover path"

# ---------------------------------------------------------------------------
# Tmf — THE STAGING MOUNT FAIL-CLOSURE: the PR's headline behaviour. On 2026-07-19 the mapper held
# no filesystem, `mount "$MAPPER" "$STAGING"` failed with `wrong fs type`, and under `set -uo
# pipefail` with no `-e` that failure was SWALLOWED onto a root-disk directory.
#
# FINDMNT_STAGING_SRC is deliberately NOT pre-satisfied here. With the happy default the
# downstream mount-source control masks this gate entirely: replacing the fail-closure with
# `|| true` still dies (at source_not_mapper), so an rc-only assertion cannot see the difference.
# The REASON is therefore the load-bearing assertion, not the rc.
# ---------------------------------------------------------------------------
happy "$CUTOVER" MOUNT_RC=1 FINDMNT_STAGING_SRC=""
died && ok "Tmf a failed \`mount \$MAPPER \$STAGING\` aborts the prepare" \
     || no "Tmf a failed staging mount was swallowed (rc=$CASE_RC) — THE 2026-07-19 defect"
if outF 'EMIT_DRIFT: staging_mount_failed' && markerF 'reason=mount_failed'; then
  ok "Tmfb the reason is mount_failed, NOT the downstream source_not_mapper (the gate is distinguishable)"
else
  no "Tmfb a failed staging mount is not reported as mount_failed — the fail-closure is inert or masked"
fi
one_drift \
  && ok "Tmfc exactly one drift fires (the abort is not double-reported downstream)" \
  || no "Tmfc $(drift_n) drift markers fired — the run continued past the mount failure"
if nhas '^df ' && nhas '^du ' && ! markerF 'result=ok'; then
  ok "Tmfd the run does NOT reach the capacity probe and emits no result=ok"
else
  no "Tmfd the run continued past a failed staging mount — the copy target is unverified"
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

# T12c — the boundary. The gate requires usable > src + 5%, not a bare `avail > src`: ext4 writes
# metadata DURING the copy, so one byte of slack is not headroom. An exactly-equal target must
# still be refused, and it is the margin — not an off-by-one — that decides it.
happy "$CUTOVER" DU_SRC=4096 DF_AVAIL=4096
died && ok "T12c an exactly-equal avail/src is REFUSED (the 5% metadata margin, not a bare -gt)" \
     || no "T12c avail == src was accepted — ext4 metadata written during the copy guarantees ENOSPC"

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

# repoint_landed — did the LAST repoint_case actually execute the extracted block?
#
# THIS GATE IS LOAD-BEARING ON EVERY repoint ASSERTION, not just the mutations. When extraction
# misses, the old code set CASE_RC=98 and CALLS=/dev/null — which made `died()` TRUE (98 != 0) and
# `nhas` UNCONDITIONALLY true (nothing ever matches in /dev/null). T5/T5c/T6/T6c therefore all
# passed with the block never running: breaking only the extraction anchor, leaving SUT behaviour
# byte-identical, kept them green. CALLS now points at a real EMPTY temp file so `nhas` is a
# genuine observation of an empty call log rather than a structural tautology, and every case
# below gates on this predicate.
REPOINT_OK=0
repoint_landed() { [ "$REPOINT_OK" = "1" ]; }

repoint_case() {  # <script> [env...]
  local script="$1"; shift
  local blk; blk="$(extract_repoint "$script")"
  if [ -z "$blk" ]; then
    REPOINT_OK=0
    CASE_RC=98; CASE_OUT="REPOINT_EXTRACTION_MISSED"
    CALLS="$(mktemp -p "$RUN_SCRATCH" empty-calls.XXXXXX)"; : > "$CALLS"
    MARKER_LOG="$(mktemp -p "$RUN_SCRATCH" empty-marker.XXXXXX)"; : > "$MARKER_LOG"
    return
  fi
  REPOINT_OK=1
  # CRYPTSETUP_DEV is required by the C13 canary's mapper->device anchor, which now runs
  # `_same_dev "$_canary_mapper_dev" "$FRESH_DEV"`; without it the happy control dies there.
  run_case "$script" \
    'DRY_RUN=0; FRESH_DEV="$BLK"; MAPPER="$BLK"; FLIP_DONE=0; CANARY_OK=0; source "$REPOINT_BLOCK"' \
    'emit_drift persist_state' \
    BLK="$BLKDEV" REPOINT_BLOCK="$blk" CRYPTSETUP_DEV="$BLKDEV" "$@"
}

# MOUNTPOINT_RCS="1 0" is the STATE TRANSITION: after `umount "$MOUNT"` the repoint asserts $MOUNT
# is NOT a mountpoint (rc 1), and after `mount "$MAPPER" "$MOUNT"` the canary asserts it IS (rc 0).
# One global rc cannot express that, and without it neither T5/T6 nor their control is writable.
repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS"
if ! repoint_landed; then
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
if ! repoint_landed; then
  no "T5/T5b/T5c NOT RUN: repoint extraction missed — treat as un-run, not as evidence"
else
  died && ok "T5 a failed \`umount \$STAGING\` aborts the repoint" \
       || no "T5 a failed staging umount was swallowed (rc=$CASE_RC) — two live divergent copies"
  outF 'EMIT_DRIFT: staging_umount_failed' \
    && ok "T5b the reason is staging_umount_failed" \
    || no "T5b no staging_umount_failed drift emitted"
  nhas '^mount ' \
    && ok "T5c the abort happens BEFORE \`mount \$MAPPER \$MOUNT\` (the mapper is never stacked over plaintext)" \
    || no "T5c the mapper was mounted at \$MOUNT despite the failed staging umount"
fi

# T6 — a failed repoint mount must abort before the canary. The canary would otherwise run against
# whatever is still mounted at $MOUNT and certify it.
repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" BLKID_FS="crypto_LUKS" \
  MOUNT_RC=1
if ! repoint_landed; then
  no "T6/T6b/T6c NOT RUN: repoint extraction missed — treat as un-run, not as evidence"
else
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
  printf '#!/usr/bin/env bash\nprintf "cryptsetup %%s\\n" "$*" >> "$CALLS"\ncase "$*" in *luksFormat*) exit "${LUKSFORMAT_RC:-0}";; *luksOpen*) exit "${LUKSOPEN_RC:-0}";; esac\nexit 0\n' > "$d/bin/cryptsetup"
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

# Tlo — the luksOpen fail-closure, sibling of T15's luksFormat in the same hunk. Unguarded, a
# failed open leaves $MAPPER absent and prepare_staging_target then dies as staging_mapper_absent
# — a MISLEADING reason on the operator's only no-SSH channel. WORKSPACES_MAPPER_NAME is pointed
# at a name guaranteed absent so the call site's `[ ! -e "$MAPPER" ]` skip does not fire.
script_case "$CUTOVER" "$BLKDEV" DRY_RUN=0 ROLLBACK=0 WORKSPACES_LUKS_DEV="$BLKDEV" \
  WORKSPACES_MAPPER_NAME="wl-staging-test-absent" LUKSOPEN_RC=1
[ "$SCRIPT_RC" -ne 0 ] && ok "Tlo a failed luksOpen aborts the run" \
                       || no "Tlo a failed luksOpen did not abort (rc=$SCRIPT_RC)"
sout 'DRIFT reason=luksopen_failed' \
  && ok "Tlob the reason is luksopen_failed (not the misleading downstream mapper_absent)" \
  || no "Tlob no luksopen_failed drift emitted: ${SCRIPT_OUT:0:300}"
if grep -qE 'cryptsetup luksOpen' "$SCRIPT_CALLS" && ! grep -qF 'staging_mapper_absent' <<<"$SCRIPT_OUT"; then
  ok "Tloc luksOpen ran and the abort is NOT attributed to the absent mapper it caused"
else
  no "Tloc the failed open is reported one layer downstream — the operator chases the wrong failure"
fi

# ---------------------------------------------------------------------------
# Trb — rollback(). This is the RECOVERY path, where a swallowed failure matters MORE than on the
# forward path, and it was entirely unasserted: deleting either line below left both suites green.
#
# Trb1: `umount "$STAGING"` must happen BEFORE `cryptsetup close`. Without it a mapper still
# mounted at $STAGING makes the close fail EBUSY — and the old `2>/dev/null || true` swallowed
# that, so rollback remounted plaintext and reported SUCCESS while leaking the mapper open AND
# mounted, holding a full divergent copy.
# Trb2: the close failure must be REPORTED, not swallowed.
# ---------------------------------------------------------------------------
# MAPPER is bound to a real block device: the close is guarded on `[ -e "$MAPPER" ]`, so with the
# default /dev/mapper/workspaces (absent on any test host) the close never runs and Trb1b/Trb2
# would assert against a line that was never reached.
ROLLBACK_ENV=(BLK="$BLKDEV" ACTIVE_UNITS="inngest-server.service webhook.service inngest-redis.service")
ROLLBACK_INV='DRY_RUN=0; MAPPER="$BLK"; rollback'
run_case "$CUTOVER" "$ROLLBACK_INV" 'rollback resume_writers' "${ROLLBACK_ENV[@]}"
ran && ok "Trb0 rollback() completes on the happy recovery path (positive control)" \
    || no "Trb0 rollback() did not complete: rc=$CASE_RC ${CASE_OUT:0:300}"
has '^umount .*/staging$' \
  && ok "Trb1 rollback() umounts \$STAGING (without it the mapper close fails EBUSY)" \
  || no "Trb1 rollback() never umounts \$STAGING — the close fails EBUSY and the mapper leaks open+mounted"
u_stg="$(idx '^umount .*/staging$')"; c_cls="$(idx '^cryptsetup close')"
if [ -n "$u_stg" ] && [ -n "$c_cls" ] && [ "$u_stg" -lt "$c_cls" ]; then
  ok "Trb1b the \$STAGING umount PRECEDES the mapper close (ordering is the whole point)"
else
  no "Trb1b staging umount does not precede the close (umount=$u_stg close=$c_cls)"
fi
outF 'EMIT_DRIFT: rollback_mapper_close_failed' \
  && no "Trb1c a SUCCEEDING close reported a close failure — the drift is unconditional, not an oracle" \
  || ok "Trb1c a succeeding mapper close emits NO close-failure drift (negative control)"

run_case "$CUTOVER" "$ROLLBACK_INV" 'rollback resume_writers' "${ROLLBACK_ENV[@]}" CRYPTSETUP_CLOSE_RC=1
outF 'EMIT_DRIFT: rollback_mapper_close_failed' \
  && ok "Trb2 a FAILED mapper close is reported (no longer swallowed by \`2>/dev/null || true\`)" \
  || no "Trb2 the mapper close failure was swallowed — rollback reports SUCCESS while leaking the mapper"

# Trb3 — the close is guarded on mapper EXISTENCE. `cryptsetup close` on an already-inactive mapper
# exits non-zero, so an unguarded emit fires a FATAL drift on a second ROLLBACK=1 dispatch — the
# most likely operator action after a partial recovery — for a rollback that fully succeeded. A
# recovery-path signal that cries wolf gets ignored, so this negative oracle is load-bearing.
run_case "$CUTOVER" 'DRY_RUN=0; MAPPER="$WORKSPACES_STAGING/no-such-mapper"; rollback' \
  'rollback resume_writers' "${ROLLBACK_ENV[@]}" CRYPTSETUP_CLOSE_RC=1
if nhas '^cryptsetup close' && ! outF 'EMIT_DRIFT: rollback_mapper_close_failed'; then
  ok "Trb3 an ALREADY-CLOSED mapper is not closed again and emits no close-failure drift (no wolf-crying)"
else
  no "Trb3 a re-dispatched rollback pages FATAL for an already-successful close"
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
# TQ — THE QUANTIFIER. emit_staging_target is documented as firing "on EVERY outcome including
# success", but until now nothing quantified over that set: deleting the call from 9 of 13 arms
# left the suite at 72/1, and the single catch was incidental (an ordering assertion that merely
# needs SOME marker to exist).
#
# This block DERIVES the arm set from the SUT source and asserts (a) every derived arm is actually
# exercised by a case here, and (b) the CARDINALITY matches the number of producer call sites. (b)
# is what keeps the guard bounded: an arm the extraction cannot see would otherwise be silently
# exempt, and a new arm added to the SUT would be covered by nobody while this block stayed green.
# It is also the mechanism by which the two blkid arms added mid-review surfaced as uncovered.
#
# Comments are stripped before extraction: the prose above the function names these slugs too, and
# a body-grep that sees comments would credit coverage to documentation.
# ---------------------------------------------------------------------------
ARMS_SRC="$RUN_SCRATCH/arms-src"; ARMS_SEEN="$RUN_SCRATCH/arms-seen"
DRIFT_SRC="$RUN_SCRATCH/drift-src"; DRIFT_SEEN="$RUN_SCRATCH/drift-seen"
: > "$ARMS_SEEN"; : > "$DRIFT_SEEN"
TQ_DRIFT_BAD=""

# record_arm <label> <expected-drift-count> — fold the case just run into the coverage sets and
# check its drift cardinality. "exactly one drift per failure arm" is the oracle that catches a
# run which fired the right drift AND then continued to fire another.
record_arm() {
  grep -oE 'result=[a-z]+ reason=[a-z_]+' "$MARKER_LOG" >> "$ARMS_SEEN" 2>/dev/null || true
  awk '/^EMIT_DRIFT: /{sub(/^EMIT_DRIFT: /,""); print $1}' <<<"$CASE_OUT" >> "$DRIFT_SEEN"
  local n; n="$(drift_n)"
  [ "$n" = "$2" ] || TQ_DRIFT_BAD="$TQ_DRIFT_BAD $1(drift=$n want=$2)"
}

# One case per arm, run against the REAL script only (never a mutant — a mutant's markers would
# credit coverage the SUT does not actually have).
happy "$CUTOVER" MKDIR_RC=1                                     ; record_arm mkdir_failed 1
run_case "$CUTOVER" \
  'FRESH_DEV="$BLK"; MAPPER="$BLK"; : > "$WORKSPACES_STAGING/stray"; prepare_staging_target' \
  'prepare_staging_target' BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" \
  CRYPTSETUP_DEV="$BLKDEV" FINDMNT_STAGING_SRC="$BLKDEV" FINDMNT_MOUNT_SRC="" BLKID_FS="" \
  DU_SRC=1024 DF_AVAIL=999999999                                ; record_arm stray_present 1
happy "$CUTOVER" FINDMNT_MOUNT_SRC="$BLKDEV"                    ; record_arm already_cutover 1
stage_case "$CUTOVER" DRY_RUN=1 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" BLKID_FS="" \
                                                                ; record_arm dryrun 0
run_case "$CUTOVER" \
  'FRESH_DEV="$BLK"; MAPPER="$WORKSPACES_STAGING/no-such-mapper"; prepare_staging_target' \
  'prepare_staging_target' BLK="$BLKDEV" DRY_RUN=0 MOUNTPOINT_RCS="1 1" FINDMNT_MOUNT_SRC="" \
  BLKID_FS="" DU_SRC=1024 DF_AVAIL=999999999                    ; record_arm mapper_absent 1
happy "$CUTOVER" CRYPTSETUP_DEV="/dev/other"                    ; record_arm mapper_wrong_device 1
happy "$CUTOVER" BLKID_ABSENT=1                                 ; record_arm blkid_absent 1
happy "$CUTOVER" BLKID_RC=4                                     ; record_arm blkid_probe_failed 1
happy "$CUTOVER" MKFS_RC=1                                      ; record_arm mkfs_failed 1
happy "$CUTOVER" BLKID_FS="xfs"                                 ; record_arm unexpected_fs 1
happy "$CUTOVER" MOUNT_RC=1 FINDMNT_STAGING_SRC=""              ; record_arm mount_failed 1
happy "$CUTOVER" FINDMNT_STAGING_SRC=""                         ; record_arm source_not_mapper 1
happy "$CUTOVER" DU_SRC="garbage"                               ; record_arm capacity_unreadable 1
happy "$CUTOVER" DU_SRC=4096 DF_AVAIL=100                       ; record_arm insufficient_capacity 1
happy "$CUTOVER"                                                ; record_arm prepared 0
# staging_umount_failed lives in the repoint block, not in prepare_staging_target, so the drift
# set is only complete with it. Gated: an extraction miss must read as un-run, not as coverage.
if repoint_landed || true; then
  repoint_case "$CUTOVER" MOUNTPOINT_RCS="1 0" FINDMNT_MOUNT_SRC="$BLKDEV" \
    BLKID_FS="crypto_LUKS" UMOUNT_FAIL_MATCH="/staging"
  if repoint_landed; then record_arm staging_umount_failed 1; fi
fi

[ -z "$TQ_DRIFT_BAD" ] \
  && ok "TQ0 every arm emits EXACTLY the expected number of drift markers (fail arms 1, ok/dryrun 0)" \
  || no "TQ0 drift cardinality wrong for:$TQ_DRIFT_BAD"

# (a) Derive the producer set from source, comments stripped.
awk '!/^[[:space:]]*#/' "$CUTOVER" \
  | grep -oE 'emit_staging_target (ok|fail|dryrun) [a-z_]+' \
  | awk '{print "result="$2" reason="$3}' | sort -u > "$ARMS_SRC"
N_CALLSITES="$(awk '!/^[[:space:]]*#/' "$CUTOVER" | grep -cE 'emit_staging_target (ok|fail|dryrun) [a-z_]+' || true)"
N_DERIVED="$(wc -l < "$ARMS_SRC" | tr -d ' ')"
sort -u "$ARMS_SEEN" > "$ARMS_SEEN.u"

# TQ1a — THE PAIRING INVARIANT, and the reason this block is bounded without an arbitrary floor.
# Deleting a producer arm removes it from the DERIVED set and from the OBSERVED set at the same
# time, so a set-difference alone can never see it — the guard would shrink silently along with
# the SUT. Every fail arm in prepare_staging_target is paired with exactly one `emit_drift
# staging_*`, so counting the two INDEPENDENT producers against each other catches a deleted
# marker immediately: drift stays, the marker goes, the counts diverge.
PSTBODY="$RUN_SCRATCH/pst-body"
awk '/^prepare_staging_target\(\) \{$/,/^\}$/' "$CUTOVER" | awk '!/^[[:space:]]*#/' > "$PSTBODY"
N_FAIL_ARMS="$(grep -cE '^ *emit_staging_target fail ' "$PSTBODY" || true)"
N_FN_DRIFT="$(grep -cE '^ *emit_drift staging_' "$PSTBODY" || true)"
if [ "$N_FAIL_ARMS" -lt 5 ] || [ "$N_FN_DRIFT" -lt 5 ]; then
  no "TQ1a function-body extraction produced $N_FAIL_ARMS marker arms / $N_FN_DRIFT drift calls — the derivation itself broke; treat TQ as un-run"
elif [ "$N_FAIL_ARMS" = "$N_FN_DRIFT" ]; then
  ok "TQ1a every fail arm is paired 1:1 with a drift call ($N_FAIL_ARMS each) — no marker arm has been dropped"
else
  no "TQ1a marker/drift pairing broken: $N_FAIL_ARMS emit_staging_target fail arms vs $N_FN_DRIFT emit_drift staging_ calls — an outcome reports on one channel only"
fi

if [ "$N_DERIVED" -lt 10 ]; then
  no "TQ1 only $N_DERIVED arms derived — either the extraction regex broke or arms were deleted from the SUT (see TQ1a); treat TQ1/TQ2/TQ3 as un-run"
else
  MISSING="$(comm -23 "$ARMS_SRC" "$ARMS_SEEN.u" | tr '\n' ' ')"
  [ -z "$MISSING" ] \
    && ok "TQ1 all $N_DERIVED emit_staging_target arms are exercised by a case in this suite" \
    || no "TQ1 emit_staging_target arms with NO covering case: $MISSING"
  # (b) CARDINALITY. Without this a new arm sharing an existing result/reason pair, or an arm the
  # regex cannot see, is silently exempt and the guard is unbounded.
  [ "$N_CALLSITES" = "$N_DERIVED" ] \
    && ok "TQ2 producer call sites ($N_CALLSITES) == distinct arms ($N_DERIVED) — no arm is hidden behind a duplicate reason" \
    || no "TQ2 $N_CALLSITES call sites collapse into $N_DERIVED distinct reasons — at least one arm is unobservable"
  EXTRA="$(comm -13 "$ARMS_SRC" "$ARMS_SEEN.u" | tr '\n' ' ')"
  [ -z "$EXTRA" ] \
    && ok "TQ3 every observed marker corresponds to a real producer arm (no stale expectations)" \
    || no "TQ3 markers observed that no producer emits: $EXTRA"
fi

# Same quantifier over the drift channel. staging_* is the slug family this change owns.
awk '!/^[[:space:]]*#/' "$CUTOVER" | grep -oE 'emit_drift staging_[a-z_]+' \
  | awk '{print $2}' | sort -u > "$DRIFT_SRC"
sort -u "$DRIFT_SEEN" > "$DRIFT_SEEN.u"
N_DRIFT="$(wc -l < "$DRIFT_SRC" | tr -d ' ')"
if [ "$N_DRIFT" -lt 8 ]; then
  no "TQ4 drift extraction produced only $N_DRIFT slugs — the derivation broke; treat as un-run"
else
  D_MISSING="$(comm -23 "$DRIFT_SRC" "$DRIFT_SEEN.u" | tr '\n' ' ')"
  [ -z "$D_MISSING" ] \
    && ok "TQ4 all $N_DRIFT staging_* drift slugs are exercised by a case in this suite" \
    || no "TQ4 staging_* drift slugs with NO covering case: $D_MISSING"
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
MS5="$(mutate 's@^  \[ "\$_usable_b" -gt "\$_need_b" \] || {$@  [ 1 = 0 ] \&\& {@')"
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
  if ! repoint_landed; then
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
  if ! repoint_landed; then
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

# MS16 — DELETE the staging mount-source positive control outright. This is the guard for the
# actual incident.
#
# CORRECTION (an earlier version of this comment claimed this suite is merge-blocking while the
# loopback suite is advisory): NEITHER is merge-blocking. `infra/github/ruleset-ci-required.tf`
# lists neither `deploy-script-tests` nor `infra-validate-required`, so BOTH suites are advisory
# at PR time. The hard enforcement for this behaviour is the freeze-arm dispatch gate in
# workspaces-luks-cutover.yml, which executes the loopback suite before a real cutover may run.
# That does not make this mutation less load-bearing — an advisory suite that cannot fail is
# still the "gate that cannot fail" class #6588 exists to remove — but the reason is coverage
# quality, not a merge block this suite does not have.
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

# mutate_block <open-line-regex> <close-line-literal> <replacement-line> -> mutant path
# Multi-line fail-closures cannot be neutered with a single-line sed: replacing only the `|| {`
# leaves the closing `}` orphaned and the mutant fails to PARSE, which reads as "mutation did not
# land" rather than as evidence. This deletes the whole block and substitutes one line.
mutate_block() {
  local open="$1" close="$2" repl="$3" mut
  mut="$(mktemp -p "$RUN_SCRATCH" mut.XXXXXX.sh)"
  awk -v open="$open" -v close="$close" -v repl="$repl" '
    s==0 && $0 ~ open { s=1; print repl; next }
    s==1 { if ($0 == close) s=0; next }
    1
  ' "$CUTOVER" > "$mut"
  printf '%s\n' "$mut"
}

# MS17 (V1) — replace the staging mount fail-closure with `|| true`, the exact pre-fix shape. This
# is the PR's HEADLINE behaviour and it previously survived: the happy default pre-satisfied the
# downstream mount-source control, so the suite stayed fully green with the fail-closure gone.
MS17="$(mutate_block '^    mount "\$MAPPER" "\$STAGING" \|\| \{$' '    }' '    mount "$MAPPER" "$STAGING" || true')"
if grep -qF 'emit_staging_target fail mount_failed' "$MS17" || ! bash -n "$MS17" 2>/dev/null; then
  no "mutation MS17 did NOT land (closure still present, or the mutant no longer parses) — treat as un-run"
else
  happy "$MS17" MOUNT_RC=1 FINDMNT_STAGING_SRC=""
  if markerF 'reason=mount_failed'; then
    no "mutation MS17 did not flip Tmfb — the staging mount fail-closure can be DELETED and this suite stays green"
  else
    ok "mutation MS17 (staging mount || true): Tmfb flips (the headline fail-closure is load-bearing)"
  fi
fi

# MS18 (V2) — neuter the mkdir fail-closure.
MS18="$(mutate_block '^  mkdir -p "\$STAGING" \|\| \{$' '  }' '  mkdir -p "$STAGING" || true')"
if grep -qF 'emit_staging_target fail mkdir_failed' "$MS18" || ! bash -n "$MS18" 2>/dev/null; then
  no "mutation MS18 did NOT land — treat as un-run, not evidence"
else
  happy "$MS18" MKDIR_RC=1
  markerF 'reason=mkdir_failed' \
    && no "mutation MS18 did not flip Tmk — the mkdir fail-closure is unpinned" \
    || ok "mutation MS18 (mkdir || true): Tmk flips (the mkdir fail-closure is load-bearing)"
fi

# MS19 (V3) — delete `umount "$STAGING"` from rollback(): the mapper close then fails EBUSY.
MS19="$(mutate 's@^  umount "\$STAGING" 2>/dev/null \|\| true$@  : # MUTANT@')"
if grep -qF 'umount "$STAGING" 2>/dev/null || true' "$MS19"; then
  no "mutation MS19 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MS19" "$ROLLBACK_INV" 'rollback resume_writers' "${ROLLBACK_ENV[@]}"
  has '^umount .*/staging$' \
    && no "mutation MS19 did not flip Trb1 — the rollback staging umount is unpinned" \
    || ok "mutation MS19 (drop rollback staging umount): Trb1 flips (the close would fail EBUSY)"
fi

# MS20 (V4) — restore the SWALLOWING close, the shape that let rollback report SUCCESS while
# leaking the mapper open and mounted with a full divergent copy.
MS20="$(mutate 's@^    cryptsetup close "\$MAPPER_NAME" \|\| emit_drift rollback_mapper_close_failed$@    cryptsetup close "$MAPPER_NAME" 2>/dev/null || true@')"
if ! grep -qF 'cryptsetup close "$MAPPER_NAME" 2>/dev/null || true' "$MS20"; then
  no "mutation MS20 sed did NOT land — treat as un-run, not evidence"
else
  run_case "$MS20" "$ROLLBACK_INV" 'rollback resume_writers' "${ROLLBACK_ENV[@]}" CRYPTSETUP_CLOSE_RC=1
  outF 'EMIT_DRIFT: rollback_mapper_close_failed' \
    && no "mutation MS20 did not flip Trb2 — the close-failure report is unpinned" \
    || ok "mutation MS20 (swallow the mapper close): Trb2 flips (the EBUSY report is load-bearing)"
fi

# MS21 (V5) — swallow the luksOpen failure.
MS21="$(mutate 's@^    || { emit_drift luksopen_failed;.*$@    || true@')"
if grep -qF 'emit_drift luksopen_failed' "$MS21"; then
  no "mutation MS21 sed did NOT land — treat as un-run, not evidence"
else
  script_case "$MS21" "$BLKDEV" DRY_RUN=0 ROLLBACK=0 WORKSPACES_LUKS_DEV="$BLKDEV" \
    WORKSPACES_MAPPER_NAME="wl-staging-test-absent" LUKSOPEN_RC=1
  sout 'DRIFT reason=luksopen_failed' \
    && no "mutation MS21 did not flip Tlob — the luksOpen fail-closure is unpinned" \
    || ok "mutation MS21 (swallow the luksOpen failure): Tlob flips (the fail-closure is load-bearing)"
fi

# MS22 (V7) — strip emit_staging_target from every `fail` arm while LEAVING the drift calls and the
# die in place. This is the precise shape the quantifier exists to catch: the run still aborts and
# still emits drift, so every rc-based and drift-based assertion stays green, and only a test that
# quantifies over the MARKER arms can see it.
MS22="$(mutate 's@^\( *\)emit_staging_target fail @\1: # MUTANT @')"
if grep -qE '^ *emit_staging_target fail ' "$MS22"; then
  no "mutation MS22 sed did NOT land — treat as un-run, not evidence"
else
  happy "$MS22" MKFS_RC=1
  if markerF 'reason=mkfs_failed'; then
    no "mutation MS22 did not flip TQ1 — marker arms can be deleted wholesale and this suite stays green"
  elif outF 'EMIT_DRIFT: staging_mkfs_failed'; then
    ok "mutation MS22 (delete the fail-arm markers, keep drift+die): TQ1 flips (the quantifier is load-bearing)"
  else
    no "mutation MS22 removed more than the marker — the mutation is not the V7 shape"
  fi
fi

# ---------------------------------------------------------------------------
echo
echo "workspaces-luks-staging.test.sh: $pass passed, $fail failed"

# NON-DEGENERACY FLOOR. `fail -eq 0` alone is satisfied by a suite that runs NOTHING: deleting the
# entire T4d-T4p region left this file reporting "109 passed, 0 failed" and exiting 0, silently
# dropping every assertion that covers the user-data deletion. A suite whose whole purpose is
# refusing to pass vacuously must first prove it ran. Raise this floor when adding cases; if it
# ever exceeds the real count the failure is loud and one line to fix.
STAGING_MIN_ASSERTIONS=150
if [ "$pass" -lt "$STAGING_MIN_ASSERTIONS" ]; then
  echo "FAIL - only $pass assertions ran (floor $STAGING_MIN_ASSERTIONS) — cases were dropped or a case aborted early; a green run here would be vacuous"
  exit 1
fi
[ "$fail" -eq 0 ]
