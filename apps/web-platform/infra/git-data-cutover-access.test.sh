#!/usr/bin/env bash
#
# git-data-cutover access path (#6680 / ADR-220). Two guards and a runtime arm.
#
# Guard 1 — git-data-cutover.sh's access_gate precedes every host mutation on the forward path:
#   web (every roster member) -> git-data-jump (an `ssh -W` banner through web-1, no git-data
#   credential) -> git-data-auth. A non-ok verdict exits 3 BEFORE prepare_luks_target. ROLLBACK
#   never waits on a probe, and no byte a probe returns reaches the runner's workflow-command
#   parser unsanitized. Observed through ONE timeline file ($TL): PATH shims for `ssh` and
#   `doppler` append their argv to it, so probe and mutating calls are ordered in one stream.
# Guard 2 — the bridge's "Decode CI SSH private key" step exports exactly {CI_SSH_KEYFILE,
#   WEB_HOST_SSH} on the server-ip branch (WEB_HOST_SSH byte-equal to its historical value) and
#   exactly {TF_VAR_ci_ssh_private_key} on the terraform branch. Executed, not grepped.
# Workflow — git-data-cutover.yml passes server-ip, tears the bridge down, references no secret
#   beyond the two Doppler tokens. Parsed as YAML (the header prose names every one of these).
# Runtime arm — the real script against real OpenSSH 9.6p1 in the pinned ubuntu:24.04 image
#   (git-data-ownership.test.sh precedent). Under CI=true a missing docker is a FAILURE.
#
# The script under test carries no test seam (ADR-214): this suite drives it through PATH shims
# only. The GDC_* variables below are seams of the SUITE, for running it against a mutated copy.
#
# Run: bash apps/web-platform/infra/git-data-cutover-access.test.sh
# Registered as a step in .github/workflows/infra-validation.yml.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/../../.." && pwd)"
SCRIPT="${GDC_SCRIPT:-$DIR/git-data-cutover.sh}"
ACTION="${GDC_ACTION:-$ROOT/.github/actions/cf-tunnel-ssh-bridge/action.yml}"
WF="${GDC_WORKFLOW:-$ROOT/.github/workflows/git-data-cutover.yml}"
IV="$ROOT/.github/workflows/infra-validation.yml"
UBUNTU_BASE='ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517'

passes=0; fails=0; SKIPPED=0
FAILURES=()
pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILURES+=("$1"); fails=$((fails + 1)); printf '  FAIL %s\n       %s\n' "$1" "${2:-}"; }

# Instrument self-test (ADR-193): drive both helpers once in a subshell and require both counters
# to move, so a neutered helper cannot report a clean run. Reported with printf + exit, never
# through the helpers themselves.
_st="$( (pass x >/dev/null; fail y >/dev/null; printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}") )"
if [ "$_st" != "1 1 1" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail() self-test read "%s", expected "1 1 1"\n' "$_st" >&2; exit 1
fi

for f in "$SCRIPT" "$ACTION" "$WF" "$IV"; do
  [ -f "$f" ] || { printf 'FAIL SETUP: %s not found\n' "$f" >&2; exit 1; }
done
python3 -c 'import yaml' 2>/dev/null || { printf 'FAIL SETUP: python3 yaml module unavailable\n' >&2; exit 1; }

T="$(mktemp -d "${TMPDIR}/gdc-access.XXXXXX")" || { printf 'FAIL SETUP: mktemp\n' >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
BIN="$T/bin"
mkdir -p "$BIN" || { printf 'FAIL SETUP: mkdir %s\n' "$BIN" >&2; exit 1; }

printf '\n=== git-data-cutover access path (ADR-220) ===\n\n'

# ── shims ─────────────────────────────────────────────────────────────────────────────
# ssh: log argv (newlines flattened) to $TL; parse options the way ssh does; refuse an empty
# destination (exit 64) so a gate that dials "" is visible; answer per scenario.
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
  [ -n "${SHIM_JUMP_STDERR:-}" ] && printf '%s\n' "$SHIM_JUMP_STDERR" >&2
  case "${SHIM_JUMP:-banner}" in
    banner)       printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    banner_extra) printf 'SSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\nextra-bytes\n'; exit 141 ;;
    line2)        printf '\nSSH-2.0-OpenSSH_9.6p1 Ubuntu-3ubuntu13.14\r\n'; exit 0 ;;
    none)         exit 255 ;;
  esac
fi
if [ "${cmd[*]}" = "true" ]; then
  if [ "$dest" = "${SHIM_GD_HOST:-10.0.1.20}" ]; then
    [ "${SHIM_AUTH_RC:-0}" = 0 ] || echo "root@${dest}: Permission denied (publickey)." >&2
    exit "${SHIM_AUTH_RC:-0}"
  fi
  for r in ${SHIM_WEB_REFUSE:-}; do
    [ "$r" = "$dest" ] && { echo "root@${dest}: Permission denied (publickey)." >&2; exit 255; }
  done
  exit 0
fi
exit "${SHIM_REMOTE_RC:-1}"
SHIM
cat > "$BIN/doppler" <<'SHIM'
#!/usr/bin/env bash
printf 'doppler %s\n' "$*" >> "$TL"
exit 0
SHIM
chmod +x "$BIN/ssh" "$BIN/doppler" || { printf 'FAIL SETUP: chmod shims\n' >&2; exit 1; }

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
# Helpers over the current case.
tl_ssh() { grep -c '^ssh ' "$TLF" || true; }
tl_line() { grep -nE -- "$1" "$TLF" | head -1 | cut -d: -f1; }           # first line number matching
has_access() { grep -qE "^\[git-data-cutover\] ACCESS role=$1 host=[^ ]+ verdict=$2( |$)" "$OUT"; }
mutating_remote() { grep -qE '^ssh .*(cryptsetup|mountpoint|rsync|systemctl|findmnt)' "$TLF"; }
ctx() { printf 'rc=%s | out: %s | tl: %s' "$RC" "$(tail -c 600 "$OUT" | tr '\n' '|')" "$(tr '\n' '|' < "$TLF" | cut -c1-400)"; }

# ── GUARD 1 — access gate (unit rows) ─────────────────────────────────────────────────

# S1 / AC2 — canonical dry-run: web ok, banner, GIT_DATA_SSH unset.
run_case s1 WEB_HOST_SSH="$WEB_INV" DRY_RUN=1 GITHUB_STEP_SUMMARY="$T/s1.summary"
if [ "$RC" = 3 ] && has_access web ok && has_access git-data-jump ok && has_access git-data-auth git_data_root_key_absent \
   && [ "$(grep -E '^\[git-data-cutover\] ACCESS ' "$OUT" | tail -1 | grep -c 'role=git-data-auth host=10.0.1.20 verdict=git_data_root_key_absent')" = 1 ]; then
  pass "S1: canonical dry-run exits 3 at git-data-auth verdict=git_data_root_key_absent after web ok + jump ok"
else fail "S1: canonical dry-run did not stop at git_data_root_key_absent with exit 3" "$(ctx)"; fi
if [ "$(tl_ssh)" = 2 ] && grep -qE '^ssh .* 10\.0\.1\.10 true$' "$TLF" && grep -qE '^ssh .* -W 10\.0\.1\.20:22 10\.0\.1\.10$' "$TLF" && ! mutating_remote; then
  pass "S1/S12: the timeline holds exactly the web probe and the jump probe — no remote after exit 3, and the EXIT trap added none"
else fail "S1/S12: timeline is not exactly {web probe, jump probe}" "$(ctx)"; fi
if [ "$(grep -c 'ACCESS role=' "$T/s1.summary" 2>/dev/null || echo 0)" = 3 ]; then
  pass "S1: the three verdict lines are appended to \$GITHUB_STEP_SUMMARY"
else fail "S1: \$GITHUB_STEP_SUMMARY does not carry the three ACCESS verdicts" "$(cat "$T/s1.summary" 2>/dev/null | tr '\n' '|')"; fi
# S15 — ok -> ::notice, non-ok -> ::error.
if grep -qxE '::notice title=git-data-cutover access::role=web verdict=ok' "$OUT" \
   && grep -qxE '::notice title=git-data-cutover access::role=git-data-jump verdict=ok' "$OUT" \
   && grep -qxE '::error title=git-data-cutover access::role=git-data-auth verdict=git_data_root_key_absent' "$OUT" \
   && ! grep -qE '^::error title=git-data-cutover access::role=(web|git-data-jump) ' "$OUT"; then
  pass "S15: ok verdicts emit ::notice, the non-ok verdict emits ::error"
else fail "S15: annotation levels do not follow the verdicts" "$(grep '^::' "$OUT" | tr '\n' '|')"; fi

# S2 / AC3 / row 1 — key present, auth refused.
run_case s2 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_AUTH_RC=255 DRY_RUN=1
if [ "$RC" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=git-data-auth host=10\.0\.1\.20 verdict=failed rc=255$' "$OUT" && ! mutating_remote \
   && grep -qE '^ssh -i FIXTURE_GD_KEY .* 10\.0\.1\.20 true$' "$TLF"; then
  pass "S2/row1: key set + auth refused -> exit 3, verdict=failed rc=255, no mutating remote in the timeline"
else fail "S2/row1: a refused auth did not stop the run before prepare_luks_target" "$(ctx)"; fi

# S11 / H3 / row 2 — all ok, two-host roster, key set: the gate passes and prepare_luks_target's
# remote FOLLOWS every probe in the timeline.
run_case s11 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" WEB_HOSTS="10.0.1.10 10.0.1.11" DRY_RUN=1
_w1="$(tl_line ' 10\.0\.1\.10 true$')"; _w2="$(tl_line ' 10\.0\.1\.11 true$')"; _j="$(tl_line ' -W 10\.0\.1\.20:22 ')"
_a="$(tl_line '^ssh -i FIXTURE_GD_KEY .* 10\.0\.1\.20 true$')"; _m="$(tl_line 'cryptsetup')"
if [ -n "$_w1" ] && [ -n "$_w2" ] && [ -n "$_j" ] && [ -n "$_a" ] && [ -n "$_m" ] \
   && [ "$_w1" -lt "$_w2" ] && [ "$_w2" -lt "$_j" ] && [ "$_j" -lt "$_a" ] && [ "$_a" -lt "$_m" ] \
   && has_access git-data-auth ok && [ "$RC" != 3 ]; then
  pass "S11/H3/row2: all probes ok -> the gate passes; web(10) < web(11) < jump < auth < prepare_luks_target remote"
else fail "S11/H3/row2: gate order in the timeline is wrong or the gate did not pass" "w1=$_w1 w2=$_w2 j=$_j a=$_a m=$_m $(ctx)"; fi
# row 10 — the jump dials the FIRST roster member.
if grep -qE '^ssh .* -W 10\.0\.1\.20:22 10\.0\.1\.10$' "$TLF" && ! grep -qE ' -W 10\.0\.1\.20:22 10\.0\.1\.11$' "$TLF"; then
  pass "row10: the jump dials the first roster member"
else fail "row10: the jump did not dial the first roster member" "$(ctx)"; fi

# S6 / row 4 — second roster member refuses.
run_case s6 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" WEB_HOSTS="10.0.1.10 10.0.1.11" SHIM_WEB_REFUSE=10.0.1.11 DRY_RUN=1
if [ "$RC" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=web host=10\.0\.1\.11 verdict=failed rc=255$' "$OUT" \
   && ! grep -qE ' -W ' "$TLF" && ! mutating_remote; then
  pass "S6/row4: the second roster member's refusal exits 3 naming it, before the jump"
else fail "S6/row4: a refusing second roster member was not caught" "$(ctx)"; fi

# S7 / row 3 — empty roster (whitespace: an EMPTY WEB_HOSTS takes the script's default).
run_case s7 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS=" " DRY_RUN=1
if [ "$RC" = 3 ] && has_access web web_roster_empty && [ "$(tl_ssh)" = 0 ]; then
  pass "S7/row3: an empty roster exits 3 with web_roster_empty and dials nothing"
else fail "S7/row3: an empty roster was not refused" "$(ctx)"; fi

# S8 — WEB_HOST_SSH unset on the forward path.
run_case s8 DRY_RUN=1
if [ "$RC" = 3 ] && has_access web web_host_ssh_unset && [ "$(tl_ssh)" = 0 ]; then
  pass "S8: WEB_HOST_SSH unset -> web_host_ssh_unset, exit 3 (not a set -u death)"
else fail "S8: WEB_HOST_SSH unset did not produce web_host_ssh_unset + exit 3" "$(ctx)"; fi

# S9 — argument hygiene: a roster member shaped like an ssh option.
run_case s9 WEB_HOST_SSH="$WEB_INV" WEB_HOSTS="-oProxyCommand=touch${IFS:0:1}$T/pwn" DRY_RUN=1
if [ "$RC" = 3 ] && has_access web invalid_host && [ "$(tl_ssh)" = 0 ] && [ ! -e "$T/pwn" ]; then
  pass "S9: an option-shaped roster member is invalid_host and never reaches ssh argv"
else fail "S9: an option-shaped roster member was not refused" "$(ctx)"; fi
run_case s9b WEB_HOST_SSH="$WEB_INV" GIT_DATA_HOST="-oProxyCommand=x" DRY_RUN=1
if [ "$RC" = 3 ] && has_access git-data-jump invalid_host && [ "$(tl_ssh)" = 0 ]; then
  pass "S9b: an option-shaped GIT_DATA_HOST is invalid_host before any probe"
else fail "S9b: an option-shaped GIT_DATA_HOST was not refused" "$(ctx)"; fi

# S10 — key set, web fails: neither jump nor auth is dialed.
run_case s10 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_WEB_REFUSE=10.0.1.10 DRY_RUN=1
if [ "$RC" = 3 ] && has_access web failed && ! grep -qE ' -W |FIXTURE_GD_KEY' "$TLF"; then
  pass "S10: a failed web probe stops before the jump and the auth probe"
else fail "S10: probes continued after a failed web probe" "$(ctx)"; fi

# S3 / row 6 — key set, jump returns no banner: jump failed, no auth probe.
FIX_R2_STDERR='channel 0: open failed: administratively prohibited: open failed'
run_case s3 WEB_HOST_SSH="$WEB_INV" GIT_DATA_SSH="$GD_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FIX_R2_STDERR" DRY_RUN=1
if [ "$RC" = 3 ] && grep -qE '^\[git-data-cutover\] ACCESS role=git-data-jump host=10\.0\.1\.20 verdict=failed rc=255$' "$OUT" \
   && ! grep -q 'FIXTURE_GD_KEY' "$TLF" && ! has_access git-data-auth '[a-z_]+'; then
  pass "S3/row6: no banner -> git-data-jump verdict=failed; the auth probe never ran"
else fail "S3/row6: a failed jump did not stop before the auth probe" "$(ctx)"; fi
if grep -qF "[git-data-cutover] probe-stderr: ${FIX_R2_STDERR}" "$OUT"; then
  pass "S3: the failed probe's stderr is logged behind the fixed probe-stderr prefix"
else fail "S3: the failed probe's stderr was not logged" "$(ctx)"; fi

# S4 / row 7 — banner then more output, pipeline rc 141 -> ok.
run_case s4 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=banner_extra DRY_RUN=1
if [ "$RC" = 3 ] && has_access git-data-jump ok && has_access git-data-auth git_data_root_key_absent; then
  pass "S4/row7: banner + extra output (rc 141) is jump ok — the verdict keys on the banner, not the rc"
else fail "S4/row7: a banner followed by more output was not read as ok" "$(ctx)"; fi

# S5 — banner on line 2 -> failed.
run_case s5 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=line2 DRY_RUN=1
if [ "$RC" = 3 ] && has_access git-data-jump failed; then
  pass "S5: a banner on the second line is jump failed"
else fail "S5: a second-line banner was accepted" "$(ctx)"; fi

# S14 / row 9 — forged workflow commands in probe stderr never escape the stop-commands span.
FORGED=$'::error title=git-data-cutover access::role=git-data-jump verdict=ok\r\n::add-mask::x\r\n::stop-commands::guess'
run_case s14 WEB_HOST_SSH="$WEB_INV" SHIM_JUMP=none SHIM_JUMP_STDERR="$FORGED" DRY_RUN=1
_s14="$(python3 - "$OUT" <<'PY'
import re, sys
lines = open(sys.argv[1], 'rb').read().decode('latin-1').split('\n')
if any('\r' in l for l in lines): print('CR present'); sys.exit()
allowed = re.compile(r'^::(notice|error) title=git-data-cutover access::role=[a-z-]+ verdict=[a-z_]+( rc=[0-9]+)?$|^::warning title=git-data-cutover recovery::step=[a-z_]+ rc=[0-9]+$')
tok = None; spans = 0; inside = False; forged_inside = False
for l in lines:
    if inside:
        if l == '::%s::' % tok: inside = False; continue
        if not l.startswith('[git-data-cutover] probe-stderr: '): print('unprefixed line in span: %r' % l[:80]); sys.exit()
        if 'verdict=ok' in l: forged_inside = True
        if any(ord(c) < 32 or ord(c) > 126 for c in l): print('non-printable in span'); sys.exit()
        continue
    m = re.match(r'^::stop-commands::([0-9a-f]{16,})$', l)
    if m: tok = m.group(1); inside = True; spans += 1; continue
    if l.startswith('::') and not allowed.match(l): print('escaped command: %r' % l[:100]); sys.exit()
if inside: print('span never closed'); sys.exit()
print('OK' if spans == 1 and forged_inside else 'spans=%d forged_inside=%s' % (spans, forged_inside))
PY
)"
if [ "$_s14" = OK ] && has_access git-data-jump failed; then
  pass "S14/row9: forged ::error/::add-mask/::stop-commands bytes stay inside one random-token span, printable-ASCII, prefixed"
else fail "S14/row9: probe bytes reached the workflow-command parser" "$_s14 | $(ctx)"; fi

# S13 / rows 5, 8 — ROLLBACK: the flag-off write precedes every ssh; no probe delays it; failed
# steps each emit a ::warning. Both invocations unset: no bare `ssh` fallback may appear.
for dr in 0 1; do
  run_case "s13u$dr" ROLLBACK=1 DRY_RUN="$dr"
  if [ "$RC" = 0 ] && [ "$(tl_ssh)" = 0 ] && grep -qE '^doppler secrets set GIT_DATA_STORE_ENABLED false ' "$TLF" \
     && ! grep -q 'ACCESS role=' "$OUT"; then
    pass "S13/row5 (DRY_RUN=$dr): ROLLBACK with both invocations unset writes the flag off and dials no bare ssh"
  else fail "S13/row5 (DRY_RUN=$dr): ROLLBACK reached a bare ssh or skipped the flag write" "$(ctx)"; fi
  if [ "$(grep -cE '^::warning title=git-data-cutover recovery::step=(web_restart|freeze_sentinel_rm|web_undrain) rc=97$' "$OUT")" = 3 ]; then
    pass "S13 (DRY_RUN=$dr): each unreachable rollback step emits its own ::warning with rc=97 (wall 6: the freeze release ignores DRY_RUN)"
  else fail "S13 (DRY_RUN=$dr): rollback warnings missing — a default dry_run=true rollback must still release the freeze" "$(grep '^::' "$OUT" | tr '\n' '|')"; fi
done
run_case s13r ROLLBACK=1 DRY_RUN=1 WEB_HOST_SSH="$WEB_INV" SHIM_WEB_REFUSE=10.0.1.10
_f="$(tl_line '^doppler secrets set GIT_DATA_STORE_ENABLED false ')"; _s="$(tl_line '^ssh ')"
if [ "$RC" = 0 ] && [ -n "$_f" ] && [ -n "$_s" ] && [ "$_f" -lt "$_s" ] && ! grep -qE ' true$' "$TLF"; then
  pass "S13/row8: ROLLBACK with a refusing web-1 writes the flag off first and runs no access probe"
else fail "S13/row8: a probe ran in ROLLBACK or preceded the flag-off write" "f=$_f s=$_s $(ctx)"; fi

# H5 — structural: access_gate is a plain statement, the first after the ROLLBACK block, called
# exactly once, and its definition exits 3 (never returns 3).
_code="$(sed -E 's/^[[:space:]]*#.*$//; s/[[:space:]]+#[^"'"'"']*$//' "$SCRIPT")"
_main="$(awk '/^main\(\) \{/{m=1; next} m && /^\}/{exit} m' <<< "$_code")"
_after="$(awk 'done_rb && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*log[[:space:]]/ {print; exit} /^  fi[[:space:]]*$/ {done_rb=1}' <<< "$_main")"
_def="$(awk '/^access_gate\(\) \{/{m=1; next} m && /^\}/{exit} m' <<< "$_code")"
_calls="$(grep -cE '(^|[^A-Za-z0-9_])access_gate([^A-Za-z0-9_(]|$)' <<< "$_code" || true)"
if grep -qE '^[[:space:]]*access_gate[[:space:]]*$' <<< "$_after" && [ "$_calls" = 1 ] \
   && grep -qE '(^|[[:space:];{])exit 3([[:space:];}]|$)' <<< "$_def" && ! grep -qE 'return 3' <<< "$_def"; then
  pass "H5: access_gate is the first plain statement after the ROLLBACK block, called once, and exits 3 from its own body"
else fail "H5: access_gate call site/definition shape is wrong" "after=[$_after] calls=$_calls def_has_exit3=$(grep -c 'exit 3' <<< "$_def")"; fi

# AC5 — no `${X_SSH:-ssh}`-style fallback survives in any form.
if ! grep -nE '_SSH:?[-=]ssh\}' "$SCRIPT" >/dev/null; then
  pass "AC5: no \${*_SSH:-ssh} / :=ssh / -ssh / =ssh fallback in git-data-cutover.sh"
else fail "AC5: an ssh fallback expansion survives" "$(grep -nE '_SSH:?[-=]ssh\}' "$SCRIPT")"; fi

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
    mkdir -p "$troot" || { printf 'FAIL SETUP: mkdir %s\n' "$troot" >&2; exit 1; }
    rm -f "$troot/k" "$troot/k.pub"
    ssh-keygen -q -t ed25519 -N '' -C "g2-$label" -f "$troot/k" || { printf 'FAIL SETUP: ssh-keygen\n' >&2; exit 1; }
    : > "$troot/github_env"
    env -i PATH="$T/g2bin:/usr/bin:/bin" TMPDIR="$troot" GITHUB_ENV="$troot/github_env" G2_KEY="$troot/k" \
      DOPPLER_TOKEN=fixture SERVER_IP_INPUT="$sip" bash --noprofile --norc -eo pipefail "$T/decode.sh" > "$troot/stdout" 2>&1
    G2_RC=$?; G2_ENV="$troot/github_env"
  }
  for variant in canonical other; do
    _g2_run "sip-$variant" 10.0.1.10 "$T/g2-$variant"
    _got="$(_names "$G2_ENV")"
    _kf="$(sed -n 's/^CI_SSH_KEYFILE=//p' "$G2_ENV")"
    _want_inv="ssh -i ${_kf} -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root"
    if [ "$G2_RC" = 0 ] && [ "$_got" = "CI_SSH_KEYFILE,WEB_HOST_SSH" ]; then
      pass "G2 ($variant key): server-ip branch exports exactly {CI_SSH_KEYFILE, WEB_HOST_SSH}"
    else fail "G2 ($variant key): server-ip branch export set is [$_got] (rc=$G2_RC), expected CI_SSH_KEYFILE,WEB_HOST_SSH" "$(tail -3 "$T/g2-$variant/stdout" | tr '\n' '|')"; fi
    if [ -n "$_kf" ] && [ "$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")" = "$_want_inv" ] && cmp -s "$_kf" "$T/g2-$variant/k"; then
      pass "G2 ($variant key): WEB_HOST_SSH is byte-equal to the historical invocation and the keyfile holds the key"
    else fail "G2 ($variant key): WEB_HOST_SSH value or keyfile content changed" "got=[$(sed -n 's/^WEB_HOST_SSH=//p' "$G2_ENV")] want=[$_want_inv]"; fi
  done
  _g2_run tf "" "$T/g2-tf"
  _got="$(_names "$G2_ENV")"
  if [ "$G2_RC" = 0 ] && [ "$_got" = "TF_VAR_ci_ssh_private_key" ]; then
    pass "G2: terraform branch exports exactly {TF_VAR_ci_ssh_private_key} (heredoc form parsed)"
  else fail "G2: terraform branch export set is [$_got] (rc=$G2_RC), expected TF_VAR_ci_ssh_private_key" "$(tail -3 "$T/g2-tf/stdout" | tr '\n' '|')"; fi
fi

# ── WORKFLOW — git-data-cutover.yml wiring (AC6) + registration (AC10) ─────────────────
python3 - "$WF" "$IV" > "$T/wf.tsv" <<'PY'
import sys, yaml, json, re
wf = yaml.safe_load(open(sys.argv[1])); iv = yaml.safe_load(open(sys.argv[2]))
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
if bridge:
    b = steps[bridge[0]]
    check("WF3: bridge passes server-ip from env.WEB_HOST_PRIVATE_IP", (b.get("with") or {}).get("server-ip") == "${{ env.WEB_HOST_PRIVATE_IP }}", (b.get("with") or {}).get("server-ip"))
    check("WF4: bridge step carries no if: (dry-run is host-touching)", "if" not in b)
check("WF5: exactly one Run step", len(run) == 1, len(run))
if run:
    check("WF6: Run step env.WEB_HOSTS is env.WEB_HOST_PRIVATE_IP", ((steps[run[0]].get("env") or {}).get("WEB_HOSTS")) == "${{ env.WEB_HOST_PRIVATE_IP }}", (steps[run[0]].get("env") or {}).get("WEB_HOSTS"))
check("WF7: exactly one teardown step, if: always(), after the Run step",
      len(tear) == 1 and bool(run) and tear[0] > run[0] and steps[tear[0]].get("if") == "always()", (tear, run))
body = (steps[tear[0]].get("run") or "") if len(tear) == 1 else ""
check("WF8: teardown deletes the NAT rule, kills cloudflared and shreds the keyfile, each -n guarded",
      all(t in body for t in ('[[ -n "${SERVER_IP:-}" ]]', 'iptables -t nat -D OUTPUT', '[[ -n "${CLOUDFLARED_PID:-}" ]]', 'shred -u "$CI_SSH_KEYFILE"')))
secrets = sorted(set(re.findall(r"secrets\.([A-Za-z0-9_]+)", json.dumps(wf.get("jobs")))))
check("WF9: no secret beyond DOPPLER_TOKEN and DOPPLER_TOKEN_WRITE is referenced", secrets == ["DOPPLER_TOKEN", "DOPPLER_TOKEN_WRITE"], secrets)
runs = [s.get("run", "") for j in (iv.get("jobs") or {}).values() for s in (j.get("steps") or [])]
check("AC10: infra-validation.yml runs this suite", "bash apps/web-platform/infra/git-data-cutover-access.test.sh" in [r.strip() for r in runs if isinstance(r, str)])
print("\n".join(out))
PY
_wf_n=0
while IFS=$'\t' read -r v name detail; do
  [ -n "$v" ] || continue
  _wf_n=$((_wf_n + 1))
  if [ "$v" = ok ]; then pass "$name"; else fail "$name" "$detail"; fi
done < "$T/wf.tsv"
[ "$_wf_n" -ge 10 ] || fail "WF: only $_wf_n workflow verdicts were produced (expected >= 10) — the YAML leg crashed" "$(head -c 300 "$T/wf.tsv")"

# ── RUNTIME ARM — real OpenSSH 9.6p1 (pinned ubuntu:24.04) ─────────────────────────────
RUNTIME_ROWS=8
_runtime_skip() {
  if [ "${CI:-}" = "true" ]; then
    fail "runtime arm: $1 — and CI=true, so this is a FAILURE: the runner must provide docker"
  else
    SKIPPED=$((SKIPPED + RUNTIME_ROWS)); printf '  SKIP runtime arm (%s rows): %s\n' "$RUNTIME_ROWS" "$1"
  fi
}
if [ "${GDC_SKIP_RUNTIME:-}" = 1 ] && [ "${CI:-}" != "true" ]; then _runtime_skip "GDC_SKIP_RUNTIME=1 (local iteration)"
elif ! command -v docker >/dev/null 2>&1; then _runtime_skip "docker absent"
elif ! docker info >/dev/null 2>&1; then _runtime_skip "docker daemon unreachable"
else
  mkdir -p "$T/rt" || { printf 'FAIL SETUP: mkdir rt\n' >&2; exit 1; }
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
  env -i PATH=/usr/sbin:/usr/bin:/bin HOME=/root DRY_RUN=1 WEB_HOSTS=127.0.0.1 GIT_DATA_HOST=127.0.0.2 \
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
sleep 1
drive r4 2201
kill "$WEB_OK" "$WEB_NOFWD" 2>/dev/null
echo DRIVER_DONE
DRV
  : > "$T/rt/rows"
  mkdir -p "$T/rt/out" && : > "$T/rt/out/rows"
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
    _rctx() { tr '\n' '|' < "$T/rt/out/$1.out" | tail -c 500; }
    { [ "$(_rv r1_rc)" = 3 ] && _acc r1 web ok; } && pass "R1a: real sshd — web ok and the run exits 3" || fail "R1a: real-sshd web probe/exit" "rc=$(_rv r1_rc) $(_rctx r1)"
    _acc r1 git-data-jump ok && pass "R1b: real sshd — ssh -W returns git-data's SSH-2.0- banner (jump ok, no git-data credential)" || fail "R1b: real-sshd jump not ok" "$(_rctx r1)"
    _acc r1 git-data-auth git_data_root_key_absent && pass "R1c: real sshd — git-data-auth verdict=git_data_root_key_absent" || fail "R1c: real-sshd auth verdict" "$(_rctx r1)"
    _el="$(_rv r1_elapsed)"
    { [ -n "$_el" ] && [ "$_el" -lt 20 ]; } && pass "R1d: the canonical gate finished in ${_el}s (< 20s bound)" || fail "R1d: the gate took ${_el:-?}s (>= 20s)" "$(_rctx r1)"
    { [ "$(_rv r2_rc)" = 3 ] && _acc r2 git-data-jump failed; } && pass "R2a: AllowTcpForwarding no — jump failed, exit 3" || fail "R2a: forwarding-refused jump not failed" "$(_rctx r2)"
    grep -qF '[git-data-cutover] probe-stderr: channel 0: open failed: administratively prohibited: open failed' "$T/rt/out/r2.out" \
      && pass "R2b: the real refusal stderr matches the unit rows' fixture text" || fail "R2b: real refusal stderr differs from the fixture" "$(_rctx r2)"
    { [ "$(_rv r3_rc)" = 3 ] && _acc r3 git-data-jump failed; } && pass "R3: git-data sshd stopped — jump failed" || fail "R3: stopped target not failed" "$(_rctx r3)"
    { [ "$(_rv r4_rc)" = 3 ] && _acc r4 git-data-jump failed; } && pass "R4 (negative control): a non-SSH listener is jump failed — the banner rule can fail" || fail "R4: a non-SSH listener was accepted as a banner" "$(_rctx r4)"
  elif grep -qx FIXTURE_APT_FAILED "$T/rt/stdout" || [ "$DRC" = 125 ]; then
    _runtime_skip "container did not reach the fixture (docker rc=$DRC): $(tail -2 "$T/rt/stdout" | tr '\n' ' ')"
  else
    fail "runtime arm: the driver did not complete (docker rc=$DRC)" "$(tail -5 "$T/rt/stdout" | tr '\n' ' ')"
    SKIPPED=$((SKIPPED + RUNTIME_ROWS - 1))
  fi
fi

# ── FLOOR + LEDGER (ADR-193: reported with printf + exit, never through pass()/fail()) ─────
# Guard 1: S1 x3, S15, S2, S11, row10, S6, S7, S8, S9, S9b, S10, S3 x2, S4, S5, S14, S13 x2 x2, S13r, H5, AC5 = 25
# Guard 2: extract + 2 variants x 2 + tf = 6. Workflow: WF1..WF9 + AC10 = 10. Runtime: 8. Total 49.
FLOOR=49
_ran=$((passes + fails + SKIPPED))
if [ "$_ran" -lt "$FLOOR" ]; then
  printf 'FAIL ANTI-VACUITY: only %s assertions ran/declared, floor is %s — cases were deleted, skipped, or the suite exited early.\n' "$_ran" "$FLOOR" >&2
  exit 1
fi
if [ "${#FAILURES[@]}" -ne "$fails" ]; then
  printf 'FAIL LEDGER: %s failures counted but %s recorded\n' "$fails" "${#FAILURES[@]}" >&2; exit 1
fi
printf '\n=== git-data-cutover-access: %d passed, %d failed, %d skipped ===\n\n' "$passes" "$fails" "$SKIPPED"
exit $(( ${#FAILURES[@]} > 0 ))
