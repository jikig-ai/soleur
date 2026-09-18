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

# HELPER SELF-TEST — the instrument self-test above covers ok()/no(); these two helpers own a
# verdict of their own and are invisible to it. Measured: an always-true `same_tree` and an
# always-true `reason_seen` each left the suite 66/66 green — and `same_tree` IS this suite's
# independent byte-identity check, the second source that is supposed to make T2's claim checkable.
_helper_self_test() {
  local d="$1"; assert_fixture_dir "$d"   # P1b: this function's operand is a caller parameter
  mkdir -p "$d/x" "$d/y"; printf 'a\n' > "$d/x/f"; printf 'b\n' > "$d/y/f"
  same_tree "$d/x" "$d/x" || { printf '[FATAL] same_tree: identical trees compared UNEQUAL\n' >&2; exit 2; }
  ! same_tree "$d/x" "$d/y" || { printf '[FATAL] same_tree: differing trees compared EQUAL — it is always-true\n' >&2; exit 2; }
  W="$d"; printf '{"marker":"X","reason":"self-test-reason","flag":"x"}\n' > "$d/log"
  reason_seen self-test-reason || { printf '[FATAL] reason_seen: a present reason was not seen\n' >&2; exit 2; }
  ! reason_seen no-such-reason-xyz || { printf '[FATAL] reason_seen: an ABSENT reason was seen — it is always-true\n' >&2; exit 2; }
  unset W
}

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

ROOT="$(mktemp -d -t luks-cutover.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$ROOT"' EXIT
PLAIN_ID=111111111
LUKS_ID=222222222

# ── The modelled block layer ───────────────────────────────────────────────────────────────────
# world <name> — a fresh pre-cutover host: plaintext volume canonical at mnt/data, the additive
# volume staged under inngest-redis-staging at mnt/data-luks, Redis and the server running.
world() {
  W="$ROOT/w-$1"; assert_fixture_dir "$W"
  mkdir -p "$W"/{byid,dev,fs/plain,fs/luks-inner,mapper,sys,proc,units,enabled,state,etc,bin,mnt/data-plain}
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
  : > "$W/units/inngest-server-probe.service"   # a READER of the store: frozen, not merely timed off
  rm -f "$W/units/inngest-cutover-flip.service" # the destructive sibling FSM: idle in every world but the one that tests it
  # ENABLEMENT IS NOT RUNNING STATE. `systemctl is-enabled` reads the install symlink and answers
  # yes for a unit that is stopped — which is the whole basis of the record-less resume path, so a
  # stub that answers both questions from one file cannot test it.
  for _u in inngest-redis.service inngest-server.service inngest-server-probe.service inngest-cutover-flip.timer inngest-server-probe.timer; do : > "$W/enabled/$_u"; done
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
# An explicit third argument overrides the content directory. That is how a world expresses two
# mountpoints of ONE device: same source (so the device id agrees) and different content paths (so
# `readlink -f` disagrees), which is the kernel's shape and the one the symlink model cannot reach.
c="\${3:-\$(content_of "\$src")}"
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
  # stat -L -c %d — the DEVICE NUMBER, modelled per underlying device rather than per mountpoint.
  #
  # The first version returned one constant for every mounted path, which made two mountpoints of
  # DIFFERENT devices indistinguishable from two mountpoints of the SAME device. That is precisely
  # the distinction `copy_store` must make before it `rm -rf`s a destination — a rollback killed
  # after it remounted the plaintext volume re-enters with one device mounted at two paths, where
  # the path strings differ and the device does not. A stub that cannot express that cannot test it.
  cat > "$b/stat" <<EOF
#!/usr/bin/env bash
W="$W"
$(declare -f content_of)
p="\${@: -1}"
case "\$p" in */..) echo 1; exit 0 ;; esac
src="\$(awk -v m="\$p" '\$2==m{print \$1}' "\$W/mounts" | tail -1)"
[ -n "\$src" ] || { echo 1; exit 0; }
# Keyed on the DEVICE the mount is of, never on the directory it is showing: two mountpoints of one
# device must agree here even when they are showing separate content paths.
d="\$(readlink -f "\$src" 2>/dev/null || printf '%s' "\$src")"
case "\$src" in "\$W"/mapper/*) d="\$(ls "\$W/sys/\$(basename "\$src")/slaves" 2>/dev/null | head -1)" ;; esac
printf '%s' "\$d" | cksum | awk '{print \$1}'
EOF
  cat > "$b/redis-check-aof" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$W/aof-check.argv"
# --fix truncates from the first bad byte. The script says so; nothing tested it until a mutation
# pointed --fix at the LIVE SOURCE and stayed green.
case "\$*" in *--fix*) printf 'redis-check-aof: --fix TRUNCATES\n' >> "$W/stub-violations"; exit 96 ;; esac
exit "\$(cat "$W/aof.rc")"
EOF
  cat > "$b/cryptsetup" <<EOF
#!/usr/bin/env bash
W="$W"
op="\$1"; shift; a=(); for x in "\$@"; do case "\$x" in --*|-) ;; *) a+=("\$x") ;; esac; done
case "\$op" in
  luksOpen)  _k="\$(cat)"
             [ "\$_k" = synthesized-test-key ] || { printf 'cryptsetup: luksOpen got the WRONG passphrase [%s]\n' "\$_k" >> "\$W/stub-violations"; exit 95; }
             d="\$(basename "\$(readlink -f "\${a[0]}")")"; : > "\$W/mapper/\${a[1]}"; mkdir -p "\$W/sys/\${a[1]}/slaves"; : > "\$W/sys/\${a[1]}/slaves/\$d" ;;
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
  is-active)  u="\${@: -1}"; [ -e "\$W/units/\$u" ] ;;
  is-enabled) u="\${@: -1}"; [ -e "\$W/enabled/\$u" ] ;;
esac
EOF
  # A stub that answers any question is a fixture that cannot catch the SUT asking the wrong one.
  # Measured: with a catch-all stub, swapping `INFO keyspace` for `DBSIZE` — the exact read the
  # script's header explains at length that it must NOT use, because DBSIZE sees database 0 only —
  # left the suite green with the latch still reporting the summed 15.
  cat > "$b/redis-cli" <<EOF
#!/usr/bin/env bash
[ -e "$W/redis.fail" ] && exit 1
case "\$*" in
  *"INFO keyspace"*) cat "$W/keyspace" ;;
  *) printf 'redis-cli: unmodelled command [%s]\n' "\$*" >> "$W/stub-violations"; exit 97 ;;
esac
EOF
  # Dispatch on the URL, not on a flag: keying on -w let the two call sites be swapped undetected.
  cat > "$b/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"/health"*) cat "$W/health.code" ;;
  *"/v0/gql"*) cat "$W/gql.body" ;;
  *) printf 'curl: unmodelled URL [%s]\n' "\$*" >> "$W/stub-violations"; exit 94 ;;
esac
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
  printf '#!/usr/bin/env bash\nexit 1\n' > "$b/systemctl-idle"   # every unit INACTIVE: t2_check's
  # unit-activity leg would otherwise short-circuit before any comparison runs
  chmod +x "$b"/*
}

# run <flag> [pointer] — run the REAL script under --fixture-seams in world W
run() {
  RC=0
  env -i PATH="$W/bin:/usr/bin:/bin" HOME="$W" \
    INNGEST_LUKS_PLAIN_VOLUME_ID="$PLAIN_ID" INNGEST_LUKS_ADDITIVE_VOLUME_ID="$LUKS_ID" \
    INNGEST_REDIS_LUKS_KEY=synthesized-test-key INNGEST_REDIS_PASSWORD=synthesized-test-password \
    INNGEST_LUKS_ACTIVE_VOLUME_ID="${2:-}" \
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
# The closing quote is load-bearing: without it `t3-failed-rc1` prefix-matches rc10 through rc14.
reason_seen() { grep -qE "\"reason\":\"$1(\"|-|\\()" "$W/log"; }
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
  # Redis comes back DURING the copy window, keyed to the FSM's own POSITION: after it announces
  # phase-copy-start and before the copy latch exists. A read COUNT was the first spelling and it
  # was wrong twice — a count moves whenever any unrelated is-active probe is added or removed, so
  # deleting an ORTHOGONAL guard silently disarmed this case.
  is-active)  u="\${@: -1}"
              [ "\$u" = inngest-redis.service ] && grep -q phase-copy-start "\$W/log" && [ ! -e "\$W/state/copy-verified.latch" ] && exit 0
              [ -e "\$W/units/\$u" ] ;;
  is-enabled) [ -e "\$W/enabled/\${@: -1}" ] ;;
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
# The durable pointer is the LAST write of the swap, so a failed pointer write leaves the host
# CORRECTLY SERVING THE ENCRYPTED STORE with only Doppler stale — which is the safe direction and
# the reason for that ordering. What must hold is that the on-host world is self-consistent (mapper
# mounted, env and fstab naming it) and that the writers came back.
if [ "$(src_of "$W/mnt/data")" = "$W/mapper/inngest-redis" ] && grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$LUKS_ID" "$W/etc/inngest-luks" && grep -qF "$W/mapper/inngest-redis $W/mnt/data " "$W/etc/fstab" && [ -e "$W/units/inngest-redis.service" ]; then ok "Doppler pointer write failed LAST: the host serves the encrypted store, env and fstab agree with it, writers resumed — only Doppler lags"; else no "Doppler pointer restore: /mnt/data=[$(src_of "$W/mnt/data")] env=[$(tr '\n' '|' < "$W/etc/inngest-luks")] fstab=[$(tr '\n' '|' < "$W/etc/fstab")]"; fi

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
  INNGEST_REDIS_PASSWORD=synthesized-test-password \
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
  is-active)  [ -e "\$W/units/\${@: -1}" ] ;;
  is-enabled) [ -e "\$W/enabled/\${@: -1}" ] ;;
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
rm -f "$W/units/inngest-server-probe.timer" "$W/enabled/inngest-server-probe.timer"   # DISABLED by the operator; must stay disabled
run swapped "$LUKS_ID"
if [ "$RC" -eq 0 ] && [ -e "$W/units/inngest-redis.service" ] && [ ! -e "$W/units/inngest-server-probe.timer" ]; then ok "resume: with no record (a reboot mid-cutover), the ENABLED set is used — a disabled unit is still not started"; else no "resume fallback: rc=$RC probe=$([ -e "$W/units/inngest-server-probe.timer" ] && echo STARTED || echo down)"; fi

# ═══ The worlds a symlink-only mount model could not express ══════════════════════════════════
# Both of these were invisible to this suite until the stat stub modelled device identity, and both
# are real sequences an operator can reach: a rollback killed after it put the store back, and a
# kill inside the swap itself.

world same-device
# A rollback killed after `mount "$plain_dev" "$MNT"`: the plaintext volume is now mounted at BOTH
# /mnt/data and (on re-entry) /mnt/data-plain. The path strings differ; the device does not.
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"
"$W/bin/umount" "$W/mnt/data" 2>/dev/null || true
"$W/bin/mount" "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" "$W/mnt/data"
run rollback "$LUKS_ID"
if [ -f "$W/fs/plain/redis/canary" ] && [ -s "$W/fs/plain/redis/appendonlydir/appendonly.aof.1.base.rdb" ]; then ok "same-device re-entry: the live store is NOT wiped (device identity, not path identity, decides)"; else no "same-device re-entry: the store was DESTROYED — canary=$([ -f "$W/fs/plain/redis/canary" ] && echo kept || echo GONE)"; fi
if [ "$RC" -eq 0 ] && [ "$(tail -1 "$W/flag.log")" = "rolled-back" ] && [ "$(tail -1 "$W/pointer.log")" = "clear" ] && [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ] && [ -e "$W/units/inngest-redis.service" ]; then ok "same-device re-entry: the rollback COMPLETES (pointer cleared, flag terminal) rather than refusing on its own second mount"; else no "same-device re-entry: rc=$RC flag=[$(tail -1 "$W/flag.log")] pointer=[$(tail -1 "$W/pointer.log")] /mnt/data=[$(src_of "$W/mnt/data")]"; fi

world crash-mid-swap
# A kill landed INSIDE swap_forward, after the mount and before the flag was written. The writers
# are stopped, PHASE is lost with the process, and the flag still reads `copied`.
run armed >/dev/null 2>&1 || true
"$W/bin/umount" "$W/mnt/data" 2>/dev/null || true
"$W/bin/systemctl" stop inngest-redis.service; "$W/bin/systemctl" stop inngest-server.service
rm -f "$W/etc/inngest-luks-pointer-marker"
: > "$W/flag.log"; : > "$W/systemctl.log"
printf '%s' "$W" > /dev/null
# leave the canonical mapper mounted (the swap's mount succeeded) and the bookkeeping unwritten
"$W/bin/mount" "$W/mapper/inngest-redis" "$W/mnt/data"
python3 - "$W" <<'PY2'
import sys,re,io,os
w=sys.argv[1]
p=os.path.join(w,'etc','inngest-luks')
s=open(p).read()
open(p,'w').write(re.sub(r'^INNGEST_LUKS_ACTIVE_VOLUME_ID=.*\n?','',s,flags=re.M))
PY2
run copied
if [ "$RC" -eq 0 ] && [ -e "$W/units/inngest-redis.service" ] && [ -e "$W/units/inngest-server.service" ]; then ok "crash mid-swap: the next tick REPAIRS FORWARD and the scheduler comes back (not a terminal abort)"; else no "crash mid-swap: rc=$RC redis=$([ -e "$W/units/inngest-redis.service" ] && echo up || echo DOWN) server=$([ -e "$W/units/inngest-server.service" ] && echo up || echo DOWN)"; fi
if [ "$(src_of "$W/mnt/data")" = "$W/mapper/inngest-redis" ] && grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$LUKS_ID" "$W/etc/inngest-luks" && grep -qF "$W/mapper/inngest-redis $W/mnt/data " "$W/etc/fstab" && [ "$(cat "$W/pointer.log" | tail -1)" = "set $LUKS_ID" ]; then ok "crash mid-swap: the repair completes the bookkeeping the kill interrupted (env, fstab, durable pointer)"; else no "crash mid-swap repair: env=[$(tr '\n' '|' < "$W/etc/inngest-luks")] pointer=[$(tr '\n' '|' < "$W/pointer.log")]"; fi
if [ "$(tail -1 "$W/flag.log")" = "done" ]; then ok "crash mid-swap: the FSM reaches done rather than parking terminal-aborted"; else no "crash mid-swap: last flag [$(tail -1 "$W/flag.log")]"; fi

world flip-in-flight
: > "$W/units/inngest-cutover-flip.service"   # the destructive sibling FSM is mid-run
run armed
if [ "$RC" -ne 0 ] && reason_seen flip-in-flight && ! grep -q '^stop ' "$W/systemctl.log"; then ok "the destructive sibling FSM mid-run refuses the cutover BEFORE anything is stopped (it owns the FLUSHALL)"; else no "flip-in-flight: rc=$RC stops=$(grep -c '^stop ' "$W/systemctl.log")"; fi

world noauth
# Redis answers, but with an error REPLY on stdout and exit 0 — the shape an absent password makes.
cat > "$W/bin/redis-cli" <<EOF
#!/usr/bin/env bash
printf '(error) NOAUTH Authentication required.\n'
EOF
chmod +x "$W/bin/redis-cli"
run armed
if [ "$RC" -ne 0 ] && reason_seen t1-unreadable && ! grep -q '^stop ' "$W/systemctl.log"; then ok "an error REPLY is not a zero: NOAUTH refuses before the freeze instead of certifying an empty store"; else no "noauth: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

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

# ═══ T2 AS THE PURE PREDICATE IT ADVERTISES ═══════════════════════════════════════════════════
# Every FSM arm hands T2 a pair `cp -a` produced moments earlier, so eight of its ten failure
# reasons are unreachable through them — deleting the checksum comparison outright left this suite
# green, which made its headline claim ("byte-equality is MEASURED") vacuous. t2_check is a pure
# predicate by design; these call it directly, which is the only way to reach the comparison legs.
call_t2() {  # call_t2 <src> <dst> -> T2RC, T2WHY
  T2RC=0
  T2WHY="$(env -i PATH="$W/bin:/usr/bin:/bin" LUKS_UID=0 LUKS_STATE_DIR="$W/state" \
    LUKS_LOGGER_CMD="$W/bin/logger" LUKS_SYSTEMCTL_CMD="$W/bin/systemctl-idle" \
    bash -c 'source "$1" --fixture-seams; t2_check "$2" "$3"' _ "$SUT" "$1" "$2" 2>&1)" || T2RC=$?
}
world t2-content
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"
printf 'CORRUPTED-ROW-HERE\n' > "$W/fs/luks-inner/redis/canary"   # same name, SAME SIZE, different bytes
if [ "$(stat -c %s "$W/fs/plain/redis/canary")" -ne "$(stat -c %s "$W/fs/luks-inner/redis/canary")" ]; then printf '[FATAL] t2-content fixture: sizes differ, the listing leg would catch it first\n' >&2; exit 2; fi
call_t2 "$W/fs/plain" "$W/fs/luks-inner"
if [ "$T2RC" -ne 0 ] && [ "$T2WHY" = "t2-checksums-differ" ]; then ok "T2: a copy matching by NAME and SIZE but differing by BYTE is refused (the checksum leg)"; else no "T2 content: rc=$T2RC why=[$T2WHY]"; fi
world t2-positive
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"
call_t2 "$W/fs/plain" "$W/fs/luks-inner"
if [ "$T2RC" -eq 0 ] && [ -z "$T2WHY" ]; then ok "T2 positive control: a byte-identical pair passes every leg (the direction a refusing-everything T2 would fail)"; else no "T2 positive: rc=$T2RC why=[$T2WHY]"; fi
world t2-listing
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"; printf 'x\n' > "$W/fs/luks-inner/redis/extra"
call_t2 "$W/fs/plain" "$W/fs/luks-inner"
if [ "$T2WHY" = "t2-listing-differs" ]; then ok "T2: an extra file on the copy is caught by the listing leg"; else no "T2 listing: [$T2WHY]"; fi
world t2-unreadable
call_t2 "$W/fs/plain" "$W/does-not-exist"
if [ "$T2WHY" = "t2-listing-unreadable" ]; then ok "T2: an unreadable tree prints the sentinel, never an empty listing that would compare equal to another empty one"; else no "T2 unreadable: [$T2WHY]"; fi
world t2-latch
cp -a "$W/fs/plain/." "$W/fs/luks-inner/"
printf 'DIFFERENT\n' > "$W/fs/luks-inner/inngest-cutover/flip-done.latch"
truncate -s "$(stat -c %s "$W/fs/plain/inngest-cutover/flip-done.latch")" "$W/fs/luks-inner/inngest-cutover/flip-done.latch"
call_t2 "$W/fs/plain" "$W/fs/luks-inner"
# rc ONLY, deliberately: the latch lives inside the checksummed tree, so the REASON at this point
# is t2-checksums-differ and the Fork L leg that runs after it is an EQUIVALENT MUTANT — deleting
# it leaves this row green. Measured, and argued where the leg is, not papered over here.
if [ "$T2RC" -ne 0 ]; then ok "T2: a flip-latch that differs is refused (Fork L — a swap without it re-opens a second FLUSHALL)"; else no "T2 latch: rc=$T2RC why=[$T2WHY]"; fi

# ═══ The guards the review pass added, each with a case of its own ═════════════════════════════
world same-device-direct
# Two mountpoints of ONE device, handed straight to copy_store — the shape a rollback re-entry
# reaches. The twin shows its own content PATH (so `readlink -f` disagrees, exactly as on a real
# kernel) while naming the same device (so `stat -c %d` agrees). Without that split the symlink
# model collapses both paths onto one target and the PATH check refuses for a reason the kernel
# would not have provided — the case would pass with the device check deleted.
mkdir -p "$W/fs/plain-twin"; cp -a "$W/fs/plain/." "$W/fs/plain-twin/"
mkdir -p "$W/mnt/twin"; "$W/bin/mount" "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" "$W/mnt/twin" "$W/fs/plain-twin"
if [ "$(readlink -f "$W/mnt/twin")" = "$(readlink -f "$W/mnt/data")" ]; then printf '[FATAL] same-device fixture: both paths resolve alike, the PATH check would refuse first\n' >&2; exit 2; fi
call_copy "$W/mnt/data" "$W/mnt/twin"
if [ "$RC" -ne 0 ] && reason_seen copy-dst-is-src && [ -f "$W/fs/plain-twin/redis/canary" ]; then ok "copy_store: two mountpoints of ONE device are refused by DEVICE identity (the paths differ; the filesystem does not)"; else no "same-device direct: rc=$RC twin canary=$([ -f "$W/fs/plain-twin/redis/canary" ] && echo kept || echo DESTROYED)"; fi
world src-not-mount
mkdir -p "$W/bare/redis"; printf 'x\n' > "$W/bare/redis/f"
call_copy "$W/bare" "$W/mnt/data-luks"
if [ "$RC" -ne 0 ] && reason_seen copy-src-not-a-mount && [ -f "$W/fs/luks-inner/lost+found/.keep" -o -d "$W/fs/luks-inner" ]; then ok "copy_store: a SOURCE that is not a mount is refused (a kill between two umounts leaves /mnt/data a bare root-disk directory)"; else no "src-not-mount: rc=$RC"; fi
world no-password
RC=0
env -i PATH="$W/bin:/usr/bin:/bin" INNGEST_LUKS_PLAIN_VOLUME_ID="$PLAIN_ID" INNGEST_LUKS_ADDITIVE_VOLUME_ID="$LUKS_ID" \
  INNGEST_REDIS_LUKS_KEY=synthesized-test-key LUKS_FLAG=armed LUKS_UID=0 LUKS_STATE_DIR="$W/state" \
  LUKS_FLAG_SET_CMD="$W/bin/flag" LUKS_LOGGER_CMD="$W/bin/logger" LUKS_SYSTEMCTL_CMD="$W/bin/systemctl" \
  bash "$SUT" --fixture-seams > "$W/out" 2>&1 < /dev/null || RC=$?
if [ "$RC" -ne 0 ] && reason_seen redis-password-absent && ! grep -q '^stop ' "$W/systemctl.log"; then ok "pre: an un-injected Redis password refuses before the freeze (every keyspace read would be an error reply)"; else no "no-password: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi
world envfile-dup
# systemd's EnvironmentFile is LAST-WINS, so a second pointer line decides which volume the
# boot-reopen unit opens. The rewrite must leave exactly one — asserted as a COUNT, because a
# presence check passes just as happily with two.
printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=999999999\n' >> "$W/etc/inngest-luks"
run armed
_n_ptr="$(grep -c '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' "$W/etc/inngest-luks" || true)"
if [ "$RC" -eq 0 ] && [ "$_n_ptr" -eq 1 ] && grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$LUKS_ID" "$W/etc/inngest-luks"; then ok "envfile: a pre-existing DUPLICATE pointer line is normalised to exactly one, naming the additive volume"; else no "envfile-dup: rc=$RC pointer lines=$_n_ptr"; fi

world rb-pointer-mismatch
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"; : > "$W/systemctl.log"   # the setup run's stops are not this case's evidence
run rollback 999999999
if [ "$RC" -ne 0 ] && reason_seen rollback-pointer-mismatch && ! grep -q '^stop ' "$W/systemctl.log"; then ok "rollback: a pointer naming a volume this host does not own is refused before anything stops"; else no "rb-pointer-mismatch: rc=$RC stops=$(grep -c '^stop ' "$W/systemctl.log") reasons=[$(grep -o '\"reason\":\"[^\"]*' "$W/log" | tr '\n' ' ')]"; fi
world rb-dst-holder
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"
mkdir -p "$W/proc/7777/fd"; ln -s "$W/mnt/data-plain/x" "$W/proc/7777/fd/3"
run rollback "$LUKS_ID"
if [ "$RC" -ne 0 ] && reason_seen mount-not-quiesced; then ok "rollback: a holder under the DESTINATION is refused — copy_store clears that path"; else no "rb-dst-holder: rc=$RC"; fi
world rb-abort-keeps-mapper
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"; printf '1' > "$W/aof.rc"    # the reverse copy's T2 fails
run rollback "$LUKS_ID"
if [ "$RC" -ne 0 ] && [ "$(src_of "$W/mnt/data")" = "$W/mapper/inngest-redis" ] && [ -e "$W/units/inngest-redis.service" ]; then ok "rollback abort: the ENCRYPTED store stays mounted (the frozen branch's 'plaintext is canonical' is false here) and writers resume"; else no "rb-abort: rc=$RC /mnt/data=[$(src_of "$W/mnt/data")] redis=$([ -e "$W/units/inngest-redis.service" ] && echo up || echo DOWN)"; fi
world refuse-resumes
# A refusal in a process that did NOT perform the freeze: PHASE is init, the record is on disk.
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"
rm -f "$W/sys/inngest-redis-staging/slaves/luks"; : > "$W/sys/inngest-redis-staging/slaves/plain"
printf ' inngest-redis.service inngest-server.service\n' > "$W/state/frozen-active"
"$W/bin/systemctl" stop inngest-redis.service; "$W/bin/systemctl" stop inngest-server.service
run copied
if [ -e "$W/units/inngest-redis.service" ] && [ -e "$W/units/inngest-server.service" ]; then ok "a refusal resumes from the RECORD even when this process never froze anything (PHASE is init after a kill)"; else no "refuse-resumes: redis=$([ -e "$W/units/inngest-redis.service" ] && echo up || echo DOWN) server=$([ -e "$W/units/inngest-server.service" ] && echo up || echo DOWN)"; fi
world t3-wrong-backing
run armed >/dev/null 2>&1 || true
: > "$W/flag.log"
rm -f "$W/sys/inngest-redis/slaves/luks"; : > "$W/sys/inngest-redis/slaves/plain"
run swapped "$LUKS_ID"
if [ "$RC" -ne 0 ] && reason_seen t3-failed-rc15; then ok "T3: the canonical mapper must sit on the ADDITIVE volume — the resume arm reaches T3 without ever having run the swap's own backing check"; else no "t3-wrong-backing: rc=$RC reasons=$(grep -o '"reason":"[^"]*' "$W/log" | tr '\n' ' ')"; fi

world flip-starts-mid-copy
# The precondition catches a flip that is ALREADY running. This is the other half: one that starts
# DURING the copy window, which only T2's own re-check can see.
cat > "$W/bin/systemctl" <<EOF
#!/usr/bin/env bash
W="$W"; printf '%s\n' "\$*" >> "\$W/systemctl.log"
case "\$1" in
  stop)  rm -f "\$W/units/\$2" ;;
  start) : > "\$W/units/\$2" ;;
  is-active)  u="\${@: -1}"
              # the flip appears once the copy is under way
              [ "\$u" = inngest-cutover-flip.service ] && grep -q phase-copy-start "\$W/log" && exit 0
              [ -e "\$W/units/\$u" ] ;;
  is-enabled) [ -e "\$W/enabled/\${@: -1}" ] ;;
esac
EOF
chmod +x "$W/bin/systemctl"
run armed
if [ "$RC" -ne 0 ] && reason_seen t2-unit-active && [ "$(src_of "$W/mnt/data")" = "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" ]; then ok "T2: a flip that STARTS during the copy window is caught by T2's own re-check, with the plaintext store untouched"; else no "flip mid-copy: rc=$RC /mnt/data=[$(src_of "$W/mnt/data")] reasons=$(grep -o '\"reason\":\"[^\"]*' "$W/log" | tr '\n' ' ')"; fi

world stacked-mount
# findmnt lists a stacked mountpoint oldest-first, so `head -1` returns the SHADOWED source while
# the kernel serves the last one. restore_service_best_effort umounts with `|| true` and then mounts
# unconditionally, so this is reachable — and reading the wrong row means the FSM (and the Redis
# mount guard that copies this idiom) believe the mapper is serving while plaintext is on top.
#
# THE TWO ROWS MUST NAME DIFFERENT DEVICES. An earlier version of this world stacked the PLAINTEXT
# volume onto a fresh world, whose /mnt/data is ALREADY the plaintext volume — so `head -1` and
# `tail -1` returned the same row and the assertion below passed with the defect live (measured:
# `tail -1` -> `head -1` left the suite 89/89 green). The stack is therefore built explicitly:
# the canonical mapper underneath (the post-swap topology), plaintext stacked on top.
: > "$W/mapper/inngest-redis"; mkdir -p "$W/sys/inngest-redis/slaves"; : > "$W/sys/inngest-redis/slaves/luks"
{ printf '%s %s\n' "$W/mapper/inngest-redis" "$W/mnt/data"                       # SHADOWED, listed first
  printf '%s %s\n' "$W/mapper/inngest-redis-staging" "$W/mnt/data-luks"
  printf '%s %s\n' "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" "$W/mnt/data"; } > "$W/mounts"   # stacked ON TOP
_top="$(awk -v m="$W/mnt/data" '$2==m{print $1}' "$W/mounts" | tail -1)"
_bot="$(awk -v m="$W/mnt/data" '$2==m{print $1}' "$W/mounts" | head -1)"
if [ "$_top" = "$_bot" ]; then printf '[FATAL] stacked-mount fixture: both rows name %s — head and tail agree, so the row below cannot discriminate\n' "$_top" >&2; exit 2; fi
_mounted_from() {  # _mounted_from <mountpoint> <device> -> rc
  env -i PATH="$W/bin:/usr/bin:/bin" LUKS_UID=0 LUKS_BYID="$W/byid" LUKS_MAPPER_DIR="$W/mapper" \
    LUKS_SYSFS="$W/sys" LUKS_MNT="$W/mnt/data" LUKS_STATE_DIR="$W/state" LUKS_LOGGER_CMD="$W/bin/logger" \
    bash -c 'source "$1" --fixture-seams; mounted_from "$2" "$3"' _ "$SUT" "$1" "$2"
}
_mf=0; _mounted_from "$W/mnt/data" "$W/byid/scsi-0HC_Volume_${PLAIN_ID}" && _mf=1
if [ "$_mf" -eq 1 ]; then ok "mounted_from reads the EFFECTIVE (last) mount of a stacked pair, not the shadowed one"; else no "stacked-mount: mounted_from did not see the top mount — it is reading head -1"; fi
# The negative half. Without it, a mounted_from that answered TRUE for ANY row of the stack would
# satisfy the row above while telling the FSM the mapper is still serving.
_ms=0; _mounted_from "$W/mnt/data" "$W/mapper/inngest-redis" && _ms=1
if [ "$_ms" -eq 0 ]; then ok "mounted_from does NOT match the SHADOWED mapper row (the swap looks undone, which it is)"; else no "stacked-mount: mounted_from matched the shadowed mapper — it accepts any row of the stack"; fi

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
_floor=90
if [ "$executed" -lt "$_floor" ]; then printf '[FATAL] assertion floor: %s ran, floor %s\n' "$executed" "$_floor" >&2; exit 1; fi
if [ "${#FAILED[@]}" -ne "$fail" ]; then printf '[FATAL] ledger %s != fail counter %s\n' "${#FAILED[@]}" "$fail" >&2; exit 1; fi
printf '\n=== inngest-luks-cutover.test.sh: %s passed, %s failed (%s assertions, floor %s) ===\n' "$pass" "$fail" "$executed" "$_floor"
# The GATE, reported like the floor: printf + exit, never a trailing expression whose status a
# later edit can shadow. Measured: `[ "$fail" -eq 0 ]` as the last line returned 0 on a red run.
if [ "$fail" -ne 0 ]; then
  printf '[FAIL] %s assertion(s) failed:\n' "$fail" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
