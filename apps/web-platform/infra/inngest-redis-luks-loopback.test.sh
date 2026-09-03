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
# WHAT THE HARNESS REBINDS, AND WHAT IT DOES NOT. The stage is extracted VERBATIM and then five
# ENVIRONMENT CONSTANTS are rebound: the device path, the mount point, the fstab path, the detail
# log, and the phone-home binary. Each substitution asserts it actually landed. Nothing in the
# DECISION path is touched — the blkid probe, the five arms, the rc checks, the traps and the final
# mountpoint verify all run as written. The one exception is declared at its call site: the
# device-absent arm lowers the 30-second wait bound to 2 so the case costs 2s rather than 30, and
# the STRUCTURAL sibling separately pins that the SOURCE bound is 30 — a harness that shortened the
# bound without that pin would be testing a budget it had itself invented.
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

# The mapper NAME is fixed in the SUT (`inngest-redis`), so a concurrent run on the same box would
# collide. Refuse rather than race — a suite that silently reuses another run's mapper is reporting
# on a device it did not build.
if cryptsetup status inngest-redis >/dev/null 2>&1; then
  unavailable "device-mapper name 'inngest-redis' is already in use (another run, or a real host)"
fi
CLEAN_MAPPERS+=("inngest-redis")

# ── Extract + render the REAL stage ─────────────────────────────────────────────
# `$${` -> `${` is terraform's escape, undone exactly as templatefile() would. The two named
# variables are substituted with the values the call site passes.
render_stage() {
  local expect="$1" dev="$2" mnt="$3" fstab="$4" detail="$5" phone="$6" waitbound="${7:-30}" out="$8"
  awk '/doppler run --project soleur-inngest --config prd -- bash -s <<.LUKSEOF.$/{f=1;next} /^    LUKSEOF$/{f=0} f' "$CLOUD_INIT" \
    | sed -e 's/\$\${/${/g' \
          -e "s|\${inngest_expect_luks}|${expect}|g" \
          -e "s|DEV=\"/dev/disk/by-id/scsi-0HC_Volume_\${inngest_volume_id}\"|DEV=\"${dev}\"|" \
          -e "s|/mnt/data|${mnt}|g" \
          -e "s|/etc/fstab|${fstab}|g" \
          -e "s|/etc/default/inngest-luks|${TMPROOT}/inngest-luks.env|g" \
          -e "s|/run/inngest-luks-stage.log|${detail}|g" \
          -e "s|/usr/local/bin/inngest-boot-phone-home.sh|${phone}|g" \
          -e "s|\\[ \"\\\$_i\" -lt 30 \\]|[ \"\$_i\" -lt ${waitbound} ]|" \
    > "$out"
  # EVERY substitution is asserted. A sed that matched nothing exits 0, so an un-rendered
  # placeholder would otherwise sail through and the case would measure the wrong device.
  local bad=""
  grep -qF 'inngest_volume_id' "$out" && bad="${bad} volume_id"
  grep -qF 'inngest_expect_luks' "$out" && bad="${bad} expect_luks"
  grep -qF '$${' "$out" && bad="${bad} tf-escape"
  grep -qF "DEV=\"${dev}\"" "$out" || bad="${bad} dev-rebind"
  grep -qF "${mnt}" "$out" || bad="${bad} mount-rebind"
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

# new_loop <tag> [prep] — backing file -> loop device. prep: ext4 | luks | raw | swap
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

# run_arm <name> <expect_luks> <loop> <want_rc> [waitbound]
# Runs the rendered stage with INNGEST_REDIS_LUKS_KEY in the environment (the real stage receives
# it from `doppler run`). Sets ARM_MNT / ARM_RC / ARM_DETAIL for the caller's assertions.
run_arm() {
  local name="$1" expect="$2" loop="$3" want="$4" wb="${5:-30}"
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
  mkdir -p "$d/mnt" || unavailable "mkdir failed for $name"
  ARM_MNT="$d/mnt"; ARM_DETAIL="$d/detail.log"; ARM_FSTAB="$d/fstab"
  : > "$ARM_FSTAB" || unavailable "fstab seed failed for $name"
  render_stage "$expect" "$loop" "$ARM_MNT" "$ARM_FSTAB" "$ARM_DETAIL" "$PHONE" "$wb" "$d/stage.sh"
  ARM_RC=0
  INNGEST_REDIS_LUKS_KEY="$KEY" bash "$d/stage.sh" > "$d/out.log" 2>&1 || ARM_RC=$?
  CLEAN_MOUNTS+=("$ARM_MNT")
  if [ "$ARM_RC" -eq "$want" ]; then ok "$name (rc=$ARM_RC as designed)"; else no "$name expected rc=$want, got rc=$ARM_RC"; sed -n '1,20p' "$d/out.log" >&2; fi
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

REOPEN="$TMPROOT/inngest-luks-open.sh"
awk '/^  - path: \/usr\/local\/bin\/inngest-luks-open\.sh$/{f=1;next} f&&/^    content: \|$/{c=1;next} c&&/^    owner:/{exit} c' "$CLOUD_INIT" \
  | sed -e 's/^      //' -e 's/\$\$/$/g' -e "s|\${inngest_expect_luks}|true|g" \
        -e "s|DEV=\"/dev/disk/by-id/scsi-0HC_Volume_\${inngest_volume_id}\"|DEV=\"${L_RAW}\"|" \
  > "$REOPEN"
if [ -s "$REOPEN" ] && ! grep -qF 'inngest_volume_id' "$REOPEN" && grep -qF "DEV=\"${L_RAW}\"" "$REOPEN"; then
  ok "BOOT2 the reopen script extracts and renders"
else
  no "BOOT2 could not extract/render inngest-luks-open.sh — every assertion below would be vacuous"
fi

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
run_arm "ARM0 absent device REFUSES (never formats a non-device)" false "$TMPROOT/not-a-device" 1 2
if grep -qF 'is not a block device' "$ARM_DETAIL"; then ok "ARM0 the refusal names the absent device"; else no "ARM0 the detail log does not name the absent device"; fi
if [ ! -e "$TMPROOT/not-a-device" ]; then ok "ARM0 nothing was created at the absent path"; else no "ARM0 the stage created something at a path that was not a block device"; fi

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
if [ "$executed" -lt 42 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 42. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 42)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks-loopback.test.sh: ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
