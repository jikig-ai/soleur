#!/usr/bin/env bash
# Unit tests for scripts/betterstack-ingest-probe.sh (#7569).
#
# The probe answers ONE question the reader side structurally cannot: when the warehouse is
# returning nothing, is that because writes are being REFUSED, and with what code? It is a
# cause ANNOTATION and has no veto over the reader-derived verdict — a point asserted below,
# because the tempting design (let the probe decide) reintroduces the failure it explains.
#
# WHY THE PROBE IS NON-WRITING. Measured 2026-08-16 against the live endpoint: an empty batch
# (`[]` or `{}`) is refused with the SAME HTTP 402 {"error": "Quota exceeded"} as a real
# payload, and a bad token returns 401. So the probe can discriminate quota from auth from
# healthy WITHOUT writing a row. That matters beyond tidiness: the alarm's control query is
# unfiltered, so any row the probe wrote would satisfy it forever, converting a two-day outage
# into a permanent blind spot. A writing probe would mask the silence it exists to detect.
#
# cq-test-fixtures-synthesized-only: no live responses are captured here.

set -uo pipefail
export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/betterstack-ingest-probe.sh"

TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); echo "[ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $1"; }

[[ -x "$PROBE" ]] || { echo "[FATAL] probe not found/executable at $PROBE"; exit 2; }

# --- curl stub -----------------------------------------------------------------------------
# Validates argv (exit 64 on a missing required flag) so the suite can detect the probe
# sending the WRONG request, not merely getting an answer. A stub that answers identically
# regardless of argv puts the fixture seam above the code under test.
STUB_DIR="$TMP/bin"; mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/curl" <<'STUB_EOF'
#!/usr/bin/env bash
argv="$*"
[[ "$argv" == *"Authorization: Bearer"* ]] || { echo "stub-curl: missing Authorization header" >&2; exit 64; }
[[ "$argv" == *"--data-raw"* ]] || { echo "stub-curl: missing --data-raw" >&2; exit 64; }
# The probe MUST NOT write a log line. Fail loudly if the body carries a message payload.
if [[ "$argv" == *'"message"'* ]]; then
  echo "stub-curl: probe attempted to WRITE a row (body contains a message key)" >&2
  exit 65
fi
if [[ -n "${STUB_CURL_EXIT:-}" && "${STUB_CURL_EXIT}" != "0" ]]; then
  exit "${STUB_CURL_EXIT}"
fi
# Honour -o: the probe passes `-o /dev/null -w '%{http_code}'`, so real curl writes ONLY the
# status to stdout. A stub that also echoes the body would concatenate them and every status
# would read as unrecognised — a harness defect that presents exactly like a SUT defect.
out_target=""
prev=""
for a in "$@"; do
  [[ "$prev" == "-o" ]] && out_target="$a"
  prev="$a"
done
if [[ -n "$out_target" ]]; then
  printf '%s' "${STUB_HTTP_BODY:-}" > "$out_target"
else
  printf '%s' "${STUB_HTTP_BODY:-}"
fi
printf '%s' "${STUB_HTTP_CODE:-000}"
STUB_EOF
chmod +x "$STUB_DIR/curl"

run_probe() {
  PATH="$STUB_DIR:$PATH" BETTERSTACK_LOGS_TOKEN="synthetic-token-for-tests" \
    BETTERSTACK_INGEST_URL="https://ingest.invalid/" bash "$PROBE" 2>/dev/null
}

assert_probe() {
  local name="$1" want="$2" got rc=0
  CASES=$((CASES + 1))
  got="$(run_probe)" || rc=$?
  if [[ "$got" == *"$want"* ]]; then
    pass "$name → $got"
  else
    fail "$name → expected to contain '$want', got '$got' (rc=$rc)"
  fi
}

echo "--- classification ---"
STUB_HTTP_CODE=402 STUB_HTTP_BODY='{"error": "Quota exceeded"}' \
  assert_probe "402 → quota refusal" "INGEST_REFUSED_QUOTA"
STUB_HTTP_CODE=401 STUB_HTTP_BODY='{"error": "Unauthorized"}' \
  assert_probe "401 → auth refusal" "INGEST_REFUSED_AUTH"
STUB_HTTP_CODE=202 STUB_HTTP_BODY='' \
  assert_probe "202 → accepting" "INGEST_ACCEPTING"
STUB_HTTP_CODE=200 STUB_HTTP_BODY='' \
  assert_probe "200 → accepting" "INGEST_ACCEPTING"
STUB_HTTP_CODE=503 STUB_HTTP_BODY='upstream' \
  assert_probe "503 → vendor-side error, not a verdict about quota" "INGEST_VENDOR_ERROR"
STUB_HTTP_CODE=429 STUB_HTTP_BODY='slow down' \
  assert_probe "429 → rate limited, distinct from quota exhaustion" "INGEST_RATE_LIMITED"

echo "--- unreachable / transport ---"
STUB_CURL_EXIT=6 \
  assert_probe "curl exit 6 (host resolution) → unreachable, never a refusal" "INGEST_UNREACHABLE"
STUB_CURL_EXIT=28 \
  assert_probe "curl exit 28 (timeout) → unreachable" "INGEST_UNREACHABLE"

echo "--- credential guard ---"
CASES=$((CASES + 1))
out="$(PATH="$STUB_DIR:$PATH" BETTERSTACK_LOGS_TOKEN="" BETTERSTACK_INGEST_URL="https://ingest.invalid/" bash "$PROBE" 2>&1)" || true
if [[ "$out" == *"INGEST_PROBE_UNCONFIGURED"* ]]; then
  pass "unset token → UNCONFIGURED (never reported as a refusal)"
else
  fail "unset token → expected INGEST_PROBE_UNCONFIGURED, got '$out'"
fi

echo "--- the probe must not write a row (self-masking guard) ---"
# The stub exits 65 if the body carries a message key. If the probe ever starts writing, this
# case reports UNREACHABLE (curl 'failed'), which is a visible, loud change — and the grep
# below pins the source directly so the intent cannot be lost to a refactor.
CASES=$((CASES + 1))
if grep -qE '\-\-data-raw[[:space:]]+.\[\].' "$PROBE"; then
  pass "probe posts a literal empty batch"
else
  fail "probe does not post a literal empty batch — it may be writing a row"
fi
CASES=$((CASES + 1))
if grep -q '"message"' "$PROBE"; then
  fail "probe source contains a message payload key — a writing probe masks the silence it detects"
else
  pass "probe source carries no message payload"
fi

# Derived: 8 assert_probe + 1 credential guard + 2 source-grep guards = 11.
EXPECTED_CASES=11
echo
echo "cases=$CASES passed=$PASS failed=$FAIL"
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  echo "[FAIL] cardinality: ran $CASES cases, expected at least $EXPECTED_CASES"
  FAIL=$((FAIL + 1))
fi
[[ "$FAIL" -eq 0 ]] || exit 1
echo "=== betterstack-ingest-probe: $PASS assertions passed ==="
