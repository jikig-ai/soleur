#!/usr/bin/env bash
#
# REAL-DEVICE evidence for the #7695 LUKS apparatus on the inngest Redis AOF store.
#
# STRUCTURAL tier. It reads cloud-init-inngest.yml, inngest-redis.service and
# inngest-redis-bootstrap.sh, and asserts the properties a behavioural run cannot see — that the
# boot-reopen unit is ENABLED and has a passphrase source, that the wait bound is what the design
# says, that no `|| true` sits on a path that could leave /mnt/data on the root disk, and that
# `nofail` is retained.
#
# THE BEHAVIOURAL TIER IS A SEPARATE FILE: inngest-redis-luks-loopback.test.sh, which builds a real
# loopback device and drives the REAL extracted cloud-init stage through all five blkid arms plus a
# second simulated boot. THE SPLIT IS NOT COSMETIC. That suite needs root, so it is invoked as
# `sudo bash` inside a multi-line `run: |` block and is deliberately invisible to
# run-registered-suites.sh's single-line derivation — deriving it would turn a mandated ship gate
# permanently RED for any operator without passwordless sudo (the workspaces-luks-loopback
# precedent, tracked #7076). Keeping THIS tier in a plain single-line registration is what keeps
# the arms that actually caught the two shipped P0s inside the local gate the work and ship skills
# mandate, instead of behind a privilege check most runs cannot satisfy.
#
# NO SILENT SKIP: it exits non-zero if any of the three files it reads is missing.
#
# Harness conventions (this repo's own post-mortems — load-bearing):
#   - NEVER pipe into an assertion predicate. Under `set -o pipefail` an early `grep -q` match
#     SIGPIPEs the producer (141) and a NEGATIVE assertion then fails OPEN. Every assertion greps
#     a FILE directly.
#   - Every setup command is rc-checked. A harness that fails to SET UP must ABORT, never continue
#     into a confident wrong verdict about the SUT.
#   - mktemp for every path; dm names and backing files are $$-scoped so two concurrent worktree
#     runs cannot collide.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init-inngest.yml"
REDIS_UNIT="$SCRIPT_DIR/inngest-redis.service"
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
  echo "inngest-redis-luks: LOOPBACK_UNAVAILABLE — real-device evidence was NOT collected." >&2
  echo "This is a FAILURE, not a skip: run as root on a host with losetup + cryptsetup +" >&2
  echo "mkfs.ext4 + a dm-crypt-capable kernel (GitHub-hosted ubuntu runners qualify, via sudo)." >&2
  exit 2
}

for f in "$CLOUD_INIT" "$REDIS_UNIT" "$REDIS_BOOTSTRAP"; do
  [ -f "$f" ] || unavailable "required file not found: $f"
done

# ═══ TIER 1 — structural ═════════════════════════════════════════════════════════

# T1.1 The boot-reopen unit is ENABLED. It shipped un-enabled once: `write_files` puts a unit on
# disk and NOTHING starts it, so on boot 2 the mapper stays closed, the `nofail` fstab line skips
# silently, and Redis writes its AOF to the ephemeral root disk — the exact failure the unit
# exists to prevent. A `write_files` entry looks like delivery and is not.
if grep -qE 'systemctl enable --now inngest-luks-open\.service' "$CLOUD_INIT"; then ok "T1.1 boot-reopen unit is systemctl-enabled"; else no "T1.1 inngest-luks-open.service is written but never enabled — on boot 2 it does not run at all"; fi

# T1.2 …and the enable's outcome is phoned home. An enable that fails silently is the same defect
# one level up: the unit exists, is not running, and nothing off-box says so.
if grep -qE 'inngest-luks-reopen-(armed|ARM-FAILED)' "$CLOUD_INIT"; then ok "T1.2 the enable outcome self-reports off-box"; else no "T1.2 the boot-reopen enable has no off-box success/failure marker"; fi

# T1.3 The unit has a PASSPHRASE SOURCE. It shipped reading INNGEST_REDIS_LUKS_KEY from
# /etc/default/inngest-doppler, which carries only HOME + the Doppler token — so every boot >= 2
# would have hit reopen_key_missing. It cannot be solved with `doppler run`: the unit is ordered
# DefaultDependencies=no / Before=local-fs.target, so it runs before the network exists.
if grep -qF 'EnvironmentFile=/etc/default/inngest-luks' "$CLOUD_INIT"; then ok "T1.3 the reopen unit reads a dedicated passphrase env file"; else no "T1.3 inngest-luks-open.service has no source for INNGEST_REDIS_LUKS_KEY — it fails reopen_key_missing on every boot >= 2"; fi

# T1.4 …and something WRITES that file, under a restrictive umask, from inside the one stage where
# the key is in scope without a network call.
if grep -qE "umask 0177 .*inngest-luks-key|umask 0177 && printf 'INNGEST_REDIS_LUKS_KEY" "$CLOUD_INIT"; then ok "T1.4 the passphrase is staged 0600 for the reopen unit"; else no "T1.4 nothing writes /etc/default/inngest-luks — the EnvironmentFile would be absent and the unit would fail"; fi

# T1.5 The staging write is FATAL, not best-effort. A key that silently failed to land reproduces
# the plaintext-AOF-on-root-disk failure one boot later, with nothing watching.
if grep -qF '[ -s /etc/default/inngest-luks ] ||' "$CLOUD_INIT"; then ok "T1.5 the passphrase staging is asserted, not best-effort"; else no "T1.5 the /etc/default/inngest-luks write is unchecked"; fi

# T1.6 The device-presence wait bound is 30. blkid on an absent path returns rc 2, which the
# accept-0-or-2 policy would otherwise route into the luksFormat arm — a volume that is merely
# slow to attach must never be read as blank. Tier 2 lowers this bound for one case; this is the
# pin that keeps that a declared harness knob rather than an invented budget.
if [ "$(grep -cE '\[ "\$_i" -lt 30 \]|\[ "\$\$_i" -lt 30 \]' "$CLOUD_INIT")" -ge 2 ]; then ok "T1.6 both the runcmd stage and the reopen script bound the attach wait at 30s"; else no "T1.6 the 30s device-presence wait bound is missing from one of the two device readers"; fi

# T1.7 No `|| true` / `|| :` / `set +e` on a mount. The whole apparatus is defeated by one of them:
# a swallowed mount failure leaves /mnt/data as a plain directory on the root disk while every
# downstream check that reads the STRING "/mnt/data" still passes.
LUKS_BLOCK="$(awk '/doppler run --project soleur-inngest --config prd -- bash -s <<.LUKSEOF.$/,/^    LUKSEOF$/' "$CLOUD_INIT")"
if [ -n "$LUKS_BLOCK" ]; then ok "T1.7a the LUKS stage block extracts"; else no "T1.7a could not extract the LUKS stage from $CLOUD_INIT — every assertion below it would be vacuous"; fi
printf '%s\n' "$LUKS_BLOCK" > /tmp/.ilt-block.$$ 2>/dev/null || true
if [ -s /tmp/.ilt-block.$$ ] && ! grep -qE '^\s*(mount|mkfs|cryptsetup)[^|]*\|\|\s*(true|:)\s*$' /tmp/.ilt-block.$$; then ok "T1.7b no mount/mkfs/cryptsetup step is suffixed with || true"; else no "T1.7b a mount/mkfs/cryptsetup step swallows its failure"; fi
# ANCHORED ON SYNTAX, NOT ON THE BARE TOKEN. The stage's own comment says "No `|| true`, no
# `|| :`, and no `set +e`" — so a bare-literal grep matches the SUT's documentation of the rule and
# reports a violation that does not exist. This is the collision `cq-assert-anchor-not-bare-token`
# names, and it fired here on the first run: a comment line starts with `#`, a statement does not.
if [ -s /tmp/.ilt-block.$$ ] && ! grep -qE '^[[:space:]]*set[[:space:]]+\+e' /tmp/.ilt-block.$$; then ok "T1.7c the stage never disarms errexit"; else no "T1.7c the LUKS stage contains a live 'set +e' statement"; fi
rm -f /tmp/.ilt-block.$$

# T1.8 `nofail` is RETAINED in every fstab line the stage writes. A strict fstab on a host with no
# SSH and no console converts a slow attach into an unrecoverable boot wedge; loud failure belongs
# in the Redis unit's ExecStartPre, not in a line that bricks the boot before anything can report.
_fstab_lines="$(grep -cE 'echo "\$(DEV|MAPPER) /mnt/data ext4 defaults,nofail 0 2"' "$CLOUD_INIT")"
if [ "$_fstab_lines" -eq 3 ]; then ok "T1.8 all three fstab writes retain nofail"; else no "T1.8 expected 3 nofail-carrying fstab writes (one per mounting arm), found ${_fstab_lines}"; fi

# T1.9 THE EXT4 ARM MUST STILL PERMIT REDIS TO START. This is the regression test for the
# ExecStartPre deadlock: a ONE-state gate demanding /dev/mapper/inngest-redis unconditionally
# would refuse to start Redis on the PRE-recut host — whose volume is plaintext ext4 today — and
# deadlock the very cutover this apparatus exists to enable.
if grep -qF 'ExecStartPre=/usr/local/bin/inngest-redis-mount-guard.sh' "$REDIS_UNIT"; then ok "T1.9a the Redis unit carries the mount guard"; else no "T1.9a inngest-redis.service has no ExecStartPre mount guard"; fi
if grep -qF 'if [ -e "$MAPPER" ]; then' "$REDIS_BOOTSTRAP"; then ok "T1.9b the guard is TWO-state (mapper-conditional), not a bare mapper demand"; else no "T1.9b the mount guard is not mapper-conditional — it would refuse to start Redis on the pre-recut ext4 host"; fi

# T1.10 expect_luks is threaded into BOTH device readers, or the post-recut refusal is armed in
# only one of them and an ext4 signature after a recut mounts plaintext from the other.
_expect_sites="$(grep -cF 'inngest_expect_luks' "$CLOUD_INIT")"
if [ "$_expect_sites" -ge 3 ]; then ok "T1.10 expect_luks reaches the runcmd stage and the reopen script"; else no "T1.10 expect_luks appears ${_expect_sites}x — it must thread into BOTH device readers"; fi

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only. A floor that lives in a helper
# is silenced by the same move that silences the arms it guards.
if [ "$executed" -lt 13 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 13. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 13)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks.test.sh (structural): ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
