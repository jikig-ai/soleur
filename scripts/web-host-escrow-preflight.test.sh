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
  if [[ -n "${MOCK_GET_FAIL:-}" ]]; then printf 'Unable to fetch secret\nDoppler Error: vendor outage\n' >&2; exit 1; fi
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
log_lacks() { ! grep -qF -- "$1" "$2"; }
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

# --- P0: the harness itself can see a checker call (a positive control for every "checker was never called" row) ----
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_EXPECT_TOK="$ENVTOK"
[[ "$(checker_calls)" == 1 ]]; check "P0 positive control: a normal run reaches the checker exactly once, so a zero count below means 'blocked'" $?

# --- W1: the environment token wins -----------------------------------------------------------------------------------
[[ "$RC" -eq 0 ]]; check "W1a env token present -> rc 0 from the checker" $?
log_has "CALLED --live" "$FAKE_LOG" && log_has TOKEN_MATCH "$FAKE_LOG"; check "W1b the checker runs in --live mode and is handed the ENV provider token (not the step token)" $?
! grep -q '^ARGV' "$MOCK_LOG"; check "W1c env token wins: no Doppler call at all, so no fallback read" $?
no_leak "$ENVTOK" "$STEPTOK"; check "W1d no token byte in the output, the Doppler argv log or the checker log (env path)" $?

# env token wins even when a different value is readable through the fallback
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK" FAKE_EXPECT_TOK="$ENVTOK"
{ log_has TOKEN_MATCH "$FAKE_LOG" && ! grep -q '^ARGV' "$MOCK_LOG"; }; check "W1e a readable fallback value never overrides the environment token" $?

# --- W2: the fallback reads exactly one named secret --------------------------------------------------------------------
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK" FAKE_EXPECT_TOK="$FALLTOK"
{ [[ "$RC" -eq 0 ]] && log_has TOKEN_MATCH "$FAKE_LOG"; }; check "W2a no env token -> the fallback value is handed to the checker" $?
[[ "$(grep -c '^ARGV' "$MOCK_LOG")" == 1 ]] && grep -q '^ARGV secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain' "$MOCK_LOG"; check "W2b exactly ONE Doppler call: 'secrets get DOPPLER_TOKEN_TF -p soleur -c prd_terraform --plain'" $?
{ ! grep -qE '^ARGV (run|secrets download|secrets --only-names)' "$MOCK_LOG" && log_has "AUTH step" "$MOCK_LOG"; }; check "W2c the fallback authenticates with the step token and never uses run/download (the checker does not inherit prd_terraform)" $?
log_has "::add-mask::${FALLTOK}" <(printf '%s\n' "$OUT"); check "W2d the fallback value is registered with ::add-mask:: before the checker runs" $?
[[ "$(printf '%s\n' "$OUT" | grep -cxF -- "::add-mask::${FALLTOK}")" == 1 ]]; check "W2e the mask directive is emitted exactly once" $?
no_leak "$FALLTOK" "$STEPTOK"; check "W2f no token byte anywhere except the mask directive (fallback path)" $?
[[ "$(printf '%s\n' "$OUT" | grep -n 'add-mask' | head -1 | cut -d: -f1)" == 1 ]]; check "W2g the mask directive precedes any other output" $?

# --- W3: the fallback value is shape-checked (a plantable prd_terraform value cannot carry directives) -----------------
shape_row() { # <label> <value>
  reset_logs
  run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$2" FAKE_EXPECT_TOK="$2"
  { [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]] && [[ "$OUT" != *"::set-env"* && "$OUT" != *"::add-mask::"* ]]; }; check "$1" $?
}
shape_row "W3a a wrong-kind token (dp.st.*) fails before the checker, with no mask or directive emitted" "dp.st.SYNTHwrongKIND0004dddd"
shape_row "W3b a value with an embedded newline and a workflow directive fails before the checker, no directive reaches the log" $'dp.pt.SYNTHnl0005eeee\n::set-env name=PWN::1'
shape_row "W3c a value with trailing junk fails before the checker" "dp.pt.SYNTHtrail0006ffff;touch"
shape_row "W3d a bare 'dp.pt.' (no body) fails before the checker" "dp.pt."
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL=$'dp.pt.SYNTHnl0005eeee\n::set-env name=PWN::1' FAKE_EXPECT_TOK=x
{ [[ "$RC" -ne 0 ]] && [[ "$OUT" != *SYNTHnl0005eeee* && "$OUT" != *PWN* ]]; }; check "W3e a rejected value (and the directive riding it) is never echoed" $?

# --- W4: an empty token fails BEFORE the checker -------------------------------------------------------------------------
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL=""
{ [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; check "W4a no env token and an EMPTY fallback read -> non-zero, the checker never called" $?
reset_logs
run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_GET_FAIL=1
{ [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; check "W4b the fallback read FAILS (vendor error) -> non-zero, the checker never called" $?
reset_logs
run "$WRAP_FAKE"
{ [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]] && ! grep -q '^ARGV' "$MOCK_LOG"; }; check "W4c neither TF_VAR_doppler_token_tf nor DOPPLER_TOKEN set -> non-zero, no Doppler call (no ambient login), checker never called" $?
reset_logs
run "$WRAP_FAKE" TF_VAR_doppler_token_tf="" DOPPLER_TOKEN=""
{ [[ "$RC" -ne 0 ]] && [[ "$(checker_calls)" == 0 ]]; }; check "W4d both set but EMPTY -> non-zero, checker never called" $?

# --- W5: the checker's exit code is the step's exit code (fail closed on 1, 2 and 3) ----------------------------------------
for rc in 1 2 3; do
  reset_logs
  run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" FAKE_RC="$rc" FAKE_NOISE="escrow-split-contract:FAIL stub"
  { [[ "$RC" -eq "$rc" ]] && [[ "$OUT" == *"escrow-split-contract:FAIL stub"* ]] && [[ "$OUT" == *"::error::"* ]]; }; check "W5.$rc checker rc=$rc -> the step exits $rc, the checker's lines survive, and an ::error:: annotation names the abort" $?
done

# --- W6: xtrace is refused FIRST, before any read -----------------------------------------------------------------------------
reset_logs
RUN_BASHFLAGS="-x" run "$WRAP_FAKE" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK"
{ [[ "$RC" -eq 78 ]] && [[ "$(checker_calls)" == 0 ]] && ! grep -q '^ARGV' "$MOCK_LOG"; }; check "W6a bash -x -> rc 78, no Doppler call, checker never called" $?
no_leak "$ENVTOK" "$STEPTOK" "$FALLTOK"; check "W6b the refused trace leaks no token (the refusal precedes every bind)" $?
reset_logs
run "$WRAP_FAKE" SHELLOPTS=xtrace TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
{ [[ "$RC" -eq 78 ]] && [[ "$(checker_calls)" == 0 ]]; }; check "W6c SHELLOPTS=xtrace (no -x token on argv) is refused too" $?
reset_logs
RUN_BASHFLAGS="-x" run "$WRAP_FAKE" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$FALLTOK"
{ [[ "$RC" -eq 78 ]] && ! grep -q '^ARGV' "$MOCK_LOG"; }; check "W6d the refusal holds on the fallback path, where the token is bound by the read (the case that leaks)" $?

# --- W7: source-level pins (cheap structural claims the rows above exercise behaviourally) ---------------------------------------
src_code() { grep -vE '^[[:space:]]*#' "$SUT"; }
{ ! src_code | grep -qE 'doppler[[:space:]]+run|GITHUB_ENV|set[[:space:]]+-[A-Za-z]*x|\|\|[[:space:]]*true'; }; check "W7a the wrapper never runs 'doppler run', writes GITHUB_ENV, enables xtrace, or swallows an error with '|| true'" $?
[[ "$(src_code | grep -c 'secrets get')" == 1 ]]; check "W7b exactly one Doppler read in the wrapper" $?
first_stmt="$(src_code | grep -vE '^[[:space:]]*(set[[:space:]]|shopt[[:space:]]|$)' | head -1)"
[[ "$first_stmt" == *'case "$-" in'* ]]; check "W7c the first statement after set/shopt is the xtrace refusal (it precedes every credential bind)" $?

# --- E2E: the REAL checker behind the stub (the stub grants a listing only to the provider token) -----------------------------
REAL_WRAP="$SUT"   # in place, so it resolves the real checker beside it
reset_logs
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
{ [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"escrow-split-contract:live-ok"* ]]; }; check "E1 real checker, complete web config, env token -> live-ok (rc 0)" $?
{ grep -c '^AUTH provider' "$MOCK_LOG" | grep -qx 2 && ! grep -q '^AUTH step' "$MOCK_LOG"; }; check "E1b both names-only reads authenticate with the PROVIDER token, never the step's prd_terraform token" $?
no_leak "$ENVTOK" "$STEPTOK"; check "E1c the real checker child never echoes its environment (no token byte in output or logs)" $?
reset_logs
run "$REAL_WRAP" DOPPLER_TOKEN="$STEPTOK" MOCK_TFVAL="$ENVTOK"
{ [[ "$RC" -eq 0 ]] && [[ "$OUT" == *"escrow-split-contract:live-ok"* ]] && log_has "AUTH step" "$MOCK_LOG"; }; check "E2 real checker through the single fallback read -> live-ok" $?
no_leak "$ENVTOK" "$STEPTOK"; check "E2b no token byte beyond the mask directive (real checker, fallback path)" $?
reset_logs
grep -vx WORKSPACES_HEADER_R2_ACCESS_KEY_ID "$MOCK/prd_workspaces_luks_web.names" > "$MOCK/w.tmp"; mv "$MOCK/w.tmp" "$MOCK/prd_workspaces_luks_web.names"
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$ENVTOK" DOPPLER_TOKEN="$STEPTOK"
{ [[ "$RC" -eq 1 ]] && [[ "$OUT" == *"missing in prd_workspaces_luks_web: WORKSPACES_HEADER_R2_ACCESS_KEY_ID"* ]]; }; check "E3 a missing R2 pair name -> the step exits 1 naming it (the birth never starts)" $?
reset_logs
run "$REAL_WRAP" TF_VAR_doppler_token_tf="$STEPTOK" DOPPLER_TOKEN="$STEPTOK"
{ [[ "$RC" -eq 3 ]] && [[ "$OUT" == *"unreadable"* ]]; }; check "E4 a token that cannot list both configs (the step token handed over as provider) -> exit 3 'unreadable', never read as absence" $?
no_leak "$STEPTOK"; check "E4b the unreadable path leaks no token byte" $?

# --- Anti-vacuity: an exact assertion count ------------------------------------------------------------------------------------
EXPECTED_PASSES=40
if [[ "$passes" -ne "$EXPECTED_PASSES" ]]; then no "count: ${passes} assertions passed, expected exactly ${EXPECTED_PASSES} — a block of rows was deleted or added without moving the number"; fi

echo ""
echo "=== web-host-escrow-preflight.test.sh: ${passes} passed, ${fails} failed ==="
[[ "$fails" -eq 0 ]]
