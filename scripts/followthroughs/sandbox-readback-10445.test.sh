#!/usr/bin/env bash
# Behavioural rows for sandbox-readback-10445.sh with `curl` and `gh` stubbed on PATH (no network, no credentials).
# The properties: the probe is NOTIFY-ONLY (it never exits 0 or 1 on any input: exit 0 would close tracker #10456 on a canary
# that was green throughout the outage); it reports ACTION REQUIRED (5) only when the fix PR's merge commit is contained in the
# deployed tag AND the last deploy succeeded for web-platform AND the canary ran since that deploy started; every other state is
# NOT YET (2) or CANNOT ESTABLISH (3). The `gh` stub answers ONLY the exact argv the script must send, so a swapped compare
# range, a dropped `web-` prefix, a wrong PR number or a wrong repo reads as "gh returned nothing" and fails the row.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/sandbox-readback-10445.sh"
ROOT_TMP="$(mktemp -d -t soleur-run.$$.XXXXXXXX)"
trap 'rm -rf "$ROOT_TMP"' EXIT
STUBS="$ROOT_TMP/bin"
mkdir -p "$STUBS"
FAILURES=()
PASSES=0
FAIL_N=0
SHA=0123456789abcdef0123456789abcdef01234567

# curl stub: records the config the SUT feeds on stdin (CURL_STDIN_LOG) and the call count (CURL_CALLS_LOG), then prints
# $STUB_BODY and the HTTP_STATUS trailer the SUT parses.
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
cat >"${CURL_STDIN_LOG:-/dev/null}" 2>/dev/null || true
[[ -z "${CURL_CALLS_LOG:-}" ]] || echo call >>"$CURL_CALLS_LOG"
printf '%s\nHTTP_STATUS:%s' "${STUB_BODY:-}" "${STUB_HTTP:-200}"
STUB
# gh stub: answers only the exact argv the SUT must send; anything else prints nothing (the SUT then reads "unavailable").
cat > "$STUBS/gh" <<STUB
#!/usr/bin/env bash
argv="\$*"
case "\$argv" in
  "pr view 10451 --repo jikig-ai/soleur --json mergeCommit,mergedAt --jq [(.mergeCommit.oid // \"\"), (.mergedAt // \"\")] | @tsv")
    [[ -z "\${STUB_GH_FAIL:-}" ]] || exit 1
    printf '%s\t%s\n' "\${STUB_MERGE_SHA:-}" "\${STUB_MERGED_AT:-1970-01-01T00:08:20Z}" ;;
  "api repos/jikig-ai/soleur/compare/web-v1.2.3...$SHA --jq .status") printf '%s\n' "\${STUB_COMPARE:-}" ;;
esac
STUB
chmod +x "$STUBS/curl" "$STUBS/gh"

LAST_OUT=""
run() { # <expected rc> <label> <body> <merge sha> <compare> [http] [env-unset-var]
  local want="$1" label="$2" body="$3" sha="$4" cmp="$5" http="${6:-200}" unset_var="${7:-}" out rc
  out="$(env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=sec GH_TOKEN=t \
    STUB_BODY="$body" STUB_MERGE_SHA="$sha" STUB_COMPARE="$cmp" STUB_HTTP="$http" STUB_GH_FAIL="${GH_FAIL:-}" env ${unset_var:+-u "$unset_var"} bash "$SUT" 2>&1)"
  rc=$?
  LAST_OUT="$out"
  if [[ "$rc" == "0" || "$rc" == "1" ]]; then FAIL_N=$((FAIL_N + 1)); FAILURES+=("$label: NOTIFY-ONLY violated (rc=$rc): $out"); echo "  FAIL: $label (rc=$rc is forbidden)"; return; fi
  if [[ "$rc" == "$want" ]]; then PASSES=$((PASSES + 1)); echo "  ok: $label (rc=$rc)"; else FAIL_N=$((FAIL_N + 1)); FAILURES+=("$label: want rc=$want got rc=$rc: $out"); echo "  FAIL: $label (want $want got $rc)"; fi
}
body() { # <exit_code> <component> <start_ts> <verdict> <checked_at> [tag]
  printf '{"tag":"%s","exit_code":%s,"component":"%s","start_ts":%s,"sandbox_canary":{"verdict":"%s","checked_at":%s}}' "${6:-v1.2.3}" "$1" "$2" "$3" "$4" "$5"
}
GREEN="$(body 0 web-platform 1000 pass 1500)"
RED="$(body 0 web-platform 1000 sandbox_broken 1500)"

run 5 "fix contained in the deployed tag, deploy ok, canary re-run since -> ACTION REQUIRED" "$GREEN" "$SHA" behind
run 5 "merge commit IS the tag -> ACTION REQUIRED" "$GREEN" "$SHA" identical
run 5 "canary broken after the deploy -> ACTION REQUIRED (regression), never exit 1" "$RED" "$SHA" behind
run 2 "PR not merged yet -> NOT YET even though the canary is green" "$GREEN" "" behind
run 2 "tag predates the fix (merge commit ahead of the tag) -> NOT YET" "$GREEN" "$SHA" ahead
run 2 "diverged -> NOT YET" "$GREEN" "$SHA" diverged
run 3 "gh api returned nothing -> CANNOT ESTABLISH" "$GREEN" "$SHA" ""
run 3 "deploy-status HTTP 502 -> CANNOT ESTABLISH" "$GREEN" "$SHA" behind 502
run 3 "body without sandbox_canary -> CANNOT ESTABLISH" '{"tag":"v1.2.3"}' "$SHA" behind
run 3 "tag that is not a release tag -> CANNOT ESTABLISH" '{"tag":"main","exit_code":0,"component":"web-platform","start_ts":1000,"sandbox_canary":{"verdict":"pass","checked_at":1500}}' "$SHA" behind
run 2 "no verdict yet -> NOT YET" "$(body 0 web-platform 1000 canary_infra_error 1500)" "$SHA" behind
# The deploy-in-flight / stale-canary rows: `.tag` is the last ATTEMPT and the canary ledger is the previous deploy's.
run 2 "deploy in flight (exit_code=-1) with a stale green canary -> NOT YET" "$(body -1 web-platform 1000 pass 500)" "$SHA" behind
run 2 "last deploy FAILED (exit_code=1) with a green canary -> NOT YET" "$(body 1 web-platform 1000 pass 1500)" "$SHA" behind
# The deploy frame is shared by every component: a later inngest deploy overwrites it, so the readback must fall back on the
# durable canary ledger (checked after the PR merged, merged_at = epoch 500 in the stub) instead of sitting at NOT YET forever.
run 5 "a later inngest deploy overwrote the frame; ledger checked after the merge -> ACTION REQUIRED (likely)" "$(body 0 inngest 1000 pass 1500 vinngest-v1.1.56)" "$SHA" behind
run 2 "a later inngest deploy overwrote the frame; ledger predates the merge -> NOT YET" "$(body 0 inngest 1000 pass 400 vinngest-v1.1.56)" "$SHA" behind
run 2 "web-platform deploy whose canary ran before the PR merged -> NOT YET" "$(body 0 web-platform 400 pass 499)" "$SHA" behind
GH_FAIL=1 run 3 "gh pr view failing -> CANNOT ESTABLISH, not NOT YET" "$GREEN" "$SHA" behind
run 2 "canary verdict predates the deploy start (checked_at < start_ts) -> NOT YET" "$(body 0 web-platform 1000 pass 999)" "$SHA" behind
run 2 "no start_ts in the answer -> NOT YET" '{"tag":"v1.2.3","exit_code":0,"component":"web-platform","sandbox_canary":{"verdict":"pass","checked_at":1500}}' "$SHA" behind
# The stub answers only the exact argv: a different tag in the answer makes the compare path differ and reads as unavailable.
run 3 "a deployed tag the exact-argv stub does not model -> CANNOT ESTABLISH (proves argv is pinned)" "$(body 0 web-platform 1000 pass 1500 v9.9.9)" "$SHA" behind
run 3 "GH_TOKEN unset -> CANNOT ESTABLISH" "$GREEN" "$SHA" behind 200 GH_TOKEN
# A forged remote value must not reach stdout with a newline or a workflow command.
run 2 "forged verdict falls to NOT YET with the value reduced" '{"tag":"v1.2.3","exit_code":0,"component":"web-platform","start_ts":1000,"sandbox_canary":{"verdict":"x\n::error::boom","checked_at":1500}}' "$SHA" behind
if grep -qE '^::' <<<"$LAST_OUT" || [[ "$(wc -l <<<"$LAST_OUT")" -ne 1 ]] || ! grep -q "verdict='xerrorboom'" <<<"$LAST_OUT"; then
  FAIL_N=$((FAIL_N + 1)); FAILURES+=("forged workflow command not neutralised (want one line with verdict='xerrorboom'): $LAST_OUT")
else PASSES=$((PASSES + 1)); echo "  ok: forged verdict is one line, no leading ::, value reduced to xerrorboom"; fi

# xtrace refusal with a live credential: rc 78 (declined before any request), never 0/1.
xt_out="$(PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=sec GH_TOKEN=t bash -x "$SUT" 2>&1 >/dev/null | grep -c 'refusing to trace' )"
xt_rc=$(PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=sec GH_TOKEN=t bash -x "$SUT" >/dev/null 2>&1; echo $?)
if [[ "$xt_rc" == "78" && "$xt_out" -ge 1 ]]; then PASSES=$((PASSES + 1)); echo "  ok: xtrace with a live credential is refused (rc=78)"; else FAIL_N=$((FAIL_N + 1)); FAILURES+=("xtrace refusal: rc=$xt_rc refusals=$xt_out"); fi

# The credentials ride curl's stdin as three exact config lines, the signature is 64 lowercase hex, and a hostile Cloudflare Access
# value is refused before any request is made (one value-free marker, rc 3, zero curl calls).
curl_stdin_log="$ROOT_TMP/curl-stdin.log"
env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=sec GH_TOKEN=t \
  STUB_BODY="$GREEN" STUB_MERGE_SHA="$SHA" STUB_COMPARE=behind CURL_STDIN_LOG="$curl_stdin_log" bash "$SUT" >/dev/null 2>&1
if grep -qE '^header = "X-Signature-256: sha256=[0-9a-f]{64}"$' "$curl_stdin_log" && grep -qxF 'header = "CF-Access-Client-Id: id"' "$curl_stdin_log" \
   && grep -qxF 'header = "CF-Access-Client-Secret: sec"' "$curl_stdin_log" && [[ "$(wc -l <"$curl_stdin_log")" -eq 3 ]]; then
  PASSES=$((PASSES + 1)); echo "  ok: curl stdin carries exactly the three header lines (a 64-hex signature, the id, the secret)"
else FAIL_N=$((FAIL_N + 1)); FAILURES+=("curl stdin does not carry exactly the three header lines"); echo "  FAIL: curl stdin header lines"; fi
curl_calls_log="$ROOT_TMP/curl-calls.log"
: >"$curl_calls_log"
hostile_out="$(env PATH="$STUBS:$PATH" WEBHOOK_DEPLOY_SECRET=s CF_ACCESS_CLIENT_ID=id CF_ACCESS_CLIENT_SECRET=$'se"c\nheader = "x' GH_TOKEN=t \
  STUB_BODY="$GREEN" STUB_MERGE_SHA="$SHA" STUB_COMPARE=behind CURL_CALLS_LOG="$curl_calls_log" bash "$SUT" 2>&1)"
hostile_rc=$?
if [[ "$hostile_rc" == "3" && ! -s "$curl_calls_log" && "$(grep -c 'SOLEUR_CREDENTIAL_REFUSED script=sandbox-readback-10445' <<<"$hostile_out")" == "1" ]] \
   && ! grep -q 'se"c' <<<"$hostile_out"; then
  PASSES=$((PASSES + 1)); echo "  ok: a hostile Cloudflare Access secret is refused (rc=3, zero curl calls, one marker, value not echoed)"
else FAIL_N=$((FAIL_N + 1)); FAILURES+=("hostile CF secret: rc=$hostile_rc calls=$(wc -l <"$curl_calls_log") out=$hostile_out"); echo "  FAIL: hostile CF secret"; fi

ROWS=$((PASSES + FAIL_N))
echo ""
echo "=== sandbox-readback-10445: $PASSES passed, ${#FAILURES[@]} failed ($ROWS rows) ==="
# Floor reported directly (not through the helper it backstops): the row count above.
if (( PASSES + FAIL_N < 26 )); then
  printf 'FAIL: only %d rows ran (floor 26)\n' "$((PASSES + FAIL_N))"
  exit 1
fi
if (( ${#FAILURES[@]} > 0 )); then printf 'FAIL: %s\n' "${FAILURES[@]}"; exit 1; fi
exit 0
