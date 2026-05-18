#!/usr/bin/env bash
# RED-first per cq-write-failing-tests-before. Phase 2.
# TS6: R2 conditional-PUT idempotency (412 on duplicate); fast-fail on 4xx≠412.
#
# Strategy: stub `curl` with a Bash function that returns scripted HTTP codes
# from a stack file. The script-under-test reads our PATH stub instead of real
# curl; this exercises the retry/exit-code logic without hitting R2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/upload-evidence.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -x "$SUT" ]]; then
  red "FAIL (RED expected): $SUT does not exist or is not executable yet."
  red "Phase 2 GREEN will create it."
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stub curl: echo the next response code from $work/codes.txt and consume it.
# If $work/body_fixture exists, honor curl's `-o <file>` arg and copy the
# fixture there so body-echo tests can assert the error annotation surfaces
# the R2 ErrorCode. (Mirrors upload-bypass.test.sh's stub form.)
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
# Accept a -w "%{http_code}" pattern: emit just the code on stdout, nothing on stderr.
echo "\$code"
exit 0
EOF
  chmod +x "$work/curl"
}

run_sut() {
  local payload="$1"
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

# TS6.a: first-write 200 → exit 0
printf "200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1; then
  green "PASS: TS6.a first-write 200 → exit 0"
else
  red "FAIL: TS6.a expected exit 0 on first-write 200"
  fail=1
fi

# TS6.b: duplicate 412 → exit 0 (idempotent)
printf "412\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1; then
  green "PASS: TS6.b duplicate 412 → exit 0"
else
  red "FAIL: TS6.b expected exit 0 on 412 duplicate"
  fail=1
fi

# TS6.c: 5xx then 200 → retry succeeds
printf "503\n200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1; then
  green "PASS: TS6.c 5xx-then-200 retry → exit 0"
else
  red "FAIL: TS6.c expected exit 0 after 5xx retry"
  fail=1
fi

# TS6.d: 403 → fast-fail (no retry, exit non-zero)
printf "403\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1; then
  red "FAIL: TS6.d expected non-zero exit on 403 fast-fail"
  fail=1
else
  green "PASS: TS6.d 403 → fast-fail (Kieran F5)"
fi

# TS6.e: 5xx 3 times → hard-fail
printf "503\n503\n503\n503\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
if run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1; then
  red "FAIL: TS6.e expected non-zero exit after 3 5xx retries"
  fail=1
else
  green "PASS: TS6.e 5xx exhausted → hard-fail"
fi

# TS6.f: WORM-bucket-policy duplicate at HTTP 409 (R2 Lock Rules block a
# byte-identical re-write of the same content-addressed evidence key). This
# is the dormant evidence path the shared-primitive fix unblocks for free: a
# contributor edits their sign-comment to byte-identical text → identical
# sha → same key → R2 Lock Rules refuse the duplicate write with
# <Code>ObjectLockedByBucketPolicy</Code>. Idempotent-success, not a config
# error.
printf "409\n" > "$work/codes.txt"
printf '<Error><Code>ObjectLockedByBucketPolicy</Code><Message>The object is locked by the bucket policy.</Message></Error>' > "$work/body_fixture"
mk_curl_stub "$work/codes.txt"
out=$(run_sut '{"schema_version":"1.0","x":1}' 2>&1) && rc=0 || rc=$?
rm -f "$work/body_fixture"
if [[ "$rc" -eq 0 ]] && grep -qE 'worm-duplicate status=409' <<<"$out" && ! grep -q '::error::' <<<"$out"; then
  green "PASS: TS6.f WORM-bucket-policy 409 + ObjectLockedByBucketPolicy → exit 0 (worm-idempotent)"
else
  red "FAIL: TS6.f expected exit 0 + 'worm-duplicate status=409' (no ::error::); got rc=$rc"
  red "$out"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL upload-evidence.sh tests passed."
fi
exit "$fail"
