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
VARIABLES_TF="$SCRIPT_DIR/variables.tf"
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
# PER-WINDOW, NOT A WHOLE-FILE COUNT — the same defect T1.10 carried. A `-ge 2` over the file is
# satisfied by two bounds in ONE reader and none in the other, which is precisely the state the arm
# names ("missing from one of the two"). Split at the runcmd stage's heredoc opener: above it is
# the write_files region shipping the boot-2 reopen script, below it the first-boot runcmd stage.
_split6="$(grep -n "bash -s <<'LUKSEOF'" "$CLOUD_INIT" | head -1 | cut -d: -f1)"
if [ -n "$_split6" ]; then
  _w6r="$(head -n "$((_split6 - 1))" "$CLOUD_INIT" | grep -cE '\[ "\$_i" -lt 30 \]|\[ "\$\$_i" -lt 30 \]')"
  _w6c="$(tail -n +"$_split6" "$CLOUD_INIT" | grep -cE '\[ "\$_i" -lt 30 \]|\[ "\$\$_i" -lt 30 \]')"
  if [ "$_w6r" -ge 1 ] && [ "$_w6c" -ge 1 ]; then ok "T1.6 BOTH device readers bound the attach wait at 30s (reopen ${_w6r}x, runcmd ${_w6c}x)"; else no "T1.6 the 30s device-presence wait bound is missing from one of the two device readers (reopen ${_w6r}x, runcmd ${_w6c}x)"; fi
else
  no "T1.6 could not locate the runcmd LUKS stage in $CLOUD_INIT — the per-window split is vacuous"
fi

# T1.7 No `|| true` / `|| :` / `set +e` on a mount. The whole apparatus is defeated by one of them:
# a swallowed mount failure leaves /mnt/data as a plain directory on the root disk while every
# downstream check that reads the STRING "/mnt/data" still passes.
LUKS_BLOCK="$(awk '/doppler run --project soleur-inngest --config prd -- bash -s <<.LUKSEOF.$/,/^    LUKSEOF$/' "$CLOUD_INIT")"
if [ -n "$LUKS_BLOCK" ]; then ok "T1.7a the LUKS stage block extracts"; else no "T1.7a could not extract the LUKS stage from $CLOUD_INIT — every assertion below it would be vacuous"; fi
# A POSITIVE CONTROL ON WHAT THE RANGE ACTUALLY CAPTURED. `-n` is satisfied by a range that
# stopped after two harmless lines AND by one that swallowed half the file because its terminator
# moved — and the two negative greps below are vacuous on the first and misleading on the second.
#
# BOUND IT AT BOTH ENDS, which is the only form that discriminates. An earlier pair of controls
# here — "at least 5 device ops" and "fewer lines than the file" — passed against BOTH a truncated
# range and a run-away one: awk restarts a range, so an unmatched terminator yields a big block
# that is still smaller than the file, and a widened block contains MORE operations, not fewer.
# The first and last lines of the block are the two facts that actually pin it.
_ops="$(printf '%s\n' "$LUKS_BLOCK" | grep -cE '^[[:space:]]*(mount|mountpoint|mkfs|cryptsetup)')"
if [ "$_ops" -ge 5 ]; then ok "T1.7a2 the extracted block carries the device operations (${_ops} >= 5)"; else no "T1.7a2 the extraction captured only ${_ops} device operations — the range is truncated and T1.7b/c are vacuous"; fi
_first="$(printf '%s\n' "$LUKS_BLOCK" | head -1)"
_last="$(printf '%s\n' "$LUKS_BLOCK" | tail -1)"
case "$_first" in *"bash -s <<'LUKSEOF'") _fok=1 ;; *) _fok=0 ;; esac
case "$_last"  in *LUKSEOF)               _lok=1 ;; *) _lok=0 ;; esac
if [ "$_fok" -eq 1 ] && [ "$_lok" -eq 1 ]; then ok "T1.7a3 the block is bounded by its own opener and terminator"; else no "T1.7a3 the extracted block is not bounded by the LUKS heredoc (first='${_first}' last='${_last}') — the range drifted and T1.7b/c grade the wrong text"; fi
printf '%s\n' "$LUKS_BLOCK" > /tmp/.ilt-block.$$ 2>/dev/null || true
# `[^|]*` CANNOT SPAN AN EARLIER `||`, and every mount in this stage is written as
# `mountpoint -q X || mount …`. So the swallow-form that would actually appear in this file was
# the one form the pattern could not see; the arm was green against the only mutation that
# matters. `.*` sees the whole line, and the trailing anchor still pins the swallow to the END.
if [ -s /tmp/.ilt-block.$$ ] && ! grep -qE '^[[:space:]]*(mount|mountpoint|mkfs|cryptsetup).*\|\|[[:space:]]*(true|:)[[:space:]]*$' /tmp/.ilt-block.$$; then ok "T1.7b no mount/mkfs/cryptsetup step is suffixed with || true"; else no "T1.7b a mount/mkfs/cryptsetup step swallows its failure"; fi
# ANCHORED ON SYNTAX, NOT ON THE BARE TOKEN. The stage's own comment says "No `|| true`, no
# `|| :`, and no `set +e`" — so a bare-literal grep matches the SUT's documentation of the rule and
# reports a violation that does not exist. This is the collision `cq-assert-anchor-not-bare-token`
# names, and it fired here on the first run: a comment line starts with `#`, a statement does not.
if [ -s /tmp/.ilt-block.$$ ] && ! grep -qE '^[[:space:]]*set[[:space:]]+\+e' /tmp/.ilt-block.$$; then ok "T1.7c the stage never disarms errexit"; else no "T1.7c the LUKS stage contains a live 'set +e' statement"; fi
rm -f /tmp/.ilt-block.$$

# T1.8 `nofail` is RETAINED in every fstab line the stage writes. A strict fstab on a host with no
# SSH and no console converts a slow attach into an unrecoverable boot wedge; loud failure belongs
# in the Redis unit's ExecStartPre, not in a line that bricks the boot before anything can report.
# TWO ARMS, because counting the GOOD lines is not the same claim as "there is no BAD one": a
# fourth fstab write that omits nofail leaves the count at 3 and the boot wedged.
_fstab_lines="$(grep -cE 'echo "\$(DEV|MAPPER) /mnt/data ext4 defaults,nofail 0 2"' "$CLOUD_INIT")"
if [ "$_fstab_lines" -eq 3 ]; then ok "T1.8a all three fstab writes retain nofail"; else no "T1.8a expected 3 nofail-carrying fstab writes (one per mounting arm), found ${_fstab_lines}"; fi
_fstab_all="$(grep -cE '/mnt/data[[:space:]]+ext4[[:space:]]' "$CLOUD_INIT")"
_fstab_bad="$(grep -E '/mnt/data[[:space:]]+ext4[[:space:]]' "$CLOUD_INIT" | grep -cv 'nofail' || true)"
if [ "$_fstab_bad" -eq 0 ]; then ok "T1.8b NO /mnt/data fstab line anywhere in the file omits nofail (${_fstab_all} checked)"; else no "T1.8b ${_fstab_bad} of ${_fstab_all} /mnt/data fstab lines omit nofail — a strict fstab wedges the boot on a host with no SSH and no console"; fi

# T1.9 THE EXT4 ARM MUST STILL PERMIT REDIS TO START. This is the regression test for the
# ExecStartPre deadlock: a ONE-state gate demanding /dev/mapper/inngest-redis unconditionally
# would refuse to start Redis on the PRE-recut host — whose volume is plaintext ext4 today — and
# deadlock the very cutover this apparatus exists to enable.
# COMMENT-STRIPPED VIEWS. T1.9a-c grepped these two files raw, and T1.9c's needle was a phrase that
# lives only in a COMMENT — so commenting out the guard's entire host-identity refusal (a P0 of
# this delta: absent allows / unreadable refuses / no DOPPLER_PROJECT refuses) left the suite at
# `23 passed, 0 failed`. MEASURED by prefixing every DOPPLER_PROJECT line with `#`. A systemd
# directive and a shell statement are both `#`-commentable, so presence in the file is not
# evidence the machine ever reads them. `cq-assert-anchor-not-bare-token`.
_UNIT_CODE="$(grep -vE '^[[:space:]]*#' "$REDIS_UNIT" || true)"
_BOOT_CODE="$(grep -vE '^[[:space:]]*#' "$REDIS_BOOTSTRAP" || true)"

if printf '%s\n' "$_UNIT_CODE" | grep -qF 'ExecStartPre=/usr/local/bin/inngest-redis-mount-guard.sh'; then ok "T1.9a the Redis unit carries the mount guard (live directive, not a commented one)"; else no "T1.9a inngest-redis.service has no live ExecStartPre mount guard"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -qF 'if [ -e "$MAPPER" ]; then'; then ok "T1.9b the guard is TWO-state (mapper-conditional), not a bare mapper demand"; else no "T1.9b the mount guard is not mapper-conditional — it would refuse to start Redis on the pre-recut ext4 host"; fi
# T1.9c The identity read FAILS CLOSED. `proj=""` used to fall through to the `|| exit 0` written
# for the web host, so a dedicated host whose env file failed to write — the exact host this guard
# exists for — was waved through. Anchored on the refusal, which is the thing that can be deleted.
# FOUR SEPARATE VERDICTS, and the exit code bound to ITS OWN BRANCH.
#
# The first cut fused these into one `_id_ok` boolean and asserted the exit codes with
# `grep -c '^exit 1$' >= 3` over the WHOLE FILE. inngest-redis-bootstrap.sh has NINE bare `exit 1`
# lines against a floor of three — six units of slack on the exact axis the comment claimed to
# guard. MEASURED: flipping the unreadable-envfile refusal to `exit 0`, or the no-DOPPLER_PROJECT
# refusal to `exit 0`, or BOTH, each left the suite at 23 passed, 0 failed while printing
# `ok - T1.9c … each exiting non-zero` — a verdict line asserting as a pass a statement false in
# both halves. A `grep -c` is evidence about a file, never about a branch.
#
# Each refusal is now located by its own message and the FOLLOWING non-blank line must be `exit 1`.
_next_stmt() {  # _next_stmt <needle> — the first non-blank executable line after the match
  printf '%s\n' "$_BOOT_CODE" | grep -A3 -F "$1" | tail -n +2 | grep -vE '^\s*$' | head -1 | sed 's/^[[:space:]]*//'
}
if printf '%s\n' "$_BOOT_CODE" | grep -qF 'DOPPLER_PROJECT:-'; then ok "T1.9c1 the guard actually READS the host identity"; else no "T1.9c1 the guard never reads DOPPLER_PROJECT — it cannot know which host it is on"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -qF 'if [ -z "$proj" ]; then'; then ok "T1.9c2 an EMPTY identity is its own branch"; else no "T1.9c2 an empty DOPPLER_PROJECT is not branched on — it falls through to the web-host exit 0"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -qF '[ ! -r "$ENVFILE" ]'; then ok "T1.9c3 an UNREADABLE env file is its own branch"; else no "T1.9c3 an unreadable env file is not branched on"; fi
_x_unreadable="$(_next_stmt 'exists but is unreadable')"
_x_noproj="$(_next_stmt 'carries no DOPPLER_PROJECT')"
if [ "$_x_unreadable" = "exit 1" ] && [ "$_x_noproj" = "exit 1" ]; then
  ok "T1.9c4 BOTH identity refusals exit non-zero (bound to their own branch, not a file-wide count)"
else
  no "T1.9c4 an identity refusal does not exit non-zero — it fails OPEN on the host it gates (after-unreadable='${_x_unreadable}' after-no-project='${_x_noproj}')"
fi

# T1.10 expect_luks is threaded into BOTH device readers, or the post-recut refusal is armed in
# only one of them and an ext4 signature after a recut mounts plaintext from the other.
# PER-WINDOW, NOT WHOLE-FILE. A `-ge 3` over the whole file is satisfied by three occurrences in
# ONE reader and none in the other — which is exactly the defect the arm names ("armed in only one
# of them"). Split the file at the reopen script's own marker and require a hit on each side.
# The split point is the runcmd stage's own heredoc opener: everything above it is the write_files
# region that ships /usr/local/bin/inngest-luks-open.sh (the BOOT-2 reader), everything from it
# down is the first-boot runcmd stage. Anchoring on the reopen unit's NAME does not split them —
# the unit is declared above the runcmd, so one side got both readers and the other got neither,
# which is precisely the vacuity this arm is supposed to detect.
_split="$(grep -n "bash -s <<'LUKSEOF'" "$CLOUD_INIT" | head -1 | cut -d: -f1)"
if [ -n "$_split" ]; then
  _expect_reopen="$(head -n "$((_split - 1))" "$CLOUD_INIT" | grep -cF 'inngest_expect_luks')"
  _expect_runcmd="$(tail -n +"$_split" "$CLOUD_INIT" | grep -cF 'inngest_expect_luks')"
  if [ "$_expect_runcmd" -ge 1 ] && [ "$_expect_reopen" -ge 1 ]; then ok "T1.10 expect_luks reaches BOTH device readers (runcmd ${_expect_runcmd}x, reopen ${_expect_reopen}x)"; else no "T1.10 expect_luks is threaded into only one reader (runcmd ${_expect_runcmd}x, reopen ${_expect_reopen}x) — an ext4 signature after a recut would mount plaintext from the other"; fi
else
  no "T1.10 could not locate the runcmd LUKS stage in $CLOUD_INIT — the per-window split is vacuous"
fi

# T1.11 THE SEQUENCING INSTRUCTION. `inngest_expect_luks` and `format` act at different moments —
# `format` governs what a CREATE produces (once, on the recut apply); expect_luks governs what
# every BOOT refuses. Flipping expect_luks in the same change that drops `format` makes ARM 1
# refuse the still-ext4 volume at the very next host replace, so /mnt/data never mounts and the
# dedicated host comes up with no store. The variable comment said to do exactly that. Pinned
# here because the instruction is what the next author will follow, and it is not executable.
if grep -qF 'MUST NOT FLIP IN THE SAME CHANGE' "$VARIABLES_TF"; then ok "T1.11a the expect_luks comment warns against the flip that empties /mnt/data"; else no "T1.11a the expect_luks sequencing warning is gone — the next author will flip it with format and take the store out"; fi
# Grep the SUPERSEDED wording, not the new one: a residual count over the new text is blind to a
# partial revert that restores the old instruction alongside it.
#
# ANCHORED ON THE INSTRUCTION'S OPENING LINE, not on the bare phrase. The correction above QUOTES
# the phrase it retracts — that is the append-only convention working — so a `grep -qF` for the
# fragment matches the retraction itself and reports a violation that does not exist. It fired
# that way on the first run. `cq-assert-anchor-not-bare-token`, in the one file in this branch
# whose whole subject is that class.
if grep -qE '^# This flips on the recut branch' "$VARIABLES_TF"; then no "T1.11b the superseded one-decision instruction is back as a live directive in variables.tf"; else ok "T1.11b the superseded one-decision instruction is not present as a directive"; fi
# And the default must still be false at merge — the whole ordering rests on it.
if grep -A4 'variable "inngest_expect_luks"' "$VARIABLES_TF" | grep -qE '^\s*default\s*=\s*false\s*$'; then ok "T1.11c inngest_expect_luks still defaults to false at merge"; else no "T1.11c inngest_expect_luks no longer defaults to false — the next host replace would refuse the ext4 mount"; fi

# T1.12 THE EXIT TRAP MUST NOT TREAT SUCCESS AS FAILURE. Driven, not grepped — the trap machinery
# is extracted verbatim and run both ways, which needs no root and so belongs in THIS tier rather
# than the loopback one. It exists because the shipped handler ended in an unconditional `exit 1`
# while the stage deliberately never disarms the trap: every successful LUKS boot re-entered the
# handler, phoned home `inngest-luks-FAILED`, and exited 1, so cloud-init recorded a healthy stage
# as a failed runcmd item and the only off-box signal said the opposite of the truth. Found by the
# loopback suite's first real execution, where all three mount arms did their work correctly
# (device mounted, header written, canary intact) and still returned rc 1.
_T12="$(mktemp -d)"; trap 'rm -rf "$_T12"' EXIT
{
  printf 'set -euo pipefail
STAGE=luks_open
INNGEST_LUKS_DETAIL=/dev/null
EXPECT_LUKS=false
'
  printf 'luks_emit() { echo "EMIT stage=$1 rc=$2"; }
'
  awk '/^    luks_err\(\) \{/,/^    trap luks_err EXIT$/' "$CLOUD_INIT" \
    | sed -e 's/^    //' -e 's/\$\${/${/g' -e 's|/usr/local/bin/inngest-boot-phone-home.sh|echo PHONE|'
} > "$_T12/trap.sh"
# Non-vacuity: the extraction must have captured the handler AND the arming line.
if grep -q '^luks_err() {' "$_T12/trap.sh" && grep -q '^trap luks_err EXIT$' "$_T12/trap.sh"; then ok "T1.12a the EXIT-trap machinery extracts (handler + arming line)"; else no "T1.12a could not extract the EXIT trap — T1.12b/c would be vacuous"; fi
cp "$_T12/trap.sh" "$_T12/ok.sh"; printf 'exit 0\n' >> "$_T12/ok.sh"
_rc=0; _out="$(bash "$_T12/ok.sh" 2>&1)" || _rc=$?
if [ "$_rc" -eq 0 ] && ! printf '%s' "$_out" | grep -q 'inngest-luks-FAILED'; then ok "T1.12b a SUCCESSFUL stage exits 0 and does not phone home a failure"; else no "T1.12b a successful stage exited rc=${_rc} / phoned home a failure — every healthy boot would report itself failed (out: ${_out})"; fi
cp "$_T12/trap.sh" "$_T12/bad.sh"; printf 'false\n' >> "$_T12/bad.sh"
_rc=0; _out="$(bash "$_T12/bad.sh" 2>&1)" || _rc=$?
if [ "$_rc" -ne 0 ] && printf '%s' "$_out" | grep -q 'inngest-luks-FAILED'; then ok "T1.12c a FAILED stage still exits non-zero and phones home"; else no "T1.12c the rc guard is disarmed — a failed stage exited rc=${_rc} without phoning home (out: ${_out})"; fi

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Self-contained: bash builtins and this suite's own counters only. A floor that lives in a helper
# is silenced by the same move that silences the arms it guards.
if [ "$executed" -lt 26 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 26. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 26)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks.test.sh (structural): ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
