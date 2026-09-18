#!/usr/bin/env bash
#
# REAL-DEVICE evidence for the #7695 LUKS apparatus on the inngest Redis AOF store.
#
# Sibling of inngest-redis-luks.test.sh, which carries the STRUCTURAL tier and runs everywhere.
# This file is the behavioural half: it builds a real loopback device, runs the REAL extracted
# cloud-init LUKS stage against it, and drives all five blkid arms plus a SECOND SIMULATED BOOT
# through the REAL reopen script. Precedent: workspaces-luks-loopback.test.sh.
#
# IT LIVES IN ITS OWN FILE BECAUSE IT NEEDS ROOT. It is invoked as `sudo bash` inside a multi-line
# `run: |` block in infra-validation.yml, which makes it invisible to run-registered-suites.sh's
# single-line derivation — and it must STAY invisible: it exits 2 unprivileged, so deriving it
# would turn a mandated ship gate permanently RED for any operator without passwordless sudo.
# That is the same trade-off workspaces-luks-loopback.test.sh records, tracked in #7076, and it is
# why the structural arms are in the sibling rather than here.
#
# NO SILENT SKIP. If losetup/cryptsetup/mkfs.ext4/mount are unavailable, or the run lacks the
# privileges to use them, this suite exits NON-ZERO with the literal token LOOPBACK_UNAVAILABLE.
# A conditional self-skip is indistinguishable from a suite that greened wrongly.
#
# WHAT THE HARNESS REBINDS, AND WHAT IT DOES NOT. The stage is extracted VERBATIM, rendered with
# Terraform's two real escapes and nothing else, and then these ENVIRONMENT CONSTANTS are rebound:
# the by-id PREFIX (onto a per-arm directory of real symlinks to loop devices), the two volume ids,
# the mount point, the fstab path, the env file, the detail log, and the phone-home binary. Each
# substitution asserts it actually landed. Nothing in the DECISION path is touched — the pointer
# resolution, the blkid probes, the arms, the rc checks, the traps, the fstab rewrite and the
# positive controls all run as written against real dm-crypt and real sysfs. The one exception is
# declared at run_arm: the wait bound defaults to 2 rather than 30, and the STRUCTURAL sibling
# separately pins that the SOURCE bound is 30 — a harness that shortened the bound without that pin
# would be testing a budget it had itself invented.
#
# Harness conventions (this repo's own post-mortems — load-bearing):
#   - NEVER pipe into an assertion predicate. Under `set -o pipefail` an early `grep -q` match
#     SIGPIPEs the producer (141) and a NEGATIVE assertion then fails OPEN.
#   - Every setup command is rc-checked. A harness that fails to SET UP must ABORT, never continue
#     into a confident wrong verdict about the SUT.
#   - mktemp for every path; the dm name is fixed by the SUT, so a concurrent run is REFUSED
#     rather than raced.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init-inngest.yml"
REDIS_BOOTSTRAP="$SCRIPT_DIR/inngest-redis-bootstrap.sh"

pass=0
fail=0
executed=0
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1"; }

# INSTRUMENT SELF-TEST — drive both counters once each and refuse to continue unless both moved.
_p0=$pass; _f0=$fail
ok "instrument self-test (expected)" >/dev/null
no "instrument self-test (expected)" >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ]; then
  echo "FATAL: instrument self-test did not move both counters" >&2; exit 2
fi
pass=$_p0; fail=$_f0; executed=0

unavailable() {
  echo "LOOPBACK_UNAVAILABLE: $*" >&2
  echo "inngest-redis-luks-loopback: LOOPBACK_UNAVAILABLE — real-device evidence was NOT collected." >&2
  echo "This is a FAILURE, not a skip: run as root on a host with losetup + cryptsetup +" >&2
  echo "mkfs.ext4 + a dm-crypt-capable kernel (GitHub-hosted ubuntu runners qualify, via sudo)." >&2
  exit 2
}

for f in "$CLOUD_INIT" "$REDIS_BOOTSTRAP"; do
  [ -f "$f" ] || unavailable "required file not found: $f"
done

# The canonical P1b guard (#7810): the one shape plugins/soleur/test/lib/fixture-scan.py accepts as
# proof that a write's operand is absolute. Duplicated per file by the repo's own convention.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture path is EMPTY; a redirect would truncate a file in %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture path %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture path %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture path resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture path %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

# ═══ TIER 2 — behavioural, on a real loopback device ═════════════════════════════

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    exec sudo -n bash "${BASH_SOURCE[0]}" "$@"
  fi
  unavailable "not running as root and passwordless sudo is unavailable"
fi
# mkswap is in this list because `new_loop swap` calls it (the ARM4 unhandled-signature
# fixture); it was absent, so a host without it produced `unavailable` from the middle of the run
# instead of from the preflight, where an infra gap belongs.
for b in losetup cryptsetup mkfs.ext4 mkswap mount umount findmnt mountpoint truncate; do
  command -v "$b" >/dev/null 2>&1 || unavailable "required binary '$b' not found on PATH"
done
for b in /usr/sbin/blkid /usr/sbin/blockdev; do
  [ -x "$b" ] || unavailable "required binary '$b' not found (the stage calls it by ABSOLUTE path)"
done

export TMPDIR="${TMPDIR:-/var/tmp}"
TMPROOT="$(mktemp -d -t inngest-luks.XXXXXXXX)" || unavailable "mktemp -d failed"
CLEAN_MOUNTS=(); CLEAN_MAPPERS=(); CLEAN_LOOPS=()
teardown() {
  local i
  for ((i = ${#CLEAN_MOUNTS[@]} - 1; i >= 0; i--)); do
    mountpoint -q "${CLEAN_MOUNTS[$i]}" 2>/dev/null && { umount "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1 || umount -l "${CLEAN_MOUNTS[$i]}" >/dev/null 2>&1; }
  done
  for ((i = ${#CLEAN_MAPPERS[@]} - 1; i >= 0; i--)); do
    cryptsetup status "${CLEAN_MAPPERS[$i]}" >/dev/null 2>&1 && cryptsetup close "${CLEAN_MAPPERS[$i]}" >/dev/null 2>&1
  done
  for ((i = ${#CLEAN_LOOPS[@]} - 1; i >= 0; i--)); do losetup -d "${CLEAN_LOOPS[$i]}" >/dev/null 2>&1; done
  rm -rf "$TMPROOT" >/dev/null 2>&1
  return 0
}
trap teardown EXIT

# The mapper NAMES are fixed in the SUT (`inngest-redis`, and since #6894 `inngest-redis-staging`),
# so a concurrent run on the same box would collide. Refuse rather than race — a suite that silently
# reuses another run's mapper is reporting on a device it did not build.
for _dm in inngest-redis inngest-redis-staging; do
  if cryptsetup status "$_dm" >/dev/null 2>&1; then
    unavailable "device-mapper name '$_dm' is already in use (another run, or a real host)"
  fi
  CLEAN_MAPPERS+=("$_dm")
done

# ── Extract + render the REAL stage ─────────────────────────────────────────────
# Terraform's template unescape is EXACTLY two transforms — `$${` -> `${` and `%%{` -> `%{` — and
# nothing else; a doubled dollar not followed by a brace stays doubled. This render performs those
# two and no third (#6894: the BOOT2 render below used a global doubled-dollar-to-dollar sed, so it
# graded a reopen script that was never delivered while the delivered one failed to parse). The
# template variables are substituted with fixed ids, and the by-id PREFIX is rebound to a per-arm
# directory of REAL symlinks onto loop devices — the same alias-to-device indirection production
# mounts through, where the previous revision rebound the device path to the loop device directly.
render_stage() {
  local expect="$1" byid="$2" mnt="$3" fstab="$4" detail="$5" phone="$6" waitbound="${7:-30}" out="$8"
  # P1b relative-operand rule (#7810): the `> "$out"` below TRUNCATES whatever the 8th positional
  # names, and this function cannot see its root. Callers pass "$TMPROOT/...", but that is a fact
  # about the callers; a bare filename would truncate a file in the CWD instead.
  assert_fixture_dir "$out"
  awk '/doppler run --project soleur-inngest --config prd -- bash -s <<.LUKSEOF.$/{f=1;next} /^    LUKSEOF$/{f=0} f' "$CLOUD_INIT" \
    | sed -e 's/\$\${/${/g' -e 's/%%{/%{/g' \
          -e "s|\${inngest_expect_luks}|${expect}|g" \
          -e "s|\${inngest_volume_id}|${PLAIN_ID}|g" \
          -e "s|\${inngest_luks_volume_id}|${LUKS_ID}|g" \
          -e "s|^    BYID=/dev/disk/by-id/scsi-0HC_Volume_\$|    BYID=${byid}/scsi-0HC_Volume_|" \
          -e "s|/mnt/data|${mnt}|g" \
          -e "s|/etc/fstab|${fstab}|g" \
          -e "s|/etc/default/inngest-luks-volumes|${TMPROOT}/inngest-luks-volumes.env|g" \
          -e "s|/etc/default/inngest-luks|${TMPROOT}/inngest-luks.env|g" \
          -e "s|/run/inngest-luks-stage.log|${detail}|g" \
          -e "s|/usr/local/bin/inngest-boot-phone-home.sh|${phone}|g" \
          -e "s|\\[ \"\\\$_i\" -lt 30 \\]|[ \"\$_i\" -lt ${waitbound} ]|" \
    > "$out"   # operand guarded by assert_fixture_dir above (P1b, #7810)
  # EVERY substitution is asserted. A sed that matched nothing exits 0, so an un-rendered
  # placeholder would otherwise sail through and the case would measure the wrong device.
  local bad=""
  grep -qF 'inngest_volume_id' "$out" && bad="${bad} volume_id"
  grep -qF 'inngest_luks_volume_id' "$out" && bad="${bad} luks_volume_id"
  grep -qF 'inngest_expect_luks' "$out" && bad="${bad} expect_luks"
  grep -qF '$${' "$out" && bad="${bad} tf-escape"
  grep -qF "BYID=${byid}/scsi-0HC_Volume_" "$out" || bad="${bad} byid-rebind"
  grep -qF '/dev/disk/by-id/' "$out" && bad="${bad} byid-still-real"
  grep -qF "${mnt}" "$out" || bad="${bad} mount-rebind"
  # This runs as ROOT on the CI runner: a surviving /etc/default path would write the runner's own.
  grep -qF '/etc/default/' "$out" && bad="${bad} etc-default-still-real"
  grep -qF -- "-lt ${waitbound} ]" "$out" || bad="${bad} waitbound-rebind"
  [ -z "$bad" ] || unavailable "stage render left unsubstituted tokens or missed a rebind:${bad}"
}

PHONE="$TMPROOT/phone-home.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/phone.log"\n' "$TMPROOT" > "$PHONE"
chmod 0755 "$PHONE"
# `logger` may be absent in a container; stub it on PATH so the stage's emitters do not turn a
# missing syslog client into a case failure. It is stubbed to a RECORDER, not a no-op, so the
# emitted markers remain assertable.
mkdir -p "$TMPROOT/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/logger.log"\nexit 0\n' "$TMPROOT" > "$TMPROOT/bin/logger"
chmod 0755 "$TMPROOT/bin/logger"
export PATH="$TMPROOT/bin:$PATH"

KEY="synthesized-inngest-luks-test-passphrase-$$"
# The two volume ids the template would supply. Nine digits, like every hcloud id in-repo.
PLAIN_ID=111111111
LUKS_ID=222222222

# new_loop <tag> [prep] — backing file -> loop device. prep: ext4 | luks | luks-ext4 | raw | swap
new_loop() {
  local tag="$1" prep="${2:-raw}" backing loop
  backing="$TMPROOT/backing-${tag}.img"
  truncate -s 96M "$backing" || unavailable "truncate failed for $tag"
  loop="$(losetup --find --show "$backing")" || unavailable "losetup failed for $tag"
  CLEAN_LOOPS+=("$loop")
  case "$prep" in
    ext4) mkfs.ext4 -q "$loop" || unavailable "mkfs.ext4 failed for $tag" ;;
    luks) printf '%s' "$KEY" | cryptsetup luksFormat --batch-mode --type luks2 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --key-file - "$loop" || unavailable "luksFormat failed for $tag" ;;
    swap) mkswap -q "$loop" >/dev/null 2>&1 || unavailable "mkswap failed for $tag" ;;
    raw)  : ;;
  esac
  printf '%s' "$loop"
}

# arm_reset — unmount this arm's two mounts and close both SUT mapper names, so the next arm starts
# from a known device state. Both names are fixed in the SUT, so they are closed by name.
arm_reset() {
  [ -n "${ARM_MNT:-}" ] && { umount "${ARM_MNT}-luks" >/dev/null 2>&1; umount "$ARM_MNT" >/dev/null 2>&1; }
  cryptsetup close inngest-redis-staging >/dev/null 2>&1
  cryptsetup close inngest-redis >/dev/null 2>&1
  return 0
}

# run_arm <name> <expect_luks> <plain-loop|""> <want_rc> [waitbound] [staging-loop|""] [pointer|""]
# Runs the rendered stage with INNGEST_REDIS_LUKS_KEY (and the pointer) in the environment, as
# `doppler run` would supply them. An EMPTY loop argument means that volume is NOT ATTACHED: its
# by-id alias is simply never created, which is the production shape of an absent volume.
# Sets ARM_MNT / ARM_RC / ARM_DETAIL / ARM_FSTAB / ARM_BYID / ARM_LOG for the caller's assertions.
#
# THE WAIT BOUND DEFAULTS TO 2, not 30. Since #6894 the stage waits for the ADDITIVE volume on every
# pre-cutover boot, so every arm without a staging loop would otherwise cost the full 30s. A present
# device returns from the wait immediately, so the lower bound changes nothing for the arms that
# exercise a present device; T1.6 in the structural sibling pins that the SOURCE bound is 30, so
# this is a declared harness knob rather than a budget the suite invented.
run_arm() {
  local name="$1" expect="$2" plain="$3" want="$4" wb="${5:-2}" staging="${6:-}" pointer="${7:-}"
  # THE LABEL IS NOT A PATH. Every arm name here is a human sentence — spaces, and in one case a
  # slash ("ARM1 ext4/expect_luks=false mounts as-is"). That directory becomes ARM_MNT, which
  # render_stage substitutes into the SUT for the UNQUOTED literal `/mnt/data`, so the rendered
  # stage died at word-splitting with rc 127 before its trap was even armed — all six arms, and
  # three negative arms ("nothing was mounted", "the device was left untouched") reporting green
  # because the stage never ran. Take the leading tag only, and refuse if it is still not a safe
  # path component rather than discovering it as six rc-127s.
  local tag="${name%% *}"
  case "$tag" in
    ''|*[!A-Za-z0-9_-]*) unavailable "arm tag '$tag' is not a safe path component (derived from '$name')" ;;
  esac
  local d="$TMPROOT/arm-$tag"
  mkdir -p "$d/mnt" "$d/byid" || unavailable "mkdir failed for $name"
  ARM_MNT="$d/mnt"; ARM_DETAIL="$d/detail.log"; ARM_FSTAB="$d/fstab"; ARM_BYID="$d/byid"; ARM_LOG="$d/logger.log"
  : > "$ARM_FSTAB" || unavailable "fstab seed failed for $name"
  if [ -n "$plain" ]; then ln -s "$plain" "$ARM_BYID/scsi-0HC_Volume_${PLAIN_ID}" || unavailable "by-id link failed for $name"; fi
  if [ -n "$staging" ]; then ln -s "$staging" "$ARM_BYID/scsi-0HC_Volume_${LUKS_ID}" || unavailable "staging by-id link failed for $name"; fi
  : > "$TMPROOT/logger.log"; : > "$TMPROOT/phone.log"
  render_stage "$expect" "$ARM_BYID" "$ARM_MNT" "$ARM_FSTAB" "$ARM_DETAIL" "$PHONE" "$wb" "$d/stage.sh"
  ARM_RC=0
  INNGEST_REDIS_LUKS_KEY="$KEY" INNGEST_LUKS_ACTIVE_VOLUME_ID="$pointer" bash "$d/stage.sh" > "$d/out.log" 2>&1 || ARM_RC=$?
  cp "$TMPROOT/logger.log" "$ARM_LOG" 2>/dev/null || : > "$ARM_LOG"
  CLEAN_MOUNTS+=("$ARM_MNT" "${ARM_MNT}-luks")
  if [ "$ARM_RC" -eq "$want" ]; then ok "$name (rc=$ARM_RC as designed)"; else no "$name expected rc=$want, got rc=$ARM_RC"; sed -n '1,20p' "$d/out.log" >&2; fi
}

# backing_of <mapper-name> — the kernel name of the mapper's single backing device, from sysfs.
backing_of() {
  local dm; dm="$(basename "$(readlink -f "/dev/mapper/$1" 2>/dev/null)" 2>/dev/null)" || dm=""
  ls "/sys/class/block/$dm/slaves" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# ── ARM 1: ext4, expect_luks=false — the PRE-RECUT steady state ─────────────────
# This is the first boot under the new stage on the live host. A three-arm mirror of git-data
# (which owns a born-raw volume) would have made this boot FATAL and taken the host dark on merge.
L_EXT4="$(new_loop ext4 ext4)"
run_arm "ARM1 ext4/expect_luks=false mounts as-is" false "$L_EXT4" 0
if mountpoint -q "$ARM_MNT"; then ok "ARM1 the plaintext volume is mounted"; else no "ARM1 $ARM_MNT is not a mountpoint"; fi
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "$L_EXT4" ]; then ok "ARM1 mounted from the DEVICE, not the root disk"; else no "ARM1 mounted from the wrong source"; fi
if grep -qF 'nofail' "$ARM_FSTAB"; then ok "ARM1 the fstab line retains nofail"; else no "ARM1 fstab line lost nofail"; fi
umount "$ARM_MNT" >/dev/null 2>&1

# ── ARM 1b: ext4, expect_luks=TRUE — the post-recut refusal ─────────────────────
# Once the recut has run, an ext4 signature means it silently did not take. Mounting would put the
# AOF back on plaintext while the ledger, the ADR and the cloud-init all claim encryption.
run_arm "ARM1b ext4/expect_luks=true REFUSES" true "$L_EXT4" 1
if ! mountpoint -q "$ARM_MNT"; then ok "ARM1b nothing was mounted on the refusal path"; else no "ARM1b the refusal still mounted the plaintext device"; fi
if grep -qF 'the recut did not take' "$ARM_DETAIL"; then ok "ARM1b the refusal names the cause"; else no "ARM1b the detail log does not explain the refusal"; fi

# ── ARM 3: empty device — the ONLY arm that may write a header ──────────────────
L_RAW="$(new_loop raw raw)"
run_arm "ARM3 empty device luksFormats, mkfs, mounts" false "$L_RAW" 0
if [ "$(/usr/sbin/blkid -o value -s TYPE "$L_RAW" 2>/dev/null)" = "crypto_LUKS" ]; then ok "ARM3 the device now carries a LUKS2 header"; else no "ARM3 the device was not luksFormatted"; fi
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "/dev/mapper/inngest-redis" ]; then ok "ARM3 mounted from the MAPPER, not the raw device"; else no "ARM3 not mounted from /dev/mapper/inngest-redis"; fi
# Bytes must land on the mapper. This is the property the 2026-07-19 workspaces incident disproved
# for its sibling: everything downstream is a pure function of the STRING "/mnt/data" unless
# something anchors it to a block device.
printf 'aof-canary\n' > "$ARM_MNT/canary" || no "ARM3 could not write to the mounted store"
sync
ARM3_MNT="$ARM_MNT"

# ── SECOND SIMULATED BOOT — the reopen unit's whole reason for existing ─────────
# cloud-init runcmd is FIRST-BOOT-ONLY, so the stage above opens the mapper exactly once in the
# life of the host. Boot 2 has no mapper: the nofail fstab line skips silently and Redis writes
# its AOF to the ephemeral root disk while every artifact claims LUKS at rest.
umount "$ARM3_MNT" >/dev/null 2>&1
cryptsetup close inngest-redis >/dev/null 2>&1
if [ ! -e /dev/mapper/inngest-redis ]; then ok "BOOT2 precondition: the mapper is closed (a fresh boot)"; else no "BOOT2 could not close the mapper — the case below would be vacuous"; fi

# render_reopen <byid-dir> <expect> <out> — the reopen script, rendered the way Terraform renders it.
# THE PREVIOUS RENDER WAS THE DEFECT'S HIDING PLACE. It applied a global doubled-dollar-to-dollar
# sed, so it graded a script that Terraform never produces; the script Terraform DID produce failed
# with `syntax error near unexpected token` on the live host on every boot (#6894). This render
# applies only Terraform's two real escapes, and the arm below requires the result to PARSE.
render_reopen() {
  local byid="$1" expect="$2" out="$3"
  assert_fixture_dir "$out"
  awk '/^  - path: \/usr\/local\/bin\/inngest-luks-open\.sh$/{f=1;next} f&&/^    content: \|$/{c=1;next} c&&/^    owner:/{exit} c' "$CLOUD_INIT" \
    | sed -e 's/^      //' -e 's/\$\${/${/g' -e 's/%%{/%{/g' \
          -e "s|\${inngest_expect_luks}|${expect}|g" \
          -e "s|\${inngest_volume_id}|${PLAIN_ID}|g" -e "s|\${inngest_luks_volume_id}|${LUKS_ID}|g" \
          -e "s|^BYID=/dev/disk/by-id/scsi-0HC_Volume_\$|BYID=${byid}/scsi-0HC_Volume_|" \
          -e "s|\\[ \"\\\$_i\" -lt 30 \\]|[ \"\$_i\" -lt 2 ]|" \
    > "$out"   # operand guarded by assert_fixture_dir above (P1b, #7810)
}
REOPEN="$TMPROOT/inngest-luks-open.sh"
B2_BYID="$TMPROOT/b2-byid"; mkdir -p "$B2_BYID"
ln -sf "$L_RAW" "$B2_BYID/scsi-0HC_Volume_${PLAIN_ID}"
render_reopen "$B2_BYID" true "$REOPEN"
if [ -s "$REOPEN" ] && ! grep -qE 'inngest_(luks_)?volume_id|inngest_expect_luks|/dev/disk/by-id/' "$REOPEN" && grep -qF "BYID=${B2_BYID}/scsi-0HC_Volume_" "$REOPEN"; then
  ok "BOOT2 the reopen script extracts and renders (Terraform's escapes only, by-id rebound)"
else
  no "BOOT2 could not extract/render inngest-luks-open.sh — every assertion below would be vacuous"
fi
if bash -n "$REOPEN" 2>/dev/null; then ok "BOOT2 the reopen script PARSES as Terraform renders it (the #7695 script did not)"; else no "BOOT2 the reopen script does not parse as delivered: $(bash -n "$REOPEN" 2>&1 | head -1)"; fi

# THE CREDENTIAL IS THE POINT. The unit's EnvironmentFile is what supplies INNGEST_REDIS_LUKS_KEY;
# it shipped reading a file that carries only the Doppler token, so this script would have exited
# `reopen_key_missing` on every boot >= 2. Run it FIRST with the key absent to prove the failure is
# loud, then with it present to prove the reopen works.
R_RC=0
env -u INNGEST_REDIS_LUKS_KEY bash "$REOPEN" > "$TMPROOT/reopen-nokey.log" 2>&1 || R_RC=$?
# `-ne 0` alone is satisfied by the WRONG refusal: if the device were never luksFormatted the
# reopen exits `reopen_not_luks` first, and the arm would report the credential path healthy while
# measuring a different failure entirely. The logger stub records the token; require it.
# THE TOKEN GOES TO `logger`, NOT TO STDOUT. The reopen script's `emit()` is
# `logger -t inngest-luks-stage "SOLEUR_INNGEST_LUKS_STAGE stage=$1 ..."`, and this suite stubs
# `logger` as a RECORDER on PATH — so the marker lands in logger.log, and the script's own stdout
# carries nothing. Grepping the stdout capture asserted the token was absent from a stream it was
# never written to; measured on the suite's first real run, where the arm failed while the script
# behaved exactly as designed.
if [ "$R_RC" -ne 0 ] && grep -qF 'reopen_key_missing' "$TMPROOT/logger.log"; then
  ok "BOOT2 reopen with NO passphrase fails LOUDLY, naming reopen_key_missing"
else
  no "BOOT2 no-passphrase reopen: rc=$R_RC, reopen_key_missing not in the logger recorder (a different refusal, or none)"
  sed -n '1,15p' "$TMPROOT/reopen-nokey.log" >&2
  tail -5 "$TMPROOT/logger.log" 2>/dev/null >&2 || true
fi

R_RC=0
INNGEST_REDIS_LUKS_KEY="$KEY" bash "$REOPEN" > "$TMPROOT/reopen.log" 2>&1 || R_RC=$?
if [ "$R_RC" -eq 0 ]; then ok "BOOT2 reopen with the staged passphrase succeeds"; else no "BOOT2 reopen failed rc=$R_RC"; sed -n '1,15p' "$TMPROOT/reopen.log" >&2; fi
if [ -e /dev/mapper/inngest-redis ]; then ok "BOOT2 the mapper is open again"; else no "BOOT2 the mapper was not reopened — boot 2 would mount nothing and Redis would write to the root disk"; fi
mkdir -p "$TMPROOT/boot2mnt"
if mount /dev/mapper/inngest-redis "$TMPROOT/boot2mnt" >/dev/null 2>&1; then
  CLEAN_MOUNTS+=("$TMPROOT/boot2mnt")
  ok "BOOT2 the store mounts from the reopened mapper"
  if [ -f "$TMPROOT/boot2mnt/canary" ]; then ok "BOOT2 the data written on boot 1 survived"; else no "BOOT2 the boot-1 canary is missing — the reopen mounted a different store"; fi
  umount "$TMPROOT/boot2mnt" >/dev/null 2>&1
else
  no "BOOT2 could not mount the reopened mapper"
fi

# ── ARM 2: crypto_LUKS — already recut. Open and mount; NEVER format. ───────────
cryptsetup close inngest-redis >/dev/null 2>&1
run_arm "ARM2 crypto_LUKS opens and mounts" true "$L_RAW" 0
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "/dev/mapper/inngest-redis" ]; then ok "ARM2 mounted from the mapper"; else no "ARM2 not mounted from the mapper"; fi

# --- ARM2b — #8017's device resolution against a REAL, KERNEL-BUILT device tree -------------
# Every other data_mount_devid arm in this repo drives a PATH-stubbed lsblk, and a stub answers
# whatever the fixture author imagined lsblk prints. This arm is the only place the resolution
# meets a tree the KERNEL actually built: a real dm-crypt node over a real loopback device, with
# a real /sys topology underneath it. If `lsblk -s` does not walk dm -> backing device the way
# the emitter assumes, this is the arm that says so.
#
# THE PIPELINE IS EXTRACTED FROM THE EMITTER, not retyped. A retyped copy proves that some
# pipeline works, never that the SHIPPED one does -- and drifts the moment the emitter changes.
LB_EMITTER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/inngest-bootstrap.sh"
# EXTRACT BY DELIMITER, NEVER BY THE PROGRAM'S OWN TEXT. The previous form anchored on the awk's
# first rule (`NF{l=$1}`), so it silently stopped matching the moment that rule changed -- which is
# exactly what an extract-from-source arm exists to survive. It was already broken by the time this
# ran in CI: the emitter had moved to a leaf-counting program and the sed still asked for the
# original last-non-empty one. Anchor on the SHELL delimiters instead, which are the stable part.
LB_AWK="$(awk "/[|] awk '''/{f=1; sub(/.*[|] awk '''/, \"\")} f{ if (/''' [|][|] true\)\"/) { sub(/''' [|][|] true\)\".*/, \"\"); print; exit } print }" "$LB_EMITTER")"
if [ -n "$LB_AWK" ] && printf '%s\n' "" | awk "$LB_AWK" >/dev/null 2>&1; then
  ok "ARM2b the base-device awk was EXTRACTED from the emitter and PARSES (this arm cannot drift from it)"
else
  no "ARM2b could not extract a parseable base-device awk from the emitter"
  # HARD STOP, no fallback. The previous revision fell back to a RETYPED copy of the old program
  # (`awk "${LB_AWK:-NF{l=$1} ...}"`), so an extraction failure did not stop the arm -- it quietly
  # re-pointed every assertion below at stale text while the header still claimed the arm "cannot
  # drift from" the emitter. A guard whose failure mode is to test something else and keep going is
  # the vacuity class this whole file exists to close.
  printf '[FATAL] ARM2b cannot proceed: the emitter awk did not extract. Refusing to test a retyped copy.\n' >&2
  exit 1
fi

# What does the kernel actually report for a mapper over a loop device?
LB_SRC="$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)"
# -inso, not -nso: the emitter asks lsblk for ASCII so byte depth tracks logical depth, and an arm
# that drives a DIFFERENT invocation is not exercising the shipped path.
LB_BASE="$(timeout 5 lsblk -inso NAME "$LB_SRC" 2>/dev/null | awk "$LB_AWK")"
LB_WANT="$(basename "$L_RAW")"
if [ "$LB_BASE" = "$LB_WANT" ]; then
  ok "ARM2b lsblk -s walks the REAL mapper to its REAL backing device ($LB_SRC -> $LB_BASE)"
else
  no "ARM2b the real device tree did NOT resolve to the backing device (got '$LB_BASE', want '$LB_WANT') — the emitter's assumption is false on a kernel-built tree"
fi

# ...and the reverse map, against real symlinks resolved by the real readlink. The Hetzner
# namespace is synthesized over the loop device because no HC_Volume exists on a CI box, but
# every link, target and resolution below is genuine.
LB_BYID="$TMPROOT/byid"; mkdir -p "$LB_BYID"
ln -sf "$L_RAW" "$LB_BYID/scsi-0HC_Volume_106261946"
lb_devid() {  # lb_devid <byid-dir> <base> -> the emitter's reverse map, same shape
  _h=0; _m=""
  for _a in "$1"/scsi-0HC_Volume_*; do
    [ -e "$_a" ] || continue
    _t="$(readlink -f "$_a" 2>/dev/null || true)"; [ -n "$_t" ] || continue
    case "$_t" in */"$2") _h=$((_h+1)); _m="${_a##*/}" ;; esac
  done
  if [ "$_h" -eq 0 ]; then printf '__NOMATCH__'; elif [ "$_h" -gt 1 ]; then printf '__AMBIGUOUS__'; else printf '%s' "$_m"; fi
}
LB_DEVID="$(lb_devid "$LB_BYID" "$LB_BASE")"
if [ "$LB_DEVID" = "scsi-0HC_Volume_106261946" ]; then
  ok "ARM2b the reverse map resolves a REAL symlink to the volume alias (the value G14 authorizes on)"
else
  no "ARM2b the reverse map failed against real symlinks (got '$LB_DEVID')"
fi
# A second alias on the same real device must be AMBIGUOUS, not an arbitrary pick.
ln -sf "$L_RAW" "$LB_BYID/scsi-0HC_Volume_999999999"
if [ "$(lb_devid "$LB_BYID" "$LB_BASE")" = "__AMBIGUOUS__" ]; then
  ok "ARM2b two REAL aliases on one device => __AMBIGUOUS__, never an arbitrary pick"
else
  no "ARM2b a genuinely multi-valued reverse map did not report __AMBIGUOUS__"
fi
rm -f "$LB_BYID/scsi-0HC_Volume_999999999"
# A dangling alias must be SKIPPED, not matched. This is production semantics -- an alias pointing
# at nothing is a device that is gone -- and it is the exact fixture defect that made an earlier
# stub-based arm silently report __NOMATCH__ while claiming to test a healthy host.
ln -sf "$TMPROOT/no-such-device" "$LB_BYID/scsi-0HC_Volume_111111111"
if [ "$(lb_devid "$LB_BYID" "$LB_BASE")" = "scsi-0HC_Volume_106261946" ]; then
  ok "ARM2b a DANGLING alias is skipped rather than matched (real -e semantics)"
else
  no "ARM2b a dangling alias perturbed the reverse map"
fi
rm -f "$LB_BYID/scsi-0HC_Volume_111111111"
if [ -f "$ARM_MNT/canary" ]; then ok "ARM2 the existing store was OPENED, not reformatted"; else no "ARM2 the canary is gone — the crypto_LUKS arm reformatted an existing store"; fi
umount "$ARM_MNT" >/dev/null 2>&1
cryptsetup close inngest-redis >/dev/null 2>&1

# ── ARM 4: an unhandled signature — refuse ──────────────────────────────────────
L_SWAP="$(new_loop swap swap)"
run_arm "ARM4 unhandled signature REFUSES" false "$L_SWAP" 1
if grep -qF 'unhandled signature' "$ARM_DETAIL"; then ok "ARM4 the refusal names the unhandled type"; else no "ARM4 the detail log does not name the unhandled signature"; fi
if [ "$(/usr/sbin/blkid -o value -s TYPE "$L_SWAP" 2>/dev/null)" = "swap" ]; then ok "ARM4 the device was left untouched"; else no "ARM4 the refusal path wrote to a device whose contents were unknown"; fi

# ── ARM 0: the device is absent after the bounded wait ──────────────────────────
# blkid on an absent path returns rc 2, which the accept-0-or-2 policy would otherwise route
# straight into the luksFormat arm. The wait bound is lowered to 2 for this case ONLY; T1.6 pins
# that the SOURCE bound is 30, so this is a declared harness knob rather than an invented budget.
run_arm "ARM0 absent device REFUSES (never formats a non-device)" false "" 1 2
if grep -qF 'is not a block device' "$ARM_DETAIL"; then ok "ARM0 the refusal names the absent device"; else no "ARM0 the detail log does not name the absent device"; fi
if [ ! -e "$ARM_BYID/scsi-0HC_Volume_${PLAIN_ID}" ]; then ok "ARM0 nothing was created at the absent alias"; else no "ARM0 the stage created something at an alias that was not a block device"; fi

# ═══ #6894 — the two-device resolver, against real dm-crypt and real sysfs ═══════════════════
arm_reset

# fstab_count <fstab> <mountpoint> — lines naming exactly that mountpoint in field 2.
fstab_count() { awk -v mp="$2" '$1 !~ /^#/ && $2 == mp' "$1" | wc -l; }

# ── REG: a plaintext-only boot is byte-identical to the stage before #6894 (Guard 4, row b) ─────
# The resolver edits a LIVE state machine rather than adding beside one, so the one world the
# running host is in today must come out exactly as it did: same fstab bytes, same env bytes, no
# mapper, and the additive volume's absence reported rather than swallowed.
L_REG="$(new_loop reg ext4)"
run_arm "REG plaintext-only boot (pointer absent, one volume attached)" false "$L_REG" 0
if [ "$(cat "$ARM_FSTAB")" = "$ARM_BYID/scsi-0HC_Volume_${PLAIN_ID} $ARM_MNT ext4 defaults,nofail 0 2" ]; then ok "REG fstab is EXACTLY the one pre-#6894 line"; else no "REG fstab differs from the pre-#6894 shape: $(tr '\n' '|' < "$ARM_FSTAB")"; fi
if [ "$(cat "$TMPROOT/inngest-luks.env")" = "INNGEST_REDIS_LUKS_KEY=$KEY" ]; then ok "REG the staged env file is EXACTLY the key line (no pointer written)"; else no "REG the staged env file carries more than the key"; fi
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "$L_REG" ]; then ok "REG /mnt/data is the plaintext device"; else no "REG /mnt/data source is '$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)'"; fi
if [ ! -e /dev/mapper/inngest-redis ] && [ ! -e /dev/mapper/inngest-redis-staging ]; then ok "REG no mapper was opened"; else no "REG a mapper was opened on a plaintext-only boot"; fi
if grep -qF 'stage=staging_absent' "$ARM_LOG"; then ok "REG the absent additive volume is reported, not silently skipped"; else no "REG no staging_absent marker"; fi
arm_reset

# ── ST1: pre-cutover with a RAW additive volume — staged, never canonical ─────────────────────
L_P="$(new_loop stp ext4)"
L_S="$(new_loop sts raw)"
run_arm "ST1 a raw additive volume is staged under the non-canonical mapper" false "$L_P" 0 2 "$L_S"
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "$L_P" ]; then ok "ST1 /mnt/data is STILL the plaintext device"; else no "ST1 /mnt/data moved to '$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)'"; fi
if [ "$(findmnt -no SOURCE "${ARM_MNT}-luks" 2>/dev/null)" = "/dev/mapper/inngest-redis-staging" ]; then ok "ST1 /mnt/data-luks is mounted from the staging mapper"; else no "ST1 the staging mount source is '$(findmnt -no SOURCE "${ARM_MNT}-luks" 2>/dev/null)'"; fi
if [ "$(backing_of inngest-redis-staging)" = "$(basename "$L_S")" ]; then ok "ST1 the staging mapper is backed by the ADDITIVE volume (real sysfs slaves/)"; else no "ST1 the staging mapper is backed by '$(backing_of inngest-redis-staging)', not $(basename "$L_S")"; fi
if [ ! -e /dev/mapper/inngest-redis ]; then ok "ST1 the CANONICAL mapper was never opened (the Redis guard stays in its pre-recut state)"; else no "ST1 the canonical mapper was opened pre-cutover — the Redis guard would refuse the plaintext store"; fi
if [ "$(/usr/sbin/blkid -p -o value -s TYPE "$L_S" 2>/dev/null)" = "crypto_LUKS" ]; then ok "ST1 the additive volume now carries a LUKS2 header"; else no "ST1 the additive volume was not luksFormatted"; fi
if [ "$(fstab_count "$ARM_FSTAB" "$ARM_MNT")" -eq 1 ] && [ "$(fstab_count "$ARM_FSTAB" "${ARM_MNT}-luks")" -eq 1 ]; then ok "ST1 fstab carries exactly one line per mountpoint"; else no "ST1 fstab lines: /mnt/data=$(fstab_count "$ARM_FSTAB" "$ARM_MNT") /mnt/data-luks=$(fstab_count "$ARM_FSTAB" "${ARM_MNT}-luks")"; fi
printf 'staged-canary\n' > "${ARM_MNT}-luks/canary" || no "ST1 could not write to the staged volume"
sync
arm_reset

# ── ST2: re-entry — an already-staged volume is opened and mounted, never recreated ──────────
run_arm "ST2 re-entry on an already-staged volume" false "$L_P" 0 2 "$L_S"
if [ -f "${ARM_MNT}-luks/canary" ]; then ok "ST2 the staged data survived re-entry (no luksFormat, no mkfs)"; else no "ST2 the staged canary is gone — re-entry reformatted the additive volume"; fi
if ! grep -qE 'stage=staging_(luks_format|mkfs) ' "$ARM_LOG"; then ok "ST2 no format or mkfs marker was emitted on re-entry"; else no "ST2 re-entry emitted a format/mkfs marker"; fi
arm_reset

# ── ST3: the additive volume carries a FOREIGN signature — refused and left untouched (Guard 1) ─
L_F="$(new_loop stf ext4)"
run_arm "ST3 an additive volume carrying ext4 is REFUSED" false "$L_P" 1 2 "$L_F"
if [ "$(/usr/sbin/blkid -p -o value -s TYPE "$L_F" 2>/dev/null)" = "ext4" ]; then ok "ST3 the refused device was left untouched"; else no "ST3 the refusal path wrote to a device carrying data"; fi
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "$L_P" ]; then ok "ST3 /mnt/data was mounted and verified BEFORE the staging refusal"; else no "ST3 the staging refusal left /mnt/data unmounted"; fi
if grep -qE 'inngest-luks-FAILED stage=staging_' "$TMPROOT/phone.log"; then ok "ST3 the refusal phones home under its own staging stage"; else no "ST3 phone-home: $(tr '\n' '|' < "$TMPROOT/phone.log")"; fi
arm_reset

# ── PTR1: the pointer names the additive volume — it is now the canonical store ───────────────
run_arm "PTR1 a pointer to the additive volume mounts it as the canonical store" false "$L_P" 0 2 "$L_S" "$LUKS_ID"
if [ "$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)" = "/dev/mapper/inngest-redis" ]; then ok "PTR1 /mnt/data is mounted from the CANONICAL mapper"; else no "PTR1 /mnt/data source is '$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)'"; fi
if [ "$(backing_of inngest-redis)" = "$(basename "$L_S")" ]; then ok "PTR1 the canonical mapper is backed by the ADDITIVE volume (real sysfs slaves/)"; else no "PTR1 the canonical mapper is backed by '$(backing_of inngest-redis)'"; fi
if [ -f "$ARM_MNT/canary" ]; then ok "PTR1 the store the pointer names is the one that was staged (its canary is present)"; else no "PTR1 the canonical store is not the staged one"; fi
if [ ! -e /dev/mapper/inngest-redis-staging ]; then ok "PTR1 no staging mapper is opened under a pointer"; else no "PTR1 the staging mapper was opened under a pointer"; fi
if [ "$(/usr/sbin/blkid -p -o value -s TYPE "$L_P" 2>/dev/null)" = "ext4" ] && ! mountpoint -q "${ARM_MNT}-luks"; then ok "PTR1 the plaintext backstop is left attached and untouched"; else no "PTR1 the plaintext backstop was touched"; fi
if grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=${LUKS_ID}" "$TMPROOT/inngest-luks.env"; then ok "PTR1 the pointer is staged for the boot-reopen unit"; else no "PTR1 the pointer was not staged — boot 2 would take the pre-cutover arm"; fi
if [ "$(fstab_count "$ARM_FSTAB" "$ARM_MNT")" -eq 1 ] && grep -qF "/dev/mapper/inngest-redis $ARM_MNT " "$ARM_FSTAB"; then ok "PTR1 fstab carries exactly one /mnt/data line, naming the canonical mapper"; else no "PTR1 fstab: $(tr '\n' '|' < "$ARM_FSTAB")"; fi
arm_reset

# ── PTR2: the pointer names an ABSENT volume — refuse, never fall back (Guard 4, row 2) ──────
run_arm "PTR2 a pointer to an ABSENT additive volume REFUSES" false "$L_P" 1 2 "" "$LUKS_ID"
if ! mountpoint -q "$ARM_MNT"; then ok "PTR2 nothing is mounted — the plaintext volume is NOT used as a fallback"; else no "PTR2 /mnt/data was mounted from '$(findmnt -no SOURCE "$ARM_MNT" 2>/dev/null)' — the silent un-encryption Fork P refuses"; fi
if grep -qF 'is not attached' "$ARM_DETAIL"; then ok "PTR2 the refusal names the missing volume"; else no "PTR2 the detail log does not name the missing volume"; fi
arm_reset

# ── PTR3: the pointer names a device that is NOT LUKS — refuse (Guard 4, row 3) ───────────────
run_arm "PTR3 a pointer to the plaintext ext4 volume REFUSES" false "$L_P" 1 2 "$L_S" "$PLAIN_ID"
if ! mountpoint -q "$ARM_MNT"; then ok "PTR3 nothing is mounted — the pointer cannot certify a plaintext device"; else no "PTR3 a plaintext device was mounted under a pointer"; fi
if grep -qF 'not crypto_LUKS' "$ARM_DETAIL"; then ok "PTR3 the refusal names the failed corroboration"; else no "PTR3 the detail log does not name the corroboration"; fi
arm_reset

# ── PTR4: the pointer names a LUKS volume with an EMPTY filesystem — refuse, never mkfs ────────
L_E="$(new_loop pte luks)"
run_arm "PTR4 a pointer to an EMPTY store REFUSES" false "$L_P" 1 2 "$L_E" "$LUKS_ID"
if grep -qF 'not ext4' "$ARM_DETAIL"; then ok "PTR4 the refusal names the empty store"; else no "PTR4 the detail log does not name the empty store"; fi
arm_reset
printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$L_E" inngest-redis-staging >/dev/null 2>&1 || unavailable "could not open the PTR4 fixture to inspect it"
if [ -z "$(/usr/sbin/blkid -p -o value -s TYPE /dev/mapper/inngest-redis-staging 2>/dev/null)" ]; then ok "PTR4 the empty store was NOT given a filesystem"; else no "PTR4 the refusal path ran mkfs on the store the pointer names"; fi
arm_reset

# ── BOOT2 under a pointer: the reopen unit opens exactly the volume the pointer names ─────────
B3_BYID="$TMPROOT/b3-byid"; mkdir -p "$B3_BYID"
ln -sf "$L_P" "$B3_BYID/scsi-0HC_Volume_${PLAIN_ID}"
ln -sf "$L_S" "$B3_BYID/scsi-0HC_Volume_${LUKS_ID}"
render_reopen "$B3_BYID" false "$TMPROOT/reopen-b3.sh"
R_RC=0
INNGEST_REDIS_LUKS_KEY="$KEY" INNGEST_LUKS_ACTIVE_VOLUME_ID="$LUKS_ID" bash "$TMPROOT/reopen-b3.sh" > "$TMPROOT/reopen-b3.log" 2>&1 || R_RC=$?
if [ "$R_RC" -eq 0 ] && [ "$(backing_of inngest-redis)" = "$(basename "$L_S")" ]; then ok "BOOT2-PTR reboot reopens the ADDITIVE volume as the canonical mapper"; else no "BOOT2-PTR rc=$R_RC canonical backing='$(backing_of inngest-redis)'"; sed -n '1,8p' "$TMPROOT/reopen-b3.log" >&2; fi
if [ ! -e /dev/mapper/inngest-redis-staging ]; then ok "BOOT2-PTR ...and opens nothing else"; else no "BOOT2-PTR the staging mapper was also opened"; fi
mkdir -p "$TMPROOT/b3mnt"
if mount /dev/mapper/inngest-redis "$TMPROOT/b3mnt" >/dev/null 2>&1; then
  CLEAN_MOUNTS+=("$TMPROOT/b3mnt")
  if [ -f "$TMPROOT/b3mnt/canary" ]; then ok "BOOT2-PTR the store survives the reboot"; else no "BOOT2-PTR the reopened store is not the staged one"; fi
  umount "$TMPROOT/b3mnt" >/dev/null 2>&1
else
  no "BOOT2-PTR could not mount the reopened canonical mapper"
fi
arm_reset
rm -f "$B3_BYID/scsi-0HC_Volume_${LUKS_ID}"
R_RC=0
INNGEST_REDIS_LUKS_KEY="$KEY" INNGEST_LUKS_ACTIVE_VOLUME_ID="$LUKS_ID" bash "$TMPROOT/reopen-b3.sh" > "$TMPROOT/reopen-b3b.log" 2>&1 || R_RC=$?
if [ "$R_RC" -ne 0 ] && [ ! -e /dev/mapper/inngest-redis ]; then ok "BOOT2-PTR a pointer to an absent volume REFUSES on reboot too (no fallback)"; else no "BOOT2-PTR absent-volume reboot: rc=$R_RC, canonical mapper present=$([ -e /dev/mapper/inngest-redis ] && echo yes || echo no)"; fi
arm_reset

# ── BOOT2 pre-cutover: a reboot re-opens the staged volume under the staging name only ─────────
ln -sf "$L_S" "$B3_BYID/scsi-0HC_Volume_${LUKS_ID}"
R_RC=0
INNGEST_REDIS_LUKS_KEY="$KEY" INNGEST_LUKS_ACTIVE_VOLUME_ID="" bash "$TMPROOT/reopen-b3.sh" > "$TMPROOT/reopen-b3c.log" 2>&1 || R_RC=$?
if [ "$R_RC" -eq 0 ] && [ "$(backing_of inngest-redis-staging)" = "$(basename "$L_S")" ] && [ ! -e /dev/mapper/inngest-redis ]; then ok "BOOT2-STG a pre-cutover reboot opens the staged volume under the staging name, and nothing canonical"; else no "BOOT2-STG rc=$R_RC staging backing='$(backing_of inngest-redis-staging)' canonical present=$([ -e /dev/mapper/inngest-redis ] && echo yes || echo no)"; sed -n '1,8p' "$TMPROOT/reopen-b3c.log" >&2; fi
arm_reset

# ── The mount guard's two states, behaviourally ─────────────────────────────────
# Extracted from inngest-redis-bootstrap.sh and driven directly. A guard that only ever runs on a
# host is a guard nothing can falsify.
GUARD_SRC="$TMPROOT/mount-guard.src.sh"
awk "/^install -m 0755 \/dev\/stdin \/usr\/local\/bin\/inngest-redis-mount-guard.sh <<'GUARDEOF'\$/{f=1;next} /^GUARDEOF\$/{f=0} f" "$REDIS_BOOTSTRAP" > "$GUARD_SRC"
if [ -s "$GUARD_SRC" ]; then ok "GUARD extracts from inngest-redis-bootstrap.sh"; else no "GUARD could not be extracted — the cases below would be vacuous"; fi
# A POSITIVE CONTROL ON THE EXTRACTION, the same shape as G10's in the dark gate: a range that ran
# to EOF or stopped early is still non-empty, and every negative arm below would pass on it.
if [ "$(grep -cE '^[[:space:]]*(exit 1|exit 0)' "$GUARD_SRC")" -ge 5 ]; then ok "GUARD extraction captured the whole guard (>=5 exit arms)"; else no "GUARD extraction looks truncated — $(grep -cE '^[[:space:]]*exit' "$GUARD_SRC") exit arms"; fi

# render_guard <mapper> <mount> <envfile> <out>
# The guard hardcodes three absolute paths, so driving it as-is can only ever reach the two states
# this host happens to be in. Rebinding them is what makes the other three reachable — including
# BOTH must-ALLOW directions, whose absence let a guard mutated to "refuse whenever the mapper
# exists" pass every arm that existed.
render_guard() {
  sed -e "s|^MAPPER=/dev/mapper/inngest-redis\$|MAPPER=$1|" \
      -e "s|^MOUNT=/mnt/data\$|MOUNT=$2|" \
      -e "s|^ENVFILE=/etc/default/inngest-server\$|ENVFILE=$3|" \
      "$GUARD_SRC" > "$4"
  # Assert the rebinding TOOK. A sed that matched nothing leaves the guard pointed at the real
  # host paths, where every case below reads whatever this machine happens to be.
  if grep -qF "MAPPER=$1" "$4" && grep -qF "MOUNT=$2" "$4" && grep -qF "ENVFILE=$3" "$4"; then
    ok "GUARD render rebound all three paths"
  else
    no "GUARD render did not rebind — the guard still points at the real host paths"
  fi
}

G_MNT="$TMPROOT/g-mnt";   mkdir -p "$G_MNT"
G_ENV="$TMPROOT/g-env"
G_MAPPER_ABSENT="$TMPROOT/g-no-such-mapper"

guard_case() {  # guard_case <label> <want-rc> <mapper> <mount> <envfile>
  local label="$1" want="$2"; shift 2
  local g="$TMPROOT/guard-$$-${RANDOM}.sh"
  render_guard "$1" "$2" "$3" "$g"
  local rc=0; bash "$g" >"$g.log" 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$label (rc=$rc as designed)"; else no "$label expected rc=$want, got rc=$rc"; sed -n '1,5p' "$g.log" >&2; fi
}

# STATE A — no mapper, identity is the WEB project => inert. The positive-identity scoping, driven
# with the file PRESENT and carrying a real other-project value, rather than by its absence.
printf 'DOPPLER_PROJECT=soleur-web-platform\n' > "$G_ENV"
guard_case "GUARD is inert on the web host (positive other-project identity)" 0 "$G_MAPPER_ABSENT" "$G_MNT" "$G_ENV"

# STATE B — no mapper, DEDICATED identity, /mnt/data NOT a mountpoint => refuse. The pre-recut
# failure the guard exists for: cloud-init's mount never happened and the AOF would land on root.
printf 'DOPPLER_PROJECT=soleur-inngest\n' > "$G_ENV"
guard_case "GUARD refuses on the dedicated host when /mnt/data is not a mountpoint" 1 "$G_MAPPER_ABSENT" "$G_MNT" "$G_ENV"

# STATE C — no mapper, DEDICATED identity, /mnt/data IS mounted => ALLOW. THE PRE-RECUT STEADY
# STATE, and a must-PASS direction that had no arm at all: a guard hardened into "always refuse
# without a mapper" would deadlock the very cutover this apparatus exists to enable, and would
# have passed every case that existed.
L_PRE="$(new_loop pre ext4)"
mount "$L_PRE" "$G_MNT" >/dev/null 2>&1 || unavailable "could not mount the pre-recut fixture"
CLEAN_MOUNTS+=("$G_MNT")
guard_case "GUARD ALLOWS the pre-recut steady state (plaintext ext4, mounted)" 0 "$G_MAPPER_ABSENT" "$G_MNT" "$G_ENV"
umount "$G_MNT" >/dev/null 2>&1

# STATE D — an env file that EXISTS but carries no DOPPLER_PROJECT => refuse. This arm exited 0
# before review: `proj=""` fell through to the `|| exit 0` that was written for the web host, so a
# dedicated host whose env file failed to write was waved through by the guard meant to catch it.
: > "$G_ENV"
guard_case "GUARD refuses an env file with no DOPPLER_PROJECT (identity unreadable is not a licence)" 1 "$G_MAPPER_ABSENT" "$G_MNT" "$G_ENV"
printf 'DOPPLER_PROJECT=soleur-inngest\n' > "$G_ENV"

# STATE E — mapper open, /mnt/data mounted FROM IT => ALLOW. The post-recut steady state; the
# second must-PASS direction, and the one that makes the two mapper refusals below meaningful
# rather than "this guard refuses whenever a mapper exists".
printf '%s' "$KEY" | cryptsetup luksOpen --key-file - "$L_RAW" inngest-redis >/dev/null 2>&1 || unavailable "could not reopen the mapper for the guard cases"
mount /dev/mapper/inngest-redis "$G_MNT" >/dev/null 2>&1 || unavailable "could not mount the mapper for the guard cases"
CLEAN_MOUNTS+=("$G_MNT")
guard_case "GUARD ALLOWS the post-recut steady state (mounted from the mapper)" 0 /dev/mapper/inngest-redis "$G_MNT" "$G_ENV"
umount "$G_MNT" >/dev/null 2>&1

# STATE F — mapper open, /mnt/data not a mountpoint => refuse, WITHOUT any identity read. The arm
# that cannot be disarmed by an unreadable env file: point ENVFILE at a path that does not exist
# and it must still refuse.
guard_case "GUARD refuses with the mapper open and /mnt/data unmounted, with NO readable identity" 1 /dev/mapper/inngest-redis "$G_MNT" "$TMPROOT/g-env-absent"

# STATE G — mapper open, /mnt/data mounted from something ELSE => refuse.
mount "$L_PRE" "$G_MNT" >/dev/null 2>&1 || unavailable "could not mount the wrong-source fixture"
CLEAN_MOUNTS+=("$G_MNT")
guard_case "GUARD refuses when /mnt/data is mounted from the WRONG device" 1 /dev/mapper/inngest-redis "$G_MNT" "$G_ENV"
umount "$G_MNT" >/dev/null 2>&1
cryptsetup close inngest-redis >/dev/null 2>&1

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only. A floor that lives in a helper
# is silenced by the same move that silences the arms it guards.
# THE FLOOR IS NOW MEASURED, not projected. The first CI run (the first time this suite ever
# executed — it needs root, which the authoring machine does not have) reported 42 assertions
# against a projected 48. The projection over-counted: it treated a few if/else assertion pairs as
# two sites and assumed every branch of the BOOT2 mount block runs.
#
# 42 is taken as the floor only because the discrepancy is fully accounted for. Four arms DID fail
# on that run, and the rule this comment previously stated — do not lower a floor to match a suite
# that may have lost arms — is why that matters. Each failure was diagnosed and fixed, and none of
# the four fixes adds or removes an assertion:
#
#   ARM1 / ARM2 / ARM3 returned rc 1 while doing their work correctly (device mounted, LUKS header
#     written, canary intact). Cause: the stage's `trap luks_err EXIT` ended in an unconditional
#     `exit 1`, so a SUCCESSFUL stage re-entered the handler and reported itself failed. That is a
#     production defect in cloud-init-inngest.yml, not a test defect, and it is fixed there.
#   BOOT2's no-passphrase arm grepped the script's STDOUT for `reopen_key_missing`. The token is
#     written by `logger`, which this suite stubs as a recorder — so the assertion looked for it in
#     a stream it was never written to. Fixed here.
#
# So the arm COUNT was never in question; four of the 42 were reporting failures. If a later run
# reds on this floor, apply the same discipline: account for the difference before touching it.
#
# 42 -> 85 (#6894), and THIS VALUE IS PROJECTED, NOT YET MEASURED, for the same reason the first one
# was: the authoring machine has no passwordless sudo. The projection counts one execution per
# `if … ok … else no … fi` and one per run_arm, on the success path: +42 in the resolver/staging/
# pointer/BOOT2 arms, +1 for BOOT2's new parse check. It must be confirmed against the first CI run
# and, if it differs, the difference accounted for arm by arm before the literal moves.
if [ "$executed" -lt 85 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 85. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 85)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks-loopback.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
