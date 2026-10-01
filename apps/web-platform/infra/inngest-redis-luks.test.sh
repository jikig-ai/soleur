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
_split6="$(grep -n "bash -s <<'LUKSEOF'" "$CLOUD_INIT" | sed -n '1p' | cut -d: -f1)"
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
_first="$(printf '%s\n' "$LUKS_BLOCK" | sed -n '1p')"
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
# further fstab write that omits nofail leaves the good count intact and the boot wedged.
# (#6894) Every writer now goes through `fstab_set`, which REPLACES the mountpoint's line: four for
# /mnt/data (the pointer arm plus the three pre-cutover mounting arms) and one for the staging mount.
_fstab_lines="$(grep -cE 'fstab_set /mnt/data "\$(DEV|MAPPER) /mnt/data ext4 defaults,nofail 0 2"' "$CLOUD_INIT")"
if [ "$_fstab_lines" -eq 4 ]; then ok "T1.8a all four /mnt/data fstab writes go through fstab_set and retain nofail"; else no "T1.8a expected 4 nofail-carrying fstab_set writes for /mnt/data (pointer arm + three pre-cutover arms), found ${_fstab_lines}"; fi
_fstab_stg="$(grep -cE 'fstab_set /mnt/data-luks "\$STAGING_MAPPER /mnt/data-luks ext4 defaults,nofail 0 2"' "$CLOUD_INIT")"
if [ "$_fstab_stg" -eq 1 ]; then ok "T1.8a2 the staging mount's fstab write goes through fstab_set and retains nofail"; else no "T1.8a2 expected 1 nofail-carrying fstab_set write for /mnt/data-luks, found ${_fstab_stg}"; fi
_fstab_all="$(grep -cE '/mnt/data(-luks)?[[:space:]]+ext4[[:space:]]' "$CLOUD_INIT")"
_fstab_bad="$(grep -E '/mnt/data(-luks)?[[:space:]]+ext4[[:space:]]' "$CLOUD_INIT" | grep -cv 'nofail' || true)"
if [ "$_fstab_bad" -eq 0 ]; then ok "T1.8b NO /mnt/data or /mnt/data-luks fstab line anywhere in the file omits nofail (${_fstab_all} checked)"; else no "T1.8b ${_fstab_bad} of ${_fstab_all} fstab lines omit nofail — a strict fstab wedges the boot on a host with no SSH and no console"; fi
# T1.8c (Guard 4 row 6) NO APPEND-IF-ABSENT WRITER SURVIVES. Every earlier writer was
# `grep -q ' /mnt/data ' /etc/fstab || echo … >> /etc/fstab`, so after a store swap the OLD line
# stayed, and won the next boot. The shape is asserted absent over the whole file, not the stage.
if grep -qE "grep -q ' /mnt/data(-luks)? ' /etc/fstab \|\|" "$CLOUD_INIT"; then no "T1.8c an append-if-absent /mnt/data fstab writer is back — a swapped store keeps its old line and the old line wins the next boot"; else ok "T1.8c no append-if-absent fstab writer for /mnt/data or /mnt/data-luks"; fi
# T1.8d fstab_set REPLACES and then asserts EXACTLY ONE. Both halves, field-exact on the mountpoint
# ($2), so /mnt/data never matches /mnt/data-luks.
_FS_DEF="$(awk '/^    fstab_set\(\) \{$/,/^    \}$/' "$CLOUD_INIT")"
if printf '%s\n' "$_FS_DEF" | grep -cF "\$2 != mp" >/dev/null; then ok "T1.8d1 fstab_set drops the mountpoint's existing line before writing (replace, not append)"; else no "T1.8d1 fstab_set does not filter the mountpoint's existing line — it appends"; fi
if printf '%s\n' "$_FS_DEF" | grep -cF '[ "$_fs_n" -eq 1 ] ||' >/dev/null; then ok "T1.8d2 fstab_set asserts exactly one line for the mountpoint after writing"; else no "T1.8d2 fstab_set does not assert exactly one line"; fi
if grep -qE '^    _fstab_n="\$\(awk .\$1 !~ /\^#/ && \$2 == "/mnt/data". /etc/fstab \| wc -l\)"$' "$CLOUD_INIT" \
   && grep -qF '[ "$_fstab_n" -eq 1 ] ||' "$CLOUD_INIT"; then ok "T1.8e stage=fstab asserts EXACTLY ONE /mnt/data line, not merely one-or-more"; else no "T1.8e stage=fstab no longer asserts exactly one /mnt/data line"; fi

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

if printf '%s\n' "$_UNIT_CODE" | grep -cF 'ExecStartPre=/usr/local/bin/inngest-redis-mount-guard.sh' >/dev/null; then ok "T1.9a the Redis unit carries the mount guard (live directive, not a commented one)"; else no "T1.9a inngest-redis.service has no live ExecStartPre mount guard"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -cF 'if [ -e "$MAPPER" ]; then' >/dev/null; then ok "T1.9b the guard is TWO-state (mapper-conditional), not a bare mapper demand"; else no "T1.9b the mount guard is not mapper-conditional — it would refuse to start Redis on the pre-recut ext4 host"; fi
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
  printf '%s\n' "$_BOOT_CODE" | grep -A3 -F "$1" | tail -n +2 | grep -vE '^\s*$' | sed -n '1p' | sed 's/^[[:space:]]*//'
}
if printf '%s\n' "$_BOOT_CODE" | grep -cF 'DOPPLER_PROJECT:-' >/dev/null; then ok "T1.9c1 the guard actually READS the host identity"; else no "T1.9c1 the guard never reads DOPPLER_PROJECT — it cannot know which host it is on"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -cF 'if [ -z "$proj" ]; then' >/dev/null; then ok "T1.9c2 an EMPTY identity is its own branch"; else no "T1.9c2 an empty DOPPLER_PROJECT is not branched on — it falls through to the web-host exit 0"; fi
if printf '%s\n' "$_BOOT_CODE" | grep -cF '[ ! -r "$ENVFILE" ]' >/dev/null; then ok "T1.9c3 an UNREADABLE env file is its own branch"; else no "T1.9c3 an unreadable env file is not branched on"; fi
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
_split="$(grep -n "bash -s <<'LUKSEOF'" "$CLOUD_INIT" | sed -n '1p' | cut -d: -f1)"
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
if grep -A4 'variable "inngest_expect_luks"' "$VARIABLES_TF" | grep -cE '^\s*default\s*=\s*false\s*$' >/dev/null; then ok "T1.11c inngest_expect_luks still defaults to false at merge"; else no "T1.11c inngest_expect_luks no longer defaults to false — the next host replace would refuse the ext4 mount"; fi

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
if [ "$_rc" -eq 0 ] && ! printf '%s' "$_out" | grep -c 'inngest-luks-FAILED' >/dev/null; then ok "T1.12b a SUCCESSFUL stage exits 0 and does not phone home a failure"; else no "T1.12b a successful stage exited rc=${_rc} / phoned home a failure — every healthy boot would report itself failed (out: ${_out})"; fi
cp "$_T12/trap.sh" "$_T12/bad.sh"; printf 'false\n' >> "$_T12/bad.sh"
_rc=0; _out="$(bash "$_T12/bad.sh" 2>&1)" || _rc=$?
if [ "$_rc" -ne 0 ] && printf '%s' "$_out" | grep -c 'inngest-luks-FAILED' >/dev/null; then ok "T1.12c a FAILED stage still exits non-zero and phones home"; else no "T1.12c the rc guard is disarmed — a failed stage exited rc=${_rc} without phoning home (out: ${_out})"; fi

# ═══ TIER 1b — the delivered bytes, rendered as Terraform renders them (#6894) ═══════════════
# T1.13 EVERY write_files SHELL SCRIPT PARSES AS DELIVERED. Terraform's template unescape is exactly
# two transforms — dollar-dollar-brace to dollar-brace, percent-percent-brace to percent-brace — and
# NOTHING ELSE. In particular a doubled dollar NOT followed by a brace is left doubled, and bash then
# reads it as its own PID. The #7695 boot-reopen script was written with doubled dollars throughout
# and failed with `syntax error near unexpected token` on the live host on every boot (Better Stack,
# 2026-09-17 11:38:31, host soleur-inngest), while its arming marker reported success. The loopback
# suite's BOOT2 arm rendered the block with a global doubled-dollar-to-dollar sed, which Terraform
# never performs, so it graded bytes that were never delivered. This arm renders ONLY the two real
# transforms. Its outside anchor is a real `templatefile()` render (measured 2026-09-18: identical).
_T13="$(mktemp -d)"
_t13_n=0; _t13_bad=""
_t13_render() { sed -e 's/\$\${/${/g' -e 's/%%{/%{/g' \
  -e 's/\${inngest_volume_id}/106261946/g' -e 's/\${inngest_luks_volume_id}/106999999/g' \
  -e 's/\${inngest_expect_luks}/false/g' -e 's/\${[a-z_][a-z_0-9]*}/TEMPLATE_VALUE/g'; }
# split write_files into one file per content block: a `  - path:` line, then `    content: |`, then
# every line indented at least six spaces, ended by the first line at indent four
awk -v out="${_T13:?}" '
  /^  - path: /{ path=$3; next }
  path!="" && /^    content: \|$/ { n++; f=out "/wf." n; print path > (f ".path"); inblk=1; next }
  inblk && /^      / { sub(/^      /, ""); print > f; next }
  inblk && /^$/ { print "" > f; next }
  inblk { inblk=0; path="" }
' "$CLOUD_INIT"
for _wf in "${_T13:?}"/wf.*; do
  case "$_wf" in *.path|*.r) continue ;; esac
  head -1 "$_wf" | grep -cE '^#!.*(ba)?sh' >/dev/null || continue
  _t13_n=$((_t13_n + 1))
  _t13_render < "$_wf" > "$_wf.r"
  if ! bash -n "$_wf.r" 2>/dev/null; then _t13_bad="${_t13_bad} $(cat "$_wf.path")"; fi
done
if [ "$_t13_n" -ge 4 ]; then ok "T1.13a found ${_t13_n} write_files shell scripts to render (floor 4)"; else no "T1.13a found only ${_t13_n} write_files shell scripts — the splitter is broken and T1.13b is vacuous"; fi
if [ -z "$_t13_bad" ]; then ok "T1.13b every write_files shell script PARSES as Terraform renders it (${_t13_n} checked)"; else no "T1.13b unparseable as delivered:${_t13_bad} — Terraform leaves a doubled dollar doubled, bash reads it as its PID"; fi
# Positive control: the render MUST be able to see the defect it exists for.
printf '#!/usr/bin/env bash\n_i=0; _i=$$((_i+1))\n' | _t13_render > "${_T13:?}/ctl.r"
if bash -n "${_T13:?}/ctl.r" 2>/dev/null; then no "T1.13c POSITIVE CONTROL: the render let a doubled-dollar arithmetic expansion parse — it is rewriting doubled dollars and cannot see the #7695 defect"; else ok "T1.13c positive control: the #7695 shape fails to parse under this render"; fi
rm -rf "${_T13:?}"
# T1.14 NO DOUBLED DOLLAR BEFORE AN IDENTIFIER OR PAREN, outside a comment, anywhere in the file.
# The lint form of T1.13: it names the site instead of the script.
_t14="$(grep -nE '\$\$[A-Za-z_(0-9?#@*!-]' "$CLOUD_INIT" | grep -vE '^[0-9]+:[[:space:]]*#' || true)"
if [ -z "$_t14" ]; then ok "T1.14 no doubled-dollar expansion in any delivered line (bash would read the PID)"; else no "T1.14 doubled-dollar expansions survive — each renders literally and bash reads the PID: $(printf '%s' "$_t14" | head -3 | tr '\n' ' ')"; fi

# ═══ TIER 2 — Guard 1: nothing writes to a device carrying data (#6894) ═════════════════════
# THE ASSEMBLY IS DERIVED, NOT LISTED. Every `blkid` call in the two device readers (the runcmd
# stage and the boot-reopen script) is found by walking the file and must be CLASSIFIED: its own rc
# captured into a variable, and that variable checked against exactly 0-or-2 on the next statement.
# An unclassified site is a RED, which is what makes "a second reader that skips the probe" visible
# (mutation row 3). The site count here is a floor, never the definition.
_G1_STAGE="$(awk '/doppler run --project soleur-inngest --config prd -- bash -s <<.LUKSEOF.$/{f=1;next} /^    LUKSEOF$/{f=0} f' "$CLOUD_INIT")"
_G1_REOPEN="$(awk '/^  - path: \/usr\/local\/bin\/inngest-luks-open\.sh$/{f=1;next} f&&/^    content: \|$/{c=1;next} c&&/^    owner:/{exit} c' "$CLOUD_INIT")"
_g1_sites=0; _g1_bad=""
_g1_classify() {  # _g1_classify <label> <text>
  local label="$1" text="$2" prev="" rcvar="" line
  while IFS= read -r line; do
    case "$line" in *'#'*blkid*) [[ "$line" =~ ^[[:space:]]*# ]] && continue ;; esac
    if [ -n "$rcvar" ]; then
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      if [[ "$line" == *"{ [ \"\$${rcvar}\" -eq 0 ] || [ \"\$${rcvar}\" -eq 2 ]; } ||"* ]]; then :; else _g1_bad="${_g1_bad} ${label}:rc-not-checked(${rcvar})"; fi
      rcvar=""; continue
    fi
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # THE CALL FORM, never the bare word: `blkid` followed by whitespace and a flag. The word also
    # appears in stage names (blkid_probe), marker fields (blkid_type=) and prose, none of which
    # is a probe (cq-assert-anchor-not-bare-token). A bare `blkid -o` in a rogue reader still matches.
    [[ "$line" =~ (^|[[:space:]\(\"/])blkid[[:space:]]+- ]] || continue
    _g1_sites=$((_g1_sites + 1))
    if [[ "$line" =~ ^[[:space:]]*[A-Z_]+=\"\$\(/usr/sbin/blkid(\ -p)?\ -o\ value\ -s\ TYPE\ \"[^\"]+\"\ 2\>/dev/null\)\"\ \|\|\ (_[a-z_]+)=\$\?$ ]]; then
      rcvar="${BASH_REMATCH[2]}"
      # a probe of a MAPPER must bypass the cache: across an abort-and-retry the cached type is stale
      if [[ "$line" == *'"$MAPPER"'* || "$line" == *'"$STAGING_MAPPER"'* ]] && [[ "$line" != *'blkid -p '* ]]; then _g1_bad="${_g1_bad} ${label}:mapper-probe-without--p"; fi
    else
      _g1_bad="${_g1_bad} ${label}:UNCLASSIFIED[$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-60)]"
    fi
  done <<< "$text"
}
_g1_classify stage "$(printf '%s\n' "$_G1_STAGE" | sed 's/\$\${/${/g')"
_g1_classify reopen "$(printf '%s\n' "$_G1_REOPEN" | sed -e 's/^      //' -e 's/\$\${/${/g')"
if [ "$_g1_sites" -ge 6 ]; then ok "G1.a found ${_g1_sites} blkid probe sites across both device readers (floor 6)"; else no "G1.a found only ${_g1_sites} blkid sites — the walk is not reaching a reader"; fi
if [ -z "$_g1_bad" ]; then ok "G1.b every blkid site captures its own rc and checks it against exactly 0-or-2; every mapper probe bypasses the cache"; else no "G1.b unclassified or unchecked probe sites:${_g1_bad}"; fi
# Positive control: a second reader that skips the capture must be caught.
_g1_sites=0; _g1_bad=""
_g1_classify ctl 'BLK_TYPE="$(/usr/sbin/blkid -o value -s TYPE "$DEV" 2>/dev/null)" || _blk_rc=$?
{ [ "$_blk_rc" -eq 0 ] || [ "$_blk_rc" -eq 2 ]; } || exit 1
T2="$(/usr/sbin/blkid -o value -s TYPE "$X")"'
if [[ "$_g1_bad" == *UNCLASSIFIED* ]]; then ok "G1.c positive control: an uncaptured second probe is flagged UNCLASSIFIED"; else no "G1.c POSITIVE CONTROL: an uncaptured second probe was not flagged — G1.b is vacuous"; fi
# G1.d the privilege assertion precedes the FIRST probe in each reader (measurements.md §1).
_g1_order() { printf '%s\n' "$1" | awk '/id -u\)" -eq 0 \]/ && !p {p=NR} /\/usr\/sbin\/blkid/ && !b {b=NR} END { exit !(p && b && p < b) }'; }
if _g1_order "$_G1_STAGE" && _g1_order "$_G1_REOPEN"; then ok "G1.d both readers assert root BEFORE their first blkid (unprivileged blkid reads a populated device as blank)"; else no "G1.d a device reader probes before asserting root — rc 2 from a Permission denied reads as blank and takes the luksFormat arm"; fi
# G1.e mkfs targets ONLY a mapper, and only AFTER the luksOpen that creates it (mutation row 6).
_g1_mkfs_bad="$(printf '%s\n' "$_G1_STAGE" | grep -E '^[[:space:]]*mkfs' | grep -vE 'mkfs\.ext4 -q "\$(MAPPER|STAGING_MAPPER)"' || true)"
if [ -z "$_g1_mkfs_bad" ]; then ok "G1.e every mkfs in the stage targets a mapper, never a raw device"; else no "G1.e an mkfs targets something other than a mapper: ${_g1_mkfs_bad}"; fi
_stg_open="$(printf '%s\n' "$_G1_STAGE" | grep -nE '^[[:space:]]*\[ -e "\$STAGING_MAPPER" \] \|\| printf' | sed -n '1p' | cut -d: -f1)"
_stg_mkfs="$(printf '%s\n' "$_G1_STAGE" | grep -nE '^[[:space:]]*mkfs\.ext4 -q "\$STAGING_MAPPER"' | sed -n '1p' | cut -d: -f1)"
if [ -n "$_stg_open" ] && [ -n "$_stg_mkfs" ] && [ "$_stg_open" -lt "$_stg_mkfs" ]; then ok "G1.f the staging mkfs comes after the staging luksOpen (line ${_stg_open} < ${_stg_mkfs})"; else no "G1.f staging mkfs is not after its luksOpen (open=${_stg_open:-none} mkfs=${_stg_mkfs:-none})"; fi
# G1.g the staging arm never opens the CANONICAL mapper name: the Redis mount guard keys on it.
_stg_region="$(printf '%s\n' "$_G1_STAGE" | awk '/STAGE=staging_wait/{f=1} f')"
if printf '%s\n' "$_stg_region" | grep -cE 'cryptsetup luksOpen .* inngest-redis[[:space:]]|cryptsetup luksOpen .* inngest-redis[[:space:]]*2>>' >/dev/null; then no "G1.g the staging arm opens the canonical inngest-redis name — it would trip the Redis guard's mapper-open state"; else ok "G1.g the staging arm opens only the non-canonical inngest-redis-staging name"; fi

# ═══ TIER 3 — Guard 4: the pointer decides, never the signature (#6894) ════════════════════
# THE POPULATION IS DERIVED. Every line in a DELIVERED artifact that names the pointer is found by
# walking the tree and must be classified into a known role; an unclassified site REDS. A reader the
# guard has never seen is exactly mutation row 4, and a hand-listed population would already be
# stale — a draft that named two sites was written before the cutover became the pointer's writer.
_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
_g4_bad=""; _g4_reads_stage=0; _g4_reads_reopen=0; _g4_total=0
_g4_stager_count=0; _g4_unit_inject=0; _g4_write_set=0; _g4_write_clear=0; _g4_fsm_read=0; _g4_dispatch_read=0
while IFS= read -r _hit; do
  _f="${_hit%%:*}"; _rest="${_hit#*:}"; _ln="${_rest%%:*}"; _txt="${_rest#*:}"
  [[ "$_txt" =~ ^[[:space:]]*# ]] && continue
  _g4_total=$((_g4_total + 1))
  case "$_txt" in
    *'n_inngest="$(printf'*'LUKS_ACTIVE_VOLUME_ID|'*) : ;;                                   # boot isolation admission
    *'POINTER="$${INNGEST_LUKS_ACTIVE_VOLUME_ID:-}"'*)                                        # resolver / reopen READ
      if awk -v n="$_ln" 'NR<n && /bash -s <<.LUKSEOF.$/{s=NR} NR<n && /^    LUKSEOF$/{s=0} END{exit !s}' "$_f"; then _g4_reads_stage=$((_g4_reads_stage + 1))
      elif awk -v n="$_ln" 'NR<n && /^  - path: \/usr\/local\/bin\/inngest-luks-open\.sh$/{s=NR} NR<n && /^  - path: / && !/inngest-luks-open\.sh/{s=0} END{exit !s}' "$_f"; then _g4_reads_reopen=$((_g4_reads_reopen + 1))
      else _g4_bad="${_g4_bad} ${_f##*/}:${_ln}:read-outside-both-readers"; fi ;;
    *"printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=%s\\n' \"\$POINTER\" >> /etc/default/inngest-luks"*) : ;;  # first-boot STAGER
    *'grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$POINTER" /etc/default/inngest-luks'*) : ;;      # stager's own check
    *'echo "FATAL: INNGEST_LUKS_ACTIVE_VOLUME_ID is set but is not a volume id'*) : ;;          # diagnostic text
    # ── #6894 cutover roles. The pointer gained a WRITER (the on-host FSM) and a second READER
    # (the dispatch's pre-write gate), so the population grew by five roles. Each is named here and
    # ASSERTED below (G4.g/G4.h) — a role that is merely allowlisted is a site nothing grades,
    # which is the shape this whole guard exists to refuse.
    *'--only-secrets INNGEST_LUKS_ACTIVE_VOLUME_ID'*) _g4_unit_inject=$((_g4_unit_inject + 1)) ;;  # unit INJECTION
    *'doppler secrets set INNGEST_LUKS_ACTIVE_VOLUME_ID "$2"'*) _g4_write_set=$((_g4_write_set + 1)) ;;    # FSM writer: set
    *'doppler secrets delete INNGEST_LUKS_ACTIVE_VOLUME_ID'*) _g4_write_clear=$((_g4_write_clear + 1)) ;; # FSM writer: clear
    *'current_pointer() { printf'*) _g4_fsm_read=$((_g4_fsm_read + 1)) ;;                          # FSM READ of the injected value
    *"grep -v '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' \"\$ENVFILE\""*) : ;;                                 # FSM stager: strip before rewrite
    *"printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=%s\\n' \"\$1\" >> \"\$tmp\""*) : ;;                       # FSM stager: write
    *'grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$1" "$ENVFILE"'*) : ;;                              # FSM stager: landed check
    *"n=\"\$(grep -c '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' \"\$ENVFILE\""*) _g4_stager_count=$((_g4_stager_count + 1)) ;;  # FSM stager: CARDINALITY
    *"! grep -q '^INNGEST_LUKS_ACTIVE_VOLUME_ID=' \"\$ENVFILE\""*) : ;;                              # FSM stager: removed check
    *'jq -e '"'"'has("INNGEST_LUKS_ACTIVE_VOLUME_ID")'"'"''*) _g4_dispatch_read=$((_g4_dispatch_read + 1)) ;; # dispatch pre-write READ
    *'::error::op='*'INNGEST_LUKS_ACTIVE_VOLUME_ID'*) : ;;                                        # operator-facing refusal text
    *) _g4_bad="${_g4_bad} ${_f##*/}:${_ln}:UNCLASSIFIED" ;;
  esac
done < <(cd "$_REPO" && git grep -nF 'INNGEST_LUKS_ACTIVE_VOLUME_ID' -- apps/web-platform/infra scripts .github/workflows \
          ':!*.test.sh' ':!*.test.ts' ':!tests/**' 2>/dev/null | sed "s|^|$_REPO/|")
if [ "$_g4_total" -ge 5 ]; then ok "G4.a found ${_g4_total} pointer sites in delivered artifacts (floor 5)"; else no "G4.a found only ${_g4_total} pointer sites — the walk is not reaching the tree"; fi
if [ -z "$_g4_bad" ]; then ok "G4.b every pointer site in a delivered artifact is classified (no reader the guard has never seen)"; else no "G4.b unclassified pointer sites:${_g4_bad} — classify each, or it is a reader nothing grades"; fi
if [ "$_g4_reads_stage" -eq 1 ] && [ "$_g4_reads_reopen" -eq 1 ]; then ok "G4.c the pointer is read by BOTH device readers exactly once (first-boot resolver and boot-reopen)"; else no "G4.c pointer reads: first-boot=${_g4_reads_stage} reopen=${_g4_reads_reopen} — each reader must apply it exactly once (mutation row 4)"; fi
# G4.g THE POINTER HAS EXACTLY ONE WRITER, and it is the on-host FSM. Two writers on a value that
# decides which device holds the store is the shape where a race decides where user data lives — and
# the dispatch deliberately does not write it, so its only pointer contact is a READ.
if [ "$_g4_write_set" -eq 1 ] && [ "$_g4_write_clear" -eq 1 ]; then ok "G4.g1 the pointer has exactly one set site and one clear site, both in the on-host FSM"; else no "G4.g1 pointer writers: set=${_g4_write_set} clear=${_g4_write_clear} — expected exactly one of each"; fi
_g4_disp_write="$(cd "$_REPO" && git grep -nE 'secrets (set|delete) INNGEST_LUKS_ACTIVE_VOLUME_ID' -- scripts .github/workflows 2>/dev/null || true)"
if [ -z "$_g4_disp_write" ]; then ok "G4.g2 no dispatch-side writer: the operator verbs read the pointer and never set it"; else no "G4.g2 a dispatch-side pointer WRITE exists (${_g4_disp_write}) — two writers decide where the store lives"; fi
# G4.g3 the FSM's own writes go through the pointer_cmd seam, never a bare doppler call in a phase.
# Scoped by the FUNCTION BODY, never by a line range (cq-cite-content-anchor-not-line-number): a
# range pins where the seam sits today, which is the one thing a refactor is allowed to change.
_g4_seam="$(awk '/^pointer_cmd\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$_REPO/apps/web-platform/infra/inngest-luks-cutover.sh")"
_g4_outside="$(awk '/^pointer_cmd\(\) \{/{f=1} f&&/^\}$/{f=0;next} !f' "$_REPO/apps/web-platform/infra/inngest-luks-cutover.sh" | grep -nE '^[^#]*doppler secrets (set|delete) INNGEST_LUKS_ACTIVE_VOLUME_ID' || true)"
_g4_inside="$(printf '%s\n' "$_g4_seam" | grep -cE '^[^#]*doppler secrets (set|delete) INNGEST_LUKS_ACTIVE_VOLUME_ID' || true)"
_g4_bare="$_g4_outside"
if [ -z "$_g4_bare" ] && [ "$_g4_inside" -eq 2 ]; then ok "G4.g3 both FSM pointer writes are inside the pointer_cmd seam, and no phase body writes it directly"; else no "G4.g3 seam writes=${_g4_inside} (expected 2); writes outside the seam: ${_g4_bare:-none}"; fi
# G4.h the pointer is INJECTED into the unit, and the FSM reads the injected value rather than
# shelling out — a read that needed its own credential would be a second failure mode mid-swap.
if [ "$_g4_unit_inject" -ge 1 ] && [ "$_g4_fsm_read" -eq 1 ]; then ok "G4.h the unit injects the pointer and the FSM reads it exactly once, from the environment"; else no "G4.h unit injection=${_g4_unit_inject} FSM reads=${_g4_fsm_read} — the FSM must read the injected value once"; fi
# The stager COUNTS rather than merely checking presence: systemd's EnvironmentFile is last-wins, so
# a second pointer line would silently decide which volume the boot-reopen unit opens.
if [ "$_g4_stager_count" -eq 1 ]; then ok "G4.j the envfile stager asserts pointer CARDINALITY, not presence (EnvironmentFile is last-wins)"; else no "G4.j the envfile stager no longer counts its pointer lines (sites=${_g4_stager_count})"; fi
if [ "$_g4_dispatch_read" -eq 1 ]; then ok "G4.i the dispatch's pointer gate reads presence from the NAME LIST (an absent name and a dead token are not the same answer)"; else no "G4.i dispatch pointer reads=${_g4_dispatch_read} — expected exactly one, via the name list"; fi

# G4.d the pointer arm REFUSES; it never formats and never falls back to the other volume.
_PTR_ARM="$(printf '%s\n' "$_G1_STAGE" | awk '/^    if \[ "\$MODE" = pointer \]; then$/{f=1;next} f&&/^    else$/{exit} f')"
if [ -n "$_PTR_ARM" ]; then ok "G4.d1 the pointer arm extracts"; else no "G4.d1 could not extract the pointer arm — G4.d2..d4 would be vacuous"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cE '^[[:space:]]*(mkfs|printf .* cryptsetup luksFormat)|luksFormat' >/dev/null; then no "G4.d2 the pointer arm can FORMAT — it would hand Redis an empty store and call it the store"; else ok "G4.d2 the pointer arm never formats and never runs mkfs"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cF '[ "$${BLK_TYPE:-}" = crypto_LUKS ] || {' >/dev/null; then ok "G4.d3 the pointer's device must CORROBORATE as crypto_LUKS (mutation row 3)"; else no "G4.d3 the crypto_LUKS corroboration is gone — the pointer could certify a plaintext device as the store"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cE '"\$DEV"' >/dev/null; then no "G4.d4 the pointer arm references the plaintext device — a fallback path exists (mutation row 2)"; else ok "G4.d4 the pointer arm never references the plaintext device (no fall-through)"; fi
# G4.e the resolver refuses both malformed pointer shapes rather than deriving a path from them.
_RES="$(printf '%s\n' "$_G1_STAGE" | awk '/^    STAGE=resolve$/{f=1} f&&/^    esac$/{print; exit} f')"
if printf '%s\n' "$_RES" | grep -cF '*[!0-9]*)' >/dev/null && printf '%s\n' "$_RES" | grep -cF '"$PLAIN_ID"|"$LUKS_ID")' >/dev/null && printf '%s\n' "$_RES" | grep -cE '^      \*\)$' >/dev/null; then ok "G4.e the resolver has explicit arms for non-numeric, own-id and third-id pointers"; else no "G4.e the resolver lost an arm (non-numeric / one-of-two-ids / third id)"; fi
# G4.f the arming marker MEASURES the unit, it does not trust enable's exit status.
if grep -qF '_reopen_state="$(systemctl is-active inngest-luks-open.service 2>/dev/null || true)"' "$CLOUD_INIT" \
   && grep -qF 'if [ "$_reopen_state" = "active" ]; then' "$CLOUD_INIT"; then ok "G4.f inngest-luks-reopen-armed is emitted only when the unit reads active"; else no "G4.f the reopen arming marker trusts enable --now again — it reported success on 2026-09-17 on a boot where the unit failed"; fi

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Raised 26 -> 51 by #6894, which added T1.8a2/c/d/e, T1.13, T1.14, G1.a-g and G4.a-f; 51 -> 56
# when the cutover FSM became the pointer's writer and the dispatch its second reader (G4.g1-g3/h/i). Derived from
# the measured count after the arms were final, not written ahead of them.
# Self-contained: bash builtins and this suite's own counters only. A floor that lives in a helper
# is silenced by the same move that silences the arms it guards.
if [ "$executed" -lt 57 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 57. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 57)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks.test.sh (structural): ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
