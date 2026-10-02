#!/usr/bin/env bash
# workspaces-luks-provision.test.sh — Guard 1 for the guest-side fresh-boot LUKS provisioner (#6931).
#
# PROPERTY UNDER TEST. workspaces-luks-provision.sh runs `cryptsetup luksFormat` or `mkfs` only on
# a device whose `blkid -o value -s TYPE` is empty (rc 2) AND which shows no partition table, other
# signature or non-zero content — re-checked immediately before EACH destructive call — and never on
# any other state. `mkfs` on a LUKS mapper happens only for a blank mapper whose format THIS
# provisioner started: the local intent file OR the formatting LABEL carried by the volume (which is
# what lets a REPLACEMENT host finish an interrupted birth). It never uses `cryptsetup isLuks`.
#
# SHAPE. Every external command is a stub on a scratch PATH that appends "<cmd> <argv>" to a calls
# log, driven by small state files; the provisioner runs against a scratch root through its test
# seam. Every destructive-capable binary NOT used by the provisioner (mkfs*, mke2fs, blkdiscard, dd,
# sgdisk, sfdisk, parted, fstrim, wipefs write modes, any other cryptsetup verb, shred outside the
# header temp files) is a TRAP stub: it logs `TRAP ...` and exits 99. The no-write cases assert the
# calls log is a SUBSET of a read-only allow-list (not "free of a deny-list"). Assertions are over
# the CALLS (what was invoked, in what order, with what), never over a value compared with the thing
# it protects. Mutation rows at the bottom mutate COPIES of the provisioner and re-run this file
# against them (WLP_SCRIPT); rc 1 = the mutation was caught, rc 0 = it SURVIVED, rc 2 = a broken
# instrument (never counted as a catch). Rows run up to WLP_MUT_JOBS (default 3) at a time and are scored in row order.
#
# A compound claim is ONE scored command: `expect "name" all 'cmd' 'cmd'`. The `expect "n" test A && B`
# form is banned (the && half is never scored); a static row below fails the suite if one returns.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$DIR/$(basename "${BASH_SOURCE[0]}")"
PRISTINE="$DIR/workspaces-luks-provision.sh"
SUT="${WLP_SCRIPT:-$PRISTINE}"
# Instrument seams (suite-only; the mutation rows below drive them):
#   WLP_MUTANT=1       inner run of a mutation row — skips the mutation rows themselves.
#   WLP_STUB_NOLOG=1   the stubs record nothing (the "0 calls checked" harness row).
#   WLP_DROP_CASE=<n>  the named case is not run (the "a case was deleted" harness row).
#   WLP_ONLY_CASES="a b"  inner runs only: run just these cases (each mutation row names the cases that
#                      hold its target assertions; the outer run is the one full control run). A name that
#                      is not a case, a duplicate, or an empty list exits 2 (a broken instrument, never a
#                      catch), so a typo cannot make a row vacuous.
#   WLP_MUT_JOBS=<n>   how many mutation rows run at once (default 3; the infra runner is already -P4).
#   WLP_LOCK_WAIT=<s>  passed to the provisioner as WORKSPACES_PROVISION_LOCK_WAIT (honoured ONLY under the seam).
#   WLP_RUN_TIMEOUT=<s>  run_sut kills the provisioner after this long (the contended-lock runs set it, so a mutant
#                      whose lock wait is unbounded ends its row in seconds instead of hanging on the holder).
WLP_MUTANT="${WLP_MUTANT:-}"

pass=0; fail=0; FAILED=()
ok() { if [ "$1" -eq 0 ]; then pass=$((pass + 1)); printf '[ok] %s\n' "$2"; else fail=$((fail + 1)); FAILED+=("$2"); printf '[FAIL] %s%s\n' "$2" "${3:+ ($3)}"; fi; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }
expect() { # <name> <cmd...> — the command's exit status is the verdict
  local n="$1"; shift
  if "$@"; then ok 0 "$n"; else ok 1 "$n"; fi
}
all() { local _all_c; for _all_c in "$@"; do eval "$_all_c" || return 1; done; } # every string is evaluated; the first false one is the verdict

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

# INSTRUMENT SELF-TEST — the helpers must move their own counters before any verdict is trusted.
# A compound whose FIRST half fails, whose SECOND half fails, or that passes must each score right.
_p0=$pass; _f0=$fail
{ ok 0 "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()
{ expect "self-test" all 'test 1 -eq 2' 'true'; expect "self-test" all 'true' 'test 1 -eq 2'; expect "self-test" all 'true' 'true'; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 2)) ] || [ "${#FAILED[@]}" -ne 2 ]; then
  printf '[FATAL] instrument self-test: expect/all did not score a failing compound red (pass=%s fail=%s)\n' "$pass" "$fail" >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

[ -r "$SUT" ] || { printf '[FATAL] unreadable: %s\n' "$SUT" >&2; exit 2; }
# The REAL binaries the lock cases drive (the flock stub delegates to the real one: stub-only coverage
# proves the argv spelling, not exclusion). Absent -> a broken instrument, never a pass.
FLOCK_REAL="$(command -v flock || true)"; SLEEP_REAL="$(command -v sleep || true)"
[ -x "$FLOCK_REAL" ] && [ -x "$SLEEP_REAL" ] || { printf '[FATAL] flock and sleep must be installed to run this suite\n' >&2; exit 2; }
SCRATCH="$(mktemp -d)"
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

DEVID=424242
DEVPIN="/dev/disk/by-id/scsi-0HC_Volume_$DEVID"
KEYVAL="FIXTURE-PASSPHRASE-0001"
TOKVAL="TESTTOKEN-not-a-credential-0001"
SECVAL="TESTSECRET-not-a-credential-0002"
LBL_F=soleur-formatting
LBL_R=soleur-workspaces
DEVSIZE=300M
ACCT=0123456789abcdef0123456789abcdef # a synthetic 32-hex Cloudflare account id (the R2 endpoint shape the provisioner pins)

# ── stubs ─────────────────────────────────────────────────────────────────────────────────────
mkstub() { # <dir> <name>: the body arrives on stdin; the call logger is prepended
  [ -n "${FX-}" ] && assert_fixture_dir "$FX" # FX is unset while the pre-fixture core stubs are built
  { printf '%s\n' '#!/bin/bash' '_L() { [ -z "${WLP_STUB_NOLOG:-}" ] || return 0; printf "%s\n" "$*" >> "$FX/calls"; }'; cat; } > "$1/$2"
}
write_stubs() { # <dir>: written ONCE; every fixture copies it
  local d="$1" t
  mkdir -p "$d"
  mkstub "$d" blkid <<'EOF'
_L "blkid $*"
last="${*: -1}"
st="$FX/st"
case "$*" in
  *PTTYPE*) v=$(cat "$st/dev.pttype" 2>/dev/null); [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }; exit 2 ;;
  *LABEL*) v=$(cat "$st/dev.label" 2>/dev/null); [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }; exit 2 ;;
esac
if [ "$last" = /dev/mapper/workspaces ]; then
  v=$(cat "$st/map.type" 2>/dev/null); [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }; exit 2
fi
n=$(( $(cat "$st/blkid.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/blkid.n"
if [ -s "$st/blkid.rc" ]; then exit "$(cat "$st/blkid.rc")"; fi
if [ -s "$st/flip_after" ] && [ "$n" -gt "$(cat "$st/flip_after")" ]; then printf 'ext4\n'; exit 0; fi
v=$(cat "$st/dev.type" 2>/dev/null); [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }
exit 2
EOF
  # cryptsetup dispatches on the VERB, wherever the flags sit (`cryptsetup --batch-mode luksFormat`
  # reaches luksFormat too); a verb the provisioner has no business using is a TRAP, not a silent exit 0.
  mkstub "$d" cryptsetup <<'EOF'
st="$FX/st"
verb=""
for a in "$@"; do
  case "$a" in
    luksFormat|luksOpen|status|luksUUID|luksHeaderBackup|config|isLuks|open|close|luksClose|luksDump|luksErase|erase|luksKillSlot|luksAddKey|luksRemoveKey|luksChangeKey|luksHeaderRestore|reencrypt|convert|resize|repair|benchmark|token|refresh|luksSuspend|luksResume|format) verb="$a"; break ;;
  esac
done
_L "cryptsetup $*"
_L "cryptsetup-verb $verb"
label=""; uuid=""; prev=""
for a in "$@"; do [ "$prev" = --label ] && label="$a"; [ "$prev" = --uuid ] && uuid="$a"; prev="$a"; done
case "$verb" in
  luksFormat)
    key=$(cat); [ -n "$key" ] || exit 2
    _L "luksFormat-state intent_present=$([ -f "$FX/root/var/lib/soleur/workspaces-luks-formatting" ] && echo 1 || echo 0) label=$label uuid=$uuid core=$(ulimit -c)"
    [ -f "$st/fail.luksFormat" ] && { echo "Cannot format device FIXTURE-CAUSE-FORMAT." >&2; exit 1; }
    printf 'crypto_LUKS' > "$st/dev.type"; printf 'crypto_LUKS signature\n' > "$st/dev.wipefs"; printf '%s' "$label" > "$st/dev.label"
    [ -n "$uuid" ] && [ ! -f "$st/uuid.ignore" ] && printf '%s' "$uuid" > "$st/dev.uuid"
    [ -f "$st/crash_after_luksFormat" ] && kill -9 "$PPID"
    exit 0 ;;
  luksOpen)
    key=$(cat); [ "$key" = "$(cat "$st/key")" ] || exit 2
    [ -f "$st/fail.luksOpen" ] && { echo "Device open failed FIXTURE-CAUSE-OPEN" >&2; exit 2; }
    echo 1 > "$st/map.active"
    [ -s "$st/luksOpen.preload_type" ] && { cp "$st/luksOpen.preload_type" "$st/map.type"; printf 'preloaded signature\n' > "$st/map.wipefs"; }
    exit 0 ;;
  config)
    [ -f "$st/fail.relabel" ] && { echo "Failed to set the label FIXTURE-CAUSE-RELABEL" >&2; exit 1; }
    printf '%s' "$label" > "$st/dev.label"; exit 0 ;;
  status)
    [ -s "$st/map.active" ] || exit 4
    printf '/dev/mapper/workspaces is active.\n  type:    LUKS2\n  device:  %s\n' "$(cat "$st/backing")"; exit 0 ;;
  luksUUID)
    [ -f "$st/fail.luksUUID" ] && exit 1
    if [ -s "$st/dev.uuid" ]; then cat "$st/dev.uuid"; echo; else printf '11111111-2222-3333-4444-555555555555\n'; fi
    exit 0 ;;
  luksHeaderBackup)
    [ -f "$st/fail.hdrbackup" ] && exit 1
    f=""; while [ $# -gt 0 ]; do [ "$1" = --header-backup-file ] && f="$2"; shift; done
    head -c 4096 /dev/zero > "$f"; exit 0 ;;
  isLuks) exit 1 ;;
esac
_L "TRAP cryptsetup ${verb:-unknown-verb} $*"
exit 99
EOF
  mkstub "$d" mkfs.ext4 <<'EOF'
_L "mkfs.ext4 $*"
st="$FX/st"
[ -f "$st/fail.mkfs" ] && { printf 'mkfs.ext4: simulated failure FIXTURE-CAUSE-MKFS %s\n' "$(head -c "$(cat "$st/fail.mkfs.pad" 2>/dev/null || echo 0)" /dev/zero | tr '\0' x)" >&2; exit 1; }
printf 'ext4' > "$st/map.type"; printf 'ext4 signature\n' > "$st/map.wipefs"
[ -f "$st/crash_after_mkfs" ] && kill -9 "$PPID"
exit 0
EOF
  # wipefs is called READ-ONLY (device argument only); any flag is a write mode and a TRAP.
  mkstub "$d" wipefs <<'EOF'
_L "wipefs $*"
st="$FX/st"
for a in "$@"; do case "$a" in -*) _L "TRAP wipefs-flag $a"; exit 99 ;; esac; done
last="${*: -1}"
if [ "$last" = /dev/mapper/workspaces ]; then cat "$st/map.wipefs" 2>/dev/null; else cat "$st/dev.wipefs" 2>/dev/null; fi
exit 0
EOF
  # shred is legitimate ONLY on the header temp files (cleanup); anywhere else it is a TRAP.
  mkstub "$d" shred <<'EOF'
_L "shred $*"
for a in "$@"; do
  case "$a" in
    -*) ;;
    *lukshdr*) rm -f "$a" ;;
    *) _L "TRAP shred $a"; exit 99 ;;
  esac
done
exit 0
EOF
  for t in mkfs mkfs.ext2 mkfs.ext3 mkfs.xfs mkfs.btrfs mkfs.vfat mkfs.fat mkfs.f2fs mkfs.ntfs mke2fs blkdiscard sgdisk sfdisk parted fstrim dd; do
    mkstub "$d" "$t" <<EOF
_L "TRAP $t \$*"
exit 99
EOF
  done
  mkstub "$d" lsblk <<'EOF'
_L "lsblk $*"
st="$FX/st"
echo sdb
c=$(cat "$st/dev.children" 2>/dev/null || echo 0); i=0; while [ "$i" -lt "$c" ]; do echo "sdb$((i+1))"; i=$((i+1)); done
[ -s "$st/map.active" ] && echo workspaces
exit 0
EOF
  mkstub "$d" findmnt <<'EOF'
_L "findmnt $*"
st="$FX/st"
case "$*" in
  *"-S /dev/mapper/workspaces"*) [ -s "$st/map.mounted_direct" ] && echo /mnt/elsewhere; exit 0 ;;
  *"-S /dev/disk/by-id/"*)
    n=$(( $(cat "$st/findmnt.dev.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/findmnt.dev.n"
    [ -s "$st/dev.mounted" ] && echo /mnt/elsewhere
    [ -s "$st/dev.mounted_after" ] && [ "$n" -gt "$(cat "$st/dev.mounted_after")" ] && echo /mnt/elsewhere
    exit 0 ;;
  *"-o SOURCE /mnt/data"*) [ -s "$st/mounted" ] || exit 1; if [ -s "$st/mounted.src" ]; then cat "$st/mounted.src"; else echo /dev/mapper/workspaces; fi; exit 0 ;;
esac
exit 0
EOF
  mkstub "$d" mountpoint <<'EOF'
_L "mountpoint $*"
[ -s "$FX/st/mounted" ]
EOF
  mkstub "$d" mount <<'EOF'
_L "mount $*"
[ -f "$FX/st/fail.mount" ] && exit 32
grep -qxF '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2' "$FX/root/etc/fstab" || exit 33
echo 1 > "$FX/st/mounted"; exit 0
EOF
  mkstub "$d" chattr <<'EOF'
_L "chattr $*"
[ -f "$FX/st/fail.chattr" ] && exit 1
echo 1 > "$FX/st/immutable"; exit 0
EOF
  mkstub "$d" lsattr <<'EOF'
_L "lsattr $*"
if [ -s "$FX/st/immutable" ] && [ ! -f "$FX/st/lsattr.hide" ]; then echo '----i---------e------- /mnt/data'; else echo '--------------e------- /mnt/data'; fi
EOF
  mkstub "$d" systemctl <<'EOF'
_L "systemctl $*"
st="$FX/st"
case "$*" in
  "enable workspaces-luks-reopen"*) [ -f "$st/fail.enable" ] && exit 1 ;;
  "is-enabled "*) [ -f "$st/fail.isenabled" ] && exit 1 ;;
  *luks-monitor.timer*) [ -f "$st/fail.monitor" ] && exit 1 ;;
esac
exit 0
EOF
  mkstub "$d" logger <<'EOF'
_L "logger $*"
exit 0
EOF
  mkstub "$d" soleur-boot-emit <<'EOF'
_L "boot-emit $*"
exit 0
EOF
  mkstub "$d" sleep <<'EOF'
_L "sleep $*"
exit 0
EOF
  # flock logs its argv and then DELEGATES to the real flock, so one stub serves the argv-spelling rows
  # (the calls log) and the real-exclusion rows (a background holder on the same lock file).
  mkstub "$d" flock <<EOF
_L "flock \$*"
exec $FLOCK_REAL "\$@"
EOF
  # sync records its argv and never touches the disk. fail.sync = "<mode>[ <substring>]": mode tmp fails the
  # fsync of a *.provision.tmp temp file, mode dir fails the fsync of anything else (the directory after the
  # rename); the optional substring narrows the failure to one path.
  mkstub "$d" sync <<'EOF'
_L "sync $*"
m=$(cat "$FX/st/fail.sync" 2>/dev/null || true); mode=${m%% *}; pat=""; [ "$m" = "$mode" ] || pat=${m#* }
for a in "$@"; do
  case "$a" in
    *.provision.tmp) [ "$mode" = tmp ] && case "$a" in *"$pat"*) exit 1 ;; esac ;;
    -*) ;;
    *) [ "$mode" = dir ] && case "$a" in *"$pat"*) exit 1 ;; esac ;;
  esac
done
exit 0
EOF
  # apt-get: always fails, unless the fixture says the install lands on the 2nd attempt.
  mkstub "$d" apt-get <<'EOF'
_L "apt-get $*"
st="$FX/st"
n=$(( $(cat "$st/apt.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/apt.n"
if [ -f "$st/apt.install_on_2" ] && [ "$n" -ge 2 ]; then cp "$st/cryptsetup.saved" "$FX/bin/cryptsetup"; exit 0; fi
exit 100
EOF
  # blockdev reports the size of the fixture's regular-file device (so the zero-content probe and the
  # reported size agree); zero_until simulates an attachment that lags server boot.
  mkstub "$d" blockdev <<'EOF'
_L "blockdev $*"
st="$FX/st"
n=$(( $(cat "$st/blockdev.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/blockdev.n"
if [ "$n" -le "$(cat "$st/blockdev.zero_until" 2>/dev/null || echo 0)" ]; then echo 0; exit 0; fi
stat -c %s "$FX/root${*: -1}" 2>/dev/null || echo 21474836480
EOF
  mkstub "$d" doppler <<'EOF'
_L "doppler $*"
st="$FX/st"
printf '%s\n' "${DOPPLER_TOKEN:-}" >> "$st/doppler.tokens"
name="$3"
if [ "$name" = WORKSPACES_LUKS_KEY ]; then
  [ -f "$st/doppler.down" ] && exit 1
  n=$(cat "$st/doppler.fail_n" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$st/doppler.fail_n"; exit 1; fi
  cat "$st/key"; exit 0
fi
[ -s "$st/doppler.$name" ] || exit 1
cat "$st/doppler.$name"
EOF
  # curl models an S3-ish object store: PUT stores size + md5 (the single-part ETag); HEAD returns both.
  mkstub "$d" curl <<'EOF'
_L "curl $*"
st="$FX/st"
cfg=""; if printf '%s ' "$@" | grep -q -- '--config -'; then cfg=$(cat); printf '%s\n' "$cfg" >> "$st/curl.cfg"; fi
method=GET; dfile=""; up=""; code_out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -I) method=HEAD ;;
    -T) method=PUT; up="$2"; shift ;;
    -D) dfile="$2"; shift ;;
    -w) code_out="$2"; shift ;;
  esac
  shift
done
code=200
if [ "$method" = PUT ]; then
  if [ -f "$st/fail.put" ]; then code=403
  elif [ -f "$st/put.noop" ]; then code=200
  else echo "$(stat -c %s "$up")" > "$st/s3.len"; md5sum "$up" | cut -d' ' -f1 > "$st/s3.etag"; code=200; fi
elif [ "$method" = HEAD ]; then
  if [ -f "$st/fail.head" ]; then code=500; elif [ -s "$st/s3.len" ]; then code=200; else code=404; fi
fi
[ -z "$dfile" ] || printf 'HTTP/1.1 %s\r\ncontent-length: %s\r\nETag: "%s"\r\n\r\n' "$code" "$(cat "$st/s3.len" 2>/dev/null || echo 0)" "$(cat "$st/s3.etag" 2>/dev/null || echo none)" > "$dfile"
[ -z "$code_out" ] || printf '%s' "$code"
exit 0
EOF
  chmod 0755 "$d"/*
}

STUBS="$SCRATCH/stubs"
write_stubs "$STUBS"

new_fx() { # builds a pristine fixture; sets FX
  FX="$(mktemp -d "$SCRATCH/fx.XXXXXXXX")"
  assert_fixture_dir "$FX"
  mkdir -p "$FX/bin" "$FX/st" "$FX/root/etc/default" "$FX/root/etc/systemd/system" "$FX/root/var/lib" "$FX/root/run" "$FX/root/mnt" "$FX/root/dev/disk/by-id"
  : > "$FX/calls"
  cp "$STUBS"/* "$FX/bin/"
  truncate -s "$DEVSIZE" "$FX/root$DEVPIN"
  printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"
  chmod 600 "$FX/root/etc/default/workspaces-luks-boot"
  printf 'SOLEUR_SENTRY_DSN=https://example.invalid/1\nDOPPLER_TOKEN=%s\n' "$TOKVAL" > "$FX/root/etc/default/luks-monitor"
  chmod 600 "$FX/root/etc/default/luks-monitor"
  printf '# fstab\n' > "$FX/root/etc/fstab"
  : > "$FX/root/etc/crypttab"
  chmod 644 "$FX/root/etc/fstab" "$FX/root/etc/crypttab" # explicit: an existing file's mode is preserved, so the fixture must not depend on the runner's umask
  printf '%s\n' "$DEVPIN" > "$FX/st/backing"
  printf '%s' "$KEYVAL" > "$FX/st/key"
  printf 'soleur-test-header\n' > "$FX/st/doppler.WORKSPACES_HEADER_BUCKET"
  printf 'TESTKEYID0001\n' > "$FX/st/doppler.WORKSPACES_HEADER_R2_ACCESS_KEY_ID"
  printf '%s\n' "$SECVAL" > "$FX/st/doppler.WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY"
  printf 'https://%s.r2.cloudflarestorage.com\n' "$ACCT" > "$FX/st/doppler.WORKSPACES_HEADER_R2_ENDPOINT"
}
# A REPLACEMENT host: a fresh root disk (no state dir, nothing wired) in front of the SAME volume
# (its signature, label and key survive; the mapper is closed).
replace_host() { # <old-fx>: sets FX to the new host
  local old="$1"
  new_fx
  cp "$old/st"/dev.* "$FX/st/" 2>/dev/null || true
  cp "$old/root$DEVPIN" "$FX/root$DEVPIN"
}
put_at() { printf 'DATA' | dd of="$FX/root$DEVPIN" bs=1 seek="$1" conv=notrunc status=none; } # non-zero bytes at an offset of the fixture device

run_sut() { # runs the provisioner in $FX; sets RC
  RC=0
  # The soft core limit is raised first so that "the provisioner lowered it" is observable.
  ( ulimit -S -c unlimited 2>/dev/null || ulimit -S -c "$(ulimit -H -c)" 2>/dev/null
    exec env -i PATH="$FX/bin:/usr/bin:/bin" FX="$FX" WLP_STUB_NOLOG="${WLP_STUB_NOLOG:-}" WORKSPACES_PROVISION_LOCK_WAIT="${WLP_LOCK_WAIT:-}" \
    WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" ${WLP_RUN_TIMEOUT:+timeout $WLP_RUN_TIMEOUT} bash "${1:-$SUT}" > "$FX/out" 2> "$FX/err" < /dev/null ) || RC=$?
}

has()  { grep -qE -- "$1" "$FX/calls"; }
lack() { ! grep -qE -- "$1" "$FX/calls"; }
lineno() { grep -nE -- "$1" "$FX/calls" | head -1 | cut -d: -f1; }
count_calls() { grep -cE -- "$1" "$FX/calls" || true; }
detail() { cat "$FX/root/detail/$1" 2>/dev/null; }
mode_is() { [ "$(stat -c %a "$1" 2>/dev/null)" = "$2" ]; }
secret_absent() { ! grep -rqs -- "$1" "$FX/calls" "$FX/out" "$FX/err" "$FX/root/detail"; }
UUID_DEF=11111111-2222-3333-4444-555555555555
uuid_cur() { if [ -s "$FX/st/dev.uuid" ]; then cat "$FX/st/dev.uuid"; else printf '%s' "$UUID_DEF"; fi; }
# an intent file as the provisioner writes it: <DEV> <luksUUID> <epoch>
put_intent() { mkdir -p "$FX/root/var/lib/soleur"; printf '%s %s 1\n' "${1:-$DEVPIN}" "${2:-$UUID_DEF}" > "$FX/root/$INTENT_F"; }
label_is() { [ "$(cat "$FX/st/dev.label" 2>/dev/null)" = "$1" ]; }
arm_line() { sed -n "$1p" "$FX/root/run/soleur/workspaces-luks-arm"; }

# Spelling-independent handles on what the cryptsetup/mkfs stubs saw.
V_FORMAT='^cryptsetup-verb luksFormat$'
V_OPEN='^cryptsetup-verb luksOpen$'
V_CONFIG='^cryptsetup-verb config$'
MKFS='^mkfs\.ext4 '
INTENT_F="var/lib/soleur/workspaces-luks-formatting"
intent_present() { [ -e "$FX/root/$INTENT_F" ]; }

CASES_RUN=()
dropped() { [ -n "${WLP_DROP_CASE:-}" ] && [ "$WLP_DROP_CASE" = "$1" ]; }
# A dropped case is NOT recorded, so the case-set assertion below reds on a deleted case.
ONLY=""; [ -z "$WLP_MUTANT" ] || ONLY="${WLP_ONLY_CASES:-}" # never restricts the outer (control) run
begin() {
  dropped "$1" && return 1
  if [ -n "$ONLY" ]; then case " $ONLY " in *" $1 "*) : ;; *) return 1 ;; esac; fi
  CASES_RUN+=("$1"); return 0
}

# The ONLY calls a refusal case may have made: read-only probes, the key fetch, logging/emitting, the
# sleeps of the retry ladders. Anything else (a cryptsetup verb that is not status/luksUUID, a mkfs, a
# mount, a chattr, a systemctl, a TRAP) is a write and reds the case.
READONLY='^(flock -w [0-9]+ 9$|sync( |$)|blkid |lsblk |findmnt |mountpoint |blockdev --getsize64 |lsattr |sleep |logger |boot-emit |doppler secrets get |wipefs [^ -][^ ]*$|cryptsetup (status|luksUUID) |cryptsetup-verb (status|luksUUID)$|apt-get install -y -o DPkg::Lock::Timeout=300 cryptsetup-bin$)'
no_writes() { ! grep -vE -- "$READONLY" "$FX/calls" | grep -q .; }
files_untouched() { [ "$(cat "$FX/root/etc/fstab")" = "# fstab" ] && [ ! -s "$FX/root/etc/crypttab" ] && [ ! -e "$FX/root/etc/systemd/system/docker.service.d" ]; }

# Static handles on the provisioner CODE. scode is the comment-stripped source with line numbers preserved;
# sblk / sfn print a sentinel-delimited block / a function body verbatim, so a case can EXECUTE the very
# lines the provisioner ships (with its one constant swapped) instead of grepping for them.
scode() { awk '{ s=$0; sub(/^[[:space:]]*#.*/, "", s); print s }' "$SUT"; }
sline() { scode | grep -nE -- "$1" | head -1 | cut -d: -f1; }
sblk() { awk -v n="$1" '$0 == "# >>> " n { f = 1; next } $0 == "# <<< " n { f = 0 } f' "$SUT"; }
sfn() { awk -v n="$1" '$0 ~ "^" n "\\(\\) \\{" { f = 1 } f { print } f && /^\}/ { exit }' "$SUT"; }
CORE_TOOLS="awk sed grep cat stat id mkdir mv rm rmdir date sync realpath mktemp sha256sum md5sum cmp cut head tail tr wc ls sort chmod chown timeout bash dirname env printf kill cp"
mk_core() { # $FX/core: symlinks to ONLY the tools the script needs (no flock, no cryptsetup)
  local t; mkdir -p "$FX/core"
  for t in $CORE_TOOLS; do ln -s "$(command -v "$t")" "$FX/core/$t" 2>/dev/null || true; done
}
open_fx() { new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; printf '%s' "$LBL_R" > "$FX/st/dev.label"; } # a LUKS volume with a filesystem: the open arm, so only the wire step writes
no_tmp_left() { ! find "$FX/root" -name '*.provision.tmp' 2>/dev/null | grep -q .; }
victims_intact() { local t; for t in fstab crypttab dropin intent; do [ "$(cat "$FX/victim.$t" 2>/dev/null)" = "VICTIM-$t" ] || return 1; done; }
LOCKF() { printf '%s' "$FX/root/run/workspaces-luks-provision.lock"; }
hold_lock() { # a REAL flock holder on the provisioner's lock file, in the background; sets HOLDER; waits until it holds
  mkdir -p "$FX/root/run"; rm -f "$FX/st/held"
  ( exec 9> "$(LOCKF)"; "$FLOCK_REAL" 9 && : > "$FX/st/held" && exec "$SLEEP_REAL" 25 ) > /dev/null 2>&1 & # 25 s: long enough for any contended run, short enough that a mutant with an unbounded wait ends the row soon
  HOLDER=$!
  for _ in $(seq 1 100); do [ -e "$FX/st/held" ] && return 0; "$SLEEP_REAL" 0.05; done
  return 1
}
wait_unlocked() { local _; for _ in $(seq 1 100); do "$FLOCK_REAL" -n "$(LOCKF)" true 2>/dev/null && return 0; "$SLEEP_REAL" 0.05; done; return 1; }

# ── cases ─────────────────────────────────────────────────────────────────────────────────────
# The first-boot raw-device birth, asserted as four cases of at most 8 assertions each (it was one
# case of ~32): raw_order (the destructive sequence and its argv), raw_wiring (what the wire step leaves),
# raw_secret_hygiene (what must never reach argv, logs or a forbidden tool) and raw_idempotent (the end
# state and the second run on it).
# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_raw_order() {
  begin raw_order || return
  new_fx; run_sut
  expect "raw: rc 0" test "$RC" -eq 0
  local a b c d
  a=$(lineno "$V_FORMAT"); b=$(lineno "$V_OPEN"); c=$(lineno "$MKFS"); d=$(lineno "$V_CONFIG")
  expect "raw: luksFormat -> luksOpen -> mkfs -> relabel in that order" all 'test -n "$a" -a -n "$b" -a -n "$c" -a -n "$d"' '[ "$a" -lt "$b" ]' '[ "$b" -lt "$c" ]' '[ "$c" -lt "$d" ]'
  expect "raw: luksFormat uses luks2 + batch-mode + the formatting label + a pre-assigned UUID + stdin key" has "^cryptsetup luksFormat --batch-mode --type luks2 --label $LBL_F --uuid [0-9a-f-]{36} --key-file - "
  expect "raw: luksFormat targets the pinned device and luksOpen the pinned device + mapper" all "has '^cryptsetup luksFormat .* $DEVPIN\$'" "has '^cryptsetup luksOpen --key-file - $DEVPIN workspaces\$'"
  expect "raw: mkfs targets the MAPPER, never the device" all "has '^mkfs\.ext4 -q /dev/mapper/workspaces\$'" "lack '^mkfs\.ext4 .*/dev/disk'"
  expect "raw: the intent file existed and luksFormat was told the label and UUID; the core limit was already 0" has "^luksFormat-state intent_present=1 label=$LBL_F uuid=[0-9a-f-]{36} core=0\$"
  expect "raw: the volume carries the UUID the intent recorded, and luksUUID was read back" all 'test -s "$FX/st/dev.uuid"' "has '^cryptsetup luksUUID $DEVPIN\$'"
  expect "raw: the relabel targets the pinned device with the final label, after mkfs" has "^cryptsetup config $DEVPIN --label $LBL_R\$"
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_raw_wiring() {
  begin raw_wiring || return
  new_fx; run_sut
  expect "raw: arm file says formatted + escrow ok" test "$(cat "$FX/root/run/soleur/workspaces-luks-arm")" = "$(printf 'luks_arm=formatted\nescrow=ok')"
  expect "raw: crypttab holds the canonical line exactly once" test "$(cat "$FX/root/etc/crypttab")" = "workspaces $DEVPIN none luks,noauto"
  expect "raw: fstab holds exactly one /mnt/data line and it is the canonical one" all 'test "$(grep -vc "^#" "$FX/root/etc/fstab")" -eq 1' "grep -qxF '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2' \"\$FX/root/etc/fstab\""
  expect "raw: the docker drop-in is the canonical 3 lines" test "$(cat "$FX/root/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf")" = "$(printf '[Unit]\nRequiresMountsFor=/mnt/data\nAfter=workspaces-luks-reopen.service')"
  expect "raw: wired modes: fstab 644, drop-in 644, drop-in dir 755, covered mountpoint 755" all 'mode_is "$FX/root/etc/fstab" 644' 'mode_is "$FX/root/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf" 644' 'mode_is "$FX/root/etc/systemd/system/docker.service.d" 755' 'mode_is "$FX/root/mnt/data" 755'
  local ci mo
  ci=$(lineno '^chattr \+i'); mo=$(lineno '^mount /mnt/data')
  expect "raw: the covered inode is made immutable BEFORE the mount" all 'test -n "$ci" -a -n "$mo"' '[ "$ci" -lt "$mo" ]'
  expect "raw: the reopen service + timer are enabled and verified enabled" all "has '^systemctl enable workspaces-luks-reopen\.service workspaces-luks-reopen\.timer'" "has '^systemctl is-enabled workspaces-luks-reopen\.service workspaces-luks-reopen\.timer'"
  expect "raw: the daily probe timer is enabled and the service is NOT started (Row 10 of luks-monitor-install)" all "has '^systemctl enable --now luks-monitor\.timer'" "lack 'luks-monitor\.service'"
}

case_raw_secret_hygiene() {
  begin raw_secret_hygiene || return
  new_fx; run_sut
  expect "raw: never calls isLuks" lack 'isLuks'
  expect "raw: no TRAP stub (a destructive-capable binary) was hit" lack '^TRAP '
  expect "raw: the passphrase never appears in any argv, log or detail" secret_absent "$KEYVAL"
  expect "raw: the doppler token reaches doppler by env, never argv, logs or details" all 'test -n "$(sort -u "$FX/st/doppler.tokens")"' 'test "$(sort -u "$FX/st/doppler.tokens")" = "$TOKVAL"' 'secret_absent "$TOKVAL"'
  expect "raw: the key is fetched with the R9-pinned single-secret form" has '^doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks_web$'
  expect "raw: never uses doppler run or secrets download" lack 'doppler (run|secrets download)'
  expect "raw: the evidence row is logged under the journald tag Vector already ships (workspaces-luks-reopen), never a new tag" all "has '^logger -t workspaces-luks-reopen -- SOLEUR_WORKSPACES_LUKS_PROVISION '" "lack '^logger -t workspaces-luks-provision'"
  expect "raw: a result row is logged" grep -q 'arm=result rc=0 luks_arm=formatted escrow=ok' "$FX/err"
}

case_raw_idempotent() {
  begin raw_idempotent || return
  new_fx; run_sut
  expect "raw: the volume ends labelled with the final (non-formatting) label" label_is "$LBL_R"
  expect "raw: the intent file is gone after mkfs" test ! -e "$FX/root/$INTENT_F"
  expect "raw: exactly one luksFormat, one mkfs, one relabel" all 'test "$(count_calls "$V_FORMAT")" -eq 1' 'test "$(count_calls "$MKFS")" -eq 1' 'test "$(count_calls "$V_CONFIG")" -eq 1'
  # second run on the state the first run left behind (the provisioner is idempotent): a no-op.
  : > "$FX/calls"; run_sut
  expect "raw: second run rc 0" test "$RC" -eq 0
  expect "raw: second run is a no-op (no luksFormat/luksOpen/relabel/mkfs)" lack '^cryptsetup-verb (luksFormat|luksOpen|config)$|^mkfs\.|^TRAP '
  expect "raw: second run records noop" test "$(head -1 "$FX/root/run/soleur/workspaces-luks-arm")" = luks_arm=noop
  expect "raw: second run leaves one crypttab line and one fstab line" all 'test "$(grep -c . "$FX/root/etc/crypttab")" -eq 1' 'test "$(grep -vc "^#" "$FX/root/etc/fstab")" -eq 1'
  expect "raw: second run does not re-upload an escrowed header" lack '^curl .*-T '
}

case_luks_opens() {
  begin luks_open || return
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; printf '%s' "$LBL_R" > "$FX/st/dev.label"
  run_sut
  expect "luks: rc 0" test "$RC" -eq 0
  expect "luks: opens the mapper" has '^cryptsetup luksOpen '
  expect "luks: never formats, never relabels and never mkfs" lack '^cryptsetup-verb (luksFormat|config)$|^mkfs\.|^TRAP '
  expect "luks: arm is opened" test "$(head -1 "$FX/root/run/soleur/workspaces-luks-arm")" = luks_arm=opened
  # A crash between mkfs and the relabel leaves ext4 under the FORMATTING label: the open arm closes
  # that window so the label can never authorise a mkfs on a store that later reads blank by damage.
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; printf '%s' "$LBL_F" > "$FX/st/dev.label"
  run_sut
  expect "luks: ext4 under the formatting label is healed to the final label (rc 0, no mkfs, no format)" all 'test "$RC" -eq 0' 'label_is "$LBL_R"' "lack '^cryptsetup-verb luksFormat\$|^mkfs\.|^TRAP '"
}

case_ext4_refused() {
  begin ext4 || return
  new_fx; printf 'ext4' > "$FX/st/dev.type"
  run_sut
  expect "ext4: FATAL discriminate (12)" test "$RC" -eq 12
  expect "ext4: ZERO write calls (every call is on the read-only allow-list)" no_writes
  expect "ext4: no key was even fetched" lack '^doppler '
  expect "ext4: fstab, crypttab and the drop-in were not written" files_untouched
  expect "ext4: the discriminate stage is emitted" has '^boot-emit workspaces_luks_provision_discriminate fatal'
}

case_blkid_rc() {
  begin blkid_rc || return
  local rc
  for rc in 4 8; do
    new_fx; printf '%s' "$rc" > "$FX/st/blkid.rc"
    run_sut
    expect "blkid rc $rc: FATAL discriminate" test "$RC" -eq 12
    expect "blkid rc $rc: ZERO write calls" no_writes
  done
}

case_signatures_refused() {
  begin signatures || return
  new_fx; printf 'gpt' > "$FX/st/dev.pttype"
  run_sut
  expect "empty TYPE + GPT: FATAL (a TYPE-only discriminator would format a partitioned disk)" test "$RC" -eq 12
  expect "empty TYPE + GPT: ZERO write calls" no_writes
  new_fx; printf 'zfs_member signature\n' > "$FX/st/dev.wipefs"
  run_sut
  expect "empty TYPE + wipefs signature: FATAL" test "$RC" -eq 12
  expect "empty TYPE + wipefs signature: ZERO write calls" no_writes
  new_fx; printf '1' > "$FX/st/dev.children"
  run_sut
  expect "empty TYPE + a child device: FATAL" test "$RC" -eq 12
  expect "empty TYPE + a child device: ZERO write calls" no_writes
  new_fx; printf '1' > "$FX/st/dev.mounted"
  run_sut
  expect "device mounted directly: FATAL" test "$RC" -eq 11
  expect "device mounted directly: ZERO write calls" no_writes
  # TOCTOU: the device is NOT mounted at the device arm or at discriminate, and IS by the re-check.
  new_fx; printf '2' > "$FX/st/dev.mounted_after"
  run_sut
  expect "device mounted between discriminate and luksFormat: FATAL format (14), no luksFormat" all 'test "$RC" -eq 14' "lack '^cryptsetup-verb luksFormat\$'"
}

# The content probe: "no signature libblkid knows" is not "empty". blkid/wipefs read the BLANK
# in every row below (the stubs have no signature); only the bytes of the device say otherwise.
case_zero_probe() {
  begin zero_probe || return
  local sz
  new_fx; put_at 8192
  run_sut
  expect "zero probe: data right after a zeroed 8 KiB header (head of the device): FATAL discriminate (12)" test "$RC" -eq 12
  expect "zero probe: head data: ZERO write calls and no key fetched" all 'no_writes' "lack '^doppler '"
  new_fx; put_at $((15 * 1024 * 1024))
  run_sut
  expect "zero probe: data at 15 MiB (inside the 16 MiB head window): FATAL (12), ZERO write calls" all 'test "$RC" -eq 12' 'no_writes'
  sz=$((300 * 1024 * 1024))
  new_fx; put_at $((sz - 1048576))
  run_sut
  expect "zero probe: data in the last 16 MiB (tail of the device): FATAL (12), ZERO write calls" all 'test "$RC" -eq 12' 'no_writes'
  new_fx; put_at $((134217728 + 4096))
  run_sut
  expect "zero probe: data in the 128 MiB window (first ext4 backup superblock): FATAL (12), ZERO write calls" all 'test "$RC" -eq 12' 'no_writes'
  new_fx; put_at $((sz - 16777216 + 2))
  run_sut
  expect "zero probe: data in the first byte-run of the tail window is also refused" all 'test "$RC" -eq 12' 'no_writes'
  new_fx; run_sut
  expect "zero probe: an all-zero device is formatted (the probe does not refuse a clean birth)" all 'test "$RC" -eq 0' "has '$V_FORMAT'"
  # A device smaller than the windows: the windows clamp to its size.
  new_fx; truncate -s 4M "$FX/root$DEVPIN"
  run_sut
  expect "zero probe: a 4 MiB all-zero device (smaller than every window) is formatted" all 'test "$RC" -eq 0' "has '$V_FORMAT'"
  new_fx; truncate -s 4M "$FX/root$DEVPIN"; put_at 3000000
  run_sut
  expect "zero probe: a 4 MiB device with data in it is refused (12)" all 'test "$RC" -eq 12' 'no_writes'
  # A REAL ext4 image whose first 8 KiB was zeroed: the case blkid and wipefs read as blank.
  new_fx
  if command -v mke2fs >/dev/null 2>&1 && mke2fs -q -t ext4 -F "$FX/root$DEVPIN" >/dev/null 2>&1; then
    dd if=/dev/zero of="$FX/root$DEVPIN" bs=4096 count=2 conv=notrunc status=none
    run_sut
    expect "zero probe: a real populated ext4 volume with its first 8 KiB zeroed is refused (12), ZERO write calls" all 'test "$RC" -eq 12' 'no_writes'
  else
    ok 0 "zero probe: a real ext4 image is not buildable here (mke2fs absent); the synthetic rows above carry the claim"
  fi
}

case_blank_mapper() {
  begin blank_mapper || return
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"          # LUKS container, blank mapper, NO intent file, NO label
  run_sut
  expect "blank mapper with neither intent nor label: FATAL open (15) — a damaged store" test "$RC" -eq 15
  expect "blank mapper with neither intent nor label: NEVER mkfs and never relabel" lack '^mkfs\.|^cryptsetup-verb config$'
  expect "blank mapper with neither intent nor label: the fatal says why" grep -q 'neither a volume-bound format intent nor the formatting label' "$FX/root/detail/workspaces_luks_provision_open"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf '%s' "$LBL_R" > "$FX/st/dev.label"   # the FINAL label authorises nothing
  run_sut
  expect "blank mapper under the FINAL label and no intent: FATAL open (15), no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; put_intent
  printf 'leftover signature\n' > "$FX/st/map.wipefs"
  run_sut
  expect "blank mapper WITH intent but a visible signature: FATAL, no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; put_intent
  run_sut
  expect "blank mapper with a volume-bound intent and NO label (same host, intent-only): recovers, rc 0, one mkfs on the mapper" all 'test "$RC" -eq 0' 'test "$(count_calls "$MKFS")" -eq 1' 'label_is "$LBL_R"' '! intent_present'
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; put_intent "$DEVPIN" ffffffff-ffff-ffff-ffff-ffffffffffff
  run_sut
  expect "blank mapper with an intent bound to ANOTHER volume's UUID and no label: FATAL open (15), no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; put_intent /dev/disk/by-id/scsi-0HC_Volume_999
  run_sut
  expect "blank mapper with an intent recorded for ANOTHER device and no label: FATAL open (15), no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; put_intent; : > "$FX/st/fail.luksUUID"
  run_sut
  expect "blank mapper with an intent but an UNREADABLE volume UUID and no label: FATAL open (15), no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf '%s' "$LBL_F" > "$FX/st/dev.label"; printf 'leftover signature\n' > "$FX/st/map.wipefs"
  run_sut
  expect "blank mapper WITH the formatting label but a visible signature: FATAL, no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf '%s' "$LBL_F" > "$FX/st/dev.label"; printf '1' > "$FX/st/map.mounted_direct"
  run_sut
  expect "blank mapper WITH the formatting label but mounted elsewhere: FATAL, no mkfs" all 'test "$RC" -eq 15' "lack '^mkfs\.'"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf '%s' "$LBL_F" > "$FX/st/dev.label"
  run_sut
  expect "blank mapper WITH the formatting label and NO intent file (a replacement host): recovers, rc 0" test "$RC" -eq 0
  expect "label-only recovery: exactly one mkfs on the MAPPER, never a luksFormat" all 'test "$(count_calls "$MKFS")" -eq 1' "has '^mkfs\.ext4 -q /dev/mapper/workspaces\$'" "lack '$V_FORMAT'"
  expect "label-only recovery: the volume ends under the final label, arm formatted, mapper mounted" all 'label_is "$LBL_R"' 'test "$(head -1 "$FX/root/run/soleur/workspaces-luks-arm")" = luks_arm=formatted' 'test -s "$FX/st/mounted"'
}

case_crash_recovery() {
  begin crash || return
  local crashed
  new_fx; : > "$FX/st/crash_after_luksFormat"
  run_sut
  expect "crash after luksFormat: the process died (137)" test "$RC" -eq 137
  expect "crash after luksFormat: the intent file survives on this host and the formatting label on the volume" all 'intent_present' 'label_is "$LBL_F"'
  expect "crash after luksFormat: the intent file is bound to the volume (records DEV and the volume's UUID)" test "$(awk '{print $1 " " $2}' "$FX/root/$INTENT_F")" = "$DEVPIN $(uuid_cur)"
  expect "crash after luksFormat: no mkfs yet" lack '^mkfs\.'
  crashed="$SCRATCH/crashed.$$"; rm -rf "$crashed"; mkdir -p "$crashed"; cp -a "$FX/st" "$crashed/"
  rm -f "$FX/st/crash_after_luksFormat"; : > "$FX/calls"
  run_sut
  expect "re-run on the same host after the crash: rc 0" test "$RC" -eq 0
  expect "re-run on the same host after the crash: finishes mkfs exactly once, never luksFormat" all 'test "$(count_calls "$MKFS")" -eq 1' "lack '$V_FORMAT'"
  expect "re-run on the same host after the crash: the intent file is removed and the final label set" all '! intent_present' 'label_is "$LBL_R"'
  expect "re-run on the same host after the crash: the mapper ends mounted" test -s "$FX/st/mounted"
  # The REAL recovery path: the host is replaced; its root disk has no intent file, the volume has its label.
  new_fx; cp "$crashed/st"/dev.* "$FX/st/"
  run_sut
  expect "host replaced after the crash (no intent file, label on the volume): rc 0" test "$RC" -eq 0
  expect "host replaced after the crash: finishes mkfs exactly once on the mapper, never luksFormat, never the device" all 'test "$(count_calls "$MKFS")" -eq 1' "lack '$V_FORMAT'" "lack '^mkfs\.ext4 .*/dev/disk'"
  expect "host replaced after the crash: the volume ends under the final label and mounted" all 'label_is "$LBL_R"' 'test -s "$FX/st/mounted"'
  new_fx; : > "$FX/st/crash_after_mkfs"
  run_sut
  expect "crash after mkfs: the process died (137)" test "$RC" -eq 137
  expect "crash after mkfs: ext4 exists but the volume still carries the formatting label" label_is "$LBL_F"
  crashed="$SCRATCH/crashed2.$$"; rm -rf "$crashed"; mkdir -p "$crashed"; cp -a "$FX/st" "$crashed/"
  rm -f "$FX/st/crash_after_mkfs"; : > "$FX/calls"
  run_sut
  expect "re-run after a post-mkfs crash: rc 0, no second mkfs, intent removed, label healed" all 'test "$RC" -eq 0' '! intent_present' 'label_is "$LBL_R"' "lack '^mkfs\.'"
  new_fx; cp "$crashed/st"/dev.* "$FX/st/"; cp "$crashed/st/map.type" "$FX/st/map.type"
  run_sut
  expect "host replaced after a post-mkfs crash: rc 0, no mkfs, no luksFormat, label healed" all 'test "$RC" -eq 0' "lack '^mkfs\.|$V_FORMAT'" 'label_is "$LBL_R"'
  rm -rf "$SCRATCH"/crashed*
}

case_state_change() {
  begin state_change || return
  new_fx; printf '2' > "$FX/st/flip_after"                    # blkid calls 1-2 read raw; call 3 reads ext4
  run_sut
  expect "device changes state after discriminate: FATAL format (14)" test "$RC" -eq 14
  expect "device changes state after discriminate: luksFormat is NEVER called" lack "$V_FORMAT"
  expect "device changes state after discriminate: the intent file is not left behind and no label was written" all '! intent_present' 'test ! -s "$FX/st/dev.label"'
}

# Failure switches and the mapper-level chokepoint: every destructive step that fails must stop the
# arm with the arm's code, name its cause, and leave the recovery evidence in place.
case_failures() {
  begin failures || return
  new_fx; : > "$FX/st/fail.luksFormat"
  run_sut
  expect "luksFormat fails: FATAL format (14), no luksOpen, no mkfs, no mount" all 'test "$RC" -eq 14' "lack '$V_OPEN|^mkfs\.|^mount |^TRAP '"
  expect "luksFormat fails: the cause is shipped in the detail, the key is not" all "grep -q 'luksFormat failed: Cannot format device FIXTURE-CAUSE-FORMAT' \"\$FX/root/detail/workspaces_luks_provision_format\"" 'secret_absent "$KEYVAL"'
  expect "luksFormat fails: the intent file is left for recovery" intent_present
  new_fx; : > "$FX/st/fail.mkfs"; printf '400' > "$FX/st/fail.mkfs.pad"
  run_sut
  expect "mkfs fails (format arm): FATAL format (14), no mount, no relabel" all 'test "$RC" -eq 14' "lack '^mount |$V_CONFIG|^TRAP '"
  expect "mkfs fails (format arm): the intent file is NOT removed and the label still says formatting" all 'intent_present' 'label_is "$LBL_F"'
  expect "mkfs fails (format arm): the cause is shipped, capped at 200 characters" all "grep -q 'FIXTURE-CAUSE-MKFS' \"\$FX/root/detail/workspaces_luks_provision_format\"" '! grep -q "x\{201\}" "$FX/root/detail/workspaces_luks_provision_format"'
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf '%s' "$LBL_F" > "$FX/st/dev.label"; : > "$FX/st/fail.mkfs"
  run_sut
  expect "mkfs fails (recovery arm): FATAL open (15), no mount, label still formatting" all 'test "$RC" -eq 15' "lack '^mount '" 'label_is "$LBL_F"'
  new_fx; : > "$FX/st/fail.relabel"
  run_sut
  expect "relabel fails after a good mkfs: FATAL format (14), no mount, intent kept" all 'test "$RC" -eq 14' "lack '^mount '" 'intent_present' "grep -q 'FIXTURE-CAUSE-RELABEL' \"\$FX/root/detail/workspaces_luks_provision_format\""
  new_fx; : > "$FX/st/uuid.ignore"
  run_sut
  expect "luksFormat did not apply the recorded UUID: FATAL format (14), no luksOpen, no mkfs" all 'test "$RC" -eq 14' "lack '$V_OPEN|^mkfs\.'"
  new_fx; : > "$FX/st/fail.luksOpen"
  run_sut
  expect "luksOpen fails after luksFormat: FATAL format (14), no mkfs, no mount" all 'test "$RC" -eq 14' "lack '^mkfs\.|^mount '"
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; : > "$FX/st/fail.luksOpen"
  run_sut
  expect "luksOpen fails (open arm): FATAL open (15), no mkfs, no mount, cause shipped" all 'test "$RC" -eq 15' "lack '^mkfs\.|^mount '" "grep -q 'FIXTURE-CAUSE-OPEN' \"\$FX/root/detail/workspaces_luks_provision_open\""
  # The mapper-level chokepoint, driven DYNAMICALLY: the freshly opened mapper already carries a
  # filesystem / is mounted elsewhere; the first mkfs must be refused.
  new_fx; printf 'ext4' > "$FX/st/luksOpen.preload_type"
  run_sut
  expect "new mapper already carries a filesystem: FATAL format (14), NEVER mkfs" all 'test "$RC" -eq 14' "lack '^mkfs\.'"
  new_fx; printf '1' > "$FX/st/map.mounted_direct"
  run_sut
  expect "new mapper is mounted elsewhere: FATAL format (14), NEVER mkfs" all 'test "$RC" -eq 14' "lack '^mkfs\.'"
}

case_key() {
  begin key || return
  new_fx; : > "$FX/st/doppler.down"
  run_sut
  expect "doppler down: FATAL key (13)" test "$RC" -eq 13
  expect "doppler down: the device is untouched (no write calls)" no_writes
  expect "doppler down: the retry ladder ran (19 sleeps)" test "$(count_calls '^sleep 15')" -eq 19
  new_fx; : > "$FX/st/key"
  run_sut
  expect "empty key: FATAL key (13), no luksFormat" all 'test "$RC" -eq 13' "lack '$V_FORMAT'"
  new_fx; printf '3' > "$FX/st/doppler.fail_n"
  run_sut
  expect "doppler fails 3 times then answers: succeeds inside the ladder" test "$RC" -eq 0
  expect "doppler fails 3 times then answers: slept 3 times" test "$(count_calls '^sleep 15')" -eq 3
}

case_config() {
  begin config || return
  new_fx; rm -f "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: env file absent -> 10" test "$RC" -eq 10
  new_fx; chmod 644 "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: env file mode 644 -> 10" test "$RC" -eq 10
  new_fx; printf 'WORKSPACES_LUKS_DEV=/dev/sdb\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' > "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: device pin that is not a by-id Hetzner path -> 10" test "$RC" -eq 10
  new_fx; printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: the shared prd config is refused -> 10" test "$RC" -eq 10
  new_fx; printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: web-1's original config is still accepted (closed set, member 1) -> 0" test "$RC" -eq 0
  new_fx; printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: the web-host config is accepted (closed set, member 2) -> 0" test "$RC" -eq 0
  new_fx; printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web2\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "config: a prefix-colliding name is refused (closed set, not a prefix match) -> 10" test "$RC" -eq 10
  new_fx; rm -f "$FX/root/etc/default/luks-monitor"; run_sut
  expect "config: token file absent -> 10" test "$RC" -eq 10
  new_fx; printf 'DOPPLER_TOKEN=a\nDOPPLER_TOKEN=b\n' > "$FX/root/etc/default/luks-monitor"; run_sut
  expect "config: two DOPPLER_TOKEN lines -> 10 (ambiguity is refused)" test "$RC" -eq 10
  expect "config: every config refusal made ZERO calls to anything destructive" no_writes
  # cryptsetup absent: a PATH of symlinks to ONLY the tools the script needs, so a host that really
  # has cryptsetup installed cannot satisfy the lookup (the outcome must not depend on the runner).
  new_fx; cp "$FX/bin/cryptsetup" "$FX/st/cryptsetup.saved"; rm -f "$FX/bin/cryptsetup"; mk_core
  RC=0; env -i PATH="$FX/bin:$FX/core" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "$SUT" > "$FX/out" 2> "$FX/err" || RC=$?
  expect "config: cryptsetup absent (and not installable) -> 10, no writes, the install was attempted twice" all 'test "$RC" -eq 10' 'no_writes' 'test "$(count_calls "^apt-get install ")" -eq 2'
  : > "$FX/st/apt.install_on_2"; rm -f "$FX/st/apt.n"; : > "$FX/calls"; rm -rf "$FX/root/detail"
  RC=0; env -i PATH="$FX/bin:$FX/core" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "$SUT" > "$FX/out" 2> "$FX/err" || RC=$?
  expect "config: cryptsetup installable on the 2nd attempt (a transient mirror fault) -> the birth proceeds, rc 0" all 'test "$RC" -eq 0' 'test "$(count_calls "^apt-get install ")" -eq 2' "has '$V_FORMAT'"
  # The test-seam root guard refuses anything that could point the writes at a live tree.
  local r
  for r in /proc/x /sys/x /dev/x rel/x /tmp/../x /; do
    new_fx; RC=0; env -i PATH="$FX/bin:/usr/bin:/bin" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$r" SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "$SUT" > "$FX/out" 2> "$FX/err" < /dev/null || RC=$?
    expect "config: test-seam root '$r' is refused (2) before anything runs" all 'test "$RC" -eq 2' 'test ! -s "$FX/calls"'
  done
}

case_device_wait() {
  begin device_wait || return
  new_fx; printf '9999' > "$FX/st/blockdev.zero_until"; run_sut
  expect "device never appears: FATAL device (11)" test "$RC" -eq 11
  expect "device never appears: waited 299 one-second sleeps" test "$(count_calls '^sleep 1$')" -eq 299
  expect "device never appears: no write calls" no_writes
  new_fx; printf '5' > "$FX/st/blockdev.zero_until"; run_sut
  expect "device appears after 5 polls: succeeds" test "$RC" -eq 0
}

case_wire() {
  begin wire || return
  new_fx; printf 'workspaces /dev/disk/by-label/workspaces_luks none luks,nofail\n' > "$FX/root/etc/crypttab"
  run_sut
  expect "foreign crypttab workspaces line: FATAL wire (16), never coexisted with" all 'test "$RC" -eq 16' 'test "$(grep -c . "$FX/root/etc/crypttab")" -eq 1'
  new_fx; printf '# fstab\n/dev/disk/by-id/scsi-0HC_Volume_%s /mnt/data ext4 defaults,nofail 0 2\n' "$DEVID" > "$FX/root/etc/fstab"
  run_sut
  expect "a foreign /mnt/data fstab line is commented in place, not deleted, and the canonical one is the only live line" all 'test "$RC" -eq 0' 'test "$(grep -vc "^#" "$FX/root/etc/fstab")" -eq 1' "grep -q '^# provision-6931-superseded /dev/disk/by-id/' \"\$FX/root/etc/fstab\""
  new_fx; : > "$FX/st/fail.chattr"; run_sut
  expect "chattr +i fails: FATAL wire (16) and /mnt/data is never mounted" all 'test "$RC" -eq 16' "lack '^mount '"
  new_fx; : > "$FX/st/lsattr.hide"; run_sut
  expect "lsattr does not show the i flag: FATAL wire (16)" all 'test "$RC" -eq 16' "lack '^mount '"
  new_fx; : > "$FX/st/fail.mount"; run_sut
  expect "mount fails: FATAL mount (17)" test "$RC" -eq 17
  new_fx; printf '/dev/sdb1\n' > "$FX/st/mounted.src"; run_sut
  expect "/mnt/data mounted from the wrong source: FATAL mount (17)" test "$RC" -eq 17
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; echo 1 > "$FX/st/map.active"; printf '/dev/disk/by-id/scsi-0HC_Volume_999\n' > "$FX/st/backing"
  run_sut
  expect "the mapper is backed by a different device than the pin: FATAL open (15)" all 'test "$RC" -eq 15' "lack '^mount '"
  # The reopen units are the ONLY thing that unlocks the volume at the next reboot.
  new_fx; : > "$FX/st/fail.enable"; run_sut
  expect "enabling the reopen units fails: FATAL wire (16) with a wire stage emitted" all 'test "$RC" -eq 16' "has '^boot-emit workspaces_luks_provision_wire fatal'"
  new_fx; : > "$FX/st/fail.isenabled"; run_sut
  expect "the reopen units do not read back as enabled: FATAL wire (16)" all 'test "$RC" -eq 16' "has '^boot-emit workspaces_luks_provision_wire fatal'"
  # Non-fatal warns are never local-only: each emits a warning stage with a detail.
  new_fx; : > "$FX/st/fail.monitor"; run_sut
  expect "the probe timer fails to enable: boot continues (rc 0, escrow ok) and a wire_warn WARNING stage is emitted" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=ok' "has '^boot-emit workspaces_luks_provision_wire_warn warning'" 'detail workspaces_luks_provision_wire_warn | grep -q luks_monitor_timer_not_enabled'
  new_fx; mkdir -p "$FX/root/run/soleur/workspaces-luks-arm"; run_sut
  expect "the arm file is unwritable: boot continues (rc 0) and a result WARNING stage is emitted" all 'test "$RC" -eq 0' "has '^boot-emit workspaces_luks_provision_result warning'" 'detail workspaces_luks_provision_result | grep -q arm_file_unwritable'
}

case_escrow() {
  begin escrow || return
  new_fx; : > "$FX/st/fail.put"; run_sut
  expect "escrow PUT fails: boot continues (rc 0)" test "$RC" -eq 0
  expect "escrow PUT fails: escrow=missing is recorded" test "$(arm_line 2)" = escrow=missing
  expect "escrow PUT fails: the stage is emitted with its reason" all "has '^boot-emit workspaces_luks_provision_escrow warning'" 'detail workspaces_luks_provision_escrow | grep -q "reason=put"'
  expect "escrow PUT fails: /mnt/data is nevertheless mounted" test -s "$FX/st/mounted"
  rm -f "$FX/st/fail.put"; : > "$FX/calls"; run_sut
  expect "escrow is NOT retried by the boot path; a manual re-run of the idempotent provisioner uploads and now succeeds" all 'test "$(arm_line 2)" = escrow=ok' "has '^curl .*-T '"
  new_fx; : > "$FX/st/fail.head"; run_sut
  expect "escrow read-back fails: escrow=missing, boot continues" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=missing'
  new_fx; : > "$FX/st/fail.hdrbackup"; run_sut
  expect "luksHeaderBackup fails: escrow=missing, boot continues" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=missing'
  new_fx; : > "$FX/st/doppler.WORKSPACES_HEADER_BUCKET"; run_sut
  expect "escrow credentials unreadable: escrow=missing, boot continues" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=missing'
  # An object of the right SIZE but the wrong CONTENT (a stale header under the same UUID) is not an escrow.
  new_fx; printf '4096\n' > "$FX/st/s3.len"; printf 'deadbeefdeadbeefdeadbeefdeadbeef\n' > "$FX/st/s3.etag"; run_sut
  expect "a same-size object with a stale ETag is re-uploaded, and the stored ETag is then the header's md5" all 'test "$RC" -eq 0' "has '^curl .*-T '" 'test "$(arm_line 2)" = escrow=ok' 'test "$(cat "$FX/st/s3.etag")" = "$(head -c 4096 /dev/zero | md5sum | cut -d" " -f1)"'
  new_fx; printf '4096\n' > "$FX/st/s3.len"; printf 'deadbeefdeadbeefdeadbeefdeadbeef\n' > "$FX/st/s3.etag"; : > "$FX/st/put.noop"; run_sut
  expect "a PUT that stores nothing is caught by the ETag read-back: escrow=missing (readback)" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=missing' 'detail workspaces_luks_provision_escrow | grep -q "reason=readback"'
  local ep
  for ep in 'https://example.invalid' "https://${ACCT}.r2.cloudflarestorage.com.evil.example" "https://${ACCT:1}.r2.cloudflarestorage.com" "https://${ACCT^^}.r2.cloudflarestorage.com" "http://${ACCT}.r2.cloudflarestorage.com"; do
    new_fx; printf '%s\n' "$ep" > "$FX/st/doppler.WORKSPACES_HEADER_R2_ENDPOINT"; run_sut
    expect "escrow: the endpoint '$ep' is not the pinned R2 account shape: escrow=missing (shape), no request is made, boot continues" all 'test "$RC" -eq 0' 'test "$(arm_line 2)" = escrow=missing' 'detail workspaces_luks_provision_escrow | grep -q "reason=shape"' "lack '^curl '"
  done
  new_fx; run_sut
  expect "escrow: the R2 secret reaches curl on stdin config only, never argv" all 'test "$(grep -c -- "$SECVAL" "$FX/calls")" -eq 0' 'test "$(grep -c -- "$SECVAL" "$FX/st/curl.cfg")" -ge 1'
  expect "escrow: SigV4 signing is requested with the R2 form" has "aws-sigv4 aws:amz:auto:s3"
  expect "escrow: the object key carries the header UUID" has "workspaces-luks-header-$(uuid_cur)\\.img"
  expect "escrow: the tmpfs header copy is removed (shred touched only the header temp files)" all '! compgen -G "$FX/root/run/soleur-lukshdr.*" >/dev/null' "lack '^TRAP shred'"
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_xtrace_and_static() {
  begin static || return
  new_fx
  RC=0; env -i PATH="$FX/bin:/usr/bin:/bin" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" bash -x "$SUT" > "$FX/out" 2> "$FX/err" || RC=$?
  expect "xtrace is refused (78) before anything runs" test "$RC" -eq 78
  expect "xtrace refusal made no calls at all" test ! -s "$FX/calls"
  # The comment-stripped provisioner. Every pattern below is spelling-independent where it can be:
  # flag-first cryptsetup, mke2fs, blkdiscard, sgdisk, dd of=, wipefs write flags and every other
  # destructive cryptsetup verb are counted by SHAPE, not by the one spelling the provisioner uses.
  local RMI='rm -f "$INTENT"'
  local code CMDPOS F_FORMAT F_OPEN F_MKFS F_WIPE_DEV F_WIPE_MAP
  code="$(awk '{ s=$0; sub(/^[[:space:]]*#.*/, "", s); print s }' "$SUT")"
  CMDPOS='(^|[|&;({]|then|do)[[:space:]]*'
  F_FORMAT='cryptsetup luksFormat --batch-mode --type luks2 --label "$LABEL_FORMATTING" --uuid "$_nu" --key-file - "$DEV" >/dev/null 2>"$ERRF"'
  F_OPEN='cryptsetup luksOpen --key-file - "$DEV" "$MAPPER_NAME" >/dev/null 2>"$ERRF"'
  F_MKFS='mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF"'
  F_WIPE_DEV='wipefs "$DEV" 2>/dev/null'
  F_WIPE_MAP='wipefs "$MAPPER" 2>/dev/null'
  ccount() { printf '%s\n' "$code" | grep -cE -- "$1" || true; }
  cfix() { printf '%s\n' "$code" | grep -cF -- "$1" || true; }
  cnofatal() { printf '%s\n' "$code" | grep -E -- "$1" | grep -vc 'fatal ' || true; } # call lines: the fatal messages that name a verb are not calls
  expect "static: the core limit is lowered at start, before anything handles the key" test "$(printf '%s\n' "$code" | grep -n -E '^ulimit -c 0( |$)' | head -1 | cut -d: -f1)" -lt "$(printf '%s\n' "$code" | grep -n 'WORKSPACES_LUKS_KEY' | head -1 | cut -d: -f1)"
  expect "static: every intent-file removal is followed by a sync on the same line (three sites)" all 'test "$(cfix "$RMI; sync")" -eq 3' 'test "$(cfix "$RMI")" -eq 3'
  expect "static: no isLuks anywhere in the provisioner code" test "$(ccount 'isLuks')" -eq 0
  expect "static: exactly one luksFormat token, in the pinned spelling (label, stdin key, target \$DEV)" all 'test "$(cnofatal luksFormat)" -eq 1' 'test "$(cfix "$F_FORMAT")" -eq 1'
  expect "static: exactly two luksOpen call sites, both with stdin key and target \$DEV \$MAPPER_NAME" all 'test "$(cnofatal luksOpen)" -eq 2' 'test "$(cfix "$F_OPEN")" -eq 2'
  expect "static: exactly two mkfs/mke2fs commands, both the pinned mkfs.ext4 on \$MAPPER (never the device)" all 'test "$(ccount "${CMDPOS}(mkfs|mke2fs)")" -eq 2' 'test "$(cfix "$F_MKFS")" -eq 2' 'test "$(printf "%s\n" "$code" | grep -E "mkfs\." | grep -vcE "mkfs\.ext4")" -eq 0'
  expect "static: every luksFormat is preceded by a _may_format re-check that is FATAL" test "$(printf '%s\n' "$code" | grep -B14 'cryptsetup luksFormat' | grep -cE '_may_format \|\| fatal format 14 ')" -ge 1
  expect "static: every mkfs is preceded by a FATAL _may_format_fs re-check (an or-colon would keep the token)" all 'test "$(printf "%s\n" "$code" | grep -B3 "mkfs\.ext4 -q" | grep -cE "_may_format_fs \|\| fatal (format 14|open 15) ")" -eq 2' 'test "$(ccount "_may_format_fs \|\| fatal ")" -eq 2'
  expect "static: the relabel is one cryptsetup config, reached from exactly three guarded call sites" all 'test "$(ccount "cryptsetup config ")" -eq 1' 'test "$(ccount "^[[:space:]]*(\[.*\] \|\| )?_ready_label (format|open) (14|15)")" -eq 3'
  expect "static: no wipefs write mode anywhere; only the two read-only calls on \$DEV and \$MAPPER" all 'test "$(ccount "wipefs[[:space:]]+-")" -eq 0' 'test "$(ccount wipefs)" -eq 3' 'test "$(cfix "$F_WIPE_DEV")" -eq 1' 'test "$(cfix "$F_WIPE_MAP")" -eq 1'
  expect "static: every cryptsetup call is verb-first (a flag-first spelling would hide from the counts above)" test "$(ccount 'cryptsetup[[:space:]]+-')" -eq 0
  expect "static: no destructive cryptsetup verb (erase, KillSlot, AddKey, ChangeKey, HeaderRestore, reencrypt, ...)" test "$(ccount 'cryptsetup[[:space:]]+(luks(Erase|KillSlot|AddKey|ChangeKey|RemoveKey|HeaderRestore|Suspend|Resume)|erase|reencrypt|convert|resize|repair|open|close|format)([[:space:]]|$)')" -eq 0
  expect "static: no other formatter, discarder or partitioner (mke2fs, blkdiscard, sgdisk, sfdisk, parted, fstrim, dd of=)" all 'test "$(ccount "mke2fs|blkdiscard|sgdisk|sfdisk|parted|fstrim")" -eq 0' 'test "$(ccount "(^|[^[:alnum:]_./-])dd[[:space:]]+[a-z]+=")" -eq 0' 'test "$(ccount "mkfs[[:space:]]+-t")" -eq 0'
  expect "static: shred appears only in the header-temp-file cleanup" all 'test "$(ccount "${CMDPOS}shred")" -eq 1' 'test "$(printf "%s\n" "$code" | grep -E "${CMDPOS}shred" | grep -vc HDR_DIR)" -eq 0'
  expect "static: the zero-content probe is DEVICE-level only (three windows in _may_format, none on the mapper)" all 'test "$(ccount "_zero_window (0|\\\$\(\(_sz - 16777216\)\)|134217728) ")" -eq 3' 'test "$(ccount "cmp -s")" -eq 1'
  expect "static: this suite carries no expect line with a dead and-or half (a compound is ONE scored command)" test "$(grep -cE '^[[:space:]]*expect .* (&&|\|\|) ' "$SELF")" -eq 0
  expect "static: the provisioner no longer claims a boot-path retry or a next-boot self-heal" test "$(grep -ciE 'retried on every boot|self-heals on the next boot' "$SUT")" -eq 0
}

case_long_path() {
  begin long_path || return
  new_fx
  local big=123456789012
  printf 'WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks_web\n' "$big" > "$FX/root/etc/default/workspaces-luks-boot"
  printf '/dev/disk/by-id/scsi-0HC_Volume_%s\n' "$big" > "$FX/st/backing"
  truncate -s "$DEVSIZE" "$FX/root/dev/disk/by-id/scsi-0HC_Volume_$big"
  run_sut
  expect "must-pass: a raw device with a different serial and a longer by-id path formats normally" all 'test "$RC" -eq 0' "has '$V_FORMAT'"
}

# ── hardening cases (#9378): the lock, the PATH pin, the seam refusal, the atomic writes ──────────
# Helpers for the static census: ncount counts CODE lines (comments stripped) matching an ERE.
ncount() { scode | grep -cE -- "$1" || true; }
run_pin() { # <ROOT>: executes the provisioner's PATH-pin block with that ROOT; prints "PATH|detail-dir|detail-dir as a child sees it"
  { printf 'ROOT=%q\n' "$1"; sblk pin; printf '%s\n' 'printf "%s|%s|%s" "$PATH" "${SOLEUR_STAGE_DETAIL_DIR-unset}" "$("$BASH" -c '"'"'printf %s "${SOLEUR_STAGE_DETAIL_DIR-unset}"'"'"')"'; } > "$FX/pin.sh"
  env -i PATH=/evil/bin:/usr/bin:/bin SOLEUR_STAGE_DETAIL_DIR=/evil/detail "$BASH" "$FX/pin.sh" 2>&1
}
set_marker() { # <state>: file | dir | dangling | absent
  rm -rf "$FX/cloud-marker"
  case "$1" in file) : > "$FX/cloud-marker" ;; dir) mkdir "$FX/cloud-marker" ;; dangling) ln -s "$FX/nowhere" "$FX/cloud-marker" ;; esac
}
# shellcheck disable=SC2034  # SOUT and SRC are read by the eval'd all() strings of the caller
run_seam() { # <uid> <marker-state> <seam 1|0>: executes the provisioner's seam block with the marker constant swapped for a scratch path
  local blk
  set_marker "$2"
  mkdir -p "$FX/idbin"; printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "$1" > "$FX/idbin/id"; chmod 0755 "$FX/idbin/id"
  blk=$(sblk seam); blk=${blk//\/var\/lib\/cloud\/instance/$FX\/cloud-marker}
  { printf '%s\n' "$blk"; printf '%s\n' 'printf "ROOT=[%s]\n" "$ROOT"'; } > "$FX/seam.sh"
  SRC=0; SOUT=$(env -i PATH="$FX/idbin:$FX/bin:/usr/bin:/bin" "FX=$FX" WORKSPACES_PROVISION_TEST_SEAM="$3" WORKSPACES_PROVISION_ROOT="$FX/root" "$BASH" "$FX/seam.sh" 2>&1) || SRC=$?
}
seam_fn_rc() { # <marker-state>: the exit status of the provisioner's _seam_allowed on a scratch marker in that state
  local fn rc=0
  fn=$(sfn _seam_allowed); [ -n "$fn" ] || { printf 'nofn'; return; }
  set_marker "$1"
  "$BASH" -c "$fn"$'\n''_seam_allowed "$1"' _ "$FX/cloud-marker" > /dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_lock() {
  begin lock || return
  local l_cv l_ex l_fl l_sf first
  # The lock is taken before the FIRST side effect: with the boot env file absent nothing else can have run.
  new_fx; rm -f "$FX/root/etc/default/workspaces-luks-boot"; run_sut
  expect "lock: flock -w 600 on fd 9 is the FIRST call and the lock file exists, even when the env file is absent" all 'test "$RC" -eq 10' 'test "$(head -1 "$FX/calls")" = "flock -w 600 9"' 'test -e "$(LOCKF)"'
  new_fx; WLP_LOCK_WAIT='1; touch /pwned' run_sut
  expect "lock: a non-numeric seam timeout falls back to 600 (the knob is validated, never interpolated)" all 'test "$RC" -eq 0' "has '^flock -w 600 9\$'"
  # flock absent: arm config with its own reason, never rc 127 (the required-commands loop runs later).
  new_fx; rm -f "$FX/bin/flock"; mk_core
  RC=0; env -i PATH="$FX/bin:$FX/core" "FX=$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "$SUT" > "$FX/out" 2> "$FX/err" < /dev/null || RC=$?
  expect "lock: flock absent -> arm config (10) saying so (never 127), and no write call" all 'test "$RC" -eq 10' 'grep -q "flock is absent" "$FX/root/detail/workspaces_luks_provision_config"' 'no_writes'
  new_fx; mkdir -p "$(LOCKF)"; run_sut
  expect "lock: a lock path that cannot be opened -> arm config (10) with its own reason, and no write call" all 'test "$RC" -eq 10' 'grep -q "cannot open the lock file" "$FX/root/detail/workspaces_luks_provision_config"' 'no_writes'
  # A REAL holder (not a stub): exclusion, the lock_timeout reason, an untouched tree, and the holder's scratch file intact.
  new_fx; mkdir -p "$FX/root/run/soleur"; printf 'holder-scratch\n' > "$FX/root/run/soleur/workspaces-luks-cmd.err"
  if hold_lock; then
    WLP_RUN_TIMEOUT=10 WLP_LOCK_WAIT=1 run_sut
    expect "lock: a REAL holder blocks a second run: rc 10, reason lock_timeout, the seam timeout of 1 s was used" all 'test "$RC" -eq 10' 'grep -q "lock_timeout" "$FX/root/detail/workspaces_luks_provision_config"' "has '^flock -w 1 9\$'"
    expect "lock: the blocked run touched nothing: no write call, fstab/crypttab/drop-in untouched, no key fetch, the holder's scratch file kept" all 'no_writes' 'files_untouched' "lack '^doppler '" 'test -e "$FX/root/run/soleur/workspaces-luks-cmd.err"'
    kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; wait_unlocked
    run_sut
    expect "lock: once the holder is gone the same fixture provisions normally (the lock is not wedged)" test "$RC" -eq 0
  else
    no "lock: the instrument could not take the real lock (broken instrument)"
  fi
  # A child that outlives the script keeps fd 9, so the lock stays held: the 'no child daemonizes' comment in the
  # provisioner is load-bearing, and this row is what makes it so.
  new_fx
  cat > "$FX/bin/systemctl" <<STUB
#!/bin/bash
printf '%s\n' "systemctl \$*" >> "\$FX/calls"
case "\$*" in "start --no-block"*) $SLEEP_REAL 25 > /dev/null 2>&1 & echo \$! > "\$FX/st/child.pid" ;; esac
exit 0
STUB
  chmod 0755 "$FX/bin/systemctl"
  run_sut; first=$RC
  WLP_RUN_TIMEOUT=10 WLP_LOCK_WAIT=1 run_sut
  expect "lock: a child that outlives the script keeps fd 9: the next run times out on lock_timeout" all "test $first -eq 0" 'test "$RC" -eq 10' 'grep -q "lock_timeout" "$FX/root/detail/workspaces_luks_provision_config"'
  kill "$(cat "$FX/st/child.pid")" 2>/dev/null; wait_unlocked
  run_sut
  expect "lock: after the child exits the lock is free again and the run succeeds" test "$RC" -eq 0
  kill "$(cat "$FX/st/child.pid")" 2>/dev/null
  # Static census: one flock call site, ordered before every side effect, and the timeout knob exists only under the seam.
  l_cv=$(sline 'command -v flock'); l_ex=$(sline '^exec 9>'); l_fl=$(sline '^flock -w'); l_sf=$(sline '^_secure_file "\$ENVFILE"')
  expect "lock: static: command -v flock, then the fd-9 open, then the single flock -w, all before the first _secure_file" all 'test -n "$l_cv" -a -n "$l_ex" -a -n "$l_fl" -a -n "$l_sf"' '[ "$l_cv" -lt "$l_ex" ]' '[ "$l_ex" -lt "$l_fl" ]' '[ "$l_fl" -lt "$l_sf" ]' 'test "$(ncount "(^|[^[:alnum:]_])flock[[:space:]]+-w")" -eq 1'
  expect "lock: static: the lock-timeout knob is read only under the seam (every line naming it also names ROOT) and is named at least once" all 'test "$(ncount WORKSPACES_PROVISION_LOCK_WAIT)" -ge 1' 'test "$(scode | grep WORKSPACES_PROVISION_LOCK_WAIT | grep -vc ROOT)" -eq 0'
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_pathpin() {
  begin pathpin || return
  local pinval='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' l_p l_cv l_ex l_fl l_sf l_mk
  new_fx
  expect "pin: production (ROOT empty): PATH is the pinned system path and the stage-detail dir is clamped to its default, exported to children" test "$(run_pin '')" = "$pinval|/run/soleur-stage-detail.d|/run/soleur-stage-detail.d"
  expect "pin: under the seam (ROOT set) the scratch PATH and the detail-dir knob are left alone (the stubs must intercept)" test "$(run_pin /scratch/root)" = "/evil/bin:/usr/bin:/bin|/evil/detail|/evil/detail"
  l_p=$(sline '^[[:space:]]*PATH='); l_cv=$(sline 'command -v flock'); l_ex=$(sline '^exec 9>'); l_fl=$(sline '^flock -w'); l_sf=$(sline '^_secure_file "\$ENVFILE"'); l_mk=$(sline '^mkdir -p ')
  expect "pin: static: exactly one PATH= assignment, and it precedes the lock probe, the lock, the first mkdir and the first _secure_file" all 'test "$(ncount "^[[:space:]]*PATH=")" -eq 1' 'test -n "$l_p" -a -n "$l_cv" -a -n "$l_mk"' '[ "$l_p" -lt "$l_cv" ]' '[ "$l_p" -lt "$l_ex" ]' '[ "$l_p" -lt "$l_fl" ]' '[ "$l_p" -lt "$l_sf" ]' '[ "$l_p" -lt "$l_mk" ]'
  expect "pin: static: the assignment is the pinned value" test "$(scode | grep -cxF "  PATH=$pinval")" -eq 1
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_seam() {
  begin seam || return
  new_fx
  run_seam 0 file 1
  expect "seam: euid 0 + a cloud-init marker (a real host) refuses the seam: exit 2, announced on stderr and under the journald tag, ROOT never set" all 'test "$SRC" -eq 2' '! grep -qF "ROOT=[" <<< "$SOUT"' 'grep -qi "cloud-init" <<< "$SOUT"' "has '^logger -t workspaces-luks-reopen -- .*seam'"
  run_seam 0 dangling 1
  expect "seam: the marker is tested as a path OR a symlink: a dangling symlink still refuses" test "$SRC" -eq 2
  run_seam 0 dir 1
  expect "seam: a marker that is a directory (the real shape of the cloud-init instance dir) refuses" test "$SRC" -eq 2
  run_seam 0 absent 1
  expect "seam: euid 0 on a host WITHOUT the marker proceeds and keeps the scratch root" all 'test "$SRC" -eq 0' 'grep -qF "ROOT=[$FX/root]" <<< "$SOUT"'
  run_seam 1000 file 1
  expect "seam: a non-root runner that happens to carry cloud-init state keeps the suite green (the carve-out)" all 'test "$SRC" -eq 0' 'grep -qF "ROOT=[$FX/root]" <<< "$SOUT"'
  run_seam 0 file 0
  expect "seam: production (no seam) never reads the marker: ROOT stays empty and nothing is refused" all 'test "$SRC" -eq 0' 'grep -qF "ROOT=[]" <<< "$SOUT"'
  expect "seam: _seam_allowed itself refuses a file, a directory and a dangling symlink, and allows an absent path" all 'test "$(seam_fn_rc file)" -eq 1' 'test "$(seam_fn_rc dir)" -eq 1' 'test "$(seam_fn_rc dangling)" -eq 1' 'test "$(seam_fn_rc absent)" -eq 0'
  expect "seam: static: one _seam_allowed call, whose argument is the literal constant (never a variable), and the marker literal appears once" all 'test "$(ncount "(^|[^[:alnum:]_])_seam_allowed /var/lib/cloud/instance([[:space:];)]|$)")" -eq 1' 'test "$(ncount _seam_allowed)" -eq 2' 'test "$(ncount /var/lib/cloud/instance)" -eq 1'
  expect "seam: static: the only WORKSPACES_PROVISION_* variables are the test seam, its root and the seam-only lock timeout" test "$(scode | grep -oE 'WORKSPACES_PROVISION_[A-Z_]+' | sort -u | tr '\n' ' ')" = "WORKSPACES_PROVISION_LOCK_WAIT WORKSPACES_PROVISION_ROOT WORKSPACES_PROVISION_TEST_SEAM "
}

# shellcheck disable=SC2034  # the locals are read by the eval'd all() strings
case_install() {
  begin install || return
  local t want v pat
  # (1) a symlinked destination is refused for each of the four targets, and the link target is never written.
  for t in crypttab fstab dropin intent; do
    if [ "$t" = intent ]; then new_fx; else open_fx; fi
    v="$FX/victim"; printf 'VICTIM-ORIGINAL\n' > "$v"; want=16
    case "$t" in
      crypttab) rm -f "$FX/root/etc/crypttab"; ln -s "$v" "$FX/root/etc/crypttab" ;;
      fstab) rm -f "$FX/root/etc/fstab"; ln -s "$v" "$FX/root/etc/fstab" ;;
      dropin) mkdir -p "$FX/root/etc/systemd/system/docker.service.d"; ln -s "$v" "$FX/root/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf" ;;
      intent) mkdir -p "$FX/root/var/lib/soleur"; ln -s "$v" "$FX/root/$INTENT_F"; want=14 ;;
    esac
    run_sut
    expect "install: a symlinked $t destination is refused ($want), the link target is untouched, no luksFormat, no mount" all "test \"\$RC\" -eq $want" 'test "$(cat "$v")" = VICTIM-ORIGINAL' "lack '^mount |$V_FORMAT'"
  done
  # (2) a planted temp symlink is removed before writing, never followed.
  new_fx; mkdir -p "$FX/root/etc/systemd/system/docker.service.d" "$FX/root/var/lib/soleur"
  for t in fstab crypttab dropin intent; do printf 'VICTIM-%s\n' "$t" > "$FX/victim.$t"; done
  ln -s "$FX/victim.fstab" "$FX/root/etc/fstab.provision.tmp"; ln -s "$FX/victim.crypttab" "$FX/root/etc/crypttab.provision.tmp"
  ln -s "$FX/victim.dropin" "$FX/root/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf.provision.tmp"; ln -s "$FX/victim.intent" "$FX/root/$INTENT_F.provision.tmp"
  run_sut
  expect "install: planted temp symlinks (all four targets) are removed, never followed: rc 0, every victim untouched, no temp left" all 'test "$RC" -eq 0' 'victims_intact' 'no_tmp_left'
  # (3) a failing fsync is FATAL, before the rename (temp) or after it (directory); nothing half-written is left.
  for pat in "/etc/crypttab:16" "/etc/fstab:16" "10-workspaces-luks-mount.conf:16" "workspaces-luks-formatting:14"; do
    if [ "${pat%%:*}" = workspaces-luks-formatting ]; then new_fx; else open_fx; fi
    printf 'tmp %s' "${pat%%:*}" > "$FX/st/fail.sync"; run_sut
    expect "install: a failing fsync of the ${pat%%:*} temp file is FATAL (${pat##*:}), nothing is left behind, and a failed intent fsync never reaches luksFormat" all "test \"\$RC\" -eq ${pat##*:}" 'no_tmp_left' "lack '$V_FORMAT'"
  done
  for pat in "var/lib/soleur:14" "docker.service.d:16"; do
    if [ "${pat%%:*}" = var/lib/soleur ]; then new_fx; else open_fx; fi
    printf 'dir %s' "${pat%%:*}" > "$FX/st/fail.sync"; run_sut
    expect "install: a failing fsync of the ${pat%%:*} directory after the rename is FATAL (${pat##*:}), never swallowed" all "test \"\$RC\" -eq ${pat##*:}" 'no_tmp_left' "lack '$V_FORMAT'"
  done
  # (4) a producer that dies mid-stream: the truncated output is never renamed over fstab.
  open_fx; printf '# fstab\nUUID=abc / ext4 defaults 0 1\n' > "$FX/root/etc/fstab"; cp "$FX/root/etc/fstab" "$FX/fstab.before"
  cat > "$FX/bin/awk" <<STUB
#!/bin/bash
case "\$*" in *canon=*) printf 'PARTIAL-TRUNCATED'; exit 1 ;; esac
exec $(command -v awk) "\$@"
STUB
  chmod 0755 "$FX/bin/awk"; run_sut
  expect "install: a producer that dies mid-stream: FATAL wire (16), fstab byte-identical, no temp left, no mount" all 'test "$RC" -eq 16' 'cmp -s "$FX/root/etc/fstab" "$FX/fstab.before"' 'no_tmp_left' "lack '^mount '"
  # (5) files without a trailing newline: the canonical line never glues onto the last line.
  open_fx; printf 'other /dev/disk/by-id/zzz none luks' > "$FX/root/etc/crypttab"; printf 'UUID=abc / ext4 defaults 0 1' > "$FX/root/etc/fstab"; run_sut
  expect "install: a crypttab and an fstab with no trailing newline: each existing line survives whole and the new line is on its OWN line" all 'test "$RC" -eq 0' 'test "$(cat "$FX/root/etc/crypttab")" = "$(printf "other /dev/disk/by-id/zzz none luks\nworkspaces %s none luks,noauto" "$DEVPIN")"' 'test -z "$(tail -c1 "$FX/root/etc/crypttab")"' 'grep -qxF "UUID=abc / ext4 defaults 0 1" "$FX/root/etc/fstab"' 'test "$(grep -c . "$FX/root/etc/fstab")" -eq 2'
  # (6) must-pass: a crypttab that already holds the canonical line plus an unrelated one is preserved byte for byte and mode.
  open_fx; printf 'other /dev/disk/by-id/zzz none luks\nworkspaces %s none luks,noauto\n' "$DEVPIN" > "$FX/root/etc/crypttab"; chmod 644 "$FX/root/etc/crypttab"; cp "$FX/root/etc/crypttab" "$FX/ct.before"; run_sut
  expect "install: must-pass: a crypttab with the canonical line plus an unrelated mount line, mode 0644, is preserved byte for byte and mode" all 'test "$RC" -eq 0' 'cmp -s "$FX/root/etc/crypttab" "$FX/ct.before"' 'mode_is "$FX/root/etc/crypttab" 644'
  # (6b) an UNREADABLE crypttab (cat fails: here a directory stands in for an I/O error) is fatal at the READ, never an empty file:
  #      `_ct=$(cat f; printf x) || fatal` tested printf's status, so a failed cat read as "no entries" and the rewrite dropped every other line.
  open_fx; rm -f "$FX/root/etc/crypttab"; mkdir "$FX/root/etc/crypttab"; run_sut
  expect "install: an unreadable crypttab is FATAL wire (16) at the read ('cannot read crypttab'), fstab untouched, no mount" all 'test "$RC" -eq 16' 'grep -q "cannot read crypttab" "$FX/root/detail/workspaces_luks_provision_wire" "$FX/root/detail/"* 2>/dev/null' 'test "$(cat "$FX/root/etc/fstab")" = "# fstab"' "lack '^mount '"
  # (7) modes: an existing file keeps its mode; a file this script creates is 0600 (crypttab) as before.
  open_fx; chmod 640 "$FX/root/etc/fstab"; rm -f "$FX/root/etc/crypttab"; run_sut
  expect "install: an existing fstab keeps its mode (640), and a crypttab created by the script is 0600" all 'test "$RC" -eq 0' 'mode_is "$FX/root/etc/fstab" 640' 'mode_is "$FX/root/etc/crypttab" 600'
  # (8) the fsync spelling on a clean birth: each temp file is fsynced, and each directory after its rename.
  new_fx; run_sut
  expect "install: every target's temp file is fsynced (same-directory *.provision.tmp)" all "has '^sync .*/root/etc/crypttab\.provision\.tmp\$'" "has '^sync .*/root/etc/fstab\.provision\.tmp\$'" "has '^sync .*/docker\.service\.d/10-workspaces-luks-mount\.conf\.provision\.tmp\$'" "has '^sync .*/var/lib/soleur/workspaces-luks-formatting\.provision\.tmp\$'"
  expect "install: each directory is fsynced after its rename (etc twice, the drop-in dir, the state dir) and a temp sync precedes its directory sync" all 'test "$(count_calls "^sync .*/root/etc\$")" -eq 2' "has '^sync .*/docker\.service\.d\$'" "has '^sync .*/var/lib/soleur\$'" 'test "$(lineno "^sync .*/docker\.service\.d/10-workspaces-luks-mount\.conf\.provision\.tmp\$")" -lt "$(lineno "^sync .*/docker\.service\.d\$")"'
  # (9) static census: no writer to the four targets other than _install_file, and each of the four goes through it once.
  expect "install: static: no direct write, move, copy or chmod names fstab, crypttab, the drop-in or the intent file (a trailing >> after a compliant writer included)" test "$(ncount '(>>?|[[:space:]]tee[[:space:]]|[[:space:]]mv[[:space:]]|[[:space:]]cp[[:space:]]|[[:space:]]install[[:space:]]|sed[[:space:]]+-i|truncate|[[:space:]]ln[[:space:]]|[[:space:]]chmod[[:space:]]|[[:space:]]chown[[:space:]])[^|;]*"\$\{?(FSTAB|CRYPTTAB|DROPIN|INTENT)([^A-Za-z0-9_]|$)')" -eq 0
  expect "install: static: fstab, crypttab, the drop-in and the intent file each have exactly one _install_file call site" all 'test "$(ncount "_install_file \"\\\$FSTAB\" [0-9]+")" -eq 1' 'test "$(ncount "_install_file \"\\\$CRYPTTAB\" [0-9]+")" -eq 1' 'test "$(ncount "_install_file \"\\\$DROPIN\" [0-9]+")" -eq 1' 'test "$(ncount "_install_file \"\\\$INTENT\" [0-9]+")" -eq 1'
}

run_cases() {
  case_raw_order; case_raw_wiring; case_raw_secret_hygiene; case_raw_idempotent
  case_luks_opens; case_ext4_refused; case_blkid_rc; case_signatures_refused
  case_zero_probe; case_blank_mapper; case_crash_recovery; case_state_change; case_failures; case_key
  case_config; case_device_wait; case_wire; case_escrow; case_xtrace_and_static; case_long_path
  case_lock; case_pathpin; case_seam; case_install
}
EXPECTED_CASES=24
if [ -n "$ONLY" ]; then
  # A requested name that is not a case is a broken ROW (exit 2: never counted as a catch), not a red suite.
  ALL_CASES="raw_order raw_wiring raw_secret_hygiene raw_idempotent luks_open ext4 blkid_rc signatures zero_probe blank_mapper crash state_change failures key config device_wait wire escrow static long_path lock pathpin seam install"
  _seen=" "
  for _c in $ONLY; do
    case " $ALL_CASES " in
      *" $_c "*) : ;;
      *) printf '[FATAL] WLP_ONLY_CASES names an unknown case: %s\n' "$_c" >&2; exit 2 ;;
    esac
    case "$_seen" in
      *" $_c "*) printf '[FATAL] WLP_ONLY_CASES names a case twice: %s\n' "$_c" >&2; exit 2 ;;
    esac
    _seen="$_seen$_c "
  done
  [ "$_seen" != " " ] || { printf '[FATAL] WLP_ONLY_CASES is set but names no case\n' >&2; exit 2; }
fi
run_cases

# The suite asserts its own case set and that the stubs recorded anything at all: a deleted case or a
# stub that logs nothing must RED the suite, never pass vacuously.
if [ -n "$ONLY" ]; then
  # shellcheck disable=SC2086  # word-split on purpose: ONLY is a space-separated case list
  set -- $ONLY; EXPECTED_CASES=$#
fi
[ "${#CASES_RUN[@]}" -eq "$EXPECTED_CASES" ] || { printf 'FAIL - %s cases ran, expected %s (a case was deleted)\n' "${#CASES_RUN[@]}" "$EXPECTED_CASES"; exit 1; }
if [ -n "${WLP_STUB_NOLOG:-}" ]; then
  printf 'FAIL - the stubs recorded 0 calls; every call assertion above is vacuous\n'; exit 1
fi

# ── mutation rows (outer run only) ────────────────────────────────────────────────────────────
if [ -z "$WLP_MUTANT" ]; then
  mut_rows=0
  MUT="$SCRATCH/mut"; mkdir -p "$MUT"; assert_fixture_dir "$MUT"
  # Bounded: the infra runner already runs suites -P4, and 6 mutants on top of that starved sibling suites
  # into their per-suite bounds on a 4-vCPU CI leg (run 36917791726). Overridable for a fast local run.
  MAXJ="${WLP_MUT_JOBS:-3}"
  declare -a MUT_NAME MUT_WANT MUT_LAND MUT_COV
  # cov "<cases>" names the cases a mutant run executes (the cases holding the row's target assertions);
  # it applies to the NEXT row only. A row with no cov line runs the FULL inner suite.
  NEXT_COV=""
  cov() { NEXT_COV="$*"; }
  throttle() { while [ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]; do wait -n; done; }
  # <name> <expect: caught|survive> <python expression over s producing the mutated source, or
  # statements assigning `new`>. The mutant runs in the background (up to $MAXJ at a time) and is
  # scored by score_rows in row order.
  mutate() {
    local name="$1" want="$2" expr="$3" n=$((mut_rows + 1)) m
    m="$MUT/m$n.sh"
    mut_rows=$n; MUT_NAME[n]="$name"; MUT_WANT[n]="$want"; MUT_LAND[n]=""; MUT_COV[n]="$NEXT_COV"; NEXT_COV=""
    cp "$PRISTINE" "$m"
    WLP_M="$m" WLP_EXPR="$expr" python3 - <<'PY' || { MUT_LAND[n]=python; return; }
import os
p = os.environ["WLP_M"]
s = open(p).read()
ns = {"s": s}
src = os.environ["WLP_EXPR"]
try:
    new = eval(src, {}, ns)
except SyntaxError:
    exec(src, {}, ns)
    new = ns["new"]
assert new != s, "mutation produced identical source"
open(p, "w").write(new)
PY
    cmp -s "$PRISTINE" "$m" && { MUT_LAND[n]=identical; return; }
    bash -n "$m" 2>/dev/null || { MUT_LAND[n]=syntax; return; }  # a mutant that does not parse is a broken instrument, not a catch
    throttle
    ( rc=0; WLP_MUTANT=1 WLP_ONLY_CASES="${MUT_COV[n]}" WLP_SCRIPT="$m" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  # <name> <caught|survive> <old text> <new text>: replace the first occurrence of a literal (it must exist).
  msub() {
    local name="$1" want="$2" n=$((mut_rows + 1)) m
    m="$MUT/m$n.sh"
    mut_rows=$n; MUT_NAME[n]="$name"; MUT_WANT[n]="$want"; MUT_LAND[n]=""; MUT_COV[n]="$NEXT_COV"; NEXT_COV=""
    cp "$PRISTINE" "$m"
    WLP_M="$m" WLP_OLD="$3" WLP_NEW="$4" python3 - <<'PY' || { MUT_LAND[n]=python; return; }
import os
p = os.environ["WLP_M"]
s = open(p).read()
old, new = os.environ["WLP_OLD"], os.environ["WLP_NEW"]
assert old in s, "mutation anchor not found"
open(p, "w").write(s.replace(old, new, 1))
PY
    cmp -s "$PRISTINE" "$m" && { MUT_LAND[n]=identical; return; }
    bash -n "$m" 2>/dev/null || { MUT_LAND[n]=syntax; return; }  # a mutant that does not parse is a broken instrument, not a catch
    throttle
    ( rc=0; WLP_MUTANT=1 WLP_ONLY_CASES="${MUT_COV[n]}" WLP_SCRIPT="$m" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  envrow() { # <name> <want-rc> <ENV=val>
    local n=$((mut_rows + 1))
    mut_rows=$n; MUT_NAME[n]="harness row: $1"; MUT_WANT[n]="env:$2"; MUT_LAND[n]=""; MUT_COV[n]="$NEXT_COV"; NEXT_COV=""
    throttle
    ( rc=0; env WLP_MUTANT=1 WLP_ONLY_CASES="${MUT_COV[n]}" "$3" bash "$SELF" > "$MUT/out.$n" 2>&1 || rc=$?; echo "$rc" > "$MUT/rc.$n" ) &
  }
  score_rows() {
    local n rc want
    wait
    for ((n = 1; n <= mut_rows; n++)); do
      want="${MUT_WANT[n]}"
      case "${MUT_LAND[n]}" in
        python) no "mutation did NOT land (python): ${MUT_NAME[n]}"; continue ;;
        identical) no "mutation did NOT land (identical bytes): ${MUT_NAME[n]}"; continue ;;
        syntax) no "mutation does not parse (bash -n): ${MUT_NAME[n]}"; continue ;;
      esac
      rc=$(cat "$MUT/rc.$n" 2>/dev/null || echo missing)
      case "$want" in
        env:*) [ "$rc" != 0 ] && [ "$rc" = "${want#env:}" ] && ok 0 "${MUT_NAME[n]}" || ok 1 "${MUT_NAME[n]}" "rc=$rc" ;;
        *)
          case "$rc" in
            1) [ "$want" = caught ] && ok 0 "mutation caught: ${MUT_NAME[n]}" || ok 1 "mutation caught but expected to survive: ${MUT_NAME[n]}" ;;
            0) [ "$want" = survive ] && ok 0 "harmless variant stays green: ${MUT_NAME[n]}" || ok 1 "mutation SURVIVED: ${MUT_NAME[n]}" ;;
            *) no "broken instrument (rc=$rc): ${MUT_NAME[n]}" ;;
          esac ;;
      esac
    done
  }

  cov "raw_secret_hygiene ext4"
  mutate "1 blkid probe replaced by cryptsetup isLuks (inverted guard)" caught \
    "s.replace('TYPE=\$(blkid -o value -s TYPE \"\$DEV\" 2>/dev/null) || _rc=\$?', 'cryptsetup isLuks \"\$DEV\" >/dev/null 2>&1 && TYPE=crypto_LUKS || { TYPE=\"\"; _rc=2; }', 1)"
  cov "ext4"
  mutate "2 ext4 treated as formattable" caught \
    "s.replace('  crypto_LUKS) MODE=open ;;', '  crypto_LUKS) MODE=open ;;\n  ext4) MODE=format ;;', 1)"
  cov "blkid_rc state_change"
  mutate "3 blkid rc 4/8 folded into empty (every layer that reads the rc)" caught \
    "s.replace('case \"\$_rc\" in 0|2) : ;; *) fatal', 'case \"\$_rc\" in *) : ;; esac; case x in y) fatal', 1).replace('[ \"\$_rc\" = 2 ] || fatal discriminate 12 \"blkid rc 0 with no TYPE is ambiguous\"', ':', 1).replace('  [ \"\$rc\" = 2 ] && [ -z \"\$t\" ] || return 1\n  rc=0; pt=', '  rc=0; pt=', 1)"
  cov "signatures"
  mutate "4 PTTYPE and wipefs corroboration dropped" caught \
    "s.replace('  [ \"\$rc\" = 2 ] && [ -z \"\$pt\" ] || return 1\n', '', 1).replace('  [ \"\$rc\" = 0 ] && [ -z \"\$wf\" ] || return 1\n  [ \"\$(lsblk', '  [ \"\$(lsblk', 1)"
  cov "luks_open static"
  mutate "5 luksFormat called directly from the open arm" caught \
    "s.replace('    4)\n      _get_key\n', '    4)\n      _get_key\n      printf \"%s\" \"\$KEY\" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - \"\$DEV\" >/dev/null 2>&1\n', 1)"
  cov "signatures state_change static"
  mutate "6 _may_format not re-run before luksFormat (discriminate-time only)" caught \
    "s.replace('  _may_format || fatal format 14 \"device state changed after discriminate; refusing luksFormat\"\n', '', 1)"
  cov "blank_mapper"
  msub "7 intent/label authorisation removed from the open arm (any LUKS + blank mapper is mkfs'd)" caught \
    '    [ "$_bound" = 1 ] || [ "$_lbl" = "$LABEL_FORMATTING" ] \' \
    '    : \'
  cov "crash raw_order"
  msub "8 intent file never written (the same-host crash window loses its evidence)" caught \
    '| _install_file "$INTENT" 600 || fatal format 14 "cannot install the format intent file${_IF_WHY:+: $_IF_WHY}"' \
    '> /dev/null'
  cov "ext4 lock"
  envrow "9a the stubs record nothing (0 calls checked)" 1 "WLP_STUB_NOLOG=1"
  cov "ext4"
  envrow "9b a case is deleted from the suite" 1 "WLP_DROP_CASE=ext4"
  cov "wire raw_wiring"
  msub "11 chattr +i removed (a plaintext root-disk write becomes possible)" caught \
    '  chattr +i "$MNT_DIR" || fatal wire 16 "chattr +i on the covered mountpoint failed"' \
    '  :'
  cov "wire"
  msub "12 a foreign crypttab line is accepted" caught \
    '    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"' \
    '    || :'
  cov "failures static"
  msub "13 the mapper-level re-check dropped before the first mkfs" caught \
    '  _may_format_fs || fatal format 14 "the new mapper is not blank; refusing mkfs"' \
    '  :'
  cov "raw_wiring wire"
  msub "14 the reopen units are no longer enabled" caught \
    'systemctl enable workspaces-luks-reopen.service workspaces-luks-reopen.timer >/dev/null 2>&1 \' \
    'true \'
  mutate "10 harmless: a comment-only edit must stay green" survive \
    "s.replace('# THE ONE RULE.', '# THE ONE RULE (reworded).', 1)"

  # ── volume-carried recovery marker ──
  cov "raw_order crash"
  msub "15 luksFormat no longer writes the formatting label (a replacement host cannot recover)" caught \
    '--label "$LABEL_FORMATTING" --uuid' \
    '--uuid'
  cov "blank_mapper crash"
  msub "16 the label leg is the ONLY check removed from the recovery gate (intent-only)" caught \
    '[ "$_bound" = 1 ] || [ "$_lbl" = "$LABEL_FORMATTING" ] \' \
    '[ "$_bound" = 1 ] \'
  cov "blank_mapper"
  msub "17 ANY label authorises the blank-mapper mkfs (the final label too)" caught \
    '[ "$_lbl" = "$LABEL_FORMATTING" ] \' \
    '[ -n "$_lbl" ] \'
  cov "raw_order failures"
  msub "18 the relabel after mkfs is skipped in the format arm" caught \
    '  _ready_label format 14' \
    '  :'
  cov "failures"
  msub "19 a failed relabel is ignored (no fatal)" caught \
    '|| fatal "$1" "$2" "relabel to the final volume label failed after mkfs$(_cause)"' \
    '|| true'
  cov "luks_open crash"
  msub "20 the formatting-label heal on an ext4 mapper is skipped" caught \
    '!= "$LABEL_FORMATTING" ] || _ready_label open 15' \
    '!= "$LABEL_FORMATTING" ] || :'
  cov "blank_mapper crash"
  msub "21 the relabel after the recovery mkfs is skipped (open arm)" caught \
    '    _ready_label open 15
    rm -f "$INTENT"; sync
    ARM=formatted' \
    '    :
    rm -f "$INTENT"; sync
    ARM=formatted'

  # ── zero-content probe ──
  cov "zero_probe"
  msub "22 the zero-content probe is dropped entirely" caught \
    '  _zero_window 0 16777216 || return 1
  _zero_window $((_sz - 16777216)) 16777216 || return 1
  _zero_window 134217728 1048576 || return 1' \
    '  :'
  cov "zero_probe"
  msub "23 the tail window is dropped" caught \
    '  _zero_window $((_sz - 16777216)) 16777216 || return 1' ''
  cov "zero_probe"
  msub "24 the 128 MiB backup-superblock window is dropped" caught \
    '  _zero_window 134217728 1048576 || return 1' ''
  cov "zero_probe"
  msub "25 the head window shrinks from 16 MiB to 1 MiB" caught \
    '_zero_window 0 16777216' '_zero_window 0 1048576'
  cov "zero_probe"
  msub "26 no clamp: a device smaller than a window is read past its end" caught \
    '  [ $((off + len)) -le "$_sz" ] || len=$((_sz - off))' ''
  cov "zero_probe"
  msub "27 a cmp error reads as zero (fail-open on an unreadable device)" caught \
    '  cmp -s -n "$len" -i "$off:0" "$DEVNODE" /dev/zero' \
    '  cmp -s -n "$len" -i "$off:0" "$DEVNODE" /dev/zero; return 0'

  # ── wire: modes, fatal enable, warnings ──
  cov "raw_wiring install"
  msub "28 an existing file's mode is not carried over to its replacement (the temp keeps umask 077: fstab 0600)" caught \
    '{ chmod --reference="$dest" "$tmp" && chown --reference="$dest" "$tmp"; } || {' \
    'true || {'
  cov "raw_wiring"
  msub "29 the drop-in directory and covered mountpoint are created under umask 077 (0700)" caught \
    '( umask 022; mkdir -p "$DROPIN_DIR" )' 'mkdir -p "$DROPIN_DIR"'
  cov "wire"
  msub "30 the reopen-unit enable failure is a warning again" caught \
    '  || fatal wire 16 "the reopen service and timer could not be enabled; the next boot would leave docker without its volume"' \
    '  || warn wire reopen_units_not_enabled'
  cov "raw_wiring wire"
  msub "31 the reopen units are never verified enabled" caught \
    '  && systemctl is-enabled workspaces-luks-reopen.service workspaces-luks-reopen.timer >/dev/null 2>&1 \' \
    '  \'
  cov "wire"
  msub "32 the warning stage is not emitted (local-only again)" caught \
    '  soleur-boot-emit "workspaces_luks_provision_$1" warning 2>/dev/null || true' ''

  # ── mapper/device chokepoints driven dynamically ──
  cov "failures static"
  msub "33 the mapper-level re-check is non-fatal (|| : keeps the token)" caught \
    '_may_format_fs || fatal format 14 "the new mapper is not blank; refusing mkfs"' \
    '_may_format_fs || :'
  cov "blank_mapper failures"
  msub "34 the mapper-level findmnt check is removed" caught \
    '  [ -z "$(findmnt -rn -S "$MAPPER" 2>/dev/null || true)" ] || return 1
' ''
  cov "signatures"
  msub "35 the device-level findmnt check inside _may_format is removed" caught \
    '  [ -z "$(findmnt -rn -S "$DEV" 2>/dev/null || true)" ] || return 1
  [[ "$_sz"' \
    '  [[ "$_sz"'

  # ── ordering / non-fatal-after-failure mutants ──
  cov "raw_wiring wire"
  mutate "36 the covered inode is made immutable only AFTER the mount" caught \
    'a = s.index("if ! mountpoint -q")
b = s.index("( umask 022; mkdir -p ", a)
blk = s[a:b]
m = s.index("is not mounted from", b)
e = s.index("\n", m) + 1
new = s[:a] + s[b:e] + blk + s[e:]'
  cov "failures raw_order"
  mutate "37 mkfs is issued BEFORE luksOpen (format arm)" caught \
    'a = s.rfind("\n", 0, s.index("| cryptsetup luksOpen")) + 1
b = s.rfind("\n", 0, s.index("_may_format_fs || fatal format 14")) + 1
c = s.index("\n", s.index("mkfs.ext4 -q", b)) + 1
new = s[:a] + s[b:c] + s[a:b] + s[c:]'
  cov "wire"
  msub "38 chattr +i fails, the provisioner mounts anyway, then dies" caught \
    '  chattr +i "$MNT_DIR" || fatal wire 16 "chattr +i on the covered mountpoint failed"' \
    '  chattr +i "$MNT_DIR" || { mount "$MNT" >/dev/null 2>&1; fatal wire 16 "chattr +i on the covered mountpoint failed"; }'
  cov "wire"
  msub "39 a foreign crypttab line triggers the canonical append, then the fatal" caught \
    '    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"' \
    '    || { printf "%s\n" "$CRYPTTAB_LINE" >> "$CRYPTTAB"; fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"; }'
  cov "raw_secret_hygiene"
  msub "40 the Doppler token is put in a logger argv" caught \
    'logger -t workspaces-luks-reopen -- "$line"' \
    'logger -t workspaces-luks-reopen -- "$line tok=$TOKEN"'
  cov "raw_order static"
  msub "41 mkfs target argument changed to the device (format arm)" caught \
    'mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal format 14' \
    'mkfs.ext4 -q "$DEV" >/dev/null 2>"$ERRF" || fatal format 14'
  cov "raw_order static"
  msub "42 luksFormat target argument changed" caught \
    '--uuid "$_nu" --key-file - "$DEV" >/dev/null 2>"$ERRF" \' \
    '--uuid "$_nu" --key-file - "$MAPPER" >/dev/null 2>"$ERRF" \'

  # ── other spellings of a destructive call dropped into a refusal arm (the ext4 refusal) ──
  cov "ext4 static"
  msub "43 flag-first luksFormat spelling in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    cryptsetup --batch-mode luksFormat --key-file /dev/null "$DEV"
    fatal discriminate 12 "the device carries a $(printf'
  cov "ext4 static"
  msub "44 mke2fs in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    mke2fs -t ext4 -F "$DEV"
    fatal discriminate 12 "the device carries a $(printf'
  cov "ext4 static"
  msub "45 dd of= over the device in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    dd if=/dev/zero of="$DEV" bs=1M count=1
    fatal discriminate 12 "the device carries a $(printf'
  cov "ext4 static"
  msub "46 blkdiscard in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    blkdiscard -z "$DEV"
    fatal discriminate 12 "the device carries a $(printf'
  cov "ext4 static"
  msub "47 wipefs -qa in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    wipefs -qa "$DEV"
    fatal discriminate 12 "the device carries a $(printf'
  cov "ext4 static"
  msub "48 cryptsetup luksErase in the ext4 refusal arm" caught \
    '    fatal discriminate 12 "the device carries a $(printf' \
    '    cryptsetup luksErase --batch-mode "$DEV"
    fatal discriminate 12 "the device carries a $(printf'

  # ── failure switches ──
  cov "failures"
  msub "49 mkfs failure ignored in the format arm (the intent is then removed after a FAILED mkfs)" caught \
    'mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal format 14 "mkfs.ext4 failed$(_cause)"' \
    'mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || true'
  cov "failures"
  msub "50 luksFormat failure ignored" caught \
    '    || fatal format 14 "luksFormat failed$(_cause)"' \
    '    || true'
  cov "failures"
  msub "51 the intent is removed BEFORE mkfs" caught \
    '  mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal format 14 "mkfs.ext4 failed$(_cause)"
  _ready_label format 14
  rm -f "$INTENT"' \
    '  rm -f "$INTENT"
  mkfs.ext4 -q "$MAPPER" >/dev/null 2>"$ERRF" || fatal format 14 "mkfs.ext4 failed$(_cause)"
  _ready_label format 14'
  cov "failures"
  msub "52 the stderr cause is not shipped" caught \
    "printf ': %s' \"\$l\"" ':'

  # ── escrow integrity, apt retry, seam guard ──
  cov "escrow"
  msub "53 the escrow CHECK compares size only (a stale same-size header is certified)" caught \
    '[ "${len:-0}" = "$sz" ] && [ "$etag" = "$md5" ]; then return 0; fi' \
    '[ "${len:-0}" = "$sz" ]; then return 0; fi'
  cov "escrow"
  msub "54 the escrow read-back compares size only" caught \
    '[ "${len:-0}" = "$sz" ] && [ "$etag" = "$md5" ] || { ESCROW_WHY=readback' \
    '[ "${len:-0}" = "$sz" ] || { ESCROW_WHY=readback'
  cov "config"
  msub "55 the cryptsetup install gets no second attempt" caught \
    '[ "$_a" -lt 2 ] || break' '[ "$_a" -lt 1 ] || break'
  cov "config"
  msub "56 the test-seam root guard loses its /proc /sys /dev arm" caught \
    '    /proc/*|/sys/*|/dev/*) printf' '    /nonexistent-arm/*) printf'
  # ── volume-bound intent, sync, core limit ──
  cov "blank_mapper"
  msub "58 the intent's UUID is not compared with the volume's (any intent authorises)" caught \
    '[ "${_i_dev:-}" = "$DEV" ] && [ "${_i_uuid:-}" = "$_cur" ] && _bound=1' \
    '[ "${_i_dev:-}" = "$DEV" ] && _bound=1'
  cov "blank_mapper"
  msub "59 the intent's DEV is not compared with the pin" caught \
    '[ "${_i_dev:-}" = "$DEV" ] && [ "${_i_uuid:-}" = "$_cur" ] && _bound=1' \
    '[ "${_i_uuid:-}" = "$_cur" ] && _bound=1'
  cov "raw_order static"
  msub "60 luksFormat is not told the recorded UUID" caught \
    '--label "$LABEL_FORMATTING" --uuid "$_nu" --key-file' \
    '--label "$LABEL_FORMATTING" --key-file'
  cov "failures"
  msub "61 the UUID read-back after luksFormat is dropped" caught \
    '  [ "$(cryptsetup luksUUID "$DEV" 2>/dev/null)" = "$_nu" ] || fatal format 14 "the formatted volume does not carry the UUID the intent file recorded"' \
    '  :'
  cov "crash"
  msub "62 the intent records no volume UUID" caught \
    "printf '%s %s %s\\n' \"\$DEV\" \"\$_nu\" " \
    "printf '%s %s %s\\n' \"\$DEV\" unbound "
  cov "static"
  msub "63 one intent removal loses its sync" caught \
    '    rm -f "$INTENT"; sync
  else' \
    '    rm -f "$INTENT"
  else'
  cov "raw_order static"
  msub "64 the core-dump limit is not lowered" caught \
    'ulimit -c 0 2>/dev/null || true' ':'
  cov "raw_secret_hygiene"
  msub "65 the evidence row goes back to a journald tag Vector does not ship" caught \
    'logger -t workspaces-luks-reopen -- "$line"' 'logger -t workspaces-luks-provision -- "$line"'
  cov "escrow"
  msub "66 the escrow stage is emitted at fatal again (pages)" caught \
    'soleur-boot-emit workspaces_luks_provision_escrow warning' 'soleur-boot-emit workspaces_luks_provision_escrow fatal'
  cov "wire"
  msub "67 the probe-timer warning goes back to the paging wire arm" caught \
    '|| warn wire_warn luks_monitor_timer_not_enabled' '|| warn wire luks_monitor_timer_not_enabled'
  # ── hardening (#9378): the lock, the PATH pin, the seam refusal, atomic writes (Guard 1) ──
  cov "install raw_wiring"
  msub "69 the docker drop-in is written with a direct redirect instead of _install_file" caught \
    'printf '"'"'%s'"'"' "$DROPIN_BODY" | _install_file "$DROPIN" 644 || fatal wire 16 "cannot install the docker drop-in${_IF_WHY:+: $_IF_WHY}"' \
    'printf '"'"'%s'"'"' "$DROPIN_BODY" > "$DROPIN" || fatal wire 16 "cannot write the docker drop-in"'
  cov "install"
  msub "70 the temp file is no longer fsynced before the rename" caught \
    '  sync "$tmp" || { rm -f "$tmp"; _IF_WHY="fsync of the temp file failed"; return 1; }
' ''
  cov "install"
  msub "71 the directory is no longer fsynced after the rename" caught \
    '  sync "$dir" || { _IF_WHY="fsync of the directory failed"; return 1; }' \
    '  :'
  cov "install"
  msub "72 a failing temp fsync is swallowed (|| true)" caught \
    '  sync "$tmp" || { rm -f "$tmp"; _IF_WHY="fsync of the temp file failed"; return 1; }' \
    '  sync "$tmp" || true'
  cov "install"
  msub "73 a second writer is added to crypttab after the compliant one (a trailing >>)" caught \
    '# fstab: exactly ONE non-comment /mnt/data entry' \
    'printf "extra\n" >> "$CRYPTTAB"
# fstab: exactly ONE non-comment /mnt/data entry'
  cov "install"
  msub "74 the symlinked-destination refusal is removed from _install_file (drop-in and intent file are only guarded there)" caught \
    '  [ ! -L "$dest" ] || { _IF_WHY="destination is a symlink"; return 1; }' \
    '  :'
  cov "install"
  msub "75 a pre-existing temp path is not removed first (a planted temp symlink is followed)" caught \
    '  rm -f "$tmp" || { _IF_WHY="cannot clear the temp path"; return 1; }' \
    '  :'
  cov "install"
  mutate "76 a producer that dies mid-stream: its exit status AND the validation are both ignored (a truncated fstab is renamed over the real one)" caught \
    "s.replace('\"\$_fsrc\") || fatal wire 16 \"fstab rewrite failed\"', '\"\$_fsrc\") || true', 1).replace('  || fatal wire 16 \"the rewritten fstab does not hold exactly one canonical /mnt/data line\"', '  || true', 1)"
  cov "install"
  msub "76b only the producer's exit status is ignored: the validation still refuses the truncated fstab (two independent layers)" survive \
    '"$_fsrc") || fatal wire 16 "fstab rewrite failed"' \
    '"$_fsrc") || true'
  cov "install"
  msub "77 only the validation is dropped: the producer's exit status still refuses (two independent layers)" survive \
    '  || fatal wire 16 "the rewritten fstab does not hold exactly one canonical /mnt/data line"' \
    '  || true'
  cov "install"
  msub "78 crypttab: the new line is glued onto an unterminated last line" caught \
    '|| _ct+=' \
    '|| :  # '
  cov "install"
  msub "79 crypttab is rewritten even when it already holds the canonical line (bytes and mode of an unrelated line at risk)" caught \
    '    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"' \
    '    || fatal wire 16 "a foreign workspaces crypttab line exists; refusing to coexist"
  printf "%s\n" "# rewritten" "$_ct" | _install_file "$CRYPTTAB" 600 || true'
  cov "install"
  mutate "80 harmless: a reworded temp-file failure reason stays green" survive \
    "s.replace('_IF_WHY=\"cannot write the temp file\"', '_IF_WHY=\"cannot write the scratch file\"', 1)"
  cov "lock"
  mutate "81 the flock is moved after the first config check (_secure_file)" caught \
    'fl = "flock -w \"$LOCK_WAIT\" 9 || fatal config 10 \"lock_timeout: another provisioner holds the lock\"\n"
sf = "_secure_file \"$ENVFILE\" || fatal config 10 \"boot env file absent, not a regular file, or not root 0600\"\n"
assert fl in s and sf in s
new = s.replace(fl, "", 1).replace(sf, sf + fl, 1)'
  cov "lock"
  msub "82 the lock wait is unbounded (flock 9)" caught \
    'flock -w "$LOCK_WAIT" 9 || fatal' 'flock 9 || fatal'
  cov "lock"
  msub "83 a lock timeout loses its distinct reason" caught \
    'lock_timeout: another provisioner holds the lock' 'another provisioner holds the lock'
  cov "lock"
  msub "84 a provisioner that lost the lock deletes the winner's scratch file" caught \
    '  [ "$HAVE_LOCK" != 1 ] || rm -f "$ERRF" 2>/dev/null || true' \
    '  rm -f "$ERRF" 2>/dev/null || true'
  cov "lock"
  msub "85 the lock-timeout knob is readable outside the seam" caught \
    '[ -z "$ROOT" ] || LOCK_WAIT="${WORKSPACES_PROVISION_LOCK_WAIT:-600}"' \
    'LOCK_WAIT="${WORKSPACES_PROVISION_LOCK_WAIT:-600}"'
  cov "lock"
  msub "86 the lock-timeout value is not validated" caught \
    '[[ "$LOCK_WAIT" =~ ^[0-9]{1,4}$ ]] || LOCK_WAIT=600' ':'
  cov "lock"
  msub "87 a missing flock falls through to rc 127 (the probe is dropped)" caught \
    'command -v flock >/dev/null 2>&1 || fatal config 10 "flock is absent"' ':'
  cov "lock"
  msub "88 a failed lock-file open is not fatal" caught \
    'exec 9>"${ROOT}/run/workspaces-luks-provision.lock" || fatal config 10 "cannot open the lock file"' \
    'exec 9>"${ROOT}/run/workspaces-luks-provision.lock" || true'
  cov "pathpin"
  msub "89 the PATH pin is deleted" caught \
    '  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  export PATH
' ''
  cov "pathpin"
  mutate "90 the PATH pin is set only after the first external command (after the lock)" caught \
    'a = s.index("# >>> pin\n")
b = s.index("# <<< pin\n") + len("# <<< pin\n")
blk = s[a:b]
anchor = "HAVE_LOCK=1\n"
assert anchor in s
new = s[:a] + s[b:]
new = new.replace(anchor, anchor + blk, 1)'
  cov "pathpin"
  msub "91 the stage-detail directory is no longer clamped in production" caught \
    '  SOLEUR_STAGE_DETAIL_DIR=/run/soleur-stage-detail.d
  export SOLEUR_STAGE_DETAIL_DIR
' ''
  cov "seam"
  msub "92 _seam_allowed returns 0 unconditionally (the seam is always allowed)" caught \
    '  [ ! -e "$1" ] && [ ! -L "$1" ]' '  return 0'
  cov "seam"
  msub "93 the cloud-init marker path comes from an environment variable" caught \
    '! _seam_allowed /var/lib/cloud/instance' \
    '! _seam_allowed "${WORKSPACES_PROVISION_MARKER:-/var/lib/cloud/instance}"'
  cov "seam"
  msub "94 the euid-0 predicate is mutated away (a non-root runner with cloud-init state is refused too)" caught \
    '[ "$(id -u)" = 0 ] && ! _seam_allowed' '! _seam_allowed'
  cov "seam"
  msub "95 the euid predicate is inverted (root is never refused)" caught \
    '[ "$(id -u)" = 0 ] && ! _seam_allowed' '[ "$(id -u)" != 0 ] && ! _seam_allowed'
  cov "seam"
  msub "96 _seam_allowed forgets dangling symlinks (-e only)" caught \
    '  [ ! -e "$1" ] && [ ! -L "$1" ]' '  [ ! -e "$1" ]'
  cov "escrow"
  msub "97 the escrow endpoint pin is relaxed back to any https host" caught \
    '^https://[0-9a-f]{32}\.r2\.cloudflarestorage\.com$' '^https://[A-Za-z0-9.-]+$'
  cov "lock"
  envrow "98 a hardening case is deleted from the suite" 1 "WLP_DROP_CASE=lock"
  mutate "57 harmless: renaming the private stderr scratch file stays green" survive \
    "s.replace('workspaces-luks-cmd.err', 'workspaces-luks-cmd.stderr', 1)"
  cov "install"
  msub "99 the crypttab read tests printf's status again (cat ... ; printf x)" caught \
    '_ct=$(cat "$CRYPTTAB" && printf x)' '_ct=$(cat "$CRYPTTAB"; printf x)'

  score_rows
  MUT_ROWS_EXPECTED=100
  [ "$mut_rows" -eq "$MUT_ROWS_EXPECTED" ] || { printf 'FAIL - %s mutation rows ran, expected %s\n' "$mut_rows" "$MUT_ROWS_EXPECTED"; exit 1; }
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
# Anti-vacuity floor (EXACT: 232 inner assertions + 100 mutation rows; raise it with every added check). The threshold sits on the line directly above its `if`.
_wlp_floor="${WLP_MUTANT:+0}"
[ -z "$ONLY" ] || _wlp_floor=-232 # a restricted inner run executes only the named cases: its floor is 0 (the outer control run keeps the full floor)
MIN_ASSERTIONS=$((232 + ${_wlp_floor:-100}))
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"; exit 1
fi
[ "$fail" -eq 0 ] || { printf 'failed: %s\n' "${FAILED[@]}"; exit 1; }
printf 'all assertions passed\n'
exit 0
