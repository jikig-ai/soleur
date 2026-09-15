#!/usr/bin/env bash
#
# git-data-cutover read-only proof (#6680 / #8189 / ADR-220). Access gate, store probes, captured
# values, real-mode refusal, workflow wiring, the root-token census, and a runtime arm.
#
# Access gate — git-data-cutover.sh's access_gate runs web (every roster member) -> git-data-jump
#   (an `ssh -W` banner through web-1, no git-data credential) -> git-data-auth; a non-ok verdict
#   exits 3 before any store probe. No probe byte reaches the runner's workflow-command parser
#   unsanitized. Observed through ONE timeline file ($TL): PATH shims for `ssh`, `doppler` and
#   `timeout` append to it, so every remote call is ordered in one stream.
# Guard 2 (plan) — no run exits 0 on an unmounted, cut-over or non-empty store; each probe fails
#   closed; the script carries no rsync/cryptsetup/mount/umount/mkfs/touch/rm -rf/systemctl/doppler.
# Guard 3 — DOPPLER_TOKEN_GIT_DATA_ROOT is named under .github/ only by git-data-cutover.yml job
#   `cutover` (environment web-platform-infra-apply); `secrets: inherit` sites are the known set.
# Guard 5 — gd_capture bounds (30 s, 4096 bytes), anchors and never prints a captured value; no
#   raw capture of an ssh invocation outside it.
# Guard 6 (cutover half) — workflow-level git-data-state, cancel-in-progress False, the literal
#   equal to git_data_host_replace's group in apply-web-platform-infra.yml.
# Guard 7 — the workflow's inputs are exactly {confirm}; DRY_RUN/ROLLBACK/CONFIRM_WIPE carrying a
#   non-default value exits 5 with an EMPTY timeline.
# Bridge — the "Decode CI SSH private key" step exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH} on
#   the server-ip branch and exactly {TF_VAR_ci_ssh_private_key} on the terraform branch.
# Workflow (D-6 / AC9) — parsed as YAML (`on:` read through the True-key lookup); the key-fetch,
#   ssh_config and secrets-check step bodies are EXECUTED, not grepped.
# Runtime arm — the real script against real OpenSSH in the pinned ubuntu:24.04 image, including
#   the workflow's own ssh_config writer end to end through a web-1 jump. Under CI=true a missing
#   docker is a FAILURE.
#
# Harness conventions (plan › Guard Contract): code-edit rows run as MUTANTS through mutate()
# (copy, sed the copy, assert the edit landed on the expected diff-line count, point the suite's
# override at the copy, require the NAMED case RED); fixture rows are negative cases; floors are
# reported with printf + exit, never through pass()/fail().
#
# The script under test carries no test seam (ADR-214): it is driven through PATH shims only.
# GDC_* variables are seams of the SUITE (GDC_SCRIPT, GDC_WORKFLOW, GDC_GITHUB_DIR, GDC_ACTION).
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
GHDIR="${GDC_GITHUB_DIR:-$ROOT/.github}"
IV="$ROOT/.github/workflows/infra-validation.yml"
APPLY_WF="$ROOT/.github/workflows/apply-web-platform-infra.yml"
# The pinned base image is owned by git-data-runcmd-rehearsal.test.sh (rule-audit.yml watches
# that copy); read it from there so a pin bump cannot leave this arm on a stale image.
REHEARSAL="$DIR/git-data-runcmd-rehearsal.test.sh"
UBUNTU_BASE="$(sed -nE "s/^UBUNTU_BASE='(ubuntu:24\.04@sha256:[0-9a-f]{64})'\$/\1/p" "$REHEARSAL" 2>/dev/null | head -1)"

passes=0; fails=0; SKIPPED=0; MUTANTS_RUN=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both counters
# to move, so a neutered helper cannot report a clean run. Reported with printf + exit.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$SCRIPT" "$ACTION" "$WF" "$IV" "$APPLY_WF"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }
[ -n "$UBUNTU_BASE" ] || { printf 'FAIL SETUP: no UBUNTU_BASE pin readable from %s\n' "$REHEARSAL" >&2; exit 1; }
REAL_TIMEOUT="$(command -v timeout)" || { printf 'FAIL SETUP: timeout(1) not found\n' >&2; exit 1; }
command -v ssh-keygen >/dev/null 2>&1 || { printf 'FAIL SETUP: ssh-keygen not found\n' >&2; exit 1; }
command -v ssh >/dev/null 2>&1 || { printf 'FAIL SETUP: ssh not found\n' >&2; exit 1; }

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
mkdir -p "$BIN" "$T/mut" "$T/steps" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data-cutover read-only proof (ADR-220, #8189) ===\n\n'

# ── shims ─────────────────────────────────────────────────────────────────────────────
# ssh: log argv (newlines flattened) and its stdin to $TL; parse options the way ssh does;
# refuse an empty destination (exit 64); answer per scenario.
cat > "$BIN/ssh" <<'SHIM'
#!/usr/bin/env bash
line="ssh"
for a in "$@"; do line+=" ${a//$'\n'/ }"; done
printf '%s\n' "$line" >> "$TL"
printf 'ssh-stdin %s\n' "$(readlink /proc/$$/fd/0)" >> "$TL"
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
  [ -n "${SHIM_JUMP_STDERR:-}" ] && printf '%s' "$SHIM_JUMP_STDERR" >&2
  case "${SHIM_JUMP:-banner}" in
    banner)       printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    banner_extra) printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\nextra-bytes\n'; exit 255 ;;
    line2)        printf '\nSSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    http)         printf 'HTTP/1.0 400 Bad Request\r\n'; exit 0 ;;
    none)         exit 255 ;;
  esac
fi
c="${cmd[*]}"
if [ "$c" = "true" ]; then
  if [ "$dest" = "10.0.1.20" ]; then
    [ "${SHIM_AUTH_RC:-0}" = 0 ] || echo "root@${dest}: Permission denied (publickey)." >&2
    exit "${SHIM_AUTH_RC:-0}"
  fi
  for r in ${SHIM_WEB_REFUSE:-}; do
    [ "$r" = "$dest" ] && { echo "root@${dest}: Permission denied (publickey)." >&2; exit "${SHIM_WEB_RC:-255}"; }
  done
  exit 0
fi
case "$c" in
  "findmnt -no SOURCE "*)
    case "${SHIM_FINDMNT:-dev}" in
      dev)    printf '/dev/sdb\n' ;;
      mapper) printf '/dev/mapper/git-data\n' ;;
      empty)  : ;;
      rc1)    exit 1 ;;
      tmpfs)  printf 'tmpfs\n' ;;
      line2)  printf '/dev/sdb\nCANARY-SECOND-LINE-7f3a\n' ;;
      noeol)  printf '/dev/sdb' ;;
      big)    printf '/dev/'; head -c 5000 /dev/zero | tr '\0' a ;;
      hang)   exec sleep 30 ;;
    esac
    exit 0 ;;
  "d="*)
    case "${SHIM_COUNT:-zero}" in
      zero)    printf '0\n' ;;
      one)     printf '1\n' ;;
      zero2nl) printf '0\n\n' ;;
      err)     echo "find: cannot open directory: Permission denied" >&2; exit 4 ;;
      exec)    exec bash -c "$c" ;;
    esac
    exit 0 ;;
esac
exit "${SHIM_REMOTE_RC:-1}"
SHIM
# doppler: the script must never call it. Logged and refused.
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$TL"
echo "doppler-shim: git-data-cutover.sh must not call doppler" >&2
exit 1
SHIM
# timeout: log the bound, then run the real command (so a probe without its bound is visible).
# SHIM_TIMEOUT_S swaps in a REAL timeout with a short bound, for the hung-host rows.
cat > "$BIN/timeout" <<SHIM
#!/usr/bin/env bash
printf 'timeout %s\n' "\$1" >> "\$TL"
shift
if [ -n "\${SHIM_TIMEOUT_S:-}" ]; then exec "$REAL_TIMEOUT" "\$SHIM_TIMEOUT_S" "\$@"; fi
exec "\$@"
SHIM
chmod +x "$BIN/ssh" "$BIN/doppler" "$BIN/timeout" || { printf 'FAIL SETUP: chmod shims\n' >&2; exit 1; }

WEB_INV='ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root'
GD_INV='ssh -F /fixture/gd-ssh-config'

# run_case <name> [VAR=value ...] — runs the script (CASE_SCRIPT, default the real one) under the
# shims, bounded by CASE_TIMEOUT. Sets OUT, TLF, RC.
run_case() {
  local name="$1"; shift
  TLF="$T/$name.tl"; OUT="$T/$name.out"
  : > "$TLF" || { printf 'FAIL SETUP: cannot write %s\n' "$TLF" >&2; exit 1; }
  "$REAL_TIMEOUT" -k 3 "${CASE_TIMEOUT:-60}" env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" "$@" \
    bash "${CASE_SCRIPT:-$SCRIPT}" > "$OUT" 2>&1
  RC=$?
}
tl_ssh() { grep -c '^ssh ' "$TLF" || true; }
tl_line() { grep -nE -- "$1" "$TLF" | head -1 | cut -d: -f1; }
has_access() { grep -qE "^\[git-data-cutover\] ACCESS role=$1 host=[^ ]+ verdict=$2( |$)" "$OUT"; }
has_store() { grep -qE "^\[git-data-cutover\] STORE probe=$1 verdict=$2( |$)" "$OUT"; }
# Any remote that is not a read: LUKS/mount/rsync/systemd/sentinel shapes, or any doppler call.
# findmnt is a READ (the store probe) and is deliberately not in this list.
mutating() { grep -qE '^ssh .*(cryptsetup|mountpoint|rsync|systemctl|rm -f|touch |test -f|(^| )u?mount )|^doppler ' "$TLF"; }
no_count_probe() { ! grep -qE '^ssh .* d=' "$TLF"; }
# Detail text for a failure, neutralised so a failing row cannot raise a real annotation.
ctx() { printf 'rc=%s | out: %s | tl: %s' "$RC" "$(tail -c 600 "$OUT" | tr '\n' '|')" "$(tr '\n' '|' < "$TLF" | cut -c1-400)" | sed 's/::/: :/g; s/##\[/#-#[/g'; }

WEB_PROBE='^ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20'
JUMP_PROBE="$WEB_PROBE -W 10\\.0\\.1\\.20:22 10\\.0\\.1\\.10\$"
KEYED=(WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV")

# mutate <name> <file> <expected-diff-lines> <sed -E program> — copies <file> to $T/mut/<name>,
# applies the edit, and requires it to have landed on exactly the expected number of diff lines
# (`<` plus `>`). Sets MUTANT. A mutation that does not land reports the baseline, which is
# indistinguishable from a pass — so the landing is itself an assertion.
MUTANT=""
mutate() {
  local name="$1" src="$2" want="$3" expr="$4" got
  MUTANT="$T/mut/$name.$(basename "$src")"
  cp "$src" "$MUTANT" || { printf 'FAIL SETUP: mutation copy %s\n' "$name" >&2; exit 1; }
  if ! sed -E -i "$expr" "$MUTANT" 2>"$T/mut/$name.sed.err"; then
    fail "M-$name: mutation sed failed" "$(head -1 "$T/mut/$name.sed.err")"; return 1
  fi
  got="$(diff "$src" "$MUTANT" | grep -cE '^[<>]' || true)"
  # A script mutant that no longer parses would go RED for the wrong reason.
  if [ "${src%.sh}" != "$src" ] && ! bash -n "$MUTANT" 2>/dev/null; then
    fail "M-$name: the mutant does not parse (bash -n) — it would go RED for the wrong reason" "sed -E [$expr]"; return 1
  fi
  if [ "$got" != "$want" ]; then
    fail "M-$name: mutation landed on $got diff line(s), expected $want" "sed -E [$expr]"; return 1
  fi
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
# mutant_red <name> <case-fn> [args...] — the named case must go RED against $MUTANT.
mutant_red() {
  local name="$1"; shift
  if "$@"; then fail "M-$name: the named case stayed GREEN against the mutant" "$(ctx)"
  else pass "M-$name: the named case goes RED against the mutant"; fi
}

# ── ACCESS GATE (unit rows) ───────────────────────────────────────────────────────────

# S1 / S12 — canonical key-absent stop, with the real-mode variables unset AND set to their defaults.
for mode in unset defaults; do
  if [ "$mode" = unset ]; then run_case "s1$mode" WEB_HOST_SSH="$WEB_INV" GITHUB_STEP_SUMMARY="$T/s1$mode.summary"
  else run_case "s1$mode" WEB_HOST_SSH="$WEB_INV" DRY_RUN=1 ROLLBACK=0 CONFIRM_WIPE=0 GITHUB_STEP_SUMMARY="$T/s1$mode.summary"; fi
  if [ "$RC" = 3 ] && has_access web ok && has_access git-data-jump ok \
     && [ "$(grep -E '^\[git-data-cutover\] ACCESS ' "$OUT" | tail -1)" = "[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
    pass "S1 ($mode): exits 3 at git-data-auth verdict=git_data_root_key_absent after web ok + jump ok"
  else fail "S1 ($mode): did not stop at git_data_root_key_absent with exit 3" "$(ctx)"; fi
  if [ "$(tl_ssh)" = 2 ] && grep -qE "$WEB_PROBE 10\\.0\\.1\\.10 true\$" "$TLF" && grep -qE "$JUMP_PROBE" "$TLF" \
     && ! mutating && ! grep -q 'STORE ' "$OUT"; then
    pass "S1/S12 ($mode): timeline is exactly {web probe, jump probe}; no store probe and no doppler call"
  else fail "S1/S12 ($mode): timeline is not exactly {web probe, jump probe}" "$(ctx)"; fi
done
if grep -qx 'timeout 30' "$T/s1unset.tl" && grep -qx 'timeout 25' "$T/s1unset.tl" && ! grep -qv -e '^ssh' -e '^timeout' "$T/s1unset.tl" \
   && [ "$(grep -c '^ssh-stdin ' "$T/s1unset.tl")" = 2 ] && ! grep '^ssh-stdin ' "$T/s1unset.tl" | grep -vqx 'ssh-stdin /dev/null'; then
  pass "X1: the web probe is bounded by timeout 30, the jump by timeout 25, and every probe's stdin is /dev/null"
else fail "X1: probe bounds or stdin changed" "$(tr '\n' '|' < "$T/s1unset.tl")"; fi
if [ "$(cat "$T/s1unset.summary" 2>/dev/null)" = "- ACCESS role=web host=10.0.1.10 verdict=ok
- ACCESS role=git-data-jump host=10.0.1.20 verdict=ok
- ACCESS role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent" ]; then
  pass "S1: \$GITHUB_STEP_SUMMARY carries exactly the three verdict lines"
else fail "S1: \$GITHUB_STEP_SUMMARY content differs" "$(tr '\n' '|' < "$T/s1unset.summary" 2>/dev/null)"; fi

# S15 — annotations: exactly these three, ok -> ::notice, non-ok -> ::error.
if [ "$(grep -E '^::' "$T/s1unset.out")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::error title=git-data-cutover access::role=git-data-auth verdict=git_data_root_key_absent" ]; then
  pass "S15: exactly three annotations — ::notice for the ok verdicts, ::error for the stop"
else fail "S15: annotation set/levels differ" "$(grep -E '^::' "$T/s1unset.out" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# S2 / row 1 — key present, auth refused.
run_case s2 "${KEYED[@]}" SHIM_AUTH_RC=255
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-auth host=10.0.1.20 verdict=failed rc=255 reason=auth_refused' "$OUT" \
   && ! mutating && no_count_probe && ! grep -q 'findmnt' "$TLF" \
   && grep -qE '^ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10\.0\.1\.20 true$' "$TLF"; then
  pass "S2/row1: auth refused -> exit 3, failed rc=255 reason=auth_refused, no store probe"
else fail "S2/row1: a refused auth did not stop the run before the store probes" "$(ctx)"; fi

# X2 — auth failing with a non-255 rc is still a failure.
run_case x2 "${KEYED[@]}" SHIM_AUTH_RC=1
if [ "$RC" = 3 ] && has_access git-data-auth failed && grep -q 'verdict=failed rc=1 ' "$OUT" && ! grep -q 'findmnt' "$TLF"; then
  pass "X2: auth rc=1 is failed (not only rc=255)"
else fail "X2: a non-255 auth failure was not caught" "$(ctx)"; fi

# S11 / H3 / row 2 — all ok, two-host roster, key set: the first store probe FOLLOWS every access probe.
run_case s11 "${KEYED[@]}" WEB_HOSTS="10.0.1.10 10.0.1.11"
_w1="$(tl_line ' 10\.0\.1\.10 true$')"; _w2="$(tl_line ' 10\.0\.1\.11 true$')"; _j="$(tl_line ' -W 10\.0\.1\.20:22 ')"
_a="$(tl_line '^ssh -F /fixture/gd-ssh-config .* 10\.0\.1\.20 true$')"; _m="$(tl_line ' findmnt -no SOURCE ')"
if [ -n "$_w1" ] && [ -n "$_w2" ] && [ -n "$_j" ] && [ -n "$_a" ] && [ -n "$_m" ] \
   && [ "$_w1" -lt "$_w2" ] && [ "$_w2" -lt "$_j" ] && [ "$_j" -lt "$_a" ] && [ "$_a" -lt "$_m" ] \
   && has_access git-data-auth ok && [ "$RC" = 0 ]; then
  pass "S11/H3/row2: all probes ok -> the gate passes; web(10) < web(11) < jump < auth < findmnt probe"
else fail "S11/H3/row2: gate order in the timeline is wrong or the gate did not pass" "w1=$_w1 w2=$_w2 j=$_j a=$_a m=$_m $(ctx)"; fi
if grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.10$' "$TLF" && ! grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.11$' "$TLF"; then
  pass "row10: the jump dials the first roster member"
else fail "row10: the jump did not dial the first roster member" "$(ctx)"; fi

# S6 / row 4 — second roster member refuses.
run_case s6 "${KEYED[@]}" WEB_HOSTS="10.0.1.10 10.0.1.11" SHIM_WEB_REFUSE=10.0.1.11
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.11 verdict=failed rc=255 reason=auth_refused' "$OUT" \
   && ! grep -qE ' -W ' "$TLF" && ! mutating; then
  pass "S6/row4: the second roster member's refusal exits 3 naming it, before the jump"
else fail "S6/row4: a refusing second roster member was not caught" "$(ctx)"; fi

# X3 — a web probe killed by its timeout (rc 124) is failed reason=timeout.
run_case x3 WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10 SHIM_WEB_RC=124
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=web host=10.0.1.10 verdict=failed rc=124 reason=timeout' "$OUT" && ! grep -qE ' -W ' "$TLF"; then
  pass "X3: a timed-out web probe (rc 124) is failed reason=timeout"
else fail "X3: a timed-out web probe was not reported as reason=timeout" "$(ctx)"; fi

# S7 / row 3 — empty roster (whitespace: an EMPTY WEB_HOSTS takes the script's default).
run_case s7 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=" "
if [ "$RC" = 3 ] && has_access web web_roster_empty && [ "$(tl_ssh)" = 0 ]; then
  pass "S7/row3: an empty roster exits 3 with web_roster_empty and dials nothing"
else fail "S7/row3: an empty roster was not refused" "$(ctx)"; fi

# S8 — WEB_HOST_SSH unset, and blank-but-set.
for v in unset blank; do
  if [ "$v" = unset ]; then run_case "s8$v"; else run_case "s8$v" WEB_HOST_SSH="   "; fi
  if [ "$RC" = 3 ] && has_access web web_host_ssh_unset && [ "$(tl_ssh)" = 0 ]; then
    pass "S8 ($v): WEB_HOST_SSH $v -> web_host_ssh_unset, exit 3"
  else fail "S8 ($v): WEB_HOST_SSH $v did not produce web_host_ssh_unset + exit 3" "$(ctx)"; fi
done

# S9 — argument hygiene: option-shaped addresses that CONTAIN digits and dots.
run_case s9 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS="-oProxyCommand=/tmp/1.2.sh"
if [ "$RC" = 3 ] && has_access web invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9: an option-shaped roster member is invalid_host and never reaches ssh argv"
else fail "S9: an option-shaped roster member was not refused" "$(ctx)"; fi
run_case s9b WEB_HOST_SSH="$WEB_INV" GIT_DATA_HOST="-oProxyCommand=10.0.0.1"
if [ "$RC" = 3 ] && has_access git-data-jump invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9b: an option-shaped GIT_DATA_HOST is invalid_host before any probe"
else fail "S9b: an option-shaped GIT_DATA_HOST was not refused" "$(ctx)"; fi

# X4 — a multi-line roster is refused as one input, never split two different ways.
run_case x4 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=$'10.0.1.10\n10.0.1.11'
if [ "$RC" = 3 ] && has_access web invalid_multiline_input && [ "$(tl_ssh)" = 0 ]; then
  pass "X4: a multi-line WEB_HOSTS is invalid_multiline_input, nothing dialed"
else fail "X4: a multi-line WEB_HOSTS was not refused" "$(ctx)"; fi

# S10 — key set, web fails: neither jump nor auth is dialed.
run_case s10 "${KEYED[@]}" SHIM_WEB_REFUSE=10.0.1.10
if [ "$RC" = 3 ] && has_access web failed && ! grep -qE ' -W |gd-ssh-config' "$TLF"; then
  pass "S10: a failed web probe stops before the jump and the auth probe"
else fail "S10: probes continued after a failed web probe" "$(ctx)"; fi

# S3 / row 6 — key set, jump returns no banner: jump failed, no auth probe.
FIX_R2_STDERR='channel 0: open failed: administratively prohibited: open failed'
run_case s3 "${KEYED[@]}" SHIM_JUMP=none SHIM_JUMP_STDERR="$FIX_R2_STDERR"$'\n'
if [ "$RC" = 3 ] && grep -qxF '[git-data-cutover] ACCESS role=git-data-jump host=10.0.1.20 verdict=failed rc=255 reason=forward_refused' "$OUT" \
   && ! grep -q 'gd-ssh-config' "$TLF" && ! has_access git-data-auth '[a-z_]+'; then
  pass "S3/row6: no banner -> git-data-jump failed reason=forward_refused; the auth probe never ran"
else fail "S3/row6: a failed jump did not stop before the auth probe" "$(ctx)"; fi
if grep -qxF "[git-data-cutover] probe-stderr: ${FIX_R2_STDERR}" "$OUT"; then
  pass "S3: the failed probe's stderr is logged behind the fixed probe-stderr prefix"
else fail "S3: the failed probe's stderr was not logged" "$(ctx)"; fi

# X5 — a final stderr line without a trailing newline is still printed.
run_case x5 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="line-one"$'\n'"last-no-newline"
if grep -qxF '[git-data-cutover] probe-stderr: last-no-newline' "$OUT"; then
  pass "X5: a final stderr line without a newline is not dropped"
else fail "X5: the final stderr line was dropped" "$(ctx)"; fi

# S4 / row 7 — banner then more output with a non-zero rc -> ok.
run_case s4 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=banner_extra
if [ "$RC" = 3 ] && has_access git-data-jump ok && has_access git-data-auth git_data_root_key_absent; then
  pass "S4/row7: banner + more output (ssh rc 255) is jump ok — the verdict keys on the banner, not the rc"
else fail "S4/row7: a banner followed by more output was not read as ok" "$(ctx)"; fi

# S5 / X6 — banner on line 2, and a non-SSH first line -> failed.
for mode in line2 http; do
  run_case "s5$mode" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP="$mode"
  if [ "$RC" = 3 ] && has_access git-data-jump failed; then
    pass "S5 ($mode): a first line that is not an SSH-2.0- banner is jump failed"
  else fail "S5 ($mode): a non-banner first line was accepted" "$(ctx)"; fi
done

# S14 / row 9 — forged workflow commands in probe stderr (both parsers, indented, CR/LF) never
# escape one random-token span, and the token differs per run.
FORGED=$'::error title=git-data-cutover access::role=git-data-jump verdict=ok\r\n  ::add-mask::y\n##[add-mask]x\n##[error]forged\r\n::stop-commands::guess\n'
_toks=()
for k in 1 2; do
  run_case "s14r$k" WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FORGED"
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

# X10 — xtrace refusal: the script refuses to run under -x before doing anything.
TLF="$T/x10.tl"; OUT="$T/x10.out"; : > "$TLF"
env -i PATH="$BIN:/usr/bin:/bin" HOME="$T" TMPDIR="$T" TL="$TLF" WEB_HOST_SSH="$WEB_INV" bash -x "$SCRIPT" > "$OUT" 2>&1
RC=$?
if [ "$RC" = 78 ] && [ ! -s "$TLF" ]; then pass "X10: under bash -x the script exits 78 before any ssh or doppler call"
else fail "X10: the xtrace refusal did not fire first" "$(ctx)"; fi

# AC5 — no `${X_SSH:-ssh}`-style fallback in any form (comment-stripped code).
_code="$(sed -E 's/^[[:space:]]*#.*$//' "$SCRIPT")"
if ! grep -qE '_SSH:?[-=]ssh\}' <<< "$_code"; then
  pass "AC5: no \${*_SSH:-ssh} / :=ssh / -ssh / =ssh fallback in git-data-cutover.sh"
else fail "AC5: an ssh fallback expansion survives" "$(grep -nE '_SSH:?[-=]ssh\}' <<< "$_code")"; fi

# X11 — the script's GIT_DATA_HOST default is the Terraform-owned private address.
_tf_ip="$(sed -nE 's/^[[:space:]]*git_data_private_ip[[:space:]]*=[[:space:]]*"([0-9.]+)".*$/\1/p' "$DIR/git-data.tf" | head -1)"
_sh_ip="$(sed -nE 's/^GIT_DATA_HOST="\$\{GIT_DATA_HOST:-([0-9.]+)\}".*$/\1/p' "$SCRIPT" | head -1)"
if [ -n "$_tf_ip" ] && [ "$_tf_ip" = "$_sh_ip" ]; then pass "X11: GIT_DATA_HOST default ($_sh_ip) equals git-data.tf local.git_data_private_ip"
else fail "X11: GIT_DATA_HOST default '$_sh_ip' != git-data.tf '$_tf_ip'"; fi

# ── AC2 — the canonical read-only proof and its exact remote timeline ─────────────────
cat > "$T/ac2.expected" <<'EXP'
ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20 10.0.1.10 true
ssh -i FIXTURE_WEB_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root -o BatchMode=yes -o ConnectTimeout=20 -W 10.0.1.20:22 10.0.1.10
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 true
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 findmnt -no SOURCE /mnt/git-data
ssh -F /fixture/gd-ssh-config -o BatchMode=yes -o ConnectTimeout=20 10.0.1.20 d=/mnt/git-data/repositories; if [ -d "$d" ]; then n=$(find -H "$d" -mindepth 1 -maxdepth 1 -name '*.git' -printf .) || exit 4; echo "${#n}"; elif [ -e "$d" ]; then exit 3; else echo 0; fi
EXP
run_case ac2 "${KEYED[@]}" GITHUB_STEP_SUMMARY="$T/ac2.summary"
if [ "$RC" = 0 ] && has_store store-mounted ok && has_store store-not-cut-over ok && has_store store-empty ok \
   && grep -qxF '::notice title=git-data-cutover store::verdict=clear' "$OUT"; then
  pass "AC2: key present, plaintext device source, empty store -> exit 0 with all three store probes ok"
else fail "AC2: the canonical read-only proof did not exit 0 clear" "$(ctx)"; fi
if diff <(grep -E '^(ssh|doppler) ' "$TLF") "$T/ac2.expected" > "$T/ac2.diff" 2>&1; then
  pass "AC2: diff of the recorded remote timeline against the expected file is empty (web, jump, auth, findmnt, count — nothing else)"
else fail "AC2: the remote timeline differs from the expected file" "$(tr '\n' '|' < "$T/ac2.diff" | cut -c1-500)"; fi
if [ "$(grep '^timeout ' "$TLF" | paste -sd' ' -)" = "timeout 30 timeout 25 timeout 30 timeout 30 timeout 30" ] \
   && [ "$(grep -c '^ssh-stdin /dev/null$' "$TLF")" = 5 ] && [ "$(grep -c '^ssh-stdin ' "$TLF")" = 5 ]; then
  pass "AC2/G5: every remote call is bounded (30/25/30/30/30) with stdin /dev/null"
else fail "AC2/G5: a remote call lost its bound or its /dev/null stdin" "$(tr '\n' '|' < "$TLF" | cut -c1-500)"; fi
if [ "$(grep -E '^::' "$OUT")" = "::notice title=git-data-cutover access::role=web verdict=ok
::notice title=git-data-cutover access::role=git-data-jump verdict=ok
::notice title=git-data-cutover access::role=git-data-auth verdict=ok
::notice title=git-data-cutover store::probe=store-mounted verdict=ok
::notice title=git-data-cutover store::probe=store-not-cut-over verdict=ok
::notice title=git-data-cutover store::probe=store-empty verdict=ok
::notice title=git-data-cutover store::verdict=clear" ] && ! grep -q '/dev/sdb' "$OUT"; then
  pass "AC2: exactly seven ::notice annotations of fixed words; the captured device name is never printed"
else fail "AC2: annotation set differs, or the captured value was printed" "$(grep -E '^::|/dev/sdb' "$OUT" | tr '\n' '|' | sed 's/::/: :/g')"; fi

# ── GUARD 2 — store probes fail closed ────────────────────────────────────────────────
# Each case is a function so a mutant can re-run exactly the case its matrix row names.
case_unmounted_empty() { # findmnt rc 0 with an empty source
  run_case g2empty "${KEYED[@]}" SHIM_FINDMNT=empty
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=96' "$OUT" && no_count_probe
}
case_mapper() {
  run_case g2mapper "${KEYED[@]}" SHIM_FINDMNT=mapper
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-not-cut-over verdict=already_cut_over' "$OUT" && no_count_probe \
    && grep -qxF '::error title=git-data-cutover store::probe=store-not-cut-over verdict=already_cut_over' "$OUT"
}
case_probe_error() {
  run_case g2err "${KEYED[@]}" SHIM_COUNT=err
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=4' "$OUT" \
    && grep -qxF '[git-data-cutover] probe-stderr: find: cannot open directory: Permission denied' "$OUT"
}
# The mutating-verb census over every non-comment line (whole-line and ` # ` trailing comments
# stripped). At least 50 lines must be scanned.
case_verb_census() { # <script>
  local code n hits
  code="$(sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]+# .*$//' "$1" | grep -vE '^[[:space:]]*$')"
  n="$(printf '%s\n' "$code" | wc -l)"
  hits="$(printf '%s\n' "$code" | grep -nE '(^|[^A-Za-z0-9_-])(rsync|cryptsetup|mount|umount|mkfs(\.[a-z0-9]+)?|touch|systemctl|doppler|web_ssh)([^A-Za-z0-9_-]|$)|(^|[^A-Za-z0-9_-])rm[[:space:]]+-[A-Za-z]*(rf|fr)|soleur-(web|drain)|(bulk|delta)_rsync|repoint_luks_[a-z_]+|canary_luks_[a-z_]+|old_volume_[a-z_]+|prepare_luks_[a-z_]+|verify_set_identity|(acquire|release)_freeze|flip_flag_and_reload' || true)"
  CENSUS_DETAIL="scanned=$n hits=[$(printf '%s' "$hits" | tr '\n' '|' | cut -c1-300)]"
  [ "$n" -ge 50 ] && [ -z "$hits" ]
}

if case_unmounted_empty; then pass "S4b/G2: findmnt exits 0 with an EMPTY source -> old_store_unmounted rc=96, exit 5, count never dialed"
else fail "S4b/G2: an empty findmnt source was accepted" "$(ctx)"; fi
run_case g2rc1 "${KEYED[@]}" SHIM_FINDMNT=rc1
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=1' "$OUT" && no_count_probe; then
  pass "S4/G2: findmnt non-zero -> old_store_unmounted rc=1, exit 5"
else fail "S4/G2: a failing findmnt was not refused" "$(ctx)"; fi
run_case g2tmpfs "${KEYED[@]}" SHIM_FINDMNT=tmpfs
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=96' "$OUT" && no_count_probe; then
  pass "S4c/G2: a non-device source (tmpfs) is old_store_unmounted rc=96"
else fail "S4c/G2: a non-device source was accepted" "$(ctx)"; fi
if case_mapper; then pass "S5/G2: findmnt names the LUKS mapper -> already_cut_over, exit 5, count never dialed"
else fail "S5/G2: a mapper-backed store was not refused" "$(ctx)"; fi
run_case g2one "${KEYED[@]}" SHIM_COUNT=one
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=store_not_empty' "$OUT"; then
  pass "S6/G2: a count of 1 -> store_not_empty, exit 5"
else fail "S6/G2: a non-empty store was not refused" "$(ctx)"; fi
if case_probe_error; then pass "G2: a failing count probe -> probe_failed rc=4, its stderr printed behind the fixed prefix"
else fail "G2: a failing count probe was not probe_failed" "$(ctx)"; fi
run_case g2nl "${KEYED[@]}" SHIM_COUNT=zero2nl
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=96' "$OUT"; then
  pass "G5: only ONE trailing newline is stripped — \"0\\n\\n\" is probe_failed rc=96"
else fail "G5: a count with two trailing newlines was accepted" "$(ctx)"; fi
run_case g2noeol "${KEYED[@]}" SHIM_FINDMNT=noeol
if [ "$RC" = 0 ] && has_store store-mounted ok; then pass "H2: a source with no trailing newline is accepted (the count row covers one trailing newline)"
else fail "H2: a source without a trailing newline was refused" "$(ctx)"; fi

# The count command EXECUTED against a synthesized store (SHIM_COUNT=exec runs the remote bytes
# locally), so the missing / not-a-directory / symlink semantics are the command's own.
_store() { # <name> — a fresh fixture store root under $T
  assert_fixture_dir "$T/store-$1"
  rm -rf "$T/store-$1"; mkdir -p "$T/store-$1" || { printf 'FAIL SETUP: mkdir store\n' >&2; exit 1; }
  printf '%s' "$T/store-$1"
}
# `_store`'s own guard runs inside `$( )`, where `exit` kills only the subshell and the caller
# binds "" — so each binding is re-guarded HERE, in the shell that performs the writes.
_sr="$(_store missing)"; assert_fixture_dir "$_sr"
run_case g2missing "${KEYED[@]}" SHIM_COUNT=exec OLD_ROOT="$_sr"
if [ "$RC" = 0 ] && has_store store-empty ok; then pass "S7/H2: a mounted root with NO repositories dir counts 0 -> exit 0"
else fail "S7/H2: a missing repositories dir was not counted as 0" "$(ctx)"; fi
_sr="$(_store other)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories/notes" && : > "$_sr/repositories/x.gitx" && : > "$_sr/repositories/README"
run_case g2other "${KEYED[@]}" SHIM_COUNT=exec OLD_ROOT="$_sr"
if [ "$RC" = 0 ] && has_store store-empty ok; then pass "S7b: entries that are not *.git do not count -> exit 0"
else fail "S7b: non-repository entries were counted" "$(ctx)"; fi
_sr="$(_store realrepo)"; assert_fixture_dir "$_sr"; mkdir -p "$_sr/repositories/ws-1.git"
run_case g2realrepo "${KEYED[@]}" SHIM_COUNT=exec OLD_ROOT="$_sr"
if [ "$RC" = 5 ] && has_store store-empty store_not_empty; then pass "S6b: one real *.git entry under the store -> store_not_empty"
else fail "S6b: a real repository entry was not counted" "$(ctx)"; fi
_sr="$(_store symlink)"; assert_fixture_dir "$_sr"; mkdir -p "$T/store-symlink-target/ws-2.git" && ln -s "$T/store-symlink-target" "$_sr/repositories"
run_case g2symlink "${KEYED[@]}" SHIM_COUNT=exec OLD_ROOT="$_sr"
if [ "$RC" = 5 ] && has_store store-empty store_not_empty; then pass "S7c: a symlinked repositories dir is followed (find -H) -> store_not_empty"
else fail "S7c: a symlinked repositories dir hid a repository" "$(ctx)"; fi
_sr="$(_store notdir)"; assert_fixture_dir "$_sr"; : > "$_sr/repositories"
run_case g2notdir "${KEYED[@]}" SHIM_COUNT=exec OLD_ROOT="$_sr"
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-empty verdict=probe_failed rc=3' "$OUT"; then
  pass "S7d: a repositories path that is not a directory -> probe_failed rc=3"
else fail "S7d: a non-directory repositories path was not a probe error" "$(ctx)"; fi

if case_verb_census "$SCRIPT"; then pass "G2 census: no rsync/cryptsetup/mount/umount/mkfs/touch/rm -rf/systemctl/doppler/web_ssh or deleted cutover function in the script ($CENSUS_DETAIL)"
else fail "G2 census: a mutating verb or deleted function survives" "$CENSUS_DETAIL"; fi

# G2/G7 order: main() calls, as plain statements, each exactly once and in this order.
case_main_order() { # <script>
  local main calls
  main="$(awk '/^main\(\) \{/{m=1; next} m && /^\}/{exit} m' "$1" | sed -E 's/^[[:space:]]*#.*$//' | grep -vE '^[[:space:]]*$')"
  calls="$(printf '%s\n' "$main" | grep -oE '^[[:space:]]*(refuse_real_modes|resolve_roster|access_gate|refuse_if_unmounted|refuse_if_cut_over|refuse_if_store_not_empty)[[:space:]]*$' | tr -d ' ' | paste -sd, -)"
  ORDER_DETAIL="$calls"
  [ "$calls" = "refuse_real_modes,resolve_roster,access_gate,refuse_if_unmounted,refuse_if_cut_over,refuse_if_store_not_empty" ] \
    && [ "$(grep -cE '(\$\(|`|\||&&)[^#]*(access_gate|refuse_if_|refuse_real_modes)|(access_gate|refuse_if_[a-z_]+|refuse_real_modes)[[:space:]]*(\|\||&&|\|)' "$1" || true)" = 0 ]
}
if case_main_order "$SCRIPT"; then pass "H5: main() runs refuse_real_modes, resolve_roster, access_gate, then the three probes in order, each once, never wrapped"
else fail "H5: main() order/shape is wrong" "calls=[$ORDER_DETAIL]"; fi

# Doppler is never called by any case above (the shim logs every call).
if ! grep -lq '^doppler ' "$T"/*.tl 2>/dev/null; then pass "D-3: no case invoked doppler — the script reads no secret store"
else fail "D-3: the script called doppler" "$(grep -l '^doppler ' "$T"/*.tl | head -3 | tr '\n' ' ')"; fi

# ── GUARD 5 — captured values ─────────────────────────────────────────────────────────
case_line2() { # injected second line: refused AND the canary never printed
  run_case g5line2 "${KEYED[@]}" SHIM_FINDMNT=line2
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=96' "$OUT" \
    && ! grep -q 'CANARY-SECOND-LINE' "$OUT" && no_count_probe
}
case_hang() {
  CASE_TIMEOUT=15 run_case g5hang "${KEYED[@]}" SHIM_FINDMNT=hang SHIM_TIMEOUT_S=2
  [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=124' "$OUT"
}
case_capture_census() { # <script>
  local code outside calls
  code="$(sed -E 's/^[[:space:]]*#.*$//' "$1")"
  # Lines outside access_gate/gd_capture/resolve_roster that expand an ssh invocation.
  outside="$(printf '%s\n' "$code" | awk '
    /^(access_gate|gd_capture|resolve_roster)\(\) \{/ {skip=1; next}
    skip && /^\}/ {skip=0; next}
    !skip' | grep -nE '"\$\{(inv|gdinv)\[@\]\}"|\$\{?GIT_DATA_SSH|\$\{?WEB_HOST_SSH' || true)"
  calls="$(printf '%s\n' "$code" | grep -cE '^[[:space:]]+gd_capture ' || true)"
  CAPTURE_DETAIL="calls=$calls outside=[$(printf '%s' "$outside" | tr '\n' '|' | cut -c1-300)]"
  [ -z "$outside" ] && [ "$calls" -ge 1 ] && [ "$calls" = 2 ]
}
if case_line2; then pass "S8a/G5: a findmnt answer with an injected second line is refused (rc=96) and neither line is printed"
else fail "S8a/G5: a multi-line captured value was accepted or printed" "$(ctx)"; fi
if case_hang; then pass "S8b/G5: a hung host is cut by gd_capture's timeout -> old_store_unmounted rc=124, exit 5"
else fail "S8b/G5: a hung host was not bounded" "$(ctx)"; fi
run_case g5big "${KEYED[@]}" SHIM_FINDMNT=big
if [ "$RC" = 5 ] && grep -qxF '[git-data-cutover] STORE probe=store-mounted verdict=old_store_unmounted rc=96' "$OUT" && ! grep -q 'aaaaaaaaaa' "$OUT"; then
  pass "G5: a 5005-byte answer that would match once truncated is refused (cap 4096), never printed"
else fail "G5: an oversized answer was truncated into an accepted value, or printed" "$(ctx)"; fi
if case_capture_census "$SCRIPT"; then pass "G5 census: exactly two gd_capture call sites; no ssh invocation is expanded outside access_gate/gd_capture ($CAPTURE_DETAIL)"
else fail "G5 census: a raw capture or a stray invocation exists" "$CAPTURE_DETAIL"; fi

# ── GUARD 7 — real modes are refused before any remote call ───────────────────────────
case_refuse() { # <label> <VAR=value>
  run_case "g7$1" "${KEYED[@]}" "$2"
  [ "$RC" = 5 ] && [ ! -s "$TLF" ] \
    && grep -qE '^\[git-data-cutover\] REFUSE verdict=real_cutover_unreconciled vars=' "$OUT" \
    && [ "$(grep -E '^::' "$OUT")" = "::error title=git-data-cutover::verdict=real_cutover_unreconciled" ] \
    && grep -q '#8211' "$OUT"
}
for kv in DRY_RUN=0 ROLLBACK=1 CONFIRM_WIPE=1 DRY_RUN=true; do
  _lbl="$(printf '%s' "$kv" | tr '=A-Z' '-a-z')"
  if case_refuse "$_lbl" "$kv"; then pass "S9/G7 ($kv): exit 5 real_cutover_unreconciled naming #8211, and the timeline is EMPTY"
  else fail "S9/G7 ($kv): a real mode was not refused before any remote call" "$(ctx)"; fi
done
run_case g7empty "${KEYED[@]}" DRY_RUN= ROLLBACK= CONFIRM_WIPE=
if [ "$RC" = 0 ] && ! grep -q 'REFUSE' "$OUT"; then pass "G7 harness: empty DRY_RUN/ROLLBACK/CONFIRM_WIPE take the defaults and reach the proof"
else fail "G7 harness: empty values were refused" "$(ctx)"; fi
if [ "$(grep -c 'DRY_RUN\|ROLLBACK\|CONFIRM_WIPE' "$T/g7dry_run-0.out")" -ge 1 ] && ! grep -qE 'vars=.*(=|[0-9])' "$T/g7dry_run-0.out"; then
  pass "G7: the refusal names the variable, never its value"
else fail "G7: the refusal printed a value or no variable" "$(tr '\n' '|' < "$T/g7dry_run-0.out")"; fi

# ── BRIDGE — the "Decode CI SSH private key" export set ───────────────────────────────
python3 - "$ACTION" "$T/decode.sh" <<'PY' > "$T/g2.count"
import sys, yaml
act = yaml.safe_load(open(sys.argv[1]))
bodies = [s["run"] for s in (act.get("runs") or {}).get("steps") or []
          if str(s.get("name", "")).startswith("Decode CI SSH private key") and s.get("run")]
if len(bodies) == 1: open(sys.argv[2], "w").write(bodies[0])
print(len(bodies))
PY
if [ "$(cat "$T/g2.count")" != 1 ]; then
  fail "BR: extracted $(cat "$T/g2.count") 'Decode CI SSH private key' run bodies, expected exactly 1" "never a pass on zero"
else
  pass "BR: extracted exactly one 'Decode CI SSH private key' run body"
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
      pass "BR (server-ip $variant): server-ip branch exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH}"
    else fail "BR (server-ip $variant): export set is [$_got] (rc=$G2_RC), expected CI_SSH_KEYFILE,WEB_HOST_SSH" "$(tail -3 "$T/g2-$variant/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
    if [ -n "$_kf" ] && [ "$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")" = "$_want_inv" ] && cmp -s "$_kf" "$T/g2-$variant/k"; then
      pass "BR (server-ip $variant): WEB_HOST_SSH is byte-equal to the historical invocation and the keyfile holds the key"
    else fail "BR (server-ip $variant): WEB_HOST_SSH value or keyfile content changed" "got=[$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")] want=[$_want_inv]"; fi
  done
  _g2_run tf "" "$T/g2-tf"
  _got="$(_names "$G2_ENV")"
  if [ "$G2_RC" = 0 ] && [ "$_got" = "TF_VAR_ci_ssh_private_key" ]; then
    pass "BR: terraform branch exports exactly {TF_VAR_ci_ssh_private_key} (heredoc form parsed)"
  else fail "BR: terraform branch export set is [$_got] (rc=$G2_RC), expected TF_VAR_ci_ssh_private_key" "$(tail -3 "$T/g2-tf/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
fi

# ── WORKFLOW — git-data-cutover.yml (D-6 / AC9 / G6 / G7) ──────────────────────────────
cat > "$T/wf.py" <<'PY'
import sys, yaml, json, re
wf_path, iv_path, apply_path, steps_dir = sys.argv[1:5]
wf_text = open(wf_path).read()
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
try:
    wf = yaml.safe_load(wf_text) or {}
except Exception as e:
    print("FAIL\tWF0: workflow parses as YAML\t%s" % str(e)[:200]); sys.exit()
check("WF0: workflow parses as YAML", isinstance(wf, dict))
iv = yaml.safe_load(open(iv_path)); ap = yaml.safe_load(open(apply_path))
on = wf.get(True) or wf.get("on") or {}
check("WF-on: the only trigger is workflow_dispatch (on: read through the True-key lookup)", isinstance(on, dict) and list(on.keys()) == ["workflow_dispatch"], on if not isinstance(on, dict) else list(on.keys()))
inputs = ((on.get("workflow_dispatch") or {}).get("inputs") or {}) if isinstance(on, dict) else {}
check("G7/AC9: workflow_dispatch inputs are exactly {confirm}", sorted(inputs.keys()) == ["confirm"], sorted(inputs.keys()))
check("WF-perm: permissions are exactly {contents: read}", wf.get("permissions") == {"contents": "read"}, wf.get("permissions"))
env = wf.get("env") or {}
check("WF1: workflow env WEB_HOST_PRIVATE_IP is 10.0.1.10", env.get("WEB_HOST_PRIVATE_IP") == "10.0.1.10", env.get("WEB_HOST_PRIVATE_IP"))
rep = ((ap.get("jobs") or {}).get("git_data_host_replace") or {}).get("concurrency") or {}
conc = wf.get("concurrency") or {}
check("G6: workflow-level concurrency group equals git_data_host_replace's literal (git-data-state)",
      isinstance(conc, dict) and bool(rep.get("group")) and conc.get("group") == rep.get("group") == "git-data-state", (conc, rep.get("group")))
check("G6: workflow-level cancel-in-progress is False", isinstance(conc, dict) and conc.get("cancel-in-progress") is False, conc)
jobs = wf.get("jobs") or {}
check("WF-jobs: exactly one job, cutover", list(jobs.keys()) == ["cutover"], list(jobs.keys()))
job = jobs.get("cutover") or {}
envname = job.get("environment")
if isinstance(envname, dict): envname = envname.get("name")
check("AC9: job cutover declares environment web-platform-infra-apply", envname == "web-platform-infra-apply", envname)
check("WF-jobconc: the job carries no concurrency of its own (the group is workflow-level)", "concurrency" not in job)
check("WF-jobenv: the job declares no job-level env", "env" not in job)
steps = job.get("steps") or []
def idx(pred):
    return [i for i, s in enumerate(steps) if pred(s)]
BRIDGE = "./.github/actions/cf-tunnel-ssh-bridge"
pos = {
    "confirm": idx(lambda s: s.get("id") == "confirm"),
    "checkout": idx(lambda s: str(s.get("uses", "")).startswith("actions/checkout@")),
    "doppler": idx(lambda s: s.get("id") == "doppler"),
    "flag_precheck": idx(lambda s: s.get("id") == "flag_precheck"),
    "secrets_check": idx(lambda s: s.get("id") == "secrets_check"),
    "bridge": idx(lambda s: s.get("uses") == BRIDGE),
    "key_fetch": idx(lambda s: s.get("id") == "key_fetch"),
    "ssh_config": idx(lambda s: s.get("id") == "ssh_config"),
    "run": idx(lambda s: isinstance(s.get("run"), str) and "git-data-cutover.sh" in s["run"]),
    "teardown": idx(lambda s: s.get("name") == "Tear down cloudflared SSH bridge"),
}
single = all(len(v) == 1 for v in pos.values())
order = ["confirm", "checkout", "doppler", "flag_precheck", "secrets_check", "bridge", "key_fetch", "ssh_config", "run", "teardown"]
check("D-6: each step exists exactly once, in order confirm < checkout < doppler < flag precheck < secrets check < bridge < key fetch < ssh_config < script < teardown",
      single and [pos[k][0] for k in order] == sorted(pos[k][0] for k in order), {k: v for k, v in pos.items()})
def step(k):
    return steps[pos[k][0]] if len(pos[k]) == 1 else {}
b = step("bridge")
check("WF3: bridge passes server-ip from env.WEB_HOST_PRIVATE_IP", (b.get("with") or {}).get("server-ip") == "${{ env.WEB_HOST_PRIVATE_IP }}", (b.get("with") or {}).get("server-ip"))
check("WF4: bridge step carries no if: and no env:", bool(b) and "if" not in b and "env" not in b)
check("WF-bridge-token: bridge doppler-token is secrets.DOPPLER_TOKEN", (b.get("with") or {}).get("doppler-token") == "${{ secrets.DOPPLER_TOKEN }}", (b.get("with") or {}).get("doppler-token"))
fp = step("flag_precheck")
check("AC9: flag precheck binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD} and runs the precheck script, no if:",
      fp.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_PRD }}"} and str(fp.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-flag-precheck.sh" and "if" not in fp,
      (fp.get("env"), fp.get("run")))
sc = step("secrets_check")
check("WF-secrets: secrets check tests presence only ({DOPPLER_TOKEN_PRESENT, GIT_DATA_ROOT_TOKEN_PRESENT} as != '' booleans)",
      sc.get("env") == {"DOPPLER_TOKEN_PRESENT": "${{ secrets.DOPPLER_TOKEN != '' }}", "GIT_DATA_ROOT_TOKEN_PRESENT": "${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT != '' }}"}, sc.get("env"))
kf = step("key_fetch")
check("AC9: key fetch binds exactly {DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_GIT_DATA_ROOT}, no if:",
      kf.get("env") == {"DOPPLER_TOKEN": "${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}"} and "if" not in kf, kf.get("env"))
cf = step("ssh_config")
check("WF-sshcfg: the ssh_config writer has no env: and no if:", bool(cf) and "env" not in cf and "if" not in cf)
r = step("run")
check("WF6: script step env is exactly {WEB_HOSTS: env.WEB_HOST_PRIVATE_IP, GIT_DATA_SSH: ssh -F runner.temp/gd-ssh-config}",
      r.get("env") == {"WEB_HOSTS": "${{ env.WEB_HOST_PRIVATE_IP }}", "GIT_DATA_SSH": "ssh -F ${{ runner.temp }}/gd-ssh-config"}, r.get("env"))
check("WF10: script step runs the script with no if: (only when every earlier step succeeded)",
      str(r.get("run", "")).strip() == "bash apps/web-platform/infra/git-data-cutover.sh" and "if" not in r, (r.get("run"), r.get("if")))
td = step("teardown")
check("WF7: teardown is if: always() and after the script step", td.get("if") == "always()")
body = td.get("run") or ""
code = "\n".join(l for l in body.splitlines() if not l.lstrip().startswith("#"))
check("WF8: teardown deletes the NAT rule, kills cloudflared, shreds the CI keyfile, the root key and the ssh_config, each guarded",
      all(t in code for t in ('[[ -n "${SERVER_IP:-}" ]]', 'iptables -t nat -D OUTPUT', '[[ -n "${CLOUDFLARED_PID:-}" ]]',
                              '[[ -n "${CI_SSH_KEYFILE:-}" && -f "$CI_SSH_KEYFILE" ]]', 'shred -u "$CI_SSH_KEYFILE"',
                              '[[ -f "$RUNNER_TEMP/gd-root-key" ]]', 'shred -u "$RUNNER_TEMP/gd-root-key"',
                              '[[ -f "$RUNNER_TEMP/gd-ssh-config" ]]', 'shred -u "$RUNNER_TEMP/gd-ssh-config"')))
dumped = json.dumps(wf)
secrets = sorted(set(a or b for a, b in re.findall(r"secrets\s*(?:\.\s*([A-Za-z0-9_]+)|\[\s*['\"]([A-Za-z0-9_]+)['\"]\s*\])", dumped)))
check("WF9: the referenced secrets are exactly {DOPPLER_TOKEN, DOPPLER_TOKEN_GIT_DATA_ROOT, DOPPLER_TOKEN_PRD}",
      secrets == ["DOPPLER_TOKEN", "DOPPLER_TOKEN_GIT_DATA_ROOT", "DOPPLER_TOKEN_PRD"], secrets)
check("AC9: DOPPLER_TOKEN_WRITE is not referenced", "DOPPLER_TOKEN_WRITE" not in dumped)
# PRD token census: every place in the parsed workflow that names it (>= 1 step scanned).
prd_sites = [("step", s.get("id") or s.get("name")) for s in steps if "DOPPLER_TOKEN_PRD" in json.dumps(s)]
prd_sites += [("top", k) for k, v in wf.items() if k != "jobs" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
prd_sites += [("job", k) for k, v in job.items() if k != "steps" and "DOPPLER_TOKEN_PRD" in json.dumps(v, default=str)]
check("AC9: DOPPLER_TOKEN_PRD is named only by the flag precheck step (%d steps scanned)" % len(steps),
      len(steps) >= 1 and prd_sites == [("step", "flag_precheck")], prd_sites)
real_modes = re.findall(r"\b(DRY_RUN|ROLLBACK|CONFIRM_WIPE|dry_run|confirm_wipe|rollback)\b", dumped)
check("G7: no DRY_RUN/ROLLBACK/CONFIRM_WIPE (or their inputs) anywhere in the workflow", not real_modes, sorted(set(real_modes)))
refs = sorted(set(re.findall(r"inputs\.([A-Za-z0-9_]+)", dumped)))
check("WF-inputs-refs: only inputs.confirm is referenced", refs == ["confirm"], refs)
# Pins on the RAW text (the `# v` comment is not in the parse).
uses = [l.strip() for l in wf_text.splitlines() if re.match(r"^\s*(-\s+)?uses:\s", l)]
remote = [u for u in uses if not re.search(r"uses:\s+\./", u)]
local = [re.sub(r"^(-\s+)?uses:\s+", "", u) for u in uses if re.search(r"uses:\s+\./", u)]
check("AC9 pins: every remote uses: is @<40 hex> # v… (%d remote), and the only local action is the bridge" % len(remote),
      len(remote) >= 2 and all(re.search(r"uses:\s+[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+@[0-9a-f]{40} # v", u) for u in remote) and local == [BRIDGE],
      (remote, local))
# Step bodies for the executed rows.
for k in ("key_fetch", "ssh_config", "secrets_check"):
    s = step(k)
    if isinstance(s.get("run"), str):
        open("%s/%s.sh" % (steps_dir, k), "w").write(s["run"])
ivsteps = [s for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
mine = [s for s in ivsteps if isinstance(s.get("run"), str) and s["run"].strip() == "bash apps/web-platform/infra/git-data-cutover-access.test.sh"]
check("AC10: infra-validation.yml runs this suite in exactly one step with no if:/continue-on-error",
      len(mine) == 1 and "if" not in mine[0] and not mine[0].get("continue-on-error"), len(mine))
print("\n".join(out))
PY
# wf_row <tsv> <name-prefix> — 0 when the named row is ok.
# wf_row <tsv> <name-prefix> — 1 only when the named row is PRESENT and not ok. An ABSENT row (the
# YAML leg crashed on a mutant) returns 0, so a mutant can never read as RED for the wrong reason.
# shellcheck disable=SC2317  # invoked indirectly through mutant_red
wf_row() { awk -F'\t' -v p="$2" 'index($2, p) == 1 { found = 1; if ($1 != "ok") bad = 1 } END { exit (found && bad) ? 1 : 0 }' "$1"; }
python3 "$T/wf.py" "$WF" "$IV" "$APPLY_WF" "$T/steps" > "$T/wf.tsv" 2> "$T/wf.err"
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -ge 30 ] || fail "WF: only $_wf_n workflow verdicts were produced (expected 30) — the YAML leg crashed" "$(head -c 300 "$T/wf.err")"

# ── WORKFLOW STEPS, EXECUTED ──────────────────────────────────────────────────────────
# Per-name Doppler shim: answers per project/config/secret AND per flag presence, mirroring the
# measured v3.75.3 semantics (see git-data-flag-precheck.sh). A store is a directory tree
# $DOPPLER_STORE/<project>/<config>/<NAME>.
mkdir -p "$T/kbin" || { printf 'FAIL SETUP: mkdir kbin\n' >&2; exit 1; }
cat > "$T/kbin/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "${DOPPLER_LOG:-/dev/null}"
[ "${1:-}" = secrets ] && [ "${2:-}" = get ] || { echo "doppler-shim: unsupported: $*" >&2; exit 64; }
name="${3:-}"; shift 3
plain=0; noexit=0; proj=""; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --plain) plain=1; shift ;;
    --no-exit-on-missing-secret) noexit=1; shift ;;
    -p|--project) proj="${2:-}"; shift 2 ;;
    -c|--config) cfg="${2:-}"; shift 2 ;;
    *) echo "doppler-shim: unknown argument $1" >&2; exit 64 ;;
  esac
done
[ -n "${DOPPLER_TOKEN:-}" ] || { echo "Doppler Error: you must provide a token" >&2; exit 1; }
[ "${SHIM_DOPPLER_SCOPE_ERROR:-0}" = 1 ] && { echo "Doppler Error: This token does not have access to requested config '$cfg'" >&2; exit 1; }
[ "$plain" = 1 ] || { echo "doppler-shim: --plain required" >&2; exit 64; }
d="$DOPPLER_STORE/$proj/$cfg"
if [ -z "$proj" ] || [ -z "$cfg" ] || [ ! -d "$d" ]; then echo "Doppler Error: Could not find requested config '$cfg'" >&2; exit 1; fi
if [ -f "$d/$name" ]; then cat "$d/$name"; exit 0; fi
if [ "$noexit" = 1 ] && [ "${SHIM_DOPPLER_IGNORE_FLAG:-0}" != 1 ]; then exit 0; fi
echo "Doppler Error: Could not find requested secret: $name" >&2; exit 1
SHIM
chmod +x "$T/kbin/doppler"

# Key fetch.
if [ ! -s "$T/steps/key_fetch.sh" ]; then
  fail "KF: the key fetch step body was not extracted" "never a pass on zero"
else
  ssh-keygen -q -t ed25519 -N '' -C fixture-root -f "$T/fixture-root" || { printf 'FAIL SETUP: ssh-keygen root\n' >&2; exit 1; }
  _kf_run() { # <label> <store-mode: good|garbage|empty|none> [extra env...]
    local label="$1" mode="$2"; shift 2
    local -a KF_FLAGS=(-eo pipefail)
    [ "${KF_XTRACE:-0}" = 1 ] && KF_FLAGS=(-x -eo pipefail)
    KR="$T/kf-$label"
    assert_fixture_dir "$KR"
    rm -rf "$KR"; mkdir -p "$KR/rt" "$KR/store/soleur-git-data-root/prd" || { printf 'FAIL SETUP: mkdir kf\n' >&2; exit 1; }
    case "$mode" in
      good)    printf '%s' "$(cat "$T/fixture-root")" > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      garbage) printf 'NOT-A-KEY-CANARY-91c\nsecond line\n' > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      empty)   : > "$KR/store/soleur-git-data-root/prd/GIT_DATA_ROOT_SSH_PRIVATE_KEY" ;;
      none)    : ;;
    esac
    : > "$KR/github_env"; : > "$KR/doppler.log"
    env -i PATH="$T/kbin:/usr/bin:/bin" HOME="$KR" RUNNER_TEMP="$KR/rt" GITHUB_ENV="$KR/github_env" DOPPLER_STORE="$KR/store" \
      DOPPLER_LOG="$KR/doppler.log" DOPPLER_TOKEN=fixture-root-read "$@" \
      bash --noprofile --norc "${KF_FLAGS[@]}" "$T/steps/key_fetch.sh" > "$KR/stdout" 2>&1
    KF_RC=$?
  }
  _kf_run good good
  _key="$KR/rt/gd-root-key"
  if [ "$KF_RC" = 0 ] && [ -f "$_key" ] && [ "$(stat -c %a "$_key")" = 600 ] && [ -z "$(tail -c 1 "$_key")" ] \
     && ssh-keygen -y -f "$_key" </dev/null >/dev/null 2>&1 && cmp -s "$_key" "$T/fixture-root"; then
    pass "KF1: a good key lands at \$RUNNER_TEMP/gd-root-key, mode 600, with a trailing newline, and derives a public key"
  else fail "KF1: the key fetch did not produce a usable 0600 key file" "rc=$KF_RC $(tail -3 "$KR/stdout" | tr '\n' '|' | sed 's/::/: :/g')"; fi
  _kf_leak="$(python3 - "$KR/stdout" "$T/fixture-root" <<'PY'
import sys
out = open(sys.argv[1]).read().split("\n"); key = [l for l in open(sys.argv[2]).read().split("\n") if l]
masks = [l[len("::add-mask::"):] for l in out if l.startswith("::add-mask::")]
first_other = next((i for i, l in enumerate(out) if l and not l.startswith("::add-mask::")), len(out))
last_mask = max((i for i, l in enumerate(out) if l.startswith("::add-mask::")), default=-1)
problems = []
if sorted(set(masks)) != sorted(set(key)): problems.append("mask set != key lines")
if last_mask > first_other: problems.append("a mask followed other output")
for l in out:
    if l.startswith("::add-mask::"): continue
    if any(k in l for k in key if len(k) > 8): problems.append("key bytes outside a mask line")
print("OK" if not problems else ";".join(problems))
PY
)"
  if [ "$_kf_leak" = OK ]; then pass "KF1: every key line is add-masked before any other output, and no key byte reaches stdout otherwise"
  else fail "KF1: key masking/leak check failed" "$_kf_leak"; fi
  if [ ! -s "$KR/github_env" ] && [ "$(cat "$KR/doppler.log")" = "doppler secrets get GIT_DATA_ROOT_SSH_PRIVATE_KEY --plain -p soleur-git-data-root -c prd" ]; then
    pass "KF1: nothing is written to \$GITHUB_ENV, and doppler is called exactly once with -p soleur-git-data-root -c prd"
  else fail "KF1: GITHUB_ENV written or doppler argv differs" "env=[$(head -c 100 "$KR/github_env")] log=[$(tr '\n' '|' < "$KR/doppler.log")]"; fi
  for spec in "none:rc_nonzero" "empty:empty" "garbage:not_openssh_key"; do
    _m="${spec%%:*}"; _r="${spec##*:}"
    _kf_run "$_m" "$_m"
    if [ "$KF_RC" != 0 ] && grep -qxF "::error title=git-data-cutover key::verdict=git_data_root_key_fetch_failed reason=${_r}" "$KR/stdout" \
       && ! grep -v '^::add-mask::' "$KR/stdout" | grep -q 'NOT-A-KEY-CANARY'; then
      pass "KF ($_m): fails with verdict=git_data_root_key_fetch_failed reason=$_r, printing the reason word only"
    else fail "KF ($_m): expected reason=$_r" "rc=$KF_RC $(tr '\n' '|' < "$KR/stdout" | sed 's/::/: :/g' | cut -c1-300)"; fi
  done
  _kf_run scope good SHIM_DOPPLER_SCOPE_ERROR=1
  if [ "$KF_RC" != 0 ] && grep -qF 'reason=rc_nonzero' "$KR/stdout"; then pass "S10b/KF: a revoked or wrong-scope token is reason=rc_nonzero"
  else fail "S10b/KF: a scope error was not rc_nonzero" "rc=$KF_RC $(tr '\n' '|' < "$KR/stdout" | sed 's/::/: :/g')"; fi
  KF_XTRACE=1 _kf_run xtrace good
  if [ "$KF_RC" = 78 ] && [ ! -s "$KR/doppler.log" ] && [ ! -e "$KR/rt/gd-root-key" ]; then pass "KF: under xtrace the key fetch exits 78 before calling doppler"
  else fail "KF: the key fetch ran under xtrace" "rc=$KF_RC"; fi
fi

# ssh_config writer — its output is resolved by the REAL OpenSSH (`ssh -G`), not grepped alone.
if [ ! -s "$T/steps/ssh_config.sh" ]; then
  fail "SC: the ssh_config step body was not extracted" "never a pass on zero"
else
  _sc_run() { # <label> <ci-keyfile-path-or-empty> [write-root-key=1]
    SR="$T/sc-$1"
    assert_fixture_dir "$SR"
    rm -rf "$SR"; mkdir -p "$SR/rt" || { printf 'FAIL SETUP: mkdir sc\n' >&2; exit 1; }
    [ "${3:-1}" = 1 ] && printf 'fixture-root-key\n' > "$SR/rt/gd-root-key"
    printf 'fixture-ci-key\n' > "$SR/ci-key"
    env -i PATH=/usr/bin:/bin HOME="$SR" RUNNER_TEMP="$SR/rt" ${2:+CI_SSH_KEYFILE="$2"} \
      bash --noprofile --norc -eo pipefail "$T/steps/ssh_config.sh" > "$SR/stdout" 2>&1
    SC_RC=$?; SC_CFG="$SR/rt/gd-ssh-config"
  }
  _sc_run good "$T/sc-good/ci-key"
  if [ "$SC_RC" = 0 ] && [ -f "$SC_CFG" ] && [ "$(stat -c %a "$SC_CFG")" = 600 ]; then pass "SC1: the writer succeeds and the config is mode 600"
  else fail "SC1: the ssh_config writer failed" "rc=$SC_RC $(tr '\n' '|' < "$SR/stdout" | sed 's/::/: :/g')"; fi
  _sc_struct="$(python3 - "$SC_CFG" "$SR/rt/gd-root-key" "$T/sc-good/ci-key" <<'PY'
import sys, re
try: lines = open(sys.argv[1]).read().splitlines()
except Exception as e: print("unreadable"); sys.exit()
cfg, rootkey, cikey = sys.argv[1:4]
blocks = {}; cur = None; problems = []; order = []
for l in lines:
    s = l.strip()
    if not s: continue
    kw = s.split(None, 1)[0].lower()
    if kw in ("host", "match"):
        cur = s; order.append(s); blocks[cur] = []; continue
    if cur is None: problems.append("option outside a block: " + s); continue
    blocks[cur].append(s)
if order != ["Host 10.0.1.10", "Host 10.0.1.20"]: problems.append("host lines %r" % order)
HARD = ["IdentitiesOnly yes", "BatchMode yes", "LogLevel ERROR", "ForwardAgent no", "ClearAllForwardings yes",
        "PermitLocalCommand no", "ControlPath none", "UpdateHostKeys no", "StrictHostKeyChecking accept-new",
        "UserKnownHostsFile /dev/null", "User root"]
want_id = {"Host 10.0.1.10": cikey, "Host 10.0.1.20": rootkey}
for h, opts in blocks.items():
    for o in HARD:
        if o not in opts: problems.append("%s lacks %s" % (h, o))
    ids = [o for o in opts if o.lower().startswith("identityfile ")]
    if ids != ["IdentityFile " + want_id.get(h, "?")]: problems.append("%s identityfiles %r" % (h, ids))
    if any("%" in o for o in opts): problems.append("%s carries a %% token" % h)
pc20 = [o for o in blocks.get("Host 10.0.1.20", []) if o.lower().startswith("proxycommand ")]
if pc20 != ["ProxyCommand ssh -F %s -W 10.0.1.20:22 10.0.1.10" % cfg]: problems.append("proxycommand %r" % pc20)
if any(o.lower().startswith("proxy") for o in blocks.get("Host 10.0.1.10", [])): problems.append("web block has a proxy")
print("OK" if not problems else "; ".join(problems))
PY
)"
  if [ "$_sc_struct" = OK ]; then pass "SC2: exactly Host 10.0.1.10 then Host 10.0.1.20 (no Host */Match), one IdentityFile each, literal ProxyCommand, every hardening option in both"
  else fail "SC2: ssh_config structure differs" "$_sc_struct"; fi
  _g20="$(ssh -G -F "$SC_CFG" 10.0.1.20 2>/dev/null)"; _g10="$(ssh -G -F "$SC_CFG" 10.0.1.10 2>/dev/null)"
  if grep -qxF "proxycommand ssh -F $SC_CFG -W 10.0.1.20:22 10.0.1.10" <<< "$_g20" \
     && [ "$(grep '^identityfile ' <<< "$_g20")" = "identityfile $SR/rt/gd-root-key" ] && grep -qx 'user root' <<< "$_g20" \
     && [ "$(grep '^identityfile ' <<< "$_g10")" = "identityfile $T/sc-good/ci-key" ] && ! grep -q '^proxycommand ' <<< "$_g10" \
     && grep -qx 'identitiesonly yes' <<< "$_g20" && grep -qx 'forwardagent no' <<< "$_g10"; then
    pass "SC3: real OpenSSH (ssh -G) resolves git-data to the root key via the web-1 ProxyCommand, and web-1 to the CI key with no proxy"
  else fail "SC3: ssh -G resolution differs" "$(printf '%s' "$_g20" | grep -E '^(proxycommand|identityfile|user) ' | tr '\n' '|')"; fi
  _sc_run nokey ""
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && grep -qF 'verdict=ssh_config_key_absent' "$SR/stdout"; then pass "SC4: CI_SSH_KEYFILE unset -> ssh_config_key_absent, nothing written"
  else fail "SC4: the writer ran without the CI keyfile" "rc=$SC_RC"; fi
  _sc_run noroot "$T/sc-noroot/ci-key" 0
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ]; then pass "SC5: no root key file -> refused, nothing written"
  else fail "SC5: the writer ran without the root key" "rc=$SC_RC"; fi
  mkdir -p "$T/sc bad" && printf 'k\n' > "$T/sc bad/ci-key"
  _sc_run unsafe "$T/sc bad/ci-key"
  if [ "$SC_RC" != 0 ] && [ ! -e "$SC_CFG" ] && grep -qF 'verdict=ssh_config_path_unsafe' "$SR/stdout"; then pass "SC6: a keyfile path with a space -> ssh_config_path_unsafe, nothing written"
  else fail "SC6: an unsafe path reached the config" "rc=$SC_RC"; fi
fi

# Secrets check — the root token's absence is its own verdict.
if [ ! -s "$T/steps/secrets_check.sh" ]; then
  fail "SEC: the secrets check step body was not extracted" "never a pass on zero"
else
  _sec() { env -i PATH=/usr/bin:/bin "$@" bash --noprofile --norc -eo pipefail "$T/steps/secrets_check.sh" > "$T/sec.out" 2>&1; SEC_RC=$?; }
  _sec DOPPLER_TOKEN_PRESENT=true GIT_DATA_ROOT_TOKEN_PRESENT=false
  if [ "$SEC_RC" != 0 ] && grep -qxF '::error title=git-data-cutover secrets::verdict=git_data_root_token_absent' "$T/sec.out"; then
    pass "S10/SEC: an empty DOPPLER_TOKEN_GIT_DATA_ROOT -> verdict=git_data_root_token_absent, step fails (before the bridge)"
  else fail "S10/SEC: an absent root token was not reported" "rc=$SEC_RC $(tr '\n' '|' < "$T/sec.out" | sed 's/::/: :/g')"; fi
  _sec DOPPLER_TOKEN_PRESENT=true GIT_DATA_ROOT_TOKEN_PRESENT=true
  if [ "$SEC_RC" = 0 ] && ! grep -q '::error' "$T/sec.out"; then pass "SEC: both tokens present -> the step passes"
  else fail "SEC: present tokens were refused" "rc=$SEC_RC"; fi
  _sec DOPPLER_TOKEN_PRESENT=false GIT_DATA_ROOT_TOKEN_PRESENT=true
  if [ "$SEC_RC" != 0 ]; then pass "SEC: an absent DOPPLER_TOKEN fails the step"
  else fail "SEC: an absent DOPPLER_TOKEN passed"; fi
fi

# ── GUARD 3 — the root token's reference census ──────────────────────────────────────
cat > "$T/g3.py" <<'PY'
import sys, os, yaml, json, re
gh = sys.argv[1]
NAME = "DOPPLER_TOKEN_GIT_DATA_ROOT"
KNOWN_INHERIT = {("version-bump-and-release.yml", "release"), ("web-platform-release.yml", "release")}
out = []
def check(name, cond, detail=""):
    out.append("%s\t%s\t%s" % ("ok" if cond else "FAIL", name, str(detail)[:240].replace("\t", " ").replace("\n", " ")))
files = []
for sub in ("workflows", "actions"):
    for dp, dn, fn in os.walk(os.path.join(gh, sub)):
        for f in fn: files.append(os.path.join(dp, f))
files.sort()
check("G3a: census scanned >= 1 file under .github/workflows and .github/actions (%d files scanned)" % len(files),
      len(files) >= 1 and any(p.endswith("/workflows/git-data-cutover.yml") for p in files), "%d files scanned" % len(files))
naming, parse_err, inherit, dynamic, reusable_names = [], [], set(), [], False
cut = None
for p in files:
    rel = os.path.relpath(p, gh)
    text = open(p, encoding="utf-8", errors="replace").read()
    if p.endswith((".yml", ".yaml")):
        try: doc = yaml.safe_load(text)
        except Exception as e: parse_err.append(rel); continue
        dumped = json.dumps(doc, default=str)
        if isinstance(doc, dict):
            for j, b in (doc.get("jobs") or {}).items():
                if isinstance(b, dict) and b.get("secrets") == "inherit": inherit.add((os.path.basename(p), j))
        if rel == os.path.join("workflows", "git-data-cutover.yml"): cut = doc
    else:
        dumped = text  # no comment semantics outside YAML: any mention counts
    if NAME in dumped: naming.append(rel)
    if "toJSON(secrets)" in dumped or re.search(r"secrets\s*\[", dumped): dynamic.append(rel)
    if os.path.basename(p) == "reusable-release.yml" and NAME in dumped: reusable_names = True
check("G3b: the token is named (outside comments) only by workflows/git-data-cutover.yml", naming == [os.path.join("workflows", "git-data-cutover.yml")] and not parse_err, (naming, parse_err))
jobs = (cut or {}).get("jobs") or {}
top = [k for k, v in (cut or {}).items() if k != "jobs" and NAME in json.dumps(v, default=str)]
jn = [j for j, b in jobs.items() if NAME in json.dumps(b, default=str)]
check("G3c: within it only job `cutover` names the token, and no workflow-level key does", jn == ["cutover"] and not top, (jn, top))
env = (jobs.get("cutover") or {}).get("environment")
if isinstance(env, dict): env = env.get("name")
check("G3d: job `cutover` declares environment web-platform-infra-apply", env == "web-platform-infra-apply", env)
steps = (jobs.get("cutover") or {}).get("steps") or []
sites = []
for s in steps:
    if NAME not in json.dumps(s, default=str): continue
    e = s.get("env") or {}
    keys = [k for k, v in e.items() if NAME in str(v)]
    rest = {k: v for k, v in s.items() if k != "env"}
    sites.append((s.get("id"), keys, [e[k] for k in keys], NAME in json.dumps(rest, default=str)))
check("G3e: the token's steps are exactly the secrets check (presence boolean) and the key fetch (value bind)",
      sites == [("secrets_check", ["GIT_DATA_ROOT_TOKEN_PRESENT"], ["${{ secrets.%s != '' }}" % NAME], False),
                ("key_fetch", ["DOPPLER_TOKEN"], ["${{ secrets.%s }}" % NAME], False)], sites)
check("G3f: `secrets: inherit` sites are exactly the known release callers", inherit == KNOWN_INHERIT, sorted(inherit))
check("G3g: no toJSON(secrets) / secrets[...] dynamic secret access anywhere", not dynamic, dynamic)
check("G3h: reusable-release.yml never names the token", not reusable_names)
print("\n".join(out))
PY
python3 "$T/g3.py" "$GHDIR" > "$T/g3.tsv" 2> "$T/g3.err"
_g3_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _g3_n=$((_g3_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/g3.tsv"
[ "$_g3_n" -ge 8 ] || fail "G3: only $_g3_n census verdicts were produced (expected 8) — the census crashed" "$(head -c 300 "$T/g3.err")"

# Harness rows: a fixture tree.
_ghcopy() { # <name> — a copy of the census input tree under $T; prints its path
  local d="$T/gh-$1"
  assert_fixture_dir "$d"; assert_fixture_dir "$GHDIR"
  rm -rf "$d"; mkdir -p "$d" && cp -r "$GHDIR/workflows" "$GHDIR/actions" "$d/" || { printf 'FAIL SETUP: gh copy\n' >&2; exit 1; }
  printf '%s' "$d"
}
# Same as `_store` above: `_ghcopy`'s guard exits only its subshell, so re-guard every binding.
_gc="$(_ghcopy comment)"; assert_fixture_dir "$_gc"
printf '# mentions DOPPLER_TOKEN_GIT_DATA_ROOT in a comment only\nname: zz-comment\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo ok\n' > "$_gc/workflows/zz-comment.yml"
python3 "$T/g3.py" "$_gc" > "$T/g3c.tsv" 2>&1
if grep -qP '^ok\tG3b:' "$T/g3c.tsv"; then pass "H3a: a comment-only mention in another workflow does not count"
else fail "H3a: a comment-only mention was counted" "$(grep G3b "$T/g3c.tsv")"; fi
assert_fixture_dir "$T/gh-empty"; mkdir -p "$T/gh-empty/workflows" "$T/gh-empty/actions"
python3 "$T/g3.py" "$T/gh-empty" > "$T/g3e.tsv" 2>&1
if grep -qP '^FAIL\tG3a:' "$T/g3e.tsv" && grep -q '0 files scanned' "$T/g3e.tsv"; then pass "H3b: an empty scan set is a FAILURE reported as '0 files scanned'"
else fail "H3b: an empty scan set passed" "$(head -2 "$T/g3e.tsv")"; fi

# ── MUTANTS ───────────────────────────────────────────────────────────────────────────
echo; echo "--- mutation matrix (each row must turn its named case RED)"
# shellcheck disable=SC2016  # sed programs are data
{
# G2 row 1 — accept an empty findmnt source.
if mutate g2-empty-source "$SCRIPT" 2 "s#gd_capture '\\^/dev/\\[A-Za-z0-9/_.-\\]\\+\\\$'#gd_capture '^(/dev/[A-Za-z0-9/_.-]+)?\$'#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g2-empty-source case_unmounted_empty
fi
# G2 row 2 — delete refuse_if_cut_over from main (keep the other two).
if mutate g2-no-cut-over "$SCRIPT" 1 '/^  refuse_if_cut_over$/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g2-no-cut-over case_mapper
fi
# G2 row 3 — treat a failed count probe as zero.
if mutate g2-failed-count-zero "$SCRIPT" 2 's#^  \[ "\$rc" -eq 0 \] \|\| _store_refuse store-empty probe_failed "\$rc"$#  [ "$rc" -eq 0 ] || GD_CAPTURED=0#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g2-failed-count-zero case_probe_error
fi
# G2 row 4 — reintroduce the bulk rsync function of the deleted body.
if mutate g2-bulk-rsync "$SCRIPT" 1 's#^main\(\) \{$#bulk_rsync() { gd_capture "^$" "rsync -aHAX --delete /mnt/git-data/repositories/ /mnt/git-data-luks/repositories/"; }\n&#'; then
  mutant_red g2-bulk-rsync case_verb_census "$MUTANT"
fi
# G5 row 1 — return the value without the pattern check (both the multi-line and the regex arm).
if mutate g5-no-pattern "$SCRIPT" 4 "s#^    \\*\\\$'\\\\n'\\*\\) return 96 ;;\$#    *NEVER*) return 96 ;;#; s#^  if ! \\[\\[ \"\\\$val\" =~ \\\$pat \\]\\]; then\$#  if false; then#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-no-pattern case_line2
fi
# G5 row 2 — drop the timeout wrapper.
if mutate g5-no-timeout "$SCRIPT" 2 's#^  val="\$\(timeout 30 #  val="$(#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-no-timeout case_hang
fi
# G5 row 3 — echo the captured value in the mismatch branch.
if mutate g5-echo-value "$SCRIPT" 2 "s#^    \\*\\\$'\\\\n'\\*\\) return 96 ;;\$#    *\$'\\\\n'*) printf '%s\\\\n' \"\$val\"; return 96 ;;#"; then
  CASE_SCRIPT="$MUTANT" mutant_red g5-echo-value case_line2
fi
# G5 row 4 — a raw capture of the invocation outside gd_capture.
if mutate g5-raw-capture "$SCRIPT" 1 's#^  \[ -n "\$STORE_SOURCE" \] \|\| _store_refuse store-not-cut-over probe_failed$#  local -a inv; read -ra inv <<< "${GIT_DATA_SSH:-}"; STORE_SOURCE="$("${inv[@]}" "$GIT_DATA_HOST" findmnt -no SOURCE /mnt/git-data)"\n&#'; then
  mutant_red g5-raw-capture case_capture_census "$MUTANT"
fi
# G7 row 1 — re-add a rollback input.
if mutate g7-rollback-input "$WF" 2 's#^        type: string$#&\n      rollback:\n        type: boolean#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-g7.tsv" 2>&1
  mutant_red g7-rollback-input wf_row "$T/mut/wf-g7.tsv" "G7/AC9: workflow_dispatch inputs"
fi
# G7 row 2 — refuse only ROLLBACK/DRY_RUN: drop the CONFIRM_WIPE arm.
if mutate g7-no-wipe-arm "$SCRIPT" 1 '/^  \[ "\$\{CONFIRM_WIPE:-0\}" = 0 \] \|\| bad=/d'; then
  CASE_SCRIPT="$MUTANT" mutant_red g7-no-wipe-arm case_refuse mwipe CONFIRM_WIPE=1
fi
# G7 row 3 — REORDER: the refusal after access_gate.
if mutate g7-reorder "$SCRIPT" 2 '/^  refuse_real_modes$/d; s#^  access_gate$#&\n  refuse_real_modes#'; then
  CASE_SCRIPT="$MUTANT" mutant_red g7-reorder case_refuse mreorder DRY_RUN=0
fi
# G6 row 1 — rename the cutover workflow's group.
if mutate g6-group-rename "$WF" 2 's#^  group: git-data-state$#  group: git-data-cutover#'; then
  python3 "$T/wf.py" "$MUTANT" "$IV" "$APPLY_WF" "$T/mut" > "$T/mut/wf-g6.tsv" 2>&1
  mutant_red g6-group-rename wf_row "$T/mut/wf-g6.tsv" "G6: workflow-level concurrency group"
fi
# G3 row 1 — a second job in git-data-cutover.yml referencing the token.
_gm="$(_ghcopy m-secondjob)"; assert_fixture_dir "$_gm"
if mutate g3-second-job "$_gm/workflows/git-data-cutover.yml" 6 '$a\  second:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}'; then
  cp "$MUTANT" "$_gm/workflows/git-data-cutover.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-1.tsv" 2>&1
  mutant_red g3-second-job wf_row "$T/mut/g3-1.tsv" "G3c:"
fi
# G3 row 4 — remove environment: from cutover.
_gm="$(_ghcopy m-noenv)"; assert_fixture_dir "$_gm"
if mutate g3-no-environment "$_gm/workflows/git-data-cutover.yml" 1 '/^    environment: web-platform-infra-apply$/d'; then
  cp "$MUTANT" "$_gm/workflows/git-data-cutover.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-4.tsv" 2>&1
  mutant_red g3-no-environment wf_row "$T/mut/g3-4.tsv" "G3d:"
fi
# G3 row 2 — a second workflow file referencing the token, sorted after the compliant first.
_gm="$(_ghcopy m-secondwf)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    environment: web-platform-infra-apply\n    steps:\n      - run: echo x\n        env:\n          T: ${{ secrets.DOPPLER_TOKEN_GIT_DATA_ROOT }}\n' > "$_gm/workflows/zz-second.yml"
if [ -s "$_gm/workflows/zz-second.yml" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g3-second-workflow: fixture workflow zz-second.yml written after git-data-cutover.yml"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-2.tsv" 2>&1
  mutant_red g3-second-workflow wf_row "$T/mut/g3-2.tsv" "G3b:"
else fail "M-g3-second-workflow: fixture not written"; fi
# G3 row 3 — `secrets: inherit` on a new caller.
_gm="$(_ghcopy m-inherit)"; assert_fixture_dir "$_gm"
printf 'name: zz\non: workflow_dispatch\njobs:\n  call:\n    uses: ./.github/workflows/reusable-release.yml\n    secrets: inherit\n' > "$_gm/workflows/zz-caller.yml"
if [ -s "$_gm/workflows/zz-caller.yml" ]; then
  MUTANTS_RUN=$((MUTANTS_RUN + 1)); pass "M-g3-inherit: fixture caller zz-caller.yml with secrets: inherit written"
  python3 "$T/g3.py" "$_gm" > "$T/mut/g3-3.tsv" 2>&1
  mutant_red g3-inherit wf_row "$T/mut/g3-3.tsv" "G3f:"
else fail "M-g3-inherit: fixture not written"; fi
}

# ── RUNTIME ARM — real OpenSSH (pinned ubuntu:24.04) ─────────────────────────────────
RUNTIME_ROWS=17
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
  if [ -s "$T/steps/ssh_config.sh" ]; then cp "$T/steps/ssh_config.sh" "$T/rt/sshcfg.sh"; else : > "$T/rt/sshcfg.sh"; fi
  cat > "$T/rt/drive.sh" <<'DRV'
set -u
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq openssh-server openssh-client netcat-openbsd iproute2 >/dev/null 2>&1 || { echo FIXTURE_APT_FAILED; exit 100; }
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
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root WEB_HOSTS=127.0.0.1 GIT_DATA_HOST=127.0.0.2 \
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

# ── The workflow's own ssh_config, end to end: web-1 (10.0.1.10) authorizes ONLY the CI key,
# git-data (10.0.1.20) ONLY the root key, and a root session's PATH (/usr/local/sbin first) finds a
# fixture findmnt/find that record the remote commands. The script itself runs with
# PATH=/usr/sbin:/usr/bin:/bin, so the fixtures are reached only through sshd.
ipok=1
ip addr add 10.0.1.10/32 dev lo >/dev/null 2>&1 || ipok=0
ip addr add 10.0.1.20/32 dev lo >/dev/null 2>&1 || ipok=0
row ip_ok "$ipok"
ssh-keygen -q -t ed25519 -N '' -f /tmp/ci && ssh-keygen -q -t ed25519 -N '' -f /tmp/gdroot
install -m 600 /tmp/ci.pub /etc/ssh/ak-web && install -m 600 /tmp/gdroot.pub /etc/ssh/ak-gd
mkdir -p /fixture /rt && : > /out/remote.log
cat > /usr/local/sbin/findmnt <<'F'
#!/bin/bash
printf 'findmnt %s\n' "$*" >> /out/remote.log
cat /fixture/findmnt.out
exit "$(cat /fixture/findmnt.rc)"
F
cat > /usr/local/sbin/find <<'F'
#!/bin/bash
printf 'find %s\n' "$*" >> /out/remote.log
exec /usr/bin/find "$@"
F
chmod 755 /usr/local/sbin/findmnt /usr/local/sbin/find
W1=$(sshd_on 10.0.1.10 22 -o AuthorizedKeysFile=/etc/ssh/ak-web)
G1=$(sshd_on 10.0.1.20 22 -o AuthorizedKeysFile=/etc/ssh/ak-gd)
sleep 1
install -m 600 /tmp/gdroot /rt/gd-root-key
env -i PATH=/usr/bin:/bin HOME=/root RUNNER_TEMP=/rt CI_SSH_KEYFILE=/tmp/ci bash --noprofile --norc -eo pipefail /work/sshcfg.sh > /out/sshcfg.out 2>&1
row sshcfg_rc "$?"
accepted() { grep -c 'Accepted publickey for root' "/tmp/sshd-$1-22.log" 2>/dev/null || true; }
drive2() { # label
  local wb gb
  wb=$(accepted 10.0.1.10); gb=$(accepted 10.0.1.20)
  : > /out/remote.log
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root WEB_HOSTS=10.0.1.10 \
    WEB_HOST_SSH="ssh -i /tmp/ci -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root" \
    GIT_DATA_SSH="ssh -F /rt/gd-ssh-config" bash /work/git-data-cutover.sh > "/out/$1.out" 2>&1
  row "$1_rc" "$?"
  row "$1_web_accepted" "$(( $(accepted 10.0.1.10) - wb ))"; row "$1_gd_accepted" "$(( $(accepted 10.0.1.20) - gb ))"
  cp /out/remote.log "/out/$1.remote"
}
printf '/dev/sdb\n' > /fixture/findmnt.out; echo 0 > /fixture/findmnt.rc; rm -rf /mnt/git-data
drive2 r5
mkdir -p /mnt/git-data/repositories/ws-1.git
drive2 r6
printf '/dev/mapper/git-data\n' > /fixture/findmnt.out; rm -rf /mnt/git-data
drive2 r7
printf '/dev/sdb\n' > /fixture/findmnt.out; install -m 600 /tmp/ci.pub /etc/ssh/ak-gd
drive2 r8
kill "$W1" "$G1" 2>/dev/null
echo DRIVER_DONE
DRV
  : > "$T/rt/out/rows"
  # Bounded: a hung driver must fail this arm loudly, never eat the CI job's clock.
  _cname="gdc-access-$$-${RANDOM}"
  timeout -k 10 480 docker run --rm --cap-add NET_ADMIN --name "$_cname" -v "$T/rt/drive.sh:/work/drive.sh:ro" \
    -v "$T/rt/git-data-cutover.sh:/work/git-data-cutover.sh:ro" -v "$T/rt/sshcfg.sh:/work/sshcfg.sh:ro" \
    -v "$T/rt/out:/out" "$UBUNTU_BASE" bash /work/drive.sh > "$T/rt/stdout" 2>&1
  DRC=$?
  docker rm -f "$_cname" >/dev/null 2>&1 || true
  if grep -qx DRIVER_DONE "$T/rt/stdout"; then
    _rv() { sed -n "s/^$1=//p" "$T/rt/out/rows" | tail -1; }
    _acc() { grep -qE "^\[git-data-cutover\] ACCESS role=$2 host=[^ ]+ verdict=$3( |$)" "$T/rt/out/$1.out"; }
    _sto() { grep -qE "^\[git-data-cutover\] STORE probe=$2 verdict=$3( |$)" "$T/rt/out/$1.out"; }
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
    { [ "$(_rv ip_ok)" = 1 ] && [ "$(_rv sshcfg_rc)" = 0 ]; } \
      && pass "R5-fixture: 10.0.1.10/10.0.1.20 bound in the container and the workflow's ssh_config writer ran (rc 0)" || fail "R5-fixture: address binding or the ssh_config writer failed" "ip=$(_rv ip_ok) sshcfg=$(_rv sshcfg_rc) $(tr '\n' '|' < "$T/rt/out/sshcfg.out" 2>/dev/null | sed 's/::/: :/g')"
    { [ "$(_rv r5_rc)" = 0 ] && _acc r5 web ok && _acc r5 git-data-jump ok && _acc r5 git-data-auth ok && _sto r5 store-mounted ok && _sto r5 store-not-cut-over ok && _sto r5 store-empty ok; } \
      && pass "R5a/AC2 runtime: real OpenSSH through the generated ssh_config — access ok x3, store probes ok x3, exit 0" || fail "R5a: the end-to-end read-only proof did not exit 0" "rc=$(_rv r5_rc) $(_rctx r5)"
    [ "$(cat "$T/rt/out/r5.remote" 2>/dev/null)" = "findmnt -no SOURCE /mnt/git-data" ] \
      && pass "R5b: on git-data the only command observed is findmnt -no SOURCE /mnt/git-data (a missing repositories dir needs no find)" || fail "R5b: unexpected remote commands" "$(tr '\n' '|' < "$T/rt/out/r5.remote" 2>/dev/null)"
    { [ "$(_rv r5_web_accepted)" = 5 ] && [ "$(_rv r5_gd_accepted)" = 3 ]; } \
      && pass "R5c: web-1 accepted 5 CI-key logins (web, jump, and the ProxyCommand hop of auth/findmnt/count); git-data accepted 3 root-key logins" || fail "R5c: login counts differ" "web=$(_rv r5_web_accepted) gd=$(_rv r5_gd_accepted)"
    { [ "$(_rv r6_rc)" = 5 ] && _sto r6 store-empty store_not_empty; } \
      && pass "R6a: a real ws-1.git under /mnt/git-data/repositories -> store_not_empty, exit 5" || fail "R6a: a non-empty store passed" "rc=$(_rv r6_rc) $(_rctx r6)"
    grep -qxF "find -H /mnt/git-data/repositories -mindepth 1 -maxdepth 1 -name *.git -printf ." "$T/rt/out/r6.remote" \
      && pass "R6b: the count ran on git-data as find -H … -name *.git" || fail "R6b: the count command differs" "$(tr '\n' '|' < "$T/rt/out/r6.remote" 2>/dev/null)"
    { [ "$(_rv r7_rc)" = 5 ] && _sto r7 store-not-cut-over already_cut_over; } \
      && pass "R7: a mapper source -> already_cut_over, exit 5" || fail "R7: a mapper source passed" "rc=$(_rv r7_rc) $(_rctx r7)"
    { [ "$(_rv r8_rc)" = 3 ] && grep -qE 'role=git-data-auth host=10\.0\.1\.20 verdict=failed rc=[0-9]+ reason=auth_refused$' "$T/rt/out/r8.out"; } \
      && pass "R8 (negative control): git-data authorizing only the CI key -> auth_refused — the git-data block offers ONLY the root key" || fail "R8: the git-data block authenticated with a key other than the root key" "rc=$(_rv r8_rc) $(_rctx r8)"
  elif grep -qx FIXTURE_APT_FAILED "$T/rt/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$T/rt/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$T/rt/stdout" | tr '\n' ' ' | sed 's/::/: :/g')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER (ADR-193: reported with printf + exit, never through pass()/fail()) ─────
# MUTANT_FLOOR = the matrix rows this suite owns: Guard 2 x4, Guard 3 x4, Guard 5 x4,
# Guard 6 (cutover half) x1, Guard 7 x3 = 16.
MUTANT_FLOOR=16
if [ "$MUTANTS_RUN" -lt "$MUTANT_FLOOR" ]; then
  printf 'FAIL MUTANT FLOOR: only %s mutants executed, floor is %s — a matrix row did not land or was deleted.\n' "$MUTANTS_RUN" "$MUTANT_FLOOR" >&2
  exit 1
fi
# Assertion FLOOR, restated after the #8189 rewrite (the old 69 counted the deleted ROLLBACK and
# prepare_luks_target rows). Measured, by section: script unit rows 62 (access gate, AC2, Guard 2,
# Guard 5, Guard 7); bridge export set 6; workflow YAML 30; executed workflow steps 17 (key fetch 8,
# ssh_config 6, secrets check 3); Guard 3 census 8 + harness 2; mutants 16 x 2 = 32; runtime 17.
# Total 174 — exact, not a margin: removing an assertion on purpose costs one edit here.
FLOOR=174
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
