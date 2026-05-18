#!/usr/bin/env bash
# Tests for upload-bypass.sh — the per-quarter allowlist-bypass writer.
# Same stub-curl pattern as upload-evidence.test.sh; additionally asserts the
# principal_safe key derivation is unforgeable from the payload's own
# principal_safe field (re-derived from principal via the `[bot]` -> `-bot`
# sanitiser).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/upload-bypass.sh"
RC_PUT="$SCRIPT_DIR/r2-conditional-put.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -x "$SUT" || ! -f "$RC_PUT" ]]; then
  red "FAIL: $SUT or $RC_PUT missing"
  exit 1
fi
command -v jq >/dev/null || { red "FAIL: jq not on PATH"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stub curl: emit the next HTTP code from $work/codes.txt and consume it.
# Also append the request URL to $work/urls.txt so tests can assert key
# derivation (the URL is the only side-effect visible to the harness).
# If $work/body_fixture exists, honor curl's `-o <file>` arg and copy the
# fixture there so body-echo tests can assert the error annotation
# surfaces the R2 ErrorCode.
mk_curl_stub() {
  local codes="$1"
  cat > "$work/curl" <<EOF
#!/usr/bin/env bash
codes_file="$codes"
read -r code < "\$codes_file"
sed -i '1d' "\$codes_file"
# Parse \`-o <file>\` and copy the body fixture there if present.
prev=""
out_path=""
for arg in "\$@"; do
  if [[ "\$prev" == "-o" ]]; then out_path="\$arg"; fi
  prev="\$arg"
done
if [[ -n "\$out_path" && -f "$work/body_fixture" ]]; then
  cp "$work/body_fixture" "\$out_path"
fi
# The URL is the last positional arg.
for arg in "\$@"; do url="\$arg"; done
echo "\$url" >> "$work/urls.txt"
echo "\$code"
exit 0
EOF
  chmod +x "$work/curl"
}

run_sut() {
  local payload="$1"
  : > "$work/urls.txt"
  # 32-char access key + 64-char secret to satisfy the r2-conditional-put.sh
  # credential-shape preflight (catches Doppler-still-holds-bearer-token regressions).
  PATH="$work:$PATH" \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID=00000000000000000000000000000000 \
  R2_CLA_EVIDENCE_SECRET=0000000000000000000000000000000000000000000000000000000000000000 \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://example.invalid \
    bash "$SUT" "$payload"
}

fail=0

# Common code-fixture for happy-path assertions.
prime_200() {
  printf "200\n" > "$work/codes.txt"
  mk_curl_stub "$work/codes.txt"
}

# Bypass.a: well-formed payload writes to allowlist/<principal_safe>/<quarter>.json.
prime_200
payload='{"schema_version":"1.0","principal":"dependabot[bot]","principal_safe":"dependabot-bot","quarter":"2026-q2","db_id":49699333,"first_seen_at":"2026-05-16T00:00:00Z","first_pr":3201,"allowlist_source":"cla.yml#with.allowlist"}'
if run_sut "$payload" >/dev/null 2>&1; then
  url=$(cat "$work/urls.txt")
  if [[ "$url" == *"/allowlist/dependabot-bot/2026-q2.json" ]]; then
    green "PASS: Bypass.a first-write 200 → key=allowlist/dependabot-bot/2026-q2.json"
  else
    red "FAIL: Bypass.a expected key /allowlist/dependabot-bot/2026-q2.json; got url=$url"
    fail=1
  fi
else
  red "FAIL: Bypass.a expected exit 0 on first-write 200"
  fail=1
fi

# Bypass.b: 412 duplicate-quarter → exit 0 (idempotent).
printf "412\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut "$payload" >/dev/null 2>&1; then
  green "PASS: Bypass.b duplicate-quarter 412 → exit 0"
else
  red "FAIL: Bypass.b expected exit 0 on 412"
  fail=1
fi

# Bypass.b2: WORM-bucket-policy duplicate at HTTP 409 (production-observed envelope
# from run 26042357131) → exit 0 idempotent. R2 Lock Rules enforce the same
# audit property as 412 in non-WORM buckets ("first-PR-of-quarter wins"); the
# CI must classify it the same way.
printf "409\n" > "$work/codes.txt"
printf '<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>' > "$work/body_fixture"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
rm -f "$work/body_fixture"
if [[ "$rc" -eq 0 ]] && grep -qE 'worm-duplicate-quarter status=409' <<<"$out" && ! grep -q '::error::' <<<"$out"; then
  green "PASS: Bypass.b2 WORM-bucket-policy 409 + ObjectLockedByBucketPolicy → exit 0 (worm-idempotent)"
else
  red "FAIL: Bypass.b2 expected exit 0 + 'worm-duplicate-quarter status=409' (no ::error::); got rc=$rc"
  red "$out"
  fail=1
fi

# Bypass.b2b: WORM-bucket-policy duplicate at HTTP 403 (CF-documented envelope
# for error code 10069). The status disjunction (409 || 403) must cover both
# envelopes so a future CF behavior shift to the documented 403 does not
# silently regress this fix. Body code is the stable identifier.
printf "403\n" > "$work/codes.txt"
printf '<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>' > "$work/body_fixture"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
rm -f "$work/body_fixture"
if [[ "$rc" -eq 0 ]] && grep -qE 'worm-duplicate-quarter status=403' <<<"$out" && ! grep -q '::error::' <<<"$out"; then
  green "PASS: Bypass.b2b WORM-bucket-policy 403 + ObjectLockedByBucketPolicy → exit 0 (worm-idempotent)"
else
  red "FAIL: Bypass.b2b expected exit 0 + 'worm-duplicate-quarter status=403' (no ::error::); got rc=$rc"
  red "$out"
  fail=1
fi

# Bypass.b3: specificity guard — a real R2 4xx code (SignatureDoesNotMatch) is
# NOT a WORM-bucket-policy duplicate. The body match MUST be specific to
# <Code>ObjectLockedByBucketPolicy</Code> so any other 4xx body still
# fast-fails and surfaces in the operator annotation (no silent regressions
# if R2 later adds object-key-lock codes).
printf "409\n" > "$work/codes.txt"
printf '<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match the signature you provided.</Message></Error>' > "$work/body_fixture"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
rm -f "$work/body_fixture"
if [[ "$rc" -ne 0 ]] && grep -qE 'fatal-4xx status=409' <<<"$out" && grep -q 'SignatureDoesNotMatch' <<<"$out"; then
  green "PASS: Bypass.b3 409 + non-WORM body (SignatureDoesNotMatch) → fast-fail with body excerpt"
else
  red "FAIL: Bypass.b3 expected non-zero exit + fatal-4xx annotation with SignatureDoesNotMatch; got rc=$rc"
  red "$out"
  fail=1
fi

# Bypass.b4: defensive fail-closed when R2 returns 409 with no body. We cannot
# prove idempotency from an empty body; fast-fail with the standard annotation.
# Explicit `rm -f` defends against state pollution if a future reorder inserts
# a body-leaving case immediately before this one.
rm -f "$work/body_fixture"
printf "409\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]] && grep -qE 'fatal-4xx status=409' <<<"$out" && grep -q '(empty body)' <<<"$out"; then
  green "PASS: Bypass.b4 409 + empty body → fast-fail (cannot prove idempotency)"
else
  red "FAIL: Bypass.b4 expected non-zero exit + fatal-4xx annotation with (empty body); got rc=$rc"
  red "$out"
  fail=1
fi

# Bypass.c: 403 → fast-fail (Kieran F5). Same defensive cleanup as b4 — every
# case that does NOT prime a body_fixture must `rm -f` first so a future reorder
# cannot leak a WORM-matching body from a prior case and flip Bypass.c's
# expected fast-fail into a worm-idempotent success.
rm -f "$work/body_fixture"
printf "403\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]] && grep -qE 'fatal-4xx.*status=403' <<<"$out"; then
  green "PASS: Bypass.c 403 → fast-fail with ::error::fatal-4xx"
else
  red "FAIL: Bypass.c expected non-zero exit + fatal-4xx annotation"
  red "$out"
  fail=1
fi

# Bypass.d: 5xx exhausted → hard-fail after 3 attempts.
printf "503\n503\n503\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut "$payload" >/dev/null 2>&1; then
  red "FAIL: Bypass.d expected non-zero exit after 3x 5xx"
  fail=1
else
  green "PASS: Bypass.d 5xx exhausted → hard-fail"
fi

# Bypass.e: trust-boundary — principal_safe in payload is IGNORED for key.
# An attacker (or a buggy build-bypass.ts) submits a payload whose
# principal_safe field contains literal `[bot]` substring. The wrapper MUST
# re-derive principal_safe from principal so the bucket key is sanitised
# regardless of payload contents.
prime_200
payload_evil='{"schema_version":"1.0","principal":"dependabot[bot]","principal_safe":"dependabot[bot]","quarter":"2026-q2","db_id":49699333,"first_seen_at":"2026-05-16T00:00:00Z","first_pr":3201,"allowlist_source":"cla.yml#with.allowlist"}'
if run_sut "$payload_evil" >/dev/null 2>&1; then
  url=$(cat "$work/urls.txt")
  if [[ "$url" != *"[bot]"* ]] && [[ "$url" == *"/allowlist/dependabot-bot/2026-q2.json" ]]; then
    green "PASS: Bypass.e payload-supplied principal_safe ignored; key re-derived as dependabot-bot"
  else
    red "FAIL: Bypass.e key=$url contains [bot] substring (trust boundary broken)"
    fail=1
  fi
else
  red "FAIL: Bypass.e expected exit 0 on 200 with adversarial payload"
  fail=1
fi

# Bypass.g: 4xx error surfaces the captured R2 response body in the annotation.
# This is the diagnostic-PR contract — without it the operator has no way to
# distinguish e.g. SignatureDoesNotMatch from ObjectLockedRetention.
printf "400\n" > "$work/codes.txt"
printf '<Error><Code>ObjectLockConfigurationNotFoundError</Code><Message>example</Message></Error>' > "$work/body_fixture"
mk_curl_stub "$work/codes.txt"
out=$(run_sut "$payload" 2>&1) && rc=0 || rc=$?
rm -f "$work/body_fixture"
if [[ "$rc" -ne 0 ]] && grep -q 'ObjectLockConfigurationNotFoundError' <<<"$out"; then
  green "PASS: Bypass.g 400 → fast-fail annotation includes R2 response body"
else
  red "FAIL: Bypass.g expected error annotation to include 'ObjectLockConfigurationNotFoundError'"
  red "$out"
  fail=1
fi

# Bypass.h: 53-char bearer-token-shaped access key → preflight fast-fail with
# operator-actionable bootstrap.sh instruction. Reproduces the 2026-05-16
# Doppler misconfig that caused every pull_request_target run to fail.
prime_200
out=$(
  PATH="$work:$PATH" \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA \
  R2_CLA_EVIDENCE_SECRET=0000000000000000000000000000000000000000000000000000000000000000 \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://example.invalid \
    bash "$SUT" "$payload" 2>&1
) && rc=0 || rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'length=53, expected 32' <<<"$out" && grep -q 'bootstrap.sh' <<<"$out"; then
  green "PASS: Bypass.h 53-char bearer token → preflight fast-fail with bootstrap.sh instruction"
else
  red "FAIL: Bypass.h expected preflight error pointing at bootstrap.sh; got rc=$rc"
  red "$out"
  fail=1
fi

# Bypass.f: missing principal → 64 usage exit.
out=$(run_sut '{"schema_version":"1.0","quarter":"2026-q2"}' 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 64 ]] && grep -qE 'missing principal' <<<"$out"; then
  green "PASS: Bypass.f missing principal → exit 64"
else
  red "FAIL: Bypass.f expected exit 64 with 'missing principal'; got rc=$rc"
  red "$out"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL upload-bypass.sh tests passed."
fi
exit "$fail"
