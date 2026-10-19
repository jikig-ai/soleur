#!/usr/bin/env bash
# Behavioural rows for sdk-bash-smoke-verdict-10548.sh (the #10548 promotion-soak follow-through) with `curl` stubbed on PATH
# (no network, no credentials). The properties:
#   * exit 0 ONLY when the latest verdict is `pass`, coverage is sdk_wrapper_shim_prodtuple, consecutive_pass >= 5 and the span
#     since first_pass_at is >= 3 days (a replay_only/absent coverage, an infra error, 4 greens or 2 days each read TRANSIENT);
#   * exit 1 ONLY for a recorded sdk_bash_smoke_failed;
#   * EVERY path prints one stdout line starting `sdk_bash_smoke` (the discoverability probe's contract), with remote values
#     reduced so a forged verdict cannot inject a second line or a workflow command;
#   * the three credentials ride curl's stdin as exactly three header lines; a hostile Cloudflare Access value is refused before
#     any request; no credential value is echoed.
# SUT override (RED proof before the script existed): SBS_VERDICT_SUT=/path bash this-file.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SBS_VERDICT_SUT:-$HERE/sdk-bash-smoke-verdict-10548.sh}"

# P1b (#7708) — byte-identical to every other tracked copy; the P1a suite pins that.
# `$(cd X && pwd)` prints an absolute path but yields EMPTY when the cd fails, which would root
# the fixture at `/` and point every rm below at the wrong tree.
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

ROOT_TMP="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
assert_fixture_dir "$ROOT_TMP"
trap 'rm -rf "$ROOT_TMP"' EXIT
STUBS="$ROOT_TMP/bin"
mkdir -p "$STUBS"
FAILURES=()
PASSES=0
FAIL_N=0

# curl stub: records the config the SUT feeds on stdin (CURL_STDIN_LOG) and the call count (CURL_CALLS_LOG), then prints
# $STUB_BODY and the HTTP_STATUS trailer the SUT parses.
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
cat >"${CURL_STDIN_LOG:-/dev/null}" 2>/dev/null || true
[[ -z "${CURL_CALLS_LOG:-}" ]] || echo call >>"$CURL_CALLS_LOG"
printf '%s\nHTTP_STATUS:%s' "${STUB_BODY:-}" "${STUB_HTTP:-200}"
STUB
chmod +x "$STUBS/curl"

WH_SECRET="whsec-synth-0123456789"
CF_ID="cfid-synth-abc"
CF_SECRET="cfsec-synth-xyz"
FIRST=1000000
DAY=86400

LAST_OUT=""; LAST_ERR=""; LAST_RC=""
run() { # <expected rc> <expected status word or ""> <label> <body> [http] [env-unset-var]
  local want="$1" status="$2" label="$3" body="$4" http="${5:-200}" unset_var="${6:-}" rc first_line
  LAST_OUT="$(env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET="$WH_SECRET" CF_ACCESS_CLIENT_ID="$CF_ID" CF_ACCESS_CLIENT_SECRET="$CF_SECRET" \
    STUB_BODY="$body" STUB_HTTP="$http" env ${unset_var:+-u "$unset_var"} bash "$SUT" 2>"$ROOT_TMP/err.txt")"
  rc=$?
  LAST_RC="$rc"; LAST_ERR="$(cat "$ROOT_TMP/err.txt")"
  first_line="$(printf '%s\n' "$LAST_OUT" | head -n 1)"
  if [[ "$rc" != "$want" ]]; then
    FAIL_N=$((FAIL_N + 1)); FAILURES+=("$label: want rc=$want got rc=$rc: $LAST_OUT / $LAST_ERR"); echo "  FAIL: $label (want rc=$want got $rc)"; return
  fi
  # Every path prints exactly one stdout line starting `sdk_bash_smoke` (and, when the row names it, the status word).
  if [[ "$(printf '%s\n' "$LAST_OUT" | grep -c .)" != "1" || "$first_line" != sdk_bash_smoke\ * || ( -n "$status" && "$first_line" != "sdk_bash_smoke status=$status"* ) ]]; then
    FAIL_N=$((FAIL_N + 1)); FAILURES+=("$label: stdout is not ONE 'sdk_bash_smoke status=${status:-*}' line: $LAST_OUT"); echo "  FAIL: $label (stdout contract)"; return
  fi
  if grep -qF -e "$WH_SECRET" -e "$CF_SECRET" <<<"$LAST_OUT"$'\n'"$LAST_ERR"; then
    FAIL_N=$((FAIL_N + 1)); FAILURES+=("$label: a credential value was echoed"); echo "  FAIL: $label (credential echoed)"; return
  fi
  PASSES=$((PASSES + 1)); echo "  ok: $label (rc=$rc)"
}
body() { # <verdict> <consecutive_pass> <first_pass_at> <checked_at> <coverage> [reason]
  printf '{"tag":"v1.2.3","exit_code":0,"sdk_bash_smoke":{"verdict":"%s","reason":"%s","consecutive_pass":%s,"first_pass_at":%s,"checked_at":%s,"coverage":"%s","consecutive_infra_error":0}}' \
    "$1" "${6:-ok}" "$2" "$3" "$4" "$5"
}
FULL=sdk_wrapper_shim_prodtuple

run 0 PASS "5 greens over 4 days, latest pass, full coverage -> PASS" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")"
run 0 PASS "exactly 5 greens over exactly 3 days -> PASS (the boundary)" "$(body pass 5 "$FIRST" $((FIRST + 3 * DAY)) "$FULL")"
run 2 TRANSIENT "4 greens over 4 days -> TRANSIENT" "$(body pass 4 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")"
run 2 TRANSIENT "5 greens over 2d23h59m59s -> TRANSIENT (the span boundary)" "$(body pass 5 "$FIRST" $((FIRST + 3 * DAY - 1)) "$FULL")"
run 2 TRANSIENT "5 greens, replay_only coverage -> TRANSIENT (a replay-only pass never counts)" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) replay_only)"
run 2 TRANSIENT "5 greens, coverage field empty -> TRANSIENT" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "")"
run 2 TRANSIENT "5 greens over 4 days but the LATEST verdict is smoke_infra_error -> TRANSIENT (the held counter must not PASS)" "$(body smoke_infra_error 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL" probe_absent)"
run 2 TRANSIENT "first_pass_at 0 with 9 greens -> TRANSIENT" "$(body pass 9 0 $((FIRST + 4 * DAY)) "$FULL")"
run 1 FAIL "a recorded sdk_bash_smoke_failed -> FAIL" "$(body sdk_bash_smoke_failed 0 0 $((FIRST + 4 * DAY)) "$FULL" 'apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted')"
run 1 FAIL "sdk_bash_smoke_failed wins over a high held counter" "$(body sdk_bash_smoke_failed 7 "$FIRST" $((FIRST + 9 * DAY)) "$FULL")"
run 2 TRANSIENT "verdict unknown (no deploy has reached the smoke) -> TRANSIENT" "$(body unknown 0 0 0 "")"
run 2 TRANSIENT "deploy-status HTTP 502 -> TRANSIENT" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" 502
run 2 TRANSIENT "body without .sdk_bash_smoke (old host script) -> TRANSIENT" '{"tag":"v1.2.3","exit_code":0}'
run 2 TRANSIENT "non-JSON body -> TRANSIENT" 'not json at all'
run 2 TRANSIENT "non-numeric consecutive_pass -> TRANSIENT" '{"sdk_bash_smoke":{"verdict":"pass","consecutive_pass":"many","first_pass_at":1000000,"checked_at":2000000,"coverage":"sdk_wrapper_shim_prodtuple"}}'
run 2 TRANSIENT "WEBHOOK_DEPLOY_SECRET unset -> TRANSIENT, still one sdk_bash_smoke line" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" 200 WEBHOOK_DEPLOY_SECRET
run 2 TRANSIENT "CF_ACCESS_CLIENT_ID unset -> TRANSIENT" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" 200 CF_ACCESS_CLIENT_ID
run 2 TRANSIENT "CF_ACCESS_CLIENT_SECRET unset -> TRANSIENT" "$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" 200 CF_ACCESS_CLIENT_SECRET
# A forged remote value must not reach stdout with a newline or a workflow command.
run 2 TRANSIENT "forged verdict falls to TRANSIENT with the value reduced" '{"sdk_bash_smoke":{"verdict":"x\n::error::boom","consecutive_pass":0,"first_pass_at":0,"checked_at":5,"coverage":"c\n::warning::x"}}'
# `:` is in the safe charset (a verdict such as "a:b" is legal); newlines and a leading :: workflow command are not.
if grep -qE '^::' <<<"$LAST_OUT" || [[ "$(printf '%s\n' "$LAST_OUT" | grep -c .)" != "1" ]] || ! grep -q 'verdict=x::error::boom' <<<"$LAST_OUT"; then
  FAIL_N=$((FAIL_N + 1)); FAILURES+=("forged workflow command not neutralised: $LAST_OUT"); echo "  FAIL: forged verdict neutralisation"
else PASSES=$((PASSES + 1)); echo "  ok: forged verdict is one line with no leading :: (value reduced)"; fi

# xtrace refusal with a live credential: rc 78 (declined before any request).
xt_rc=$(PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET="$WH_SECRET" CF_ACCESS_CLIENT_ID="$CF_ID" CF_ACCESS_CLIENT_SECRET="$CF_SECRET" bash -x "$SUT" >/dev/null 2>&1; echo $?)
xt_n="$(PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET="$WH_SECRET" CF_ACCESS_CLIENT_ID="$CF_ID" CF_ACCESS_CLIENT_SECRET="$CF_SECRET" bash -x "$SUT" 2>&1 >/dev/null | grep -c 'refusing to trace' || true)"
if [[ "$xt_rc" == "78" && "$xt_n" -ge 1 ]]; then PASSES=$((PASSES + 1)); echo "  ok: xtrace with a live credential is refused (rc=78)"; else FAIL_N=$((FAIL_N + 1)); FAILURES+=("xtrace refusal: rc=$xt_rc refusals=$xt_n"); echo "  FAIL: xtrace refusal"; fi

# The credentials ride curl's stdin as three exact config lines, the signature is 64 lowercase hex, and the signature is HMAC-SHA256
# of the EMPTY body keyed by the webhook secret (the deploy-status GET contract).
curl_stdin_log="$ROOT_TMP/curl-stdin.log"
env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET="$WH_SECRET" CF_ACCESS_CLIENT_ID="$CF_ID" CF_ACCESS_CLIENT_SECRET="$CF_SECRET" \
  STUB_BODY="$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" CURL_STDIN_LOG="$curl_stdin_log" bash "$SUT" >/dev/null 2>&1
want_sig="$(printf '' | openssl dgst -sha256 -hmac "$WH_SECRET" 2>/dev/null | sed 's/^.* //')"
if grep -qxF "header = \"X-Signature-256: sha256=$want_sig\"" "$curl_stdin_log" && [[ ${#want_sig} -eq 64 ]] \
   && grep -qxF "header = \"CF-Access-Client-Id: $CF_ID\"" "$curl_stdin_log" \
   && grep -qxF "header = \"CF-Access-Client-Secret: $CF_SECRET\"" "$curl_stdin_log" && [[ "$(wc -l <"$curl_stdin_log")" -eq 3 ]]; then
  PASSES=$((PASSES + 1)); echo "  ok: curl stdin carries exactly the three header lines (the HMAC of the empty body, the id, the secret)"
else FAIL_N=$((FAIL_N + 1)); FAILURES+=("curl stdin does not carry exactly the three expected header lines"); echo "  FAIL: curl stdin header lines"; fi
# The GET targets the deploy-status URL only.
if grep -qF 'hooks/deploy-status' "$SUT" && ! grep -q 'curl.* -X POST' "$SUT"; then PASSES=$((PASSES + 1)); echo "  ok: the probe is a read-only GET of /hooks/deploy-status"; else FAIL_N=$((FAIL_N + 1)); FAILURES+=("probe is not a read-only GET"); echo "  FAIL: read-only GET"; fi

# A hostile Cloudflare Access value is refused before any request (one value-free marker, rc 2, zero curl calls).
curl_calls_log="$ROOT_TMP/curl-calls.log"
: >"$curl_calls_log"
hostile_out="$(env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET="$WH_SECRET" CF_ACCESS_CLIENT_ID="$CF_ID" CF_ACCESS_CLIENT_SECRET=$'se"c\nheader = "x' \
  STUB_BODY="$(body pass 5 "$FIRST" $((FIRST + 4 * DAY)) "$FULL")" CURL_CALLS_LOG="$curl_calls_log" bash "$SUT" 2>&1)"
hostile_rc=$?
if [[ "$hostile_rc" == "2" && ! -s "$curl_calls_log" && "$(grep -c 'SOLEUR_CREDENTIAL_REFUSED script=sdk-bash-smoke-verdict-10548' <<<"$hostile_out")" == "1" ]] \
   && ! grep -q 'se"c' <<<"$hostile_out" && [[ "$(grep -c '^sdk_bash_smoke ' <<<"$hostile_out")" == "1" ]]; then
  PASSES=$((PASSES + 1)); echo "  ok: a hostile Cloudflare Access secret is refused (rc=2, zero curl calls, one marker, value not echoed, one sdk_bash_smoke line)"
else FAIL_N=$((FAIL_N + 1)); FAILURES+=("hostile CF secret: rc=$hostile_rc calls=$(wc -l <"$curl_calls_log") out=$hostile_out"); echo "  FAIL: hostile CF secret"; fi

echo ""
echo "=== sdk-bash-smoke-verdict-10548: $PASSES passed, ${#FAILURES[@]} failed ==="
# Floor reported directly (not through the helper it backstops): both operands are literals on the lines immediately above the if.
SELFTEST_ROWS=0
MIN_ROWS=24
REAL=$((PASSES + FAIL_N - SELFTEST_ROWS))
if (( REAL < MIN_ROWS )); then
  printf 'FAIL: only %d rows ran (floor %d)\n' "$REAL" "$MIN_ROWS"
  exit 1
fi
if (( ${#FAILURES[@]} > 0 )); then printf 'FAIL: %s\n' "${FAILURES[@]}"; exit 1; fi
exit 0
