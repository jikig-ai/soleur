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
#             stubs: mount (logs argv, asserts the ro,noload,nosuid,nodev,noexec options, and
#             copies a fixture tree into its target), umount, dumpe2fs, findmnt, install and
#             runuser. The seams the bootstrap honours (GIT_DATA_STORE_DEVICE,
#             GIT_DATA_STORE_VERIFIED, GIT_DATA_REMOVE_BIN and the by-id GIT_DATA_PLAINTEXT_DEV)
#             are what make that possible without EACCES standing in for a refusal.
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
# The mount is temporary, private and inert. `ro` alone still lets ext4 replay the journal, which
# is a WRITE to the volume this step exists to leave untouched.
ok "$(grep -qF 'mount -o ro,noload,nosuid,nodev,noexec' "$UNIT_BODY"; echo $?)" \
  "S6 the plaintext mount is -o ro,noload,nosuid,nodev,noexec"
ok "$(grep -qF '_pt_dir="$(mktemp -d)"' "$UNIT_BODY"; echo $?)" "S7 the mount parent is a private mktemp -d"
ok "$(grep -qF '_pt_mnt="$_pt_dir/mnt"' "$UNIT_BODY"; echo $?)" \
  "S7b the mount target is <mktemp -d>/mnt, so the 0700 parent outlives the volume's own root mode"
ok "$(grep -qE '^[[:space:]]*trap _pt_release EXIT$' "$UNIT_BODY"; echo $?)" \
  "S8 a trap unmounts the plaintext volume on EVERY exit"
ok "$(grep -qF 'plaintext_unverified reason=umount' "$UNIT_BODY"; echo $?)" "S8b a failed umount is FATAL reason=umount"
ok "$(grep -qF "! -name '.*.init.lock' ! -name lost+found" "$UNIT_BODY"; echo $?)" \
  "S9 the count excludes the .<id>.init.lock dotfiles and lost+found, and nothing else"
n=$(grep -c "\-name '\*\.git'" "$UNIT_BODY" || true)
ok "$((n != 0))" "S9b the count is NOT narrowed to *.git — a partial repositories/x is still user data (got $n)"
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
for _b in fence_on_mapper erasure_probe plaintext_empty plaintext_volume served_repos; do
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
  mkdir -p "$FX/bin" "$FX/store/repositories" "$FX/store/hooks" "$FX/ptsrc/repositories" "$FX/dev" "$FX/tmp"
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  : > "$FX/store/hooks/pre-receive"
  chmod 0755 "$FX/store/hooks/pre-receive"
  : > "$FX/dev/vol"
  : > "$FX/dev/other"
  ln -sfn "$FX/dev/vol" "$FX/dev/by-id"
  # findmnt answers, per query kind. The by-id seam points at a symlink, so the unit's
  # realpath comparison has something real to resolve on both sides.
  printf '%s\n' "$FX/dev/vol" > "$FX/pt_source"
  printf '%s\n' "$STORE_DEV_FIXTURE" > "$FX/fence_source"
  printf '%s\n' "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > "$FX/store_uuid"

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

  mkstub dumpe2fs <<'STUB'
printf 'dumpe2fs|%s\n' "$*" >> "$FXD/calls.log"
[ ! -e "$FXD/dumpe2fs_fail" ] || exit 1
if [ -e "$FXD/dumpe2fs_dirty" ]; then
  printf 'Filesystem features:      has_journal ext_attr needs_recovery extent 64bit\n'
else
  printf 'Filesystem features:      has_journal ext_attr resize_inode extent 64bit\n'
fi
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
TRAIL
}

# The extracted unit names runuser by absolute path (S15c), which is right on the host and
# unreachable in a non-root fixture. Rewriting that ONE absolute path into the scratch dir is
# the reporter-unit precedent from git-data-luks-reopen.test.sh; S15c is what keeps the shipped
# spelling honest.
run_unit() {
  local _u="$1"
  sed "s#/usr/sbin/runuser#$FX/bin/runuser#g" "$_u" > "$FX/unit.run"
  # Per-RUN artifacts, not per-fixture: the mutation rows drive the pristine unit and then the
  # mutant against the SAME fixture, and a calls.log carried over from the first run makes
  # "the mutant never called the wrapper" true of neither run.
  : > "$FX/calls.log"
  : > "$FX/emit.log"
  rm -f "$FX/probe.env" "$FX/runuser.env" "$FX/mount_opts" "$FX/etc/git-data/store-verified"
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

# --- R1: plaintext verified empty -> marker + every boolean yes -----------------------
new_fixture r1-verified-empty
run_unit "$UNIT"
ok "$((RC != 0))" "R1 the all-pass path exits 0 (rc=$RC)" "$(cat "$FX/err")"
ok "$([ "$(field plaintext_volume)" = present ]; echo $?)" "R1 plaintext_volume=present"
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R1 plaintext_empty=yes"
ok "$([ "$(field fence_on_mapper)" = yes ]; echo $?)" "R1 fence_on_mapper=yes"
ok "$([ "$(field erasure_probe)" = yes ]; echo $?)" "R1 erasure_probe=yes"
ok "$([ "$(field served_repos)" = 0 ]; echo $?)" "R1 served_repos=0"
ok "$([ "$(marker)" = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" ]; echo $?)" \
  "R1 the marker holds exactly the mapper filesystem UUID (contract C2)" "$(marker)"
ok "$([ "$(stat -c %a "$FX/etc/git-data/store-verified" 2>/dev/null)" = 644 ]; echo $?)" "R1 the marker is mode 0644"
ok "$([ "$(wc -l < "$FX/etc/git-data/store-verified")" -eq 1 ]; echo $?)" "R1 the marker is exactly one line"
ok "$(grep -qxF 'ro,noload,nosuid,nodev,noexec' "$FX/mount_opts"; echo $?)" \
  "R1 the plaintext mount carried -o ro,noload,nosuid,nodev,noexec" "$(cat "$FX/mount_opts" 2>/dev/null)"
ok "$(grep -q '^umount|' "$FX/calls.log"; echo $?)" "R1 the plaintext volume was unmounted"
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
ok "$([ "$(field plaintext_empty)" = yes ]; echo $?)" "R2 plaintext_empty=yes"
ok "$(absent_in '^mount|' "$FX/calls.log")" "R2 nothing was mounted"
ok "$([ -n "$(marker)" ]; echo $?)" "R2 the marker is still written on the absent path"

# --- R3: a no-op mount, adjudicated by the REAL findmnt --------------------------------
# The mount "succeeds" and leaves an empty directory. A count alone reads 0 and clears the
# volume; only the SOURCE check catches it. Driven with the real findmnt against a path that is
# not a mountpoint, so the stub cannot be what makes the row pass.
if command -v findmnt >/dev/null 2>&1; then
  new_fixture r3-noop-mount
  rm -f "$FX/bin/findmnt"
  : > "$FX/mount_noop"
  run_unit "$UNIT"
  ok "$((RC == 0))" "R3 a no-op mount is FATAL (rc=$RC)" "$(cat "$FX/err")"
  ok "$(fatal_is 'plaintext_unverified reason=source')" "R3 reason=source" "$(cat "$FX/err")"
  ok "$(marker_absent)" "R3 no marker was written"
  ok "$(emit_stage_bootstrap)" "R3 the FATAL was emitted at stage=bootstrap" "$(cat "$FX/emit.log")"
else
  ok 0 "R3 SKIPPED — findmnt(8) absent, the real-instrument row cannot run"
  ok 0 "R3 SKIPPED — reason=source"
  ok 0 "R3 SKIPPED — no marker"
  ok 0 "R3 SKIPPED — stage=bootstrap"
fi

# --- R3b: the mount itself fails -------------------------------------------------------
new_fixture r3b-mount-failed
: > "$FX/mount_fail"
run_unit "$UNIT"
ok "$((RC == 0))" "R3b a failed mount is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_unverified reason=mount')" "R3b reason=mount" "$(cat "$FX/err")"
ok "$(marker_absent)" "R3b no marker was written"

# --- R3c: a failed umount --------------------------------------------------------------
new_fixture r3c-umount-failed
: > "$FX/umount_fail"
run_unit "$UNIT"
ok "$((RC == 0))" "R3c a failed umount is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_unverified reason=umount')" "R3c reason=umount" "$(cat "$FX/err")"
ok "$(marker_absent)" "R3c no marker was written"

# --- R4: a dirty journal ---------------------------------------------------------------
# The fixture ALSO holds a repository, so "nothing is counted" is discriminating: a journal
# verdict must win over the residue verdict the same tree would otherwise produce.
new_fixture r4-needs-recovery
: > "$FX/dumpe2fs_dirty"
mkdir -p "$FX/ptsrc/repositories/ws-1.git"
run_unit "$UNIT"
ok "$((RC == 0))" "R4 needs_recovery is FATAL (rc=$RC)"
ok "$(fatal_is 'plaintext_unverified reason=journal')" "R4 reason=journal" "$(cat "$FX/err")"
ok "$(absent_in plaintext_residue "$FX/err")" "R4 nothing was counted — no residue verdict" "$(cat "$FX/err")"
ok "$(marker_absent)" "R4 no marker was written"

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
MIN_ASSERTIONS=90
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
