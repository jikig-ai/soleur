#!/usr/bin/env bash
#
# Behavioral suite for workspaces-cutover.sh's ROLLBACK refusal once web-1's plaintext copy is gone
# (Guard 5, #6604 step 7, ADR-119 addendum), and for the retired CONFIRM_WIPE tombstone (Guard B1,
# #6604 PR B).
#
# HISTORY. This file was workspaces-luks-wipe.test.sh, the suite of the single-use CONFIRM_WIPE /
# wipe_plaintext() mode that zeroed web-1's retained plaintext /workspaces volume. PR B deleted that
# mode (the procedure as run is in git history at 59abf6a76c) and kept here, renamed, the rows that
# guard what must outlive it:
#   Guard B1 — a stray CONFIRM_WIPE (any value but unset or `0`) is refused by the tombstone in the
#     main body: exactly one outcome=wipe_retired row, no drift event, rc != 0, never the L3 cutover
#     body. A cleanup() abort carries no `mode=` field any more.
#   Guard 5 (plan Guard B2) — once a PLAINTEXT_WIPE_BEGUN/PLAINTEXT_WIPED marker is persisted, or
#     /mnt/data is on the LUKS mapper and the recorded PLAINTEXT_DEV is not an intact ext4, no ROLLBACK
#     run, cleanup() rollback or dead-man fire unmounts the mapper: it holds the ONLY copy of every
#     workspace. Rows G5-W (the PLAINTEXT_DEV writer), F6, F7, F11, S5, S6, G5, G5b-*, G5c, G5d-*.
#     Loopback Session G5 (workspaces-luks-loopback.test.sh) holds the real-device rows.
#
# HARNESS. Counters, reporters, the floor, run_case and the file-direct predicates come from
# workspaces-luks-harness.sh. Every verdict greps a FILE or a herestring, never a pipe.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUTOVER="$SCRIPT_DIR/workspaces-cutover.sh"

# shellcheck source=apps/web-platform/infra/workspaces-luks-harness.sh
. "$SCRIPT_DIR/workspaces-luks-harness.sh"
harness_selftest workspaces-luks-rollback-refusal.test.sh

# The mode flags are read from the environment: a value the caller happens to export must not reach a
# case that did not ask for it (Guard B1's H1 row means "unset", so it must BE unset).
unset CONFIRM_WIPE ROLLBACK CLEAN_STRAY ROLLBACK_ACK_LUKS_WRITES DRY_RUN

PIN=105149570   # the retired plaintext volume id, as the PLAINTEXT_WIPE_* markers name it
DM='SOLEUR_WORKSPACES_LUKS_DEADMAN feature=workspaces-luks op=workspaces-luks-deadman'

# G5d bakes a REAL block device path into the dead-man fire it executes (its stubs answer every
# command, but `[ -b ]` in the arm is a builtin).
TGT_BLK="$(harness_blockdev)" || { printf 'INSTRUMENT FAIL - no block device on this host; the G5d fire rows cannot be reached\n'; exit 2; }
# The stubs cover COMMANDS, not shell redirections: a `> "$dev"` in the SUT (or in a mutant of it) would
# reach the real device. So the suite refuses to run with write access to it — root, or a `disk` group
# member — rather than trusting the stubs alone.
if [ "$(id -u)" = 0 ] || [ -w "$TGT_BLK" ]; then
  printf 'INSTRUMENT FAIL - this suite hands a REAL block device (%s) to the SUT and must not be able to write it: run it as an unprivileged user outside the disk group\n' "$TGT_BLK"
  exit 2
fi

# assert_fixture_dir — the canonical body from plugins/soleur/test/test-helpers.sh, copied BYTE-FOR-BYTE
# (fixture-dir-operand-assert.test.sh pins inline copies to it): a path this suite writes must be
# absolute, free of `..`, and neither a synthetic filesystem nor the root, else exit 2.
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

# Every path below hangs off ONE absolute mktemp root. The harness owns the EXIT trap (this suite must
# not REPLACE it, #6713), so its trap FUNCTION is extended to remove this root too.
RR_SCRATCH="$(mktemp -d -t wl-rr.XXXXXXXX)" || { printf 'INSTRUMENT FAIL - mktemp -d failed\n'; exit 2; }
eval "_wl_harness_cleanup_scratch() $(declare -f cleanup_scratch | tail -n +2)"
cleanup_scratch() { rm -rf "$RR_SCRATCH"; _wl_harness_cleanup_scratch; }

# ============================================================================
# Guard B1 — a retired CONFIRM_WIPE never wipes and never falls through (#6604 PR B)
# ============================================================================
# Assembly: the REAL main-body prefix between `trap cleanup EXIT` and `step "L3 gates` (extracted, never
# copied): assert_mode_exclusive (it counts CONFIRM_WIPE by the string "1" only, it does not validate),
# the ROLLBACK block, the CLEAN_STRAY block, the tombstone. A case that gets past all four prints
# FELL_THROUGH_TO_L3: the L3 cutover body would run next.
MAIN_PREFIX="$(awk '/^trap cleanup EXIT$/{f=1} /^step "L3 gates/{exit} f{print}' "$CUTOVER")"
# B1-H2 (instrument) — an empty or unparseable extraction would make every row below vacuous.
if [ -n "$MAIN_PREFIX" ] && [ "$(head -n1 <<<"$MAIN_PREFIX")" = 'trap cleanup EXIT' ] \
  && grep -qE '^assert_mode_exclusive$' <<<"$MAIN_PREFIX" && bash -n <<<"$MAIN_PREFIX" 2>/dev/null; then
  ok "B1-H2 the main-body prefix (trap cleanup EXIT .. the L3 gates) is extracted, calls assert_mode_exclusive and parses"
else
  no "B1-H2 INSTRUMENT: the main-body prefix could not be extracted or does not parse — treat every B1 row as UN-RUN"
fi
b1_case() {  # [env...] — the real prefix, then the line the L3 body would follow
  run_case "$CUTOVER" 'eval "$MAIN_PREFIX"; echo FELL_THROUGH_TO_L3' 'cleanup assert_mode_exclusive' MAIN_PREFIX="$MAIN_PREFIX" "$@"
}
# b1_retired — the whole refusal contract: rc != 0 through die, never the L3 body, EXACTLY one
# cutover_aborted row and it is the tombstone's (a second one means the EXIT trap was not dropped), no
# drift event (a stray value must not restart the #6604 sweeper's window), and nothing touched.
b1_retired() {
  died && outF 'CONFIRM_WIPE is retired' && ! outF FELL_THROUGH_TO_L3 \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && grep -qE -- "-- ${DM} result=cutover_aborted outcome=wipe_retired\$" "$MARKER_LOG" \
    && nhas '^EMIT_DRIFT' && nhas '^(umount|mount|cryptsetup|docker|systemctl|systemd-run|blkid|dd|blkdiscard) '
}
b1_dump() {
  printf 'rc=%s rows=[%s] drift=[%s] out=[%s]' "$CASE_RC" "$(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')" \
    "$(grep -E '^EMIT_DRIFT' "$CALLS" | tr '\n' '|')" "$(tr '\n' '|' <<<"${CASE_OUT:0:240}")"
}
# B1 rows 1, 2, 4, 5: the two shapes the deleted workflow could deliver (the DRY_RUN=0 row is the second
# member: a tombstone gated on DRY_RUN=1 falls through on it).
for b1v in 'DRY_RUN=1|CONFIRM_WIPE=1 with DRY_RUN=1 (the old rehearsal shape)' \
           'DRY_RUN=0|CONFIRM_WIPE=1 with DRY_RUN=0 (the old destructive shape)'; do
  b1_case CONFIRM_WIPE=1 "${b1v%%|*}"
  b1_retired && ok "B1 ${b1v#*|} is refused by the tombstone: one outcome=wipe_retired row, no drift, rc!=0, never the L3 body" \
    || no "B1 ${b1v#*|} was not refused by the tombstone: $(b1_dump)"
done
# B1 row 6: values assert_mode_exclusive does not count (it compares to the string "1") must still be
# refused, never ignored — a tombstone testing `= "1"` lets them fall through to L3.
for b1v in true ' 1'; do
  b1_case "CONFIRM_WIPE=$b1v" DRY_RUN=0
  b1_retired && ok "B1 CONFIRM_WIPE='$b1v' (not counted by assert_mode_exclusive) is refused by the tombstone, never ignored" \
    || no "B1 CONFIRM_WIPE='$b1v' fell through or was mis-recorded: $(b1_dump)"
done
# B1-H1 (must-PASS) — the tombstone is not refuse-everything: unset, or an explicit 0, reaches L3.
b1_case DRY_RUN=1
outF FELL_THROUGH_TO_L3 && ! markerF 'outcome=wipe_retired' && ! outF 'CONFIRM_WIPE is retired' \
  && ok "B1-H1 CONFIRM_WIPE unset passes the tombstone and reaches the L3 body" \
  || no "B1-H1 CONFIRM_WIPE unset did not reach the L3 body: $(b1_dump)"
b1_case CONFIRM_WIPE=0 DRY_RUN=1
outF FELL_THROUGH_TO_L3 && ! markerF 'outcome=wipe_retired' \
  && ok "B1-H1b CONFIRM_WIPE=0 passes the tombstone and reaches the L3 body" \
  || no "B1-H1b CONFIRM_WIPE=0 did not reach the L3 body: $(b1_dump)"
# B1-X — a mixed dispatch is refused by assert_mode_exclusive FIRST (it still counts CONFIRM_WIPE):
# the mode-conflict slug, no tombstone row, nothing rolled back.
b1_case CONFIRM_WIPE=1 ROLLBACK=1 DRY_RUN=0
died && has '^EMIT_DRIFT clean_stray_mode_conflict$' && ! markerF 'outcome=wipe_retired' && nhas '^(umount|cryptsetup|docker) ' \
  && ok "B1-X CONFIRM_WIPE=1 with ROLLBACK=1 is refused by assert_mode_exclusive before either block (no wipe_retired row, nothing rolled back)" \
  || no "B1-X a CONFIRM_WIPE+ROLLBACK dispatch was not refused by the mode exclusion: $(b1_dump)"
# B1-C — cleanup() lost its CONFIRM_WIPE arm with the mode: an abort through it (here with a stray
# CONFIRM_WIPE=1, e.g. the mode-conflict die above) records exactly ONE outcome row with no `mode=`
# field and pages nothing. Under `set -u` a dangling ${mode} would kill the EXIT trap and lose the row.
for b1c in '1|dry_run' '0|pre_freeze'; do
  run_case "$CUTOVER" 'trap cleanup EXIT; die "synthetic pre-freeze abort"' 'cleanup' CONFIRM_WIPE=1 "DRY_RUN=${b1c%%|*}"
  died && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && grep -qE -- "-- ${DM} result=cutover_aborted outcome=${b1c#*|}\$" "$MARKER_LOG" && ! markerF 'mode=' && nhas '^EMIT_DRIFT' \
    && ok "B1-C a cleanup() abort (DRY_RUN=${b1c%%|*}, stray CONFIRM_WIPE=1) emits exactly one outcome=${b1c#*|} row with no mode= field and no drift" \
    || no "B1-C the cleanup() abort row is wrong (DRY_RUN=${b1c%%|*}, want one outcome=${b1c#*|} row, no mode=): $(b1_dump)"
done
# B1-S — no code path can zero, detach or delete a volume any more (plan P3): the sourced script defines
# none of the retired wipe functions (positive control: a kept Guard-5 function IS defined, so an empty
# answer cannot come from a failed source), and its comment-stripped body names no blkdiscard.
b1_fns="$(bash -c 'source "$1" >/dev/null 2>&1
  for f in wipe_plaintext emit_wipe emit_wipe_evidence _wipe_refuse _wipe_shred_hdrs _wipe_assert_no_dependents \
           _wipe_readback _wipe_dev_path _wipe_sysfs_block _wipe_cgroup_root _wipe_frozen_at_epoch _wv _plaintext_record_status; do
    declare -F "$f"
  done' _ "$CUTOVER" 2>/dev/null)"
b1_bd="$(grep -cE '(^|[^A-Za-z0-9_-])blkdiscard([^A-Za-z0-9_-]|$)' <<<"$(grep -vE '^[[:space:]]*#' "$CUTOVER")" || true)"
[ "$b1_fns" = "_plaintext_record_status" ] && [ "$b1_bd" -eq 0 ] \
  && ok "B1-S the script defines no retired wipe function (wipe_plaintext, emit_wipe, _wipe_*, _wv) and invokes no blkdiscard" \
  || no "B1-S retired wipe code survives (declared=[$(tr '\n' ' ' <<<"$b1_fns")] want only _plaintext_record_status; blkdiscard lines=$b1_bd)"
# B1-O — the plan's Observability discoverability probe: the tombstone row literal exists exactly once.
b1_disc="$(grep -c -e 'result=cutover_aborted outcome=wipe_retired"' "$CUTOVER" || true)"
[ "$b1_disc" -eq 1 ] && ok "B1-O the tombstone's outcome=wipe_retired row literal exists exactly once (the discoverability probe)" \
  || no "B1-O the tombstone row literal count is $b1_disc (want 1)"

# ============================================================================
# Guard 5 (plan Guard B2) — the record writer and the static rows
# ============================================================================
# G5-W (writer -> reader; was G1-W) — the ONE writer of the record Guard 5's physical witness, the arm
# and rollback()'s remount all read is the cutover's rollback-rehearsal step: it persists
# `findmnt -no SOURCE $MOUNT` (the plaintext's mount source, pre-repoint). Run the REAL block (extracted,
# not copied) in the harness world with no seeded record: the LAST state line must be that mount source,
# and read_state (the readers' accessor) must return it.
REH_TEXT="$(awk '/^step "rollback rehearsal/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
if [ -z "$REH_TEXT" ] || ! grep -qF 'persist_state PLAINTEXT_DEV' <<<"$REH_TEXT"; then
  no "G5-W INSTRUMENT: the rollback-rehearsal block (the PLAINTEXT_DEV writer) could not be extracted"
else
  run_case "$CUTOVER" 'DRY_RUN=0; eval "$REH_TEXT"; echo "READ=$(read_state PLAINTEXT_DEV)"' 'persist_state read_state' \
    REH_TEXT="$REH_TEXT" PLAINTEXT_DEV_UNSEEDED=1 FINDMNT_MOUNT_SRC=/dev/sdzX MKDIR_RC=0
  if ran && [ "$(tail -n1 "$STATE/state" 2>/dev/null)" = "PLAINTEXT_DEV=/dev/sdzX" ] && outF "READ=/dev/sdzX" \
    && [ "$(grep -c '^PLAINTEXT_DEV=' "$STATE/state" 2>/dev/null)" -eq 1 ]; then
    ok "G5-W the rollback-rehearsal step persists the plaintext mount source as the LAST PLAINTEXT_DEV line, and read_state returns it"
  else
    no "G5-W the writer did not record the mount source (rc=$CASE_RC last=[$(tail -n1 "$STATE/state" 2>/dev/null)]) ${CASE_OUT:0:200}"
  fi
fi
# S5 (re-scoped to the two _plaintext_* seams the wipe's removal left) — the seams are not settable from
# the environment (an .env line could otherwise pick the blkid a root dead-man fire execs, or answer the
# physical probe). A one-line seam ends on its own line; a multi-line one at `^}$`. The only variables a
# seam may read are its argument and its declared local `b`.
SEAM_RE='^(_plaintext_blkid_bin|_plaintext_dev_type)\(\) '
seam_env="$(awk -v re="$SEAM_RE" '$0 ~ re {f=1} f{print} f && (/^\}$/ || /\(\) \{.*\}$/){f=0}' "$CUTOVER" | grep -vE '^[[:space:]]*#' | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | grep -vE '^\$\{?b$' || true)"
seam_n="$(grep -cE "$SEAM_RE" "$CUTOVER" || true)"
[ "$seam_n" -eq 2 ] && [ -z "$seam_env" ] \
  && ok "S5 the blkid-path and plaintext-type seams read no variable but their own argument (not env-settable)" \
  || no "S5 a seam reads an environment variable or is missing (defs=$seam_n want 2, vars=[$seam_env])"
# F6 — the REAL probe functions (never the harness seams): only the blkid PATH seam is replaced, by a
# stub that records its argv and exits with a chosen rc. The rc is kept (rc 0 → the TYPE, or `none` when
# empty; rc 2 → `none`; anything else → `blkid_error_<rc>`), the argv is exactly `-p -s TYPE -o value
# <dev>`, a missing blkid reads `blkid_absent`, and a node that is not a block device reads `absent`
# (both through _plaintext_dev_type and through the composed _plaintext_record_status).
F6_BLKID="$RR_SCRATCH/f6-blkid"; F6_ARGV="$RR_SCRATCH/f6-argv"
cat > "$F6_BLKID" <<'F6_STUB'
#!/bin/sh
printf '%s\n' "$*" > "$F6_ARGV"
[ -z "$F6_OUT" ] || printf '%s\n' "$F6_OUT"
exit "$F6_RC"
F6_STUB
chmod +x "$F6_BLKID"
f6() {  # <fn> <arg> <stub stdout> <stub rc> [bin override: '' = the stub, - = none]
  : > "$F6_ARGV"
  env -u PLAINTEXT_DEV_FSTYPE F6_ARGV="$F6_ARGV" F6_OUT="$3" F6_RC="$4" F6_BIN="${5:-$F6_BLKID}" F6_FN="$1" F6_ARG="$2" \
    bash -c 'source "$1" >/dev/null 2>&1
      _plaintext_blkid_bin() { [ "$F6_BIN" = - ] || printf "%s" "$F6_BIN"; }
      "$F6_FN" "$F6_ARG"' _ "$CUTOVER" 2>/dev/null
}
f6_bad=""
for f6c in "ext4|0|ext4" "|2|none" "|0|none" "|4|blkid_error_4" "crypto_LUKS|0|crypto_LUKS" "|8|blkid_error_8"; do
  IFS='|' read -r f6_out f6_rc f6_want <<<"$f6c"
  f6_got="$(f6 _plaintext_blkid_type /dev/sdz9 "$f6_out" "$f6_rc")"
  [ "$f6_got" = "$f6_want" ] && [ "$(cat "$F6_ARGV")" = "-p -s TYPE -o value /dev/sdz9" ] \
    || f6_bad="$f6_bad [out=${f6_out:-empty} rc=$f6_rc got=$f6_got want=$f6_want argv=$(cat "$F6_ARGV")]"
done
f6_got="$(f6 _plaintext_blkid_type /dev/sdz9 ext4 0 -)"; [ "$f6_got" = blkid_absent ] || f6_bad="$f6_bad [no-bin got=$f6_got]"
f6_file="$RR_SCRATCH/f6-regular"; : > "$f6_file"
for f6a in /dev/null "$f6_file" /dev/sdz_no_such_node; do
  f6_got="$(f6 _plaintext_dev_type "$f6a" ext4 0)"; [ "$f6_got" = absent ] && [ ! -s "$F6_ARGV" ] || f6_bad="$f6_bad [dev_type $f6a got=$f6_got]"
done
f6_got="$(f6 _plaintext_record_status /dev/null ext4 0)"; [ "$f6_got" = absent ] || f6_bad="$f6_bad [status /dev/null got=$f6_got]"
f6_got="$(f6 _plaintext_record_status '/dev/sdz9;x' ext4 0)"; [ "$f6_got" = invalid ] || f6_bad="$f6_bad [status invalid got=$f6_got]"
[ -z "$f6_bad" ] \
  && ok "F6 the real blkid probe keeps the rc (TYPE / none / blkid_error_<rc> / blkid_absent) with argv '-p -s TYPE -o value <dev>', and a non-block node reads absent without running blkid" \
  || no "F6 the real probe mapping is wrong:$f6_bad"
# F7 — the real _plaintext_blkid_bin in a clean shell with a FAKE blkid first on PATH: it must answer a
# fixed root-owned path, never the PATH hit (the fire bakes this path into an unattended root command).
F7_DIR="$RR_SCRATCH/f7-path"; mkdir -p "$F7_DIR"; printf '#!/bin/sh\nexit 0\n' > "$F7_DIR/blkid"; chmod +x "$F7_DIR/blkid"
f7_got="$(env PATH="$F7_DIR:$PATH" bash -c 'source "$1" >/dev/null 2>&1; blkid() { :; }; _plaintext_blkid_bin' _ "$CUTOVER" 2>/dev/null)"
[[ "$f7_got" =~ ^(/usr/sbin|/sbin|/usr/bin|/bin)/blkid$ ]] \
  && ok "F7 _plaintext_blkid_bin answers a fixed root-owned path ($f7_got), not a PATH-first fake or a shell function" \
  || no "F7 _plaintext_blkid_bin answered [$f7_got] (want one of /usr/sbin|/sbin|/usr/bin|/bin + /blkid; this host has: $(ls /usr/sbin/blkid /sbin/blkid /usr/bin/blkid /bin/blkid 2>/dev/null | tr '\n' ' '))"
# F11 — the main body records the plaintext mount source BEFORE it arms the dead-man (the arm refuses
# without a record, and the fire bakes it).
f11_rec="$(grep -n 'persist_state PLAINTEXT_DEV' "$CUTOVER" | head -1 | cut -d: -f1)"; f11_arm="$(grep -n '^arm_dead_man$' "$CUTOVER" | head -1 | cut -d: -f1)"
[ -n "$f11_rec" ] && [ -n "$f11_arm" ] && [ "$f11_rec" -lt "$f11_arm" ] \
  && ok "F11 the main body persists PLAINTEXT_DEV (line $f11_rec) before it arms the dead-man (line $f11_arm)" \
  || no "F11 PLAINTEXT_DEV is not persisted before the main-body arm (record line=${f11_rec:-none} arm line=${f11_arm:-none})"
# S6 — arm_dead_man reachability: no dispatch can reach arm_dead_man on a post-cutover host, because the
# main body runs prepare_staging_target (which refuses staging_already_cutover when $MOUNT is the mapper)
# BEFORE arm_dead_man. That is why arm_dead_man carries no wipe-marker refusal of its own (the FIRE does,
# G5d); this row pins the premise it rests on.
MAIN_BODY="$(awk '/^trap cleanup EXIT$/{f=1} f{print}' "$CUTOVER")"
pst_ln="$(grep -nE '^prepare_staging_target$' <<<"$MAIN_BODY" | head -1 | cut -d: -f1)"
adm_ln="$(grep -nE '^arm_dead_man$' <<<"$MAIN_BODY" | head -1 | cut -d: -f1)"
[ -n "$pst_ln" ] && [ -n "$adm_ln" ] && [ "$pst_ln" -lt "$adm_ln" ] && grep -qF 'emit_drift staging_already_cutover' "$CUTOVER" \
  && ok "S6 arm_dead_man is unreachable on a cut-over host: prepare_staging_target (already_cutover refusal) runs first" \
  || no "S6 arm_dead_man may be reachable post-cutover (prepare=$pst_ln arm=$adm_ln) — add the plaintext-wiped refusal there"

# ============================================================================
# Guard 5 — nothing remounts a wiped volume (ROLLBACK refusal), via the harness's rollback world
# ============================================================================
RB_TEXT="$(awk '/^if \[ "\$ROLLBACK" = "1" \]; then$/{f=1} f{print} f && /^fi$/{exit}' "$CUTOVER")"
T_MAPPER="$(env -u WORKSPACES_MAPPER_NAME bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "$MAPPER"' _ "$CUTOVER")"
G5_ACT="inngest-server.service webhook.service inngest-redis.service"
g5_case() {  # <seed lines> [env...]
  local seed="$1"; shift
  run_case "$CUTOVER" "$seed trap cleanup EXIT; eval \"\$RB_TEXT\"" 'rollback cleanup assert_rollback_not_post_cutover' \
    ROLLBACK=1 RB_TEXT="$RB_TEXT" ACTIVE_UNITS="$G5_ACT" CRYPTSETUP_DEV=/dev/sdz7 "$@"
}
g5_refused() {  # [drift slug] [outcome] — default: the marker refusal (a wipe began)
  local slug="${1:-rollback_refused_plaintext_wiped}" oc="${2:-refused_plaintext_wiped}"
  died && has "^EMIT_DRIFT ${slug}\$" \
    && markerF "$DM result=cutover_aborted outcome=${oc} mode=rollback" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && nhas '^umount[[:space:]]' && nhas '^docker stop' && nhas '^cryptsetup close'
}
g5_case "persist_state PLAINTEXT_WIPE_BEGUN '$PIN:1';" FINDMNT_MOUNT_SRC=/dev/sdz9 ROLLBACK_ACK_LUKS_WRITES=1
g5_refused && ok "G5 #1/#2 a BEGUN-only state refuses ROLLBACK=1 even with ROLLBACK_ACK_LUKS_WRITES=1 — before any umount/close/stop" \
  || no "G5 BEGUN-only ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:200}"
g5_case "persist_state PLAINTEXT_WIPED '$PIN:1'; persist_state CANARY_OK 1:u-live-1;" FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=u-live-1
g5_refused && outF "rollback_ack_luks_writes does not override this" && outF "a plaintext wipe began" \
  && grep -qE "outcome=refused_plaintext_wiped mode=rollback why=marker\$" "$MARKER_LOG" && ! markerF 'recorded=' \
  && ok "G5 a WIPED completed cutover refuses ROLLBACK=1 as refused_plaintext_wiped (why=marker, no recorded= fields: the marker arm never probed the record) FIRST, never as post_cutover (#4: never a false pre_freeze)" \
  || no "G5 WIPED ROLLBACK not refused (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" FINDMNT_MOUNT_SRC=/dev/sdz9 CRYPTSETUP_UUID=u-live-1
ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
  && ok "G5 H1 a ROLLBACK with no wipe markers behaves exactly as before (runs, not refused)" \
  || no "G5 H1 an unmarked ROLLBACK was refused or failed (rc=$CASE_RC) ${CASE_OUT:0:200}"
# G5b — the PHYSICAL check, independent of the wipe markers: /mnt/data on the mapper and the RECORDED
# plaintext device (PLAINTEXT_DEV, the device rollback() remounts) not an intact ext4 means there is no
# copy to remount, ack or not. Device-based: nothing here depends on a /dev/disk/by-label link. Each
# refusal must say WHICH (why=) and what the record read (recorded=/recorded_status=), in the run log and
# on the off-host outcome row, under its OWN slug (rollback_refused_plaintext_record_gone): no marker
# exists, so this is never a wipe — the sentence says so.
g5b_refused() {  # <recorded> <recorded_status>
  g5_refused rollback_refused_plaintext_record_gone refused_plaintext_record_gone && outF "(plaintext_dev_gone)" \
    && outF "recorded_status=$2" && outF "NOT a wipe" && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
    && markerF "$DM result=cutover_aborted outcome=refused_plaintext_record_gone mode=rollback why=plaintext_dev_gone recorded=$1 recorded_status=$2"
}
G5B_ENV=(FINDMNT_MOUNT_SRC="$T_MAPPER" CRYPTSETUP_UUID=u-live-1 ROLLBACK_ACK_LUKS_WRITES=1)
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=
g5b_refused /dev/sdz9 none && ok "G5b-R1 mapper mounted + the recorded plaintext reads no filesystem signature → refused before any umount, why=plaintext_dev_gone recorded_status=none" \
  || no "G5b-R1 a zeroed recorded plaintext did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') ${CASE_OUT:0:240}"
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=crypto_LUKS
g5b_refused /dev/sdz9 crypto_LUKS && ok "G5b-D the record names a crypto_LUKS device (a stale record, drift) → refused, recorded_status=crypto_LUKS tells drift from a wipe" \
  || no "G5b-D a drifted record did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" "${G5B_ENV[@]}" BLKID_ABSENT=1
g5b_refused /dev/sdz9 blkid_absent && ok "G5b-B no blkid at a fixed path (cannot tell) → refused, recorded_status=blkid_absent (the one name for it)" \
  || no "G5b-B an unreadable type did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_UNSEEDED=1
g5b_refused none invalid && ok "G5b-U no PLAINTEXT_DEV recorded (a lost state file) → refused, recorded=none recorded_status=invalid (fail-closed)" \
  || no "G5b-U an unrecorded plaintext did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case "persist_state PLAINTEXT_DEV $T_MAPPER;" "${G5B_ENV[@]}"
g5b_refused "$T_MAPPER" is_mapper && ok "G5b-M the record IS the mapper (reads ext4, but it is the live copy) → refused, recorded_status=is_mapper" \
  || no "G5b-M a record naming the mapper did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-M2 — an ALIAS of the mapper (a `/./` spelling; readlink -f resolves it) is the live copy too.
G5_MAP_ALIAS="${T_MAPPER%/*}/./${T_MAPPER##*/}"
g5_case "persist_state PLAINTEXT_DEV $G5_MAP_ALIAS;" "${G5B_ENV[@]}"
g5b_refused "$G5_MAP_ALIAS" is_mapper && ok "G5b-M2 a record that is an ALIAS of the mapper ($G5_MAP_ALIAS) → refused, recorded_status=is_mapper" \
  || no "G5b-M2 a mapper-alias record did not refuse as is_mapper (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-A — the recorded node is not a block device (a vanished kernel name after a reboot): absent, never
# conflated with a zeroed device (none).
g5_case ":;" "${G5B_ENV[@]}" PLAINTEXT_DEV_FSTYPE=absent
g5b_refused /dev/sdz9 absent && ok "G5b-A the recorded node is not a block device → refused, recorded_status=absent (drift or detach, not zeroed)" \
  || no "G5b-A an absent recorded node did not refuse as absent (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_case "persist_state PLAINTEXT_DEV -o;" "${G5B_ENV[@]}"
g5b_refused -o invalid && ! hasF "SEAM _plaintext_dev_type -o" \
  && ok "G5b-V an option-shaped record (-o, the seam says ext4) → refused by the validator, never probed" \
  || no "G5b-V an option-shaped record did not refuse (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
# G5b-V2/V3 — the validator's charset and `..` clauses, each on its own (the seam says ext4, so only the
# validator can refuse these): a `;` inside a /dev path, and a /dev path that climbs out with `..`.
for g5v in '/dev/sdz9;logger' '/dev/../tmp/x'; do
  g5_case "persist_state PLAINTEXT_DEV '$g5v';" "${G5B_ENV[@]}"
  g5b_refused "$g5v" invalid && ! hasF "SEAM _plaintext_dev_type $g5v" \
    && ok "G5b-V an unsafe record ($g5v) → refused by the validator (recorded_status=invalid), never probed" \
    || no "G5b-V an unsafe record ($g5v) did not refuse as invalid (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
done
# G5b-F8 — the physical witness needs BOTH conjuncts: with $MOUNT on the plaintext (pre-flip) a record that
# reads no filesystem is NOT "gone" (the mount gate), and the same record with the mapper mounted is.
for g5m in "/dev/sdz9:1:" "$T_MAPPER:0:plaintext_dev_gone"; do
  IFS=: read -r g5m_src g5m_rc g5m_why <<<"$g5m"
  run_case "$CUTOVER" '_plaintext_gone; echo "GONE_RC=$? WHY=$PLAINTEXT_GONE_WHY"' '_plaintext_gone' FINDMNT_MOUNT_SRC="$g5m_src" PLAINTEXT_DEV_FSTYPE=
  grep -qxF "GONE_RC=$g5m_rc WHY=$g5m_why" <<<"$CASE_OUT" \
    && ok "G5b-F8 _plaintext_gone with the mount on ${g5m_src} and an empty recorded fs → rc=$g5m_rc why=[${g5m_why}]" \
    || no "G5b-F8 _plaintext_gone mount conjunct wrong for ${g5m_src} (want rc=$g5m_rc why=[${g5m_why}]) ${CASE_OUT:0:200}"
done
# G5b-H1 — the pre-wipe web-1 shape: mapper mounted, the recorded plaintext intact → the acknowledged
# rollback runs, it probed the RECORDED device (not an empty or other key), and remounts that device.
g5_case ":;" "${G5B_ENV[@]}" DEADMAN_LOADED=timer FINDMNT_MOUNT_SRC_AFTER_DEADMAN_STOP=/dev/sdz9
ran && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' \
  && hasF "SEAM _plaintext_dev_type /dev/sdz9" && has '^mount /dev/sdz9[[:space:]]' \
  && ok "G5b-H1 mapper mounted + the recorded plaintext intact (pre-wipe) + ack → the rollback runs, probing and remounting the recorded device" \
  || no "G5b-H1 a pre-wipe acknowledged rollback was refused or probed the wrong key (rc=$CASE_RC seam=[$(grep -F 'SEAM _plaintext_dev_type' "$CALLS" | tr '\n' '|')]) ${CASE_OUT:0:200}"

# G5c — the check lives IN rollback(), so every caller is covered, not only ROLLBACK mode: here the
# cleanup() freeze arm (FREEZE_HELD / FLIP_DONE set, CANARY_OK not) on a post-wipe host.
g5_cleanup() {  # <seed> [env...]
  local seed="$1"; shift
  run_case "$CUTOVER" "$seed DRY_RUN=0; trap cleanup EXIT; die 'synthetic abort mid-freeze'" 'rollback cleanup' \
    ACTIVE_UNITS="$G5_ACT" CRYPTSETUP_DEV=/dev/sdz7 FINDMNT_MOUNT_SRC="$T_MAPPER" "$@"
}
g5c_refused() {  # [drift slug] [outcome]
  local slug="${1:-rollback_refused_plaintext_wiped}" oc="${2:-refused_plaintext_wiped}"
  died && has "^EMIT_DRIFT ${slug}\$" \
    && markerF "$DM result=cutover_aborted outcome=${oc}" \
    && [ "$(grep -cF 'result=cutover_aborted' "$MARKER_LOG")" -eq 1 ] \
    && nhas '^umount[[:space:]]' && nhas '^docker stop' && nhas '^cryptsetup close' && nhas '^mount[[:space:]]'
}
g5_cleanup "persist_state PLAINTEXT_WIPED '$PIN:1'; FREEZE_HELD=1;"
g5c_refused && grep -qE "outcome=refused_plaintext_wiped why=marker\$" "$MARKER_LOG" \
  && ok "G5c cleanup()'s freeze arm on a WIPED host refuses inside rollback(): no umount/close/stop/mount, outcome=refused_plaintext_wiped why=marker" \
  || no "G5c the cleanup() freeze arm rolled back over a wiped plaintext (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|') calls=[$(grep -E '^(umount|mount|docker|cryptsetup) ' "$CALLS" | tr '\n' '|')]"
g5_cleanup "FLIP_DONE=1;" PLAINTEXT_DEV_FSTYPE=
g5c_refused rollback_refused_plaintext_record_gone refused_plaintext_record_gone \
  && markerF "outcome=refused_plaintext_record_gone why=plaintext_dev_gone recorded=/dev/sdz9 recorded_status=none" \
  && ok "G5c the cleanup() flip arm with NO marker but the recorded plaintext unreadable (physical) refuses inside rollback() as refused_plaintext_record_gone, the outcome row carrying why=/recorded=/recorded_status=" \
  || no "G5c the markerless physical case rolled back (rc=$CASE_RC): $(grep -F cutover_aborted "$MARKER_LOG" | tr '\n' '|')"
g5_cleanup "FLIP_DONE=1;"
died && has '^umount[[:space:]]' && nhas '^EMIT_DRIFT rollback_refused_plaintext_wiped$' && has '^mount /dev/sdz9[[:space:]]' \
  && ok "G5c H1 the pre-wipe flip arm (recorded plaintext intact, no marker) still rolls back, remounting the recorded device" \
  || no "G5c H1 the pre-wipe cleanup rollback was refused (rc=$CASE_RC) ${CASE_OUT:0:200}"

# G5d — the dead-man FIRE string is self-contained (it runs after this script is gone), so it cannot
# call rollback(): it carries its OWN copy of the same check, evaluated by /bin/sh at fire time before
# any stop/umount/close. EXECUTED here against recording stubs (not grepped). g5d_arm re-arms per record
# (the record and the blkid path are BAKED at arm time), rebinding both the fire and its state file.
G5D_BIN="$RR_SCRATCH/g5d-bin"; mkdir -p "$G5D_BIN"
# One recording stub, copied per name (a quoted heredoc, so the stub's own `>>` is never read as a
# redirect of this suite by the fixture-relative-assert scanner).
cat > "$G5D_BIN/logger" <<'G5D_STUB'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$G5D_LOG"
G5D_STUB
for b in umount mount cryptsetup docker systemctl; do cp "$G5D_BIN/logger" "$G5D_BIN/$b"; done
# findmnt answers ONLY `-no SOURCE <the baked mount>`; blkid ONLY `-p -s TYPE -o value <the expected
# device>` (anything else logs *-unexpected and exits 64, so a fire probing the wrong device is seen).
cat > "$G5D_BIN/findmnt" <<'G5D_STUB'
#!/bin/sh
[ "$*" = "-no SOURCE $G5D_MNT" ] || { printf 'findmnt-unexpected %s\n' "$*" >> "$G5D_LOG"; exit 64; }
printf '%s\n' "$G5D_SRC"
G5D_STUB
cat > "$G5D_BIN/blkid" <<'G5D_STUB'
#!/bin/sh
printf 'blkid %s\n' "$*" >> "$G5D_LOG"
[ "$*" = "-p -s TYPE -o value $G5D_EXPECT_DEV" ] || { printf 'blkid-unexpected %s\n' "$*" >> "$G5D_LOG"; exit 64; }
[ -n "$G5D_TYPE" ] || exit 2
printf '%s\n' "$G5D_TYPE"
G5D_STUB
chmod +x "$G5D_BIN"/*
g5d_arm() {  # <record> [env...]
  local r="$1"; shift
  run_case "$CUTOVER" "persist_state PLAINTEXT_DEV '$r'; DRY_RUN=0 arm_dead_man" 'arm_dead_man' BLKID_BIN_PATH="$G5D_BIN/blkid" "$@"
  G5D_STATE="$STATE/state"; G5D_MNT="$MNT"
  G5D_FIRE="$(awk '/^systemd-run / { sub(/^.* \/bin\/sh -c /, ""); print; exit }' "$CALLS")"
}
g5d_fire() {  # <mount source> <state line or empty> <blkid TYPE or empty>
  G5D_LOG="$RR_SCRATCH/g5d.log"; : > "$G5D_LOG"
  # G5D_STATE is the state file run_case's arm baked into the fire ($STATE, bound by the harness, not
  # here): prove it is an absolute fixture path before writing it.
  assert_fixture_dir "$G5D_STATE"
  : > "$G5D_STATE"; [ -z "$2" ] || printf '%s\n' "$2" > "$G5D_STATE"
  env PATH="$G5D_BIN:/usr/bin:/bin" G5D_LOG="$G5D_LOG" G5D_SRC="$1" G5D_MNT="$G5D_MNT" G5D_TYPE="${3:-}" \
    G5D_EXPECT_DEV="$TGT_BLK" sh -c "$G5D_FIRE" >/dev/null 2>&1
}
g5d_log() { tr '\n' '|' < "$G5D_LOG" | cut -c1-300; }
g5d_arm "$TGT_BLK"
if [ -z "$G5D_FIRE" ] || ! sh -n -c "$G5D_FIRE" 2>/dev/null; then
  no "G5d INSTRUMENT: the fire string was not captured or is not valid /bin/sh (every fire row below would be vacuous) — ${G5D_FIRE:0:160}"
else
  # The behavioural rows below run whatever the fire contains, so a fire that lost its physical test
  # (or the whole guard) goes RED on the row that exercises it, not only here.
  grep -qF "$G5D_BIN/blkid -p -s TYPE -o value $TGT_BLK" <<<"$G5D_FIRE" \
    && ok "G5d the captured fire string parses under sh -n and bakes the fixed-path blkid against the recorded device" \
    || no "G5d the fire does not bake the arm-time blkid path against the recorded device — ${G5D_FIRE:0:200}"
  g5d_fire /dev/sdz9 "PLAINTEXT_WIPE_BEGUN=$PIN:1" ext4
  grep -qF 'reason=refused_plaintext_wiped why=marker' "$G5D_LOG" && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" && ! grep -qE '^docker stop' "$G5D_LOG" \
    && ok "G5d-R1 a dead-man FIRE on a host whose state names a wipe refuses (why=marker) before any stop/umount/close" \
    || no "G5d-R1 the fire string tore down the mount on a wiped host: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" ""
  grep -qF "reason=refused_plaintext_record_gone why=plaintext_dev_gone recorded=$TGT_BLK recorded_status=none" "$G5D_LOG" \
    && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" && ! grep -qE '^docker stop' "$G5D_LOG" && ! grep -qF -- '-unexpected' "$G5D_LOG" \
    && ok "G5d-R2 a FIRE with no marker, the mapper mounted and the recorded plaintext zeroed refuses (reason=refused_plaintext_record_gone recorded_status=none)" \
    || no "G5d-R2 the markerless physical fire tore down the mount: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" crypto_LUKS
  grep -qF "reason=refused_plaintext_record_gone why=plaintext_dev_gone recorded=$TGT_BLK recorded_status=crypto_LUKS" "$G5D_LOG" && ! grep -qE '^(umount|cryptsetup|mount) ' "$G5D_LOG" \
    && ok "G5d-D a FIRE whose recorded device now reads crypto_LUKS (drift) refuses and says so" \
    || no "G5d-D a drifted-record fire tore down the mount: $(g5d_log)"
  g5d_fire "$T_MAPPER" "" ext4
  grep -qE "^mount $TGT_BLK $G5D_MNT\$" "$G5D_LOG" && grep -qF "result=ok reason=plaintext_remounted mount_source=$TGT_BLK" "$G5D_LOG" \
    && grep -qxF "blkid -p -s TYPE -o value $TGT_BLK" "$G5D_LOG" && ! grep -qF -- '-unexpected' "$G5D_LOG" && ! grep -qF refused_plaintext "$G5D_LOG" \
    && ok "G5d-H2 the pre-wipe web-1 shape (mapper mounted, recorded plaintext intact ext4) RESTORES: mount <record> <mnt>, result=ok mount_source=<record>, blkid probed the record" \
    || no "G5d-H2 the intact-record fire did not restore the recorded device: $(g5d_log)"
  g5d_fire /dev/sdz9 "" ext4
  grep -qE '^umount ' "$G5D_LOG" && ! grep -qF 'reason=refused_plaintext_wiped' "$G5D_LOG" && grep -qE "^mount $TGT_BLK " "$G5D_LOG" \
    && ok "G5d-H1 a FIRE mid-freeze (plaintext still mounted, no marker) runs its restore exactly as before" \
    || no "G5d-H1 the pre-wipe fire was refused: $(g5d_log)"
  # G5d-F8 — the fire's physical witness is gated on the mapper being mounted: mid-freeze (plaintext still
  # mounted) a record that reads NO filesystem still restores — the mount conjunct, not the type alone.
  g5d_fire /dev/sdz9 "" ""
  grep -qE "^mount $TGT_BLK $G5D_MNT\$" "$G5D_LOG" && ! grep -qF refused_plaintext "$G5D_LOG" \
    && ok "G5d-F8 a FIRE with the plaintext still mounted restores even when the record reads no filesystem (the mapper conjunct)" \
    || no "G5d-F8 the fire refused (or did not mount) with the plaintext still mounted: $(g5d_log)"
  # G5d-S — the fire carries a SUBSET of _plaintext_record_status (marker; mapper mounted AND recorded not
  # ext4); validity, -b and not-the-mapper are proven at arm time. Pin the ext4 clause literally.
  grep -qF "= ${T_MAPPER} ] && [ \"\$t\" != ext4 ]" <<<"$G5D_FIRE" \
    && ok "G5d-S the fire's physical witness is exactly (mapper mounted AND recorded TYPE != ext4)" \
    || no "G5d-S the fire's ext4 clause changed — ${G5D_FIRE:0:300}"
fi

# ============================================================================
echo
echo "workspaces-luks-rollback-refusal.test.sh: $pass passed, $fail failed"
# PASS FLOOR pinned at the EXACT measured count (harness_floor is `-lt`, so only an exact pin makes a
# dropped row bite). It exits through printf, never through no().
RR_MIN_PASS=45
harness_floor workspaces-luks-rollback-refusal.test.sh "$RR_MIN_PASS"
[ "$fail" -eq 0 ]
