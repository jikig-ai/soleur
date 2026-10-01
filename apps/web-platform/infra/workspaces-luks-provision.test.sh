#!/usr/bin/env bash
# workspaces-luks-provision.test.sh — Guard 1 for the guest-side fresh-boot LUKS provisioner (#6931).
#
# PROPERTY UNDER TEST. workspaces-luks-provision.sh runs `cryptsetup luksFormat` or `mkfs` only on
# a device whose `blkid -o value -s TYPE` is empty (rc 2) AND which shows no partition table or other
# signature — re-checked immediately before EACH destructive call — and never on any other state.
# `mkfs` on a LUKS mapper happens only for a blank mapper whose format THIS provisioner started (the
# durable intent file). It never uses `cryptsetup isLuks`.
#
# SHAPE. Every external command is a stub on a scratch PATH that appends "<cmd> <argv>" to a calls
# log, driven by small state files; the provisioner runs against a scratch root through its test
# seam. Assertions are over the CALLS (what was invoked, in what order, with what), never over a
# value compared with the thing it protects. Mutation rows at the bottom mutate COPIES of the
# provisioner and re-run this file against them (WLP_SCRIPT); rc 1 = the mutation was caught, rc 0 =
# it SURVIVED, rc 2 = a broken instrument (never counted as a catch).
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
WLP_MUTANT="${WLP_MUTANT:-}"

pass=0; fail=0; FAILED=()
ok() { if [ "$1" -eq 0 ]; then pass=$((pass + 1)); printf '[ok] %s\n' "$2"; else fail=$((fail + 1)); FAILED+=("$2"); printf '[FAIL] %s%s\n' "$2" "${3:+ ($3)}"; fi; }
no() { fail=$((fail + 1)); FAILED+=("$1"); printf '[FAIL] %s\n' "$1"; }

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

# INSTRUMENT SELF-TEST — both helpers must move their own counter before any verdict is trusted.
_p0=$pass; _f0=$fail
{ ok 0 "self-test"; no "self-test"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; FAILED=()

[ -r "$SUT" ] || { printf '[FATAL] unreadable: %s\n' "$SUT" >&2; exit 2; }
SCRATCH="$(mktemp -d)"
assert_fixture_dir "$SCRATCH"
trap 'rm -rf "$SCRATCH"' EXIT

DEVID=424242
DEVPIN="/dev/disk/by-id/scsi-0HC_Volume_$DEVID"
KEYVAL="FIXTURE-PASSPHRASE-0001"
TOKVAL="TESTTOKEN-not-a-credential-0001"
SECVAL="TESTSECRET-not-a-credential-0002"

# ── stubs ─────────────────────────────────────────────────────────────────────────────────────
write_stubs() { # <fx>
  local b="$1/bin"
  cat > "$b/_log" <<'EOF'
#!/bin/bash
[ -z "${WLP_STUB_NOLOG:-}" ] || exit 0
printf '%s\n' "$*" >> "$FX/calls"
EOF
  cat > "$b/blkid" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "blkid $*"
last="${*: -1}"
st="$FX/st"
case "$*" in
  *PTTYPE*) v=$(cat "$st/dev.pttype" 2>/dev/null); [ -n "$v" ] && { printf '%s\n' "$v"; exit 0; }; exit 2 ;;
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
  cat > "$b/cryptsetup" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "cryptsetup $*"
st="$FX/st"
case "$1" in
  luksFormat)
    key=$(cat); [ -n "$key" ] || exit 2
    "$(dirname "$0")/_log" "luksFormat-state intent_present=$([ -f "$FX/root/var/lib/soleur/workspaces-luks-formatting" ] && echo 1 || echo 0)"
    [ -f "$st/fail.luksFormat" ] && exit 1
    printf 'crypto_LUKS' > "$st/dev.type"; printf 'crypto_LUKS signature\n' > "$st/dev.wipefs"
    [ -f "$st/crash_after_luksFormat" ] && kill -9 "$PPID"
    exit 0 ;;
  luksOpen)
    key=$(cat); [ "$key" = "$(cat "$st/key")" ] || exit 2
    [ -f "$st/fail.luksOpen" ] && exit 2
    echo 1 > "$st/map.active"; exit 0 ;;
  status)
    [ -s "$st/map.active" ] || exit 4
    printf '/dev/mapper/workspaces is active.\n  type:    LUKS2\n  device:  %s\n' "$(cat "$st/backing")"; exit 0 ;;
  luksUUID) printf '11111111-2222-3333-4444-555555555555\n'; exit 0 ;;
  luksHeaderBackup)
    [ -f "$st/fail.hdrbackup" ] && exit 1
    f=""; while [ $# -gt 0 ]; do [ "$1" = --header-backup-file ] && f="$2"; shift; done
    head -c 4096 /dev/zero > "$f"; exit 0 ;;
  isLuks) exit 1 ;;
esac
exit 0
EOF
  cat > "$b/mkfs.ext4" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "mkfs.ext4 $*"
st="$FX/st"
[ -f "$st/fail.mkfs" ] && exit 1
printf 'ext4' > "$st/map.type"; printf 'ext4 signature\n' > "$st/map.wipefs"
[ -f "$st/crash_after_mkfs" ] && kill -9 "$PPID"
exit 0
EOF
  cat > "$b/wipefs" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "wipefs $*"
st="$FX/st"
case "$*" in *" -a"*|*--all*|*" -f"*|*--force*) "$(dirname "$0")/_log" "WIPEFS_WRITE"; exit 0 ;; esac
last="${*: -1}"
if [ "$last" = /dev/mapper/workspaces ]; then cat "$st/map.wipefs" 2>/dev/null; else cat "$st/dev.wipefs" 2>/dev/null; fi
exit 0
EOF
  cat > "$b/lsblk" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "lsblk $*"
st="$FX/st"
echo sdb
c=$(cat "$st/dev.children" 2>/dev/null || echo 0); i=0; while [ "$i" -lt "$c" ]; do echo "sdb$((i+1))"; i=$((i+1)); done
[ -s "$st/map.active" ] && echo workspaces
exit 0
EOF
  cat > "$b/findmnt" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "findmnt $*"
st="$FX/st"
case "$*" in
  *"-S /dev/mapper/workspaces"*) [ -s "$st/map.mounted_direct" ] && echo /mnt/elsewhere; exit 0 ;;
  *"-S /dev/disk/by-id/"*) [ -s "$st/dev.mounted" ] && echo /mnt/elsewhere; exit 0 ;;
  *"-o SOURCE /mnt/data"*) [ -s "$st/mounted" ] || exit 1; if [ -s "$st/mounted.src" ]; then cat "$st/mounted.src"; else echo /dev/mapper/workspaces; fi; exit 0 ;;
esac
exit 0
EOF
  cat > "$b/mountpoint" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "mountpoint $*"
[ -s "$FX/st/mounted" ]
EOF
  cat > "$b/mount" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "mount $*"
[ -f "$FX/st/fail.mount" ] && exit 32
grep -qxF '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2' "$FX/root/etc/fstab" || exit 33
echo 1 > "$FX/st/mounted"; exit 0
EOF
  cat > "$b/chattr" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "chattr $*"
[ -f "$FX/st/fail.chattr" ] && exit 1
echo 1 > "$FX/st/immutable"; exit 0
EOF
  cat > "$b/lsattr" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "lsattr $*"
if [ -s "$FX/st/immutable" ] && [ ! -f "$FX/st/lsattr.hide" ]; then echo '----i---------e------- /mnt/data'; else echo '--------------e------- /mnt/data'; fi
EOF
  cat > "$b/systemctl" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "systemctl $*"
exit 0
EOF
  cat > "$b/logger" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "logger $*"
exit 0
EOF
  cat > "$b/soleur-boot-emit" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "boot-emit $*"
exit 0
EOF
  cat > "$b/sleep" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "sleep $*"
exit 0
EOF
  cat > "$b/blockdev" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "blockdev $*"
st="$FX/st"
n=$(( $(cat "$st/blockdev.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/blockdev.n"
if [ "$n" -le "$(cat "$st/blockdev.zero_until" 2>/dev/null || echo 0)" ]; then echo 0; exit 0; fi
echo 21474836480
EOF
  cat > "$b/doppler" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "doppler $*"
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
  cat > "$b/curl" <<'EOF'
#!/bin/bash
"$(dirname "$0")/_log" "curl $*"
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
  if [ -f "$st/fail.put" ]; then code=403; else echo "$(stat -c %s "$up")" > "$st/s3.len"; code=200; fi
elif [ "$method" = HEAD ]; then
  if [ -f "$st/fail.head" ]; then code=500; elif [ -s "$st/s3.len" ]; then code=200; else code=404; fi
fi
[ -z "$dfile" ] || printf 'HTTP/1.1 %s\r\ncontent-length: %s\r\n\r\n' "$code" "$(cat "$st/s3.len" 2>/dev/null || echo 0)" > "$dfile"
[ -z "$code_out" ] || printf '%s' "$code"
exit 0
EOF
  # Inline the call logger (a function per stub) instead of forking a helper script per call.
  local f
  for f in "$b"/*; do
    sed -i -e 's|"$(dirname "$0")/_log"|_L|g' "$f"
    sed -i -e '1a _L() { [ -z "${WLP_STUB_NOLOG:-}" ] || return 0; printf "%s\\n" "$*" >> "$FX/calls"; }' "$f"
  done
  rm -f "$b/_log"
  chmod 0755 "$b"/*
}

new_fx() { # builds a pristine fixture; sets FX
  FX="$(mktemp -d "$SCRATCH/fx.XXXXXXXX")"
  assert_fixture_dir "$FX"
  mkdir -p "$FX/bin" "$FX/st" "$FX/root/etc/default" "$FX/root/etc/systemd/system" "$FX/root/var/lib" "$FX/root/run" "$FX/root/mnt"
  : > "$FX/calls"
  write_stubs "$FX"
  printf 'WORKSPACES_LUKS_DEV=%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' "$DEVPIN" > "$FX/root/etc/default/workspaces-luks-boot"
  chmod 600 "$FX/root/etc/default/workspaces-luks-boot"
  printf 'SOLEUR_SENTRY_DSN=https://example.invalid/1\nDOPPLER_TOKEN=%s\n' "$TOKVAL" > "$FX/root/etc/default/luks-monitor"
  chmod 600 "$FX/root/etc/default/luks-monitor"
  printf '# fstab\n' > "$FX/root/etc/fstab"
  : > "$FX/root/etc/crypttab"
  printf '%s\n' "$DEVPIN" > "$FX/st/backing"
  printf '%s' "$KEYVAL" > "$FX/st/key"
  printf 'soleur-test-header\n' > "$FX/st/doppler.WORKSPACES_HEADER_BUCKET"
  printf 'TESTKEYID0001\n' > "$FX/st/doppler.WORKSPACES_HEADER_R2_ACCESS_KEY_ID"
  printf '%s\n' "$SECVAL" > "$FX/st/doppler.WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY"
  printf 'https://example.invalid\n' > "$FX/st/doppler.WORKSPACES_HEADER_R2_ENDPOINT"
}

run_sut() { # runs the provisioner in $FX; sets RC
  RC=0
  env -i PATH="$FX/bin:/usr/bin:/bin" FX="$FX" WLP_STUB_NOLOG="${WLP_STUB_NOLOG:-}" \
    WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "${1:-$SUT}" > "$FX/out" 2> "$FX/err" || RC=$?
}

has()  { grep -qE -- "$1" "$FX/calls"; }
lack() { ! grep -qE -- "$1" "$FX/calls"; }
lineno() { grep -nE -- "$1" "$FX/calls" | head -1 | cut -d: -f1; }
yes() { "$@"; echo $?; }
expect() { # <name> <cmd...> — the command's exit status is the verdict
  local n="$1"; shift
  if "$@"; then ok 0 "$n"; else ok 1 "$n"; fi
}
count_calls() { grep -cE -- "$1" "$FX/calls" || true; }

CASES_RUN=()
dropped() { [ -n "${WLP_DROP_CASE:-}" ] && [ "$WLP_DROP_CASE" = "$1" ]; }
# A dropped case is NOT recorded, so the case-set assertion below reds on a deleted case.
begin() { dropped "$1" && return 1; CASES_RUN+=("$1"); return 0; }

# Every destructive/write call a refusal case must NOT have made.
NO_WRITES='cryptsetup (luksFormat|luksOpen)|mkfs\.|WIPEFS_WRITE|^mount |^chattr |systemctl enable'
no_writes() { lack "$NO_WRITES"; }
files_untouched() { [ "$(cat "$FX/root/etc/fstab")" = "# fstab" ] && [ ! -s "$FX/root/etc/crypttab" ] && [ ! -e "$FX/root/etc/systemd/system/docker.service.d" ]; }

# ── cases ─────────────────────────────────────────────────────────────────────────────────────
case_raw_formats_once() {
  begin raw || return
  new_fx; run_sut
  expect "raw: rc 0" test "$RC" -eq 0
  local a b c
  a=$(lineno '^cryptsetup luksFormat'); b=$(lineno '^cryptsetup luksOpen'); c=$(lineno '^mkfs\.ext4')
  expect "raw: luksFormat -> luksOpen -> mkfs in that order" test -n "$a" -a -n "$b" -a -n "$c" && [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ]
  expect "raw: luksFormat uses luks2 + batch-mode + stdin key" has '^cryptsetup luksFormat --batch-mode --type luks2 --key-file - '
  expect "raw: the intent file existed when luksFormat ran" has '^luksFormat-state intent_present=1'
  expect "raw: the intent file is gone after mkfs" test ! -e "$FX/root/var/lib/soleur/workspaces-luks-formatting"
  expect "raw: exactly one luksFormat and one mkfs" test "$(count_calls '^cryptsetup luksFormat')" -eq 1 -a "$(count_calls '^mkfs\.ext4')" -eq 1
  expect "raw: arm file says formatted + escrow ok" test "$(cat "$FX/root/run/soleur/workspaces-luks-arm")" = "$(printf 'luks_arm=formatted\nescrow=ok')"
  expect "raw: crypttab holds the canonical line exactly once" test "$(cat "$FX/root/etc/crypttab")" = "workspaces $DEVPIN none luks,noauto"
  expect "raw: fstab holds exactly one /mnt/data line and it is the canonical one" test "$(grep -vc '^#' "$FX/root/etc/fstab")" -eq 1 && grep -qxF '/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2' "$FX/root/etc/fstab"
  expect "raw: the docker drop-in is the canonical 3 lines" test "$(cat "$FX/root/etc/systemd/system/docker.service.d/10-workspaces-luks-mount.conf")" = "$(printf '[Unit]\nRequiresMountsFor=/mnt/data\nAfter=workspaces-luks-reopen.service')"
  local ci mo
  ci=$(lineno '^chattr \+i'); mo=$(lineno '^mount /mnt/data')
  expect "raw: the covered inode is made immutable BEFORE the mount" test -n "$ci" -a -n "$mo" && [ "$ci" -lt "$mo" ]
  expect "raw: the reopen service + timer are enabled" has '^systemctl enable workspaces-luks-reopen\.service workspaces-luks-reopen\.timer'
  expect "raw: the daily probe timer is enabled and the service is NOT started (Row 10 of luks-monitor-install)" has '^systemctl enable --now luks-monitor\.timer' && lack 'luks-monitor\.service'
  expect "raw: never calls isLuks" lack 'isLuks'
  expect "raw: the passphrase never appears in any argv or log" test "$(grep -c -- "$KEYVAL" "$FX/calls" "$FX/out" "$FX/err" | awk -F: '{s+=$2} END{print s+0}')" -eq 0
  expect "raw: the doppler token reaches doppler by env, never argv" test -n "$(sort -u "$FX/st/doppler.tokens")" -a "$(sort -u "$FX/st/doppler.tokens")" = "$TOKVAL" && lack "$TOKVAL"
  expect "raw: the key is fetched with the R9-pinned single-secret form" has '^doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks$'
  expect "raw: never uses doppler run or secrets download" lack 'doppler (run|secrets download)'
  expect "raw: a result row is logged" grep -q 'arm=result rc=0 luks_arm=formatted escrow=ok' "$FX/err"
  # second run on the state the first run left behind: a no-op.
  : > "$FX/calls"; run_sut
  expect "raw: second run rc 0" test "$RC" -eq 0
  expect "raw: second run is a no-op (no luksFormat/luksOpen/mkfs)" lack '^cryptsetup (luksFormat|luksOpen)|^mkfs\.'
  expect "raw: second run records noop" test "$(head -1 "$FX/root/run/soleur/workspaces-luks-arm")" = luks_arm=noop
  expect "raw: second run leaves one crypttab line and one fstab line" test "$(grep -c . "$FX/root/etc/crypttab")" -eq 1 -a "$(grep -vc '^#' "$FX/root/etc/fstab")" -eq 1
  expect "raw: second run does not re-upload an escrowed header" lack '^curl .*-T '
}

case_luks_opens() {
  begin luks_open || return
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"
  run_sut
  expect "luks: rc 0" test "$RC" -eq 0
  expect "luks: opens the mapper" has '^cryptsetup luksOpen '
  expect "luks: never formats and never mkfs" lack '^cryptsetup luksFormat|^mkfs\.'
  expect "luks: arm is opened" test "$(head -1 "$FX/root/run/soleur/workspaces-luks-arm")" = luks_arm=opened
}

case_ext4_refused() {
  begin ext4 || return
  new_fx; printf 'ext4' > "$FX/st/dev.type"
  run_sut
  expect "ext4: FATAL discriminate (12)" test "$RC" -eq 12
  expect "ext4: ZERO write calls" no_writes
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
}

case_blank_mapper() {
  begin blank_mapper || return
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"          # LUKS container, blank mapper, NO intent file
  run_sut
  expect "blank mapper without intent: FATAL open (15) — a damaged store" test "$RC" -eq 15
  expect "blank mapper without intent: NEVER mkfs" lack '^mkfs\.'
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; mkdir -p "$FX/root/var/lib/soleur"; printf 'x 1\n' > "$FX/root/var/lib/soleur/workspaces-luks-formatting"
  printf 'leftover signature\n' > "$FX/st/map.wipefs"
  run_sut
  expect "blank mapper WITH intent but a visible signature: FATAL, no mkfs" test "$RC" -eq 15 && lack '^mkfs\.'
}

case_crash_recovery() {
  begin crash || return
  new_fx; : > "$FX/st/crash_after_luksFormat"
  run_sut
  expect "crash after luksFormat: the process died (137)" test "$RC" -eq 137
  expect "crash after luksFormat: the intent file survives" test -e "$FX/root/var/lib/soleur/workspaces-luks-formatting"
  expect "crash after luksFormat: no mkfs yet" lack '^mkfs\.'
  rm -f "$FX/st/crash_after_luksFormat"; : > "$FX/calls"
  run_sut
  expect "next boot after the crash: rc 0" test "$RC" -eq 0
  expect "next boot after the crash: finishes mkfs exactly once, never luksFormat" test "$(count_calls '^mkfs\.ext4')" -eq 1 && lack '^cryptsetup luksFormat'
  expect "next boot after the crash: the intent file is removed" test ! -e "$FX/root/var/lib/soleur/workspaces-luks-formatting"
  expect "next boot after the crash: the mapper ends mounted" test -s "$FX/st/mounted"
  new_fx; : > "$FX/st/crash_after_mkfs"
  run_sut
  expect "crash after mkfs: the process died (137)" test "$RC" -eq 137
  rm -f "$FX/st/crash_after_mkfs"; : > "$FX/calls"
  run_sut
  expect "next boot after a post-mkfs crash: rc 0, no second mkfs, intent removed" test "$RC" -eq 0 -a ! -e "$FX/root/var/lib/soleur/workspaces-luks-formatting" && lack '^mkfs\.'
}

case_state_change() {
  begin state_change || return
  new_fx; printf '2' > "$FX/st/flip_after"                    # blkid calls 1-2 read raw; call 3 reads ext4
  run_sut
  expect "device changes state after discriminate: FATAL format (14)" test "$RC" -eq 14
  expect "device changes state after discriminate: luksFormat is NEVER called" lack '^cryptsetup luksFormat'
  expect "device changes state after discriminate: the intent file is not left behind" test ! -e "$FX/root/var/lib/soleur/workspaces-luks-formatting"
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
  expect "empty key: FATAL key (13), no luksFormat" test "$RC" -eq 13 && lack '^cryptsetup luksFormat'
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
  new_fx; rm -f "$FX/root/etc/default/luks-monitor"; run_sut
  expect "config: token file absent -> 10" test "$RC" -eq 10
  new_fx; printf 'DOPPLER_TOKEN=a\nDOPPLER_TOKEN=b\n' > "$FX/root/etc/default/luks-monitor"; run_sut
  expect "config: two DOPPLER_TOKEN lines -> 10 (ambiguity is refused)" test "$RC" -eq 10
  expect "config: every config refusal made ZERO calls to anything destructive" no_writes
  # cryptsetup absent: a PATH of symlinks to ONLY the tools the script needs, so a host that really
  # has cryptsetup installed cannot satisfy the lookup (the outcome must not depend on the runner).
  new_fx; rm -f "$FX/bin/cryptsetup"; mkdir -p "$FX/core"
  local t
  for t in awk sed grep cat stat id mkdir mv rm date sync shred realpath mktemp sha256sum cut head tail tr wc ls sort chmod timeout bash dirname env printf kill cp; do
    ln -s "$(command -v "$t")" "$FX/core/$t" 2>/dev/null || true
  done
  RC=0; env -i PATH="$FX/bin:$FX/core" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" \
    SOLEUR_STAGE_DETAIL_DIR="$FX/root/detail" bash "$SUT" > "$FX/out" 2> "$FX/err" || RC=$?
  expect "config: cryptsetup absent (and not installable) -> 10, no writes" test "$RC" -eq 10 && no_writes
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
  expect "foreign crypttab workspaces line: FATAL wire (16), never coexisted with" test "$RC" -eq 16 && test "$(grep -c . "$FX/root/etc/crypttab")" -eq 1
  new_fx; printf '# fstab\n/dev/disk/by-id/scsi-0HC_Volume_%s /mnt/data ext4 defaults,nofail 0 2\n' "$DEVID" > "$FX/root/etc/fstab"
  run_sut
  expect "a foreign /mnt/data fstab line is commented in place, not deleted, and the canonical one is the only live line" test "$RC" -eq 0 && test "$(grep -vc '^#' "$FX/root/etc/fstab")" -eq 1 && grep -q '^# provision-6931-superseded /dev/disk/by-id/' "$FX/root/etc/fstab"
  new_fx; : > "$FX/st/fail.chattr"; run_sut
  expect "chattr +i fails: FATAL wire (16) and /mnt/data is never mounted" test "$RC" -eq 16 && lack '^mount '
  new_fx; : > "$FX/st/lsattr.hide"; run_sut
  expect "lsattr does not show the i flag: FATAL wire (16)" test "$RC" -eq 16 && lack '^mount '
  new_fx; : > "$FX/st/fail.mount"; run_sut
  expect "mount fails: FATAL mount (17)" test "$RC" -eq 17
  new_fx; printf '/dev/sdb1\n' > "$FX/st/mounted.src"; run_sut
  expect "/mnt/data mounted from the wrong source: FATAL mount (17)" test "$RC" -eq 17
  new_fx; printf 'crypto_LUKS' > "$FX/st/dev.type"; printf 'ext4' > "$FX/st/map.type"; echo 1 > "$FX/st/map.active"; printf '/dev/disk/by-id/scsi-0HC_Volume_999\n' > "$FX/st/backing"
  run_sut
  expect "the mapper is backed by a different device than the pin: FATAL open (15)" test "$RC" -eq 15 && lack '^mount '
}

case_escrow() {
  begin escrow || return
  new_fx; : > "$FX/st/fail.put"; run_sut
  expect "escrow PUT fails: boot continues (rc 0)" test "$RC" -eq 0
  expect "escrow PUT fails: escrow=missing is recorded" test "$(sed -n 2p "$FX/root/run/soleur/workspaces-luks-arm")" = escrow=missing
  expect "escrow PUT fails: the page-level stage is emitted" has '^boot-emit workspaces_luks_provision_escrow fatal'
  expect "escrow PUT fails: /mnt/data is nevertheless mounted" test -s "$FX/st/mounted"
  rm -f "$FX/st/fail.put"; : > "$FX/calls"; run_sut
  expect "escrow retried on the next boot and now succeeds" test "$(sed -n 2p "$FX/root/run/soleur/workspaces-luks-arm")" = escrow=ok && has '^curl .*-T '
  new_fx; : > "$FX/st/fail.head"; run_sut
  expect "escrow read-back fails: escrow=missing, boot continues" test "$RC" -eq 0 && test "$(sed -n 2p "$FX/root/run/soleur/workspaces-luks-arm")" = escrow=missing
  new_fx; : > "$FX/st/fail.hdrbackup"; run_sut
  expect "luksHeaderBackup fails: escrow=missing, boot continues" test "$RC" -eq 0 && test "$(sed -n 2p "$FX/root/run/soleur/workspaces-luks-arm")" = escrow=missing
  new_fx; : > "$FX/st/doppler.WORKSPACES_HEADER_BUCKET"; run_sut
  expect "escrow credentials unreadable: escrow=missing, boot continues" test "$RC" -eq 0 && test "$(sed -n 2p "$FX/root/run/soleur/workspaces-luks-arm")" = escrow=missing
  new_fx; run_sut
  expect "escrow: the R2 secret reaches curl on stdin config only, never argv" test "$(grep -c -- "$SECVAL" "$FX/calls")" -eq 0 -a "$(grep -c -- "$SECVAL" "$FX/st/curl.cfg")" -ge 1
  expect "escrow: SigV4 signing is requested with the R2 form" has "aws-sigv4 aws:amz:auto:s3"
  expect "escrow: the object key carries the header UUID" has 'workspaces-luks-header-11111111-2222-3333-4444-555555555555\.img'
  expect "escrow: the tmpfs header copy is removed" test -z "$(ls "$FX/root/run" | grep lukshdr || true)"
}

case_xtrace_and_static() {
  begin static || return
  new_fx
  RC=0; env -i PATH="$FX/bin:/usr/bin:/bin" FX="$FX" WORKSPACES_PROVISION_TEST_SEAM=1 WORKSPACES_PROVISION_ROOT="$FX/root" bash -x "$SUT" > "$FX/out" 2> "$FX/err" || RC=$?
  expect "xtrace is refused (78) before anything runs" test "$RC" -eq 78
  expect "xtrace refusal made no calls at all" test ! -s "$FX/calls"
  local code
  code="$(awk '{ s=$0; sub(/^[[:space:]]*#.*/, "", s); print s }' "$SUT")"
  expect "static: no isLuks anywhere in the provisioner code" test "$(printf '%s\n' "$code" | grep -c 'isLuks')" -eq 0
  expect "static: exactly one luksFormat token" test "$(printf '%s\n' "$code" | grep -c 'cryptsetup luksFormat')" -eq 1
  expect "static: exactly two mkfs tokens (format arm + interrupted-birth recovery)" test "$(printf '%s\n' "$code" | grep -c 'mkfs\.ext4 -q')" -eq 2
  expect "static: the luksFormat is preceded by a _may_format re-check in the same arm" test "$(printf '%s\n' "$code" | grep -B8 'cryptsetup luksFormat' | grep -c '_may_format ||')" -ge 1
  expect "static: every mkfs is preceded by a _may_format_fs re-check" test "$(printf '%s\n' "$code" | grep -B3 'mkfs\.ext4 -q' | grep -c '_may_format_fs ||')" -eq 2
  expect "static: no wipefs write flag anywhere" test "$(printf '%s\n' "$code" | grep -cE 'wipefs +(-a|--all|-f|--force)')" -eq 0
  expect "static: exactly three luksFormat/luksOpen call sites, every one reading the key from stdin" test "$(printf '%s\n' "$code" | grep -cE 'cryptsetup luks(Format|Open)')" -eq 3 -a "$(printf '%s\n' "$code" | grep -E 'cryptsetup luks(Format|Open)' | grep -vc -- '--key-file -')" -eq 0
}

case_long_path() {
  begin long_path || return
  new_fx
  local big=123456789012
  printf 'WORKSPACES_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_%s\nWORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks\n' "$big" > "$FX/root/etc/default/workspaces-luks-boot"
  printf '/dev/disk/by-id/scsi-0HC_Volume_%s\n' "$big" > "$FX/st/backing"
  run_sut
  expect "must-pass: a raw device with a different serial and a longer by-id path formats normally" test "$RC" -eq 0 && has '^cryptsetup luksFormat'
}

run_cases() {
  case_raw_formats_once; case_luks_opens; case_ext4_refused; case_blkid_rc; case_signatures_refused
  case_blank_mapper; case_crash_recovery; case_state_change; case_key; case_config; case_device_wait
  case_wire; case_escrow; case_xtrace_and_static; case_long_path
}
EXPECTED_CASES=15
run_cases

# The suite asserts its own case set and that the stubs recorded anything at all: a deleted case or a
# stub that logs nothing must RED the suite, never pass vacuously.
[ "${#CASES_RUN[@]}" -eq "$EXPECTED_CASES" ] || { printf 'FAIL - %s cases ran, expected %s (a case was deleted)\n' "${#CASES_RUN[@]}" "$EXPECTED_CASES"; exit 1; }
if [ -n "${WLP_STUB_NOLOG:-}" ]; then
  printf 'FAIL - the stubs recorded 0 calls; every call assertion above is vacuous\n'; exit 1
fi

# ── mutation rows (outer run only) ────────────────────────────────────────────────────────────
if [ -z "$WLP_MUTANT" ]; then
  mut_rows=0
  MUT="$SCRATCH/mut"; mkdir -p "$MUT"; assert_fixture_dir "$MUT"
  # <name> <expect: caught|survive> <python-expression over s producing the mutated source>
  mutate() {
    local name="$1" want="$2" expr="$3" m="$MUT/m$((mut_rows + 1)).sh" rc
    mut_rows=$((mut_rows + 1))
    cp "$PRISTINE" "$m"
    WLP_M="$m" WLP_EXPR="$expr" python3 - <<'PY' || { no "mutation did NOT land (python): $name"; return; }
import os
p = os.environ["WLP_M"]
s = open(p).read()
ns = {"s": s}
new = eval(os.environ["WLP_EXPR"], {}, ns)
assert new != s, "mutation produced identical source"
open(p, "w").write(new)
PY
    cmp -s "$PRISTINE" "$m" && { no "mutation did NOT land (identical bytes): $name"; return; }
    rc=0; WLP_MUTANT=1 WLP_SCRIPT="$m" bash "$SELF" > "$MUT/out.$mut_rows" 2>&1 || rc=$?
    case "$rc" in
      1) [ "$want" = caught ] && ok 0 "mutation caught: $name" || ok 1 "mutation caught but expected to survive: $name" ;;
      0) [ "$want" = survive ] && ok 0 "harmless variant stays green: $name" || ok 1 "mutation SURVIVED: $name" ;;
      *) no "broken instrument (rc=$rc): $name" ;;
    esac
  }
  envrow() { # <name> <want-rc> <ENV=val>
    local rc=0; env WLP_MUTANT=1 "$3" bash "$SELF" > "$MUT/out.env" 2>&1 || rc=$?
    mut_rows=$((mut_rows + 1))
    [ "$rc" -ne 0 ] && [ "$rc" = "$2" ] && ok 0 "harness row: $1" || ok 1 "harness row: $1" "rc=$rc"
  }

  mutate "1 blkid probe replaced by cryptsetup isLuks (inverted guard)" caught \
    "s.replace('TYPE=\$(blkid -o value -s TYPE \"\$DEV\" 2>/dev/null) || _rc=\$?', 'cryptsetup isLuks \"\$DEV\" >/dev/null 2>&1 && TYPE=crypto_LUKS || { TYPE=\"\"; _rc=2; }', 1)"
  mutate "2 ext4 treated as formattable" caught \
    "s.replace('  crypto_LUKS) MODE=open ;;', '  crypto_LUKS) MODE=open ;;\n  ext4) MODE=format ;;', 1)"
  mutate "3 blkid rc 4/8 folded into empty (every layer that reads the rc)" caught \
    "s.replace('case \"\$_rc\" in 0|2) : ;; *) fatal', 'case \"\$_rc\" in *) : ;; esac; case x in y) fatal', 1).replace('[ \"\$_rc\" = 2 ] || fatal discriminate 12 \"blkid rc 0 with no TYPE is ambiguous\"', ':', 1).replace('  [ \"\$rc\" = 2 ] && [ -z \"\$t\" ] || return 1\n  rc=0; pt=', '  rc=0; pt=', 1)"
  mutate "4 PTTYPE and wipefs corroboration dropped" caught \
    "s.replace('  [ \"\$rc\" = 2 ] && [ -z \"\$pt\" ] || return 1\n', '', 1).replace('  [ \"\$rc\" = 0 ] && [ -z \"\$wf\" ] || return 1\n  [ \"\$(lsblk', '  [ \"\$(lsblk', 1)"
  mutate "5 luksFormat called directly from the open arm" caught \
    "s.replace('    4)\n      _get_key\n', '    4)\n      _get_key\n      printf \"%s\" \"\$KEY\" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - \"\$DEV\" >/dev/null 2>&1\n', 1)"
  mutate "6 _may_format not re-run before luksFormat (discriminate-time only)" caught \
    "s.replace('  _may_format || fatal format 14 \"device state changed after discriminate; refusing luksFormat\"\n', '', 1)"
  mutate "7 intent-file check removed from the open arm" caught \
    "s.replace('    [ -f \"\$INTENT\" ] || fatal open 15', '    : || fatal open 15', 1)"
  mutate "8 intent file never written (crash window becomes unrecoverable)" caught \
    "s.replace('  printf \'%s %s\\\\n\' \"\$DEV\" \"\$(date +%s)\" > \"\$INTENT.tmp\" || fatal format 14 \"cannot write the format intent file\"\n  mv \"\$INTENT.tmp\" \"\$INTENT\" || fatal format 14 \"cannot install the format intent file\"\n', '', 1)"
  envrow "9a the stubs record nothing (0 calls checked)" 1 "WLP_STUB_NOLOG=1"
  envrow "9b a case is deleted from the suite" 1 "WLP_DROP_CASE=ext4"
  mutate "11 chattr +i removed (a plaintext root-disk write becomes possible)" caught \
    "s.replace('  chattr +i \"\$MNT_DIR\" || fatal wire 16 \"chattr +i on the covered mountpoint failed\"\n', '  :\n', 1)"
  mutate "12 a foreign crypttab line is accepted" caught \
    "s.replace('    || fatal wire 16 \"a foreign workspaces crypttab line exists; refusing to coexist\"', '    || :', 1)"
  mutate "13 the mapper-level re-check dropped before the first mkfs" caught \
    "s.replace('  _may_format_fs || fatal format 14 \"the new mapper is not blank; refusing mkfs\"\n', '', 1)"
  mutate "14 the reopen units are no longer enabled" caught \
    "s.replace('systemctl enable workspaces-luks-reopen.service workspaces-luks-reopen.timer', 'true', 1)"
  mutate "10 harmless: a comment-only edit must stay green" survive \
    "s.replace('# THE ONE RULE.', '# THE ONE RULE (reworded).', 1)"

  MUT_ROWS_EXPECTED=15
  [ "$mut_rows" -eq "$MUT_ROWS_EXPECTED" ] || { printf 'FAIL - %s mutation rows ran, expected %s\n' "$mut_rows" "$MUT_ROWS_EXPECTED"; exit 1; }
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
# Anti-vacuity floor (EXACT: 107 inner assertions + 15 mutation rows; raise it with every added check). The threshold sits on the line directly above its `if`.
_wlp_floor="${WLP_MUTANT:+0}"
MIN_ASSERTIONS=$((107 + ${_wlp_floor:-15}))
if [ "$pass" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL - only %s assertions passed (floor %s) — a block stopped running\n' "$pass" "$MIN_ASSERTIONS"; exit 1
fi
[ "$fail" -eq 0 ] || { printf 'failed: %s\n' "${FAILED[@]}"; exit 1; }
printf 'all assertions passed\n'
exit 0
