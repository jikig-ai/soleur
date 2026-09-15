#!/usr/bin/env bash
#
# git-data-cutover access path (#6680 / ADR-220). Two guards, workflow wiring, a runtime arm.
#
# Guard 1 — git-data-cutover.sh's access_gate precedes every host mutation on the forward path
#   (DRY_RUN=0 and =1): web (every roster member) -> git-data-jump (an `ssh -W` banner through
#   web-1, no git-data credential) -> git-data-auth; a non-ok verdict exits 3 before
#   prepare_luks_target, and the EXIT trap then dials nothing. The roster and the ssh argv
#   are parsed ONCE and shared by the gate and every later call. ROLLBACK never waits on a
#   probe, writes the flag off first, and exits 4 when any recovery step could not run. No
#   probe byte reaches the runner's workflow-command parser unsanitized.
#   Observed through ONE timeline file ($TL): PATH shims for `ssh`, `doppler` and `timeout`
#   append to it, so probe calls and mutating calls are ordered in one stream.
# Guard 2 — the bridge's "Decode CI SSH private key" step exports exactly {CI_SSH_KEYFILE,
#   WEB_HOST_SSH} on the server-ip branch and exactly {TF_VAR_ci_ssh_private_key} on the
#   terraform branch. Executed, not grepped.
# Workflow — git-data-cutover.yml wiring, parsed as YAML (its header prose names every token).
# Runtime arm — the real script against real OpenSSH in the pinned ubuntu:24.04 image
#   (git-data-ownership.test.sh precedent). Under CI=true a missing docker is a FAILURE.
#
# Row ids: S<n> = plan Test Scenario n; row<n>/H<n> = plan Guard Contract matrix rows;
# G2/WF/AC = bridge, workflow and acceptance rows; R<n> = runtime arm; X = review additions.
#
# The script under test carries no test seam (ADR-214): it is driven through PATH shims only.
# GDC_* variables are seams of the SUITE, for running it against a mutated copy.
#
# Run: bash apps/web-platform/infra/git-data-cutover-access.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

# pass() cannot fail, so the runtime rows' `cond && pass || fail` is a true if/else.
# shellcheck disable=SC2015
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SCRIPT="${GDC_SCRIPT:-$DIR/git-data-cutover.sh}"
ACTION="${GDC_ACTION:-$ROOT/.github/actions/cf-tunnel-ssh-bridge/action.yml}"
WF="${GDC_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
IV="$ROOT/.github/workflows/infra-validation.yml"
# The pinned base image is owned by git-data-runcmd-rehearsal.test.sh (rule-audit.yml watches
# that copy); read it from there so a pin bump cannot leave this arm on a stale image.
REHEARSAL="$DIR/git-data-runcmd-rehearsal.test.sh"
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "$REHEARSAL" 2>/dev/null | head -1)"

passes=0; fails=0; SKIPPED=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both counters
# to move, so a neutered helper cannot report a clean run. Reported with printf + exit.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$SCRIPT" "$ACTION" "$WF" "$IV"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }
[ -n "$UBUNTU_BASE" ] || { printf 'FAIL SETUP: no UBUNTU_BASE pin readable from %s\n' "$REHEARSAL" >&2; exit 1; }

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before writes under a
# caller-supplied root so the P1b relative-operand ratchet can see the operand is absolute.
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

T="$(mktemp -d "${TMPDIR}/gdc-access.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
# A literal `exit 0` anywhere above the verdict would skip the floor; the trap turns that into
# a failure (an EXIT trap may override the exit status).
_REACHED_VERDICT=""; _rc=0
trap '_rc=$?; rm -rf "$T"; if [ "$_rc" -eq 0 ] && [ -z "$_REACHED_VERDICT" ]; then printf "FAIL: suite exited 0 before its verdict\n" >&2; exit 1; fi' EXIT
BIN="$T/bin"
mkdir -p "$BIN" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data-cutover access path (ADR-220) ===\n\n'

# ── shims ─────────────────────────────────────────────────────────────────────────────
# ssh: log argv (newlines flattened) to $TL; for -W also log its stdin; parse options the way
# ssh does; refuse an empty destination (exit 64); answer per scenario.
cat > "$BIN/ssh" <<'SHIM'
#!/usr/bin/env bash
line="ssh"
for a in "$@"; do line+=" ${a//$'\n'/ }"; done
printf '%s\n' "$line" >> "$TL"
args=("$@"); n=${#args[@]}; i=0; dest=""; w=""; cmd=()
while (( i < n )); do
  a="${args[$i]}"
  case "$a" in
    -i|-o|-l|-p|-F|-J) i=$((i + 2)) ;;
    -W) w="${args[$((i + 1))]:-}"; i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) dest="$a"; cmd=("${args[@]:$((i + 1))}"); break ;;
  esac
done
[ -n "$dest" ] || { echo "ssh-shim: empty destination" >&2; exit 64; }
if [ -n "$w" ]; then
  printf 'ssh-stdin %s\n' "$(readlink /proc/$$/fd/0)" >> "$TL"
  [ -n "${SHIM_JUMP_STDERR:-}" ] && printf '%s' "$SHIM_JUMP_STDERR" >&2
  case "${SHIM_JUMP:-banner}" in
    banner)       printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    banner_extra) printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\nextra-bytes\n'; exit 255 ;;
    line2)        printf '\nSSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    http)         printf 'HTTP/1.0 400 Bad Request\r\n'; exit 0 ;;
    none)         exit 255 ;;
  esac
fi
if [ "${cmd[*]}" = "true" ]; then
  if [ "$dest" = "10.0.1.20" ]; then
    [ "${SHIM_AUTH_RC:-0}" = 0 ] || echo "root@${dest}: Permission denied (publickey)." >&2
    exit "${SHIM_AUTH_RC:-0}"
  fi
  for r in ${SHIM_WEB_REFUSE:-}; do
    [ "$r" = "$dest" ] && { echo "root@${dest}: Permission denied (publickey)." >&2; exit "${SHIM_WEB_RC:-255}"; }
  done
  exit 0
fi
exit "${SHIM_REMOTE_RC:-1}"
SHIM
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$TL"
exit "${SHIM_DOPPLER_RC:-0}"
SHIM
# timeout: log the bound, then run the real command (so a probe without its bound is visible).
cat > "$BIN/timeout" <<'SHIM'
#!/usr/bin/env bash
printf 'timeout %s\n' "$1" >> "$TL"
shift
exec "$@"
SHIM
chmod +x "$BIN/ssh" "$BIN/doppler" "$BIN/timeout" || { printf 'FAIL SETUP: chmod shims\n' >&2; exit 1; }

WEB_INV='ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root'
GD_INV='ssh -i FIXTURE_GD_KEY -l root'

# run_case <name> [VAR=value ...] — runs the REAL script under the shims. Sets OUT, TLF, RC.
run_case() {
  local name="$1"; shift
  TLF="$T/$name.tl"; OUT="$T/$name.out"
  : > "$TLF" || { printf 'FAIL SETUP: cannot write %s\n' "$TLF" >&2; exit 1; }
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" "$@" bash "$SCRIPT" > "$OUT" 2>&1
  RC=$?
}
tl_ssh() { grep -c '^ssh ' "$TLF" || true; }
tl_line() { grep -nE -- "$1" "$TLF" | head -1 | cut -d: -f1; }
has_access() { grep -qE "^\[git-data-cutover\] ACCESS role=$1 host=[^ ]+ verdict=$2( |$)" "$OUT"; }
# Any remote that is not an access probe: LUKS/mount/rsync/systemd/sentinel/flag-write shapes.
mutating() { grep -qE '^ssh .*(cryptsetup|mountpoint|rsync|systemctl|findmnt|rm -f|touch |test -f)|^doppler secrets set' "$TLF"; }
# Detail text for a failure, neutralised so a failing row cannot raise a real annotation.
ctx() { printf 'rc=%s | out: %s | tl: %s' "$RC" "$(tail -c 600 "$OUT" | tr '\n' '|')" "$(tr '\n' '|' < "$TLF" | cut -c1-400)" | sed 's/::/: :/g; s/##\[/#-#[/g'; }

WEB_PROBE='^ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20'
JUMP_PROBE="$WEB_PROBE -W 10\\.0\\.1\\.20:22 10\\.0\\.1\\.10\$"
DOPPLER_OFF='^doppler secrets set GIT_DATA_STORE_ENABLED false --silent --no-interactive -p soleur -c prd$'

# ── GUARD 1 — access gate (unit rows) ─────────────────────────────────────────────────

# S1 / AC2 / S12 — canonical key-absent stop, under DRY_RUN=1 AND the real-cutover DRY_RUN=0.
for dr in 1 0; do
  run_case "s1d$dr" WEB_HOST_SSH="$WEB_INV" DRY_RUN="$dr" GITHUB_STEP_SUMMARY="$T/s1d$dr.summary"
  if [ "$RC" = 3 ] && has_access web ok && has_access git-data-jump ok \
     && [ "$(grep -E '^\[git-data-cutover\] ACCESS ' "$OUT" | tail -1)" = "[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
    pass "S1 (DRY_RUN=$dr): exits 3 at git-data-auth verdict=git_data_root_key_absent after web ok + jump ok"
  else fail "S1 (DRY_RUN=$dr): did not stop at git_data_root_key_absent with exit 3" "$(ctx)"; fi
  if [ "$(tl_ssh)" = 2 ] && grep -qE "$WEB_PROBE 10\\.0\\.1\\.10 true\$" "$TLF" && grep -qE "$JUMP_PROBE" "$TLF" \
     && ! mutating && [ "$(grep -c '^doppler ' "$TLF" || true)" = 0 ] && grep -q 'nothing to recover' "$OUT" && ! grep -q 'ABORT' "$OUT"; then
    pass "S1/S12 (DRY_RUN=$dr): timeline is exactly {web probe, jump probe}; the EXIT trap recovers and dials nothing"
  else fail "S1/S12 (DRY_RUN=$dr): timeline is not exactly {web probe, jump probe}, or the trap acted" "$(ctx)"; fi
done
if grep -qx 'timeout 30' "$T/s1d0.tl" && grep -qx 'timeout 25' "$T/s1d0.tl" && grep -qx 'ssh-stdin /dev/null' "$T/s1d0.tl"; then
  pass "X1: the web probe is bounded by timeout 30, the jump by timeout 25, and the jump's stdin is /dev/null"
else fail "X1: probe bounds or jump stdin changed" "$(tr '\n' '|' < "$T/s1d0.tl")"; fi
if [ "$(cat "$T/s1d1.summary" 2>/dev/null)" = "- ACCESS role=web host=10.0.1.10 verdict=ok
- ACCESS role=git-data-jump host=10.0.1.20 verdict=ok
- ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
  pass "S1: \$GITHUB_STEP_SUMMARY carries exactly the three verdict lines"
else fail "S1: \$GITHUB_STEP_SUMMARY content differs" "$(tr '\n' '|' < "$T/s1d1.summary" 2>/dev/null)"; fi

# S15 — annotations: exactly these three, ok -> ::notice, non-ok -> ::error.
if [ "$(grep -E '^::' "$T/s1d1.out")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::error title=git-data-cutover access::role=git-data-auth verdict=git_data_root_key_absent" ]; then
  pass "S15: exactly three annotations — ::notice for the ok verdicts, ::error for the stop"
else fail "S15: annotation set/levels differ" "$(grep -E '^::' "$T/s1d1.out" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# S2 / AC3 / row 1 — key present, auth refused, both DRY_RUN values.
for dr in 1 0; do
  run_case "s2d$dr" WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_AUTH_RC=255 DRY_RUN="$dr"
  if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=failed rc=255 reason=auth_refused' "$OUT" \
     && ! mutating && grep -qE '^ssh -i FIXTURE_GD_KEY -l root -o BatchMode=yes -o ConnectTimeout=20 10\.0\.1\.20 true$' "$TLF"; then
    pass "S2/row1 (DRY_RUN=$dr): auth refused -> exit 3, failed rc=255 reason=auth_refused, no mutating remote"
  else fail "S2/row1 (DRY_RUN=$dr): a refused auth did not stop the run before prepare_luks_target" "$(ctx)"; fi
done

# X2 — auth failing with a non-255 rc is still a failure.
run_case x2 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_AUTH_RC=1 DRY_RUN=0
if [ "$RC" = 3 ] && has_access git-data-auth failed && grep -q 'verdict=failed rc=1 ' "$OUT" && ! mutating; then
  pass "X2: auth rc=1 is failed (not only rc=255)"
else fail "X2: a non-255 auth failure was not caught" "$(ctx)"; fi

# S11 / H3 / row 2 — all ok, two-host roster, key set: prepare_luks_target's remote FOLLOWS every probe.
run_case s11 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" WEB_HOSTS="10.0.1.10 10.0.1.11" DRY_RUN=1
_w1="$(tl_line ' 10\.0\.1\.10 true$')"; _w2="$(tl_line ' 10\.0\.1\.11 true$')"; _j="$(tl_line ' -W 10\.0\.1\.20:22 ')"
_a="$(tl_line '^ssh -i FIXTURE_GD_KEY .* 10\.0\.1\.20 true$')"; _m="$(tl_line 'cryptsetup')"
if [ -n "$_w1" ] && [ -n "$_w2" ] && [ -n "$_j" ] && [ -n "$_a" ] && [ -n "$_m" ] \
   && [ "$_w1" -lt "$_w2" ] && [ "$_w2" -lt "$_j" ] && [ "$_j" -lt "$_a" ] && [ "$_a" -lt "$_m" ] \
   && has_access git-data-auth ok && [ "$RC" != 3 ]; then
  pass "S11/H3/row2: all probes ok -> the gate passes; web(10) < web(11) < jump < auth < prepare_luks_target remote"
else fail "S11/H3/row2: gate order in the timeline is wrong or the gate did not pass" "w1=$_w1 w2=$_w2 j=$_j a=$_a m=$_m $(ctx)"; fi
if grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.10$' "$TLF" && ! grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.11$' "$TLF"; then
  pass "row10: the jump dials the first roster member"
else fail "row10: the jump did not dial the first roster member" "$(ctx)"; fi

# S6 / row 4 — second roster member refuses.
run_case s6 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" WEB_HOSTS="10.0.1.10 10.0.1.11" SHIM_WEB_REFUSE=10.0.1.11 DRY_RUN=0
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.11 verdict=failed rc=255 reason=auth_refused' "$OUT" \
   && ! grep -qE ' -W ' "$TLF" && ! mutating; then
  pass "S6/row4: the second roster member's refusal exits 3 naming it, before the jump"
else fail "S6/row4: a refusing second roster member was not caught" "$(ctx)"; fi

# X3 — a web probe killed by its timeout (rc 124) is failed reason=timeout.
run_case x3 WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=124 DRY_RUN=0
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.10 verdict=failed rc=124 reason=timeout' "$OUT" && ! grep -qE ' -W ' "$TLF"; then
  pass "X3: a timed-out web probe (rc 124) is failed reason=timeout"
else fail "X3: a timed-out web probe was not reported as reason=timeout" "$(ctx)"; fi

# S7 / row 3 — empty roster (whitespace: an EMPTY WEB_HOSTS takes the script's default).
run_case s7 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=" " DRY_RUN=0
if [ "$RC" = 3 ] && has_access web web_roster_empty && [ "$(tl_ssh)" = 0 ]; then
  pass "S7/row3: an empty roster exits 3 with web_roster_empty and dials nothing"
else fail "S7/row3: an empty roster was not refused" "$(ctx)"; fi

# S8 — WEB_HOST_SSH unset, and blank-but-set.
for v in unset blank; do
  if [ "$v" = unset ]; then run_case "s8$v" DRY_RUN=0; else run_case "s8$v" WEB_HOST_SSH="   " DRY_RUN=0; fi
  if [ "$RC" = 3 ] && has_access web web_host_ssh_unset && [ "$(tl_ssh)" = 0 ]; then
    pass "S8 ($v): WEB_HOST_SSH $v -> web_host_ssh_unset, exit 3"
  else fail "S8 ($v): WEB_HOST_SSH $v did not produce web_host_ssh_unset + exit 3" "$(ctx)"; fi
done

# S9 — argument hygiene: option-shaped addresses that CONTAIN digits and dots (an unanchored
# host regex would accept them).
run_case s9 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS="-oProxyCommand=/tmp/1.2.sh" DRY_RUN=0
if [ "$RC" = 3 ] && has_access web invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9: an option-shaped roster member is invalid_host and never reaches ssh argv"
else fail "S9: an option-shaped roster member was not refused" "$(ctx)"; fi
run_case s9b WEB_HOST_SSH="$WEB_INV" GIT_DATA_HOST="-oProxyCommand=10.0.0.1" DRY_RUN=0
if [ "$RC" = 3 ] && has_access git-data-jump invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9b: an option-shaped GIT_DATA_HOST is invalid_host before any probe"
else fail "S9b: an option-shaped GIT_DATA_HOST was not refused" "$(ctx)"; fi

# X4 — a multi-line roster is refused as one input, never split two different ways.
run_case x4 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=$'10.0.1.10\n10.0.1.11' DRY_RUN=0
if [ "$RC" = 3 ] && has_access web invalid_multiline_input && [ "$(tl_ssh)" = 0 ]; then
  pass "X4: a multi-line WEB_HOSTS is invalid_multiline_input, nothing dialed"
else fail "X4: a multi-line WEB_HOSTS was not refused" "$(ctx)"; fi

# S10 — key set, web fails: neither jump nor auth is dialed.
run_case s10 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_WEB_REFUSE=10.0.1.10 DRY_RUN=0
if [ "$RC" = 3 ] && has_access web failed && ! grep -qE ' -W |FIXTURE_GD_KEY' "$TLF"; then
  pass "S10: a failed web probe stops before the jump and the auth probe"
else fail "S10: probes continued after a failed web probe" "$(ctx)"; fi

# S3 / row 6 — key set, jump returns no banner: jump failed, no auth probe.
FIX_R2_STDERR='channel 0: open failed: administratively prohibited: open failed'
run_case s3 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FIX_R2_STDERR"$'\n' DRY_RUN=0
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-jump host=10.0.1.20 verdict=failed rc=255 reason=forward_refused' "$OUT" \
   && ! grep -q 'FIXTURE_GD_KEY' "$TLF" && ! has_access git-data-auth '[a-z_]+'; then
  pass "S3/row6: no banner -> git-data-jump failed reason=forward_refused; the auth probe never ran"
else fail "S3/row6: a failed jump did not stop before the auth probe" "$(ctx)"; fi
if grep -qxF "[git-data-cutover] probe-stderr: ${FIX_R2_STDERR}" "$OUT"; then
  pass "S3: the failed probe's stderr is logged behind the fixed probe-stderr prefix"
else fail "S3: the failed probe's stderr was not logged" "$(ctx)"; fi

# X5 — a final stderr line without a trailing newline is still printed.
run_case x5 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="line-one"$'\n'"last-no-newline" DRY_RUN=0
if grep -qxF '[git-data-cutover] probe-stderr: last-no-newline' "$OUT"; then
  pass "X5: a final stderr line without a newline is not dropped"
else fail "X5: the final stderr line was dropped" "$(ctx)"; fi

# S4 / row 7 — banner then more output with a non-zero rc -> ok.
run_case s4 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=banner_extra DRY_RUN=0
if [ "$RC" = 3 ] && has_access git-data-jump ok && has_access git-data-auth git_data_root_key_absent; then
  pass "S4/row7: banner + more output (ssh rc 255) is jump ok — the verdict keys on the banner, not the rc"
else fail "S4/row7: a banner followed by more output was not read as ok" "$(ctx)"; fi

# S5 / X6 — banner on line 2, and a non-SSH first line -> failed.
for mode in line2 http; do
  run_case "s5$mode" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP="$mode" DRY_RUN=0
  if [ "$RC" = 3 ] && has_access git-data-jump failed; then
    pass "S5 ($mode): a first line that is not an SSH-2.0- banner is jump failed"
  else fail "S5 ($mode): a non-banner first line was accepted" "$(ctx)"; fi
done

# S14 / row 9 — forged workflow commands in probe stderr (both parsers, indented, CR/LF) never
# escape one random-token span, and the token differs per run.
FORGED=$'::error title=git-data-cutover access::role=git-data-jump verdict=ok\r\n  ::add-mask::y\n##[add-mask]x\n##[error]forged\r\n::stop-commands::guess\n'
_toks=()
for k in 1 2; do
  run_case "s14r$k" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FORGED" DRY_RUN=0
  _s14="$(python3 - "$OUT" <<'PY'
import re, sys
raw = open(sys.argv[1], 'rb').read().decode('latin-1')
if '\r' in raw: print('CR present'); sys.exit()
lines = raw.split('\n')
expected_outside = [
    '::notice title=git-data-cutover access::role=web verdict=ok',
    '::error title=git-data-cutover access::role=git-data-jump verdict=failed rc=255 reason=unknown',
]
tok = None; spans = 0; inside = False; forged_inside = 0; outside_cmds = []
for l in lines:
    if inside:
        if l == '::%s::' % tok: inside = False; continue
        if not l.startswith('[git-data-cutover] probe-stderr: '): print('unprefixed line in span: %r' % l[:80]); sys.exit()
        if any(ord(c) < 32 or ord(c) > 126 for c in l): print('non-printable in span'); sys.exit()
        if 'verdict=ok' in l or '##[' in l or '::add-mask::' in l: forged_inside += 1
        continue
    m = re.match(r'^::stop-commands::([0-9a-f]{16,})$', l)
    if m: tok = m.group(1); inside = True; spans += 1; continue
    if '##[' in l: print('legacy command outside span: %r' % l[:100]); sys.exit()
    if l.lstrip().startswith('::'): outside_cmds.append(l.lstrip())
if inside: print('span never closed'); sys.exit()
if outside_cmds != expected_outside: print('outside commands: %r' % outside_cmds); sys.exit()
if spans != 1 or forged_inside < 4: print('spans=%d forged_inside=%d' % (spans, forged_inside)); sys.exit()
print('OK ' + tok)
PY
)"
  case "$_s14" in
    OK\ *) _toks+=("${_s14#OK }"); pass "S14/row9 (run $k): forged ::/##[ bytes stay inside one span; outside it only the two script annotations exist" ;;
    *) fail "S14/row9 (run $k): probe bytes reached the workflow-command parser" "$(printf '%s' "$_s14" | sed 's/::/: :/g; s/##\[/#-#[/g')" ;;
  esac
done
if [ "${#_toks[@]}" = 2 ] && [ "${_toks[0]}" != "${_toks[1]}" ]; then
  pass "S14: the stop-commands token differs between runs"
else fail "S14: the stop-commands token did not vary (${_toks[*]:-none})"; fi

# S13 / rows 5, 8 / wall 6 — ROLLBACK: the flag-off write precedes every ssh; no probe; each
# failed recovery step annotates; any failure exits 4.
for dr in 0 1; do
  run_case "s13u$dr" ROLLBACK=1 DRY_RUN="$dr"
  if [ "$RC" = 4 ] && [ "$(tl_ssh)" = 0 ] && grep -qE "$DOPPLER_OFF" "$TLF" && ! grep -q 'ACCESS role=' "$OUT" \
     && grep -q 'rollback-only INCOMPLETE' "$OUT" && ! grep -q 'rollback-only complete' "$OUT"; then
    pass "S13/row5 (DRY_RUN=$dr): both invocations unset -> flag written off, no bare ssh, exit 4 (incomplete)"
  else fail "S13/row5 (DRY_RUN=$dr): ROLLBACK reached a bare ssh, skipped the flag write, or exited green" "$(ctx)"; fi
  if [ "$(grep -E '^::warning' "$OUT")" = "::warning title=git-data-cutover recovery::step=web_restart rc=97
::warning title=git-data-cutover recovery::step=freeze_sentinel_rm rc=97
::warning title=git-data-cutover recovery::step=web_undrain rc=97" ]; then
    pass "S13 (DRY_RUN=$dr): each unreachable step annotates rc=97 — the freeze release ignores DRY_RUN (wall 6)"
  else fail "S13 (DRY_RUN=$dr): recovery warnings differ" "$(grep -E '^::' "$OUT" | tr '\n' '|' | sed 's/::/: :/g')"; fi
done
# row 8 + no-fallback: web invocation set (and refusing), git-data unset.
run_case s13r ROLLBACK=1 DRY_RUN=1 WEB_HOST_SSH="$WEB_INV"
_f="$(tl_line "$DOPPLER_OFF")"; _s="$(tl_line '^ssh ')"
if [ "$RC" = 4 ] && [ -n "$_f" ] && [ -n "$_s" ] && [ "$_f" -lt "$_s" ] && ! grep -qE ' true$' "$TLF" \
   && ! grep -q '10\.0\.1\.20' "$TLF" && grep -qxF '::warning title=git-data-cutover recovery::step=freeze_sentinel_rm rc=97' "$OUT"; then
  pass "S13r/row8: flag off first, no probe, and the git-data step never borrows WEB_HOST_SSH (rc=97, 10.0.1.20 never dialed)"
else fail "S13r/row8: a probe ran, preceded the flag write, or git-data was dialed without GIT_DATA_SSH" "$(ctx)"; fi
# X7 — the flag write itself fails.
run_case x7 ROLLBACK=1 DRY_RUN=1 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_REMOTE_RC=0 SHIM_DOPPLER_RC=1
if [ "$RC" = 4 ] && [ "$(grep -E '^::warning' "$OUT")" = "::warning title=git-data-cutover recovery::step=set_flag rc=1" ] \
   && grep -qE ' systemctl restart soleur-web\.service$' "$TLF"; then
  pass "X7: a failed flag-off write annotates step=set_flag, the reload still runs, exit 4"
else fail "X7: a failed flag-off write was not reported or aborted the rollback" "$(ctx)"; fi
# X8 — a fully successful rollback exits 0 with no warning.
run_case x8 ROLLBACK=1 DRY_RUN=1 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_REMOTE_RC=0
if [ "$RC" = 0 ] && ! grep -qE '^::' "$OUT" && grep -q 'rollback-only complete' "$OUT" \
   && grep -qE "$DOPPLER_OFF" "$TLF" && grep -qE " rm -f '/mnt/git-data/\.cutover-freeze'\$" "$TLF"; then
  pass "X8: a rollback whose every step succeeds exits 0 with no warning"
else fail "X8: a clean rollback did not exit 0 cleanly" "$(ctx)"; fi
# X9 — a malformed roster in ROLLBACK still writes the flag off, dials nothing, exits 4.
run_case x9 ROLLBACK=1 DRY_RUN=1 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=$'10.0.1.10\n-oProxyCommand=x'
if [ "$RC" = 4 ] && grep -qE "$DOPPLER_OFF" "$TLF" && [ "$(tl_ssh)" = 0 ] \
   && grep -qxF '::warning title=git-data-cutover recovery::step=web_roster rc=3' "$OUT"; then
  pass "X9: ROLLBACK with a malformed roster writes the flag off, dials no host, exits 4"
else fail "X9: ROLLBACK with a malformed roster dialed a host or skipped the flag write" "$(ctx)"; fi

# X10 — xtrace refusal: the script refuses to run under -x before doing anything.
TLF="$T/x10.tl"; OUT="$T/x10.out"; : > "$TLF"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" WEB_HOST_SSH="$WEB_INV" DRY_RUN=0 bash -x "$SCRIPT" > "$OUT" 2>&1
RC=$?
if [ "$RC" = 78 ] && [ ! -s "$TLF" ]; then pass "X10: under bash -x the script exits 78 before any ssh or doppler call"
else fail "X10: the xtrace refusal did not fire first" "$(ctx)"; fi

# H5 — structural: access_gate is the first plain statement after the ROLLBACK block, called
# exactly once, and exits 3 from its own body. Whole-line comments stripped; a trailing comment
# on the call line is tolerated explicitly.
_code="$(sed -E 's/^[[:space:]]*#.*$//' "$SCRIPT")"
_main="$(awk '/^main\(\) \{/{m=1; next} m && /^\}/{exit} m' <<< "$_code")"
_after="$(awk 'done_rb && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*log[[:space:]]/ {print; exit} /^  fi[[:space:]]*$/ {done_rb=1}' <<< "$_main")"
_def="$(awk '/^access_gate\(\) \{/{m=1; next} m && /^\}/{exit} m' <<< "$_code")"
_calls="$(grep -cE '^[[:space:]]*access_gate[[:space:]]*(#.*)?$' <<< "$_code" || true)"
_wrapped="$(grep -cE '(\$\(|`|\||&&)[^#]*access_gate|access_gate[[:space:]]*(\|\||&&|\|)' <<< "$_code" || true)"
if grep -qE '^[[:space:]]*access_gate[[:space:]]*(#.*)?$' <<< "$_after" && [ "$_calls" = 1 ] && [ "$_wrapped" = 0 ] \
   && grep -qE '(^|[[:space:];{])exit 3([[:space:];}]|$)' <<< "$_def" && ! grep -qE 'return 3' <<< "$_def"; then
  pass "H5: access_gate is the first plain statement after the ROLLBACK block, called once, never wrapped, exits 3 from its body"
else fail "H5: access_gate call site/definition shape is wrong" "after=[$_after] calls=$_calls wrapped=$_wrapped"; fi

# AC5 — no `${X_SSH:-ssh}`-style fallback in any form (comment-stripped code).
if ! grep -qE '_SSH:?[-=]ssh\}' <<< "$_code"; then
  pass "AC5: no \${*_SSH:-ssh} / :=ssh / -ssh / =ssh fallback in git-data-cutover.sh"
else fail "AC5: an ssh fallback expansion survives" "$(grep -nE '_SSH:?[-=]ssh\}' <<< "$_code")"; fi

# X11 — the script's GIT_DATA_HOST default is the Terraform-owned private address.
_tf_ip="$(sed -nE 's/^[[:space:]]*git_data_private_ip[[:space:]]*=[[:space:]]*"([0-9.]+)".*$/\1/p' "$DIR/git-data.tf" | head -1)"
_sh_ip="$(sed -nE 's/^GIT_DATA_HOST="\$\{GIT_DATA_HOST:-([0-9.]+)\}".*$/\1/p' "$SCRIPT" | head -1)"
if [ -n "$_tf_ip" ] && [ "$_tf_ip" = "$_sh_ip" ]; then pass "X11: GIT_DATA_HOST default ($_sh_ip) equals git-data.tf local.git_data_private_ip"
else fail "X11: GIT_DATA_HOST default '$_sh_ip' != git-data.tf '$_tf_ip'"; fi

# ── GUARD 2 — the bridge's export set ─────────────────────────────────────────────────
python3 - "$ACTION" "$T/decode.sh" <<'PY' > "$T/g2.count"
import sys, yaml
act = yaml.safe_load(open(sys.argv[1]))
bodies = [s["run"] for s in (act.get("runs") or {}).get("steps") or []
          if str(s.get("name", "")).startswith("Decode CI SSH private key") and s.get("run")]
if len(bodies) == 1: open(sys.argv[2], "w").write(bodies[0])
print(len(bodies))
PY
if [ "$(cat "$T/g2.count")" != 1 ]; then
  fail "G2: extracted $(cat "$T/g2.count") 'Decode CI SSH private key' run bodies, expected exactly 1" "never a pass on zero"
else
  pass "G2: extracted exactly one 'Decode CI SSH private key' run body"
  mkdir -p "$T/g2bin" || { printf 'FAIL SETUP: mkdir g2bin\n' >&2; exit 1; }
  cat > "$T/g2bin/doppler" <<'SHIM'
#!/usr/bin/env bash
[ "$*" = "secrets get DEPLOY_SSH_PRIVATE_KEY --plain" ] || { echo "doppler-shim: unexpected argv: $*" >&2; exit 64; }
cat "$G2_KEY"
SHIM
  chmod +x "$T/g2bin/doppler"
  # _names <env-file> — NAMEs from both NAME=value and NAME<<DELIM forms, sorted, comma-joined.
  _names() {
    awk 'inh { if ($0 == delim) inh = 0; next }
         match($0, /^[A-Za-z_][A-Za-z0-9_]*<</) { print substr($0, 1, RLENGTH - 2); delim = substr($0, RLENGTH + 1); inh = 1; next }
         match($0, /^[A-Za-z_][A-Za-z0-9_]*=/) { print substr($0, 1, RLENGTH - 1) }' "$1" | LC_ALL=C sort -u | paste -sd, -
  }
  _g2_run() { # <label> <server-ip-input> <tmp-root>
    local label="$1" sip="$2" troot="$3"
    assert_fixture_dir "$troot"
    mkdir -p "$troot" || { printf 'FAIL SETUP: mkdir %s\n' "$troot" >&2; exit 1; }
    rm -f "$troot/k" "$troot/k.pub"
    ssh-keygen -q -t ed25519 -N '' -C "g2-$label" -f "$troot/k" || { printf 'FAIL SETUP: ssh-keygen\n' >&2; exit 1; }
    : > "$troot/github_env"
    env -i PATH="$T/g2bin:/usr/bin:/bin" TMPDIR="$troot" GITHUB_ENV="$troot/github_env" G2_KEY="$troot/k" \
      DOPPLER_TOKEN=fixture SERVER_IP_INPUT="$sip" bash --noprofile --norc -eo pipefail "$T/decode.sh" > "$troot/stdout" 2>&1
    G2_RC=$?; G2_ENV="$troot/github_env"
  }
  # Two server-ip values and two temp roots: the export set must not depend on either.
  for variant in 10.0.1.10 10.0.1.99; do
    _g2_run "sip-$variant" "$variant" "$T/g2-$variant"
    _got="$(_names "$G2_ENV")"
    _kf="$(sed -n 's/^CI_SSH_KEYFILE=//p' "$G2_ENV")"
    _want_inv="ssh -i ${_kf} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root"
    if [ "$G2_RC" = 0 ] && [ "$_got" = "CI_SSH_KEYFILE,WEB_HOST_SSH" ]; then
      pass "G2 (server-ip $variant): server-ip branch exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH}"
    else fail "G2 (server-ip $variant): export set is [$_got] (rc=$G2_RC), expected CI_SSH_KEYFILE,WEB_HOST_SSH" "$(tail -3 "$T/g2-$variant/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
    if [ -n "$_kf" ] && [ "$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")" = "$_want_inv" ] && cmp -s "$_kf" "$T/g2-$variant/k"; then
      pass "G2 (server-ip $variant): WEB_HOST_SSH is byte-equal to the historical invocation and the keyfile holds the key"
    else fail "G2 (server-ip $variant): WEB_HOST_SSH value or keyfile content changed" "got=[$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")] want=[$_want_inv]"; fi
  done
  _g2_run tf "" "$T/g2-tf"
  _got="$(_names "$G2_ENV")"
  if [ "$G2_RC" = 0 ] && [ "$_got" = "TF_VAR_ci_ssh_private_key" ]; then
    pass "G2: terraform branch exports exactly {TF_VAR_ci_ssh_private_key} (heredoc form parsed)"
  else fail "G2: terraform branch export set is [$_got] (rc=$G2_RC), expected TF_VAR_ci_ssh_private_key" "$(tail -3 "$T/g2-tf/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
fi

# ── WORKFLOW — git-data-cutover.yml wiring (AC6) + registration (AC10) ─────────────────
python3 - "$WF" "$IV" "$ROOT/.github/workflows/infra-validation.yml" > "$T/wf.tsv" <<'PY'
import sys, yaml, json, re
wf_text = open(sys.argv[1]).read()
wf = yaml.safe_load(wf_text); iv = yaml.safe_load(open(sys.argv[2]))
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:200].replace("\t", " ").replace("\n", " ")))
env = wf.get("env") or {}
check("WF1: workflow env WEB_HOST_PRIVATE_IP is 10.0.1.10", env.get("WEB_HOST_PRIVATE_IP") == "10.0.1.10", env.get("WEB_HOST_PRIVATE_IP"))
steps = ((wf.get("jobs") or {}).get("cutover") or {}).get("steps") or []
names = [str(s.get("name", "")) for s in steps]
bridge = [i for i, s in enumerate(steps) if s.get("uses") == "./.github/actions/cf-tunnel-ssh-bridge"]
run = [i for i, n in enumerate(names) if n == "Run git-data cutover"]
tear = [i for i, n in enumerate(names) if n == "Tear down cloudflared SSH bridge"]
check("WF2: exactly one bridge step", len(bridge) == 1, len(bridge))
b = steps[bridge[0]] if len(bridge) == 1 else {}
check("WF3: bridge passes server-ip from env.WEB_HOST_PRIVATE_IP", (b.get("with") or {}).get("server-ip") == "${{ env.WEB_HOST_PRIVATE_IP }}", (b.get("with") or {}).get("server-ip"))
check("WF4: bridge step carries no if: (dry-run is host-touching)", bool(b) and "if" not in b)
check("WF5: exactly one Run step", len(run) == 1, len(run))
r = steps[run[0]] if len(run) == 1 else {}
check("WF6: Run step env.WEB_HOSTS is env.WEB_HOST_PRIVATE_IP", ((r.get("env") or {}).get("WEB_HOSTS")) == "${{ env.WEB_HOST_PRIVATE_IP }}", (r.get("env") or {}).get("WEB_HOSTS"))
EXPECT_IF = "${{ !cancelled() && (success() || (inputs.rollback && steps.confirm.outcome == 'success' && steps.doppler.outcome == 'success' && steps.secrets_check.outcome == 'success')) }}"
check("WF10: Run step reaches a ROLLBACK past a failed bridge, never past a failed confirm/doppler/secrets step", r.get("if") == EXPECT_IF, r.get("if"))
ids = {s.get("id"): i for i, s in enumerate(steps) if s.get("id")}
check("WF11: confirm/doppler/secrets step ids exist and precede the bridge",
      all(k in ids for k in ("confirm", "doppler", "secrets_check")) and bool(bridge) and all(ids[k] < bridge[0] for k in ("confirm", "doppler", "secrets_check") if k in ids), ids)
check("WF7: exactly one teardown step, if: always(), after the Run step",
      len(tear) == 1 and bool(run) and tear[0] > run[0] and steps[tear[0]].get("if") == "always()", (tear, run))
body = (steps[tear[0]].get("run") or "") if len(tear) == 1 else ""
code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
check("WF8: teardown (comments stripped) deletes the NAT rule, kills cloudflared and shreds the keyfile, each -n guarded",
      all(t in code for t in ('[[ -n "${SERVER_IP:-}" ]]', 'iptables -t nat -D OUTPUT', '[[ -n "${CLOUDFLARED_PID:-}" ]]', '[[ -n "${CI_SSH_KEYFILE:-}" && -f "$CI_SSH_KEYFILE" ]]', 'shred -u "$CI_SSH_KEYFILE"')))
secrets = sorted(set(re.findall(r"secrets\s*(?:\.\s*([A-Za-z0-9_]+)|\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\])", json.dumps(wf))))
names_s = sorted(set(a or b for a, b in secrets))
check("WF9: no secret beyond DOPPLER_TOKEN and DOPPLER_TOKEN_WRITE is referenced anywhere in the workflow", names_s == ["DOPPLER_TOKEN", "DOPPLER_TOKEN_WRITE"], names_s)
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
mine = [s for s in ivsteps if isinstance(s.get("run"), str) and s["run"].strip() == "bash apps/web-platform/infra/git-data-cutover-access.test.sh"]
check("AC10: infra-validation.yml runs this suite in exactly one step with no if:/continue-on-error",
      len(mine) == 1 and "if" not in mine[0] and not mine[0].get("continue-on-error"), len(mine))
print("\n".join(out))
PY
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -ge 12 ] || fail "WF: only $_wf_n workflow verdicts were produced (expected 12) — the YAML leg crashed" "$(head -c 300 "$T/wf.tsv")"

# ── RUNTIME ARM — real OpenSSH (pinned ubuntu:24.04) ─────────────────────────────────
RUNTIME_ROWS=9
_runtime_skip() {
  if [ "${CI:-}" = "true" ]; then
    fail "runtime arm: $1 — and CI=true, so this is a FAILURE: the runner must provide docker"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  else
    SKIPPED=$((SKIPPED + RUNTIME_ROWS)); printf '  SKIP runtime arm (%s rows): %s\n' "$RUNTIME_ROWS" "$1"
  fi
}
if [ "${GDC_SKIP_RUNTIME:-}" = 1 ] && [ "${CI:-}" != "true" ]; then _runtime_skip "GDC_SKIP_RUNTIME=1 (local iteration)"
elif ! command -v docker >/dev/null 2>&1; then _runtime_skip "docker absent"
elif ! docker info >/dev/null 2>&1; then _runtime_skip "docker daemon unreachable"
else
  mkdir -p "$T/rt/out" || { printf 'FAIL SETUP: mkdir rt\n' >&2; exit 1; }
  cp "$SCRIPT" "$T/rt/git-data-cutover.sh" || { printf 'FAIL SETUP: cp script\n' >&2; exit 1; }
  cat > "$T/rt/drive.sh" <<'DRV'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq openssh-server openssh-client netcat-openbsd >/dev/null 2>&1 || { echo FIXTURE_APT_FAILED; exit 100; }
mkdir -p /run/sshd /root/.ssh && chmod 700 /root/.ssh
ssh-keygen -A >/dev/null 2>&1
ssh-keygen -q -t ed25519 -N '' -f /tmp/k && cp /tmp/k.pub /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
sshd_on() { # addr port extra-option...
  local a="$1" p="$2"; shift 2
  # stdout/stderr to /dev/null: a backgrounded child holding the $(...) pipe open makes the
  # caller's command substitution wait for it forever.
  /usr/sbin/sshd -D -o ListenAddress="$a" -p "$p" -o PasswordAuthentication=no -o PermitRootLogin=prohibit-password "$@" -E "/tmp/sshd-$a-$p.log" >/dev/null 2>&1 &
  echo $!
}
WEB_OK=$(sshd_on 127.0.0.1 2201)
WEB_NOFWD=$(sshd_on 127.0.0.1 2202 -o AllowTcpForwarding=no)
GD=$(sshd_on 127.0.0.2 22)
sleep 1
echo FIXTURE_OK
row() { printf '%s=%s\n' "$1" "$2" >> /out/rows; }
drive() { # label web-port
  local s e rc
  s=$(date +%s)
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root DRY_RUN=0 WEB_HOSTS=127.0.0.1 GIT_DATA_HOST=127.0.0.2 \
    WEB_HOST_SSH="ssh -i /tmp/k -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -p $2 -l root" \
    bash /work/git-data-cutover.sh > "/out/$1.out" 2>&1
  rc=$?; e=$(date +%s)
  row "$1_rc" "$rc"; row "$1_elapsed" "$((e - s))"
}
drive r1 2201
drive r2 2202
kill "$GD"; wait "$GD" 2>/dev/null
drive r3 2201
( while :; do printf 'HTTP/1.0 400 Bad Request\r\n\r\n' | nc -N -l 127.0.0.2 22 >/dev/null 2>&1; done ) >/dev/null 2>&1 &
# The listener serves one connection per loop turn, so a second confirming probe would race its
# restart: record the first success, then let it re-arm before the real probe.
listening=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if nc -z 127.0.0.2 22 2>/dev/null; then listening=1; break; fi
  sleep 0.5
done
row r4_listening "$listening"
sleep 1
drive r4 2201
kill "$WEB_OK" "$WEB_NOFWD" 2>/dev/null
echo DRIVER_DONE
DRV
  : > "$T/rt/out/rows"
  # Bounded: a hung driver must fail this arm loudly, never eat the CI job's clock.
  _cname="gdc-access-$$-${RANDOM}"
  timeout -k 10 420 docker run --rm --name "$_cname" -v "$T/rt/drive.sh:/work/drive.sh:ro" \
    -v "$T/rt/git-data-cutover.sh:/work/git-data-cutover.sh:ro" \
    -v "$T/rt/out:/out" "$UBUNTU_BASE" bash /work/drive.sh > "$T/rt/stdout" 2>&1
  DRC=$?
  docker rm -f "$_cname" >/dev/null 2>&1 || true
  if grep -qx DRIVER_DONE "$T/rt/stdout"; then
    _rv() { sed -n "s/^$1=//p" "$T/rt/out/rows" | tail -1; }
    _acc() { grep -qE "^\[git-data-cutover\] ACCESS role=$2 host=[^ ]+ verdict=$3( |$)" "$T/rt/out/$1.out"; }
    _rctx() { tr '\n' '|' < "$T/rt/out/$1.out" | tail -c 500 | sed 's/::/: :/g'; }
    { [ "$(_rv r1_rc)" = 3 ] && _acc r1 web ok; } && pass "R1a: real sshd — web ok and the run exits 3" || fail "R1a: real-sshd web probe/exit" "rc=$(_rv r1_rc) $(_rctx r1)"
    _acc r1 git-data-jump ok && pass "R1b: real sshd — ssh -W returns the target's SSH-2.0- banner (jump ok, no git-data credential)" || fail "R1b: real-sshd jump not ok" "$(_rctx r1)"
    _acc r1 git-data-auth git_data_root_key_absent && pass "R1c: real sshd — git-data-auth verdict=git_data_root_key_absent" || fail "R1c: real-sshd auth verdict" "$(_rctx r1)"
    _el="$(_rv r1_elapsed)"
    { [ -n "$_el" ] && [ "$_el" -lt 20 ]; } && pass "R1d: the canonical gate finished in ${_el}s (< 20s; the jump's own bound is 25s)" || fail "R1d: the gate took ${_el:-?}s (>= 20s)" "$(_rctx r1)"
    { [ "$(_rv r2_rc)" = 3 ] && grep -qE 'role=git-data-jump host=[^ ]+ verdict=failed rc=[0-9]+ reason=forward_refused$' "$T/rt/out/r2.out"; } \
      && pass "R2a: AllowTcpForwarding no — jump failed reason=forward_refused, exit 3" || fail "R2a: forwarding-refused jump not failed/forward_refused" "$(_rctx r2)"
    grep -qxF '[git-data-cutover] probe-stderr: channel 0: open failed: administratively prohibited: open failed' "$T/rt/out/r2.out" \
      && pass "R2b: the real refusal stderr matches the unit rows' fixture text" || fail "R2b: real refusal stderr differs from the fixture" "$(_rctx r2)"
    { [ "$(_rv r3_rc)" = 3 ] && grep -qE 'role=git-data-jump host=[^ ]+ verdict=failed rc=[0-9]+ reason=connect_refused$' "$T/rt/out/r3.out"; } \
      && pass "R3: git-data sshd stopped — jump failed reason=connect_refused" || fail "R3: stopped target not failed/connect_refused" "$(_rctx r3)"
    [ "$(_rv r4_listening)" = 1 ] && pass "R4a: the non-SSH listener was bound before the probe (R4b is not a refused connect)" || fail "R4a: the non-SSH listener never bound" "$(_rctx r4)"
    { [ "$(_rv r4_rc)" = 3 ] && _acc r4 git-data-jump failed && ! grep -q 'connect failed' "$T/rt/out/r4.out"; } \
      && pass "R4b (negative control): a non-SSH listener is jump failed — the banner rule can fail" || fail "R4b: a non-SSH listener was accepted as a banner, or was never reached" "$(_rctx r4)"
  elif grep -qx FIXTURE_APT_FAILED "$T/rt/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$T/rt/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$T/rt/stdout" | tr '\n' ' ' | sed 's/::/: :/g')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER (ADR-193: reported with printf + exit, never through pass()/fail()) ─────
# Guard 1: S1 x2x2 + X1 + summary + S15 + S2 x2 + X2 + S11 + row10 + S6 + X3 + S7 + S8 x2 + S9 + S9b
#   + X4 + S10 + S3 x2 + X5 + S4 + S5 x2 + S14 x2 + token + S13 x2x2 + S13r + X7 + X8 + X9 + X10
#   + H5 + AC5 + X11 = 42.  Guard 2: 1 + 2x2 + 1 = 6.  Workflow: 12.  Runtime: 9.  Total 69.
FLOOR=69
_ran=$((passes + fails + SKIPPED))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran/declared, floor is %s — cases were deleted, skipped, or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-cutover-access: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
_REACHED_VERDICT=1
exit $(( ${#FAILURES[@]} > 0 ))
