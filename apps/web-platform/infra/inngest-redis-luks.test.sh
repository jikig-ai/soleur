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
# loopback device and drives the REAL extracted cloud-init stage through every blkid arm (absent, blank,
# LUKS, foreign signature, pointer) plus a second simulated boot. THE SPLIT IS NOT COSMETIC. That suite needs root, so it is invoked as
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

# T1.6 The device-presence wait is the RULED counted bound (#10217, CTO rulings D1/D4/D7): a
# LITERAL 300 in BOTH bodies — no env seam, no INNGEST_LUKS_ATTACH_WAIT_S tunable — counted
# `sleep 1` passes that re-run the WHOLE `-b && size>0` predicate (never the clock), a probe once
# immediately, a `/usr/bin/timeout -k 2 10` wrap on every blockdev call, exactly ONE
# `udevadm settle --timeout=10` AFTER the loop — never per pass — and a post-settle re-probe so a
# device landing inside the settle window still converges (review round, PR #10228). blkid on an absent path returns rc 2, which the accept-0-or-2
# policy would otherwise route into the luksFormat arm — a volume merely slow to attach must never
# be read as blank; ~80s attach latency is measured on this estate, so the bound moved 30 -> 300.
# Tier 2 lowers this bound for its cases; this is the pin that keeps that a declared harness knob
# rather than an invented budget.
# PER-WINDOW, NOT A WHOLE-FILE COUNT — the same defect T1.10 carried. A `-ge 2` over the file is
# satisfied by two bounds in ONE reader and none in the other, which is precisely the state the arm
# names ("missing from one of the two"). Split at the runcmd stage's heredoc opener: above it is
# the write_files region shipping the boot-2 reopen script, below it the first-boot runcmd stage.
_split6="$(grep -n "bash -s <<'LUKSEOF'" "$CLOUD_INIT" | sed -n '1p' | cut -d: -f1)"
if [ -n "$_split6" ]; then
  _w6r="$(head -n "$((_split6 - 1))" "$CLOUD_INIT" | grep -cE '\[ "\$_i" -lt 300 \]|\[ "\$\$_i" -lt 300 \]')"
  _w6c="$(tail -n +"$_split6" "$CLOUD_INIT" | grep -cE '\[ "\$_i" -lt 300 \]|\[ "\$\$_i" -lt 300 \]')"
  if [ "$_w6r" -ge 1 ] && [ "$_w6c" -ge 1 ]; then ok "T1.6a BOTH device readers bound the attach wait at a literal 300s (reopen ${_w6r}x, runcmd ${_w6c}x)"; else no "T1.6a the 300s device-presence wait bound is missing from one of the two device readers (reopen ${_w6r}x, runcmd ${_w6c}x)"; fi
else
  no "T1.6a could not locate the runcmd LUKS stage in $CLOUD_INIT — the per-window split is vacuous"
fi
# THE MECHANISM IS PINNED PER EXTRACTED BODY, not per region — a region count is satisfied by a
# settle moved INSIDE the loop, which is exactly the per-pass shape the ruling rejected. Each body
# is lifted by its own indent (reopen payload 6, stage heredoc 4).
_wd_reopen="$(awk '/^      wait_dev\(\) \{$/{f=1} f{print} f&&/^      \}$/{exit}' "$CLOUD_INIT")"
_wd_stage="$(awk '/^    wait_dev\(\) \{$/{f=1} f{print} f&&/^    \}$/{exit}' "$CLOUD_INIT")"
if [ -n "$_wd_reopen" ] && [ -n "$_wd_stage" ]; then ok "T1.6b both wait_dev bodies extract (reopen + runcmd stage)"; else no "T1.6b a wait_dev body failed to extract — T1.6c..e are vacuous"; fi
# _wd_bad <body> — echoes defect tokens; EMPTY means the ruled shape. `grep -c` everywhere, never
# `grep -q` on a pipe: -q exits early and pipefail turns the producer's SIGPIPE into a fake defect.
_wd_bad() {
  local body="$1" loop dn sn bad=""
  loop="$(printf '%s\n' "$body" | awk '/while \[/{f=1} f{print} f&&/^[[:space:]]*done[[:space:]]*$/{exit}')"
  [ "$(printf '%s\n' "$body" | grep -cE '\[ "\$\$_i" -lt 300 \]|\[ "\$_i" -lt 300 \]')" -ge 1 ] || bad="${bad}literal-300-bound "
  [ "$(printf '%s\n' "$loop" | grep -cF 'sleep 1')" -ge 1 ] || bad="${bad}no-sleep-1-pass "
  [ "$(printf '%s\n' "$loop" | grep -cF '_i=$((_i+1))')" -ge 1 ] || bad="${bad}no-counted-pass "
  [ "$(printf '%s\n' "$loop" | grep -cF 'blockdev --getsize64 "$1"')" -ge 1 ] || bad="${bad}predicate-not-re-run-in-loop "
  [ "$(printf '%s\n' "$loop" | grep -c 'udevadm')" -eq 0 ] || bad="${bad}settle-INSIDE-loop "
  [ "$(printf '%s\n' "$body" | grep -cE 'udevadm settle --timeout=10')" -eq 1 ] || bad="${bad}settle-count!=1 "
  [ "$(printf '%s\n' "$body" | grep -cF 'timeout -k 2 10 /usr/sbin/blockdev')" -ge 3 ] || bad="${bad}probe-not-timeout-wrapped "
  dn="$(printf '%s\n' "$body" | grep -nE '^[[:space:]]*done[[:space:]]*$' | sed -n '1p' | cut -d: -f1)"
  sn="$(printf '%s\n' "$body" | grep -nE 'udevadm settle --timeout=10' | sed -n '1p' | cut -d: -f1)"
  { [ -z "$dn" ] || [ -z "$sn" ] || [ "$sn" -le "$dn" ]; } && bad="${bad}settle-not-AFTER-loop "
  # the post-settle re-probe must sit AFTER the settle line, not merely exist as a third probe
  [ "$(printf '%s\n' "$body" | sed -n "${sn:-0},\$p" | grep -cF 'timeout -k 2 10 /usr/sbin/blockdev')" -ge 1 ] || bad="${bad}no-post-settle-reprobe "
  [ "$(printf '%s\n' "$body" | grep -c 'return 1')" -ge 1 ] || bad="${bad}no-return-1 "
  [ "$(printf '%s\n' "$body" | grep -cF 'blockdev --getsize64')" -ge 2 ] || bad="${bad}probe-not-once-plus-per-pass "
  printf '%s' "$bad"
}
_w6rb="$(_wd_bad "$_wd_reopen")"
if [ -z "$_w6rb" ] && [ -n "$_wd_reopen" ]; then ok "T1.6c the reopen wait_dev is the ruled mechanism (literal 300, counted sleep-1 passes, whole predicate per pass, ONE post-loop settle)"; else no "T1.6c the reopen wait_dev deviates from the ruled mechanism:${_w6rb}"; fi
_w6sb="$(_wd_bad "$_wd_stage")"
if [ -z "$_w6sb" ] && [ -n "$_wd_stage" ]; then ok "T1.6d the runcmd wait_dev is the ruled mechanism (same shape, luks_emit channel)"; else no "T1.6d the runcmd wait_dev deviates from the ruled mechanism:${_w6sb}"; fi
# The wait REPORTS through each reader's own emitter: one wait-start line on the first miss and an
# appeared-after line on resolution — the late-attach arms exercise these, a silent wait is a
# 300s blind spot on a host with no SSH.
if [ "$(printf '%s\n' "$_wd_reopen" | grep -cE '(^|[^[:alnum:]_])emit[[:space:]]')" -ge 2 ] \
   && [ "$(printf '%s\n' "$_wd_stage" | grep -cF 'luks_emit')" -ge 2 ]; then
  ok "T1.6e each wait_dev body reports through its reader's own emitter (wait-start + appeared-after)"
else
  no "T1.6e a wait_dev body does not emit wait-start/appeared-after lines through its reader's own channel"
fi

# T1.7 No `|| true` / `|| :` / `set +e` on a mount. The whole apparatus is defeated by one of them:
# a swallowed mount failure leaves /mnt/data as a plain directory on the root disk while every
# downstream check that reads the STRING "/mnt/data" still passes.
LUKS_BLOCK="$(awk '/doppler run --project soleur-inngest --config \${inngest_doppler_config\} -- bash -s <<.LUKSEOF.$/,/^    LUKSEOF$/' "$CLOUD_INIT")"
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
printf '%s\n' "$LUKS_BLOCK" > "${TMPDIR:-/tmp}/.ilt-block.$$" 2>/dev/null || true
# `[^|]*` CANNOT SPAN AN EARLIER `||`, and every mount in this stage is written as
# `mountpoint -q X || mount …`. So the swallow-form that would actually appear in this file was
# the one form the pattern could not see; the arm was green against the only mutation that
# matters. `.*` sees the whole line, and the trailing anchor still pins the swallow to the END.
if [ -s "${TMPDIR:-/tmp}/.ilt-block.$$" ] && ! grep -qE '^[[:space:]]*(mount|mountpoint|mkfs|cryptsetup).*\|\|[[:space:]]*(true|:)[[:space:]]*$' "${TMPDIR:-/tmp}/.ilt-block.$$"; then ok "T1.7b no mount/mkfs/cryptsetup step is suffixed with || true"; else no "T1.7b a mount/mkfs/cryptsetup step swallows its failure"; fi
# ANCHORED ON SYNTAX, NOT ON THE BARE TOKEN. The stage's own comment says "No `|| true`, no
# `|| :`, and no `set +e`" — so a bare-literal grep matches the SUT's documentation of the rule and
# reports a violation that does not exist. This is the collision `cq-assert-anchor-not-bare-token`
# names, and it fired here on the first run: a comment line starts with `#`, a statement does not.
if [ -s "${TMPDIR:-/tmp}/.ilt-block.$$" ] && ! grep -qE '^[[:space:]]*set[[:space:]]+\+e' "${TMPDIR:-/tmp}/.ilt-block.$$"; then ok "T1.7c the stage never disarms errexit"; else no "T1.7c the LUKS stage contains a live 'set +e' statement"; fi
rm -f "${TMPDIR:-/tmp}/.ilt-block.$$"

# T1.8 `nofail` is RETAINED in every fstab line the stage writes. A strict fstab on a host with no
# SSH and no console converts a slow attach into an unrecoverable boot wedge; loud failure belongs
# in the Redis unit's ExecStartPre, not in a line that bricks the boot before anything can report.
# TWO ARMS, because counting the GOOD lines is not the same claim as "there is no BAD one": a
# further fstab write that omits nofail leaves the good count intact and the boot wedged.
# (#6894) Every writer now goes through `fstab_set`, which REPLACES the mountpoint's line: three for
# /mnt/data (the pointer arm plus the two unpointed mounting arms; #9786 deleted the ext4 arm and the
# staging mount with the plaintext volume).
_fstab_lines="$(grep -cE 'fstab_set /mnt/data "\$(DEV|MAPPER) /mnt/data ext4 defaults,nofail 0 2"' "$CLOUD_INIT")"
if [ "$_fstab_lines" -eq 3 ]; then ok "T1.8a all three /mnt/data fstab writes go through fstab_set and retain nofail"; else no "T1.8a expected 3 nofail-carrying fstab_set writes for /mnt/data (pointer arm + two unpointed mounting arms), found ${_fstab_lines}"; fi
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

# T1.10 THE RETIRED INPUT STAYS RETIRED (#9786 review round 3, CTO ruling A). `inngest_expect_luks` armed the
# post-recut ext4 refusal. #9786 deleted every branch on it and nothing in the repo read its `expect_luks=`
# telemetry field, so the input was retired in the SAME change: leaving it would make its later retirement a
# second user_data change, which replaces the sole scheduler host a second time for a cosmetic edit. No tracked
# infra, script or workflow file may name it again (this file is the one exemption: it must be able to say what it
# forbids). T1.11 (the variable's own comment and default) went with the variable.
_expect_hits="$(grep -rIli 'expect_luks' "$SCRIPT_DIR" "$SCRIPT_DIR/../../../scripts" "$SCRIPT_DIR/../../../.github" --exclude=inngest-redis-luks.test.sh --exclude-dir=node_modules --exclude-dir=.terraform 2>/dev/null | sed "s|^$SCRIPT_DIR/||" | tr '\n' ' ')"
if [ -z "$_expect_hits" ]; then ok "T1.10 no infra, script or workflow file names the retired inngest_expect_luks input (variable, template key, emit field and tests all gone)"; else no "T1.10 the retired inngest_expect_luks input is back in: ${_expect_hits}"; fi

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
  -e 's/\${inngest_luks_volume_id}/106999999/g' \
  -e 's/\${[a-z_][a-z_0-9]*}/TEMPLATE_VALUE/g'; }
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
_G1_STAGE="$(awk '/doppler run --project soleur-inngest --config \${inngest_doppler_config\} -- bash -s <<.LUKSEOF.$/{f=1;next} /^    LUKSEOF$/{f=0} f' "$CLOUD_INIT")"
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
      if [[ "$line" == *'"$MAPPER"'* ]] && [[ "$line" != *'blkid -p '* ]]; then _g1_bad="${_g1_bad} ${label}:mapper-probe-without--p"; fi
    else
      _g1_bad="${_g1_bad} ${label}:UNCLASSIFIED[$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-60)]"
    fi
  done <<< "$text"
}
_g1_classify stage "$(printf '%s\n' "$_G1_STAGE" | sed 's/\$\${/${/g')"
_g1_classify reopen "$(printf '%s\n' "$_G1_REOPEN" | sed -e 's/^      //' -e 's/\$\${/${/g')"
# Floor 6 -> 4 (#9786), exact: the reopen script's luks_type probe, the stage's pointer_blkid_probe,
# pointer_mapper_probe and unpointed blkid_probe. The two staging probes went with the staging block.
if [ "$_g1_sites" -ge 4 ]; then ok "G1.a found ${_g1_sites} blkid probe sites across both device readers (floor 4)"; else no "G1.a found only ${_g1_sites} blkid sites — the walk is not reaching a reader"; fi
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
# G1.e mkfs targets ONLY the canonical mapper, and only AFTER the luksOpen that creates it (mutation row 6).
_g1_mkfs_bad="$(printf '%s\n' "$_G1_STAGE" | grep -E '^[[:space:]]*mkfs' | grep -vE 'mkfs\.ext4 -q "\$MAPPER"' || true)"
if [ -z "$_g1_mkfs_bad" ]; then ok "G1.e every mkfs in the stage targets the mapper, never a raw device"; else no "G1.e an mkfs targets something other than the mapper: ${_g1_mkfs_bad}"; fi
_fresh_open="$(printf '%s\n' "$_G1_STAGE" | grep -nE '^[[:space:]]*printf .* cryptsetup luksOpen --key-file - "\$DEV" inngest-redis 2>>' | sed -n '1p' | cut -d: -f1)"
_fresh_mkfs="$(printf '%s\n' "$_G1_STAGE" | grep -nE '^[[:space:]]*mkfs\.ext4 -q "\$MAPPER"' | sed -n '1p' | cut -d: -f1)"
if [ -n "$_fresh_open" ] && [ -n "$_fresh_mkfs" ] && [ "$_fresh_open" -lt "$_fresh_mkfs" ]; then ok "G1.f the unpointed mkfs comes after the fresh luksOpen (line ${_fresh_open} < ${_fresh_mkfs})"; else no "G1.f the unpointed mkfs is not after its luksOpen (open=${_fresh_open:-none} mkfs=${_fresh_mkfs:-none})"; fi

# ═══ TIER 2b — the strip (#9786): one volume, no plaintext resolver ═════════════════════════
# The template reads ONE volume id. Everything reachable only when the retired plaintext volume could
# be canonical or staged is gone, and nothing can name it again. COMMENT-STRIPPED view, the same
# `grep -vE '^[[:space:]]*#'` shape the AC1 grep uses: prose may still name the retired id, a statement
# may not. Whole-file absence is per-reader by construction (zero hits in the file is zero in each reader).
_CI_CODE="$(grep -vE '^[[:space:]]*#' "$CLOUD_INIT" || true)"
_STRIP_NEEDLES='PLAIN_ID inngest_volume_id INNGEST_LUKS_PLAIN_VOLUME_ID STAGING_ reopen_skip_plaintext mount_ext4 plaintext_canonical 106261946 inngest-redis-staging data-luks'
_strip_hits() {  # _strip_hits <text> — prints the needles that appear in the text
  local _n _hit=""
  for _n in $_STRIP_NEEDLES; do
    [ "$(grep -cF -- "$_n" <<<"$1")" -gt 0 ] && _hit="${_hit} ${_n}"
  done
  printf '%s' "$_hit"
}
_strip_found="$(_strip_hits "$_CI_CODE")"
if [ -z "$_strip_found" ]; then ok "T1.16a no executable line names the retired plaintext volume, its staging block, or its modes"; else no "T1.16a the retired plaintext resolver is back in a delivered line:${_strip_found}"; fi
# Controls on T1.16a: a live statement must be caught, and prose must not be.
if [ -n "$(_strip_hits "$(printf '    PLAIN_ID=%s\n' "'1'" | grep -vE '^[[:space:]]*#' || true)")" ]; then ok "T1.16b control: a live PLAIN_ID statement is flagged"; else no "T1.16b CONTROL: the absence predicate cannot see a live PLAIN_ID statement — T1.16a is vacuous"; fi
if [ -z "$(_strip_hits "$(printf '    # PLAIN_ID was the plaintext volume (STAGING_DEV, reopen_skip_plaintext)\n' | grep -vE '^[[:space:]]*#' || true)")" ]; then ok "T1.16c control: a comment that names the retired id passes (comment-stripped view)"; else no "T1.16c CONTROL: a comment is graded as code — the strip cannot keep its own history"; fi
# Both readers derive their device from the ONE rendered id, and the stage carries no ext4 arm or mount.
# ANCHORED at the line start: an unanchored `DEV="..."` is also a substring of the STAGING_DEV line this strip deletes.
_dev_reopen="$(printf '%s\n' "$_G1_REOPEN" | grep -cE '^[[:space:]]*DEV="\$\$\{BYID\}\$\$\{LUKS_ID\}"$')"
_dev_stage="$(printf '%s\n' "$_G1_STAGE" | grep -cE '^[[:space:]]*DEV="\$\$\{BYID\}\$\$\{LUKS_ID\}"$')"
_luksid_def="$(printf '%s\n%s\n' "$_G1_REOPEN" "$_G1_STAGE" | grep -cF "LUKS_ID='\${inngest_luks_volume_id}'")"
if [ "$_dev_reopen" -eq 1 ] && [ "$_dev_stage" -eq 1 ] && [ "$_luksid_def" -eq 2 ]; then ok "T1.16d DEV is derived from LUKS_ID in BOTH readers, and LUKS_ID is the rendered id (reopen ${_dev_reopen}x, stage ${_dev_stage}x, defs ${_luksid_def}x)"; else no "T1.16d DEV is not derived from LUKS_ID exactly once per reader (reopen ${_dev_reopen}x, stage ${_dev_stage}x, LUKS_ID defs ${_luksid_def}x)"; fi
_stage_code="$(printf '%s\n' "$_G1_STAGE" | grep -vE '^[[:space:]]*#' || true)"
if [ "$(grep -cE '^[[:space:]]*ext4\)|mount[[:space:]]+"\$DEV"|"\$DEV /mnt/data' <<<"$_stage_code")" -eq 0 ]; then ok "T1.16e the stage has no ext4 arm and never mounts the raw device"; else no "T1.16e an ext4 arm or a raw-device mount is back in the first-boot stage"; fi
# The unpointed probe bypasses the blkid cache (a stale type from an aborted attempt must not pick a
# destructive arm). It is the STAGE=blkid_probe site, so it is located by its stage marker.
if [ "$(printf '%s\n' "$_G1_STAGE" | grep -A3 -E '^[[:space:]]*STAGE=blkid_probe$' | grep -cF 'blkid -p -o value -s TYPE "$DEV"')" -eq 1 ]; then ok "T1.16f the unpointed blkid_probe uses blkid -p (no cached type decides a destructive arm)"; else no "T1.16f the unpointed blkid_probe is not a blkid -p probe"; fi
# D6: the unpointed arm may FORMAT only on a rehearsal config. EVERY luksFormat site in the stage must be
# preceded, in the same case arm, by the one-line ALLOWLIST refusal on the rendered Doppler config (only
# `rehearsal_*` passes; prd and anything added later refuse). The guard is matched as a WHOLE STATEMENT (it
# starts the line and ends in `exit 1 ;; esac`): a guard commented out, inverted, or turned into a no-op
# still contains its own tokens, so a token match would call it present. T1.16i then DRIVES the line, so a
# guard that matches by shape but never exits cannot pass.
_D6_HEAD="case '\${inngest_doppler_config}' in rehearsal_*) ;; *) echo \"FATAL: unpointed_raw_refused"
_D6_TAIL='exit 1 ;; esac'
_d6_scan() {  # _d6_scan <text> — prints "<luksFormat sites> <unguarded sites>"
  awk -v head="$_D6_HEAD" -v tail="$_D6_TAIL" '
    /;;[[:space:]]*$/ || /^[[:space:]]*case / { g = 0 }
    { l = $0; sub(/^[[:space:]]+/, "", l) }
    index(l, head) == 1 && substr(l, length(l) - length(tail) + 1) == tail { g = 1 }
    /^[[:space:]]*[^#[:space:]].*cryptsetup luksFormat/ { n++; if (!g) bad++ }
    END { print n + 0, bad + 0 }' <<<"$1"
}
read -r _d6_n _d6_bad <<<"$(_d6_scan "$_G1_STAGE")"
if [ "$_d6_n" -eq 1 ] && [ "$_d6_bad" -eq 0 ]; then ok "T1.16g the one luksFormat site is preceded by the rehearsal-only refusal in its own arm (sites ${_d6_n}, unguarded ${_d6_bad})"; else no "T1.16g luksFormat sites=${_d6_n}, unguarded=${_d6_bad} — a format arm reachable on a non-rehearsal host (D6)"; fi
_D6_GUARD="        $_D6_HEAD\" ; exit 1 ;; esac"
read -r _d6c_n _d6c_bad <<<"$(_d6_scan "        \"\")
${_D6_GUARD}
          printf x | cryptsetup luksFormat --key-file - \"\$DEV\"
          ;;
        other)
          printf x | cryptsetup luksFormat --key-file - \"\$DEV\"
          ;;")"
read -r _d6d_n _d6d_bad <<<"$(_d6_scan "        \"\")
        : # ${_D6_GUARD#        }
          printf x | cryptsetup luksFormat --key-file - \"\$DEV\"
          ;;")"
if [ "$_d6c_n" -eq 2 ] && [ "$_d6c_bad" -eq 1 ] && [ "$_d6d_n" -eq 1 ] && [ "$_d6d_bad" -eq 1 ]; then ok "T1.16h control: a SECOND unguarded luksFormat, and a guard commented out in place, are both flagged (${_d6c_n}/${_d6c_bad}, ${_d6d_n}/${_d6d_bad})"; else no "T1.16h CONTROL: the per-site D6 scan missed an unguarded luksFormat (second site ${_d6c_n}/${_d6c_bad}, commented guard ${_d6d_n}/${_d6d_bad}) — T1.16g is vacuous"; fi
# T1.16i DRIVE the guard IN ITS ARM, with the stage's real state. The segment is everything between the
# empty-signature arm's label and `STAGE=luks_format`, so a guard that depends on state the stage itself sets
# (`[ "$STAGE" != unpointed_raw_refused ] && exit 1` passes a driver that leaves STAGE unset and reaches
# luksFormat on the host), or any extra line wedged between the guard and the format, is executed too. STAGE is
# preset to what the stage holds on entry to the arm (blkid_probe). A sentinel after the segment must be
# reached ONLY for a rehearsal_* config. rc 1 plus the refusal text means the arm was stopped.
_d6_seg="$(printf '%s\n' "$_G1_STAGE" | awk '/^        ""\)$/{f=1;next} f&&/^          STAGE=luks_format$/{exit} f' | grep -vE '^[[:space:]]*#' || true)"
_d6_tmp="$(mktemp)"; : > "$_d6_tmp"
_d6_bad_cfg=""
if [ -z "$_d6_seg" ] || ! grep -qF 'STAGE=unpointed_raw_refused' <<<"$_d6_seg"; then
  no "T1.16i could not extract the empty-signature arm's guard segment — the behavioural drive is vacuous"
else
  for _cfg in prd dev staging rehearsal '' rehearsal_1 rehearsal_loopback; do
    _stmt="${_d6_seg//'${inngest_doppler_config}'/$_cfg}"
    _rc=0; _o="$(DEV=/dev/null INNGEST_LUKS_DETAIL="$_d6_tmp" bash -c "set -euo pipefail; STAGE=blkid_probe; ${_stmt}; echo REACHED_FORMAT" 2>&1)" || _rc=$?
    case "$_cfg" in
      rehearsal_*) { [ "$_rc" -eq 0 ] && [ "$_o" = REACHED_FORMAT ]; } || _d6_bad_cfg="${_d6_bad_cfg} [${_cfg}: rc=${_rc} should be 0 and reach the format step]" ;;
      *)           { [ "$_rc" -eq 1 ] && grep -q 'unpointed_raw_refused' <<<"$_o" && ! grep -q 'REACHED_FORMAT' <<<"$_o"; } || _d6_bad_cfg="${_d6_bad_cfg} [${_cfg:-<empty>}: rc=${_rc} should be 1 with the refusal text and no format step]" ;;
    esac
  done
  if [ -z "$_d6_bad_cfg" ]; then ok "T1.16i driven in-arm with the stage's state: prd/dev/staging/empty/bare-'rehearsal' stop before the format step; only rehearsal_* reaches it"; else no "T1.16i the D6 guard segment misbehaves when executed:${_d6_bad_cfg}"; fi
fi
rm -f "$_d6_tmp"
# T1.16j the refusal names its OWN stage: luks_err ships $STAGE, so without this the off-box row reads
# stage=blkid_probe and the diagnosis names the wrong arm.
if [ "$(printf '%s\n' "$_G1_STAGE" | grep -B1 -E "^[[:space:]]*case '[$][{]inngest_doppler_config[}]' in rehearsal_" | grep -cE '^[[:space:]]*STAGE=unpointed_raw_refused$')" -eq 1 ]; then ok "T1.16j the D6 refusal sets STAGE=unpointed_raw_refused on the line before the guard"; else no "T1.16j the D6 guard is not immediately preceded by STAGE=unpointed_raw_refused — the refusal would ship as stage=blkid_probe"; fi

# T1.16k The allowlist glob and the rehearsal root's config name are ONE contract: the guard formats only for
# `rehearsal_*`, and the rehearsal root renders `rehearsal_<run id>`. Renaming either side alone leaves every
# local suite green and makes the (paid) rehearsal refuse to format; pin both ends here.
_reh_tf="$SCRIPT_DIR/inngest-provision-rehearsal/rehearsal.tf"
_reh_n="$(grep -vE '^[[:space:]]*#' "$_reh_tf" 2>/dev/null | grep -cxE '[[:space:]]*rehearsal_doppler_config[[:space:]]*=[[:space:]]*"rehearsal_[$][{]var[.]rehearsal_run_id[}]"' || true)"
_reh_glob="$(printf '%s\n' "$_G1_STAGE" | grep -cF "in rehearsal_*) ;; *) echo" || true)"
if [ "$_reh_n" -eq 1 ] && [ "$_reh_glob" -eq 1 ]; then ok "T1.16k the guard's rehearsal_* glob and rehearsal.tf's rehearsal_<run id> config name agree (one each)"; else no "T1.16k the allowlist glob and the rehearsal config prefix are out of step (rehearsal.tf defs ${_reh_n}, guard globs ${_reh_glob}) — the rehearsal would refuse to format"; fi

# ═══ TIER 2c — the destructive-operation inventory (#9786 review: structural-cause roll-up) ══════════
# T1.16g/e guard one SPELLING in one WINDOW. The property is "nothing in the delivered template formats,
# wipes, or mounts a device other than the one the resolver chose". T1.17a-e are TARGETED early-warning rows
# with specific messages (a regex over command-position shapes; they are a denylist and a denylist of shapes
# is bypassable by a list item, `sudo`, `then`, a path prefix, `dd`, `cryptsetup erase`...). The PROPERTY is
# pinned by T1.17f-j below. T1.17f-g are CLOSED SETS: every normalised line that mentions a device-touching
# token (or assigns a device variable) must equal the expected list, so a new shape of the same operation cannot
# add a line without naming it. What the closed sets do NOT see, stated plainly: a device write on a line that
# names none of the listed tokens and is reached neither through a redirect to a device variable (T1.17j) nor
# through the indirection forms T1.17h denies (eval, a variable or `${x:-y}` as the command, sh/bash -c, xargs,
# exec) -- for example a NEW shell function that wraps the write, or a command substitution. The loopback tier
# (real devices, CI) and human review are the backstop for that residual; it is not claimed closed.
_CI_OPS="$(printf '%s\n' "$_CI_CODE" | grep -vE 'echo "FATAL' || true)"
_ops_fmt="$(grep -cE 'cryptsetup[^|;]*(luksFormat|luksErase|reencrypt|luksAddKey|luksRemoveKey|luksKillSlot|luksHeaderRestore)' <<<"$_CI_OPS" || true)"
_ops_dest="$(grep -cE '(^[[:space:]]*|[|;&][[:space:]]*)(mkfs[.a-z0-9]*|mke2fs|wipefs|blkdiscard|shred|sgdisk|sfdisk|parted)[[:space:]]' <<<"$_CI_OPS" || true)"
_ops_mkfs_ok="$(grep -cE '^[[:space:]]*mkfs\.ext4 -q "\$MAPPER" 2>>"\$INNGEST_LUKS_DETAIL"$' <<<"$_CI_OPS" || true)"
if [ "$_ops_fmt" -eq 1 ] && [ "$_ops_dest" -eq 1 ] && [ "$_ops_mkfs_ok" -eq 1 ]; then ok "T1.17a the whole template has exactly one header-writing cryptsetup site and one mkfs (on the mapper), nothing else destructive (fmt ${_ops_fmt}, destructive ${_ops_dest}, mkfs-on-mapper ${_ops_mkfs_ok})"; else no "T1.17a destructive-operation inventory drifted: header-writing cryptsetup=${_ops_fmt} (want 1), mkfs/wipe/partition tools=${_ops_dest} (want 1), mkfs on the mapper=${_ops_mkfs_ok} (want 1)"; fi
_ops_mount="$(grep -cE '(^[[:space:]]*|[|;&][[:space:]]*)mount[[:space:]]' <<<"$_CI_OPS" || true)"
_ops_mount_ok="$(grep -cE 'mountpoint -q /mnt/data \|\| mount "\$MAPPER" /mnt/data 2>>"\$INNGEST_LUKS_DETAIL"$' <<<"$_CI_OPS" || true)"
_ops_fstab="$(grep -cE '^[[:space:]]*fstab_set[[:space:]]+/' <<<"$_CI_OPS" || true)"
_ops_fstab_ok="$(grep -cF 'fstab_set /mnt/data "$MAPPER /mnt/data ext4 defaults,nofail 0 2"' <<<"$_CI_OPS" || true)"
# 3 -> 4 mounts (#10217): the reopen's ensure_mount adds a fstab-driven `mount "$2"` — by mountpoint,
# so its source/options come from the line it just wrote, never a re-typed device. The three arm
# mounts stay the canonical `$MAPPER` at /mnt/data (one per arm).
if [ "$_ops_mount" -eq 4 ] && [ "$_ops_mount_ok" -eq 3 ] && [ "$_ops_fstab" -eq 3 ] && [ "$_ops_fstab_ok" -eq 3 ]; then ok "T1.17b every mount and fstab_set in the template is the mapper at /mnt/data or ensure_mount's by-mountpoint mount (mount ${_ops_mount}/${_ops_mount_ok}, fstab_set ${_ops_fstab}/${_ops_fstab_ok})"; else no "T1.17b a mount or fstab write targets something other than \$MAPPER at /mnt/data (mount ${_ops_mount} total / ${_ops_mount_ok} canonical, fstab_set ${_ops_fstab} / ${_ops_fstab_ok})"; fi
_ops_open="$(grep -cE 'cryptsetup[^|;]*luksOpen' <<<"$_CI_OPS" || true)"
_ops_open_ok="$(grep -cE 'cryptsetup luksOpen --key-file - ("\$1"|"\$CANON_DEV"|"\$DEV") ' <<<"$_CI_OPS" || true)"
if [ "$_ops_open" -eq 4 ] && [ "$_ops_open_ok" -eq 4 ]; then ok "T1.17c exactly four luksOpen sites (one reopen, three stage arms), each on a device the resolver derived (${_ops_open}/${_ops_open_ok})"; else no "T1.17c luksOpen inventory drifted: ${_ops_open} sites, ${_ops_open_ok} on a resolver-derived device (want 4/4)"; fi
# The boot-reopen script runs as root on EVERY boot after the first. It may open a LUKS volume and
# complete its mount — never format, never mkfs, never wipe a device. #10217's ensure_mount mounts
# by mountpoint and heals the fstab line, so mount/fstab writes are legitimate here and are pinned
# by the T1.17f closed set instead; what stays forbidden is any DEVICE write. (T1.16g/G1.e only ever
# scanned the stage window.)
_reopen_code="$(printf '%s\n' "$_G1_REOPEN" | grep -vE '^[[:space:]]*#' | grep -vE 'echo "FATAL' || true)"
_reopen_bad="$(grep -cE 'luksFormat|luksErase|reencrypt|mkfs|mke2fs|wipefs|blkdiscard' <<<"$_reopen_code" || true)"
_reopen_cs="$(grep -c 'cryptsetup' <<<"$_reopen_code" || true)"
if [ -n "$_reopen_code" ] && [ "$_reopen_bad" -eq 0 ] && [ "$_reopen_cs" -eq 1 ]; then ok "T1.17d the boot-reopen script never formats or wipes a device: no format/mkfs op, exactly one cryptsetup call (luksOpen in open_as)"; else no "T1.17d the boot-reopen script can write a device or filesystem (forbidden ops ${_reopen_bad}, cryptsetup calls ${_reopen_cs}, want 0 and 1)"; fi
# Refusal BODIES, not just arm headers: G4.e proves the resolver arms exist; this proves what they do.
_res2="$(printf '%s\n' "$_G1_STAGE" | awk '/^    STAGE=resolve$/{f=1} f&&/^    esac$/{print; exit} f')"
_res_pointer="$(grep -c 'MODE=pointer' <<<"$_res2" || true)"; _res_unp="$(grep -c 'MODE=unpointed' <<<"$_res2" || true)"; _res_exit="$(grep -c 'exit 1' <<<"$_res2" || true)"
_reopen_allow_bad="$(printf '%s\n' "$_G1_REOPEN" | grep -cE '^[[:space:]]*\*\)[[:space:]]*;;' || true)"
_reopen_allow_ok="$(printf '%s\n' "$_G1_REOPEN" | grep -cF '*) fail reopen_pointer 1 n/a' || true)"
if [ "$_res_pointer" -eq 1 ] && [ "$_res_unp" -eq 1 ] && [ "$_res_exit" -eq 2 ] && [ "$_reopen_allow_bad" -eq 0 ] && [ "$_reopen_allow_ok" -eq 1 ]; then ok "T1.17e the resolver sets MODE=pointer only for the own-id arm and refuses the other two shapes with exit 1; the reopen allowlist's catch-all refuses (pointer ${_res_pointer}, unpointed ${_res_unp}, exit ${_res_exit})"; else no "T1.17e a resolver refusal body or the reopen allowlist changed (MODE=pointer ${_res_pointer}, MODE=unpointed ${_res_unp}, exit 1 ${_res_exit}, reopen catch-all passes ${_reopen_allow_bad}, refuses ${_reopen_allow_ok})"; fi

# ── T1.17f-i CLOSED SETS (the class fix for the inventory's shape-bypass) ────────────────────────────
# Normalise the way a shell reads the text: drop whole-line comments, join backslash continuations, trim indent.
# Then the set of lines that mention ANY device-touching token (cryptsetup subcommands, mkfs/mke2fs/wipefs/dd and
# friends, mount/umount, fstab, cloud-init disk modules) is compared WHOLE-LINE to the list below, in order. A
# new line, in any shape (runcmd list item, `sudo`, path-qualified, after `echo "FATAL"; `), fails with a diff;
# a deliberate change edits this list in the same commit, which is the point. Residual, stated: an operation
# reached through shell indirection (`$op "$DEV"`, `eval`) names none of these tokens, so T1.17h denies the
# indirection forms themselves.
_norm_code() { grep -vE '^[[:space:]]*#' "$1" | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' -e 's/^[[:space:]]*//'; }
_OPS_TOK='(^|[^[:alnum:]_])(luksFormat|luksOpen|luksClose|luksErase|erase|reencrypt|luksAddKey|luksRemoveKey|luksKillSlot|luksHeaderRestore|luksChangeKey|luksConvertKey|mkfs[.a-z0-9]*|mke2fs|wipefs|blkdiscard|shred|sgdisk|sfdisk|parted|fdisk|dd|mkswap|truncate|cryptsetup|mount|umount|fstab|fstab_set|fs_setup|disk_setup|bootcmd|mounts|swapon|losetup|dmsetup)([^[:alnum:]_]|$)'
_VAR_RE='^(export[[:space:]]+)?(DEV|MAPPER|BYID|LUKS_ID|CANON_DEV|POINTER|MNT|CANON_NAME)='
# #10217 grew this list: the unit Description line (it names mount/cryptsetup tokens) and
# ensure_mount's whole converge path (wrong-source umount loop, atomic fstab rewrite, daemon-reload,
# by-mountpoint mount). #9786 removed the staging block's fstab/mount/luksFormat set and the
# plaintext arm's sites with it.
_exp_ops="$(cat <<'EXPEOF'
- cryptsetup
Description=Open the LUKS mapper, then complete the mount for the arm it verified — never formats, never mkfs (#7695)
After=cryptsetup-pre.target systemd-udev-settle.service
printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup luksOpen --key-file - "$1" "$2"
[ "$_em_i" -le 8 ] || fail reopen_mount 1 n/a "umount loop at $2 did not converge in 8 passes"
umount "$2" || fail reopen_mount 1 n/a "umount of a wrong-source layer at $2 failed"
if [ "$(awk -v mp="$2" '$1 !~ /^#/ && $2 == mp' /etc/fstab | grep -c .)" -eq 1 ]; then
_em_tmp="$(mktemp /etc/fstab.soleur.XXXXXX)" || fail reopen_fstab 1 n/a "mktemp /etc/fstab.soleur.XXXXXX failed"
awk -v mp="$2" '$1 ~ /^#/ || $2 != mp' /etc/fstab > "$_em_tmp" || { rm -f "$_em_tmp"; fail reopen_fstab 1 n/a "rewriting /etc/fstab for $2 failed"; }
printf '%s\n' "$1 $2 ext4 defaults,nofail 0 2" >> "$_em_tmp" || { rm -f "$_em_tmp"; fail reopen_fstab 1 n/a "writing the $2 fstab line failed"; }
chmod 0644 "$_em_tmp" || { rm -f "$_em_tmp"; fail reopen_fstab 1 n/a "chmod on the rewritten fstab failed"; }
mv -f "$_em_tmp" /etc/fstab || { rm -f "$_em_tmp"; fail reopen_fstab 1 n/a "installing the rewritten /etc/fstab failed"; }
_em_n="$(awk -v mp="$2" '$1 !~ /^#/ && $2 == mp' /etc/fstab | wc -l)" || _em_n=0
[ "$_em_n" -eq 1 ] || fail reopen_fstab 1 n/a "fstab carries $_em_n lines for $2 after the rewrite — exactly one is required"
systemctl daemon-reload || fail reopen_fstab 1 n/a "daemon-reload after the fstab install failed"
mount "$2" || fail reopen_mount 1 n/a "mount $2 failed"
emit reopen_mount 0 n/a "$1 mounted at $2 via fstab"
emit reopen_mount 0 n/a "$1 already mounted at $2 — fstab line healed"
[ -n "$${INNGEST_REDIS_LUKS_KEY:-}" ] || { echo "FATAL: INNGEST_REDIS_LUKS_KEY empty — refusing an unencrypted mount" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
fstab_set() {
_fs_tmp="$(mktemp /etc/fstab.soleur.XXXXXX)" || { echo "FATAL: mktemp for the fstab rewrite failed" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
awk -v mp="$1" '$1 ~ /^#/ || $2 != mp' /etc/fstab > "$_fs_tmp" || { rm -f "$_fs_tmp"; echo "FATAL: rewriting fstab for $1 failed" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
printf '%s\n' "$2" >> "$_fs_tmp" || { rm -f "$_fs_tmp"; echo "FATAL: writing the $1 fstab line failed" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
chmod 0644 "$_fs_tmp" || { rm -f "$_fs_tmp"; echo "FATAL: chmod on the rewritten fstab failed" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
mv -f "$_fs_tmp" /etc/fstab || { rm -f "$_fs_tmp"; echo "FATAL: installing the rewritten fstab failed" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
_fs_n="$(awk -v mp="$1" '$1 !~ /^#/ && $2 == mp' /etc/fstab | wc -l)"
[ "$_fs_n" -eq 1 ] || { echo "FATAL: fstab carries $_fs_n lines for $1 after the rewrite — exactly one is required" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
[ -e "$MAPPER" ] || printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup luksOpen --key-file - "$CANON_DEV" inngest-redis 2>>"$INNGEST_LUKS_DETAIL"
mountpoint -q /mnt/data || mount "$MAPPER" /mnt/data 2>>"$INNGEST_LUKS_DETAIL"
fstab_set /mnt/data "$MAPPER /mnt/data ext4 defaults,nofail 0 2"
[ -e "$MAPPER" ] || printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" inngest-redis 2>>"$INNGEST_LUKS_DETAIL"
mountpoint -q /mnt/data || mount "$MAPPER" /mnt/data 2>>"$INNGEST_LUKS_DETAIL"
fstab_set /mnt/data "$MAPPER /mnt/data ext4 defaults,nofail 0 2"
case '${inngest_doppler_config}' in rehearsal_*) ;; *) echo "FATAL: unpointed_raw_refused — $DEV reads blank on a non-rehearsal config with no pointer; refusing to luksFormat the only copy of the AOF" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1 ;; esac
printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV" 2>>"$INNGEST_LUKS_DETAIL"
printf '%s' "$INNGEST_REDIS_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" inngest-redis 2>>"$INNGEST_LUKS_DETAIL"
STAGE=mkfs
mkfs.ext4 -q "$MAPPER" 2>>"$INNGEST_LUKS_DETAIL"
luks_emit mkfs 0 empty
mountpoint -q /mnt/data || mount "$MAPPER" /mnt/data 2>>"$INNGEST_LUKS_DETAIL"
fstab_set /mnt/data "$MAPPER /mnt/data ext4 defaults,nofail 0 2"
STAGE=fstab
_fstab_n="$(awk '$1 !~ /^#/ && $2 == "/mnt/data"' /etc/fstab | wc -l)"
[ "$_fstab_n" -eq 1 ] || { echo "FATAL: /mnt/data mounted but fstab carries $_fstab_n lines for it — exactly one is required for the mount to survive a reboot" | tee -a "$INNGEST_LUKS_DETAIL"; exit 1; }
luks_emit fstab 0 "$${BLK_TYPE:-empty}"
EXPEOF
)"
_exp_vars="$(cat <<'EXPEOF'
LUKS_ID='${inngest_luks_volume_id}'
BYID=/dev/disk/by-id/scsi-0HC_Volume_
DEV="$${BYID}$${LUKS_ID}"
MAPPER=/dev/mapper/inngest-redis
POINTER="$${INNGEST_LUKS_ACTIVE_VOLUME_ID:-}"
CANON_DEV="$${BYID}$${POINTER}"
LUKS_ID='${inngest_luks_volume_id}'
BYID=/dev/disk/by-id/scsi-0HC_Volume_
DEV="$${BYID}$${LUKS_ID}"
MAPPER=/dev/mapper/inngest-redis
POINTER="$${INNGEST_LUKS_ACTIVE_VOLUME_ID:-}"
CANON_DEV="$DEV"
CANON_DEV="$${BYID}$${POINTER}"
EXPEOF
)"
_act_ops="$(_norm_code "$CLOUD_INIT" | grep -E "$_OPS_TOK" || true)"
if [ "$_act_ops" = "$_exp_ops" ]; then ok "T1.17f the set of lines that touch a device or mount is exactly the reviewed list ($(grep -c . <<<"$_act_ops") lines)"; else no "T1.17f a device-touching line was added, removed or changed — diff (expected vs actual): $(diff <(printf '%s\n' "$_exp_ops") <(printf '%s\n' "$_act_ops") | cut -c1-200 | head -12 | tr '\n' '|')"; fi
_act_vars="$(_norm_code "$CLOUD_INIT" | grep -E "$_VAR_RE" || true)"
if [ "$_act_vars" = "$_exp_vars" ]; then ok "T1.17g every assignment to DEV/MAPPER/BYID/LUKS_ID/CANON_DEV/POINTER is exactly the reviewed list ($(grep -c . <<<"$_act_vars") lines; a rebinding of what a destructive line operates on changes it)"; else no "T1.17g a device-variable assignment was added, removed or changed — diff (expected vs actual): $(diff <(printf '%s\n' "$_exp_vars") <(printf '%s\n' "$_act_vars") | cut -c1-200 | head -12 | tr '\n' '|')"; fi
# T1.17h/j scan the RENDERED form: the template writes every literal shell brace as `$${...}` (Terraform's escape),
# so a pattern that looks for `${DEV}` or `${x:-y}` never matches a real line. Collapse `$${` to `${` first.
_norm_rendered() { _norm_code "$1" | sed -e 's/[$][$]{/${/g'; }
_IND_RE='(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)|^[$][A-Za-z_]|^[$]\{[A-Za-z_][A-Za-z_0-9]*[:#%/^,-]|^"[$]\{[A-Za-z_][A-Za-z_0-9]*:[-=+?]|(^|[^[:alnum:]_./-])(sh|bash|dash)[[:space:]]+-c([[:space:]]|$)|(^|[^[:alnum:]_])xargs([^[:alnum:]_]|$)|(^|[^[:alnum:]_./-])exec[[:space:]]'
_indirect="$(_norm_rendered "$CLOUD_INIT" | grep -E "$_IND_RE" || true)"
if [ -z "$_indirect" ]; then ok "T1.17h no eval, variable-as-command, parameter-expansion-as-command, sh/bash -c, xargs or exec line, in rendered form (an operation cannot hide behind indirection from the closed sets)"; else no "T1.17h shell indirection appears in the template, which the closed sets cannot see through: ${_indirect}"; fi
# T1.17j no redirect, tee or dd of= targets a device variable: a raw write to the device (`head -c N /dev/zero > "$DEV"`,
# `echo x | tee "$MAPPER"`, `dd of="$DEV"`) names none of the closed sets' tokens, so it is denied by its target. This
# covers writes whose target is spelled as one of the three device variables; it is not a general write guard.
_RED_RE='(>>?|tee( +(-a|--append|--))*|of=)[[:space:]]*"?[$]\{?(DEV|MAPPER|CANON_DEV)([^[:alnum:]_]|$)'
_dev_redirect="$(_norm_rendered "$CLOUD_INIT" | grep -E "$_RED_RE" || true)"
if [ -z "$_dev_redirect" ]; then ok "T1.17j no redirect, tee or dd of= writes to \$DEV, \$MAPPER or \$CANON_DEV, in rendered form (a raw write to those variables is denied by its target)"; else no "T1.17j a redirect, tee or dd of= targets a device variable: ${_dev_redirect}"; fi
# Controls: the two patterns must FLAG the escaped-form bypasses the first version missed, and must not flag the
# template's own legitimate lines (zero hits above). Driven on literal samples, normalised the same way.
_ctl_bad=""
for _l in '$${OP:-true} "$DEV"' 'if x; then sh -c "$F" x; fi' '{ bash -c "$F"; }' 'env sh -c "$F"'; do
  [ "$(printf '%s\n' "$_l" | sed -e 's/[$][$]{/${/g' | grep -cE "$_IND_RE")" -eq 1 ] || _ctl_bad="${_ctl_bad} ind:[${_l}]"
done
for _l in 'head -c 1 /dev/zero > "$${DEV}"' 'tee --append "$DEV"' 'tee -- "$DEV"' 'dd of="$DEV" bs=1' 'echo x | tee "$${MAPPER}"'; do
  [ "$(printf '%s\n' "$_l" | sed -e 's/[$][$]{/${/g' | grep -cE "$_RED_RE")" -eq 1 ] || _ctl_bad="${_ctl_bad} red:[${_l}]"
done
if [ -z "$_ctl_bad" ]; then ok "T1.17k control: the indirection and device-redirect patterns flag the escaped-form and wrapped bypass shapes"; else no "T1.17k CONTROL: T1.17h/j miss bypass shapes:${_ctl_bad}"; fi
_top="$(grep -vE '^[[:space:]]*#' "$CLOUD_INIT" | grep -E '^[a-z_]+:' | sed 's/:.*//' | tr '\n' ' ')"
if [ "$_top" = "package_update packages groups users write_files runcmd " ]; then ok "T1.17i the template's top-level cloud-init keys are exactly package_update/packages/groups/users/write_files/runcmd (no fs_setup/disk_setup/mounts/bootcmd module)"; else no "T1.17i the top-level cloud-init keys changed: '${_top}' — a disk or mount module would act outside the shell inventory"; fi

# ═══ TIER 3 — Guard 4: the pointer decides, never the signature (#6894) ════════════════════
# THE POPULATION IS DERIVED. Every line in a DELIVERED artifact that names the pointer is found by
# walking the tree and must be classified into a known role; an unclassified site REDS. A reader the
# guard has never seen is exactly mutation row 4, and a hand-listed population would already be
# stale — a draft that named two sites was written before the cutover became the pointer's writer.
_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
_g4_bad=""; _g4_reads_stage=0; _g4_reads_reopen=0; _g4_total=0
_g4_dispatch_read=0; _g4_stager=0
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
    *"printf 'INNGEST_LUKS_ACTIVE_VOLUME_ID=%s\\n' \"\$POINTER\" >> /etc/default/inngest-luks"*) _g4_stager=$((_g4_stager + 1)) ;;  # first-boot STAGER (counted: G4.j)
    *'grep -qx "INNGEST_LUKS_ACTIVE_VOLUME_ID=$POINTER" /etc/default/inngest-luks'*) : ;;      # stager's own check
    *'echo "FATAL: INNGEST_LUKS_ACTIVE_VOLUME_ID is set but is not a volume id'*) : ;;          # diagnostic text
    # The dispatch's pre-write READ is the only non-device reader. The pointer has NO writer, injector or stager since #10112:
    # a site that reappears is UNCLASSIFIED (G4.b) or a direct write (G4.g3), never silently allowlisted.
    *'jq -e '"'"'has("INNGEST_LUKS_ACTIVE_VOLUME_ID")'"'"''*) _g4_dispatch_read=$((_g4_dispatch_read + 1)) ;; # dispatch pre-write READ
    *'doppler'*'secrets'*) _g4_bad="${_g4_bad} ${_f##*/}:${_ln}:secrets-verb-on-a-pointer-line" ;;   # never allowlisted by a text arm below
    *'::error::op='*'INNGEST_LUKS_ACTIVE_VOLUME_ID'*) : ;;                                        # operator-facing refusal text
    *) _g4_bad="${_g4_bad} ${_f##*/}:${_ln}:UNCLASSIFIED" ;;
  esac
done < <(cd "$_REPO" && git grep -nF 'INNGEST_LUKS_ACTIVE_VOLUME_ID' -- apps/web-platform/infra scripts .github \
          ':!*.test.sh' ':!*.test.ts' ':!tests/**' 2>/dev/null | sed "s|^|$_REPO/|")
if [ "$_g4_total" -ge 5 ]; then ok "G4.a found ${_g4_total} pointer sites in delivered artifacts (floor 5)"; else no "G4.a found only ${_g4_total} pointer sites — the walk is not reaching the tree"; fi
if [ -z "$_g4_bad" ]; then ok "G4.b every pointer site in a delivered artifact is classified (no reader the guard has never seen)"; else no "G4.b unclassified pointer sites:${_g4_bad} — classify each, or it is a reader nothing grades"; fi
if [ "$_g4_reads_stage" -eq 1 ] && [ "$_g4_reads_reopen" -eq 1 ]; then ok "G4.c the pointer is read by BOTH device readers exactly once (first-boot resolver and boot-reopen)"; else no "G4.c pointer reads: first-boot=${_g4_reads_stage} reopen=${_g4_reads_reopen} — each reader must apply it exactly once (mutation row 4)"; fi
# G4.g3 THE POINTER HAS NO WRITER since #10112 (its only writer was the on-host FSM, retired with the cutover trio). Two writers on a
# value that decides which device holds the store is the shape where a race decides where user data lives, so the property is
# "none": a direct secrets set or delete of the literal pointer name in any non-test file under apps/web-platform/infra, scripts or
# .github/workflows. It sees a LITERAL name only; a write through a variable name or after a `--` is not matched, but any other
# line naming the pointer literal is UNCLASSIFIED (G4.b), which is what bounds a respelled writer.
_g4_any_write="$(cd "$_REPO" && git grep -nE '^[^#]*doppler[^#]*secrets[^#]*(set|delete)[^#]*INNGEST_LUKS_ACTIVE_VOLUME_ID' -- apps/web-platform/infra scripts .github ':!*.test.sh' ':!*.test.ts' ':!tests/**' 2>/dev/null || true)"
if [ -z "$_g4_any_write" ]; then ok "G4.g3 no delivered artifact writes the pointer with a direct doppler set or delete"; else no "G4.g3 a direct pointer write exists: ${_g4_any_write}"; fi
if [ "$_g4_dispatch_read" -eq 1 ]; then ok "G4.i the dispatch's pointer gate reads presence from the NAME LIST (an absent name and a dead token are not the same answer)"; else no "G4.i dispatch pointer reads=${_g4_dispatch_read} — expected exactly one, via the name list"; fi
# G4.j the first-boot stager writes the pointer line exactly ONCE: systemd's EnvironmentFile is last-wins, so a second stager line would
# silently decide which volume the boot-reopen unit opens. (The cutover FSM's stager, which asserted cardinality itself, is retired, #10112.)
if [ "$_g4_stager" -eq 1 ]; then ok "G4.j the first-boot stager appears exactly once in delivered artifacts"; else no "G4.j first-boot pointer stager sites=${_g4_stager} -- expected exactly one (EnvironmentFile is last-wins)"; fi

# G4.d the pointer arm REFUSES; it never formats and never falls back to the other volume.
_PTR_ARM="$(printf '%s\n' "$_G1_STAGE" | awk '/^    if \[ "\$MODE" = pointer \]; then$/{f=1;next} f&&/^    else$/{exit} f')"
if [ -n "$_PTR_ARM" ]; then ok "G4.d1 the pointer arm extracts"; else no "G4.d1 could not extract the pointer arm — G4.d2..d4 would be vacuous"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cE '^[[:space:]]*(mkfs|printf .* cryptsetup luksFormat)|luksFormat' >/dev/null; then no "G4.d2 the pointer arm can FORMAT — it would hand Redis an empty store and call it the store"; else ok "G4.d2 the pointer arm never formats and never runs mkfs"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cF '[ "$${BLK_TYPE:-}" = crypto_LUKS ] || {' >/dev/null; then ok "G4.d3 the pointer's device must CORROBORATE as crypto_LUKS (mutation row 3)"; else no "G4.d3 the crypto_LUKS corroboration is gone — the pointer could certify a plaintext device as the store"; fi
if printf '%s\n' "$_PTR_ARM" | grep -cE '"\$DEV"' >/dev/null; then no "G4.d4 the pointer arm references the unpointed-arm device \$DEV — a fallback path exists (mutation row 2)"; else ok "G4.d4 the pointer arm never references the unpointed-arm device \$DEV (no fall-through)"; fi
# G4.e the resolver refuses both malformed pointer shapes rather than deriving a path from them.
_RES="$_res2"
if printf '%s\n' "$_RES" | grep -cF '*[!0-9]*)' >/dev/null && printf '%s\n' "$_RES" | grep -cxF '      "$LUKS_ID")' >/dev/null && printf '%s\n' "$_RES" | grep -cE '^      \*\)$' >/dev/null && printf '%s\n' "$_RES" | grep -cF 'MODE=unpointed' >/dev/null; then ok "G4.e the resolver has explicit arms for unpointed, non-numeric, own-id and third-id pointers"; else no "G4.e the resolver lost an arm (unpointed / non-numeric / own id / third id)"; fi
# G4.f the arming marker MEASURES the unit, it does not trust enable's exit status.
if grep -qF '_reopen_state="$(systemctl is-active inngest-luks-open.service 2>/dev/null || true)"' "$CLOUD_INIT" \
   && grep -qF 'if [ "$_reopen_state" = "active" ]; then' "$CLOUD_INIT"; then ok "G4.f inngest-luks-reopen-armed is emitted only when the unit reads active"; else no "G4.f the reopen arming marker trusts enable --now again — it reported success on 2026-09-17 on a boot where the unit failed"; fi

# T1.15 SKIP-VS-FAIL CONDITIONS on the boot-reopen unit (#9939). Both EnvironmentFile= paths
# are runcmd writes late in first boot, so an aborted LUKS stage or a pre-write pull-in must
# SKIP the unit — one "skipped, unmet condition check" journal notice — never FAIL it into
# the LUKS observability channel the way the observed storm did. The EnvironmentFile= lines
# stay unprefixed: once a start IS attempted, an absent file still fails the unit — the
# fail-closed contract is the point of the unit.
_LUKS_OPEN_UNIT="$(awk 'f&&/^  - path:/{exit} /^  - path: \/etc\/systemd\/system\/inngest-luks-open\.service$/{f=1} f' "$CLOUD_INIT")"
# Both directive kinds are section-scoped — ConditionPathExists= is valid in [Unit] only and
# EnvironmentFile= in [Service] only; anywhere else systemd logs an unknown lvalue and the
# property silently dies — so every needle below scopes to its directive's own section.
_LUKS_OPEN_UNITSEC="$(printf '%s\n' "$_LUKS_OPEN_UNIT" | awk '/^      \[Unit\]/{u=1;next} /^      \[/{u=0} u')"
# EnvironmentFile= is valid in [Service] only — in [Unit] it is the same inert lvalue the
# conditions would be elsewhere, so the EF needles scope to the [Service] region the same way.
_LUKS_OPEN_SVCSEC="$(printf '%s\n' "$_LUKS_OPEN_UNIT" | awk '/^      \[Service\]/{s=1;next} /^      \[/{s=0} s')"
if [ -n "$_LUKS_OPEN_UNIT" ] && [ -n "$_LUKS_OPEN_UNITSEC" ] && [ -n "$_LUKS_OPEN_SVCSEC" ]; then ok "T1.15a the inngest-luks-open.service write_files block and its [Unit]/[Service] sections extract"; else no "T1.15a could not extract the inngest-luks-open.service [Unit]/[Service] sections — T1.15b..f are vacuous"; fi
_T115_NEEDLE_DOPPLER='      ConditionPathExists=/etc/default/inngest-doppler'
_T115_NEEDLE_LUKS='      ConditionPathExists=/etc/default/inngest-luks'
if printf '%s\n' "$_LUKS_OPEN_UNITSEC" | grep -cxF "$_T115_NEEDLE_DOPPLER" >/dev/null; then ok "T1.15b the reopen unit condition-skips in [Unit] when /etc/default/inngest-doppler is absent"; else no "T1.15b no [Unit]-section ConditionPathExists=/etc/default/inngest-doppler — a pre-write start fails the unit into the journal channel"; fi
if printf '%s\n' "$_LUKS_OPEN_UNITSEC" | grep -cxF "$_T115_NEEDLE_LUKS" >/dev/null; then ok "T1.15c the reopen unit condition-skips in [Unit] when /etc/default/inngest-luks is absent"; else no "T1.15c no [Unit]-section ConditionPathExists=/etc/default/inngest-luks — a partial stage still fails the unit"; fi
if printf '%s\n' "$_LUKS_OPEN_SVCSEC" | grep -cxF '      EnvironmentFile=/etc/default/inngest-doppler' >/dev/null \
   && printf '%s\n' "$_LUKS_OPEN_SVCSEC" | grep -cxF '      EnvironmentFile=/etc/default/inngest-luks' >/dev/null \
   && ! printf '%s\n' "$_LUKS_OPEN_SVCSEC" | grep -cE '^[[:space:]]*EnvironmentFile=-' >/dev/null; then ok "T1.15d both EnvironmentFile= lines stay unprefixed in [Service] (fail-closed on a real start)"; else no "T1.15d an EnvironmentFile= line is missing, misplaced, or gained the '-' tolerant prefix — the fail-closed contract is gone"; fi
# T1.15e MUTATION CONTROL: dropping one condition line must fail T1.15c's own needle —
# the mutated block is driven through the SAME literal and the SAME count-predicate, so a
# drifted needle or a laxer predicate breaks this arm too.
_T115_MUT="$(printf '%s\n' "$_LUKS_OPEN_UNITSEC" | grep -vxF "$_T115_NEEDLE_LUKS")"
if printf '%s\n' "$_T115_MUT" | grep -cxF "$_T115_NEEDLE_LUKS" >/dev/null; then no "T1.15e mutation control failed — the T1.15c predicate cannot see a dropped condition"; else ok "T1.15e mutation: a unit missing ConditionPathExists=/etc/default/inngest-luks fails the T1.15c predicate"; fi
# T1.15f SET IDENTITY, not cardinality: the sorted path set of [Unit] conditions must equal
# the sorted path set of [Service] EnvironmentFile= values — a coordinated mismatched pair
# or a directive on any path outside /etc/default/ fails where a count comparison would pass.
_T115_EF_SET="$(printf '%s\n' "$_LUKS_OPEN_SVCSEC" | sed -n 's/^[[:space:]]*EnvironmentFile=//p' | tr ' \t' '\n' | sed '/^$/d' | sort -u)"
_T115_CX_SET="$(printf '%s\n' "$_LUKS_OPEN_UNITSEC" | sed -n 's/^[[:space:]]*ConditionPathExists=//p' | tr ' \t' '\n' | sed '/^$/d' | sort -u)"
if [ -n "$_T115_EF_SET" ] && [ "$_T115_EF_SET" = "$_T115_CX_SET" ]; then ok "T1.15f the [Unit] condition path-set equals the [Service] EnvironmentFile path-set"; else no "T1.15f EF set={${_T115_EF_SET}} vs condition set={${_T115_CX_SET}} — an unconditioned env file can fail a start"; fi
# T1.15g RESET LINES: a bare `Directive=` empties the list wholesale (EnvironmentFile= clears
# the env set, ConditionPathExists= erases every condition) — the set extractors drop the
# empty token and the literal pins keep matching the surviving lines, so the check is
# file-wide against the write_files block, not section-scoped.
if ! printf '%s\n' "$_LUKS_OPEN_UNIT" | grep -cE '^[[:space:]]*(EnvironmentFile|ConditionPathExists)=[[:space:]]*$' >/dev/null; then ok "T1.15g no bare EnvironmentFile=/ConditionPathExists= reset lines in the reopen unit"; else no "T1.15g a bare reset line empties the env set or erases every condition — systemd reset semantics make it invisible to the other arms"; fi

# ═══ T1.16 — #10217: the reopen COMPLETES the mount (the lost-race self-heal) ═══════════
# A mapper left open-but-unmounted by a first-boot attach race was unhealable by construction:
# reopen opened only, no fstab line existed, and every later boot repeated the state. ensure_mount
# converges it on the same boot. `_G1_REOPEN` (the write_files payload of inngest-luks-open.sh) is
# extracted in Guard 1 above and reused here.
_EM="$(printf '%s\n' "$_G1_REOPEN" | awk '/^      ensure_mount\(\) \{$/{f=1} f{print} f&&/^      \}$/{exit}')"
if [ -n "$_EM" ]; then ok "T1.16a ensure_mount extracts from the reopen payload"; else no "T1.16a could not extract ensure_mount — T1.16b..f are vacuous"; fi
# mountpoint -q FIRST: a healthy boot must be a strict no-op — zero writes, zero extra emits.
if printf '%s\n' "$_EM" | grep -cF 'mountpoint -q "$2"' >/dev/null; then ok "T1.16b ensure_mount's first act is the mountpoint -q fast path (a healthy boot writes nothing)"; else no "T1.16b ensure_mount lacks the mountpoint -q fast path — every boot would rewrite fstab"; fi
if printf '%s\n' "$_EM" | grep -cF 'ext4 defaults,nofail 0 2' >/dev/null; then ok "T1.16c ensure_mount writes the canonical nofail-carrying fstab line"; else no "T1.16c ensure_mount's fstab line lost 'ext4 defaults,nofail 0 2'"; fi
# fstab_set semantics: drop the mountpoint's existing line (replace, never append), then assert
# EXACTLY ONE — a second line is a silent one-boot time bomb (T1.8d's rule, applied here).
if printf '%s\n' "$_EM" | grep -cF '$2 != mp' >/dev/null && printf '%s\n' "$_EM" | grep -cF '"$_em_n" -eq 1' >/dev/null; then ok "T1.16d ensure_mount replaces the mountpoint's line in place and asserts exactly one"; else no "T1.16d ensure_mount does not do replace-then-assert-exactly-one"; fi
if printf '%s\n' "$_EM" | grep -cF 'fail reopen_fstab' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'fail reopen_mount' >/dev/null; then ok "T1.16e fstab and mount failures fail loudly under their own stage names (reopen_fstab / reopen_mount)"; else no "T1.16e an ensure_mount failure path does not fail — a silent half-mount is the defect this arm exists to heal"; fi
# The mount is FSTAB-DRIVEN: `mount "$2"` reads source and options from the line just written —
# re-typing them here would let the two disagree.
if printf '%s\n' "$_EM" | grep -cF 'mount "$2"' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'emit reopen_mount' >/dev/null; then ok "T1.16f the mount is fstab-driven (mount <mountpoint>) and success emits reopen_mount"; else no "T1.16f the mount re-types source/options, or reopen_mount is not emitted"; fi
# EVERY verified arm reaches ensure_mount — INCLUDING the open_as already-open noop path, which is
# the incident's exact post-state (mapper open, nothing mounted, no fstab line). The noop
# `return 0` inside open_as must land on the caller's ensure_mount; pin that EVERY open_as call
# is immediately followed by one.
_oa_calls="$(printf '%s\n' "$_G1_REOPEN" | grep -cE '^[[:space:]]*open_as "')"
_oa_em="$(printf '%s\n' "$_G1_REOPEN" | awk '/^[[:space:]]*open_as "/{o++ ; getline nxt; if (nxt ~ /^[[:space:]]*ensure_mount /) e++} END{print o+0, e+0}')"
# 3 -> 2 (#9786): the staging volume's open_as call went with the strip; the survivors are the
# pointer arm's `open_as "$CANON_DEV"` and the unpointed arm's `open_as "$DEV"`.
if [ "${_oa_calls}" -ge 2 ] && [ "${_oa_em#* }" -eq "$_oa_calls" ]; then ok "T1.16g every open_as call is followed by ensure_mount (${_oa_em#* }/${_oa_calls}) — the reopen_noop path still reaches it"; else no "T1.16g an open_as call is not followed by ensure_mount (${_oa_em#* }/${_oa_calls}) — the already-open noop path would leave the store unmounted"; fi
if [ "$(printf '%s\n' "$_G1_REOPEN" | grep -cF 'ensure_mount "$MAPPER" /mnt/data')" -eq 2 ]; then ok "T1.16h the pointer and unpointed crypto_LUKS arms both complete /mnt/data from the canonical mapper"; else no "T1.16h ensure_mount \"\$MAPPER\" /mnt/data is missing from an arm"; fi
# (#9786) the two pre-strip T1.16i/j pins — `ensure_mount "$DEV" /mnt/data` on the pre-cutover
# ext4-skip arm and `ensure_mount "$STAGING_MAPPER" /mnt/data-luks` on the staging arm — went with
# the arms they pinned; T1.16a-h (the strip tier above) now forbids both targets by name.
# T1.16k ORDERING PIN (CTO binding, D2/D8): the fstab write and mkdir -p must not land on a
# still-read-only root on boot >= 2. Scoped to the [Unit] section via _LUKS_OPEN_UNITSEC (T1.15).
if printf '%s\n' "$_LUKS_OPEN_UNITSEC" | grep -cxF '      After=systemd-remount-fs.service' >/dev/null; then ok "T1.16k inngest-luks-open.service is ordered After=systemd-remount-fs.service"; else no "T1.16k the reopen unit lost After=systemd-remount-fs.service — the self-heal's fstab write can race a read-only root"; fi
# T1.16l NO ENV SEAM (CTO D4): the bound is a literal 300 — an INNGEST_LUKS_ATTACH_WAIT_S
# variable would be retunable through Doppler and would need an attach_wait_invalid class to
# defend itself. Asserted ABSENT over the whole file.
if grep -qF 'INNGEST_LUKS_ATTACH_WAIT_S' "$CLOUD_INIT"; then no "T1.16l an INNGEST_LUKS_ATTACH_WAIT_S env seam is present — the bound must be a literal, not a Doppler-retunable"; else ok "T1.16l no attach-wait env seam exists (the 300s bound is a literal)"; fi
# T1.16m the `doppler run … -- bash -s <<'LUKSEOF'` invocation is BYTE-IDENTICAL to main — no
# `env -u`, nothing inserted. A whole-line exact match is the only form that also pins the
# indent and refuses a silently doubled invocation.
_T116_INVOCATION='    doppler run --project soleur-inngest --config ${inngest_doppler_config} -- bash -s <<'"'"'LUKSEOF'"'"''
if [ "$(grep -cxF "$_T116_INVOCATION" "$CLOUD_INIT")" -eq 1 ]; then ok "T1.16m the doppler run -- bash -s <<'LUKSEOF' invocation is byte-identical (no env -u strip)"; else no "T1.16m the doppler invocation drifted — something was inserted or the line moved"; fi

# ═══ T1.16n-q — design-review hardening of the self-heal (PR #10228 design pass) ═══
# T1.16n ATOMIC fstab install: a mid-write death on `cat tmp > /etc/fstab` truncates the file
# and recreates the exact unhealable state this PR eliminates (the retired inngest-luks-cutover.sh's mount-listing guard
# documents the same defect). The install must be same-dir rename: chmod + mv -f, and no
# redirect-to-/etc/fstab anywhere inside ensure_mount.
if printf '%s\n' "$_EM" | grep -cF 'mv -f "$_em_tmp" /etc/fstab' >/dev/null && ! printf '%s\n' "$_EM" | grep -cE '> */etc/fstab' >/dev/null; then ok "T1.16n the fstab install is atomic (chmod + mv -f); no redirect-to-/etc/fstab survives"; else no "T1.16n the fstab install is not an atomic rename — a mid-write death truncates /etc/fstab"; fi
# T1.16o SOURCE-CONGRUENT fast path: a bare mountpoint -q match no-ops a mount from the WRONG
# source (a stale generated mnt-*.mount can hold one — the cutover FSM's envfile-before-fstab
# desync window makes it reachable). The fast path must compare findmnt SOURCE through
# readlink -f against $1, umount the wrong-source mount, and daemon-reload after the install
# so the fstab generator re-reads the line THIS boot.
if printf '%s\n' "$_EM" | grep -cF 'findmnt -no SOURCE' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'readlink -f' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'umount "$2"' >/dev/null && [ "$(printf '%s\n' "$_EM" | awk '/mv -f/{m=NR} /daemon-reload/{print (m && NR>m) ? "ok" : "bad"; exit}')" = "ok" ]; then ok "T1.16o the fast path is source-congruent (findmnt+readlink -f), wrong-source mounts converge, and daemon-reload runs AFTER the fstab install"; else no "T1.16o the fast path is still source-blind, or daemon-reload is missing/misordered — a stale generated mount unit can loop the degrade"; fi
# T1.16p the open_as noop path must verify backing BEFORE emitting reopen_noop: the noop feeds
# ensure_mount, so a wrongly-backed mapper would be mounted + fstab'd silently. The ordering
# check asks whether backing_is was SEEN before the first reopen_noop — never compare NR against
# a possibly-unset mark (b=0 makes every direction read green; PR #10228 panel).
_OA="$(printf '%s\n' "$_G1_REOPEN" | awk '/^      open_as\(\) \{$/{f=1} f{print} f&&/^      \}$/{exit}')"
if printf '%s\n' "$_OA" | grep -cF 'backing_is' >/dev/null && printf '%s\n' "$_OA" | grep -cF 'fail reopen_backing' >/dev/null && [ "$(printf '%s\n' "$_OA" | awk '/backing_is/{b++} /reopen_noop/{print (b ? "ok" : "bad"); exit}')" = "ok" ]; then ok "T1.16p the open_as noop path asserts backing_is before reopen_noop"; else no "T1.16p an already-open mapper is accepted without a backing-device check"; fi
# T1.16q refusal strings name the TRUE bound: every 'after Ns' refusal sentence must read 300s —
# a stale 30s misreports the bound the host actually enforced, and on a no-console host these
# strings ARE the incident record.
if [ "$(grep -c 'after 300s' "$CLOUD_INIT")" -ge 4 ] && ! grep -q 'after 30s\b' "$CLOUD_INIT"; then ok "T1.16q all wait-refusal sentences name the 300s bound (no stale 30s survivors)"; else no "T1.16q a wait-refusal sentence still claims the old 30s bound"; fi

# T1.16r STACKED-MOUNT convergence + guarded findmnt: ensure_mount must not `head -1` a findmnt
# listing (the shadowed-bottom read the retired inngest-luks-cutover.sh documented), must guard the
# substitution under pipefail (`|| _em_src=""`), must compare the KERNEL-SERVED layer (tail -1),
# and must pop wrong layers with a bounded umount loop rather than guess which layer a stack
# serves — the loop's `mountpoint -q` re-check is the convergence condition.
if printf '%s\n' "$_EM" | grep -cE 'findmnt.*head -1' >/dev/null; then
  no "T1.16r ensure_mount still reads findmnt | head -1 — the shadowed-bottom read"
elif printf '%s\n' "$_EM" | grep -cF '|| _em_src=""' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'tail -1' >/dev/null && printf '%s\n' "$_EM" | grep -cE 'while mountpoint -q' >/dev/null && printf '%s\n' "$_EM" | grep -cF '-le 8' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'fail reopen_mount' >/dev/null; then
  ok "T1.16r the fast path reads the kernel-served layer and pops wrong layers in a bounded loop"
else
  no "T1.16r the stacked-mount convergence loop or the findmnt pipefail guard is missing"
fi
# T1.16s POST-CUTOVER-EVIDENCE refusal on the ext4-skip arm: an empty pointer plus an already-open
# canonical mapper or a mapper fstab line must fail reopen_pointer_lost rather than entrench the
# plaintext backstop (data-integrity review, PR #10228). BOTH disjuncts are pinned by their exact
# literals — a bare '/dev/mapper/' grep is satisfied by unrelated sites (MAPPER=, backing_is).
# (#9786) T1.16s went with the arm it pinned: the post-cutover-evidence refusal (reopen_pointer_lost)
# guarded the plaintext backstop on the ext4-skip path; with no plaintext volume the unpointed arm
# fails reopen_not_luks on any non-LUKS signature, and T1.16a's closed needle set forbids both stage
# names.
# T1.16t the class-wide fix: NO `findmnt -no SOURCE | head -1` may survive in cloud-init's
# host-side mount readers — stage mounted_from and the _sv_* checks read the kernel-served TOP
# of a stack (tail -1), which the cutover script documents as the only correct read. The same
# blind spot in inngest-redis-bootstrap.sh's guard is NOT pinnable here: that file ships via the
# baked vinngest image (GuardA byte-identity), so its fix rides the image-redelivery work (#6780),
# not this PR.
if grep -qE 'findmnt -no SOURCE.*\| head -1' "$CLOUD_INIT"; then
  no "T1.16t a findmnt | head -1 read survives in cloud-init — it reads the SHADOWED layer of a stacked mount"
else
  ok "T1.16t every cloud-init findmnt SOURCE read takes the kernel-served entry (tail -1 / single-line refuse)"
fi
# T1.16u BOTH fstab writers install atomically — same-dir mktemp + chmod + mv -f; the stage's
# fstab_set had the same cat-truncate defect the cutover script documents.
_FS="$(printf '%s\n' "$_G1_STAGE" | awk '/^    fstab_set\(\) \{$/{f=1} f{print} f&&/^    \}$/{exit}')"
if printf '%s\n' "$_FS" | grep -cF 'mv -f "$_fs_tmp" /etc/fstab' >/dev/null && ! printf '%s\n' "$_FS" | grep -cE '> */etc/fstab' >/dev/null; then ok "T1.16u the stage's fstab_set installs atomically too (mv -f, no redirect-to-/etc/fstab)"; else no "T1.16u fstab_set still installs by redirect — a mid-write death truncates /etc/fstab"; fi
# T1.16v the congruent-mount fast path still heals a LOST fstab line: mounted-from-the-right-
# source but unanchored is converged for this boot only. _em_mount gates the mount, not the write.
if printf '%s\n' "$_EM" | grep -cF '_em_mount=0' >/dev/null && printf '%s\n' "$_EM" | grep -cF 'fstab line healed' >/dev/null && printf '%s\n' "$_EM" | grep -cF '"$_em_mount" -eq 1' >/dev/null; then ok "T1.16v a congruent-but-unanchored mount rewrites the fstab line without remounting"; else no "T1.16v the fstab-heal path is gone — a lost fstab line under a live mount stays lost"; fi

# ═══ FLOOR ══════════════════════════════════════════════════════════════════════
# Raised 26 -> 51 by #6894, which added T1.8a2/c/d/e, T1.13, T1.14, G1.a-g and G4.a-f; 51 -> 56
# when the cutover FSM became the pointer's writer and the dispatch its second reader (G4.g1-g3/h/i). Derived from
# the measured count after the arms were final, not written ahead of them.
# #8285 PR B: G4.b2 (the retire dispatch's pointer reader) was deleted with that dispatch, taking the measured count 58 -> 57;
# the floor stays 57 and is now exact (no slack). Its mutation (a second pointer reader appearing) is still killed by G4.b
# (an unclassified site REDS) and G4.g2 (any dispatch-side pointer write fails; deleted in #10112, G4.g3 now carries it).
# #9939: T1.15a-e (reopen-unit ConditionPathExists= skip-vs-fail + mutation control) raised it 57 -> 62; review rounds added T1.15f set-parity (62 -> 63) then T1.15g reset-line coverage and set-identity (63 -> 64).
# #9786: 64 -> 70, exact. T1.8a2 (the staging fstab write) and G1.g (the staging mapper name) went with the
# staging block (-2); T1.16a-h (strip absence + its two controls, DEV derivation, no ext4 arm, blkid -p probe,
# the per-site prd refusal and its mutation control) are new (+8). G1.f survives re-keyed to the unpointed mkfs.
# #9786 review fix round: 70 -> 78, exact. T1.10 split into a/b (+1: emit-only and no-consumer), T1.16i (the D6
# guard DRIVEN across prd/dev/staging/empty/bare-rehearsal/rehearsal_*), T1.16j (STAGE set before the guard),
# T1.17a-e (destructive-op inventory over the whole template, the reopen script's open-only property, resolver
# refusal bodies and the reopen catch-all) are new (+8 in total with T1.10b).
# 83 -> 81 (review fix round 3, CTO ruling A: inngest_expect_luks retired): T1.10a/b and T1.11a-c (-5) are replaced by
# the single negative guard T1.10 (+1); T1.17j (device-redirect pin, +1) and T1.17k (a control that the T1.17h/j patterns
# flag the escaped-form bypass shapes, +1) are new: 83 - 5 + 1 + 1 + 1 = 81, exact.
# 78 -> 83 (review fix round 2): T1.16k (allowlist glob / rehearsal config prefix contract, +1) and the closed-set
# pins T1.17f-i (+4). T1.16i was re-driven in-arm and keeps its count.
# #10217 (merged in alongside): T1.6 expanded into T1.6a-e (per-body mechanism pin) and T1.16a-q (ensure_mount
# self-heal, ordering pin, no-seam + byte-identical invocation pins, then n-u review hardening) rode in with the
# merge. The strip takes T1.16i/j (plaintext-device and staging-mapper ensure_mount targets) and T1.16s (the
# reopen_pointer_lost refusal on the ext4-skip arm) back out (-3); the surviving T1.16h/g were re-pointed at the
# single-volume arms, and T1.17b/d/f/g were re-derived for the merged template.
# #10112 (cutover trio retired): 104 -> 100, exact. G4.g1 (no FSM writer counters), G4.g2 (a dispatch-side census that excluded no test files, superseded by G4.g3), G4.h (no unit
# injection / FSM read) and G4.j (no envfile stager) asserted that counters of deleted roles are zero; the dead classifier arms and
# counters went with them, so a reappearing site is UNCLASSIFIED (G4.b) or a direct write (G4.g3). Four assertions out.
# Fix round (#10966): 100 -> 101, exact. G4.j returns as the first-boot stager cardinality pin (the FSM stager's own cardinality check retired with it).
# Self-contained: bash builtins and this suite's own counters only. A floor that lives in a helper
# is silenced by the same move that silences the arms it guards.
if [ "$executed" -lt 101 ]; then
  fail=$((fail + 1))
  printf 'FAIL - ANTI-VACUITY: only %s assertions ran, floor is 101. Arms were deleted, skipped, or the suite exited early.\n' "$executed" >&2
else
  printf 'ok   - anti-vacuity floor: %s assertions ran (floor 101)\n' "$executed"
fi

echo ""
echo "=== inngest-redis-luks.test.sh (structural): ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
