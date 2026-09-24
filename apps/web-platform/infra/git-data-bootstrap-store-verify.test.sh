#!/usr/bin/env bash
# git-data-bootstrap-store-verify.test.sh — Guard 2 for #8211 (ADR-239): an instance proves its
# layout before any store action is allowed.
#
# PROPERTY. Unless the plaintext volume is verified empty or absent, the served store holds
# nothing unknown, the fence sits on the mapper, and a real erasure succeeds as `git`, (a) no
# store marker is written and (b) every failure is a named `FATAL:` at stage=bootstrap. The
# marker is what the four store-acting scripts refuse without (contract C1/C2), so "no marker"
# IS "no erasure, no provision, no push" — a Delete Account arriving mid-bootstrap is refused
# and never reported `erased`.
#
# Two arms:
#   STATIC  — predicates over git-data-bootstrap.sh itself: the seam defaults, the mount
#             options, the single marker writer and its position, `env -i` before `runuser`,
#             and the log() routing that makes every new FATAL a stage=bootstrap page.
#   RUNTIME — bootstrap steps 2-5 are extracted as ONE unit from the sentinel comments the
#             script carries for this purpose (the `_reopen_unit` precedent in
#             git-data-luks-reopen.test.sh) and DRIVEN WITHOUT ROOT against a scratch PATH of
#             stubs: mount (logs argv and SOURCE, copies a fixture tree into its target), umount,
#             dumpe2fs (per device: origin and snapshot), findmnt, stat, cryptsetup, blockdev
#             (whose --getro answers from behaviour), losetup, dmsetup, udevadm, dmesg, cat (for
#             ext4's errors_count), install and runuser. The seams the bootstrap honours
#             (GIT_DATA_STORE_DEVICE, GIT_DATA_STORE_VERIFIED, GIT_DATA_REMOVE_BIN and the by-id
#             GIT_DATA_PLAINTEXT_DEV) plus four absolute-path rewrites (runuser, /dev/shm,
#             /dev/mapper/, /sys/) are what make that possible without EACCES standing in for a
#             refusal.
#
# The plaintext volume is read through a dm snapshot over a kernel-read-only origin (ADR-239
# amendment 2026-09-24, #5274): the snapshot is what gets mounted, without noload, so a dirty
# journal replays into a RAM COW and the counted tree is the post-replay tree. Guard 1's mutation
# rows (G1-*) run here except row 4 (noload + no post-check) and the COW overflow, which need a
# real kernel and live in git-data-plaintext-snapshot-loopback.test.sh.
#
# Guard 2's mutation matrix rows 1, 2, 3, 5 and 7 are encoded as SELF-TESTS: each mutates a
# temp copy of the extracted unit, re-runs the same fixture, and requires the verdict to FLIP.
# Each carries a landed-check (the mutant is not byte-identical to the pristine unit) and an
# instrument self-test (the pristine unit against that fixture gives the expected verdict), so
# a re-anchoring slip is reported as a dead arm rather than passing silently.
#
# NOT COVERED HERE, deliberately: row 4 (the terminal-boolean set) lives with the boot-signal
# poll and the rung-2 capture, and row 6 (the reboot arm's target) with
# git-data-luks-reopen.test.sh, which owns the fstab-target allowlist.
#
# Run: bash apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$DIR/git-data-bootstrap.sh"
REMOVE="$DIR/git-data-remove.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }
cases=0
ok() { cases=$((cases + 1)); if [ "$1" -eq 0 ]; then pass; else fail "$2" "${3:-}"; fi; }

for f in "$BOOTSTRAP" "$REMOVE"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done
REAL_INSTALL="$(command -v install || true)"
[ -n "$REAL_INSTALL" ] || { echo "FAIL: install(1) not on PATH — the marker-directory stub cannot delegate" >&2; exit 1; }

SCRATCH="$(mktemp -d -t gdstoreverify.XXXXXXXX)"
# The canonical operand guard (P1a/P1b, #7652/#7708), BYTE-IDENTICAL to the definition in
# plugins/soleur/test/test-helpers.sh — `fixture-dir-operand-assert.test.sh` compares them and
# reds on drift, because a helper that is re-derived per file is eventually re-derived wrongly
# (#7822). Inlined rather than sourced only because this suite lives under apps/web-platform/infra
# and is run standalone by infra-validation.yml; the drift arm is what keeps the copy honest.
# Every scratch write below interpolates a variable into a path, and `rm -rf ""` / `cp x ""` /
# `> "/action"` are what an empty or relative one produces — the trap on the next line is itself
# such a site. Asserted at the boundary, and again per fixture.
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
assert_fixture_dir "$SCRATCH"
trap 'assert_fixture_dir "$SCRATCH"; rm -rf "$SCRATCH"' EXIT

# Drop comment lines the way the module's rationale strip does, so a static row can never be
# satisfied (or tripped) by prose. `#!` survives the strip on purpose.
strip() { grep -vE '^[[:space:]]*#([^!]|$)' "$1"; }

BS_BODY="$SCRATCH/bootstrap.body"; strip "$BOOTSTRAP" > "$BS_BODY"

# =====================================================================================
# EXTRACTION — bootstrap steps 2-5 as one unit
# =====================================================================================
BEGIN_SENTINEL='# ---- BEGIN store-verify unit ----'
END_SENTINEL='# ---- END store-verify unit ----'
UNIT="$SCRATCH/unit.sh"
awk -v b="$BEGIN_SENTINEL" -v e="$END_SENTINEL" \
  '$0==b{f=1;next} $0==e{f=0} f' "$BOOTSTRAP" > "$UNIT"

n=$(grep -cxF "$BEGIN_SENTINEL" "$BOOTSTRAP" || true)
ok "$((n != 1))" "X1 exactly one BEGIN store-verify sentinel in the bootstrap (got $n)"
n=$(grep -cxF "$END_SENTINEL" "$BOOTSTRAP" || true)
ok "$((n != 1))" "X2 exactly one END store-verify sentinel in the bootstrap (got $n)"
# The floor is what turns "extracted nothing" from a silently green suite into a red one: every
# runtime row below sources this file, and an empty one passes every assertion vacuously.
UNIT_LINES=$(grep -c . "$UNIT" || true)
ok "$((UNIT_LINES < 60))" "X3 the store-verify unit was extracted (got $UNIT_LINES lines; floor 60)"
ok "$(bash -n "$UNIT" 2>/dev/null; echo $?)" "X4 the extracted unit is syntactically valid bash on its own"
UNIT_BODY="$SCRATCH/unit.body"; strip "$UNIT" > "$UNIT_BODY"

# =====================================================================================
# STATIC — the seams, the options, the marker, the probe
# =====================================================================================
ok "$(grep -qxF 'GIT_DATA_ROOT="/mnt/git-data"' "$BS_BODY"; echo $?)" \
  "S1 the served store root is /mnt/git-data (#8211: the mapper's mountpoint, not a staging path)"
n=$(grep -c '/mnt/git-data-luks' "$BS_BODY" || true)
ok "$((n != 0))" "S1b the pre-#8211 /mnt/git-data-luks is named nowhere in the script body (got $n)"
ok "$(grep -qxF 'REPO_ROOT="$GIT_DATA_ROOT/repositories" ' "$BS_BODY" || grep -qE '^REPO_ROOT="\$GIT_DATA_ROOT/repositories"' "$BS_BODY"; echo $?)" \
  "S1c REPO_ROOT derives from GIT_DATA_ROOT (the harness prelude mirrors this derivation)"
ok "$(grep -qE '^PRE_RECEIVE="\$HOOKS_DIR/pre-receive"' "$BS_BODY"; echo $?)" \
  "S1d PRE_RECEIVE derives from HOOKS_DIR (ditto)"
ok "$(grep -qxF 'STORE_DEVICE="${GIT_DATA_STORE_DEVICE:-/dev/mapper/git-data}"' "$BS_BODY"; echo $?)" \
  "S2 STORE_DEVICE seam defaults to /dev/mapper/git-data (contract C1)"
ok "$(grep -qxF 'STORE_VERIFIED="${GIT_DATA_STORE_VERIFIED:-/etc/git-data/store-verified}"' "$BS_BODY"; echo $?)" \
  "S3 STORE_VERIFIED seam defaults to /etc/git-data/store-verified (contract C2)"
ok "$(grep -qF 'GIT_DATA_REMOVE_BIN:-/usr/local/bin/git-data-remove.sh' "$UNIT_BODY"; echo $?)" \
  "S4 GIT_DATA_REMOVE_BIN seam defaults to /usr/local/bin/git-data-remove.sh"
ok "$(grep -qF 'GIT_DATA_PLAINTEXT_DEV:-/dev/disk/by-id/scsi-0HC_Volume_$_pt_id' "$UNIT_BODY"; echo $?)" \
  "S5 the plaintext device is the by-id path built from the rendered volume id, behind a seam"
# The plaintext volume is read through a dm snapshot over a kernel-read-only origin (ADR-239
# amendment 2026-09-24): a plain `ro` mount replays a dirty journal ONTO the volume, and `noload`
# counts a stale tree. So the only mount is of the SNAPSHOT, without noload.
ok "$(grep -qF 'mount -o ro,errors=remount-ro,nosuid,nodev,noexec "/dev/mapper/$_pt_snap" "$_pt_mnt"' "$UNIT_BODY"; echo $?)" \
  "S6 the only plaintext mount is the snapshot, -o ro,errors=remount-ro,nosuid,nodev,noexec"
n=$(grep -c 'noload' "$UNIT_BODY" || true)
ok "$((n != 0))" "S6b no noload token remains in the comment-stripped unit (got $n)"
n=$(grep -cE '(^|[[:space:];|&(])mount -o' "$UNIT_BODY" || true)
ok "$((n != 1))" "S6c exactly one mount call in the unit (got $n)"
ok "$(grep -qF 'dmsetup create "$_pt_snap" --table "0 $_pt_sz snapshot $_pt_dev $_pt_loop N 8"' "$UNIT_BODY"; echo $?)" \
  "S6d the dm table is exactly '0 \$_pt_sz snapshot \$_pt_dev \$_pt_loop N 8' (no feature args: discard_passdown_origin would reach the origin)"
n=$(grep -c -- '--setrw' "$BS_BODY" || true)
ok "$((n != 0))" "S6e no blockdev --setrw anywhere in the bootstrap (got $n)"
ok "$(grep -qxF '  _pt_snap=git-data-pt-snap' "$UNIT_BODY"; echo $?)" "S6f the snapshot name is the fixed git-data-pt-snap (never the LUKS mapper name)"
# AC2 — READ-ONLY FIRST, by line, in the comment-stripped unit.
L_SETRO=$(grep -n 'blockdev --setro' "$UNIT_BODY" | head -1 | cut -d: -f1)
L_CREATE=$(grep -n 'dmsetup create' "$UNIT_BODY" | head -1 | cut -d: -f1)
L_MOUNT=$(grep -nE '(^|[[:space:];|&(])mount -o' "$UNIT_BODY" | head -1 | cut -d: -f1)
L_ISLUKS=$(grep -n 'cryptsetup isLuks' "$UNIT_BODY" | head -1 | cut -d: -f1)
ok "$([ -n "$L_SETRO" ] && [ -n "$L_CREATE" ] && [ -n "$L_MOUNT" ] && [ -n "$L_ISLUKS" ] && [ "$L_ISLUKS" -lt "$L_SETRO" ] && [ "$L_SETRO" -lt "$L_CREATE" ] && [ "$L_SETRO" -lt "$L_MOUNT" ]; echo $?)" \
  "S6g by line: isLuks ($L_ISLUKS) < blockdev --setro ($L_SETRO) < dmsetup create ($L_CREATE) and < mount ($L_MOUNT)"
ok "$(grep -qF '_pt_dir="$(mktemp -d -p /dev/shm)"' "$UNIT_BODY"; echo $?)" "S7 the COW and mount parent are a private mktemp -d on /dev/shm (RAM)"
ok "$(grep -qF '_pt_mnt="$_pt_dir/mnt"' "$UNIT_BODY"; echo $?)" \
  "S7b the mount target is <mktemp -d>/mnt, so the 0700 parent outlives the volume's own root mode"
ok "$(grep -qE '^[[:space:]]*trap _pt_release EXIT$' "$UNIT_BODY"; echo $?)" \
  "S8 a trap tears the snapshot apparatus down on EVERY exit"
ok "$(grep -qF 'plaintext_unverified reason=umount' "$UNIT_BODY"; echo $?)" "S8b a failed teardown is FATAL reason=umount"
n=$(grep -c 'rm -rf' "$UNIT_BODY" || true)
ok "$((n != 0))" "S8c no rm -rf in the unit — it would walk a still-mounted plaintext tree into stderr (got $n)"
ok "$(grep -qF "! -name '.*.init.lock' ! -name lost+found -printf x 2>/dev/null" "$UNIT_BODY"; echo $?)" \
  "S9 the count excludes the .<id>.init.lock dotfiles and lost+found, and discards find's stderr (entry names are workspace ids)"
n=$(grep -c "\-name '\*\.git'" "$UNIT_BODY" || true)
ok "$((n != 0))" "S9b the count is NOT narrowed to *.git — a partial repositories/x is still user data (got $n)"
# AC5 — every plaintext FATAL names a reason from the closed vocabulary, or is the residue line.
_bad=0
while IFS= read -r _l; do
  case "$_l" in
    *"FATAL: plaintext_unverified reason=source "*|*"FATAL: plaintext_unverified reason=snapshot "*|*"FATAL: plaintext_unverified reason=mount "*|*"FATAL: plaintext_unverified reason=journal "*|*"FATAL: plaintext_unverified reason=umount "*) : ;;
    *'FATAL: plaintext_residue count=$_pt_n — the plaintext volume still holds repositories/ entries'*) : ;;
    *) _bad=1; echo "      off-vocabulary: $_l" >&2 ;;
  esac
done < <(grep -F 'FATAL: plaintext_' "$UNIT_BODY")
ok "$_bad" "S9c every plaintext FATAL is reason=(source|snapshot|mount|journal|umount) or the unchanged residue line"
N_PT_FATAL=$(grep -c 'FATAL: plaintext_' "$UNIT_BODY" || true)
# The inner sentinels both the loopback suite and this harness depend on.
n=$(grep -cxF '# ---- BEGIN plaintext-count unit ----' "$UNIT" || true)
ok "$((n != 1))" "S9d exactly one BEGIN plaintext-count sentinel, inside the store-verify unit (got $n)"
n=$(grep -cxF '# ---- END plaintext-count unit ----' "$UNIT" || true)
ok "$((n != 1))" "S9e exactly one END plaintext-count sentinel, inside the store-verify unit (got $n)"
# The single marker writer, and it sits after every FATAL that must leave the marker absent.
n=$(grep -c 'mv -f "\$_marker_tmp" "\$STORE_VERIFIED"' "$UNIT_BODY" || true)
ok "$((n != 1))" "S10 exactly one marker writer in the unit (got $n)"
L_MARK=$(grep -n 'mv -f "\$_marker_tmp" "\$STORE_VERIFIED"' "$UNIT_BODY" | head -1 | cut -d: -f1)
_late=0
while IFS= read -r _l; do
  [ "${_l%%:*}" -lt "${L_MARK:-0}" ] || _late=1
done < <(grep -nE 'FATAL: (plaintext_unverified|plaintext_residue|luks_residue)' "$UNIT_BODY")
ok "$_late" "S11 every plaintext_*/luks_residue FATAL precedes the marker writer (marker at line ${L_MARK:-none})"
ok "$(grep -qF 'install -d -m0755 -o root -g root "$(dirname "$STORE_VERIFIED")"' "$UNIT_BODY"; echo $?)" \
  "S12 the marker's parent is created root-owned 0755"
ok "$(grep -qF 'chmod 0644 "$_marker_tmp"' "$UNIT_BODY"; echo $?)" "S12b the marker is 0644"
ok "$(grep -qF 'findmnt -n -o UUID --mountpoint "$GIT_DATA_ROOT"' "$UNIT_BODY"; echo $?)" \
  "S12c the marker's one line is the mapper filesystem UUID (contract C2)"
ok "$(grep -qF 'findmnt -n -o SOURCE -T "$PRE_RECEIVE"' "$UNIT_BODY"; echo $?)" \
  "S13 fence_on_mapper resolves the mount CONTAINING the hook (-T), not a mountpoint guess"
# The probe, and the ordering that makes it safe. `runuser -u` without -l keeps its caller's
# environment, so `runuser … env -i` would briefly run a git-uid process still holding
# GIT_DATA_LUKS_KEY in /proc/<pid>/environ.
PROBE_LINE=$(grep -n 'SSH_ORIGINAL_COMMAND=boot-probe-0' "$UNIT_BODY" | head -1 | cut -d: -f2-)
ok "$([ -n "$PROBE_LINE" ]; echo $?)" "S14 the erasure probe line is present"
_i_env=$(awk -v s="$PROBE_LINE" 'BEGIN{print index(s, "env -i")}')
_i_run=$(awk -v s="$PROBE_LINE" 'BEGIN{print index(s, "runuser")}')
ok "$([ "$_i_env" -gt 0 ] && [ "$_i_run" -gt 0 ] && [ "$_i_env" -lt "$_i_run" ]; echo $?)" \
  "S15 env -i PRECEDES runuser on the probe line (env at col $_i_env, runuser at col $_i_run)" "$PROBE_LINE"
ok "$(printf '%s\n' "$PROBE_LINE" | grep -qF 'PATH=/usr/bin:/bin'; echo $?)" "S15b the probe pins PATH=/usr/bin:/bin"
ok "$(printf '%s\n' "$PROBE_LINE" | grep -qF '/usr/sbin/runuser'; echo $?)" \
  "S15c runuser is named by absolute path — env -i's PATH does not include /usr/sbin"
ok "$(printf '%s\n' "$PROBE_LINE" | grep -qF -- '-u git --'; echo $?)" "S15d the probe runs as the git transport user"
ok "$(grep -qF 'rm -f "$STORE_VERIFIED"' "$UNIT_BODY"; echo $?)" "S16 a failed probe removes the marker before the FATAL"
L_RM=$(grep -n 'rm -f "\$STORE_VERIFIED"' "$UNIT_BODY" | tail -1 | cut -d: -f1)
L_PFATAL=$(grep -n 'FATAL: erasure_probe=no' "$UNIT_BODY" | head -1 | cut -d: -f1)
ok "$([ -n "$L_RM" ] && [ -n "$L_PFATAL" ] && [ "$L_RM" -lt "$L_PFATAL" ]; echo $?)" \
  "S16b the removal is BEFORE the erasure_probe FATAL (rm at $L_RM, FATAL at $L_PFATAL)"
# Every new failure pages on a stage Sentry already routes, so issue-alerts.tf is not edited.
ok "$(grep -qF 'bootstrap fatal' "$BS_BODY"; echo $?)" "S17 log() routes a FATAL: prefix to the emitter at stage=bootstrap"
for _r in plaintext_unverified plaintext_residue luks_residue 'fence_on_mapper=no' 'erasure_probe=no'; do
  ok "$(grep -qF "FATAL: $_r" "$UNIT_BODY"; echo $?)" "S18 the named FATAL reason '$_r' exists in the unit"
done
for _b in fence_on_mapper erasure_probe plaintext_empty plaintext_volume served_repos plaintext_journal; do
  ok "$(grep -qF "\"$_b=\${_$_b}\"" "$BS_BODY" || grep -qF "$_b=\${_$_b}" "$BS_BODY"; echo $?)" \
    "S19 boot_complete carries $_b (contract C3)"
done
# The two output strings the probe and the app-side erasure both read. Byte-exact by contract.
ok "$(grep -qF "not present (no-op)" "$REMOVE"; echo $?)" "S20 git-data-remove.sh still prints 'not present (no-op)' byte-exact"
ok "$(grep -qF "erased bare repo" "$REMOVE"; echo $?)" "S20b git-data-remove.sh still prints 'erased bare repo' byte-exact"

# =====================================================================================
# RUNTIME — the extracted unit, driven without root
# =====================================================================================
STORE_DEV_FIXTURE="/dev/mapper/git-data-fixture"
FX=""
PT_ID="100000001"
LEAK_KEY="fixture-luks-key-0000"
RC=0

# Stubs bake their fixture path in as a LITERAL rather than reading it from the environment:
# the erasure probe runs under `env -i`, so a stub reached through it sees no exported seam.
mkstub() {
  { printf '#!/usr/bin/env bash\nFXD=%q\nREAL_INSTALL=%q\n' "$FX" "$REAL_INSTALL"; cat; } > "$FX/bin/$1"
  chmod +x "$FX/bin/$1"
}

new_fixture() {
  FX="$SCRATCH/fx.$1"
  assert_fixture_dir "$FX"
  rm -rf "$FX"
  mkdir -p "$FX/bin" "$FX/store/repositories" "$FX/store/hooks" "$FX/ptsrc/repositories" "$FX/dev/mapper" "$FX/tmp" "$FX/shm" "$FX/sys/class/block/vol/holders"
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  : > "$FX/store/hooks/pre-receive"
  chmod 0755 "$FX/store/hooks/pre-receive"
  : > "$FX/dev/vol"
  : > "$FX/dev/other"
  ln -sfn "$FX/dev/vol" "$FX/dev/by-id"
  # findmnt answers, per query kind. The snapshot's mapper node exists only while the dmsetup
  # stub holds it, so the unit's realpath comparison resolves something real on both sides.
  printf '%s\n' "$FX/dev/mapper/git-data-pt-snap" > "$FX/pt_source"
  printf '%s\n' "$STORE_DEV_FIXTURE" > "$FX/fence_source"
  printf '%s\n' "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > "$FX/store_uuid"
  printf '0\n0\n' > "$FX/errors_seq"

  mkstub mount <<'STUB'
printf 'mount|%s\n' "$*" >> "$FXD/calls.log"
_opts=""; _src=""; _tgt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) _opts="$2"; shift 2 ;;
    *) if [ -z "$_src" ]; then _src="$1"; else _tgt="$1"; fi; shift ;;
  esac
done
printf '%s\n' "$_opts" > "$FXD/mount_opts"
printf '%s\n' "$_src" > "$FXD/mount_source"
[ ! -e "$FXD/mount_fail" ] || exit 32
# A no-op mount is the failure this step exists to catch: the target stays an EMPTY DIRECTORY,
# which a count alone reads as "clean".
[ ! -e "$FXD/mount_noop" ] || exit 0
cp -a "$FXD/ptsrc/." "$_tgt/"
STUB

  mkstub umount <<'STUB'
printf 'umount|%s\n' "$*" >> "$FXD/calls.log"
[ ! -e "$FXD/umount_fail" ] || exit 1
rm -rf -- "${1:?}"/* "${1:?}"/.[!.]* 2>/dev/null || true
exit 0
STUB

  # Per device: the ORIGIN (dumpe2fs_dirty toggles needs_recovery; geometry_bad drops the journal
  # geometry) and the SNAPSHOT (snap_still_dirty: the journal did not replay; snap_with_errors).
  mkstub dumpe2fs <<'STUB'
printf 'dumpe2fs|%s\n' "$*" >> "$FXD/calls.log"
_dev="${*: -1}"
case "$_dev" in
  */mapper/git-data-pt-snap)
    [ ! -e "$FXD/snap_dumpe2fs_fail" ] || exit 1
    if [ -e "$FXD/snap_still_dirty" ]; then
      printf 'Filesystem features:      has_journal ext_attr needs_recovery extent 64bit\n'
    else
      printf 'Filesystem features:      has_journal ext_attr resize_inode extent 64bit\n'
    fi
    if [ -e "$FXD/snap_with_errors" ]; then printf 'Filesystem state:         clean with errors\n'; else printf 'Filesystem state:         clean\n'; fi
    ;;
  *)
    [ ! -e "$FXD/dumpe2fs_fail" ] || exit 1
    if [ -e "$FXD/dumpe2fs_dirty" ]; then
      printf 'Filesystem features:      has_journal ext_attr needs_recovery extent 64bit\n'
    else
      printf 'Filesystem features:      has_journal ext_attr resize_inode extent 64bit\n'
    fi
    printf 'Block size:               4096\n'
    [ -e "$FXD/geometry_bad" ] || printf 'Total journal blocks:     16384\n'
    ;;
esac
STUB

  mkstub findmnt <<'STUB'
printf 'findmnt|%s\n' "$*" >> "$FXD/calls.log"
_op=""; _t=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) _op="$2"; shift 2 ;;
    -T) _t="$2"; shift 2 ;;
    --mountpoint) shift 2 ;;
    *) shift ;;
  esac
done
if [ "$_op" = UUID ]; then _f="$FXD/store_uuid"
elif [ -n "$_t" ]; then _f="$FXD/fence_source"
else _f="$FXD/pt_source"; fi
[ -s "$_f" ] || exit 1
cat "$_f"
STUB

  # The origin node is a regular file here; `stat -L -c %F` is the unit's block-device test.
  mkstub stat <<'STUB'
if [ "${*: -1}" = "$FXD/dev/vol" ]; then
  printf 'stat|%s\n' "$*" >> "$FXD/calls.log"
  if [ -e "$FXD/pt_not_block" ]; then echo 'regular empty file'; else echo 'block special file'; fi
  exit 0
fi
exec /usr/bin/stat "$@"
STUB

  mkstub cryptsetup <<'STUB'
printf 'cryptsetup|%s\n' "$*" >> "$FXD/calls.log"
[ "${1:-}" = isLuks ] || { printf 'cryptsetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
[ -e "$FXD/pt_is_luks" ]
STUB

  # --getro answers from BEHAVIOUR: 1 only after --setro was really called (Guard 1 mutation 1
  # reds on behaviour, not on a missing line).
  mkstub blockdev <<'STUB'
printf 'blockdev|%s\n' "$*" >> "$FXD/calls.log"
case "${1:-}" in
  --setro) [ ! -e "$FXD/setro_fail" ] || exit 1; : > "$FXD/ro_set" ;;
  --setrw) rm -f "$FXD/ro_set" ;;
  --getro) if [ -e "$FXD/ro_set" ] && [ ! -e "$FXD/getro_zero" ]; then echo 1; else echo 0; fi ;;
  --getsz) [ -e "$FXD/getsz_bad" ] || echo 20971520 ;;
  *) printf 'blockdev-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  mkstub losetup <<'STUB'
printf 'losetup|%s\n' "$*" >> "$FXD/calls.log"
case "${1:-}" in
  --find) [ ! -e "$FXD/losetup_fail" ] || exit 1; : > "$FXD/loop_up"; echo /dev/loop77 ;;
  -d) [ ! -e "$FXD/losetup_d_fail" ] || exit 1; rm -f "$FXD/loop_up" ;;
  *) printf 'losetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  mkstub dmsetup <<'STUB'
printf 'dmsetup|%s\n' "$*" >> "$FXD/calls.log"
case "${1:-}" in
  create) [ ! -e "$FXD/dm_create_fail" ] || exit 1; : > "$FXD/dev/mapper/$2" ;;
  remove) [ ! -e "$FXD/dm_remove_fail" ] || exit 1; rm -f "$FXD/dev/mapper/${*: -1}" ;;
  status) if [ -e "$FXD/dm_invalid" ]; then echo '0 20971520 snapshot Invalid'; else echo '0 20971520 snapshot 16/262144 16'; fi ;;
  info) echo dm-9 ;;
  *) printf 'dmsetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  mkstub udevadm <<'STUB'
printf 'udevadm|%s\n' "$*" >> "$FXD/calls.log"
STUB

  # The kernel log: a baseline on the first read, then the baseline plus klog_extra.
  mkstub dmesg <<'STUB'
_n=$(( $(cat "$FXD/dmesg_calls" 2>/dev/null || echo 0) + 1 ))
echo "$_n" > "$FXD/dmesg_calls"
echo '[    0.000000] Linux version fixture'
[ "$_n" -eq 1 ] || [ ! -e "$FXD/klog_extra" ] || cat "$FXD/klog_extra"
STUB

  # ext4's errors_count, one line per read (the unit reads it after the mount and after the count).
  mkstub cat <<'STUB'
case "${1:-}" in
  */errors_count)
    printf 'cat|%s\n' "$*" >> "$FXD/calls.log"
    _n=$(( $(/usr/bin/cat "$FXD/errors_calls" 2>/dev/null || echo 0) + 1 ))
    echo "$_n" > "$FXD/errors_calls"
    sed -n "${_n}p" "$FXD/errors_seq"
    exit 0 ;;
esac
exec /usr/bin/cat "$@"
STUB

  # Delegates to the real install with -o/-g stripped: a non-root run cannot chown to root, and
  # swallowing the whole call would make S12's root-ownership row untested at runtime.
  mkstub install <<'STUB'
printf 'install|%s\n' "$*" >> "$FXD/calls.log"
_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-g) shift 2 ;;
    *) _args+=("$1"); shift ;;
  esac
done
exec "$REAL_INSTALL" "${_args[@]}"
STUB

  # Strips `-u git --` and preserves the environment EXACTLY — anything it added would hide the
  # very leak row 7 exists to catch.
  mkstub runuser <<'STUB'
printf 'runuser|%s\n' "$*" >> "$FXD/calls.log"
env > "$FXD/runuser.env"
[ "${1:-}" = -u ] && [ "${2:-}" = git ] && [ "${3:-}" = -- ] || { printf 'runuser-stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
shift 3
exec "$@"
STUB

  mkstub remove <<'STUB'
printf 'remove|%s\n' "$*" >> "$FXD/calls.log"
env > "$FXD/probe.env"
_id="${SSH_ORIGINAL_COMMAND:-noenv}"
# The real script's 0-byte lock dotfile, so "invisible to the served_repos count" is measured
# against a file that exists rather than assumed.
: > "$FXD/store/repositories/.$_id.init.lock"
if [ -e "$FXD/probe_refuse" ]; then
  printf 'remote: git-data remove: refused\n' >&2
  exit 1
fi
printf "remote: git-data remove: '%s' not present (no-op)\n" "$_id" >&2
STUB

  mkstub git-data-emit <<'STUB'
printf '%s|%s|%s|%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" >> "$FXD/emit.log"
STUB

  # The prelude gives the unit the four bindings §1 of the bootstrap would have made. The three
  # seam lines are COPIED OUT OF THE SCRIPT, not restated, so a seam rename cannot leave this
  # harness testing a binding the host no longer has.
  {
    grep -m1 '^GIT_DATA_EMIT=' "$BOOTSTRAP"
    awk '/^log\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$BOOTSTRAP"
    grep -m1 '^STORE_DEVICE=' "$BOOTSTRAP"
    grep -m1 '^STORE_VERIFIED=' "$BOOTSTRAP"
    printf 'GIT_DATA_ROOT=%q\n' "$FX/store"
    printf 'REPO_ROOT="$GIT_DATA_ROOT/repositories"\n'
    printf 'HOOKS_DIR="$GIT_DATA_ROOT/hooks"\n'
    printf 'PRE_RECEIVE="$HOOKS_DIR/pre-receive"\n'
  } > "$FX/prelude.sh"

  cat > "$FX/trailer.sh" <<'TRAIL'
printf 'plaintext_volume=%s\n' "$_plaintext_volume"
printf 'plaintext_empty=%s\n' "$_plaintext_empty"
printf 'served_repos=%s\n' "$_served_repos"
printf 'fence_on_mapper=%s\n' "$_fence_on_mapper"
printf 'erasure_probe=%s\n' "$_erasure_probe"
printf 'plaintext_journal=%s\n' "$_plaintext_journal"
TRAIL
}

# The extracted unit names four absolute paths a non-root fixture cannot own: runuser (S15c),
# the /dev/shm COW parent, the /dev/mapper node of the snapshot, and /sys (holders and ext4's
# errors_count). Each is rewritten into the scratch dir — the reporter-unit precedent from
# git-data-luks-reopen.test.sh. The static rows above pin the shipped spellings, and the
# landed-check below refuses a rewrite that did not happen.
run_unit() {
  local _u="$1"
  sed -e "s#/usr/sbin/runuser#$FX/bin/runuser#g" -e "s#/dev/shm#$FX/shm#g" \
      -e "s#/dev/mapper/#$FX/dev/mapper/#g" -e "s#/sys/#$FX/sys/#g" "$_u" > "$FX/unit.run"
  if grep -qE '(^|[" ])/(dev/shm|dev/mapper/|sys/)' "$FX/unit.run"; then
    echo "FATAL: a path rewrite did not land in $FX/unit.run" >&2; exit 2
  fi
  # Per-RUN artifacts, not per-fixture: the mutation rows drive the pristine unit and then the
  # mutant against the SAME fixture, and a calls.log carried over from the first run makes
  # "the mutant never called the wrapper" true of neither run.
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  rm -f "$FX/probe.env" "$FX/runuser.env" "$FX/mount_opts" "$FX/mount_source" "$FX/etc/git-data/store-verified" \
    "$FX/ro_set" "$FX/loop_up" "$FX/dmesg_calls" "$FX/errors_calls" "$FX/dev/mapper/git-data-pt-snap"
  RC=0
  env -u GIT_DATA_PLAINTEXT_VOLUME_ID \
    PATH="$FX/bin:$PATH" TMPDIR="$FX/tmp" \
    GIT_DATA_EMIT="$FX/bin/git-data-emit" \
    GIT_DATA_STORE_DEVICE="$STORE_DEV_FIXTURE" \
    GIT_DATA_STORE_VERIFIED="$FX/etc/git-data/store-verified" \
    GIT_DATA_REMOVE_BIN="$FX/bin/remove" \
    GIT_DATA_PLAINTEXT_DEV="$FX/dev/by-id" \
    ${PT_ID:+GIT_DATA_PLAINTEXT_VOLUME_ID="$PT_ID"} \
    GIT_DATA_LUKS_KEY="$LEAK_KEY" \
    bash -c 'set -euo pipefail; . "$1"; . "$2"; . "$3"' _ \
      "$FX/prelude.sh" "$FX/unit.run" "$FX/trailer.sh" > "$FX/out" 2> "$FX/err" || RC=$?
}

# `ok` reads 0 as PASS, so an ABSENCE row counts hits and compares: `grep -q` returns 1 when
# the string is missing, which ok() would score as a failure of the very property it proves.
absent_in() { local _pat="$1"; shift; if grep -q -- "$_pat" "$@" 2>/dev/null; then echo 1; else echo 0; fi; }
marker() { cat "$FX/etc/git-data/store-verified" 2>/dev/null; }
marker_absent() { [ ! -e "$FX/etc/git-data/store-verified" ]; echo $?; }
field() { sed -n "s/^$1=//p" "$FX/out"; }
fatal_is() { grep -qF "FATAL: $1" "$FX/err"; echo $?; }
emit_stage_bootstrap() {
  local n_all n_boot
  n_all=$(grep -c 'fatal' "$FX/emit.log" || true)
  n_boot=$(grep -c '|bootstrap|fatal|' "$FX/emit.log" || true)
  [ "$n_all" -ge 1 ] && [ "$n_all" -eq "$n_boot" ]
  echo $?
}
# first_line <regex> — the calls.log line number of the first match, or 999999 when absent.
first_line() { local _n; _n=$(grep -nE -- "$1" "$FX/calls.log" | head -1 | cut -d: -f1); echo "${_n:-999999}"; }
# P2/P5 teardown: umount (if mounted) -> dmsetup remove -> losetup -d, in that order; no --setrw;
# no transient device left. $1 = 1 when a mount had succeeded.
teardown_ok() {
  local _m=$1 _u _r _d
  _u=$(first_line '^umount\|'); _r=$(first_line '^dmsetup\|remove'); _d=$(first_line '^losetup\|-d')
  if [ "$_m" = 1 ]; then [ "$_u" -lt "$_r" ] || { echo 1; return; }; fi
  [ "$_r" -lt "$_d" ] && [ "$_d" -lt 999999 ] || { echo 1; return; }
  grep -q -- '--setrw' "$FX/calls.log" && { echo 1; return; }
  echo 0
}
# fatal_row <tag> <reason-substring> <mounted:0|1|-> — the shared assertions of a FATAL arm: the
# named FATAL, no marker, stage=bootstrap, no residue verdict, and (unless '-') a complete teardown.
fatal_row() {
  local _t="$1" _why="$2" _m="$3"
  ok "$((RC == 0))" "$_t is FATAL (rc=$RC)" "$(cat "$FX/err")"
  ok "$(fatal_is "$_why")" "$_t FATAL: $_why" "$(cat "$FX/err")"
  ok "$(marker_absent)" "$_t no marker was written"
  ok "$(emit_stage_bootstrap)" "$_t the FATAL was emitted at stage=bootstrap" "$(cat "$FX/emit.log")"
  ok "$(absent_in plaintext_residue "$FX/err")" "$_t no residue verdict" "$(cat "$FX/err")"
  if [ "$_m" != - ]; then
    ok "$(teardown_ok "$_m")" "$_t teardown ran umount -> dmsetup remove -> losetup -d, never --setrw" "$(cat "$FX/calls.log")"
  fi
}

# --- R1: plaintext verified empty through the snapshot -> marker + every boolean yes ----------
new_fixture r1-verified-empty
run_unit "$UNIT"
ok "$((RC != 0))" "R1 the all-pass path exits 0 (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_volume)" = present ]; echo $?)" "R1 plaintext_volume=present"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R1 plaintext_empty=yes"
ok "$([ "$(field plaintext_journal)" = clean ]; echo $?)" "R1 plaintext_journal=clean (the origin carried no needs_recovery)"
ok "$([ "$(field fence_on_mapper)" = yes ]; echo $?)" "R1 fence_on_mapper=yes"
ok "$([ "$(field erasure_probe)" = yes ]; echo $?)" "R1 erasure_probe=yes"
ok "$([ "$(field served_repos)" = 0 ]; echo $?)" "R1 served_repos=0"
ok "$([ "$(marker)" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]; echo $?)" \
  "R1 the marker holds exactly the mapper filesystem UUID (contract C2)" "$(marker)"
ok "$([ "$(stat -c %a "$FX/etc/git-data/store-verified" 2>/dev/null)" = 644 ]; echo $?)" "R1 the marker is mode 0644"
ok "$([ "$(wc -l < "$FX/etc/git-data/store-verified")" -eq 1 ]; echo $?)" "R1 the marker is exactly one line"
ok "$(grep -qxF 'ro,errors=remount-ro,nosuid,nodev,noexec' "$FX/mount_opts"; echo $?)" \
  "R1 the snapshot mount carried -o ro,errors=remount-ro,nosuid,nodev,noexec (no noload)" "$(cat "$FX/mount_opts" 2>/dev/null)"
ok "$([ "$(cat "$FX/mount_source" 2>/dev/null)" = "$FX/dev/mapper/git-data-pt-snap" ]; echo $?)" \
  "R1 the mounted SOURCE is the snapshot, never the origin" "$(cat "$FX/mount_source" 2>/dev/null)"
ok "$(grep -qxF "dmsetup|create git-data-pt-snap --table 0 20971520 snapshot $FX/dev/vol /dev/loop77 N 8" "$FX/calls.log"; echo $?)" \
  "R1 the snapshot table stacks the resolved origin node over the COW loop, non-persistent, no feature args" "$(grep dmsetup "$FX/calls.log")"
ok "$(grep -qE "^losetup\|--find --show $FX/shm/[^/]+/cow\$" "$FX/calls.log"; echo $?)" \
  "R1 the COW loop is backed by <mktemp -d -p /dev/shm>/cow" "$(grep losetup "$FX/calls.log")"
ok "$([ -e "$FX/ro_set" ]; echo $?)" "R1 the origin was set kernel read-only"
ok "$(teardown_ok 1)" "R1 teardown ran umount -> dmsetup remove -> losetup -d, never --setrw" "$(cat "$FX/calls.log")"
ok "$([ ! -e "$FX/loop_up" ] && [ ! -e "$FX/dev/mapper/git-data-pt-snap" ] && [ -z "$(ls -A "$FX/shm")" ]; echo $?)" \
  "R1 no COW loop, snapshot node or /dev/shm directory survives" "$(ls -A "$FX/shm")"
# P2 ORDER (REORDER, not presence): isLuks < setro < the first dmsetup create < the first mount.
_i=$(first_line '^cryptsetup\|isLuks'); _s=$(first_line '^blockdev\|--setro'); _c=$(first_line '^dmsetup\|create'); _m=$(first_line '^mount\|')
ok "$([ "$_i" -lt "$_s" ] && [ "$_s" -lt "$_c" ] && [ "$_s" -lt "$_m" ] && [ "$_m" -lt 999999 ]; echo $?)" \
  "R1 calls.log order: isLuks ($_i) < setro ($_s) < dmsetup create ($_c), mount ($_m)"
# Guard 1 mutation 7's row: every call that names the origin node is on the allowlist, and every
# one except the two read-only identity probes comes after --setro.
_bad=0
while IFS= read -r _l; do
  _no="${_l%%:*}"; _c="${_l#*:}"
  case "$_c" in
    "stat|-L -c %F $FX/dev/vol"|"cryptsetup|isLuks $FX/dev/vol") [ "$_no" -lt "$_s" ] || _bad=1 ;;
    "blockdev|--setro $FX/dev/vol"|"blockdev|--getro $FX/dev/vol"|"dumpe2fs|-h $FX/dev/vol"|"blockdev|--getsz $FX/dev/vol") [ "$_no" -ge "$_s" ] || _bad=1 ;;
    "dmsetup|create git-data-pt-snap --table 0 20971520 snapshot $FX/dev/vol /dev/loop77 N 8") [ "$_no" -gt "$_s" ] || _bad=1 ;;
    *) _bad=1; echo "      off-allowlist opener: $_c" >&2 ;;
  esac
done < <(grep -nF "$FX/dev/vol" "$FX/calls.log")
ok "$_bad" "R1 every call naming the origin node is allowlisted and ordered after --setro (Guard 1 row 7)" "$(grep -F "$FX/dev/vol" "$FX/calls.log")"
ok "$(grep -q '^umount|' "$FX/calls.log"; echo $?)" "R1 the snapshot was unmounted"
ok "$(grep -q '^remove|' "$FX/calls.log"; echo $?)" "R1 the erasure probe ran the remove wrapper for real"
ok "$([ -z "$(cat "$FX/emit.log")" ]; echo $?)" "R1 no fatal was emitted on the all-pass path" "$(cat "$FX/emit.log")"
# The probe's lock dotfile exists and is invisible to the count — both halves, so the row
# cannot pass because the file was never created.
ok "$([ -e "$FX/store/repositories/.boot-probe-0.init.lock" ]; echo $?)" "R1 the probe left its 0-byte lock dotfile"
ok "$([ "$(field served_repos)" = 0 ]; echo $?)" "R1 served_repos stays 0 with that dotfile present"
# The probe's environment: pinned, and carrying nothing of the caller's.
ok "$(grep -qxF 'SSH_ORIGINAL_COMMAND=boot-probe-0' "$FX/probe.env"; echo $?)" "R1 the probe passed SSH_ORIGINAL_COMMAND=boot-probe-0"
ok "$(grep -qxF 'PATH=/usr/bin:/bin' "$FX/probe.env"; echo $?)" "R1 the probe pinned PATH=/usr/bin:/bin"
ok "$(absent_in GIT_DATA_LUKS_KEY "$FX/runuser.env")" "R1 GIT_DATA_LUKS_KEY is NOT in the runuser stub's environment" "$(grep GIT_DATA "$FX/runuser.env" || true)"
ok "$(absent_in GIT_DATA_LUKS_KEY "$FX/probe.env")" "R1 GIT_DATA_LUKS_KEY is NOT in the probe child's environment" "$(grep GIT_DATA "$FX/probe.env" || true)"
ok "$(absent_in "$LEAK_KEY" "$FX/probe.env" "$FX/runuser.env" "$FX/calls.log")" \
  "R1 the passphrase VALUE appears in no probe artifact"

# --- R2: no plaintext volume attached -------------------------------------------------
new_fixture r2-volume-absent
PT_ID=""
run_unit "$UNIT"
PT_ID="100000001"
ok "$((RC != 0))" "R2 an absent plaintext volume is not a failure (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_volume)" = absent ]; echo $?)" "R2 plaintext_volume=absent"
ok "$([ "$(field plaintext_journal)" = absent ]; echo $?)" "R2 plaintext_journal=absent"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R2 plaintext_empty=yes"
ok "$(absent_in '^mount|\|^blockdev|\|^dmsetup|' "$FX/calls.log")" "R2 nothing was mounted, set read-only or mapped"
ok "$([ -n "$(marker)" ]; echo $?)" "R2 the marker is still written on the absent path"

# --- R2b: a volume with no repositories/ directory at all (must-PASS, non-canonical) ---
new_fixture r2b-no-repositories-dir
rm -rf "$FX/ptsrc/repositories"
run_unit "$UNIT"
ok "$((RC != 0))" "R2b a plaintext volume without repositories/ passes (count 0, rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R2b plaintext_empty=yes"

# --- R3: a no-op mount, adjudicated by the REAL findmnt --------------------------------
# The mount "succeeds" and leaves an empty directory. A count alone reads 0 and clears the
# volume; only the SOURCE check catches it. Driven with the real findmnt against a path that is
# not a mountpoint, so the stub cannot be what makes the row pass.
if command -v findmnt >/dev/null 2>&1; then
  new_fixture r3-noop-mount
  rm -f "$FX/bin/findmnt"
  : > "$FX/mount_noop"
  run_unit "$UNIT"
  fatal_row R3 'plaintext_unverified reason=source' 1
else
  for _k in 1 2 3 4 5 6; do ok 0 "R3 SKIPPED — findmnt(8) absent, the real-instrument row cannot run"; done
fi

# --- R3b: the snapshot mount itself fails ----------------------------------------------
new_fixture r3b-mount-failed
: > "$FX/mount_fail"
run_unit "$UNIT"
fatal_row R3b 'plaintext_unverified reason=mount' 0

# --- R3c/R3d/R3e: teardown failures are reason=umount, and every later step is still tried --
new_fixture r3c-umount-failed
: > "$FX/umount_fail"
run_unit "$UNIT"
fatal_row R3c 'plaintext_unverified reason=umount' -
ok "$(grep -q '^dmsetup|remove' "$FX/calls.log" && grep -q '^losetup|-d' "$FX/calls.log"; echo $?)" \
  "R3c after a failed umount, dmsetup remove and losetup -d were still attempted (collect-then-exit)"
ok "$(compgen -G "$FX/shm/*/mnt" >/dev/null; echo $?)" \
  "R3c the still-mounted directory was NOT removed (no rm over a mounted tree)"
new_fixture r3d-dm-remove-failed
: > "$FX/dm_remove_fail"
run_unit "$UNIT"
fatal_row R3d 'plaintext_unverified reason=umount' -
ok "$(grep -q '^losetup|-d' "$FX/calls.log"; echo $?)" "R3d losetup -d was still attempted after dmsetup remove failed"
new_fixture r3e-losetup-d-failed
: > "$FX/losetup_d_fail"
run_unit "$UNIT"
fatal_row R3e 'plaintext_unverified reason=umount' -

# --- R4: a dirty journal is no longer FATAL: it replays into the COW -------------------
new_fixture r4a-dirty-empty
: > "$FX/dumpe2fs_dirty"
run_unit "$UNIT"
ok "$((RC != 0))" "R4a a dirty origin with an empty post-replay tree PASSES (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_journal)" = dirty ]; echo $?)" "R4a plaintext_journal=dirty"
ok "$([ -n "$(marker)" ]; echo $?)" "R4a the marker is written"
ok "$(teardown_ok 1)" "R4a teardown complete"

new_fixture r4b-dirty-residue
: > "$FX/dumpe2fs_dirty"
mkdir -p "$FX/ptsrc/repositories/ws-1.git"
run_unit "$UNIT"
ok "$((RC == 0))" "R4b a dirty origin whose replayed tree holds a repo is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_residue count=1')" "R4b plaintext_residue count=1 (the post-replay tree was counted)" "$(cat "$FX/err")"
ok "$(marker_absent)" "R4b no marker was written"
ok "$(teardown_ok 1)" "R4b teardown ran before the residue verdict"

new_fixture r4c-snapshot-still-dirty
: > "$FX/dumpe2fs_dirty"
: > "$FX/snap_still_dirty"
mkdir -p "$FX/ptsrc/repositories/ws-1.git"
run_unit "$UNIT"
fatal_row R4c 'plaintext_unverified reason=journal' 1

# --- R5: a non-empty plaintext volume ---------------------------------------------------
new_fixture r5-residue-bare-repo
mkdir -p "$FX/ptsrc/repositories/ws-1.git"
run_unit "$UNIT"
ok "$((RC == 0))" "R5 a bare repo on the plaintext volume is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_residue count=1')" "R5 plaintext_residue count=1" "$(cat "$FX/err")"
ok "$(marker_absent)" "R5 no marker was written"
ok "$(emit_stage_bootstrap)" "R5 the FATAL was emitted at stage=bootstrap" "$(cat "$FX/emit.log")"

# --- R5b: a PARTIAL entry, not a *.git --------------------------------------------------
new_fixture r5b-residue-partial
mkdir -p "$FX/ptsrc/repositories/x"
run_unit "$UNIT"
ok "$((RC == 0))" "R5b a partial repositories/x is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_residue count=1')" "R5b plaintext_residue count=1" "$(cat "$FX/err")"
ok "$(marker_absent)" "R5b no marker was written"

# --- R5c: the two excluded names are NOT residue ----------------------------------------
new_fixture r5c-excluded-names
: > "$FX/ptsrc/repositories/.ws-1.init.lock"
mkdir -p "$FX/ptsrc/repositories/lost+found"
run_unit "$UNIT"
ok "$((RC != 0))" "R5c a lock dotfile and lost+found are not residue (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R5c plaintext_empty=yes"

# --- R9: reason=source — the origin is not ours to touch ---------------------------------
new_fixture r9a-not-block
: > "$FX/pt_not_block"
run_unit "$UNIT"
fatal_row R9a 'plaintext_unverified reason=source' -
ok "$(absent_in '^blockdev|' "$FX/calls.log")" "R9a nothing was set read-only"
new_fixture r9b-is-luks
: > "$FX/pt_is_luks"
run_unit "$UNIT"
fatal_row R9b 'plaintext_unverified reason=source' -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R9b a LUKS device is never set read-only (it may sit under the live mapper)"
new_fixture r9c-holders
: > "$FX/sys/class/block/vol/holders/dm-0"
run_unit "$UNIT"
fatal_row R9c 'plaintext_unverified reason=source' -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R9c a device with holders is never set read-only"

# --- R10: reason=snapshot — the read-only flag or the snapshot apparatus ------------------
new_fixture r10a-setro-fails
: > "$FX/setro_fail"
run_unit "$UNIT"
fatal_row R10a 'plaintext_unverified reason=snapshot' -
ok "$(absent_in '^dmsetup|create\|^mount|' "$FX/calls.log")" "R10a no snapshot was created and nothing mounted"
new_fixture r10b-getro-zero
: > "$FX/getro_zero"
run_unit "$UNIT"
fatal_row R10b 'plaintext_unverified reason=snapshot' -
ok "$(absent_in '^dmsetup|create\|^mount|' "$FX/calls.log")" "R10b a read-back of 0 stops before any snapshot"
new_fixture r10c-geometry
: > "$FX/geometry_bad"
run_unit "$UNIT"
fatal_row R10c 'plaintext_unverified reason=snapshot' -
ok "$(absent_in '^losetup|' "$FX/calls.log")" "R10c an unparseable journal geometry is never replaced by a default COW size"
new_fixture r10d-losetup-fails
: > "$FX/losetup_fail"
run_unit "$UNIT"
fatal_row R10d 'plaintext_unverified reason=snapshot' -
ok "$([ -z "$(ls -A "$FX/shm")" ]; echo $?)" "R10d the /dev/shm directory was cleaned up"
new_fixture r10e-create-fails
: > "$FX/dm_create_fail"
run_unit "$UNIT"
fatal_row R10e 'plaintext_unverified reason=snapshot' -
ok "$(absent_in '^dmsetup|remove' "$FX/calls.log")" "R10e a create that failed (e.g. a taken name) never removes a device this run did not create"
ok "$(grep -q '^losetup|-d' "$FX/calls.log"; echo $?)" "R10e the COW loop was still released"
new_fixture r10f-invalid
: > "$FX/dm_invalid"
run_unit "$UNIT"
fatal_row R10f 'plaintext_unverified reason=snapshot' 1
new_fixture r10g-kernel-ro-write
printf '[   12.345678] Trying to write to read-only block-device vol (partno 0)\n' > "$FX/klog_extra"
run_unit "$UNIT"
fatal_row R10g 'plaintext_unverified reason=snapshot' 1
new_fixture r10h-classifier
: > "$FX/dm_invalid"
printf '[   12.3] device-mapper: snapshots: Invalidating snapshot: Unable to allocate exception.\n' > "$FX/klog_extra"
run_unit "$UNIT"
ok "$(grep -qF 'kernel=overflow cow=Invalid' "$FX/err"; echo $?)" "R10h the FATAL carries a classifier word and the dm status, not raw kernel lines" "$(cat "$FX/err")"
ok "$(absent_in 'Unable to allocate' "$FX/err")" "R10h no raw kernel line reaches the FATAL detail"

# --- R11: reason=journal — the replay did not produce a trustworthy tree ------------------
new_fixture r11a-errors-after-mount
printf '3\n3\n' > "$FX/errors_seq"
run_unit "$UNIT"
fatal_row R11a 'plaintext_unverified reason=journal' 1
new_fixture r11b-errors-rise
printf '0\n1\n' > "$FX/errors_seq"
run_unit "$UNIT"
fatal_row R11b 'plaintext_unverified reason=journal' 1
new_fixture r11c-with-errors
: > "$FX/snap_with_errors"
run_unit "$UNIT"
fatal_row R11c 'plaintext_unverified reason=journal' 1
new_fixture r11d-errors-unreadable
: > "$FX/errors_seq"
run_unit "$UNIT"
fatal_row R11d 'plaintext_unverified reason=journal' 1

# --- R6: unknown content on the SERVED store --------------------------------------------
new_fixture r6-luks-residue
mkdir -p "$FX/store/repositories/ws-9.git"
run_unit "$UNIT"
ok "$((RC == 0))" "R6 luks_residue is FATAL, not informational (rc=$RC)"
ok "$(fatal_is 'luks_residue count=1')" "R6 luks_residue count=1" "$(cat "$FX/err")"
ok "$(marker_absent)" "R6 no marker was written"
ok "$(absent_in '^remove|' "$FX/calls.log")" "R6 the count ran BEFORE the probe could add its dotfile"

# --- R7: the fence is not on the mapper --------------------------------------------------
new_fixture r7-fence-off-mapper
printf '/dev/sda1\n' > "$FX/fence_source"
run_unit "$UNIT"
ok "$((RC == 0))" "R7 a fence off the mapper is FATAL (rc=$RC)"
ok "$(fatal_is 'fence_on_mapper=no')" "R7 fence_on_mapper=no" "$(cat "$FX/err")"
ok "$(marker_absent)" "R7 no marker was written"

# --- R8: the erasure probe refuses --------------------------------------------------------
new_fixture r8-probe-refuses
: > "$FX/probe_refuse"
run_unit "$UNIT"
ok "$((RC == 0))" "R8 a refusing erasure wrapper is FATAL (rc=$RC)"
ok "$(fatal_is 'erasure_probe=no')" "R8 erasure_probe=no" "$(cat "$FX/err")"
ok "$(marker_absent)" "R8 the marker written before the probe was REMOVED on its failure"
ok "$(emit_stage_bootstrap)" "R8 the FATAL was emitted at stage=bootstrap" "$(cat "$FX/emit.log")"

# =====================================================================================
# GUARD 2 MUTATION MATRIX — rows 1, 2, 3, 5, 7. Each must RED.
# =====================================================================================
MUT=""
MUT_RC=0
# NOT called through `$( … )`: a command substitution is a subshell, so the $MUT it set would be
# lost and every mutation row would silently run `sed` on an empty path. MUT_RC is the
# landed-check — a mutant byte-identical to the pristine unit certifies nothing.
mutate() { # $1 = name, $2 = sed -E expression
  MUT="$SCRATCH/mut.$1"
  sed -E "$2" "$UNIT" > "$MUT"
  if cmp -s "$UNIT" "$MUT"; then MUT_RC=1; else MUT_RC=0; fi
}

# Row 1 — the plaintext mount fails (empty directory) and the count reads 0. Dropping the
# SOURCE check is exactly the defect: the count alone certifies an empty directory as an empty
# volume. Instrument self-test first, on a source MISMATCH the stub can produce deterministically.
new_fixture m1-source-check
printf '%s\n' "$FX/dev/other" > "$FX/pt_source"
run_unit "$UNIT"
ok "$(fatal_is 'plaintext_unverified reason=source')" "M1 instrument: the pristine unit FATALs on a source mismatch" "$(cat "$FX/err")"
mutate m1 's/if \[ -z "\$_pt_got" \] \|\| \[ "\$_pt_got" != "\$_pt_want" \]; then/if false; then/'
ok "$MUT_RC" \
  "M1 the mutation landed (the source check was removed)"
run_unit "$MUT"
ok "$((RC != 0))" "M1 ROW 1: without the source check a mismatched mount is certified clean (rc=$RC) — the arm is live"
ok "$([ -n "$(marker)" ]; echo $?)" "M1 ROW 1: and the mutant writes the marker on an unverified volume"

# Row 2 — the count matches only *.git while the fixture holds a partial repositories/x.
new_fixture m2-count-glob
mkdir -p "$FX/ptsrc/repositories/x"
run_unit "$UNIT"
ok "$(fatal_is 'plaintext_residue count=1')" "M2 instrument: the pristine unit counts a partial repositories/x" "$(cat "$FX/err")"
mutate m2 "s/! -name '\\.\\*\\.init\\.lock' ! -name lost\\+found/-name '*.git'/"
ok "$MUT_RC" \
  "M2 the mutation landed (the count narrowed to *.git)"
run_unit "$MUT"
ok "$((RC != 0))" "M2 ROW 2: a *.git-only count clears a volume holding repositories/x (rc=$RC) — the arm is live"

# Row 3 — erasure_probe skips the real wrapper call. A refusing wrapper must still yield `no`.
new_fixture m3-probe-skipped
: > "$FX/probe_refuse"
run_unit "$UNIT"
ok "$(fatal_is 'erasure_probe=no')" "M3 instrument: the pristine unit FATALs against a refusing wrapper" "$(cat "$FX/err")"
mutate m3 's#^_probe_err="\$\(env -i .*$#_probe_err="remote: git-data remove: not present (no-op)"#'
ok "$MUT_RC" \
  "M3 the mutation landed (the probe no longer calls the wrapper)"
run_unit "$MUT"
ok "$((RC != 0))" "M3 ROW 3: a skipped probe passes against a refusing wrapper (rc=$RC) — the arm is live"
ok "$(absent_in '^remove|' "$FX/calls.log")" "M3 ROW 3: and the mutant never ran the wrapper at all"

# Row 5 — the marker is written before step 2 (an order row).
new_fixture m5-marker-order
mkdir -p "$FX/ptsrc/repositories/ws-1.git"
run_unit "$UNIT"
ok "$(marker_absent)" "M5 instrument: the pristine unit leaves no marker when step 2 FATALs"
mutate m5 's#^rm -f "\$STORE_VERIFIED"$#&\ninstall -d -m0755 -o root -g root "$(dirname "$STORE_VERIFIED")"\nprintf "premature\\\\n" > "$STORE_VERIFIED"#'
ok "$MUT_RC" \
  "M5 the mutation landed (a marker write moved ahead of step 2)"
run_unit "$MUT"
ok "$([ -n "$(marker)" ]; echo $?)" "M5 ROW 5: an early marker survives the step-2 FATAL (marker='$(marker)') — the arm is live"

# Row 7 — the probe runs without `env -i`, so the git-uid process inherits GIT_DATA_LUKS_KEY.
new_fixture m7-env-i
run_unit "$UNIT"
ok "$(absent_in "$LEAK_KEY" "$FX/probe.env")" "M7 instrument: the pristine unit hands the probe no passphrase"
mutate m7 's#env -i PATH=/usr/bin:/bin SSH_ORIGINAL_COMMAND=boot-probe-0 ##'
ok "$MUT_RC" \
  "M7 the mutation landed (env -i removed from the probe)"
run_unit "$MUT"
ok "$(grep -q "$LEAK_KEY" "$FX/probe.env" && grep -q "$LEAK_KEY" "$FX/runuser.env"; echo $?)" \
  "M7 ROW 7: without env -i the passphrase reaches the git-uid process — the arm is live"

# =====================================================================================
# GUARD 1 MUTATION MATRIX (#5274 Phase 3) — rows 1, 2, 3, 5, 6, 7, 9, 10 here; row 4 (noload +
# no post-check) and the COW overflow run in git-data-plaintext-snapshot-loopback.test.sh, which
# needs a real kernel. Each mutant carries a landed-check, and each row first proves the pristine
# unit gives the opposite verdict against the same fixture.
# =====================================================================================
# mutate_py <name> <old> <new> — replace exactly one occurrence of <old>; MUT_RC=1 if it did not land.
mutate_py() {
  MUT="$SCRATCH/mut.$1"
  if python3 - "$UNIT" "$MUT" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(1)
open(dst, "w").write(s.replace(old, new))
PY
  then
    if cmp -s "$UNIT" "$MUT"; then MUT_RC=1; else MUT_RC=0; fi
  else
    MUT_RC=1
  fi
}
order_holds() {
  local _i _s _c _m
  _i=$(first_line '^cryptsetup\|isLuks'); _s=$(first_line '^blockdev\|--setro'); _c=$(first_line '^dmsetup\|create'); _m=$(first_line '^mount\|')
  [ "$_i" -lt "$_s" ] && [ "$_s" -lt "$_c" ] && [ "$_s" -lt "$_m" ] && [ "$_m" -lt 999999 ]; echo $?
}

# G1 row 1 — delete blockdev --setro. The --getro stub answers from behaviour, so the read-back fails.
new_fixture g1-setro-deleted
mutate_py g1 '  if ! blockdev --setro "$_pt_dev" || ' '  if false || '
ok "$MUT_RC" "G1-1 the mutation landed (blockdev --setro removed)"
run_unit "$MUT"
ok "$(fatal_is 'plaintext_unverified reason=snapshot')" "G1-1 ROW 1: without --setro the read-back refuses (reason=snapshot) — the arm is live" "$(cat "$FX/err")"
ok "$(marker_absent)" "G1-1 ROW 1: and no marker is written"

# G1 row 2 — REORDER: --setro moved after dmsetup create (presence is not order).
new_fixture g1-setro-reordered
_SETRO_BLOCK='  if ! blockdev --setro "$_pt_dev" || [ "$(blockdev --getro "$_pt_dev" 2>/dev/null || true)" != 1 ]; then
    log "FATAL: plaintext_unverified reason=snapshot — $_pt_dev could not be made kernel read-only"
    exit 1
  fi
'
mutate_py g1r "$_SETRO_BLOCK" ''
if [ "$MUT_RC" = 0 ]; then
  cp "$MUT" "$SCRATCH/mut.g1r.stage1"
  UNIT_SAVED="$UNIT"; UNIT="$SCRATCH/mut.g1r.stage1"
  mutate_py g1r2 '  _pt_snap_up=1
' "  _pt_snap_up=1
$_SETRO_BLOCK"
  UNIT="$UNIT_SAVED"
fi
ok "$MUT_RC" "G1-2 the mutation landed (--setro moved after dmsetup create)"
run_unit "$MUT"
ok "$(( $(order_holds) == 0 ))" "G1-2 ROW 2: the calls.log order row reds on the reordered unit — the arm is live" "$(cat "$FX/calls.log")"

# G1 row 3 — mount the ORIGIN instead of the snapshot.
new_fixture g1-mount-origin
mutate_py g1m 'noexec "/dev/mapper/$_pt_snap" "$_pt_mnt"' 'noexec "$_pt_dev" "$_pt_mnt"'
ok "$MUT_RC" "G1-3 the mutation landed (the mount source is the origin)"
run_unit "$MUT"
ok "$([ "$(cat "$FX/mount_source" 2>/dev/null)" != "$FX/dev/mapper/git-data-pt-snap" ]; echo $?)" \
  "G1-3 ROW 3: the mount-source row reds when the origin is mounted — the arm is live"

# G1 row 5 — drop the post-replay needs_recovery check: a still-dirty snapshot is then counted.
new_fixture g1-no-postcheck
: > "$FX/dumpe2fs_dirty"; : > "$FX/snap_still_dirty"; mkdir -p "$FX/ptsrc/repositories/ws-1.git"
mutate_py g1p '  if _pt_has_nr "$_pt_ssb"; then' '  if false; then'
ok "$MUT_RC" "G1-5 the mutation landed (post-replay check removed)"
run_unit "$MUT"
ok "$(( $(fatal_is 'plaintext_unverified reason=journal') == 0 ))" "G1-5 ROW 5: without the post-check the stale tree is counted instead of refused — the arm is live" "$(cat "$FX/err")"

# G1 row 6 — drop dmsetup remove from the teardown.
new_fixture g1-no-remove
mutate_py g1d 'if dmsetup remove --retry "$_pt_snap" >/dev/null 2>&1; then' 'if true; then'
ok "$MUT_RC" "G1-6 the mutation landed (dmsetup remove removed)"
run_unit "$MUT"
ok "$(( $(teardown_ok 1) == 0 ))" "G1-6 ROW 6: the teardown-order row reds when the snapshot is not removed — the arm is live"
ok "$([ -e "$FX/dev/mapper/git-data-pt-snap" ]; echo $?)" "G1-6 ROW 6: and the snapshot node survives"

# G1 row 7 — a SECOND opener of the origin after a compliant first.
new_fixture g1-second-opener
mutate_py g1o '  _pt_e1="$(_pt_errs || true)"' '  mount -o ro,noload "$_pt_dev" "$_pt_mnt" 2>/dev/null || true
  _pt_e1="$(_pt_errs || true)"'
ok "$MUT_RC" "G1-7 the mutation landed (a second mount of the origin)"
run_unit "$MUT"
_bad=0
while IFS= read -r _l; do
  case "${_l#*:}" in
    "stat|-L -c %F $FX/dev/vol"|"cryptsetup|isLuks $FX/dev/vol"|"blockdev|--setro $FX/dev/vol"|"blockdev|--getro $FX/dev/vol"|"dumpe2fs|-h $FX/dev/vol"|"blockdev|--getsz $FX/dev/vol"|"dmsetup|create git-data-pt-snap --table 0 20971520 snapshot $FX/dev/vol /dev/loop77 N 8") : ;;
    *) _bad=1 ;;
  esac
done < <(grep -nF "$FX/dev/vol" "$FX/calls.log")
ok "$((_bad == 0))" "G1-7 ROW 7: the origin allowlist row reds on the second opener — the arm is live"

# G1 row 9 — drop the errors_count check: a checksum-skipped directory block yields a short count.
new_fixture g1-no-errors-check
printf '0\n1\n' > "$FX/errors_seq"
mutate_py g1e '  [ "$_pt_e1" = 0 ] || {' '  true || {'
ok "$MUT_RC" "G1-9 the mutation landed (the post-count errors_count check removed)"
run_unit "$MUT"
ok "$((RC != 0))" "G1-9 ROW 9: without it a count that raised an ext4 error PASSES (rc=$RC) — the arm is live"

# G1 row 10 — a feature argument on the dm table.
mutate_py g1t 'snapshot $_pt_dev $_pt_loop N 8"' 'snapshot $_pt_dev $_pt_loop N 8 1 discard_passdown_origin"'
ok "$MUT_RC" "G1-10 the mutation landed (discard_passdown_origin added)"
ok "$(( MUT_RC != 0 || $(grep -qF 'dmsetup create "$_pt_snap" --table "0 $_pt_sz snapshot $_pt_dev $_pt_loop N 8"' "$MUT"; echo $?) == 0 ))" \
  "G1-10 ROW 10: the table-literal row (S6d) reds on the mutant — the arm is live"

# =====================================================================================
# Instrument self-test + floor
# =====================================================================================
_can_p0=$passes; _can_f0=$fails
pass
fail "CANARY — instrument self-test, not a real failure" 2>/dev/null
if [ "$passes" -ne $((_can_p0 + 1)) ] || [ "$fails" -ne $((_can_f0 + 1)) ]; then
  echo "FAIL CANARY: pass()/fail() did not each move their counter by one" >&2
  exit 1
fi
passes=$_can_p0; fails=$_can_f0

# ADR-193 §2/§3: the floor is checked against the CALL-SITE counter (`cases`, bumped by ok()
# before either verdict helper runs), and the two counts must agree — a verdict counter alone
# cannot see a call site that never reached a verdict. The two bindings sit DIRECTLY above the
# `if` with no comment between: guard-vacuity-floor builds its mutant from the floor block plus
# the contiguous simple assignments above it, and a comment breaks the run.
MIN_ASSERTIONS=279
total=$((passes + fails))
if [ "$cases" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL: ran only %s assertion call sites (floor %s) — suite did not execute fully\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ "$cases" -ne "$total" ]; then
  printf 'FAIL: call sites (%s) and verdicts (%s) disagree — an ok() reached neither pass nor fail\n' "$cases" "$total" >&2
  exit 1
fi
echo "git-data-bootstrap-store-verify: ${passes} passed, ${fails} failed (${total} assertions)"
exit $(( fails > 0 ))
