#!/usr/bin/env bash
#
# inngest-luks-cutover.sh (#6894) — the on-host blue-green cutover FSM, driven for real.
#
# THE REAL SCRIPT RUNS; ONLY THE BLOCK LAYER IS MODELLED. Every case executes inngest-luks-cutover.sh
# itself under `--fixture-seams`. The copy, the file listing, the per-file checksums and the byte
# count run against REAL directories with real `cp -a`, `find` and `sha256sum`, so T2's byte-equality
# is measured, not asserted by a stub. What is modelled is what needs root: a by-id directory of
# symlinks onto device files, a mapper directory whose sysfs `slaves/` records the backing device,
# and `mount` as a symlink swap of the mountpoint onto the device's content directory — so a swap
# that mounts the wrong device shows the wrong CONTENTS, not merely the wrong name.
#
# What this suite cannot see, stated plainly: real dm-crypt, real kernel mount semantics, real
# systemd, real Redis. The resolver's loopback suite is the real-device anchor for the devices this
# script consumes; this suite is the anchor for the FSM's decisions.
#
# Harness conventions (this repo's own post-mortems — load-bearing):
#   - NEVER pipe into an assertion predicate (pipefail + early grep -q match fails OPEN).
#   - An instrument self-test runs first, and the floor reports with printf + exit, never through
#     the helpers it guards.
#   - Every fixture write goes through assert_fixture_dir (P1b).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${LUKS_CUTOVER_SUT:-$SCRIPT_DIR/inngest-luks-cutover.sh}"
[ -f "$SUT" ] || { printf '[FATAL] SUT not found: %s\n' "$SUT" >&2; exit 2; }

pass=0; fail=0; executed=0
FAILED=()
ok() { pass=$((pass + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); executed=$((executed + 1)); FAILED+=("$1"); printf 'FAIL - %s\n' "$1"; }

# INSTRUMENT SELF-TEST — both helpers move their counters, reported without the helpers.
_p0=$pass; _f0=$fail
{ ok "instrument self-test (expected)"; no "instrument self-test (expected)"; } >/dev/null
if [ "$pass" -ne $((_p0 + 1)) ] || [ "$fail" -ne $((_f0 + 1)) ] || [ "${#FAILED[@]}" -ne 1 ]; then
  printf '[FATAL] instrument self-test: ok()/no() did not each move their counter\n' >&2; exit 2
fi
pass=$_p0; fail=$_f0; executed=0; FAILED=()

assert_fixture_dir() {
  case "${1-}" in
    "") printf '[FATAL] fixture path is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf '[FATAL] fixture path %s contains ..\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf '[FATAL] fixture path %s is a synthetic-fs path\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf '[FATAL] fixture path resolves to /\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf '[FATAL] fixture path %s is RELATIVE\n' "$1" >&2; exit 2 ;;
  esac
}

ROOT="$(mktemp -d -t luks-cutover.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT
PLAIN_ID=111111111
LUKS_ID=222222222

# ── The modelled block layer ───────────────────────────────────────────────────────────────────
# world <name> — a fresh pre-cutover host: plaintext volume canonical at mnt/data, the additive
# volume staged under inngest-redis-staging at mnt/data-luks, Redis and the server running.
world() {
  W="$ROOT/w-$1"; assert_fixture_dir "$W"
  mkdir -p "$W"/{byid,dev,fs/plain,fs/luks-inner,mapper,sys,proc,units,state,etc,bin,mnt/data-plain}
  : > "$W/dev/plain"; : > "$W/dev/luks"
  ln -s "$W/dev/plain" "$W/byid/scsi-0HC_Volume_${PLAIN_ID}"
  ln -s "$W/dev/luks"  "$W/byid/scsi-0HC_Volume_${LUKS_ID}"
  # the store: an AOF directory, the flip FSM's flush latch, and some bulk
  mkdir -p "$W/fs/plain/redis/appendonlydir" "$W/fs/plain/inngest-cutover" "$W/fs/plain/lost+found"
  printf 'file appendonly.aof.1.base.rdb seq 1 type b\n' > "$W/fs/plain/redis/appendonlydir/appendonly.aof.manifest"
  head -c 4096 /dev/urandom > "$W/fs/plain/redis/appendonlydir/appendonly.aof.1.base.rdb"
  printf 'flushed_at=2026-09-01T00:00:00Z host=x dbsize=0\n' > "$W/fs/plain/inngest-cutover/flip-done.latch"
  printf 'prompt-bearing-row\n' > "$W/fs/plain/redis/canary"
  mkdir -p "$W/fs/luks-inner/lost+found"
  # opened mapper + mounts: plaintext canonical, staging mapper over the additive volume
  : > "$W/mapper/inngest-redis-staging"; mkdir -p "$W/sys/inngest-redis-staging/slaves"; : > "$W/sys/inngest-redis-staging/slaves/luks"
  ln -s "$W/fs/plain" "$W/mnt/data"
  ln -s "$W/fs/luks-inner" "$W/mnt/data-luks"
  printf '%s %s\n' "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" "$W/mnt/data" > "$W/mounts"
  printf '%s %s\n' "$W/mapper/inngest-redis-staging" "$W/mnt/data-luks" >> "$W/mounts"
  printf '%s %s ext4 defaults,nofail 0 2\n' "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" "$W/mnt/data" > "$W/etc/fstab"
  printf '%s %s ext4 defaults,nofail 0 2\n' "$W/mapper/inngest-redis-staging" "$W/mnt/data-luks" >> "$W/etc/fstab"
  printf 'INNGEST_REDIS_LUKS_KEY=synthesized-test-key\n' > "$W/etc/inngest-luks"
  : > "$W/units/inngest-redis.service"; : > "$W/units/inngest-server.service"
  : > "$W/units/inngest-cutover-flip.timer"; : > "$W/units/inngest-server-probe.timer"
  printf '# Keyspace\r\ndb0:keys=10,expires=2,avg_ttl=0\r\ndb1:keys=5,expires=0,avg_ttl=0\r\n' > "$W/keyspace"
  printf '200' > "$W/health.code"
  printf '{"data":{"functions":[{"id":"a"},{"id":"b"}]}}' > "$W/gql.body"
  printf '0' > "$W/aof.rc"
  : > "$W/flag.log"; : > "$W/pointer.log"; : > "$W/log"; : > "$W/systemctl.log"
  write_stubs
}

# content_of <source> — the content directory a mount of <source> shows
content_of() {
  local s="$1" name
  case "$s" in
    "$W"/mapper/*) name="${s##*/}"; printf '%s/fs/%s-inner' "$W" "$(ls "$W/sys/$name/slaves")" ;;
    *) printf '%s/fs/%s' "$W" "$(basename "$(readlink -f "$s")")" ;;
  esac
}

write_stubs() {
  local b="$W/bin"
  # mount SRC MNT / umount MNT — a symlink swap of the mountpoint onto the device's contents
  cat > "$b/mount" <<EOF
#!/usr/bin/env bash
W="$W"
$(declare -f content_of)
src="\$1"; mnt="\$2"
c="\$(content_of "\$src")"
[ -d "\$c" ] || { echo "mount: \$src has no filesystem (\$c)" >&2; exit 32; }
awk -v m="\$mnt" '\$2==m{f=1} END{exit !f}' "\$W/mounts" && { echo "mount: \$mnt busy" >&2; exit 32; }
rmdir "\$mnt" 2>/dev/null || rm -f "\$mnt"
ln -s "\$c" "\$mnt"
printf '%s %s\n' "\$src" "\$mnt" >> "\$W/mounts"
EOF
  cat > "$b/umount" <<EOF
#!/usr/bin/env bash
W="$W"; mnt="\${@: -1}"
awk -v m="\$mnt" '\$2==m{f=1} END{exit !f}' "\$W/mounts" || { echo "umount: \$mnt not mounted" >&2; exit 32; }
awk -v m="\$mnt" '\$2!=m' "\$W/mounts" > "\$W/mounts.t"; mv "\$W/mounts.t" "\$W/mounts"
rm -f "\$mnt"; mkdir -p "\$mnt"
EOF
  cat > "$b/findmnt" <<EOF
#!/usr/bin/env bash
awk -v m="\${@: -1}" '\$2==m{print \$1}' "$W/mounts"
EOF
  cat > "$b/mountpoint" <<EOF
#!/usr/bin/env bash
awk -v m="\${@: -1}" '\$2==m{f=1} END{exit !f}' "$W/mounts"
EOF
  # stat -L -c %d — a mounted path reads a different device from its parent (is_real_mount)
  cat > "$b/stat" <<EOF
#!/usr/bin/env bash
p="\${@: -1}"
case "\$p" in */..) echo 1; exit 0 ;; esac
awk -v m="\$p" '\$2==m{f=1} END{exit !f}' "$W/mounts" && echo 2 || echo 1
EOF
  cat > "$b/redis-check-aof" <<EOF
#!/usr/bin/env bash
exit "\$(cat "$W/aof.rc")"
EOF
  cat > "$b/cryptsetup" <<EOF
#!/usr/bin/env bash
W="$W"
op="\$1"; shift; a=(); for x in "\$@"; do case "\$x" in --*|-) ;; *) a+=("\$x") ;; esac; done
case "\$op" in
  luksOpen)  cat >/dev/null; d="\$(basename "\$(readlink -f "\${a[0]}")")"; : > "\$W/mapper/\${a[1]}"; mkdir -p "\$W/sys/\${a[1]}/slaves"; : > "\$W/sys/\${a[1]}/slaves/\$d" ;;
  luksClose) rm -f "\$W/mapper/\${a[0]}"; rm -rf "\$W/sys/\${a[0]}" ;;
  *) exit 1 ;;
esac
EOF
  cat > "$b/systemctl" <<EOF
#!/usr/bin/env bash
W="$W"; printf '%s\n' "\$*" >> "\$W/systemctl.log"
case "\$1" in
  stop)  rm -f "\$W/units/\$2" ;;
  start) : > "\$W/units/\$2" ;;
  is-active|is-enabled) u="\${@: -1}"; [ -e "\$W/units/\$u" ] ;;
esac
EOF
  cat > "$b/redis-cli" <<EOF
#!/usr/bin/env bash
[ -e "$W/redis.fail" ] && exit 1
cat "$W/keyspace"
EOF
  cat > "$b/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in *http_code*) cat "$W/health.code" ;; *) cat "$W/gql.body" ;; esac
EOF
  cat > "$b/flag" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$W/flag.log"
EOF
  cat > "$b/pointer" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$W/pointer.log"
EOF
  cat > "$b/logger" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$W/log"
EOF
  chmod +x "$b"/*
}

# run <flag> [pointer] — run the REAL script under --fixture-seams in world W
run() {
  RC=0
  env -i PATH="$W/bin:/usr/bin:/bin" HOME="$W" \
    INNGEST_LUKS_PLAIN_VOLUME_ID="$PLAIN_ID" INNGEST_LUKS_ADDITIVE_VOLUME_ID="$LUKS_ID" \
    INNGEST_REDIS_LUKS_KEY=synthesized-test-key INNGEST_LUKS_ACTIVE_VOLUME_ID="${2:-}" \
    LUKS_FLAG="$1" LUKS_UID="${RUN_UID:-0}" \
    LUKS_BYID="$W/byid" LUKS_MAPPER_DIR="$W/mapper" LUKS_SYSFS="$W/sys" LUKS_PROC="$W/proc" \
    LUKS_MNT="$W/mnt/data" LUKS_STAGING_MNT="$W/mnt/data-luks" LUKS_PLAIN_MNT="$W/mnt/data-plain" \
    LUKS_FSTAB="$W/etc/fstab" LUKS_ENVFILE="$W/etc/inngest-luks" LUKS_STATE_DIR="$W/state" \
    LUKS_FLAG_SET_CMD="$W/bin/flag" LUKS_POINTER_CMD="$W/bin/pointer" LUKS_LOGGER_CMD="$W/bin/logger" \
    LUKS_SYSTEMCTL_CMD="$W/bin/systemctl" LUKS_CRYPTSETUP_CMD="$W/bin/cryptsetup" \
    LUKS_REDIS_CLI_CMD="$W/bin/redis-cli" LUKS_CURL_CMD="$W/bin/curl" \
    LUKS_VERIFY_WINDOW_S="${VERIFY_WINDOW:-2}" LUKS_VERIFY_INTERVAL_S=0 \
    bash "$SUT" --fixture-seams > "$W/out" 2>&1 < /dev/null || RC=$?
}
flags() { tr '\n' ' ' < "$W/flag.log" | sed 's/ $//'; }
reason_seen() { grep -qF "\"reason\":\"$1" "$W/log"; }
src_of() { awk -v m="$1" '$2==m{print $1}' "$W/mounts"; }
fstab_lines() { awk -v m="$1" '$1 !~ /^#/ && $2==m' "$W/etc/fstab" | wc -l; }
same_tree() {  # same_tree <a> <b> — byte identity, computed independently of the SUT
  [ "$(cd "$1" && find . -type f ! -path './lost+found/*' -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)" = \
    "$(cd "$2" && find . -type f ! -path './lost+found/*' -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum)" ]
}

# ═══ No-op and refusal arms ═══════════════════════════════════════════════════════════════════
for st in "" done rolled-back aborted; do
  world "noop-${st:-unset}"
  run "$st"
  if [ "$RC" -eq 0 ] && [ -z "$(flags)" ] && [ ! -s "$W/systemctl.log" ]; then ok "noop '${st:-unset}': exit 0, no flag write, no unit touched"; else no "noop '${st:-unset}': rc=$RC flags=[$(flags)] systemctl=$(wc -l < "$W/systemctl.log")"; fi
done

world notroot
RUN_UID=1000 run armed
if [ "$RC" -ne 0 ] && reason_seen not-root && [ -z "$(flags)" ] && [ ! -s "$W/systemctl.log" ]; then ok "non-root: refuses before any probe, flag or unit (measurements.md §1)"; else no "non-root: rc=$RC flags=[$(flags)]"; fi

# ── The seam gate: WITHOUT --fixture-seams, a seam name in the environment is ignored ─────────
world seamgate
printf '#!/usr/bin/env bash\n: > %s/evil.ran\n' "$W" > "$W/bin/evil"; chmod +x "$W/bin/evil"
RC=0
env -i PATH="$W/bin:/usr/bin:/bin" LUKS_FLAG=armed LUKS_FLAG_SET_CMD="$W/bin/evil" LUKS_UID=0 LUKS_STATE_DIR="$W/state" \
  bash "$SUT" > "$W/out" 2>&1 < /dev/null || RC=$?
if [ ! -e "$W/evil.ran" ] && grep -qF 'SOLEUR_INNGEST_LUKS_CUTOVER_SEAM_REFUSED' "$W/log"; then ok "seam gate: a Doppler-injected seam is unset and reported, never executed (#7761 shape)"; else no "seam gate: evil seam ran=$([ -e "$W/evil.ran" ] && echo yes || echo no), refused-marker=$(grep -c SEAM_REFUSED "$W/log")"; fi

# ═══ The forward cutover ══════════════════════════════════════════════════════════════════════
world happy
run armed
if [ "$RC" -eq 0 ]; then ok "forward: exit 0"; else no "forward: rc=$RC — $(tail -3 "$W/out" | tr '\n' '|')"; fi
if [ "$(flags)" = "copying copied swapped done" ]; then ok "forward: flag walks copying → copied → swapped → done"; else no "forward: flag sequence [$(flags)]"; fi
if [ "$(src_of "$W/mnt/data")" = "$W/mapper/inngest-redis" ]; then ok "forward: /mnt/data is the CANONICAL mapper"; else no "forward: /mnt/data source [$(src_of "$W/mnt/data")]"; fi
if [ "$(ls "$W/sys/inngest-redis/slaves" 2>/dev/null)" = "luks" ]; then ok "forward: the canonical mapper is backed by the ADDITIVE volume"; else no "forward: canonical backing [$(ls "$W/sys/inngest-redis/slaves" 2>/dev/null)]"; fi
if [ -f "$W/mnt/data/redis/canary" ] && same_tree "$W/fs/plain" "$W/fs/luks-inner"; then ok "forward: the store now served is byte-identical to the plaintext source (checked independently of the SUT)"; else no "forward: the served store differs from the source"; fi
if [ -f "$W/mnt/data/inngest-cutover/flip-done.latch" ]; then ok "forward: the flip FSM's flush latch crossed the swap (Fork L)"; else no "forward: the flush latch is missing on the new store — a second FLUSHALL is re-opened"; fi
if [ "$(cat "$W/pointer.log")" = "set $LUKS_ID" ]; then ok "forward: the durable pointer is written once, naming the additive volume"; else no "forward: pointer writes [$(tr '\n' '|' < "$W/pointer.log")]"; fi
if grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$LUKS_ID" "$W/etc/inngest-luks" && grep -qx 'INNGEST_REDIS_LUKS_KEY=synthesized-test-key' "$W/etc/inngest-luks"; then ok "forward: the pointer is staged for the reopen unit AND the passphrase survived the rewrite"; else no "forward: env file [$(tr '\n' '|' < "$W/etc/inngest-luks")]"; fi
if [ "$(fstab_lines "$W/mnt/data")" -eq 1 ] && grep -qF "$W/mapper/inngest-redis $W/mnt/data " "$W/etc/fstab" && [ "$(fstab_lines "$W/mnt/data-luks")" -eq 0 ]; then ok "forward: fstab — exactly one /mnt/data line, naming the mapper; the staging line removed"; else no "forward: fstab [$(tr '\n' '|' < "$W/etc/fstab")]"; fi
if [ ! -e "$W/mapper/inngest-redis-staging" ]; then ok "forward: the staging mapper is closed"; else no "forward: the staging mapper is still open"; fi
if grep -qxF 'stop inngest-cutover-flip.timer' "$W/systemctl.log" && grep -qxF 'stop inngest-redis.service' "$W/systemctl.log" \
   && [ "$(grep -nxF 'stop inngest-cutover-flip.timer' "$W/systemctl.log" | cut -d: -f1)" -lt "$(grep -nxF 'stop inngest-redis.service' "$W/systemctl.log" | cut -d: -f1)" ]; then ok "forward: timers stop BEFORE services, so nothing re-fires a stopped writer"; else no "forward: freeze order [$(tr '\n' '|' < "$W/systemctl.log")]"; fi
if [ -e "$W/units/inngest-redis.service" ] && [ -e "$W/units/inngest-server.service" ] && [ -e "$W/units/inngest-cutover-flip.timer" ]; then ok "forward: writers and timers are running again"; else no "forward: not every writer was resumed"; fi
if grep -q 'k_freeze=15 e_freeze=2' "$W/state/copy-verified.latch" 2>/dev/null; then ok "forward: the copy latch records T1 (keys summed across databases: 10+5)"; else no "forward: copy latch [$(cat "$W/state/copy-verified.latch" 2>/dev/null)]"; fi
if [ ! -e "$W/fs/plain/inngest-cutover/luks-copy-verified.latch" ] && [ "$(wc -l < "$W/fs/plain/inngest-cutover/flip-done.latch")" -eq 1 ]; then ok "forward: the cutover never appended to the flip FSM's flush latch"; else no "forward: the flip latch was written to"; fi

# ═══ T1 / T2 / T3 guards (Guard 2) ═══════════════════════════════════════════════════════════
world t1
: > "$W/redis.fail"
run armed
if [ "$RC" -ne 0 ] && reason_seen t1-unreadable && ! grep -q '^stop ' "$W/systemctl.log"; then ok "T1 unreadable: refused BEFORE the freeze (an unreadable count is not a zero)"; else no "T1 unreadable: rc=$RC stops=$(grep -c '^stop ' "$W/systemctl.log")"; fi

world t2aof
printf '1' > "$W/aof.rc"
run armed
if [ "$RC" -ne 0 ] && reason_seen t2-aof-structure; then ok "T2: a structurally bad AOF copy is a HARD abort"; else no "T2 aof: rc=$RC"; fi
if [ ! -s "$W/pointer.log" ] && [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ]; then ok "T2 abort: no pointer written, /mnt/data still the plaintext store"; else no "T2 abort: pointer=[$(cat "$W/pointer.log")] /mnt/data=[$(src_of "$W/mnt/data")]"; fi
if [ -e "$W/units/inngest-redis.service" ] && [ -e "$W/units/inngest-server.service" ]; then ok "T2 abort: writers resumed on the plaintext store (the scheduler is not left dark)"; else no "T2 abort: writers left stopped"; fi
if [ "$(tail -1 "$W/flag.log")" = "aborted" ] && [ ! -e "$W/state/copy-verified.latch" ]; then ok "T2 abort: terminal aborted, and NO latch (the latch records verified completion, never entry)"; else no "T2 abort: last flag [$(tail -1 "$W/flag.log")] latch=$([ -e "$W/state/copy-verified.latch" ] && echo present || echo absent)"; fi

world t2unit
# a writer that comes back during the copy window: the systemctl stub re-activates Redis on stop
cat > "$W/bin/systemctl" <<EOF
#!/usr/bin/env bash
W="$W"; printf '%s\n' "\$*" >> "\$W/systemctl.log"
case "\$1" in
  stop) rm -f "\$W/units/\$2" ;;
  start) : > "\$W/units/\$2" ;;
  # Redis comes back only AFTER the freeze has proven it stopped: 4 pre-freeze reads + 2 post-stop
  # reads, so the 7th onward (T2's own re-check) reports active. The fixture is keyed to the
  # freeze's read COUNT deliberately — it models a unit that restarts during the copy window.
  is-active|is-enabled) n=\$(grep -c '^is-active' "\$W/systemctl.log"); u="\${@: -1}"; [ "\$u" = inngest-redis.service ] && [ "\$n" -gt 6 ] && exit 0; [ -e "\$W/units/\$u" ] ;;
esac
EOF
chmod +x "$W/bin/systemctl"
run armed
if [ "$RC" -ne 0 ] && reason_seen t2-unit-active; then ok "T2: Redis active during the copy window is a HARD abort (a moving source)"; else no "T2 unit-active: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

world t3
printf '503' > "$W/health.code"
VERIFY_WINDOW=0 run armed
if [ "$RC" -ne 0 ] && reason_seen t3-failed-rc10 && [ "$(tail -1 "$W/flag.log")" = "rolled-back" ]; then ok "T3: a server that never serves after the swap is rolled back (rc10)"; else no "T3 health: rc=$RC last flag [$(tail -1 "$W/flag.log")]"; fi
world t3fns
printf '{"data":{"functions":"xx"}}' > "$W/gql.body"
VERIFY_WINDOW=0 run armed
if [ "$RC" -ne 0 ] && reason_seen t3-failed-rc10; then ok "T3: a STRING functions field is not read as its character count (type guard)"; else no "T3 string functions: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

world t3empty
# after the swap Redis reports an EMPTY keyspace although T1 read 15 keys
cat > "$W/bin/redis-cli" <<EOF
#!/usr/bin/env bash
if [ -e "$W/mapper/inngest-redis" ]; then printf '# Keyspace\r\n'; else cat "$W/keyspace"; fi
EOF
chmod +x "$W/bin/redis-cli"
run armed
if [ "$RC" -ne 0 ] && reason_seen t3-failed-rc12; then ok "T3: a populated store read EMPTY on the canonical mapper is refused (the fourth predicate)"; else no "T3 empty: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi
if [ "$(tail -1 "$W/flag.log")" = "rolled-back" ] && [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ]; then ok "T3 rollback: back on the plaintext store, flag rolled-back"; else no "T3 rollback: flag [$(tail -1 "$W/flag.log")] /mnt/data [$(src_of "$W/mnt/data")]"; fi
if grep -qx "clear" "$W/pointer.log" && ! grep -q '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$W/etc/inngest-luks" && grep -qx 'INNGEST_REDIS_LUKS_KEY=synthesized-test-key' "$W/etc/inngest-luks"; then ok "T3 rollback: pointer cleared in Doppler and unstaged; the passphrase kept"; else no "T3 rollback: pointer log [$(tr '\n' '|' < "$W/pointer.log")] env [$(tr '\n' '|' < "$W/etc/inngest-luks")]"; fi
if [ ! -e "$W/mapper/inngest-redis" ]; then ok "T3 rollback: the CANONICAL mapper is closed (else the Redis guard refuses every start)"; else no "T3 rollback: the canonical mapper survived"; fi
if [ "$(src_of "$W/mnt/data-luks")" = "$W/mapper/inngest-redis-staging" ] && [ "$(fstab_lines "$W/mnt/data")" -eq 1 ] && grep -qF "$W/byid/scsi-0HC_Volume_${PLAIN_ID} $W/mnt/data " "$W/etc/fstab"; then ok "T3 rollback: the pre-cutover world restored — staging remounted, fstab back to the plaintext line"; else no "T3 rollback: staging=[$(src_of "$W/mnt/data-luks")] fstab=[$(tr '\n' '|' < "$W/etc/fstab")]"; fi

# ═══ A swap that fails part-way puts the plaintext store back (PHASE=frozen) ═══════════════════
world swapfail
# luksOpen records the WRONG backing device, so swap_forward's own backing check refuses mid-swap
sed -i 's|: > "\$W/sys/\${a\[1\]}/slaves/\$d"|: > "\$W/sys/\${a[1]}/slaves/plain"|' "$W/bin/cryptsetup"
mkdir -p "$W/fs/plain-inner"
grep -qF 'slaves/plain"' "$W/bin/cryptsetup" || { printf '[FATAL] swapfail fixture edit did not land\n' >&2; exit 2; }
run armed
if [ "$RC" -ne 0 ] && reason_seen swap-wrong-backing && [ ! -s "$W/pointer.log" ]; then ok "mid-swap: a wrong-backed canonical mapper is refused BEFORE the pointer is written"; else no "mid-swap: rc=$RC pointer=[$(cat "$W/pointer.log")]"; fi
if [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ] && [ ! -e "$W/mapper/inngest-redis" ] && [ -e "$W/units/inngest-redis.service" ]; then ok "mid-swap: the plaintext store is remounted, the canonical mapper closed, Redis resumed"; else no "mid-swap restore: /mnt/data=[$(src_of "$W/mnt/data")] mapper=$([ -e "$W/mapper/inngest-redis" ] && echo open || echo closed)"; fi

# ═══ Doppler write failures are fail-closed (plan criterion 23) ═══════════════════════════════
# A failed `doppler run` read never reaches the script: the unit fails under its SyslogIdentifier.
# What the SCRIPT owns are its Doppler WRITES, and each must fail closed with the store intact.
world dw-flag
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$1" >> %s/flag.log\n[ "$1" = copying ] && exit 1\nexit 0\n' "$W" > "$W/bin/flag"
run armed
if [ "$RC" -ne 0 ] && reason_seen 'unexpected-exit' && ! grep -q '^stop ' "$W/systemctl.log" && [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ]; then ok "Doppler write: a failed flag write before the freeze aborts with nothing stopped and the store untouched"; else no "Doppler flag write: rc=$RC stops=$(grep -c '^stop ' "$W/systemctl.log") reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

world dw-pointer
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %s/pointer.log\nexit 1\n' "$W" > "$W/bin/pointer"
run armed
if [ "$RC" -ne 0 ] && reason_seen 'unexpected-exit' && [ "$(tail -1 "$W/flag.log")" = "aborted" ]; then ok "Doppler write: a failed POINTER write mid-swap aborts (ERR trap), flag terminal"; else no "Doppler pointer write: rc=$RC last flag [$(tail -1 "$W/flag.log")]"; fi
if [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ] && [ ! -e "$W/mapper/inngest-redis" ] && [ -e "$W/units/inngest-redis.service" ] && ! grep -q '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$W/etc/inngest-luks" && grep -qF "$W/byid/scsi-0HC_Volume_${PLAIN_ID} $W/mnt/data " "$W/etc/fstab"; then ok "Doppler pointer write failed: plaintext store back on /mnt/data, canonical mapper closed, fstab and env untouched, Redis resumed"; else no "Doppler pointer restore: /mnt/data=[$(src_of "$W/mnt/data")] mapper=$([ -e "$W/mapper/inngest-redis" ] && echo open || echo closed) env=[$(tr '\n' '|' < "$W/etc/inngest-luks")]"; fi

# ═══ Rollback is DATA-SAFE: writes made on the encrypted store come back ════════════════════
world rbdata
run armed
printf 'written-after-the-cutover\n' > "$W/mnt/data/redis/post-cutover"
: > "$W/flag.log"; : > "$W/pointer.log"
run rollback "$LUKS_ID"
if [ "$RC" -eq 0 ] && [ "$(flags)" = "rolled-back" ]; then ok "operator rollback: exit 0, flag rolled-back"; else no "operator rollback: rc=$RC flags=[$(flags)] — $(tail -3 "$W/out" | tr '\n' '|')"; fi
if [ -f "$W/mnt/data/redis/post-cutover" ]; then ok "operator rollback: a write made AFTER the cutover survives it (reverse copy, not a bare swap back)"; else no "operator rollback: the post-cutover write was LOST"; fi

world rbnopointer
run rollback ""
if [ "$RC" -ne 0 ] && reason_seen rollback-no-pointer && ! grep -q '^stop ' "$W/systemctl.log"; then ok "rollback with no pointer: refused, nothing stopped"; else no "rollback no pointer: rc=$RC"; fi

# ═══ Preconditions refuse before anything stops ═════════════════════════════════════════════
world pre-pointer
run armed "$LUKS_ID"
if [ "$RC" -ne 0 ] && reason_seen pointer-already-set && ! grep -q '^stop ' "$W/systemctl.log"; then ok "pre: a pointer already set refuses (this host is past the cutover)"; else no "pre pointer: rc=$RC"; fi

world pre-backing
rm -f "$W/sys/inngest-redis-staging/slaves/luks"; : > "$W/sys/inngest-redis-staging/slaves/plain"
run armed
if [ "$RC" -ne 0 ] && reason_seen staging-wrong-backing && ! grep -q '^stop ' "$W/systemctl.log"; then ok "pre: a staging mapper backed by the plaintext volume refuses"; else no "pre backing: rc=$RC"; fi

world pre-envkey
printf 'SOMETHING_ELSE=1\n' > "$W/etc/inngest-luks"
run armed
if [ "$RC" -ne 0 ] && reason_seen envfile-key-absent && ! grep -q '^stop ' "$W/systemctl.log"; then ok "pre: an env file without the passphrase refuses before anything stops"; else no "pre envkey: rc=$RC"; fi

world pre-key
RC=0
env -i PATH="$W/bin:/usr/bin:/bin" INNGEST_LUKS_PLAIN_VOLUME_ID="$PLAIN_ID" INNGEST_LUKS_ADDITIVE_VOLUME_ID="$LUKS_ID" \
  LUKS_FLAG=armed LUKS_UID=0 LUKS_STATE_DIR="$W/state" LUKS_FLAG_SET_CMD="$W/bin/flag" LUKS_LOGGER_CMD="$W/bin/logger" \
  LUKS_SYSTEMCTL_CMD="$W/bin/systemctl" bash "$SUT" --fixture-seams > "$W/out" 2>&1 < /dev/null || RC=$?
if [ "$RC" -ne 0 ] && reason_seen luks-key-absent && [ ! -s "$W/systemctl.log" ]; then ok "pre: an un-injected passphrase refuses before anything stops (it is first read mid-swap)"; else no "pre key: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

world term
# The Redis stop hangs, and the stub records its PARENT — the SUT's own bash — so the signal is
# sent to exactly that pid, never matched by pattern.
cat > "$W/bin/systemctl" <<EOF
#!/usr/bin/env bash
W="$W"; printf '%s\n' "\$*" >> "\$W/systemctl.log"
case "\$1" in
  stop)  rm -f "\$W/units/\$2"; if [ "\$2" = inngest-redis.service ] && [ ! -e "\$W/hung" ]; then printf '%s' "\$PPID" > "\$W/sut.pid"; : > "\$W/hung"; sleep 2; fi ;;
  start) : > "\$W/units/\$2" ;;
  is-active|is-enabled) [ -e "\$W/units/\${@: -1}" ] ;;
esac
EOF
chmod +x "$W/bin/systemctl"
run armed & _bg=$!
for _i in $(seq 1 50); do [ -s "$W/sut.pid" ] && break; sleep 0.1; done
[ -s "$W/sut.pid" ] && kill -TERM "$(cat "$W/sut.pid")" 2>/dev/null
wait "$_bg" 2>/dev/null
if [ -e "$W/hung" ] && grep -qF '"exit_code":143' "$W/log" && reason_seen terminated && [ -e "$W/units/inngest-redis.service" ] && [ -e "$W/units/inngest-cutover-flip.timer" ] && [ "$(tail -1 "$W/flag.log")" = "aborted" ]; then ok "SIGTERM mid-freeze: writers and timers resumed, flag aborted, the kill reported"; else no "SIGTERM: hung=$([ -e "$W/hung" ] && echo y || echo n) reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ') last flag [$(tail -1 "$W/flag.log")]"; fi

world quiesce
mkdir -p "$W/proc/4242/fd"; ln -s "$W/mnt/data/redis/canary" "$W/proc/4242/fd/3"
run armed
if [ "$RC" -ne 0 ] && reason_seen mount-not-quiesced; then ok "quiesce: a process still holding a file under the store aborts the run"; else no "quiesce: rc=$RC"; fi
if [ -e "$W/units/inngest-redis.service" ]; then ok "quiesce abort: writers resumed"; else no "quiesce abort: writers left stopped"; fi

# ═══ The resume set is RECORDED, never assumed (#8077 Guard 2 #6c) ════════════════════════════
# An unconditional `start inngest-server.service` re-arms a scheduler an operator quiesced. The
# freeze records what was ACTIVE; the resume starts exactly that.
world quiesced-server
rm -f "$W/units/inngest-server.service"      # the operator stopped the scheduler before the cutover
run armed
if [ "$RC" -eq 0 ] && [ -e "$W/units/inngest-redis.service" ] && [ ! -e "$W/units/inngest-server.service" ]; then ok "resume: a unit that was NOT running before the freeze is not started by it (no re-arm of a quiesced scheduler)"; else no "resume quiesced: rc=$RC redis=$([ -e "$W/units/inngest-redis.service" ] && echo up || echo down) server=$([ -e "$W/units/inngest-server.service" ] && echo STARTED || echo down)"; fi
if grep -qx 'start inngest-redis.service' "$W/systemctl.log" && ! grep -qx 'start inngest-server.service' "$W/systemctl.log"; then ok "resume: the start set is derived from the recorded freeze set, not from a fixed list"; else no "resume set: $(grep '^start ' "$W/systemctl.log" | tr '\n' '|')"; fi

world resume-no-record
run armed
rm -f "$W/state/frozen-active"
: > "$W/flag.log"
rm -f "$W/units/inngest-server-probe.timer"   # disabled by the operator; must stay disabled
run swapped "$LUKS_ID"
if [ "$RC" -eq 0 ] && [ -e "$W/units/inngest-redis.service" ] && [ ! -e "$W/units/inngest-server-probe.timer" ]; then ok "resume: with no record (a reboot mid-cutover), the ENABLED set is used — a disabled unit is still not started"; else no "resume fallback: rc=$RC probe=$([ -e "$W/units/inngest-server-probe.timer" ] && echo STARTED || echo down)"; fi

# ═══ Resume arms ═════════════════════════════════════════════════════════════════════════════
world copied-valid
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"
run copied
if [ "$RC" -eq 0 ] && [ "$(flags)" = "swapped done" ] && [ ! -e "$W/state/copy-verified.latch" ] && same_tree "$W/fs/plain" "$W/fs/luks-inner"; then ok "copied resume: a still-valid copy is re-verified and swapped without being re-made"; else no "copied resume valid: rc=$RC flags=[$(flags)] latch=$([ -e "$W/state/copy-verified.latch" ] && echo rewritten || echo absent)"; fi

world copied-stale
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"
printf 'written-after-the-copy\n' > "$W/fs/plain/redis/late"
run copied
if [ "$RC" -eq 0 ] && [ -f "$W/mnt/data/redis/late" ] && [ -s "$W/state/copy-verified.latch" ]; then ok "copied resume: a STALE copy is re-made and re-latched, not trusted on the latch's word"; else no "copied resume stale: rc=$RC late=$([ -f "$W/mnt/data/redis/late" ] && echo present || echo missing)"; fi

world swapped-resume
run armed
: > "$W/flag.log"
run swapped "$LUKS_ID"
if [ "$RC" -eq 0 ] && [ "$(flags)" = "done" ]; then ok "swapped resume: T3 re-run on the canonical mapper, then done"; else no "swapped resume: rc=$RC flags=[$(flags)]"; fi
world swapped-empty
run armed
: > "$W/flag.log"
cat > "$W/bin/redis-cli" <<EOF
#!/usr/bin/env bash
printf '# Keyspace\r\n'
EOF
run swapped "$LUKS_ID"
if [ "$RC" -ne 0 ] && reason_seen t3-failed-rc12; then ok "swapped resume: T1 is recovered from the latch, so an empty store after a crash is still caught"; else no "swapped resume empty: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

# ═══ copy_store guards itself (it rm -rf's its destination) ════════════════════════════════════
# Called directly from a sourced copy: the FSM's preconditions would refuse these worlds first, so
# only a direct call proves the function does not rely on every caller having checked.
call_copy() {  # call_copy <src> <dst>
  RC=0
  env -i PATH="$W/bin:/usr/bin:/bin" LUKS_UID=0 LUKS_STATE_DIR="$W/state" LUKS_FLAG_SET_CMD="$W/bin/flag" \
    LUKS_LOGGER_CMD="$W/bin/logger" LUKS_SYSTEMCTL_CMD="$W/bin/systemctl" \
    bash -c 'source "$1" --fixture-seams; copy_store "$2" "$3"' _ "$SUT" "$1" "$2" > "$W/out" 2>&1 < /dev/null || RC=$?
}
world guard-notmount
mkdir -p "$W/notmount"; printf 'keep\n' > "$W/notmount/precious"
call_copy "$W/mnt/data" "$W/notmount"
if [ "$RC" -ne 0 ] && reason_seen copy-dst-not-a-mount && [ -f "$W/notmount/precious" ]; then ok "copy_store: an unmounted destination is refused BEFORE its contents are removed"; else no "copy_store notmount: rc=$RC precious=$([ -f "$W/notmount/precious" ] && echo kept || echo DELETED)"; fi
world guard-self
call_copy "$W/mnt/data" "$W/mnt/data"
if [ "$RC" -ne 0 ] && reason_seen copy-dst-is-src && [ -f "$W/fs/plain/redis/canary" ]; then ok "copy_store: destination == source is refused (the store is not wiped onto itself)"; else no "copy_store self: rc=$RC"; fi
world guard-empty
call_copy "$W/mnt/data" ""
if [ "$RC" -ne 0 ] && reason_seen copy-dst-unsafe; then ok "copy_store: an EMPTY destination is refused"; else no "copy_store empty: rc=$RC"; fi
world guard-rel
call_copy "$W/mnt/data" "mnt/data-luks"
if [ "$RC" -ne 0 ] && reason_seen copy-dst-unsafe; then ok "copy_store: a RELATIVE destination is refused"; else no "copy_store relative: rc=$RC"; fi

# ═══ #7797: tracing with a live credential is refused, not traced ══════════════════════════════
world xtrace
RC=0
env -i PATH="$W/bin:/usr/bin:/bin" INNGEST_REDIS_LUKS_KEY=synthesized-test-key LUKS_FLAG=armed LUKS_UID=0 \
  bash -x "$SUT" --fixture-seams > "$W/xtrace.out" 2>&1 < /dev/null || RC=$?
if [ "$RC" -eq 78 ] && ! grep -qF 'synthesized-test-key' "$W/xtrace.out"; then ok "xtrace: refuses with exit 78 and the passphrase never reaches the trace (#7797)"; else no "xtrace: rc=$RC leaked=$(grep -c 'synthesized-test-key' "$W/xtrace.out")"; fi
RC=0
env -i PATH="$W/bin:/usr/bin:/bin" LUKS_FLAG=done LUKS_UID=0 LUKS_STATE_DIR="$W/state" LUKS_LOGGER_CMD="$W/bin/logger" \
  bash -x "$SUT" --fixture-seams > /dev/null 2>&1 < /dev/null || RC=$?
if [ "$RC" -eq 0 ]; then ok "xtrace: with no credential bound, tracing is allowed (the refusal is about the credential, not about -x)"; else no "xtrace positive control: rc=$RC"; fi

# ═══ Structural pins ═══════════════════════════════════════════════════════════════════════
# Every Doppler write discards stdout: `doppler secrets set|delete` prints EVERY remaining secret,
# and this unit's stdout is the journal Vector ships to Better Stack.
_dw_total="$(grep -cE '^[^#]*doppler secrets (set|delete) ' "$SUT")"
_dw_bad="$(grep -E '^[^#]*doppler secrets (set|delete) ' "$SUT" | grep -cv '>/dev/null' || true)"
if [ "$_dw_total" -ge 3 ] && [ "$_dw_bad" -eq 0 ]; then ok "structural: all ${_dw_total} Doppler writes discard stdout (it lists every secret, and stdout is shipped off-box)"; else no "structural: ${_dw_bad} of ${_dw_total} Doppler writes leak stdout"; fi
# The seam list is DERIVED, not trusted: every LUKS_* read in the body is in the gate's unset list.
# A name the script ASSIGNS is not a seam (the environment value is overwritten), so it is excluded.
_assigned="$(grep -oE '^[[:space:]]*LUKS_[A-Z_]+=' "$SUT" | tr -d ' =' | LC_ALL=C sort -u)"
_seam_body="$(grep -oE '\$\{?LUKS_[A-Z_]+' "$SUT" | tr -d '${' | LC_ALL=C sort -u | comm -23 - <(printf '%s\n' "$_assigned"))"
_seam_gate="$(awk '/for _seam in \\/{f=1;next} f&&/^  do$/{exit} f' "$SUT" | grep -oE 'LUKS_[A-Z_]+' | LC_ALL=C sort -u)"
if [ -n "$_seam_gate" ] && [ "$_seam_body" = "$_seam_gate" ]; then ok "structural: every seam read is in the argv-gated unset list ($(printf '%s\n' "$_seam_gate" | grep -c .) names)"; else no "structural: seam set drift — body-only: $(comm -23 <(printf '%s\n' "$_seam_body") <(printf '%s\n' "$_seam_gate") | tr '\n' ' ')"; fi
# T2's readability predicates are SEPARATE from its comparisons (Guard 2 row 1).
if grep -qF 'if [[ "$a" == "__UNREADABLE__" || "$b" == "__UNREADABLE__" ]]; then printf '"'"'t2-listing-unreadable'"'"'' "$SUT" \
   && grep -qF 'if ! is_uint "$a" || ! is_uint "$b"; then printf '"'"'t2-bytes-unreadable'"'"'' "$SUT"; then ok "structural: T2 checks readability on its own before any comparison"; else no "structural: a T2 readability check was merged into (or removed from) its comparison"; fi
# The latch is written AFTER T2, never before (Guard 2 row 7) — in every arm that writes it.
_latch_order_bad="$(awk '/^ *record_copy_latch$/{ if (prev !~ /^ *t2_verify "/) bad++ } { prev = $0 } END{print bad+0}' "$SUT")"
if [ "$_latch_order_bad" -eq 0 ] && [ "$(grep -c '^ *record_copy_latch$' "$SUT")" -ge 2 ]; then ok "structural: every copy-latch write is immediately preceded by a T2 verify"; else no "structural: a copy-latch write precedes T2 (${_latch_order_bad})"; fi
# There is exactly ONE copy primitive, and every call to it is followed by a T2 verify (row 5).
_copies="$(grep -cE '^ *copy_store "' "$SUT")"
_unverified="$(awk '/^ *copy_store "/{c=NR; getline nxt; if (nxt !~ /t2_verify/) u++} END{print u+0}' "$SUT")"
if [ "$_copies" -ge 3 ] && [ "$_unverified" -eq 0 ] && [ "$(grep -cE '^[^#]*cp -a ' "$SUT")" -eq 1 ]; then ok "structural: ${_copies} copy sites, each immediately T2-verified, through one cp -a"; else no "structural: copy sites=${_copies} unverified=${_unverified} cp-a=$(grep -cE '^[^#]*cp -a ' "$SUT")"; fi

# ═══ FLOOR — reported directly, never through ok()/no() ═══════════════════════════════════════
_floor=66
if [ "$executed" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$executed" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-cutover.test.sh: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$executed" "$_floor"
[ "$fail" -eq 0 ]
