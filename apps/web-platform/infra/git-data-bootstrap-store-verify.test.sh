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
#             ext4's errors_count), find (marks "counted"), rm, install and runuser. Every stub
#             refuses (exit 64) an operand other than the fixture's own, and e2fsck, fsck,
#             tune2fs, debugfs, mkfs*, wipefs, dd and friends are catch-all stubs that only log
#             and refuse, so any of them naming the origin reds the allowlist row. The seams the bootstrap honours
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
# The pass-through stubs delegate by absolute path, resolved HERE, before the stub dir leads PATH.
REAL_FIND="$(command -v find || true)"; REAL_RM="$(command -v rm || true)"
REAL_STAT="$(command -v stat || true)"; REAL_CAT="$(command -v cat || true)"
for _t in "$REAL_FIND" "$REAL_RM" "$REAL_STAT" "$REAL_CAT"; do
  case "$_t" in /*) : ;; *) echo "FAIL: find/rm/stat/cat not all on PATH — the pass-through stubs cannot delegate" >&2; exit 1 ;; esac
done

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
PT_BODY="$SCRATCH/pt.body"
awk '$0=="# ---- BEGIN plaintext-count unit ----"{f=1;next} $0=="# ---- END plaintext-count unit ----"{f=0} f' "$UNIT" > "$SCRATCH/pt.unit"
strip "$SCRATCH/pt.unit" > "$PT_BODY"
n=$(grep -c . "$PT_BODY" || true)
ok "$((n < 80))" "S9f the plaintext-count unit was extracted (got $n comment-stripped lines; floor 80)"
# An absolute tool path bypasses every PATH stub below, so a call the stubs would refuse could
# run unobserved. Counted over the comment-stripped plaintext-count unit; the self-test proves the
# pattern can fire before its zero is trusted.
abs_tool_hits() { grep -cE '(^|[[:space:];|&(!`])/(usr/)?s?bin/[A-Za-z0-9._-]+' "$1" || true; }
printf '  /usr/sbin/dmsetup info x\n  x="$(/bin/cat y)"\n' > "$SCRATCH/abs.canary"
ok "$(( $(abs_tool_hits "$SCRATCH/abs.canary") != 2 ))" "S21 instrument: the absolute-tool-path pattern fires on /usr/sbin/dmsetup and /bin/cat"
n=$(abs_tool_hits "$PT_BODY")
ok "$((n != 0))" "S21b no absolute tool path in the plaintext-count unit — it would bypass the PATH stubs (got $n)" "$(grep -nE '(^|[[:space:];|&(!`])/(usr/)?s?bin/' "$PT_BODY")"
# B5 — every wait in the teardown and the create is bounded: a stuck udev cookie hangs dmsetup.
ok "$(grep -qE '^[[:space:]]*udevadm settle --timeout=[0-9]+ ' "$PT_BODY"; echo $?)" "S22 udevadm settle is bounded (--timeout=N)"
ok "$(grep -qE '(^|[[:space:]!])timeout [0-9]+ dmsetup create "\$_pt_snap" ' "$PT_BODY"; echo $?)" "S22b dmsetup create runs under timeout N"
ok "$(grep -qE 'if timeout [0-9]+ dmsetup remove --retry "\$_pt_snap" ' "$PT_BODY"; echo $?)" "S22c dmsetup remove --retry runs under timeout N"
# B8 — the luks_open stage refuses a LUKS volume id equal to the plaintext one: a mis-wired id
# would luksFormat the retained plaintext volume. The guard line is extracted from the template
# and RUN with the two ids substituted, so a guard that exists but cannot refuse reds here.
TEMPLATE="$DIR/cloud-init-git-data.yml"
_luks_guard="$(awk '/<<'"'"'LUKSEOF'"'"'/{f=1} f && /git_data_volume_id/ && /git_data_luks_volume_id/ {print; exit}' "$TEMPLATE")"
ok "$([ -n "$_luks_guard" ]; echo $?)" "S23 the luks_open heredoc carries a guard naming both volume ids"
L_GUARD=$(grep -nF -- "$_luks_guard" "$TEMPLATE" | head -1 | cut -d: -f1)
L_ISLUKS_T=$(grep -nF '_isluks_err="$(cryptsetup isLuks "$DEV" 2>&1)"' "$TEMPLATE" | head -1 | cut -d: -f1)
ok "$([ -n "$L_GUARD" ] && [ -n "$L_ISLUKS_T" ] && [ "$L_GUARD" -lt "$L_ISLUKS_T" ]; echo $?)" \
  "S23b the id guard precedes the isLuks probe and so every luksFormat (guard at ${L_GUARD:-none}, isLuks at ${L_ISLUKS_T:-none})"
run_luks_guard() { # <plaintext id> <luks id> -> the guard's exit status
  local _g="${_luks_guard//\$\{git_data_volume_id\}/$1}"
  _g="${_g//\$\{git_data_luks_volume_id\}/$2}"
  ( export GIT_DATA_LUKS_DETAIL=/dev/null; eval "$_g" ) >/dev/null 2>&1; echo $?
}
ok "$(( $(run_luks_guard 4242 4242) == 0 ))" "S23c the guard REFUSES equal plaintext and LUKS volume ids"
ok "$(run_luks_guard 4242 4343)" "S23d the guard passes distinct ids"
ok "$(run_luks_guard '' 4343)" "S23e the guard passes an absent plaintext volume (empty id)"
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
  { printf '#!/usr/bin/env bash\nFXD=%q\nREAL_INSTALL=%q\nREAL_FIND=%q\nREAL_RM=%q\nREAL_STAT=%q\nREAL_CAT=%q\n' \
      "$FX" "$REAL_INSTALL" "$REAL_FIND" "$REAL_RM" "$REAL_STAT" "$REAL_CAT"; cat; } > "$FX/bin/$1"
  chmod +x "$FX/bin/$1"
}

# The origin's sysfs block-device stat: 17 fields, 7 = sectors written, 14 = sectors discarded.
FX_STAT='120 0 960 10 5 0 40 3 0 10 13 1 0 8 0 4 1'
# The origin's device number as `stat -c %t:%T` prints it (hex): 8:10 is sdb, /sys/dev/block/8:16.
FX_DEVNO_HEX='8:10'
FX_SYSDEV='8:16'

new_fixture() {
  FX="$SCRATCH/fx.$1"
  assert_fixture_dir "$FX"
  rm -rf "$FX"
  mkdir -p "$FX/bin" "$FX/store/repositories" "$FX/store/hooks" "$FX/ptsrc/repositories" "$FX/dev/mapper" "$FX/tmp" "$FX/shm" "$FX/sys/dev/block/$FX_SYSDEV/holders"
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  : > "$FX/store/hooks/pre-receive"
  chmod 0755 "$FX/store/hooks/pre-receive"
  : > "$FX/dev/vol"
  : > "$FX/dev/other"
  ln -sfn "$FX/dev/vol" "$FX/dev/by-id"
  printf '%s\n' "$FX_STAT" > "$FX/sys/dev/block/$FX_SYSDEV/stat"
  printf '%s\n' "$FX_DEVNO_HEX" > "$FX/devnum"
  # findmnt answers, per query kind. The snapshot's mapper node exists only while the dmsetup
  # stub holds it, so the unit's realpath comparison resolves something real on both sides.
  printf '%s\n' "$FX/dev/mapper/git-data-pt-snap" > "$FX/pt_source"
  printf '%s\n' "$STORE_DEV_FIXTURE" > "$FX/fence_source"
  printf '%s\n' "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > "$FX/store_uuid"
  # ext4's errors_count BEFORE and AFTER the count; the find stub's "counted" marker selects which.
  printf '0\n' > "$FX/errs_before"
  printf '0\n' > "$FX/errs_after"
  # The origin superblock's journal geometry and its historical error count (absent = 0).
  printf '4096\n' > "$FX/fx_bs"
  printf '16384\n' > "$FX/fx_jb"

  # The only source it will mount is the snapshot, and the only target a <shm>/mnt directory: any
  # other argv is logged (the allowlist row sees it) and refused. origin_write / origin_discard
  # move the origin's sysfs counters, as a write or discard reaching it through the stack would.
  mkstub mount <<'STUB'
printf 'mount|%s\n' "$*" >> "$FXD/calls.log"
_opts=""; _src=""; _tgt=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) _opts="$2"; shift 2 ;;
    -r|-w|-n) _opts="${_opts:+$_opts,}$1"; shift ;;
    *) if [ -z "$_src" ]; then _src="$1"; else _tgt="$1"; fi; shift ;;
  esac
done
printf '%s\n' "$_opts" > "$FXD/mount_opts"
printf '%s\n' "$_src" > "$FXD/mount_source"
[ "$_src" = "$FXD/dev/mapper/git-data-pt-snap" ] || { printf 'mount-stub: refused source %s\n' "$_src" >&2; exit 64; }
case "$_tgt" in "$FXD"/shm/*/mnt) : ;; *) printf 'mount-stub: refused target %s\n' "$_tgt" >&2; exit 64 ;; esac
[ ! -e "$FXD/mount_fail" ] || exit 32
_sf="$FXD/sys/dev/block/8:16/stat"
if [ -e "$FXD/origin_write" ]; then awk '{$7 += 8; print}' "$_sf" > "$_sf.n" && mv -f "$_sf.n" "$_sf"; fi
if [ -e "$FXD/origin_discard" ]; then awk '{$14 += 8; print}' "$_sf" > "$_sf.n" && mv -f "$_sf.n" "$_sf"; fi
# A no-op mount is the failure this step exists to catch: the target stays an EMPTY DIRECTORY,
# which a count alone reads as "clean".
[ ! -e "$FXD/mount_noop" ] || exit 0
cp -a "$FXD/ptsrc/." "$_tgt/"
STUB

  # Empties ONLY a fixture mount directory; any other operand is refused before the rm.
  mkstub umount <<'STUB'
printf 'umount|%s\n' "$*" >> "$FXD/calls.log"
case "${1:-}" in "$FXD"/shm/*/mnt) : ;; *) printf 'umount-stub: refused operand %s\n' "$*" >&2; exit 64 ;; esac
[ ! -e "$FXD/umount_fail" ] || exit 1
"$REAL_RM" -rf -- "${1:?}"/* "${1:?}"/.[!.]* 2>/dev/null || true
exit 0
STUB

  # Per device: the ORIGIN (dumpe2fs_dirty toggles needs_recovery; geometry_bad drops the journal
  # geometry; fx_errcount is its historical s_error_count) and the SNAPSHOT (snap_still_dirty: the
  # journal did not replay; snap_with_errors). reattach_after_dumpe2fs re-points the device number.
  mkstub dumpe2fs <<'STUB'
printf 'dumpe2fs|%s\n' "$*" >> "$FXD/calls.log"
[ "${1:-}" = -h ] && [ $# -eq 2 ] || { printf 'dumpe2fs-stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
case "$2" in
  "$FXD/dev/mapper/git-data-pt-snap")
    [ ! -e "$FXD/snap_dumpe2fs_fail" ] || exit 1
    if [ -e "$FXD/snap_still_dirty" ]; then
      printf 'Filesystem features:      has_journal ext_attr needs_recovery extent 64bit\n'
    else
      printf 'Filesystem features:      has_journal ext_attr resize_inode extent 64bit\n'
    fi
    if [ -e "$FXD/snap_with_errors" ]; then printf 'Filesystem state:         clean with errors\n'; else printf 'Filesystem state:         clean\n'; fi
    ;;
  "$FXD/dev/vol")
    [ ! -e "$FXD/dumpe2fs_fail" ] || exit 1
    [ ! -e "$FXD/reattach_after_dumpe2fs" ] || echo 8:20 > "$FXD/devnum"
    if [ -e "$FXD/dumpe2fs_dirty" ]; then
      printf 'Filesystem features:      has_journal ext_attr needs_recovery extent 64bit\n'
    else
      printf 'Filesystem features:      has_journal ext_attr resize_inode extent 64bit\n'
    fi
    printf 'Block size:               %s\n' "$("$REAL_CAT" "$FXD/fx_bs")"
    [ ! -s "$FXD/fx_errcount" ] || printf 'FS Error count:           %s\n' "$("$REAL_CAT" "$FXD/fx_errcount")"
    [ -e "$FXD/geometry_bad" ] || printf 'Total journal blocks:     %s\n' "$("$REAL_CAT" "$FXD/fx_jb")"
    ;;
  *) printf 'dumpe2fs-stub: refused operand %s\n' "$2" >&2; exit 64 ;;
esac
STUB

  mkstub findmnt <<'STUB'
printf 'findmnt|%s\n' "$*" >> "$FXD/calls.log"
_op=""; _t=""; _mp=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) _op="$2"; shift 2 ;;
    -T) _t="$2"; shift 2 ;;
    --mountpoint) _mp="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$_op" = UUID ]; then
  [ "$_mp" = "$FXD/store" ] || { printf 'findmnt-stub: refused UUID mountpoint %s\n' "$_mp" >&2; exit 64; }
  _f="$FXD/store_uuid"
elif [ -n "$_t" ]; then
  [ "$_t" = "$FXD/store/hooks/pre-receive" ] || { printf 'findmnt-stub: refused -T %s\n' "$_t" >&2; exit 64; }
  _f="$FXD/fence_source"
else
  case "$_mp" in "$FXD"/shm/*/mnt) : ;; *) printf 'findmnt-stub: refused mountpoint %s\n' "$_mp" >&2; exit 64 ;; esac
  _f="$FXD/pt_source"
fi
[ -s "$_f" ] || exit 1
"$REAL_CAT" "$_f"
STUB

  # The origin (its node, or the by-id link that names it) is a regular file here: `stat -L -c
  # %F` is the unit's block-device test and `stat -L -c %t:%T` its identity pin, answered from
  # $FXD/devnum so a fixture can re-point it mid-run the way a detach and reattach would.
  mkstub stat <<'STUB'
case "${*: -1}" in
  "$FXD/dev/vol"|"$FXD/dev/by-id")
    printf 'stat|%s\n' "$*" >> "$FXD/calls.log"
    case "$*" in
      "-L -c %F "*) if [ -e "$FXD/pt_not_block" ]; then echo 'regular empty file'; else echo 'block special file'; fi ;;
      "-L -c %t:%T "*) "$REAL_CAT" "$FXD/devnum" ;;
      *) printf 'stat-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
    esac
    exit 0 ;;
esac
exec "$REAL_STAT" "$@"
STUB

  mkstub cryptsetup <<'STUB'
printf 'cryptsetup|%s\n' "$*" >> "$FXD/calls.log"
[ "$*" = "isLuks $FXD/dev/vol" ] || { printf 'cryptsetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
[ ! -e "$FXD/reattach_after_isluks" ] || echo 8:20 > "$FXD/devnum"
[ -e "$FXD/pt_is_luks" ]
STUB

  # --getro answers from BEHAVIOUR: 1 only after --setro was really called (Guard 1 mutation 1
  # reds on behaviour, not on a missing line).
  mkstub blockdev <<'STUB'
printf 'blockdev|%s\n' "$*" >> "$FXD/calls.log"
[ $# -eq 2 ] && [ "$2" = "$FXD/dev/vol" ] || { printf 'blockdev-stub: unexpected argv: %s\n' "$*" >&2; exit 64; }
case "$1" in
  --setro) [ ! -e "$FXD/setro_fail" ] || exit 1; : > "$FXD/ro_set"; [ ! -e "$FXD/reattach_after_setro" ] || echo 8:20 > "$FXD/devnum" ;;
  --setrw) rm -f "$FXD/ro_set" ;;
  --getro) if [ -e "$FXD/ro_set" ] && [ ! -e "$FXD/getro_zero" ]; then echo 1; else echo 0; fi ;;
  --getsz) [ -e "$FXD/getsz_bad" ] || echo 20971520 ;;
  *) printf 'blockdev-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  # --find --show records the COW file's size, so the sizing rule is measured, not read back.
  mkstub losetup <<'STUB'
printf 'losetup|%s\n' "$*" >> "$FXD/calls.log"
case "$*" in
  "--find --show $FXD"/shm/*/cow)
    [ ! -e "$FXD/losetup_fail" ] || exit 1
    "$REAL_STAT" -c %s "${*: -1}" > "$FXD/cow_size"; : > "$FXD/loop_up"; echo /dev/loop77 ;;
  "-d /dev/loop77") [ ! -e "$FXD/losetup_d_fail" ] || exit 1; rm -f "$FXD/loop_up" ;;
  *) printf 'losetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  # The only name it answers for is git-data-pt-snap. `info` reports existence (the node, or a
  # dm_stale leftover); `deps` names the origin the table was created over (deps_other: another).
  # dm_invalid: Invalid always; dm_invalid_precount / dm_invalid_postcount: only before / after
  # the find stub's "counted" marker, so each _pt_valid call site is exercised on its own.
  mkstub dmsetup <<'STUB'
printf 'dmsetup|%s\n' "$*" >> "$FXD/calls.log"
_name="${*: -1}"
case "$1" in create) _name="$2" ;; esac
[ "$_name" = git-data-pt-snap ] || { printf 'dmsetup-stub: refused name %s\n' "$_name" >&2; exit 64; }
_hex="$("$REAL_CAT" "$FXD/devnum")"
case "$1" in
  create)
    [ ! -e "$FXD/dm_create_fail" ] || exit 1
    : > "$FXD/dev/mapper/$2"
    [ ! -e "$FXD/dm_create_partial" ] || exit 124
    case "$4" in *" $FXD/dev/vol "*) printf '2 dependencies\t: (7, 77) (%d, %d)\n' "$((16#${_hex%:*}))" "$((16#${_hex#*:}))" > "$FXD/dm_deps" ;; *) printf '2 dependencies\t: (7, 77) (1, 1)\n' > "$FXD/dm_deps" ;; esac
    [ ! -e "$FXD/deps_other" ] || printf '2 dependencies\t: (7, 77) (8, 32)\n' > "$FXD/dm_deps" ;;
  remove) [ ! -e "$FXD/dm_remove_fail" ] || exit 1; rm -f "$FXD/dev/mapper/$_name" ;;
  status)
    _inv=0
    [ ! -e "$FXD/dm_invalid" ] || _inv=1
    [ ! -e "$FXD/dm_invalid_precount" ] || [ -e "$FXD/counted" ] || _inv=1
    [ ! -e "$FXD/dm_invalid_postcount" ] || [ ! -e "$FXD/counted" ] || _inv=1
    if [ "$_inv" = 1 ]; then echo '0 20971520 snapshot Invalid'; else echo '0 20971520 snapshot 16/262144 16'; fi ;;
  info)
    [ -e "$FXD/dev/mapper/$_name" ] || [ -e "$FXD/dm_stale" ] || { echo 'Device does not exist.' >&2; exit 1; }
    case "$*" in *" -o blkdevname "*) echo dm-9 ;; *) echo "Name:              $_name" ;; esac ;;
  deps) [ -e "$FXD/dev/mapper/$_name" ] || exit 1; "$REAL_CAT" "$FXD/dm_deps" ;;
  *) printf 'dmsetup-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;;
esac
STUB

  mkstub udevadm <<'STUB'
printf 'udevadm|%s\n' "$*" >> "$FXD/calls.log"
case "$*" in "settle --timeout="[0-9]*) : ;; *) printf 'udevadm-stub: unexpected argv: %s\n' "$*" >&2; exit 64 ;; esac
STUB

  # The kernel log (DIAGNOSTIC only): a baseline on the first read, then the baseline plus klog_extra.
  mkstub dmesg <<'STUB'
_n=$(( $("$REAL_CAT" "$FXD/dmesg_calls" 2>/dev/null || echo 0) + 1 ))
echo "$_n" > "$FXD/dmesg_calls"
echo '[    0.000000] Linux version fixture'
[ "$_n" -eq 1 ] || [ ! -e "$FXD/klog_extra" ] || "$REAL_CAT" "$FXD/klog_extra"
STUB

  # ext4's errors_count: errs_before until the count has run, errs_after once it has (the find
  # stub's "counted" marker), so the fixture says WHEN an error happened, not which read it is.
  # Only the snapshot's own sysfs node is answered; any other errors_count path is refused.
  mkstub cat <<'STUB'
case "${1:-}" in
  */errors_count)
    printf 'cat|%s\n' "$*" >> "$FXD/calls.log"
    [ "$*" = "$FXD/sys/fs/ext4/dm-9/errors_count" ] || { printf 'cat-stub: refused operand %s\n' "$*" >&2; exit 64; }
    if [ -e "$FXD/counted" ]; then "$REAL_CAT" "$FXD/errs_after"; else "$REAL_CAT" "$FXD/errs_before"; fi
    exit 0 ;;
esac
exec "$REAL_CAT" "$@"
STUB

  # Pass-through, except that the count of the SNAPSHOT's repositories/ drops the marker above.
  mkstub find <<'STUB'
case "${1:-}" in "$FXD"/shm/*/mnt/repositories) : > "$FXD/counted" ;; esac
exec "$REAL_FIND" "$@"
STUB

  # Pass-through, except that rm_cow_fail fails the COW's removal (B5: the teardown must report it).
  mkstub rm <<'STUB'
case "${*: -1}" in "$FXD"/shm/*/cow) [ ! -e "$FXD/rm_cow_fail" ] || exit 1 ;; esac
exec "$REAL_RM" "$@"
STUB

  # Catch-alls: nothing in the unit may run these, and each one only logs and refuses, so a call
  # naming the origin lands in calls.log for the allowlist row instead of running unobserved.
  for _c in e2fsck fsck fsck.ext4 tune2fs debugfs mkfs mkfs.ext4 mke2fs wipefs dd blkdiscard resize2fs e2label; do
    mkstub "$_c" <<STUB
printf '%s|%s\n' '$_c' "\$*" >> "\$FXD/calls.log"
exit 64
STUB
  done

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
# the /dev/shm COW parent, the /dev/mapper node of the snapshot, and /sys (holders, the origin's
# I/O counters and ext4's errors_count). Each is rewritten into the scratch dir — the
# reporter-unit precedent from git-data-luks-reopen.test.sh. The static rows above pin the
# shipped spellings.
rewrite_unit() {
  sed -e "s#/usr/sbin/runuser#$FX/bin/runuser#g" -e "s#/dev/shm#$FX/shm#g" \
      -e "s#/dev/mapper/#$FX/dev/mapper/#g" -e "s#/sys/#$FX/sys/#g" "$1" > "$2"
}
# The landed-check: a HOST spelling the rewrite did not cover (`/sys` or `/dev/mapper` with no
# trailing slash, say) would reach the real host from a non-root run. The fixture root is
# tokenised away first, so the check cannot be satisfied by the very prefix the rewrite added,
# and it runs comment-stripped so prose cannot trip it. R0 proves it can fire.
unrewritten() {
  sed "s#$FX#@FX@#g" "$1" > "$1.tok"
  strip "$1.tok" | grep -cE '(^|[^@A-Za-z0-9_.-])/(dev/shm|dev/mapper|sys)([/"'"'"' );]|$)' || true
}
run_unit() {
  local _u="$1" _n
  rewrite_unit "$_u" "$FX/unit.run"
  _n=$(unrewritten "$FX/unit.run")
  if [ "$_n" != 0 ]; then
    echo "FATAL: $_n host path(s) survived the rewrite in $FX/unit.run" >&2; exit 2
  fi
  # Per-run fixture state the stubs mutate: the device number, the origin's counters, the marks.
  printf '%s\n' "$FX_DEVNO_HEX" > "$FX/devnum"
  if [ -e "$FX/stat_absent" ]; then rm -f "$FX/sys/dev/block/$FX_SYSDEV/stat"
  elif [ -s "$FX/stat_content" ]; then cp "$FX/stat_content" "$FX/sys/dev/block/$FX_SYSDEV/stat"
  else printf '%s\n' "$FX_STAT" > "$FX/sys/dev/block/$FX_SYSDEV/stat"; fi
  rm -f "$FX/counted" "$FX/cow_size" "$FX/dm_deps"
  # Per-RUN artifacts, not per-fixture: the mutation rows drive the pristine unit and then the
  # mutant against the SAME fixture, and a calls.log carried over from the first run makes
  # "the mutant never called the wrapper" true of neither run.
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  rm -f "$FX/probe.env" "$FX/runuser.env" "$FX/mount_opts" "$FX/mount_source" "$FX/etc/git-data/store-verified" \
    "$FX/ro_set" "$FX/loop_up" "$FX/dmesg_calls" "$FX/dev/mapper/git-data-pt-snap"
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
# Guard 1 mutation 7's allowlist: every stubbed call whose argv names the origin — by its NODE or
# by the by-id LINK that resolves to it — is one of the listed read-only or setro-guarded calls, and
# all but the identity probes come after --setro. Prints 0 when clean, 1 (and each offender) when not.
CATCHALL_RE='^(e2fsck|fsck|fsck\.ext4|tune2fs|debugfs|mkfs|mkfs\.ext4|mke2fs|wipefs|dd|blkdiscard|resize2fs|e2label)\|'
origin_calls_bad() {
  local _s _bad=0 _l _no _c
  _s=$(first_line '^blockdev\|--setro')
  while IFS= read -r _l; do
    _no="${_l%%:*}"; _c="${_l#*:}"
    case "$_c" in
      "stat|-L -c %F $FX/dev/vol"|"cryptsetup|isLuks $FX/dev/vol") [ "$_no" -lt "$_s" ] || _bad=1 ;;
      "stat|-L -c %t:%T $FX/dev/vol"|"stat|-L -c %t:%T $FX/dev/by-id") : ;;
      "blockdev|--setro $FX/dev/vol"|"blockdev|--getro $FX/dev/vol"|"dumpe2fs|-h $FX/dev/vol"|"blockdev|--getsz $FX/dev/vol") [ "$_no" -ge "$_s" ] || _bad=1 ;;
      "dmsetup|create git-data-pt-snap --table 0 20971520 snapshot $FX/dev/vol /dev/loop77 N 8") [ "$_no" -gt "$_s" ] || _bad=1 ;;
      *) _bad=1; echo "      off-allowlist opener: $_c" >&2 ;;
    esac
  done < <(grep -nF -e "$FX/dev/vol" -e "$FX/dev/by-id" "$FX/calls.log")
  echo "$_bad"
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
# Guard 1 mutation 7's row: every call that names the origin (node or link) is on the allowlist,
# and every one except the read-only identity probes comes after --setro.
ok "$(origin_calls_bad)" "R1 every call naming the origin (node or by-id link) is allowlisted and ordered after --setro (Guard 1 row 7)" "$(grep -F -e "$FX/dev/vol" -e "$FX/dev/by-id" "$FX/calls.log")"
ok "$(( $(grep -cE "$CATCHALL_RE" "$FX/calls.log" || true) != 0 ))" "R1 no fsck/tune2fs/debugfs/mkfs/wipefs/dd-class tool was called at all" "$(grep -E "$CATCHALL_RE" "$FX/calls.log")"
ok "$(( $(grep -c '^stat|-L -c %t:%T ' "$FX/calls.log" || true) < 7 ))" \
  "R1 the device number was read at resolution and re-checked through link and node before setro, dumpe2fs and create (>= 7 reads)" "$(grep '^stat|' "$FX/calls.log")"
ok "$([ "$(cat "$FX/cow_size" 2>/dev/null)" = 134217728 ]; echo $?)" \
  "R1 the COW is 16384 journal blocks x 4096 + 64 MiB = 134217728 bytes (got '$(cat "$FX/cow_size" 2>/dev/null)')"
ok "$(grep -q '^dmsetup|deps git-data-pt-snap$' "$FX/calls.log"; echo $?)" "R1 the snapshot's deps were read after the create (origin identity)"
ok "$(grep -q '^udevadm|settle --timeout=' "$FX/calls.log"; echo $?)" "R1 the teardown's udevadm settle carried a timeout"
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
: > "$FX/sys/dev/block/$FX_SYSDEV/holders/dm-0"
run_unit "$UNIT"
fatal_row R9c 'plaintext_unverified reason=source' -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R9c a device with holders is never set read-only"
new_fixture r9d-no-sysfs
rm -rf "$FX/sys/dev/block/$FX_SYSDEV/holders"
run_unit "$UNIT"
fatal_row R9d 'plaintext_unverified reason=source' -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R9d no sysfs holders directory is a refusal, not an empty holders list"
# B6 — a snapshot left by an earlier run is named as that, not as foreign holders (it is both).
new_fixture r9e-stale-snapshot
: > "$FX/dm_stale"; : > "$FX/sys/dev/block/$FX_SYSDEV/holders/dm-9"
run_unit "$UNIT"
fatal_row R9e "plaintext_unverified reason=snapshot — a previous run's git-data-pt-snap is still present" -
ok "$(absent_in '^dmsetup|remove\|^blockdev|--setro' "$FX/calls.log")" "R9e the leftover is never removed and the origin is not touched"
# B3 — the device NUMBER is the identity; a reattach between calls re-points the name.
new_fixture r9f-reattach-before-setro
: > "$FX/reattach_after_isluks"
run_unit "$UNIT"
fatal_row R9f 'plaintext_unverified reason=source — '"$FX"'/dev/by-id no longer names device 8:16 (before --setro)' -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R9f a device that changed before --setro is never set read-only"
new_fixture r9g-reattach-before-dumpe2fs
: > "$FX/reattach_after_setro"
run_unit "$UNIT"
fatal_row R9g 'plaintext_unverified reason=source — '"$FX"'/dev/by-id no longer names device 8:16 (before dumpe2fs)' -
ok "$(absent_in '^dumpe2fs|' "$FX/calls.log")" "R9g no superblock is read from a device that changed after --setro"
new_fixture r9h-reattach-before-create
: > "$FX/reattach_after_dumpe2fs"
run_unit "$UNIT"
fatal_row R9h 'plaintext_unverified reason=source — '"$FX"'/dev/by-id no longer names device 8:16 (before dmsetup create)' -
ok "$(absent_in '^dmsetup|create' "$FX/calls.log")" "R9h no snapshot is stacked on a device that changed after dumpe2fs"
ok "$(grep -q '^losetup|-d' "$FX/calls.log"; echo $?)" "R9h the COW loop was still released"
new_fixture r9i-deps-other
: > "$FX/deps_other"
run_unit "$UNIT"
fatal_row R9i "plaintext_unverified reason=source — the snapshot's origin is not device 8:16" 0
ok "$(absent_in '^mount|' "$FX/calls.log")" "R9i a snapshot over another origin is never mounted"
# B1 — `repositories` that is not a directory is never followed and never read as 0.
new_fixture r9j-repositories-symlink
rm -rf "$FX/ptsrc/repositories"; mkdir -p "$FX/ptsrc/real/ws-1.git"; ln -s real "$FX/ptsrc/repositories"
run_unit "$UNIT"
fatal_row R9j "plaintext_unverified reason=source — the snapshot's repositories is not a directory" 1
new_fixture r9k-repositories-dangling
rm -rf "$FX/ptsrc/repositories"; ln -s /nonexistent-gd-fixture "$FX/ptsrc/repositories"
run_unit "$UNIT"
fatal_row R9k "plaintext_unverified reason=source — the snapshot's repositories is not a directory" 1
new_fixture r9l-repositories-file
rm -rf "$FX/ptsrc/repositories"; : > "$FX/ptsrc/repositories"
run_unit "$UNIT"
fatal_row R9l "plaintext_unverified reason=source — the snapshot's repositories is not a directory" 1

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
# The COW sizing rule, measured on the file the loop is attached to: journal blocks x
# max(block size, 4096) + 64 MiB. A 1 KiB-block volume exercises the 4096 floor.
new_fixture r10c2-cow-floor
printf '1024\n' > "$FX/fx_bs"; printf '4096\n' > "$FX/fx_jb"
run_unit "$UNIT"
ok "$([ "$(cat "$FX/cow_size" 2>/dev/null)" = 83886080 ]; echo $?)" \
  "R10c2 a 1024-byte block size is floored to 4096: 4096 x 4096 + 64 MiB = 83886080 (got '$(cat "$FX/cow_size" 2>/dev/null)'; unfloored would be 71303168)"
new_fixture r10c3-cow-large-block
printf '65536\n' > "$FX/fx_bs"; printf '16\n' > "$FX/fx_jb"
run_unit "$UNIT"
ok "$([ "$(cat "$FX/cow_size" 2>/dev/null)" = 68157440 ]; echo $?)" \
  "R10c3 a block size above 4096 is used as is: 16 x 65536 + 64 MiB = 68157440 (got '$(cat "$FX/cow_size" 2>/dev/null)')"
new_fixture r10d-losetup-fails
: > "$FX/losetup_fail"
run_unit "$UNIT"
fatal_row R10d 'plaintext_unverified reason=snapshot' -
ok "$([ -z "$(ls -A "$FX/shm")" ]; echo $?)" "R10d the /dev/shm directory was cleaned up"
new_fixture r10e-create-fails
: > "$FX/dm_create_fail"
run_unit "$UNIT"
fatal_row R10e 'plaintext_unverified reason=snapshot' -
ok "$(absent_in '^dmsetup|remove' "$FX/calls.log")" "R10e a create that failed without a device never removes one"
ok "$(grep -q '^losetup|-d' "$FX/calls.log"; echo $?)" "R10e the COW loop was still released"
# A create killed by its timeout can leave the device behind; the name was proven absent first,
# so the device is this run's and the teardown removes it.
new_fixture r10e2-create-timed-out
: > "$FX/dm_create_partial"
run_unit "$UNIT"
fatal_row R10e2 'plaintext_unverified reason=snapshot — dmsetup create git-data-pt-snap failed' 0
ok "$([ ! -e "$FX/dev/mapper/git-data-pt-snap" ]; echo $?)" "R10e2 the half-created snapshot was removed by the teardown"
new_fixture r10f-invalid
: > "$FX/dm_invalid"
run_unit "$UNIT"
fatal_row R10f 'plaintext_unverified reason=snapshot' 1
# B2 — the write gate is the origin's sysfs counters, compared across the whole apparatus.
new_fixture r10g-origin-written
: > "$FX/origin_write"
run_unit "$UNIT"
fatal_row R10g "plaintext_unverified reason=snapshot — $FX/dev/vol was written or discarded (sectors 40 8 -> 48 8)" 1
new_fixture r10g2-origin-discarded
: > "$FX/origin_discard"
run_unit "$UNIT"
fatal_row R10g2 "plaintext_unverified reason=snapshot — $FX/dev/vol was written or discarded (sectors 40 8 -> 40 16)" 1
new_fixture r10g3-stat-short
printf '120 0 960 10 0 0 0 0 0 10 10\n' > "$FX/stat_content"
run_unit "$UNIT"
fatal_row R10g3 "plaintext_unverified reason=snapshot — the sysfs write counters of $FX/dev/vol are unreadable" -
ok "$(absent_in '^blockdev|--setro' "$FX/calls.log")" "R10g3 a stat without discard counters (11 fields) stops before --setro"
new_fixture r10g4-stat-absent
: > "$FX/stat_absent"
run_unit "$UNIT"
fatal_row R10g4 "plaintext_unverified reason=snapshot — the sysfs write counters of $FX/dev/vol are unreadable" -
new_fixture r10h-classifier
: > "$FX/dm_invalid"
printf '[   12.3] device-mapper: snapshots: Invalidating snapshot: Unable to allocate exception.\n' > "$FX/klog_extra"
run_unit "$UNIT"
ok "$(grep -qF 'kernel=overflow cow=Invalid' "$FX/err"; echo $?)" "R10h the FATAL carries a classifier word and the dm status, not raw kernel lines" "$(cat "$FX/err")"
ok "$(absent_in 'Unable to allocate' "$FX/err")" "R10h no raw kernel line reaches the FATAL detail"
# B5 — a COW file that cannot be removed is a named teardown failure, not a set -e abort mid-trap.
new_fixture r10i-cow-rm-fails
: > "$FX/rm_cow_fail"
run_unit "$UNIT"
fatal_row R10i 'plaintext_unverified reason=umount — rm of the COW file failed' 1

# --- R11: reason=journal — the replay did not produce a trustworthy tree ------------------
# B4 — errors_count must equal the volume's HISTORICAL count after the replay and must not move
# during the count. s_error_count accumulates for life, so "must be 0" would refuse forever.
new_fixture r11a-errors-after-mount
printf '3\n' > "$FX/errs_before"; printf '3\n' > "$FX/errs_after"
run_unit "$UNIT"
fatal_row R11a "plaintext_unverified reason=journal — ext4 errors_count reads '3' after replay, 0 before" 1
new_fixture r11a2-historical-errors
printf '3\n' > "$FX/fx_errcount"; printf '3\n' > "$FX/errs_before"; printf '3\n' > "$FX/errs_after"
run_unit "$UNIT"
ok "$((RC != 0))" "R11a2 a volume that logged 3 errors in its life, none new, PASSES (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R11a2 plaintext_empty=yes"
new_fixture r11b-errors-rise
printf '0\n' > "$FX/errs_before"; printf '1\n' > "$FX/errs_after"
run_unit "$UNIT"
fatal_row R11b 'plaintext_unverified reason=journal — ext4 logged an error during the count (errors_count 0 -> 1)' 1
new_fixture r11b2-historical-then-rise
printf '3\n' > "$FX/fx_errcount"; printf '3\n' > "$FX/errs_before"; printf '4\n' > "$FX/errs_after"
run_unit "$UNIT"
fatal_row R11b2 'plaintext_unverified reason=journal — ext4 logged an error during the count (errors_count 3 -> 4)' 1
new_fixture r11c-with-errors
: > "$FX/snap_with_errors"
run_unit "$UNIT"
fatal_row R11c "plaintext_unverified reason=journal — the replayed snapshot reads 'with errors'" 1
new_fixture r11d-errors-unreadable
: > "$FX/errs_before"
run_unit "$UNIT"
fatal_row R11d "plaintext_unverified reason=journal — ext4 errors_count reads 'unreadable' after replay" 1
new_fixture r11e-errcount-garbage
printf 'lots\n' > "$FX/fx_errcount"
run_unit "$UNIT"
fatal_row R11e "plaintext_unverified reason=journal — the $FX/dev/vol superblock's error count is unreadable" -

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
mutate_py g1d 'if timeout 60 dmsetup remove --retry "$_pt_snap" >/dev/null 2>&1; then' 'if true; then'
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
ok "$(( $(origin_calls_bad 2>/dev/null) == 0 ))" "G1-7 ROW 7: the origin allowlist row reds on the second opener — the arm is live"

# G1 row 9 — drop the errors_count check: a checksum-skipped directory block yields a short count.
new_fixture g1-no-errors-check
printf '0\n' > "$FX/errs_before"; printf '1\n' > "$FX/errs_after"
mutate_py g1e '  [ "$_pt_e1" = "$_pt_e0" ] || {' '  true || {'
ok "$MUT_RC" "G1-9 the mutation landed (the post-count errors_count check removed)"
run_unit "$MUT"
ok "$((RC != 0))" "G1-9 ROW 9: without it a count that raised an ext4 error PASSES (rc=$RC) — the arm is live"

# S2 — the allowlist sees the LINK spelling too: an opener that names the by-id link instead of
# the node it resolves to must red the same row. Placed BEFORE the snapshot mount, it is the shape
# that passed 279/279 when the row matched only the node string (the later mount overwrote the
# stub's recorded options, so no incidental row saw it either).
new_fixture g1-link-opener
mutate_py g1l '  mount -o ro,errors=remount-ro' '  mount -r "$_pt_link" "$_pt_mnt" 2>/dev/null || true
  mount -o ro,errors=remount-ro'
ok "$MUT_RC" "G1-7b the mutation landed (a mount of the by-id link)"
run_unit "$MUT"
ok "$(( $(origin_calls_bad 2>/dev/null) == 0 ))" "G1-7b the origin allowlist row reds on an opener spelled as the by-id link — the arm is live" "$(grep -F "$FX/dev/by-id" "$FX/calls.log")"
# S3 — a catch-all tool naming the origin is logged by its stub and reds the same row.
new_fixture g1-catchall-opener
mutate_py g1c '  _pt_e1="$(_pt_errs || true)"' '  e2fsck -n "$_pt_dev" >/dev/null 2>&1 || true
  _pt_e1="$(_pt_errs || true)"'
ok "$MUT_RC" "G1-7c the mutation landed (an e2fsck of the origin)"
run_unit "$MUT"
ok "$(( $(origin_calls_bad 2>/dev/null) == 0 ))" "G1-7c the origin allowlist row reds on an e2fsck of the origin — the arm is live"
ok "$(grep -qE "$CATCHALL_RE" "$FX/calls.log"; echo $?)" "G1-7c and the catch-all stub logged the call"

# S6 — each _pt_valid call site is load-bearing on its own. The fixture invalidates the snapshot
# only BEFORE the count (site 1, after the mount) or only AFTER it (site 2, before the release),
# so deleting either call alone lets an Invalid snapshot through.
new_fixture g1-valid-site1
: > "$FX/dm_invalid_precount"
run_unit "$UNIT"
ok "$(fatal_is 'plaintext_unverified reason=snapshot — the snapshot was invalidated')" "G1-11 instrument: the pristine unit refuses a snapshot Invalid before the count" "$(cat "$FX/err")"
mutate_py g1v1 '  _pt_mounted=1
  _pt_valid
' '  _pt_mounted=1
'
ok "$MUT_RC" "G1-11 the mutation landed (the post-mount _pt_valid removed)"
run_unit "$MUT"
ok "$((RC != 0))" "G1-11 without the post-mount check that snapshot is certified (rc=$RC) — the call site is live"
new_fixture g1-valid-site2
: > "$FX/dm_invalid_postcount"
run_unit "$UNIT"
ok "$(fatal_is 'plaintext_unverified reason=snapshot — the snapshot was invalidated')" "G1-12 instrument: the pristine unit refuses a snapshot Invalid after the count" "$(cat "$FX/err")"
mutate_py g1v2 '  _pt_valid
  _pt_release
' '  _pt_release
'
ok "$MUT_RC" "G1-12 the mutation landed (the pre-release _pt_valid removed)"
run_unit "$MUT"
ok "$((RC != 0))" "G1-12 without the pre-release check that snapshot is certified (rc=$RC) — the call site is live"

# B2 — the counter comparison is what catches a write through the stack; without it, it passes.
new_fixture g1-no-counter-check
: > "$FX/origin_write"
mutate_py g1w '  [ "$_pt_w1" = "$_pt_w0" ] || {' '  true || {'
ok "$MUT_RC" "G1-13 the mutation landed (the sector-counter comparison removed)"
run_unit "$MUT"
ok "$((RC != 0))" "G1-13 without it a write that reached the origin PASSES (rc=$RC) — the arm is live"

# S8 — the rewrite landed-check can fire: a host spelling the sed does not cover is counted, the
# pristine unit's rewrite leaves none, and the fixture-root prefix alone never counts.
new_fixture r0-landed-check
printf '  cd /sys\n  x="/dev/mapper"\n  # /sys/ in a comment is prose\n' > "$FX/landed.canary"
rewrite_unit "$FX/landed.canary" "$FX/landed.run"
ok "$(( $(unrewritten "$FX/landed.run") != 2 ))" "R0 instrument: the landed-check counts the 2 host paths the rewrite misses (and not the comment)"
rewrite_unit "$UNIT" "$FX/pristine.run"
ok "$(unrewritten "$FX/pristine.run")" "R0 the pristine unit's rewrite leaves no host /dev/shm, /dev/mapper or /sys path"
ok "$(( $(grep -c "$FX/sys/" "$FX/pristine.run" || true) == 0 ))" "R0 and the rewrite really landed (the unit now names $FX/sys/)"

# G1 row 10 — a feature argument on the dm table.
mutate_py g1t 'snapshot $_pt_dev $_pt_loop N 8"' 'snapshot $_pt_dev $_pt_loop N 8 1 discard_passdown_origin"'
ok "$MUT_RC" "G1-10 the mutation landed (discard_passdown_origin added)"
ok "$(( MUT_RC != 0 || $(grep -qF 'dmsetup create "$_pt_snap" --table "0 $_pt_sz snapshot $_pt_dev $_pt_loop N 8"' "$MUT"; echo $?) == 0 ))" \
  "G1-10 ROW 10: the table-literal row (S6d) reds on the mutant — the arm is live"

# =====================================================================================
# Instrument self-test + floor
# =====================================================================================
# Through ok(), not only pass()/fail(): the verdict DISPATCH is what every row relies on, so a
# swapped branch in ok() must stop the suite here rather than invert every verdict above.
_can_p0=$passes; _can_f0=$fails; _can_c0=$cases
pass
fail "CANARY — instrument self-test, not a real failure" 2>/dev/null
if [ "$passes" -ne $((_can_p0 + 1)) ] || [ "$fails" -ne $((_can_f0 + 1)) ]; then
  echo "FAIL CANARY: pass()/fail() did not each move their counter by one" >&2
  exit 1
fi
ok 0 "CANARY — ok 0 must PASS"
ok 1 "CANARY — ok 1 must FAIL, not a real failure" 2>/dev/null
if [ "$passes" -ne $((_can_p0 + 2)) ] || [ "$fails" -ne $((_can_f0 + 2)) ] || [ "$cases" -ne $((_can_c0 + 2)) ]; then
  echo "FAIL CANARY: ok 0 did not PASS and ok 1 did not FAIL (or ok() did not count its call site)" >&2
  exit 1
fi
passes=$_can_p0; fails=$_can_f0; cases=$_can_c0

# ADR-193 §2/§3: the floor is checked against the CALL-SITE counter (`cases`, bumped by ok()
# before either verdict helper runs), and the two counts must agree — a verdict counter alone
# cannot see a call site that never reached a verdict. The two bindings sit DIRECTLY above the
# `if` with no comment between: guard-vacuity-floor builds its mutant from the floor block plus
# the contiguous simple assignments above it, and a comment breaks the run.
MIN_ASSERTIONS=412
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
