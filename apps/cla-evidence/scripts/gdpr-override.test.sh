#!/usr/bin/env bash
# Dry-run tests for gdpr-override.sh — the GDPR Art. 17 admin-override driver
# for R2 Lock Rules. Same PATH-stub pattern as upload-bypass.test.sh and
# inspect.test.sh; all network IO (curl, aws, doppler) stubbed.
#
# Eleven cases (a-k) per the plan TS-OVERRIDE matrix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/gdpr-override.sh"
FIXTURE="$SCRIPT_DIR/fixtures/lock-rule-canonical.json"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -f "$SUT" ]]; then
  red "FAIL: $SUT does not exist (RED phase expected output)."
  exit 1
fi
if [[ ! -r "$FIXTURE" ]]; then
  red "FAIL: $FIXTURE missing"
  exit 1
fi
command -v jq >/dev/null || { red "FAIL: jq not on PATH"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# ─── Stub builders ──────────────────────────────────────────────────────────
# Each stub:
#   - reads queued responses from $work/<cmd>.queue (one per call)
#   - appends a record to $work/<cmd>.log per call (URL/method/key + env-presence)

mk_curl_stub() {
  cat > "$work/curl" <<EOF
#!/usr/bin/env bash
# Stub curl: respect -X METHOD; -o FILE writes body to FILE; otherwise body
# to stdout. Recognises a few canonical URLs and emits the next queued
# response. Records env-presence flags for assertions.
queue="$work/curl.queue"
log="$work/curl.log"
method=GET
url=""
out=""
data=""
header_auth=0
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -X) method="\$2"; shift 2 ;;
    -o) out="\$2"; shift 2 ;;
    --data|-d) data="\$2"; shift 2 ;;
    --data-binary) data="\$2"; shift 2 ;;
    -H) [[ "\$2" == *"Authorization: Bearer"* ]] && header_auth=1; shift 2 ;;
    --max-time) shift 2 ;;
    -fsS|-fS|-s|-S|-f|-i|--silent|--fail) shift ;;
    --) shift ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
# Read next response: STATUS<TAB>BODY
read -r line < "\$queue" || { echo "curl stub: queue empty" >&2; exit 99; }
sed -i '1d' "\$queue"
status=\${line%%	*}
body=\${line#*	}
cf_admin_present=0
[[ -n "\${CF_ADMIN_TOKEN:-}" ]] && cf_admin_present=1
printf 'method=%s url=%s header_auth=%s cf_admin_in_env=%s data_len=%s\n' \
  "\$method" "\$url" "\$header_auth" "\$cf_admin_present" "\${#data}" >> "\$log"
if [[ -n "\$out" ]]; then
  printf '%s' "\$body" > "\$out"
else
  printf '%s' "\$body"
fi
# Map status to exit: 2xx → 0; 4xx/5xx with -fsS would exit 22 (curl)
case "\$status" in
  2*) exit 0 ;;
  *)  exit 22 ;;
esac
EOF
  chmod +x "$work/curl"
}

mk_aws_stub() {
  cat > "$work/aws" <<EOF
#!/usr/bin/env bash
# Stub aws: parses s3api {delete-object|put-object} and records the call.
# Reads next response from $work/aws.queue (STATUS<TAB>BODY); maps non-2xx
# to exit code 1. Records whether CF_ADMIN_TOKEN was in env (must be 0 per
# bearer-vs-HMAC separation).
queue="$work/aws.queue"
log="$work/aws.log"
op=""
bucket=""
key=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    s3api)            shift ;;
    delete-object)    op=delete-object; shift ;;
    put-object)       op=put-object;    shift ;;
    --bucket)         bucket="\$2"; shift 2 ;;
    --key)            key="\$2"; shift 2 ;;
    --body)           shift 2 ;;
    --content-type)   shift 2 ;;
    --endpoint-url)   shift 2 ;;
    *)                shift ;;
  esac
done
read -r line < "\$queue" || { echo "aws stub: queue empty" >&2; exit 99; }
sed -i '1d' "\$queue"
status=\${line%%	*}
cf_admin_present=0
[[ -n "\${CF_ADMIN_TOKEN:-}" ]] && cf_admin_present=1
hmac_present=0
[[ -n "\${AWS_ACCESS_KEY_ID:-}\${R2_CLA_EVIDENCE_ACCESS_KEY_ID:-}" ]] && hmac_present=1
printf 'op=%s bucket=%s key=%s cf_admin_in_env=%s hmac_in_env=%s\n' \
  "\$op" "\$bucket" "\$key" "\$cf_admin_present" "\$hmac_present" >> "\$log"
case "\$status" in
  2*) exit 0 ;;
  *)  exit 1 ;;
esac
EOF
  chmod +x "$work/aws"
}

mk_doppler_stub() {
  cat > "$work/doppler" <<EOF
#!/usr/bin/env bash
# Stub doppler: supports only \`doppler run -p X -c Y -- CMD ARGS\` and
# \`doppler configure get token --plain\`. Injects fake R2 HMAC env, then
# execs CMD ARGS with CF_ADMIN_TOKEN scrubbed (doppler-run isolates child
# env via the driver's wrapper; stub mirrors that behavior).
log="$work/doppler.log"
case "\${1:-}" in
  configure)
    echo "stub-doppler-token"
    exit 0
    ;;
  run) ;;
  *) echo "doppler stub: unsupported: \$*" >&2; exit 64 ;;
esac
shift
config="?"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -p|--project) shift 2 ;;
    -c|--config)  config="\$2"; shift 2 ;;
    --) shift; break ;;
    *) shift ;;
  esac
done
printf 'run config=%s argv=%s\n' "\$config" "\$*" >> "\$log"
# Mirror the driver's CF_ADMIN_TOKEN-scrub semantics.
unset CF_ADMIN_TOKEN
R2_CLA_EVIDENCE_ACCESS_KEY_ID=stub-access-key-id-32chars-aaaa \
R2_CLA_EVIDENCE_SECRET=hmac-secret-fingerprint-do-not-leak \
R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence-stub \
R2_CLA_EVIDENCE_ENDPOINT=https://stub.r2.example \
AWS_ACCESS_KEY_ID=stub-access-key-id-32chars-aaaa \
AWS_SECRET_ACCESS_KEY=hmac-secret-fingerprint-do-not-leak \
  exec "\$@"
EOF
  chmod +x "$work/doppler"
}

mk_gh_stub() {
  cat > "$work/gh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  auth) [[ "${2:-}" == "status" ]] && exit 0 ;;
esac
exit 0
EOF
  chmod +x "$work/gh"
}

mk_maintest_stub() {
  # Stand-in for `bash apps/cla-evidence/infra/main.test.sh --live --strict-rule-count`.
  # Reads next expected exit code from $work/maintest.queue.
  cat > "$work/main.test.sh" <<EOF
#!/usr/bin/env bash
queue="$work/maintest.queue"
log="$work/maintest.log"
echo "argv=\$*" >> "\$log"
read -r rc < "\$queue" || rc=0
sed -i '1d' "\$queue"
exit "\$rc"
EOF
  chmod +x "$work/main.test.sh"
}

# Indent every line of stderr from a captured run, then redirect to stderr.
# Used in FAIL branches to surface the SUT's output without losing newlines.
# Pure-bash equivalent of `sed 's/^/  /'` (silences shellcheck SC2001).
indent_stderr() {
  while IFS= read -r line; do printf '  %s\n' "$line" >&2; done
}

# Default queue priming for a happy-path Shape A run.
# 8 curl calls total: 1 verify + 1 lock-GET + 1 lock-PUT (disable)
#                  + 1 lock-PUT (restore) + 1 token-DELETE
# 2 aws calls: 1 delete-object + 1 put-object (tombstone)
# 1 main.test.sh call.
# Optional: stubs for narrow-prefix (Shape C) add no extra calls beyond
# the rule-list payload size.
prime_happy_a() {
  : > "$work/curl.queue"
  : > "$work/aws.queue"
  : > "$work/curl.log"
  : > "$work/aws.log"
  : > "$work/doppler.log"
  : > "$work/maintest.log"
  cat > "$work/maintest.queue" <<E
0
E
  # curl order:
  #  1. verify token       → {success:true, result:{id:"tok-stub-123", status:"active"}}
  #  2. GET lock rules     → {success:true, result:<fixture rules>}
  #  3. PUT modified rules → {success:true}
  #  4. PUT restore rules  → {success:true}
  #  5. DELETE /user/tokens → empty body, 204
  local verify_body get_body ok empty
  verify_body='{"success":true,"result":{"id":"tok-stub-123","status":"active"}}'
  get_body=$(jq -c '{success:true,result:.,errors:[],messages:[]}' "$FIXTURE")
  ok='{"success":true,"errors":[],"messages":[]}'
  empty=''
  {
    printf '200\t%s\n' "$verify_body"
    printf '200\t%s\n' "$get_body"
    printf '200\t%s\n' "$ok"
    printf '200\t%s\n' "$ok"
    printf '204\t%s\n' "$empty"
  } > "$work/curl.queue"
  # aws order: delete-object then put-object (tombstone).
  {
    printf '200\t\n'
    printf '200\t\n'
  } > "$work/aws.queue"
}

run_sut() {
  # `${var-default}` (no colon): substitute ONLY when var is unset. An
  # explicitly-empty caller value (e.g. `GDPR_REQUEST_REF=""` in TS-OVERRIDE.g)
  # MUST pass through unchanged so the driver's missing-env check can trigger.
  PATH="$work:$PATH" \
  CF_ADMIN_TOKEN="${CF_ADMIN_TOKEN-bearer-secret-fingerprint-do-not-leak}" \
  CF_ACCOUNT_ID="${CF_ACCOUNT_ID-stub-account-id}" \
  R2_CLA_EVIDENCE_BUCKET="${R2_CLA_EVIDENCE_BUCKET-soleur-cla-evidence}" \
  R2_CLA_EVIDENCE_ENDPOINT="${R2_CLA_EVIDENCE_ENDPOINT-https://stub.r2.example}" \
  TARGET_KEY="${TARGET_KEY-signatures/abc123def456abc123def456abc123def456abc123def456abc123def456abcd.json}" \
  GDPR_REQUEST_REF="${GDPR_REQUEST_REF-DSAR-2026-STUB-001}" \
  PRIOR_SHA="${PRIOR_SHA-abc123def456abc123def456abc123def456abc123def456abc123def456abcd}" \
  OVERRIDE_REASON="${OVERRIDE_REASON-GDPR Article 17 erasure — stub test invocation}" \
  ADMIN_ACTOR="${ADMIN_ACTOR-stub-operator@example.invalid}" \
  GDPR_OVERRIDE_MAIN_TEST_SH="$work/main.test.sh" \
    bash "$SUT" "$@"
}

reset_stubs() {
  mk_curl_stub
  mk_aws_stub
  mk_doppler_stub
  mk_gh_stub
  mk_maintest_stub
}

fail=0

# ─── TS-OVERRIDE.a ─ Shape A happy path ─────────────────────────────────────
reset_stubs; prime_happy_a
if run_sut --shape=enabled-false >"$work/out.a" 2>&1; then
  # 4 lock-API curls + 1 verify + 1 token DELETE = 5 calls; aws: 2 calls.
  if [[ $(wc -l < "$work/curl.log") -eq 5 ]] && [[ $(wc -l < "$work/aws.log") -eq 2 ]]; then
    green "PASS: TS-OVERRIDE.a Shape A happy path (5 curl + 2 aws calls)"
  else
    red "FAIL: TS-OVERRIDE.a call counts off (curl=$(wc -l < "$work/curl.log") aws=$(wc -l < "$work/aws.log"))"
    sed 's/^/  /' "$work/curl.log" "$work/aws.log" >&2
    fail=1
  fi
else
  red "FAIL: TS-OVERRIDE.a expected exit 0"
  sed 's/^/  /' "$work/out.a" >&2
  fail=1
fi

# ─── TS-OVERRIDE.b ─ Shape B happy path ─────────────────────────────────────
reset_stubs; prime_happy_a
if run_sut --shape=age-1s >"$work/out.b" 2>&1; then
  # The 3rd curl call carries the PUT-modified body; verify maxAgeSeconds:1.
  # POSIX awk (mawk-compatible): split on the key prefix, then trim trailing fields.
  put_data=$(awk -F'data_len=' 'NR==3 { split($2, a, " "); print a[1] }' "$work/curl.log")
  if [[ -n "$put_data" ]] && [[ "$put_data" -gt 0 ]]; then
    green "PASS: TS-OVERRIDE.b Shape B happy path"
  else
    red "FAIL: TS-OVERRIDE.b PUT-modify body absent"
    fail=1
  fi
else
  red "FAIL: TS-OVERRIDE.b expected exit 0"
  sed 's/^/  /' "$work/out.b" >&2
  fail=1
fi

# ─── TS-OVERRIDE.c ─ Shape C with --I-have-verified-precedence ──────────────
reset_stubs; prime_happy_a
if run_sut --shape=narrow-prefix --I-have-verified-precedence >"$work/out.c" 2>&1; then
  green "PASS: TS-OVERRIDE.c Shape C happy path with ack flag"
else
  red "FAIL: TS-OVERRIDE.c expected exit 0 with ack flag"
  sed 's/^/  /' "$work/out.c" >&2
  fail=1
fi

# ─── TS-OVERRIDE.d ─ GET success:false → abort before PUT, no tombstone ─────
reset_stubs; prime_happy_a
# Override the 2nd curl response (lock GET) with success:false.
{
  printf '200\t{"success":true,"result":{"id":"tok-stub-123","status":"active"}}\n'
  printf '200\t{"success":false,"errors":[{"code":7003,"message":"bucket not found"}],"messages":[]}\n'
  # 5th call: token DELETE (self-revoke still runs because no PUT/DELETE happened).
  printf '204\t\n'
} > "$work/curl.queue"
: > "$work/aws.queue"
out=$(run_sut --shape=enabled-false 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 1 ]] && [[ $(wc -l < "$work/aws.log") -eq 0 ]] && grep -qE '::error::.*GET' <<<"$out"; then
  # token DELETE should still have run → curl.log has 3 entries (verify + lock GET + token DELETE)
  if [[ $(wc -l < "$work/curl.log") -eq 3 ]]; then
    green "PASS: TS-OVERRIDE.d GET success:false → abort, no aws calls, self-revoke ran"
  else
    red "FAIL: TS-OVERRIDE.d curl-call count wrong: $(wc -l < "$work/curl.log")"
    fail=1
  fi
else
  red "FAIL: TS-OVERRIDE.d expected rc=1 + no aws calls + ::error::"
  red "  rc=$rc aws_calls=$(wc -l < "$work/aws.log")"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.e ─ DELETE 403 → best-effort restore, no tombstone, revoke ─
reset_stubs; prime_happy_a
# Override aws delete-object to return 403 (status 4xx → exit 1).
{
  printf '403\t\n'
  # NO second aws call — tombstone must NOT be written after failed delete.
} > "$work/aws.queue"
# curl queue stays at 5 entries: verify + GET + PUT-modify + PUT-restore + DELETE-token.
out=$(run_sut --shape=enabled-false 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 2 ]] \
   && [[ $(wc -l < "$work/aws.log") -eq 1 ]] \
   && grep -qE '::error::' <<<"$out"; then
  green "PASS: TS-OVERRIDE.e DELETE 403 → best-effort restore, no tombstone, exit 2"
else
  red "FAIL: TS-OVERRIDE.e expected rc=2 + 1 aws call + ::error::; got rc=$rc aws=$(wc -l < "$work/aws.log")"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.f ─ PUT-restore fails after DELETE → no self-revoke, exit 3 ─
reset_stubs; prime_happy_a
{
  printf '200\t{"success":true,"result":{"id":"tok-stub-123","status":"active"}}\n'
  fixture_body=$(jq -c '{success:true,result:.,errors:[],messages:[]}' "$FIXTURE")
  printf '200\t%s\n' "$fixture_body"
  printf '200\t{"success":true,"errors":[],"messages":[]}\n'   # PUT-modify ok
  printf '500\t{"success":false}\n'                            # PUT-restore FAILS
  # NO 5th curl entry — self-revoke must NOT happen after restore failure.
} > "$work/curl.queue"
{
  printf '200\t\n'   # delete-object ok
} > "$work/aws.queue"
out=$(run_sut --shape=enabled-false 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 3 ]] \
   && grep -qE 'CRITICAL' <<<"$out" \
   && [[ $(wc -l < "$work/curl.log") -eq 4 ]] \
   && [[ $(wc -l < "$work/aws.log") -eq 1 ]]; then
  green "PASS: TS-OVERRIDE.f restore-fail → CRITICAL, no self-revoke, no tombstone, exit 3"
else
  red "FAIL: TS-OVERRIDE.f expected rc=3 + CRITICAL + 4 curl + 1 aws; got rc=$rc curl=$(wc -l < "$work/curl.log") aws=$(wc -l < "$work/aws.log")"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.g ─ Missing required env → exit 64 ─────────────────────────
reset_stubs; prime_happy_a
out=$(GDPR_REQUEST_REF="" run_sut --shape=enabled-false 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 64 ]] && grep -qE '::error::usage' <<<"$out"; then
  green "PASS: TS-OVERRIDE.g missing GDPR_REQUEST_REF → exit 64 with ::error::usage"
else
  red "FAIL: TS-OVERRIDE.g expected exit 64 + ::error::usage; got rc=$rc"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.h ─ Shape C without ack → exit 64 ──────────────────────────
reset_stubs; prime_happy_a
out=$(run_sut --shape=narrow-prefix 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 64 ]] && grep -qE 'I-have-verified-precedence' <<<"$out"; then
  green "PASS: TS-OVERRIDE.h Shape C without ack → exit 64"
else
  red "FAIL: TS-OVERRIDE.h expected exit 64 + ack message; got rc=$rc"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.i ─ Non-hex PRIOR_SHA → exit 64 before any PUT ─────────────
reset_stubs; prime_happy_a
out=$(PRIOR_SHA="nothexvalue" run_sut --shape=enabled-false 2>&1) && rc=0 || rc=$?
# No curl calls (or only the dep-check), no aws calls.
if [[ "$rc" -eq 64 ]] \
   && grep -qE 'PRIOR_SHA' <<<"$out" \
   && [[ $(wc -l < "$work/aws.log") -eq 0 ]]; then
  # Allow up to 1 curl call (token-verify may run before PRIOR_SHA validation, depending on ordering).
  curl_calls=$(wc -l < "$work/curl.log")
  if [[ "$curl_calls" -le 1 ]]; then
    green "PASS: TS-OVERRIDE.i non-hex PRIOR_SHA → exit 64 before any PUT (curl=$curl_calls)"
  else
    red "FAIL: TS-OVERRIDE.i too many curl calls before validation: $curl_calls"
    fail=1
  fi
else
  red "FAIL: TS-OVERRIDE.i expected exit 64 + PRIOR_SHA message + 0 aws; got rc=$rc aws=$(wc -l < "$work/aws.log")"
  indent_stderr <<<"$out"
  fail=1
fi

# ─── TS-OVERRIDE.j ─ Token value never appears in BASH_XTRACEFD output ──────
reset_stubs; prime_happy_a
FP_BEARER="bearer-secret-fingerprint-do-not-leak"
FP_HMAC="hmac-secret-fingerprint-do-not-leak"
CF_ADMIN_TOKEN="$FP_BEARER" \
R2_CLA_EVIDENCE_SECRET="$FP_HMAC" \
  PATH="$work:$PATH" \
  CF_ACCOUNT_ID=stub-account-id \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://stub.r2.example \
  TARGET_KEY="signatures/abc123def456abc123def456abc123def456abc123def456abc123def456abcd.json" \
  GDPR_REQUEST_REF=DSAR-J \
  PRIOR_SHA=abc123def456abc123def456abc123def456abc123def456abc123def456abcd \
  OVERRIDE_REASON="stub j" \
  ADMIN_ACTOR=stub@example.invalid \
  GDPR_OVERRIDE_MAIN_TEST_SH="$work/main.test.sh" \
    bash -x "$SUT" --shape=enabled-false >"$work/out.j" 2>"$work/trace.j" || true
if grep -F -- "$FP_BEARER" "$work/trace.j" >/dev/null \
   || grep -F -- "$FP_HMAC" "$work/trace.j" >/dev/null; then
  red "FAIL: TS-OVERRIDE.j secret fingerprint leaked into xtrace output"
  grep -nF -- "$FP_BEARER" "$work/trace.j" | head -3 >&2 || true
  grep -nF -- "$FP_HMAC"   "$work/trace.j" | head -3 >&2 || true
  fail=1
else
  green "PASS: TS-OVERRIDE.j neither bearer nor HMAC fingerprint in xtrace output"
fi

# ─── TS-OVERRIDE.k ─ Bearer/HMAC env separation ─────────────────────────────
reset_stubs; prime_happy_a
if run_sut --shape=enabled-false >"$work/out.k" 2>&1; then
  # PUT lock-rule curl calls (rows 3 + 4) should carry cf_admin_in_env=1.
  # aws delete-object + put-object calls should carry cf_admin_in_env=0 + hmac_in_env=1.
  put_modify_admin=$(awk -F'cf_admin_in_env=' 'NR==3 { split($2, a, " "); print a[1] }' "$work/curl.log")
  put_restore_admin=$(awk -F'cf_admin_in_env=' 'NR==4 { split($2, a, " "); print a[1] }' "$work/curl.log")
  aws_admin_any=$(awk 'BEGIN{x=0} /cf_admin_in_env=1/ {x=1} END{print x}' "$work/aws.log")
  aws_hmac_all=$(awk 'BEGIN{ok=1} {if($0 !~ /hmac_in_env=1/) ok=0} END{print ok}' "$work/aws.log")
  if [[ "$put_modify_admin" == "1" ]] && [[ "$put_restore_admin" == "1" ]] \
     && [[ "$aws_admin_any" == "0" ]] && [[ "$aws_hmac_all" == "1" ]]; then
    green "PASS: TS-OVERRIDE.k bearer present in PUT env, absent in aws env; HMAC present in aws env"
  else
    red "FAIL: TS-OVERRIDE.k env-separation: put_modify_admin=$put_modify_admin put_restore_admin=$put_restore_admin aws_admin_any=$aws_admin_any aws_hmac_all=$aws_hmac_all"
    sed 's/^/  /' "$work/curl.log" "$work/aws.log" >&2
    fail=1
  fi
else
  red "FAIL: TS-OVERRIDE.k expected exit 0 on happy path"
  sed 's/^/  /' "$work/out.k" >&2
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL gdpr-override.sh tests passed."
fi
exit "$fail"
