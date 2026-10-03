#!/usr/bin/env bash
# web-host-escrow-preflight.test.sh -- behavioural suite for scripts/web-host-escrow-preflight.sh, the one reusable
# step every web-host birth route runs before it can change anything (#9377, decision B1, Guard 3).
#
# THE PROPERTY UNDER TEST. The preflight (1) refuses xtrace before it reads any credential, (2) takes the Doppler
# provider token from TF_VAR_doppler_token_tf when the environment has it and otherwise reads EXACTLY ONE named
# secret (DOPPLER_TOKEN_TF in soleur/prd_terraform) with the step's own token, (3) fails BEFORE the checker when no
# usable token results, (4) never lets a token byte reach argv, a file, or the job log (the one exception is the
# `::add-mask::` directive for the fallback value, which is the redaction itself), and (5) fails closed with the
# checker's own exit code. It is tested against a Doppler STUB that replays the real CLI contract and refuses
# (rc 64) anything the wrapper is not supposed to call. A stub proves the plan's spelling, not the tool's contract
# (learning 2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md), so the end-to-end rows
# run the REAL checker behind the stub, and the stub grants a name listing only to the provider token: a wrapper
# that handed the checker the step's prd_terraform token would read exit 3, as it would live.
#
# All tokens here are synthetic strings (cq-test-fixtures-synthesized-only).
#
# Run: bash scripts/web-host-escrow-preflight.test.sh
# NOT globbed: scripts/*.test.sh is registered by an explicit run_suite line in scripts/test-all.sh.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$SRC_ROOT/scripts/web-host-escrow-preflight.sh"

passes=0
fails=0
ok() { passes=$((passes + 1)); echo "[ok] $1"; }
no() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

[[ -f "$SUT" ]] || { echo "[FAIL] SUT not found: $SUT (RED: the preflight wrapper does not exist yet)" >&2; exit 1; }

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
SCR="$(mktemp -d "$TMPDIR/escrow-preflight.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SCR"
trap 'rm -rf "${SCR:?}"' EXIT

# Synthetic tokens. ENVTOK is the provider token the Tier-B loader exports; FALLTOK is what the single fallback read
# returns; STEPTOK is the step's own prd_terraform token (it must never be handed to the checker).
ENVTOK="dp.pt.SYNTHenvTOKEN0001aaaa"
FALLTOK="dp.pt.SYNTHfallTOKEN0002bbbb"
STEPTOK="dp.st.SYNTHstepTOKEN0003cccc"

STUB_DIR="$SCR/stubbin"; MOCK="$SCR/mock"; FAKE="$SCR/fakeroot"; HOME_D="$SCR/home"
mkdir -p "$STUB_DIR" "$MOCK" "$FAKE/scripts" "$HOME_D"
MOCK_LOG="$SCR/doppler.log"; FAKE_LOG="$SCR/checker.log"

# --- The Doppler stub ---------------------------------------------------------------------------------------------
# `secrets get NAME -p P -c C --plain`: only DOPPLER_TOKEN_TF in soleur/prd_terraform is modelled; any other name,
# project, config or flag is a HARD STUB ERROR (rc 64), as is any subcommand other than `secrets` (so `doppler run`
# cannot pass). `secrets --only-names -p P -c C` replays the checker suite's table contract, but grants a listing only
# when the caller's DOPPLER_TOKEN equals MOCK_NAMES_TOK (a workplace-scope token); otherwise the measured
# "does not have access to requested config" failure. The stub logs argv and WHICH token authenticated, never a token.
cat > "$STUB_DIR/doppler" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "${MOCK_LOG:?}"
[[ "${1:-}" == "secrets" ]] || { echo "STUB ERROR: unexpected subcommand '$*'" >&2; exit 64; }
shift
sub=""; only=0; proj=""; cfg=""; plain=0; names=()
while (($#)); do
  case "$1" in
    get) sub=get ;;
    --only-names) only=1 ;;
    -p|--project) proj="${2:-}"; shift ;;
    -c|--config)  cfg="${2:-}"; shift ;;
    --plain) plain=1 ;;
    --no-check-version) ;;
    -*) echo "STUB ERROR: unexpected flag '$1'" >&2; exit 64 ;;
    *) names+=("$1") ;;
  esac
  shift
done
if [[ -z "${DOPPLER_TOKEN:-}" ]]; then printf 'AUTH none\n' >> "$MOCK_LOG"
elif [[ "${DOPPLER_TOKEN}" == "${MOCK_STEP_TOK:-}" ]]; then printf 'AUTH step\n' >> "$MOCK_LOG"
elif [[ "${DOPPLER_TOKEN}" == "${MOCK_NAMES_TOK:-}" ]]; then printf 'AUTH provider\n' >> "$MOCK_LOG"
else printf 'AUTH other\n' >> "$MOCK_LOG"; fi
if [[ "$sub" == get ]]; then
  [[ "$plain" == 1 && "$proj" == soleur && "$cfg" == prd_terraform && "${#names[@]}" == 1 && "${names[0]}" == DOPPLER_TOKEN_TF ]] \
    || { echo "STUB ERROR: only 'secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain' is modelled (got: ${names[*]:-} p=$proj c=$cfg plain=$plain)" >&2; exit 64; }
  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then printf 'Unable to fetch secret\nDoppler Error: Invalid Auth token\n' >&2; exit 1; fi
  if [[ -n "${MOCK_GET_FAIL:-}" ]]; then
    [[ -z "${MOCK_GET_FAIL_OUT:-}" ]] || printf '%s\n' "$MOCK_GET_FAIL_OUT"
    printf 'Unable to fetch secret\nDoppler Error: vendor outage%s\n' "${MOCK_GET_FAIL_ERR:+ ${MOCK_GET_FAIL_ERR}}" >&2; exit 1
  fi
  printf '%s\n' "${MOCK_TFVAL-}"
  exit 0
fi
[[ "$only" == 1 ]] || { echo "STUB ERROR: only --only-names and secrets get are modelled" >&2; exit 64; }
[[ -n "$proj" && -n "$cfg" ]] || { echo "STUB ERROR: --only-names invoked with no -p/-c" >&2; exit 64; }
if [[ -z "${DOPPLER_TOKEN:-}" || ( -n "${MOCK_NAMES_TOK:-}" && "${DOPPLER_TOKEN}" != "${MOCK_NAMES_TOK}" ) ]]; then
  printf 'Unable to fetch secret names\nDoppler Error: This token does not have access to requested config\n' >&2; exit 1
fi
file="${MOCK_DIR:?}/${cfg}.names"
[[ -f "$file" ]] || { printf 'Unable to fetch secret names\nDoppler Error: Could not find requested config\n' >&2; exit 1; }
printf 'NAME\n----\n'; cat "$file"
exit 0
STUB
chmod +x "$STUB_DIR/doppler"

# --- The fake checker (for the rows that must observe the handoff, not the checker) --------------------------------
# It records its argv and whether the token it was handed equals the one the row expects (a verdict, never the token).
cat > "$FAKE/scripts/check-web-host-escrow-config.sh" <<'FAKECHK'
#!/usr/bin/env bash
printf 'CALLED %s\n' "$*" >> "${FAKE_LOG:?}"
printf 'ADVISORY=%s\n' "${ESCROW_ADVISORY:-}" >> "$FAKE_LOG"
if [[ -n "${DOPPLER_TOKEN:-}" && "${DOPPLER_TOKEN}" == "${FAKE_EXPECT_TOK:-}" ]]; then echo TOKEN_MATCH >> "$FAKE_LOG"; else echo TOKEN_MISMATCH >> "$FAKE_LOG"; fi
[[ -z "${FAKE_NOISE:-}" ]] || echo "$FAKE_NOISE"
exit "${FAKE_RC:-0}"
FAKECHK
chmod +x "$FAKE/scripts/check-web-host-escrow-config.sh"
cp "$SUT" "$FAKE/scripts/web-host-escrow-preflight.sh"
WRAP_FAKE="$FAKE/scripts/web-host-escrow-preflight.sh"

seed_names() {
  printf '%s\n' DOPPLER_PROJECT DOPPLER_ENVIRONMENT DOPPLER_CONFIG WORKSPACES_LUKS_KEY WORKSPACES_HEADER_BUCKET WORKSPACES_HEADER_R2_ENDPOINT WORKSPACES_HEADER_R2_ACCESS_KEY_ID WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY SENTRY_DSN > "$MOCK/prd_workspaces_luks_web.names"
  printf '%s\n' DOPPLER_PROJECT DOPPLER_CONFIG SENTRY_DSN CF_API_TOKEN DATABASE_URL SOME_SECRET > "$MOCK/prd.names"
}
reset_logs() { : > "$MOCK_LOG"; : > "$FAKE_LOG"; rm -f "$MOCK"/*.names; seed_names; }

# run <wrapper> [bash flags before the script via RUN_BASHFLAGS] -- env assignments...
# The environment is rebuilt from nothing (env -i) so an ambient TF_VAR_doppler_token_tf or DOPPLER_TOKEN of the
# machine running the suite can never leak into a row.
run() { # <wrapper path> [VAR=value ...]
  local w="$1"; shift
  OUT="$(env -i PATH="$STUB_DIR:$PATH" HOME="$HOME_D" TMPDIR="$SCR" MOCK_LOG="$MOCK_LOG" FAKE_LOG="$FAKE_LOG" MOCK_DIR="$MOCK" \
         MOCK_STEP_TOK="$STEPTOK" MOCK_NAMES_TOK="$ENVTOK" "$@" bash ${RUN_BASHFLAGS:-} "$w" 2>&1)"; RC=$?
}

check() { # <label> <condition rc 0 = pass>
  if [[ "$2" -eq 0 ]]; then ok "$1"; else no "$1 (rc=$RC out=${OUT:0:300})"; fi
}
log_has()  { grep -qxF -- "$1" "$2"; }
# Absence needs grep rc == 1 EXACTLY: rc 2 is an unreadable or missing log, which says nothing about absence and must FAIL.
log_lacks()    { local r; grep -qF -- "$1" "$2"; r=$?; [[ "$r" -eq 1 ]]; }
log_lacks_re() { local r; grep -qE -- "$1" "$2"; r=$?; [[ "$r" -eq 1 ]]; }
checker_calls() { grep -c '^CALLED' "$FAKE_LOG" || true; }
# no_leak <token...>: no token byte anywhere in the job-visible output, in the stub's argv log or the checker's log,
# EXCEPT the one `::add-mask::<token>` directive line, which is the redaction mechanism itself.
no_leak() {
  local t body
  for t in "$@"; do
    body="$(printf '%s\n' "$OUT" | grep -vxF -- "::add-mask::${t}" || true)"
    [[ "$body" != *"$t"* ]] || return 1
    log_lacks "$t" "$MOCK_LOG" || return 1
    log_lacks "$t" "$FAKE_LOG" || return 1
  done
  return 0
}

# --- INSTRUMENT SELF-TEST ------------------------------------------------------------------------------------------
# check() and no_leak() own every verdict below. A helper that passes whatever the wrapper did would leave every row
# green, so each is driven in both directions here and must move the counters by exactly one pass and one fail.
_p0=$passes; _f0=$fails
{
  RC=0; OUT="x"; check "self-test" 0; check "self-test" 1
  OUT="leak SYNTHself123"; : > "$MOCK_LOG"; : > "$FAKE_LOG"
  no_leak SYNTHself123 && ok "self-test" || no "self-test"
  OUT="clean"; no_leak SYNTHself123 && ok "self-test" || no "self-test"
} >/dev/null 2>&1
if [[ "$passes" -ne $((_p0 + 2)) || "$fails" -ne $((_f0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: check/no_leak did not move the counters by +2 passes/+2 fails (passes %s->%s, fails %s->%s)\n' "$_p0" "$passes" "$_f0" "$fails" >&2
  exit 2
fi
passes=$_p0; fails=$_f0

# log_has / log_lacks / log_lacks_re / no_leak's two log reads own the "absent" and "present" verdicts of most rows below,
# and the block above drives only check() and no_leak()'s OUT branch. Each is driven here with a case that MUST fail
# (plus its positive twin) and reports through printf + exit, never through the helpers it checks. An UNREADABLE log is
# one of the must-fail cases: grep rc 2 says nothing about absence.
_st="$SCR/selftest.log"; _st_bad=""
printf 'alpha\nCALLED --live\n' > "$_st"
log_has "CALLED --live" "$_st"        || _st_bad+=" log_has(present)"
log_has "NOPE" "$_st"                 && _st_bad+=" log_has(absent)-must-fail"
log_has "CALLED" "$_st"               && _st_bad+=" log_has(substring)-must-fail"
log_lacks "NOPE" "$_st"               || _st_bad+=" log_lacks(absent)"
log_lacks "alpha" "$_st"              && _st_bad+=" log_lacks(present)-must-fail"
log_lacks "alpha" "$SCR/no-such.log"  && _st_bad+=" log_lacks(unreadable)-must-fail"
log_lacks_re '^ZZ' "$_st"             || _st_bad+=" log_lacks_re(absent)"
log_lacks_re '^CALLED' "$_st"         && _st_bad+=" log_lacks_re(present)-must-fail"
log_lacks_re '^ZZ' "$SCR/no-such.log" && _st_bad+=" log_lacks_re(unreadable)-must-fail"
OUT="clean"; : > "$MOCK_LOG"; : > "$FAKE_LOG"
no_leak SYNTHself123                  || _st_bad+=" no_leak(clean)"
printf 'x SYNTHself123 y\n' > "$MOCK_LOG"
no_leak SYNTHself123                  && _st_bad+=" no_leak(stub-argv-log)-must-fail"
: > "$MOCK_LOG"; printf 'SYNTHself123\n' > "$FAKE_LOG"
no_leak SYNTHself123                  && _st_bad+=" no_leak(checker-log)-must-fail"
: > "$FAKE_LOG"; rm -f "$MOCK_LOG"
no_leak SYNTHself123                  && _st_bad+=" no_leak(unreadable-stub-log)-must-fail"
: > "$MOCK_LOG"; rm -f "$FAKE_LOG"
no_leak SYNTHself123                  && _st_bad+=" no_leak(unreadable-checker-log)-must-fail"
: > "$FAKE_LOG"; OUT="::add-mask::SYNTHself123"
no_leak SYNTHself123                  || _st_bad+=" no_leak(mask-directive-exception)"
if [[ -n "$_st_bad" ]]; then
  printf '[FATAL] instrument self-test: log helper(s) gave the wrong verdict:%s\n' "$_st_bad" >&2
  exit 2
fi

# --- P0: the harness itself can see a checker call (a positive control for every "checker was never called" row) ----
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_EXPECT_TOK="$ENVTOK"
if [[ "$(checker_calls)" == 1 ]]; then rc=0; else rc=1; fi
check "P0 positive control: a normal run reaches the checker exactly once, so a zero count below means 'blocked'" "$rc"

# --- W1: the environment token wins -----------------------------------------------------------------------------------
if [[ "$RC" -eq 0 ]]; then rc=0; else rc=1; fi
check "W1a env token present -> rc 0 from the checker" "$rc"
if log_has "CALLED --live" "$FAKE_LOG" && log_has TOKEN_MATCH "$FAKE_LOG"; then rc=0; else rc=1; fi
check "W1b the checker runs in --live mode and is handed the ENV provider token (not the step token)" "$rc"
if log_lacks_re '^ARGV' "$MOCK_LOG"; then rc=0; else rc=1; fi
check "W1c env token wins: no Doppler call at all, so no fallback read" "$rc"
if no_leak "$ENVTOK" "$STEPTOK"; then rc=0; else rc=1; fi
check "W1d no token byte in the output, the Doppler argv log or the checker log (env path)" "$rc"

# env token wins even when a different value is readable through the fallback
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK" FAKE_EXPECT_TOK="$ENVTOK"
if { log_has TOKEN_MATCH "$FAKE_LOG" && log_lacks_re '^ARGV' "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "W1e a readable fallback value never overrides the environment token" "$rc"

# --- W2: the fallback reads exactly one named secret --------------------------------------------------------------------
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK" FAKE_EXPECT_TOK="$FALLTOK"
if { [[ "$RC" -eq 0 ]] && log_has TOKEN_MATCH "$FAKE_LOG"; }; then rc=0; else rc=1; fi
check "W2a no env token -> the fallback value is handed to the checker" "$rc"
if [[ "$(grep -c '^ARGV' "$MOCK_LOG")" == 1 ]] && grep -q '^ARGV secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain' "$MOCK_LOG"; then rc=0; else rc=1; fi
check "W2b exactly ONE Doppler call: 'secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain'" "$rc"
if { log_lacks_re '^ARGV (run|secrets download|secrets --only-names)' "$MOCK_LOG" && log_has "AUTH step" "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "W2c the fallback authenticates with the step token and never uses run/download (the checker does not inherit prd_terraform)" "$rc"
if log_has "::add-mask::${FALLTOK}" <(printf '%s\n' "$OUT"); then rc=0; else rc=1; fi
check "W2d the fallback value is registered with ::add-mask:: before the checker runs" "$rc"
if [[ "$(printf '%s\n' "$OUT" | grep -cxF -- "::add-mask::${FALLTOK}")" == 1 ]]; then rc=0; else rc=1; fi
check "W2e the mask directive is emitted exactly once" "$rc"
if no_leak "$FALLTOK" "$STEPTOK"; then rc=0; else rc=1; fi
check "W2f no token byte anywhere except the mask directive (fallback path)" "$rc"
if [[ "$(printf '%s\n' "$OUT" | grep -n 'add-mask' | head -1 | cut -d: -f1)" == 1 ]]; then rc=0; else rc=1; fi
check "W2g the mask directive precedes any other output" "$rc"

# --- W3: the fallback value is shape-checked (a plantable prd_terraform value cannot carry directives) -----------------
shape_row() { # <label> <value>
  reset_logs
  run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$2" FAKE_EXPECT_TOK="$2"
  if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]] && [[ "$OUT" != *"::set-env"* && "$OUT" != *"::add-mask::"* && "$OUT" != *PWN* ]]; }; then rc=0; else rc=1; fi
  check "$1" "$rc"
}
shape_row "W3a a wrong-kind token (dp.st.*) fails before the checker, with no mask or directive emitted" "dp.st.SYNTHwrongKIND0004dddd"
shape_row "W3b a value with an embedded newline and a workflow directive fails before the checker, no directive reaches the log" $'dp.pt.SYNTHnl0005eeee\n::set-env name=PWN::1'
shape_row "W3c a value with trailing junk fails before the checker" "dp.pt.SYNTHtrail0006ffff;touch"
shape_row "W3d a bare 'dp.pt.' (no body) fails before the checker" "dp.pt."
# The FRONT anchor: every row above puts the junk AFTER a valid-looking token. An unanchored front would accept a value whose
# LAST line is a valid token, and the mask directive would then print the directive line riding in front of it.
shape_row "W3f a workflow directive on a line BEFORE the token (leading junk line) fails before the checker" $'x\n::set-env name=PWN::1\ndp.pt.abc123'
shape_row "W3g the directive is the first line and the token the last line -> fails before the checker" $'::set-env name=PWN::1\ndp.pt.abc123'
shape_row "W3h leading junk on the SAME line as the token ('junk dp.pt.abc123') fails before the checker" "junk dp.pt.abc123"
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL=$'dp.pt.SYNTHnl0005eeee\n::set-env name=PWN::1' FAKE_EXPECT_TOK=x
if { [[ "$RC" -ne 0 ]] && [[ "$OUT" != *SYNTHnl0005eeee* && "$OUT" != *PWN* ]]; }; then rc=0; else rc=1; fi
check "W3e a rejected value (and the directive riding it) is never echoed" "$rc"

# --- W4: an empty token fails BEFORE the checker -------------------------------------------------------------------------
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL=""
if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; then rc=0; else rc=1; fi
check "W4a no env token and an EMPTY fallback read -> non-zero, the checker never called" "$rc"
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1
if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; then rc=0; else rc=1; fi
check "W4b the fallback read FAILS (vendor error) -> non-zero, the checker never called" "$rc"
reset_logs
run "$WRAP_FAKE"
if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]] && log_lacks_re '^ARGV' "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "W4c neither TF_VAR_doppler_token_tf nor DOPPLER_TOKEN set -> non-zero, no Doppler call (no ambient login), checker never called" "$rc"
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="" DOPPLER_TOKEN=""
if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; then rc=0; else rc=1; fi
check "W4d both set but EMPTY -> non-zero, checker never called" "$rc"

# A failing read that ALSO prints a token-shaped value on stdout (a CLI that reports an error after writing the value) must
# still fail: dropping the rc test would let the shape check and the mask directive accept it.
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1 MOCK_GET_FAIL_OUT="$FALLTOK" FAKE_EXPECT_TOK="$FALLTOK"
if { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]] && [[ "$OUT" != *"::add-mask::"* ]]; }; then rc=0; else rc=1; fi
check "W4e the fallback read exits non-zero but printed a valid-shaped token on stdout -> non-zero, no mask, the checker never called (the rc guard, not the shape check, refuses it)" "$rc"
no_leak "$FALLTOK" "$STEPTOK"
rc=$?
check "W4e2 that stdout value is never echoed" "$rc"

# The stderr of the failed read is scrubbed and kept, so an auth failure is distinguishable from a missing secret, and no value
# or directive rides along.
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1 MOCK_GET_FAIL_ERR="Invalid Auth token"
if { [[ "$RC" -eq 1 ]] && grep -qxF -- "::error::escrow preflight: could not read DOPPLER_TOKEN_TF from prd_terraform (rc=1, or empty). An unreadable token is not a passed check. Birth aborted before any change. Doppler said: Unable to fetch secret Doppler Error: vendor outage Invalid Auth token " <<<"$OUT"; }; then rc=0; else rc=1; fi
check "W4f the failed read's stderr reaches the annotation (flattened to one line), so an auth failure is distinguishable from a missing secret" "$rc"
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1 MOCK_GET_FAIL_ERR="echoed $STEPTOK and $FALLTOK end"
if { [[ "$OUT" == *"vendor outage"* && "$OUT" == *"dp.REDACTED"* ]] && no_leak "$STEPTOK" "$FALLTOK"; }; then rc=0; else rc=1; fi
check "W4g every dp.<kind>.<body> shape in the failed read's stderr is redacted (the reason text survives)" "$rc"
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1 MOCK_GET_FAIL_OUT="SYNTHrawSECRET0099xyz" MOCK_GET_FAIL_ERR="echoed SYNTHrawSECRET0099xyz end"
if { [[ "$RC" -ne 0 ]] && [[ "$OUT" == *"vendor outage"* && "$OUT" != *SYNTHrawSECRET0099* ]]; }; then rc=0; else rc=1; fi
check "W4h the literal value read on stdout is redacted from the stderr tail even when it has no dp.* shape" "$rc"
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1 MOCK_GET_FAIL_ERR=$'x\n::set-env name=PWN::1'
if { [[ "$RC" -ne 0 ]] && [[ "$OUT" != *$'\n'"::set-env"* && "$OUT" == *"vendor outage"* ]]; }; then rc=0; else rc=1; fi
check "W4i a newline and a workflow directive in the failed read's stderr are flattened into the one annotation line (no line starts with a directive)" "$rc"

# --- W5: the checker's exit code is the step's exit code (fail closed on 1, 2 and 3) ----------------------------------------
for want in 1 2 3; do
  reset_logs
  run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC="$want" FAKE_NOISE="escrow-split-contract:FAIL stub"
  if { [[ "$RC" -eq "$want" ]] && [[ "$OUT" == *"escrow-split-contract:FAIL stub"* ]] && [[ "$OUT" == *"::error::"* ]]; }; then rc=0; else rc=1; fi
  check "W5.$want checker rc=$want -> the step exits $want, the checker's lines survive, and an ::error:: annotation names the abort" "$rc"
done

# --- W5b: the red run's annotations carry the cause (an annotation-only reader never opens the step log) -----------------------
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC=1 FAKE_NOISE=$'escrow-split-contract:FAIL missing in prd_workspaces_luks_web: X\nescrow-split-contract:CAUSE a cause sentence (unmeasured)\nescrow-split-contract:NOTE a note\nescrow-split-contract:unreadable: config prd (rc=1): bar\nadvisory: 3 names\nan unrelated line'
ANN="$(printf '%s\n' "$OUT" | grep '^::error::' || true)"
if { [[ "$RC" -eq 1 ]] && grep -qxF -- "::error::escrow-split-contract:FAIL missing in prd_workspaces_luks_web: X" <<<"$ANN" && grep -qxF -- "::error::escrow-split-contract:CAUSE a cause sentence (unmeasured)" <<<"$ANN" \
     && grep -qxF -- "::error::escrow-split-contract:NOTE a note" <<<"$ANN" && grep -qxF -- "::error::escrow-split-contract:unreadable: config prd (rc=1): bar" <<<"$ANN"; }; then rc=0; else rc=1; fi
check "W5b a red run re-emits every FAIL/CAUSE/NOTE/unreadable line as its own ::error:: annotation" "$rc"
if { [[ "$ANN" != *"advisory"* && "$ANN" != *"unrelated"* ]]; }; then rc=0; else rc=1; fi
check "W5c only the cause families are re-emitted as annotations (an advisory or unrelated line is not)" "$rc"
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC=1 FAKE_NOISE=$'escrow-split-contract:CAUSE 1\nescrow-split-contract:CAUSE 2\nescrow-split-contract:CAUSE 3\nescrow-split-contract:CAUSE 4\nescrow-split-contract:CAUSE 5\nescrow-split-contract:CAUSE 6\nescrow-split-contract:CAUSE 7\nescrow-split-contract:CAUSE 8'
if [[ "$(printf '%s\n' "$OUT" | grep -c '^::error::escrow-split-contract:CAUSE')" == 6 ]]; then rc=0; else rc=1; fi
check "W5d the cause annotations are capped at six (GitHub shows ten per step; the final abort line must fit)" "$rc"
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC=1 FAKE_NOISE=$'escrow-split-contract:CAUSE a\rb\tc'
if grep -qxF -- "::error::escrow-split-contract:CAUSE a b c" <<<"$OUT"; then rc=0; else rc=1; fi
check "W5f a control character (CR, tab) in a cause line is flattened to a space inside its annotation" "$rc"
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC=0
if { [[ "$RC" -eq 0 ]] && [[ "$OUT" != *"::error::"* ]] && log_has "ADVISORY=count" "$FAKE_LOG"; }; then rc=0; else rc=1; fi
check "W5e a green run emits no ::error:: annotation, and the checker was run in ESCROW_ADVISORY=count mode" "$rc"

# --- W6: xtrace is refused FIRST, before any read -----------------------------------------------------------------------------
reset_logs
RUN_BASHFLAGS="-x" run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK"
if { [[ "$RC" -eq 78 ]] && [[ "$(checker_calls)" == 0 ]] && log_lacks_re '^ARGV' "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "W6a bash -x -> rc 78, no Doppler call, checker never called" "$rc"
if no_leak "$ENVTOK" "$STEPTOK" "$FALLTOK"; then rc=0; else rc=1; fi
check "W6b the refused trace leaks no token (the refusal precedes every bind)" "$rc"
reset_logs
run "$WRAP_FAKE" SHELLOPTS=xtrace TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
if { [[ "$RC" -eq 78 ]] && [[ "$(checker_calls)" == 0 ]]; }; then rc=0; else rc=1; fi
check "W6c SHELLOPTS=xtrace (no -x token on argv) is refused too" "$rc"
reset_logs
RUN_BASHFLAGS="-x" run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK"
if { [[ "$RC" -eq 78 ]] && log_lacks_re '^ARGV' "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "W6d the refusal holds on the fallback path, where the token is bound by the read (the case that leaks)" "$rc"

# --- W7: source-level pins (cheap structural claims the rows above exercise behaviourally) ---------------------------------------
src_code() { grep -vE '^[[:space:]]*#' "$SUT"; }
if { ! src_code | grep -qE 'doppler[[:space:]]+run|GITHUB_ENV|set[[:space:]]+-[A-Za-z]*x|\|\|[[:space:]]*true'; }; then rc=0; else rc=1; fi
check "W7a the wrapper never runs 'doppler run', writes GITHUB_ENV, enables xtrace, or swallows an error with '|| true'" "$rc"
if [[ "$(src_code | grep -c 'secrets get')" == 1 ]]; then rc=0; else rc=1; fi
check "W7b exactly one Doppler read in the wrapper" "$rc"
first_stmt="$(src_code | grep -vE '^[[:space:]]*(set[[:space:]]|shopt[[:space:]]|$)' | head -1)"
if [[ "$first_stmt" == *'case "$-" in'* ]]; then rc=0; else rc=1; fi
check "W7c the first statement after set/shopt is the xtrace refusal (it precedes every credential bind)" "$rc"

# --- E2E: the REAL checker behind the stub (the stub grants a listing only to the provider token) -----------------------------
REAL_WRAP="$SUT"   # in place, so it resolves the real checker beside it
reset_logs
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
if { [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"escrow-split-contract:live-ok"* ]]; }; then rc=0; else rc=1; fi
check "E1 real checker, complete web config, env token -> live-ok (rc 0)" "$rc"
if { grep -c '^AUTH provider' "$MOCK_LOG" | grep -qx 2 && log_lacks_re '^AUTH step' "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "E1b both names-only reads authenticate with the PROVIDER token, never the step's prd_terraform token" "$rc"
if no_leak "$ENVTOK" "$STEPTOK"; then rc=0; else rc=1; fi
check "E1c the real checker child never echoes its environment (no token byte in output or logs)" "$rc"
reset_logs
run "$REAL_WRAP" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$ENVTOK"
if { [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"escrow-split-contract:live-ok"* ]] && log_has "AUTH step" "$MOCK_LOG"; }; then rc=0; else rc=1; fi
check "E2 real checker through the single fallback read -> live-ok" "$rc"
if no_leak "$ENVTOK" "$STEPTOK"; then rc=0; else rc=1; fi
check "E2b no token byte beyond the mask directive (real checker, fallback path)" "$rc"
reset_logs
grep -vx WORKSPACES_HEADER_R2_ACCESS_KEY_ID "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
if { [[ "$RC" -eq 1 ]] && [[ "$OUT" == *"missing in prd_workspaces_luks_web: WORKSPACES_HEADER_R2_ACCESS_KEY_ID"* ]]; }; then rc=0; else rc=1; fi
check "E3 a missing R2 pair name -> the step exits 1 naming it (the birth never starts)" "$rc"
reset_logs
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$STEPTOK" DOPPLER_TOKEN="$STEPTOK"
if { [[ "$RC" -eq 3 ]] && [[ "$OUT" == *"unreadable"* ]]; }; then rc=0; else rc=1; fi
check "E4 a token that cannot list both configs (the step token handed over as provider) -> exit 3 'unreadable', never read as absence" "$rc"
if no_leak "$STEPTOK"; then rc=0; else rc=1; fi
check "E4b the unreadable path leaks no token byte" "$rc"

# The advisory scan lists prd-root secret NAMES; the repo is public and this step runs on every birth, so the job log carries a
# count only (the stub's prd root holds DOPPLER_PROJECT, DOPPLER_CONFIG and CF_API_TOKEN, all of which match the scan).
reset_logs
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
if { [[ "$RC" -eq 0 ]] && grep -qE '^advisory: 3 prd-root name\(s\) are reachable' <<<"$OUT" && [[ "$OUT" != *CF_API_TOKEN* && "$OUT" != *DOPPLER_PROJECT* && "$OUT" != *DOPPLER_CONFIG* ]]; }; then rc=0; else rc=1; fi
check "E5 the real checker through the wrapper prints a COUNT of the advisory names, never the names" "$rc"
# The aborted-before-the-push-apply state: the web-class config does not exist yet. The annotations must say what that is
# consistent with, as a hedged and unmeasured statement, and the failure stays exit 3 (a failed read is not absence).
reset_logs
rm -f "$MOCK/prd_workspaces_luks_web.names"
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
ANN="$(printf '%s\n' "$OUT" | grep '^::error::' || true)"
if { [[ "$RC" -eq 3 ]] && [[ "$ANN" == *"escrow-split-contract:unreadable: config prd_workspaces_luks_web"* ]] && [[ "$ANN" == *"escrow-split-contract:NOTE prd_workspaces_luks_web was not found; this is usually consistent with the web-platform push-apply"* && "$ANN" == *"(unmeasured"* ]]; }; then rc=0; else rc=1; fi
check "E6 an absent web-class config (exit 3) annotates 'usually consistent with the push-apply not having created it (unmeasured)' next to the unreadable line" "$rc"
reset_logs
grep -vx WORKSPACES_HEADER_R2_ACCESS_KEY_ID "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
ANN="$(printf '%s\n' "$OUT" | grep '^::error::' || true)"
if { [[ "$RC" -eq 1 ]] && [[ "$ANN" == *"::error::escrow-split-contract:FAIL missing in prd_workspaces_luks_web: WORKSPACES_HEADER_R2_ACCESS_KEY_ID"* ]] && [[ "$ANN" == *"::error::escrow-split-contract:CAUSE a missing WORKSPACES_HEADER_R2_ACCESS_KEY_ID or WORKSPACES_HEADER_R2_SECRET_ACCESS_KEY is consistent with the live R2 credential mint"* ]]; }; then rc=0; else rc=1; fi
check "E7 a missing R2 pair name annotates both the FAIL line and the (hedged) mint CAUSE line" "$rc"

# --- Anti-vacuity: an exact assertion count ------------------------------------------------------------------------------------
EXPECTED_PASSES=57
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then no "count: ${passes} assertions passed, expected exactly ${EXPECTED_PASSES} — a block of rows was deleted or added without moving the number"; fi

echo ""
echo "=== web-host-escrow-preflight.test.sh: ${passes} passed, ${fails} failed ==="
[[ "$fails" -eq 0 ]]
