#!/usr/bin/env bash
# Tests for inngest-rearm-reminders.sh — the no-SSH cutover re-arm executor
# (#5450, AC2/B2). Consumes the enumeration records (stdin) and re-POSTs each to
# POST /api/internal/schedule-reminder so a dropped reminder fires against the
# fresh backend. Verifies: the POST body carries reminder_id/fire_at/actor/action
# (the route derives the event id from reminder_id, which inngest dedups on, and the
# delivery ts from fire_at, which is NOT part of the dedup key); a 503 (quiesce
# still set) ABORTS LOUD (ordering guard, B2-iii) rather than silently dropping;
# a non-202/503 is a hard failure.
#
# Test seam: a mock `curl` on PATH records the request + returns a scripted HTTP
# code (MOCK_HTTP_CODE). INNGEST_MANUAL_TRIGGER_SECRET is set directly so no
# Doppler call is made. A mock `systemctl` (MOCK_SYSTEMCTL_ACTIVE printed by
# is-active, MOCK_SYSTEMCTL_ENABLED_STATE printed by is-enabled, each verb appended
# to systemctl.verbs.log) drives the capture branch's quiesced-shape predicate
# (#6921), and a mock `doppler` is a TRIPWIRE: it prints nothing, logs its call and
# exits 1, so a secret-less row can never reach the developer's real Doppler CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-rearm-reminders.sh"

# Canonical copy of plugins/soleur/test/test-helpers.sh's guard (the fixture-dir-operand-assert
# suite pins every tracked copy byte-identical). Executed as a statement before every write under
# "$MOCKBIN" in the #6921 rows so the P1b relative-operand ratchet can see the operand is absolute.
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
  # Mock systemctl (#6921): the real verbs' stdout AND exit codes, because the predicate reads
  # stdout under `|| true` and a mock that exited 0 for every state would hide an rc-keyed rewrite.
  # is-active: `active` rc 0, anything else rc 3. is-enabled: `enabled` rc 0, `not-found` rc 4
  # (unit absent, systemd >= 253), anything else (`disabled`) rc 1. Defaults are the SERVING shape.
  cat > "${MOCKBIN}/systemctl" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/systemctl.verbs.log"
case "\$1" in
  is-active)
    st="\${MOCK_SYSTEMCTL_ACTIVE:-active}"; printf '%s\n' "\$st"
    [[ "\$st" == active ]] && exit 0; exit 3 ;;
  is-enabled)
    st="\${MOCK_SYSTEMCTL_ENABLED_STATE:-enabled}"; printf '%s\n' "\$st"
    case "\$st" in enabled) exit 0 ;; not-found) exit 4 ;; *) exit 1 ;; esac ;;
esac
exit 0
MOCK
  chmod +x "${MOCKBIN}/systemctl"
  # Mock logger: records what would have gone to journald.
  cat > "${MOCKBIN}/logger" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/logger.log"
MOCK
  chmod +x "${MOCKBIN}/logger"
  # Doppler TRIPWIRE: shadows any real CLI on the developer's PATH; never prints a value.
  cat > "${MOCKBIN}/doppler" <<MOCK
#!/usr/bin/env bash
echo "ARGS=\$*" >> "${MOCKBIN}/doppler.log"
exit 1
MOCK
  chmod +x "${MOCKBIN}/doppler"
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
  assert_contains "body carries reminder_id (route derives the dedup event id)" "$bodies" '"reminder_id":"rem-1"'
  assert_contains "body carries fire_at (route derives the delivery ts)" "$bodies" '"fire_at":"2026-06-18T12:00:00Z"'
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
    INNGEST_REARM_MODE=rearm-from-capture \
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
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD="/bin/false" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "rearm exits non-zero when a POST fails" "1" "$rc"
  assert_eq "capture file RETAINED on failure (retry-safe)" "1" "$([[ -s "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

# --- Test 10 (#5542 review F1): rearm-from-capture with a MISSING capture is FATAL ---
# (never silently self-enumerates the empty post-deploy backend).
test_rearm_from_capture_missing_is_fatal() {
  setup_mock_curl 202
  local rc=0 out
  out=$(PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD="/bin/false" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/absent-capture.json" \
    bash "$TARGET" 2>&1) || rc=$?
  assert_eq "missing capture is FATAL (exit 1)" "1" "$rc"
  assert_contains "names the refusal-to-self-enumerate cause" "$out" "missing/empty/corrupt"
  assert_eq "no re-arm POST attempted on fatal-missing-capture" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  teardown_mock_curl
}

# --- Test 11 (#5542 review F1): rearm-from-capture with a TRUNCATED (non-array) capture is FATAL ---
test_rearm_from_capture_corrupt_is_fatal() {
  setup_mock_curl 202
  local cap_file; cap_file="${MOCKBIN}/capture.json"
  printf '%s' '[{"reminder_id":"rem-trunc"' > "$cap_file"   # truncated mid-write, invalid JSON
  local rc=0 out
  out=$(PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD="/bin/false" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" 2>&1) || rc=$?
  assert_eq "corrupt capture is FATAL (exit 1)" "1" "$rc"
  assert_eq "corrupt capture RETAINED (operator inspects)" "1" "$([[ -s "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

# --- Test 12 (#5542 review F3): steady-state rearm IGNORES an orphan capture file ---
# (an aborted cutover must not hijack a routine self-enumerate re-arm).
test_steady_state_rearm_ignores_orphan_capture() {
  setup_mock_curl 202
  local enum_stub cap_file; enum_stub="${MOCKBIN}/enum.sh"; cap_file="${MOCKBIN}/capture.json"
  cat > "$enum_stub" <<MOCK
#!/usr/bin/env bash
printf '%s' '[{"reminder_id":"rem-LIVE","fire_at":"2026-06-19T00:00:00Z","actor":"platform","action":{"type":"x"}}]'
MOCK
  chmod +x "$enum_stub"
  # An orphaned capture from a prior aborted cutover sits on disk.
  printf '%s' '[{"reminder_id":"rem-ORPHAN","fire_at":"2026-07-01T00:00:00Z","actor":"platform","action":{"type":"x"}}]' > "$cap_file"
  local rc=0
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_ENUMERATE_CMD="$enum_stub" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "steady-state rearm exits 0" "0" "$rc"
  local bodies; bodies=$(grep '^BODY:' "$REQ_LOG")
  assert_contains "re-armed the LIVE self-enumerated record" "$bodies" '"reminder_id":"rem-LIVE"'
  assert_eq "did NOT consume the orphan capture" "0" "$(echo "$bodies" | grep -c 'rem-ORPHAN' || true)"
  assert_eq "orphan capture left intact (not deleted by steady-state)" "1" "$([[ -s "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

# --- Test 13 (#5542 review F7): rearm-from-capture with an EMPTY [] capture is a clean no-op ---
test_rearm_from_capture_empty_array_noop() {
  setup_mock_curl 202
  local cap_file; cap_file="${MOCKBIN}/capture.json"
  printf '%s' '[]' > "$cap_file"
  local rc=0
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD="/bin/false" \
    INNGEST_CUTOVER_CAPTURE_FILE="$cap_file" \
    bash "$TARGET" >/dev/null 2>&1 || rc=$?
  assert_eq "empty [] capture exits 0 (nothing to re-arm)" "0" "$rc"
  assert_eq "empty [] capture made no POST" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  assert_eq "empty [] capture deleted after no-op success" "0" "$([[ -e "$cap_file" ]] && echo 1 || echo 0)"
  teardown_mock_curl
}

# --- #6921 capture-resume rows (Guard 4) -----------------------------------------------------
# write_enum_stub <records|FAIL>: an enumerate stub that touches enum.invoked (so a row can prove
# the live enumeration was, or was NOT, attempted) then prints the records or exits 99.
write_enum_stub() {
  assert_fixture_dir "$MOCKBIN"
  if [[ "$1" == FAIL ]]; then
    printf '#!/usr/bin/env bash\ntouch "%s/enum.invoked"\nexit 99\n' "$MOCKBIN" > "${MOCKBIN}/enum.sh"
  else
    printf '#!/usr/bin/env bash\ntouch "%s/enum.invoked"\nprintf '"'"'%%s'"'"' '"'"'%s'"'"'\n' "$MOCKBIN" "$1" > "${MOCKBIN}/enum.sh"
  fi
  chmod +x "${MOCKBIN}/enum.sh"
}
# run_capture <is-active> <is-enabled>: capture mode against the mock unit; stdout -> cap.out,
# stderr -> cap.err. The secret IS set, so the predicate is the only variable under test.
run_capture() {
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    MOCK_SYSTEMCTL_ACTIVE="$1" MOCK_SYSTEMCTL_ENABLED_STATE="$2" \
    INNGEST_REARM_MODE=capture \
    INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/cap.out" 2>"${MOCKBIN}/cap.err" || rc=$?
  return "$rc"
}
REC2='[{"reminder_id":"rem-p1","fire_at":"2026-09-20T12:00:00Z","actor":"platform","action":{"type":"x"}},{"reminder_id":"rem-p2","fire_at":"2026-09-21T12:00:00Z","actor":"platform","action":{"type":"x"}}]'
seed_capture() {
  assert_fixture_dir "$MOCKBIN"
  printf '%s' "$1" > "${MOCKBIN}/capture.json"
  touch -d '2026-09-13T10:11:12Z' "${MOCKBIN}/capture.json"
}
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }

test_capture_resumes_persisted_when_quiesced() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"
  local before rc=0; before=$(sha_of "${MOCKBIN}/capture.json")
  run_capture inactive disabled || rc=$?
  local out; out=$(cat "${MOCKBIN}/cap.out")
  assert_eq "quiesced resume: exits 0" "0" "$rc"
  assert_eq "quiesced resume: source is persisted" "persisted" "$(printf '%s' "$out" | jq -r '.source // "live"' 2>/dev/null)"
  assert_eq "quiesced resume: captured counts the persisted records" "2" "$(printf '%s' "$out" | jq -r '.captured' 2>/dev/null)"
  assert_eq "quiesced resume: reminder_ids are the persisted ids" "rem-p1,rem-p2" "$(printf '%s' "$out" | jq -r '.reminder_ids | join(",")' 2>/dev/null)"
  assert_eq "quiesced resume: captured_at is the file mtime, ISO-8601 UTC" "2026-09-13T10:11:12Z" "$(printf '%s' "$out" | jq -r '.captured_at' 2>/dev/null)"
  assert_eq "quiesced resume: capture_file names the persisted file" "${MOCKBIN}/capture.json" "$(printf '%s' "$out" | jq -r '.capture_file' 2>/dev/null)"
  assert_eq "quiesced resume: live enumeration NOT invoked (stub marker absent)" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "quiesced resume: persisted file unchanged (sha256)" "$before" "$(sha_of "${MOCKBIN}/capture.json")"
  assert_eq "quiesced resume: the predicate read the MOCK systemctl (verb log exists)" "1" "$(exists "${MOCKBIN}/systemctl.verbs.log")"
  assert_contains "quiesced resume: journald line names count + captured_at" "$(cat "${MOCKBIN}/logger.log" 2>/dev/null)" "resumed persisted capture: 2 reminder(s) captured_at=2026-09-13T10:11:12Z (scheduler quiesced)"
  assert_eq "quiesced resume: no re-arm POST" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  teardown_mock_curl
}

test_capture_failed_disabled_resumes_persisted() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"
  local rc=0; run_capture failed disabled || rc=$?
  assert_eq "failed+disabled (post-SIGKILL quiesce) resume: exits 0" "0" "$rc"
  assert_eq "failed+disabled resume: source is persisted" "persisted" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "failed+disabled resume: live enumeration NOT invoked" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  teardown_mock_curl
}

test_capture_quiesced_empty_array_is_valid() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture '[]'
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "quiesced [] persisted: exits 0 (an empty capture is a capture)" "0" "$rc"
  assert_eq "quiesced [] persisted: captured 0" "0" "$(jq -r '.captured' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "quiesced [] persisted: source persisted" "persisted" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  teardown_mock_curl
}

test_capture_quiesced_without_file_fails_with_remedy() {
  setup_mock_curl 202
  write_enum_stub FAIL
  local rc=0; run_capture inactive disabled || rc=$?
  local err; err=$(cat "${MOCKBIN}/cap.err")
  assert_eq "quiesced, no file: exits 1" "1" "$rc"
  assert_contains "quiesced, no file: says nothing to resume from" "$err" "nothing to resume from"
  assert_contains "quiesced, no file: names op=rollback as the remedy" "$err" "op=rollback"
  assert_eq "quiesced, no file: live enumeration NOT attempted" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "quiesced, no file: no file fabricated" "0" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
}

test_capture_quiesced_corrupt_file_fails() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture '{}'
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "quiesced, non-array file ({}): exits 1" "1" "$rc"
  assert_contains "quiesced, non-array file: nothing to resume from" "$(cat "${MOCKBIN}/cap.err")" "nothing to resume from"
  assert_eq "quiesced, non-array file: never returned as a capture (no persisted status)" "0" "$(grep -c 'persisted' "${MOCKBIN}/cap.out" || true)"
  teardown_mock_curl
}

test_capture_serving_enumerates_live() {
  setup_mock_curl 202
  write_enum_stub '[{"reminder_id":"rem-live","fire_at":"2026-09-22T00:00:00Z","actor":"platform","action":{"type":"x"}}]'
  seed_capture "$REC2"
  local rc=0; run_capture active enabled || rc=$?
  assert_eq "serving: exits 0" "0" "$rc"
  assert_eq "serving: source reads live (field absent; CI reads .source // \"live\")" "live" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "serving: live response shape unchanged (no source/captured_at keys)" "capture_file,captured,reminder_ids" "$(jq -r 'keys | join(",")' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "serving: live enumeration invoked" "1" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_contains "serving: persisted file overwritten with the enumerated record" "$(cat "${MOCKBIN}/capture.json")" '"reminder_id":"rem-live"'
  assert_eq "serving: stale records gone from the file" "0" "$(grep -c 'rem-p1' "${MOCKBIN}/capture.json" || true)"
  teardown_mock_curl
}

test_capture_health_down_but_enabled_does_not_resume() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"
  local rc=0; run_capture inactive enabled || rc=$?
  assert_eq "inactive+ENABLED (crash loop): exits 1" "1" "$rc"
  assert_contains "inactive+ENABLED: enumeration failed (no stale-file resume)" "$(cat "${MOCKBIN}/cap.err")" "enumeration failed"
  assert_eq "inactive+ENABLED: live enumeration attempted" "1" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "inactive+ENABLED: no persisted status emitted" "0" "$(grep -c 'persisted' "${MOCKBIN}/cap.out" || true)"
  teardown_mock_curl
}

test_capture_unit_not_found_does_not_resume() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"
  local rc=0; run_capture inactive not-found || rc=$?
  assert_eq "inactive+not-found (unit absent, rc 4): exits 1" "1" "$rc"
  assert_eq "inactive+not-found: live enumeration attempted (never the file)" "1" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "inactive+not-found: no persisted status emitted" "0" "$(grep -c 'persisted' "${MOCKBIN}/cap.out" || true)"
  teardown_mock_curl
}

test_capture_needs_no_secret() {
  setup_mock_curl 202
  write_enum_stub '[{"reminder_id":"rem-ns","fire_at":"2026-09-22T00:00:00Z","actor":"platform","action":{"type":"x"}}]'
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  env -u INNGEST_MANUAL_TRIGGER_SECRET -u INNGEST_REARM_SKIP_DOPPLER -u DOPPLER_TOKEN \
    PATH="${MOCKBIN}:$PATH" \
    SOLEUR_DOPPLER_TOKEN_FILE="${MOCKBIN}/no-such-token-file" \
    MOCK_SYSTEMCTL_ACTIVE=active MOCK_SYSTEMCTL_ENABLED_STATE=enabled \
    INNGEST_REARM_MODE=capture \
    INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/cap.out" 2>"${MOCKBIN}/cap.err" || rc=$?
  assert_eq "capture without any secret: exits 0" "0" "$rc"
  assert_contains "capture without any secret: file written" "$(cat "${MOCKBIN}/capture.json" 2>/dev/null)" '"reminder_id":"rem-ns"'
  assert_eq "capture without any secret: doppler never invoked (tripwire log absent)" "0" "$(exists "${MOCKBIN}/doppler.log")"
  teardown_mock_curl
}

test_rearm_still_fails_closed_without_secret() {
  setup_mock_curl 202
  seed_capture "$REC2"
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  env -u INNGEST_MANUAL_TRIGGER_SECRET -u DOPPLER_TOKEN PATH="${MOCKBIN}:$PATH" INNGEST_REARM_SKIP_DOPPLER=1 \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD=/bin/false \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/cap.out" 2>"${MOCKBIN}/cap.err" || rc=$?
  assert_eq "rearm-from-capture without a secret: exits 1 (fail closed)" "1" "$rc"
  assert_contains "rearm-from-capture without a secret: names the secret" "$(cat "${MOCKBIN}/cap.err")" "INNGEST_MANUAL_TRIGGER_SECRET unavailable"
  assert_eq "rearm-from-capture without a secret: no POST" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  assert_eq "rearm-from-capture without a secret: capture retained" "1" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
}

test_rearm_empty_capture_emits_canonical_line() {
  setup_mock_curl 202
  seed_capture '[]'
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD=/bin/false \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/cap.out" 2>"${MOCKBIN}/cap.err" || rc=$?
  assert_eq "Σ=0 re-arm: exits 0" "0" "$rc"
  assert_contains "Σ=0 re-arm: stderr carries the canonical parseable line" "$(cat "${MOCKBIN}/cap.err")" "inngest-rearm-reminders: re-armed=0 failed=0 total=0"
  assert_eq "Σ=0 re-arm: canonical line is NOT on stdout (same stream as the non-empty path)" "0" "$(grep -c 're-armed=' "${MOCKBIN}/cap.out" || true)"
  assert_eq "Σ=0 re-arm: consumed capture removed" "0" "$(exists "${MOCKBIN}/capture.json")"
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
test_rearm_from_capture_missing_is_fatal
test_rearm_from_capture_corrupt_is_fatal
test_steady_state_rearm_ignores_orphan_capture
test_rearm_from_capture_empty_array_noop
test_capture_resumes_persisted_when_quiesced
test_capture_failed_disabled_resumes_persisted
test_capture_quiesced_empty_array_is_valid
test_capture_quiesced_without_file_fails_with_remedy
test_capture_quiesced_corrupt_file_fails
test_capture_serving_enumerates_live
test_capture_health_down_but_enabled_does_not_resume
test_capture_unit_not_found_does_not_resume
test_capture_needs_no_secret
test_rearm_still_fails_closed_without_secret
test_rearm_empty_capture_emits_canonical_line

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact assertion-count floor (ADR-193): reported via printf + exit, never through
# pass()/fail(), so a neutered helper or a vanished test function cannot read green.
EXPECTED_ASSERTIONS=90
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf 'ASSERTION FLOOR: executed %d assertion(s), expected exactly %d\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
