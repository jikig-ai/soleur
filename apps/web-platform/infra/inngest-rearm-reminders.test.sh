#!/usr/bin/env bash
# Tests for inngest-rearm-reminders.sh — the no-SSH cutover re-arm executor
# (#5450, AC2/B2). Consumes the enumeration records (stdin) and re-POSTs each to
# POST /api/internal/schedule-reminder so a dropped reminder fires against the
# fresh backend. Verifies: the POST body carries reminder_id/fire_at/actor/action
# (the route recomputes the inngest dedup id/ts so no double-fire); a 503 (quiesce
# still set) ABORTS LOUD (ordering guard, B2-iii) rather than silently dropping;
# a non-202/503 is a hard failure.
#
# Test seam: a mock `curl` on PATH records the request + returns a scripted HTTP
# code (MOCK_HTTP_CODE). INNGEST_MANUAL_TRIGGER_SECRET is set directly so no
# Doppler call is made.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-rearm-reminders.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc — '$needle' not found"; FAIL=$((FAIL + 1)); fi
}

MOCKBIN=""
REQ_LOG=""
setup_mock_curl() {
  local http_code="$1"
  MOCKBIN=$(mktemp -d)
  REQ_LOG="${MOCKBIN}/requests.log"
  : > "$REQ_LOG"
  cat > "${MOCKBIN}/curl" <<MOCK
#!/usr/bin/env bash
# Mock curl: record args + any --data-binary/-d body, emit the scripted code on stdout
# (the script invokes curl with -w '%{http_code}' -o <bodyfile>).
body=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    --data-binary|-d) body="\$a" ;;
    -o) : > "\$a" 2>/dev/null || true ;;
  esac
  prev="\$a"
done
{ echo "ARGS: \$*"; echo "BODY: \$body"; } >> "$REQ_LOG"
printf '%s' "${http_code}"
MOCK
  chmod +x "${MOCKBIN}/curl"
}
teardown_mock_curl() { rm -rf "$MOCKBIN"; MOCKBIN=""; }

run_rearm() {
  local records="$1"
  printf '%s' "$records" | \
    PATH="${MOCKBIN}:$PATH" \
    INNGEST_REARM_STDIN=1 \
    INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/api/internal/schedule-reminder" \
    bash "$TARGET" 2>&1
}

echo "=== inngest-rearm-reminders.sh tests ==="
assert_eq "script exists and is executable" "1" "$([[ -x "$TARGET" ]] && echo 1 || echo 0)"

REC='[{"reminder_id":"rem-1","fire_at":"2026-06-18T12:00:00Z","actor":"platform","action":{"type":"issue-comment","issue":7,"body":"x"}},{"reminder_id":"rem-2","fire_at":"2026-06-20T09:00:00Z","actor":"platform","action":{"type":"named-check","check":"otel"}}]'

# --- Test 1: happy path (202) re-arms each record with the full route body ---
test_happy_rearm() {
  setup_mock_curl 202
  local out rc=0
  out=$(run_rearm "$REC") || rc=$?
  assert_eq "exits 0 when all re-arms return 202" "0" "$rc"
  local n; n=$(grep -c '^BODY:' "$REQ_LOG")
  assert_eq "one POST per record" "2" "$n"
  local bodies; bodies=$(grep '^BODY:' "$REQ_LOG")
  assert_contains "body carries reminder_id (route recomputes dedup id)" "$bodies" '"reminder_id":"rem-1"'
  assert_contains "body carries fire_at (route recomputes dedup ts)" "$bodies" '"fire_at":"2026-06-18T12:00:00Z"'
  assert_contains "body carries actor:platform (route 400s without it)" "$bodies" '"actor":"platform"'
  assert_contains "body carries the action object" "$bodies" '"named-check"'
  local args; args=$(grep '^ARGS:' "$REQ_LOG" | head -1)
  assert_contains "Authorization Bearer header sent" "$args" "Authorization: Bearer test-secret"
  teardown_mock_curl
}

# --- Test 2: 503 (quiesce still set) ABORTS LOUD — ordering guard (B2-iii) ---
test_503_aborts_loud() {
  setup_mock_curl 503
  local out rc=0
  out=$(run_rearm "$REC") || rc=$?
  assert_eq "exits non-zero on 503 (does NOT silently drop)" "1" "$rc"
  assert_contains "names INNGEST_CUTOVER_QUIESCE as the cause" "$out" "INNGEST_CUTOVER_QUIESCE"
  # Must abort on the FIRST 503, not attempt the rest blindly.
  local n; n=$(grep -c '^BODY:' "$REQ_LOG")
  assert_eq "aborts on first 503 (only 1 POST attempted)" "1" "$n"
  teardown_mock_curl
}

# --- Test 3: other non-202 (e.g. 401/502) is a hard failure ---
test_other_failure() {
  setup_mock_curl 401
  local rc=0
  run_rearm "$REC" >/dev/null 2>&1 || rc=$?
  assert_eq "exits non-zero on 401" "1" "$rc"
  teardown_mock_curl
}

# --- Test 4: empty record set is a clean no-op (exit 0) ---
test_empty_noop() {
  setup_mock_curl 202
  local rc=0
  run_rearm "[]" >/dev/null 2>&1 || rc=$?
  assert_eq "empty record set exits 0" "0" "$rc"
  local n; n=$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null) || true
  assert_eq "no POST for empty set" "0" "$n"
  teardown_mock_curl
}

# --- Test 5: missing secret fails closed (no unauthenticated POST) ---
test_missing_secret_fails_closed() {
  setup_mock_curl 202
  local rc=0
  printf '%s' "$REC" | PATH="${MOCKBIN}:$PATH" SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/x" \
    INNGEST_MANUAL_TRIGGER_SECRET="" INNGEST_REARM_SKIP_DOPPLER=1 bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "fails closed when secret unavailable" "1" "$rc"
  teardown_mock_curl
}

# --- Test 6: webhook path (no stdin) self-enumerates via INNGEST_ENUMERATE_CMD ---
test_self_enumerate_default() {
  setup_mock_curl 202
  local enum_stub; enum_stub="${MOCKBIN}/enum.sh"
  cat > "$enum_stub" <<MOCK
#!/usr/bin/env bash
printf '%s' '[{"reminder_id":"rem-enum","fire_at":"2026-06-18T12:00:00Z","actor":"platform","action":{"type":"named-check","check":"x","report_to_issue":9}}]'
MOCK
  chmod +x "$enum_stub"
  local rc=0 out
  out=$(PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_ENUMERATE_CMD="$enum_stub" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/no-such-capture.json" \
    SCHEDULE_REMINDER_URL="http://127.0.0.1:3000/api/internal/schedule-reminder" \
    bash "$TARGET" 2>&1) || rc=$?
  assert_eq "self-enumerate path exits 0" "0" "$rc"
  local bodies; bodies=$(grep '^BODY:' "$REQ_LOG")
  assert_contains "re-armed the self-enumerated record" "$bodies" '"reminder_id":"rem-enum"'
  teardown_mock_curl
}

# --- Test 7: capture mode (#5542) — self-enumerate the OLD server + persist on-host ---
test_capture_mode_persists() {
  setup_mock_curl 200
  local enum_stub cap_file; enum_stub="${MOCKBIN}/enum.sh"; cap_file="${MOCKBIN}/capture.json"
  cat > "$enum_stub" <<MOCK
#!/usr/bin/env bash
printf '%s' '[{"reminder_id":"rem-cap","fire_at":"2026-07-01T00:00:00Z","actor":"platform","action":{"type":"named-check","check":"reeval"}}]'
MOCK
  chmod +x "$enum_stub"
  local rc=0 out
  out=$(PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_REARM_MODE=capture \
    INNGEST_ENUMERATE_CMD="$enum_stub" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" 2>/dev/null) || rc=$?
  assert_eq "capture mode exits 0" "0" "$rc"
  assert_eq "capture wrote the on-host file" "1" "$([[ -s "$cap_file" ]] && echo 1 || echo 0)"
  assert_contains "capture file holds the enumerated record" "$(cat "$cap_file")" '"reminder_id":"rem-cap"'
  assert_contains "capture status reports count" "$out" '"captured":1'
  assert_contains "capture status surfaces reminder_ids" "$out" 'rem-cap'
  assert_eq "capture made NO re-arm POST (capture != rearm)" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  teardown_mock_curl
}

# --- Test 8: rearm consumes the capture file over self-enumerate, deletes on success ---
test_rearm_consumes_capture_file() {
  setup_mock_curl 202
  local enum_stub cap_file; enum_stub="${MOCKBIN}/enum.sh"; cap_file="${MOCKBIN}/capture.json"
  # self-enumerate would return a DIFFERENT record — prove the capture file wins.
  cat > "$enum_stub" <<MOCK
#!/usr/bin/env bash
printf '%s' '[{"reminder_id":"rem-SELF","fire_at":"2026-06-19T00:00:00Z","actor":"platform","action":{"type":"x"}}]'
MOCK
  chmod +x "$enum_stub"
  printf '%s' '[{"reminder_id":"rem-CAPTURED","fire_at":"2026-07-01T00:00:00Z","actor":"platform","action":{"type":"named-check","check":"reeval"}}]' > "$cap_file"
  local rc=0
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_ENUMERATE_CMD="$enum_stub" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "rearm-from-capture exits 0" "0" "$rc"
  local bodies; bodies=$(grep '^BODY:' "$REQ_LOG")
  assert_contains "re-armed the CAPTURED record" "$bodies" '"reminder_id":"rem-CAPTURED"'
  assert_eq "did NOT re-arm the self-enumerated record" "0" "$(echo "$bodies" | grep -c 'rem-SELF' || true)"
  assert_eq "capture file deleted after full success" "0" "$([[ -e "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

# --- Test 9: rearm RETAINS the capture file when a re-arm POST fails (retry-safe) ---
test_rearm_keeps_capture_on_failure() {
  setup_mock_curl 401
  local cap_file; cap_file="${MOCKBIN}/capture.json"
  printf '%s' '[{"reminder_id":"rem-X","fire_at":"2026-07-01T00:00:00Z","actor":"platform","action":{"type":"x"}}]' > "$cap_file"
  local rc=0
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_ENUMERATE_CMD="/bin/false" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "rearm exits non-zero when a POST fails" "1" "$rc"
  assert_eq "capture file RETAINED on failure (retry-safe)" "1" "$([[ -s "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

test_happy_rearm
test_503_aborts_loud
test_other_failure
test_empty_noop
test_missing_secret_fails_closed
test_self_enumerate_default
test_capture_mode_persists
test_rearm_consumes_capture_file
test_rearm_keeps_capture_on_failure

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
