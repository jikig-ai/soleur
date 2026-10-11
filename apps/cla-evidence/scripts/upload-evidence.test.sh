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
RC_PUT="$SCRIPT_DIR/r2-conditional-put.sh"

red()   { printf '\033[31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

if [[ ! -x "$SUT" ]]; then
  red "FAIL (RED expected): $SUT does not exist or is not executable yet."
  red "Phase 2 GREEN will create it."
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Fixture credentials are synthesized at run time (never a contiguous literal): a 32-char id and a
# 64-char secret that are DISTINCT, neither containing the other, neither one repeated character
# (the old all-zero literals made the 64-zero secret contain the 32-zero id, so an argv-absence
# row could pass or fail by accident). Nothing here prints a value.
rand_hex() { od -An -N"$(( $1 / 2 ))" -tx1 /dev/urandom | tr -d ' \n'; }
while :; do
  ID="$(rand_hex 32)"; SECRET="$(rand_hex 64)"
  [[ "${#ID}" -eq 32 && "${#SECRET}" -eq 64 ]] || continue
  [[ "$SECRET" != *"$ID"* && "$ID" != *"$SECRET"* ]] || continue
  [[ -n "${ID//${ID:0:1}/}" && -n "${SECRET//${SECRET:0:1}/}" ]] || continue
  break
done

# Stub curl: echo the next response code from $work/codes.txt and consume it.
# If $work/body_fixture exists, honor curl's `-o <file>` arg and copy the
# fixture there so body-echo tests can assert the error annotation surfaces
# the R2 ErrorCode. (Mirrors upload-bypass.test.sh's stub form.)
mk_curl_stub() {
  local codes="$1"
  cat > "$work/curl" <<EOF
#!/usr/bin/env bash
codes_file="$codes"
# Record every call: argv, and stdin (drained UNCONDITIONALLY). The stub exits 99 when stdin
# carries no user-config line, so a run that drops the credential channel cannot be served a
# scripted code (a stub that never reads stdin certifies nothing about the credential path).
{ printf 'CALL\n'; printf '%s\n' "\$@"; } >> "$work/argv.log"
stdin=\$(cat; printf x); stdin=\${stdin%x}
printf '%s' "\$stdin" >> "$work/stdin.log"
[[ "\$stdin" == *'user = "'* ]] || { echo "stub: stdin carries no user line" >&2; exit 99; }
[[ "\${STUB_FAIL:-0}" != 1 ]] || exit 7
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

run_sut_creds() {
  local id="$1" secret="$2" payload="$3"
  : > "$work/argv.log"; : > "$work/stdin.log"
  # 32-char access key + 64-char secret to satisfy the r2-conditional-put.sh
  # credential-shape preflight (catches Doppler-still-holds-bearer-token regressions).
  PATH="$work:$PATH" \
  R2_CLA_EVIDENCE_ACCESS_KEY_ID="$id" \
  R2_CLA_EVIDENCE_SECRET="$secret" \
  R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
  R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
    bash "$SUT" "$payload" </dev/null
}
run_sut() { run_sut_creds "$ID" "$SECRET" "$1"; }

fail=0
wire_rows=0

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

# TS6.g: wire contract. After a 200 run the recorded argv holds NEITHER credential value, the
# recorded stdin is the `user = "<id>:<secret>"` config line once per call, and at least one call
# was recorded (an empty log is RED, so a stub that records nothing cannot pass).
printf "200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1 && rc=0 || rc=$?
calls=$(grep -c '^CALL$' "$work/argv.log" || true)
stdin_lines=$(grep -cxF "user = \"$ID:$SECRET\"" "$work/stdin.log" || true)
if [[ "$rc" -eq 0 && "$calls" -ge 1 && "$stdin_lines" -eq "$calls" ]] \
   && ! grep -qF -e "$ID" -e "$SECRET" "$work/argv.log"; then
  green "PASS: TS6.g pair absent from every recorded argv; stdin carries the user line (calls=$calls)"
  wire_rows=$((wire_rows + 1))
else
  red "FAIL: TS6.g rc=$rc calls=$calls stdin_user_lines=$stdin_lines (argv must hold neither value)"
  fail=1
fi

# TS6.h: a 5xx-then-200 retry sends the credential channel on BOTH calls, argv clean on both.
printf "503\n200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
run_sut '{"schema_version":"1.0","x":1}' >/dev/null 2>&1 && rc=0 || rc=$?
calls=$(grep -c '^CALL$' "$work/argv.log" || true)
stdin_lines=$(grep -cxF "user = \"$ID:$SECRET\"" "$work/stdin.log" || true)
if [[ "$rc" -eq 0 && "$calls" -eq 2 && "$stdin_lines" -eq 2 ]] && ! grep -qF -e "$ID" -e "$SECRET" "$work/argv.log"; then
  green "PASS: TS6.h retry sends the user line on both calls; argv clean"
  wire_rows=$((wire_rows + 1))
else
  red "FAIL: TS6.h rc=$rc calls=$calls stdin_user_lines=$stdin_lines"
  fail=1
fi

# TS6.i: a malformed credential (a control byte in the secret, length still 64) is refused BEFORE
# any request: exit 2, zero calls, the marker exactly once with the right reason, no value printed.
bad_secret="${SECRET:0:10}"$'\x01'"${SECRET:11}"
printf "200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
out=$(run_sut_creds "$ID" "$bad_secret" '{"schema_version":"1.0","x":1}' 2>&1) && rc=0 || rc=$?
calls=$(grep -c '^CALL$' "$work/argv.log" || true)
markers=$(grep -c '^SOLEUR_CREDENTIAL_REFUSED script=r2-conditional-put reason=control_char$' <<<"$out" || true)
if [[ "$rc" -eq 2 && "$calls" -eq 0 && "$markers" -eq 1 ]] \
   && ! grep -q 'unexpected status' <<<"$out" \
   && ! grep -qF -e "$ID" -e "$bad_secret" -e "$SECRET" <<<"$out"; then
  green "PASS: TS6.i malformed secret → exit 2, zero calls, marker once (control_char), no value printed"
  wire_rows=$((wire_rows + 1))
else
  red "FAIL: TS6.i rc=$rc calls=$calls markers=$markers (expected 2/0/1, no value in output)"
  fail=1
fi

# TS6.j: a malformed id (a colon, length still 32) is refused with reason=token_shape, zero calls.
bad_id="${ID:0:5}:${ID:6}"
printf "200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
out=$(run_sut_creds "$bad_id" "$SECRET" '{"schema_version":"1.0","x":1}' 2>&1) && rc=0 || rc=$?
calls=$(grep -c '^CALL$' "$work/argv.log" || true)
markers=$(grep -c '^SOLEUR_CREDENTIAL_REFUSED script=r2-conditional-put reason=token_shape$' <<<"$out" || true)
if [[ "$rc" -eq 2 && "$calls" -eq 0 && "$markers" -eq 1 ]] && ! grep -q 'unexpected status' <<<"$out" \
   && ! grep -qF -e "$bad_id" -e "$SECRET" <<<"$out"; then
  green "PASS: TS6.j malformed id → exit 2, zero calls, marker once (token_shape)"
  wire_rows=$((wire_rows + 1))
else
  red "FAIL: TS6.j rc=$rc calls=$calls markers=$markers"
  fail=1
fi

# TS6.k: the script refuses to run under xtrace (exit 78) before binding the pair, so -x can never
# print a value: both `bash -x` and an inherited SHELLOPTS=xtrace are refused, zero calls, and
# neither value reaches the trace.
for mode in bash-x shellopts id-only; do
  printf "200\n" > "$work/codes.txt"
  mk_curl_stub "$work/codes.txt"
  : > "$work/argv.log"; : > "$work/stdin.log"
  if [[ "$mode" == bash-x ]]; then
    out=$(PATH="$work:$PATH" R2_CLA_EVIDENCE_ACCESS_KEY_ID="$ID" R2_CLA_EVIDENCE_SECRET="$SECRET" \
          R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
          R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
          bash -x "$RC_PUT" signatures/x.json '{"x":1}' </dev/null 2>&1) && rc=0 || rc=$?
  elif [[ "$mode" == id-only ]]; then
    # only the key id is set (the secret is unset): -x must still refuse before the id is traced.
    out=$(env -u R2_CLA_EVIDENCE_SECRET PATH="$work:$PATH" R2_CLA_EVIDENCE_ACCESS_KEY_ID="$ID" \
          R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
          R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
          bash -x "$RC_PUT" signatures/x.json '{"x":1}' </dev/null 2>&1) && rc=0 || rc=$?
  else
    # `env`, not a prefix assignment: SHELLOPTS is a readonly variable inside the shell, so
    # `SHELLOPTS=xtrace cmd` fails to apply it; `env` puts it in the child's environment.
    out=$(env PATH="$work:$PATH" SHELLOPTS=xtrace R2_CLA_EVIDENCE_ACCESS_KEY_ID="$ID" R2_CLA_EVIDENCE_SECRET="$SECRET" \
          R2_CLA_EVIDENCE_BUCKET=soleur-cla-evidence \
          R2_CLA_EVIDENCE_ENDPOINT=https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com \
          bash "$RC_PUT" signatures/x.json '{"x":1}' </dev/null 2>&1) && rc=0 || rc=$?
  fi
  calls=$(grep -c '^CALL$' "$work/argv.log" || true)
  if [[ "$rc" -eq 78 && "$calls" -eq 0 ]] && ! grep -qF -e "$ID" -e "$SECRET" <<<"$out"; then
    green "PASS: TS6.k $mode → exit 78 before any request, no value in the trace"
    wire_rows=$((wire_rows + 1))
  else
    red "FAIL: TS6.k $mode rc=$rc calls=$calls (expected 78/0, no value in the trace)"
    fail=1
  fi
done

# TS6.l: a curl that FAILS (exit 7, no output) is a failure: exit 2 with status=000 and no success line.
printf "200\n" > "$work/codes.txt"
mk_curl_stub "$work/codes.txt"
out=$(STUB_FAIL=1 run_sut '{"schema_version":"1.0","x":1}' 2>&1) && rc=0 || rc=$?
if [[ "$rc" -eq 2 && "$(grep -c 'unexpected status=000' <<<"$out" || true)" -ge 1 ]] && ! grep -q '^ok status=' <<<"$out"; then
  green "PASS: TS6.l a failing curl → exit 2, status=000, no success line"
  wire_rows=$((wire_rows + 1))
else
  red "FAIL: TS6.l rc=$rc (expected 2 with unexpected status=000 and no ok line)"
  fail=1
fi

# Anti-vacuity floor for the wire rows above (TS6.g-l, TS6.k counts three times): deleting that block leaves
# the rest of this suite green, so the floor counts what the block's rows passed. Literal adjacent to the if.
MIN_WIRE_ROWS=8
if [[ "$wire_rows" -lt "$MIN_WIRE_ROWS" ]]; then
  printf 'FATAL: anti-vacuity floor — %s wire rows passed, expected at least %s\n' "$wire_rows" "$MIN_WIRE_ROWS" >&2
  exit 1
fi

if [[ "$fail" -eq 0 ]]; then
  green "ALL upload-evidence.sh tests passed."
fi
exit "$fail"
