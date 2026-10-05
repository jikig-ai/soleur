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
# Review-fix contract §5 seams: `systemctl show -p ActiveEnterTimestamp --value` prints
# MOCK_SYSTEMCTL_AET; INNGEST_QUIESCE_MARKER / INNGEST_BOOT_ID_FILE point under the fixture; the mock
# curl writes `-D` response headers carrying X-Soleur-Unavailable=$MOCK_UNAVAILABLE.
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

# Helper SELF-TEST (#6921 review X7): neutering assert_eq/assert_contains (e.g. an always-PASS body)
# left the suite green, so each helper is driven once with a FALSE and once with a TRUE condition
# and must move the counters the right way. Counters are snapshotted and restored, and the verdict
# is reported through printf + exit — never through the helpers under test.
_selftest_pass=$PASS _selftest_fail=$FAIL
assert_eq "selftest: a mismatch must count as FAIL" "a" "b" >/dev/null
assert_contains "selftest: an absent needle must count as FAIL" "haystack" "needle" >/dev/null
if (( FAIL != _selftest_fail + 2 || PASS != _selftest_pass )); then
  printf 'HELPER SELF-TEST: a false condition did not register as FAIL (pass %d->%d, fail %d->%d)\n' "$_selftest_pass" "$PASS" "$_selftest_fail" "$FAIL" >&2
  exit 1
fi
assert_eq "selftest: a match must count as PASS" "a" "a" >/dev/null
assert_contains "selftest: a present needle must count as PASS" "haystack" "stack" >/dev/null
if (( PASS != _selftest_pass + 2 || FAIL != _selftest_fail + 2 )); then
  printf 'HELPER SELF-TEST: a true condition did not register as PASS (pass %d->%d, fail %d->%d)\n' "$_selftest_pass" "$PASS" "$_selftest_fail" "$FAIL" >&2
  exit 1
fi
PASS=$_selftest_pass FAIL=$_selftest_fail

# Synthetic boot ids (the shape of /proc/sys/kernel/random/boot_id) and the quiesce instant every
# marker row uses: 2026-09-13T10:11:12Z.
readonly BOOT_A="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
readonly BOOT_B="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
readonly QUIESCE_EPOCH=1789294272
readonly QUIESCE_ISO="2026-09-13T10:11:12Z"

MOCKBIN=""
REQ_LOG=""
setup_mock_curl() {
  local http_code="$1"
  MOCKBIN=$(mktemp -d)
  assert_fixture_dir "$MOCKBIN"
  REQ_LOG="${MOCKBIN}/requests.log"
  # Hermetic quiesce seams (#6921 review): every row resolves the marker and boot_id under the
  # fixture, never the host's /var/lib/inngest or /proc. A row that wants a marker writes one.
  export INNGEST_QUIESCE_MARKER="${MOCKBIN}/quiesced-by-op"
  export INNGEST_BOOT_ID_FILE="${MOCKBIN}/boot_id"
  printf '%s\n' "$BOOT_A" > "${MOCKBIN}/boot_id"
  : > "$REQ_LOG"
  cat > "${MOCKBIN}/curl" <<MOCK
#!/usr/bin/env bash
# Mock curl: record args + any --data-binary/-d body, emit the scripted code on stdout
# (the script invokes curl with -w '%{http_code}' -o <bodyfile>).
# -D <file> (response headers, #6921 review): the status line, then X-Soleur-Unavailable when
# MOCK_UNAVAILABLE is set — the route's discriminator between its two 503s.
body=""
prev=""
hdr=""
for a in "\$@"; do
  case "\$prev" in
    --data-binary|-d) body="\$a" ;;
    -o) : > "\$a" 2>/dev/null || true ;;
    -D) hdr="\$a" ;;
  esac
  prev="\$a"
done
{ echo "ARGS: \$*"; echo "BODY: \$body"; } >> "$REQ_LOG"
if [[ -n "\$hdr" ]]; then
  { printf 'HTTP/1.1 %s\r\n' "${http_code}"
    if [[ -n "\${MOCK_UNAVAILABLE:-}" ]]; then printf 'X-Soleur-Unavailable: %s\r\n' "\$MOCK_UNAVAILABLE"; fi
    printf '\r\n'; } > "\$hdr"
fi
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
  show)
    # show -p <Property> --value <unit>. ActiveEnterTimestamp is empty after a reboot (the unit never
    # started this boot); InactiveEnterTimestamp is when the quiesce stop completed on this boot.
    case "\$3" in
      ActiveEnterTimestamp) printf '%s\n' "\${MOCK_SYSTEMCTL_AET-}" ;;
      InactiveEnterTimestamp) printf '%s\n' "\${MOCK_SYSTEMCTL_IET-}" ;;
      *) printf '\n' ;;
    esac
    exit 0 ;;
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
# A row that dies between setup and teardown (set -e) would orphan its fixture dir: the EXIT trap
# owns the current one (teardown is a no-op once MOCKBIN is cleared).
trap teardown_mock_curl EXIT

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
  assert_eq "503 with NO X-Soleur-Unavailable header is NOT reported as backend-refused" "0" "$(grep -c 'backend-refused' <<<"$out" || true)"
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

# --- #6921 capture-resume rows (Guard 4 + review-fix contract §5) ----------------------------
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
# run_capture <is-active> <is-enabled> [ActiveEnterTimestamp]: capture mode against the mock unit;
# stdout -> cap.out, stderr -> cap.err. The secret IS set, so the unit shape + marker are the only
# variables under test (the marker/boot_id seams are exported by setup_mock_curl).
run_capture() {
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    MOCK_SYSTEMCTL_ACTIVE="$1" MOCK_SYSTEMCTL_ENABLED_STATE="$2" MOCK_SYSTEMCTL_AET="${3-}" \
    INNGEST_REARM_MODE=capture \
    INNGEST_ENUMERATE_CMD="${MOCKBIN}/enum.sh" \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/cap.out" 2>"${MOCKBIN}/cap.err" || rc=$?
  return "$rc"
}
REC2='[{"reminder_id":"rem-p1","fire_at":"2026-09-20T12:00:00Z","actor":"platform","action":{"type":"x"}},{"reminder_id":"rem-p2","fire_at":"2026-09-21T12:00:00Z","actor":"platform","action":{"type":"x"}}]'
# seed_capture <json> [touch-date]: the persisted capture; default mtime is the quiesce instant.
seed_capture() {
  assert_fixture_dir "$MOCKBIN"
  printf '%s' "$1" > "${MOCKBIN}/capture.json"
  touch -d "${2:-$QUIESCE_ISO}" "${MOCKBIN}/capture.json"
}
sha_of() { sha256sum "$1" | cut -d' ' -f1; }
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }
# write_marker [capture_sha256] [capture_consumed_at]: the v1 quiesce marker ci-deploy.sh writes
# (contract §1). The sha defaults to the CURRENT capture.json's, i.e. a marker that owns the file.
write_marker() {
  local sha="${1:-}" consumed="${2:-}"
  assert_fixture_dir "$MOCKBIN"
  if [[ -z "$sha" ]]; then sha="$(sha_of "${MOCKBIN}/capture.json")"; fi
  jq -nc --argjson e "$QUIESCE_EPOCH" --arg b "$BOOT_A" --arg s "$sha" --arg c "$consumed" \
    '{v:1, epoch:$e, boot_id:$b, host_id:"web-1", run_id:"4242", capture_sha256:$s, capture_count:2}
     + (if $c == "" then {} else {capture_consumed_at: ($c | tonumber)} end)' > "${MOCKBIN}/quiesced-by-op"
}
cap_err() { cat "${MOCKBIN}/cap.err"; }
persisted_count() { grep -c 'persisted' "${MOCKBIN}/cap.out" || true; }

test_capture_resumes_persisted_when_quiesced() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2" '2026-09-01T00:00:00Z'; write_marker
  local before rc=0; before=$(sha_of "${MOCKBIN}/capture.json")
  run_capture inactive disabled "Sat 2026-09-12 08:00:00 UTC" || rc=$?
  local out; out=$(cat "${MOCKBIN}/cap.out")
  assert_eq "quiesced resume: exits 0" "0" "$rc"
  assert_eq "quiesced resume: source is persisted" "persisted" "$(printf '%s' "$out" | jq -r '.source // "live"' 2>/dev/null)"
  assert_eq "quiesced resume: captured counts the persisted records" "2" "$(printf '%s' "$out" | jq -r '.captured' 2>/dev/null)"
  assert_eq "quiesced resume: reminder_ids are the persisted ids" "rem-p1,rem-p2" "$(printf '%s' "$out" | jq -r '.reminder_ids | join(",")' 2>/dev/null)"
  assert_eq "quiesced resume: captured_at is the MARKER epoch, not the file mtime (ISO-8601 UTC)" "$QUIESCE_ISO" "$(printf '%s' "$out" | jq -r '.captured_at' 2>/dev/null)"
  assert_eq "quiesced resume: quiesced_since is the marker epoch (a number)" "$QUIESCE_EPOCH" "$(printf '%s' "$out" | jq -r 'if (.quiesced_since | type) == "number" then .quiesced_since else "not-a-number" end' 2>/dev/null)"
  assert_eq "quiesced resume: rebooted_since_quiesce is boolean false on the same boot" "false" "$(printf '%s' "$out" | jq -r 'if (.rebooted_since_quiesce | type) == "boolean" then .rebooted_since_quiesce else "not-a-bool" end' 2>/dev/null)"
  assert_eq "quiesced resume: capture_file names the persisted file" "${MOCKBIN}/capture.json" "$(printf '%s' "$out" | jq -r '.capture_file' 2>/dev/null)"
  assert_eq "quiesced resume: live enumeration NOT invoked (stub marker absent)" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "quiesced resume: persisted file unchanged (sha256)" "$before" "$(sha_of "${MOCKBIN}/capture.json")"
  assert_contains "quiesced resume: the tri-state read ActiveEnterTimestamp from the MOCK systemctl" "$(cat "${MOCKBIN}/systemctl.verbs.log" 2>/dev/null)" "show -p ActiveEnterTimestamp --value inngest-server.service"
  assert_contains "quiesced resume: journald line names count + captured_at" "$(cat "${MOCKBIN}/logger.log" 2>/dev/null)" "resumed persisted capture: 2 reminder(s) captured_at=$QUIESCE_ISO (scheduler quiesced)"
  assert_eq "quiesced resume: no re-arm POST" "0" "$(grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true)"
  teardown_mock_curl
}

test_capture_failed_disabled_resumes_persisted() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"; write_marker
  local rc=0; run_capture failed disabled || rc=$?
  assert_eq "failed+disabled (post-SIGKILL quiesce) with an owning marker: exits 0" "0" "$rc"
  assert_eq "failed+disabled resume: source is persisted" "persisted" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "failed+disabled resume: live enumeration NOT invoked" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  teardown_mock_curl
}

test_capture_quiesced_empty_array_is_valid() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture '[]'; write_marker
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "quiesced [] persisted: exits 0 (an empty capture is a capture)" "0" "$rc"
  assert_eq "quiesced [] persisted: captured 0" "0" "$(jq -r '.captured' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "quiesced [] persisted: source persisted" "persisted" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  teardown_mock_curl
}

# REPRODUCED review finding: a 13-day-old capture on a failed+disabled unit resumed with rc 0. With
# no quiesce marker the disabled shape is unattributed — refused, never answered from the file.
test_capture_stale_file_without_marker_is_unattributed() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2" '2026-09-01T00:00:00Z'
  local rc=0; run_capture failed disabled || rc=$?
  assert_eq "stale file, NO marker: exits 1" "1" "$rc"
  assert_contains "stale file, NO marker: refusal names capture_unattributed + the remedy" "$(cap_err)" "ERROR: capture: capture_unattributed — scheduler disabled with no valid quiesce marker; dispatch op=rollback, then op=quiesce-web"
  assert_eq "stale file, NO marker: no persisted status emitted" "0" "$(persisted_count)"
  assert_eq "stale file, NO marker: live enumeration NOT attempted" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  teardown_mock_curl
}

test_capture_marker_sha_mismatch_is_stale() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"
  write_marker "0000000000000000000000000000000000000000000000000000000000000000"
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "marker sha != capture sha: exits 1" "1" "$rc"
  assert_contains "marker sha mismatch: refusal names stale_capture + the remedy" "$(cap_err)" "ERROR: capture: stale_capture — the persisted capture does not match the quiesce marker ("
  assert_contains "marker sha mismatch: the reason names the sha" "$(cap_err)" "sha256"
  assert_contains "marker sha mismatch: remedy tail" "$(cap_err)" "); dispatch op=rollback, then op=quiesce-web to take a fresh capture"
  assert_eq "marker sha mismatch: no persisted status emitted" "0" "$(persisted_count)"
  teardown_mock_curl
}

test_capture_quiesced_without_file_is_stale() {
  setup_mock_curl 202
  write_enum_stub FAIL
  write_marker "1111111111111111111111111111111111111111111111111111111111111111"
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "quiesced, no file: exits 1" "1" "$rc"
  assert_contains "quiesced, no file: stale_capture refusal" "$(cap_err)" "ERROR: capture: stale_capture — the persisted capture does not match the quiesce marker ("
  assert_contains "quiesced, no file: names op=rollback as the remedy" "$(cap_err)" "op=rollback"
  assert_eq "quiesced, no file: live enumeration NOT attempted" "0" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "quiesced, no file: no file fabricated" "0" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
}

test_capture_quiesced_corrupt_file_fails() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture '{}'; write_marker
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "quiesced, non-array file ({}) even with a matching sha: exits 1" "1" "$rc"
  assert_contains "quiesced, non-array file: stale_capture refusal" "$(cap_err)" "stale_capture"
  assert_eq "quiesced, non-array file: never returned as a capture (no persisted status)" "0" "$(persisted_count)"
  teardown_mock_curl
}

test_capture_consumed_marker_is_already_rearmed() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"; write_marker "" 1789380000
  local rc=0; run_capture inactive disabled || rc=$?
  assert_eq "consumed marker: exits 1" "1" "$rc"
  assert_contains "consumed marker: already re-armed with the consumed-at ISO + remedy" "$(cap_err)" "ERROR: capture: already re-armed (capture consumed at 2026-09-14T10:00:00Z) — nothing to resume; if scheduling must reopen dispatch op=rollback"
  assert_eq "consumed marker: no persisted status emitted" "0" "$(persisted_count)"
  teardown_mock_curl
}

test_capture_reboot_is_still_quiesced() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"; write_marker
  assert_fixture_dir "$MOCKBIN"
  printf '%s\n' "$BOOT_B" > "${MOCKBIN}/boot_id"
  local rc=0; run_capture inactive disabled "" || rc=$?
  assert_eq "rebooted (new boot_id, empty ActiveEnterTimestamp): exits 0" "0" "$rc"
  assert_eq "rebooted: source persisted (an empty ActiveEnterTimestamp is NOT void)" "persisted" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "rebooted: rebooted_since_quiesce is boolean true" "true" "$(jq -r 'if (.rebooted_since_quiesce | type) == "boolean" then .rebooted_since_quiesce else "not-a-bool" end' "${MOCKBIN}/cap.out" 2>/dev/null)"
  teardown_mock_curl
}

test_capture_void_marker_is_unattributed() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"; write_marker
  # The unit entered active at 11:00Z, AFTER the 10:11:12Z quiesce: someone started it since.
  local rc=0; run_capture inactive disabled "Sun 2026-09-13 11:00:00 UTC" || rc=$?
  assert_eq "void marker (ActiveEnterTimestamp later than epoch): exits 1" "1" "$rc"
  assert_contains "void marker: capture_unattributed refusal" "$(cap_err)" "ERROR: capture: capture_unattributed — scheduler disabled with no valid quiesce marker"
  assert_eq "void marker: no persisted status emitted" "0" "$(persisted_count)"
  teardown_mock_curl
}

test_capture_serving_enumerates_live() {
  setup_mock_curl 202
  write_enum_stub '[{"reminder_id":"rem-live","fire_at":"2026-09-22T00:00:00Z","actor":"platform","action":{"type":"x"}}]'
  seed_capture "$REC2"; write_marker
  local rc=0; run_capture active enabled || rc=$?
  assert_eq "serving: exits 0" "0" "$rc"
  assert_eq "serving: source reads live (field absent; CI reads .source // \"live\")" "live" "$(jq -r '.source // "live"' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "serving: live response shape unchanged (no source/captured_at keys)" "capture_file,captured,reminder_ids" "$(jq -r 'keys | join(",")' "${MOCKBIN}/cap.out" 2>/dev/null)"
  assert_eq "serving: live enumeration invoked" "1" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_contains "serving: persisted file overwritten with the enumerated record" "$(cat "${MOCKBIN}/capture.json")" '"reminder_id":"rem-live"'
  assert_eq "serving: stale records gone from the file" "0" "$(grep -c 'rem-p1' "${MOCKBIN}/capture.json" || true)"
  assert_eq "serving: no capture temp file left beside the capture" "0" "$(find "$MOCKBIN" -maxdepth 1 -name 'capture.json.*' | grep -c . || true)"
  teardown_mock_curl
}

# live_row <is-active> <is-enabled> <label>: a not_quiesced shape with an owning marker AND a valid
# persisted capture on disk still enumerates LIVE; the failing stub proves the file is never read.
live_row() {
  setup_mock_curl 202
  write_enum_stub FAIL; seed_capture "$REC2"; write_marker
  local rc=0; run_capture "$1" "$2" || rc=$?
  assert_eq "$3: exits 1 (live enumeration failed)" "1" "$rc"
  assert_contains "$3: stderr names the live enumeration failure (no stale-file resume)" "$(cap_err)" "ERROR: capture: enumeration failed; nothing persisted"
  assert_eq "$3: live enumeration attempted" "1" "$(exists "${MOCKBIN}/enum.invoked")"
  assert_eq "$3: no persisted status emitted" "0" "$(persisted_count)"
  teardown_mock_curl
}
test_capture_not_quiesced_shapes_enumerate_live() {
  live_row inactive enabled "inactive+ENABLED (stopped but still enabled)"
  live_row activating enabled "activating+enabled (crash loop)"
  live_row active disabled "active+disabled (disabled but still serving)"
  live_row activating disabled "activating+disabled"
  live_row inactive masked "inactive+masked"
  live_row inactive static "inactive+static"
  live_row inactive not-found "inactive+not-found (unit absent, rc 4)"
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

# run_rfc [X-Soleur-Unavailable] [InactiveEnterTimestamp]: rearm-from-capture over capture.json (and
# the marker, if written);
# stdout -> rfc.out, stderr -> rfc.err. TMPDIR is private so a row can prove no temp file survives.
run_rfc() {
  local rc=0
  assert_fixture_dir "$MOCKBIN"
  mkdir -p "${MOCKBIN}/tmp"
  TMPDIR="${MOCKBIN}/tmp" PATH="${MOCKBIN}:$PATH" INNGEST_MANUAL_TRIGGER_SECRET="test-secret" MOCK_UNAVAILABLE="${1-}" \
    MOCK_SYSTEMCTL_IET="${2-}" \
    INNGEST_REARM_MODE=rearm-from-capture \
    INNGEST_ENUMERATE_CMD=/bin/false \
    INNGEST_CUTOVER_CAPTURE_FILE="${MOCKBIN}/capture.json" \
    bash "$TARGET" </dev/null >"${MOCKBIN}/rfc.out" 2>"${MOCKBIN}/rfc.err" || rc=$?
  return "$rc"
}
rfc_err() { cat "${MOCKBIN}/rfc.err"; }
posts() { grep -c '^BODY:' "$REQ_LOG" 2>/dev/null || true; }

test_rearm_empty_capture_emits_canonical_line() {
  setup_mock_curl 202
  seed_capture '[]'
  local rc=0; run_rfc || rc=$?
  assert_eq "Σ=0 re-arm: exits 0" "0" "$rc"
  assert_contains "Σ=0 re-arm: stderr carries the canonical parseable line (held_back field included)" "$(rfc_err)" "inngest-rearm-reminders: re-armed=0 failed=0 held_back=0 total=0"
  assert_eq "Σ=0 re-arm: canonical line is NOT on stdout (same stream as the non-empty path)" "0" "$(grep -c 're-armed=' "${MOCKBIN}/rfc.out" || true)"
  assert_eq "Σ=0 re-arm: consumed capture removed" "0" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
}

# Due at 09:00Z and exactly AT the quiesce instant (with millisecond precision) → held back; due a
# week later → re-armed. The first two already fired on the web scheduler before it stopped.
REC3='[{"reminder_id":"rem-early","fire_at":"2026-09-13T09:00:00Z","actor":"platform","action":{"type":"x"}},{"reminder_id":"rem-edge","fire_at":"2026-09-13T10:11:12.000Z","actor":"platform","action":{"type":"x"}},{"reminder_id":"rem-late","fire_at":"2026-09-20T12:00:00Z","actor":"platform","action":{"type":"x"}}]'

test_rearm_from_capture_holds_back_pre_quiesce_records() {
  setup_mock_curl 202
  seed_capture "$REC3"; write_marker
  local rc=0; run_rfc || rc=$?
  assert_eq "held back: exits 0 (a held-back record is not a failure)" "0" "$rc"
  assert_eq "held back: only the post-quiesce record is POSTed" "1" "$(posts)"
  assert_contains "held back: the POST is rem-late" "$(grep '^BODY:' "$REQ_LOG")" '"reminder_id":"rem-late"'
  assert_contains "held back: stderr names the count + ids due before the quiesce" "$(rfc_err)" "inngest-rearm-reminders: held back 2 reminder(s) due before the quiesce: rem-early,rem-edge"
  assert_contains "held back: canonical line reconciles N+F+H == K" "$(rfc_err)" "inngest-rearm-reminders: re-armed=1 failed=0 held_back=2 total=3"
  assert_eq "held back: capture deleted on full success" "0" "$(exists "${MOCKBIN}/capture.json")"
  assert_eq "held back: marker records capture_consumed_at (a number)" "number" "$(jq -r '.capture_consumed_at | type' "${MOCKBIN}/quiesced-by-op" 2>/dev/null)"
  assert_eq "held back: marker epoch untouched by the consume rewrite" "$QUIESCE_EPOCH" "$(jq -r '.epoch' "${MOCKBIN}/quiesced-by-op" 2>/dev/null)"
  assert_eq "held back: no marker temp file left behind" "0" "$(find "$MOCKBIN" -maxdepth 1 -name 'quiesced-by-op.*' | grep -c . || true)"
  assert_contains "held back: the POST opens transport-confined and captures response headers" "$(grep '^ARGS:' "$REQ_LOG")" "--disable --noproxy * -s -D "
  teardown_mock_curl
}

# Contract §5 amendment: the marker is written BEFORE disable+stop and the stop can take up to
# TimeoutStopSec=180 s, so a reminder due in that gap fired on the web scheduler too. E = quiesce
# epoch; the stop completed at E+120 (same boot); rem-gap is due at E+60, rem-after at E+180.
REC_GAP='[{"reminder_id":"rem-gap","fire_at":"2026-09-13T10:12:12Z","actor":"platform","action":{"type":"x"}},{"reminder_id":"rem-after","fire_at":"2026-09-13T10:14:12Z","actor":"platform","action":{"type":"x"}}]'
readonly STOP_E120="Sun 2026-09-13 10:13:12 UTC"

test_rearm_from_capture_cutoff_is_the_stop_on_the_same_boot() {
  setup_mock_curl 202
  seed_capture "$REC_GAP"; write_marker
  local rc=0; run_rfc "" "$STOP_E120" || rc=$?
  assert_eq "stop cutoff (same boot): exits 0" "0" "$rc"
  assert_contains "stop cutoff (same boot): rem-gap (due between marker and stop) is held back" "$(rfc_err)" "inngest-rearm-reminders: held back 1 reminder(s) due before the quiesce: rem-gap"
  assert_contains "stop cutoff (same boot): canonical line" "$(rfc_err)" "inngest-rearm-reminders: re-armed=1 failed=0 held_back=1 total=2"
  assert_eq "stop cutoff (same boot): only rem-after is POSTed" "rem-after" "$(sed -n 's/^BODY: //p' "$REQ_LOG" | jq -r '.reminder_id' | paste -sd, -)"
  assert_contains "stop cutoff (same boot): InactiveEnterTimestamp was read from the MOCK systemctl" "$(cat "${MOCKBIN}/systemctl.verbs.log" 2>/dev/null)" "show -p InactiveEnterTimestamp --value inngest-server.service"
  teardown_mock_curl
}

test_rearm_from_capture_cutoff_after_reboot_is_the_marker() {
  setup_mock_curl 202
  seed_capture "$REC_GAP"; write_marker
  assert_fixture_dir "$MOCKBIN"
  printf '%s\n' "$BOOT_B" > "${MOCKBIN}/boot_id"
  local rc=0; run_rfc "" "$STOP_E120" || rc=$?
  assert_eq "stop cutoff (rebooted): exits 0" "0" "$rc"
  assert_contains "stop cutoff (rebooted): InactiveEnterTimestamp ignored, cutoff = marker epoch, both re-armed" "$(rfc_err)" "inngest-rearm-reminders: re-armed=2 failed=0 held_back=0 total=2"
  assert_eq "stop cutoff (rebooted): no held-back line" "0" "$(grep -c 'held back' "${MOCKBIN}/rfc.err" || true)"
  teardown_mock_curl
}

test_rearm_from_capture_cutoff_never_earlier_than_marker() {
  setup_mock_curl 202
  seed_capture "$REC3"; write_marker
  # A stop timestamp BEFORE the marker (a stale value) must not shrink the cutoff below marker.epoch.
  local rc=0; run_rfc "" "Sun 2026-09-13 09:30:00 UTC" || rc=$?
  assert_eq "stop cutoff earlier than marker: exits 0" "0" "$rc"
  assert_contains "stop cutoff earlier than marker: cutoff stays marker.epoch (max)" "$(rfc_err)" "inngest-rearm-reminders: re-armed=1 failed=0 held_back=2 total=3"
  teardown_mock_curl
}

test_rearm_from_capture_legacy_no_marker_holds_nothing() {
  setup_mock_curl 202
  seed_capture "$REC3"
  local rc=0; run_rfc || rc=$?
  assert_eq "legacy (no marker): exits 0" "0" "$rc"
  assert_eq "legacy (no marker): every record POSTed, nothing held back" "3" "$(posts)"
  assert_contains "legacy (no marker): canonical line carries held_back=0" "$(rfc_err)" "inngest-rearm-reminders: re-armed=3 failed=0 held_back=0 total=3"
  assert_eq "legacy (no marker): no marker fabricated" "0" "$(exists "${MOCKBIN}/quiesced-by-op")"
  teardown_mock_curl
}

test_rearm_from_capture_sha_mismatch_is_stale() {
  setup_mock_curl 202
  seed_capture "$REC3"
  write_marker "2222222222222222222222222222222222222222222222222222222222222222"
  local rc=0; run_rfc || rc=$?
  assert_eq "rearm sha mismatch: exits 1" "1" "$rc"
  assert_contains "rearm sha mismatch: stale_capture refusal" "$(rfc_err)" "stale_capture"
  assert_eq "rearm sha mismatch: no POST" "0" "$(posts)"
  assert_eq "rearm sha mismatch: capture kept" "1" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
}

test_rearm_from_capture_consumed_marker_refuses_replay() {
  setup_mock_curl 202
  seed_capture "$REC3"; write_marker "" 1789380000
  local rc=0; run_rfc || rc=$?
  assert_eq "rearm consumed marker: exits 1" "1" "$rc"
  assert_contains "rearm consumed marker: already re-armed refusal" "$(rfc_err)" "already re-armed (capture consumed at 2026-09-14T10:00:00Z)"
  assert_eq "rearm consumed marker: no POST (no replay)" "0" "$(posts)"
  teardown_mock_curl
}

test_rearm_from_capture_failure_keeps_marker_unconsumed() {
  setup_mock_curl 401
  seed_capture "$REC3"; write_marker
  local rc=0; run_rfc || rc=$?
  assert_eq "rearm 401 with marker: exits 1" "1" "$rc"
  assert_contains "rearm 401 with marker: canonical line counts the failure" "$(rfc_err)" "inngest-rearm-reminders: re-armed=0 failed=1 held_back=2 total=3"
  assert_eq "rearm 401 with marker: capture retained" "1" "$(exists "${MOCKBIN}/capture.json")"
  assert_eq "rearm 401 with marker: marker NOT consumed" "false" "$(jq -r 'has("capture_consumed_at")' "${MOCKBIN}/quiesced-by-op" 2>/dev/null)"
  teardown_mock_curl
}

test_rearm_503_backend_refused_vs_cutover_quiesce() {
  setup_mock_curl 503
  seed_capture "$REC3"; write_marker
  local rc=0; run_rfc backend-refused || rc=$?
  assert_eq "503 backend-refused: exits 1" "1" "$rc"
  assert_contains "503 backend-refused: names the backend, retains the capture, says when to re-run" "$(rfc_err)" "ERROR: re-arm got 503 backend-refused for reminder_id=rem-late — the app's Inngest backend is not accepting connections (the INNGEST_BASE_URL repoint has not deployed, or the dedicated host is restarting); capture retained; re-run op=rearm once the backend serves"
  assert_eq "503 backend-refused: NOT misreported as INNGEST_CUTOVER_QUIESCE" "0" "$(grep -c 'INNGEST_CUTOVER_QUIESCE' "${MOCKBIN}/rfc.err" || true)"
  assert_eq "503 backend-refused: capture retained" "1" "$(exists "${MOCKBIN}/capture.json")"
  teardown_mock_curl
  setup_mock_curl 503
  seed_capture "$REC3"; write_marker
  rc=0; run_rfc cutover-quiesce || rc=$?
  assert_eq "503 cutover-quiesce: exits 1" "1" "$rc"
  assert_contains "503 cutover-quiesce: names INNGEST_CUTOVER_QUIESCE" "$(rfc_err)" "ERROR: re-arm got 503 for reminder_id=rem-late — INNGEST_CUTOVER_QUIESCE is still set."
  assert_eq "503 cutover-quiesce: NOT reported as backend-refused" "0" "$(grep -c 'backend-refused' "${MOCKBIN}/rfc.err" || true)"
  assert_eq "503 cutover-quiesce: the header temp file is removed on the abort path (EXIT trap owns it)" "0" "$(find "${MOCKBIN}/tmp" -type f | grep -c . || true)"
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
test_capture_stale_file_without_marker_is_unattributed
test_capture_marker_sha_mismatch_is_stale
test_capture_quiesced_without_file_is_stale
test_capture_quiesced_corrupt_file_fails
test_capture_consumed_marker_is_already_rearmed
test_capture_reboot_is_still_quiesced
test_capture_void_marker_is_unattributed
test_capture_serving_enumerates_live
test_capture_not_quiesced_shapes_enumerate_live
test_capture_needs_no_secret
test_rearm_still_fails_closed_without_secret
test_rearm_empty_capture_emits_canonical_line
test_rearm_from_capture_holds_back_pre_quiesce_records
test_rearm_from_capture_cutoff_is_the_stop_on_the_same_boot
test_rearm_from_capture_cutoff_after_reboot_is_the_marker
test_rearm_from_capture_cutoff_never_earlier_than_marker
test_rearm_from_capture_legacy_no_marker_holds_nothing
test_rearm_from_capture_sha_mismatch_is_stale
test_rearm_from_capture_consumed_marker_refuses_replay
test_rearm_from_capture_failure_keeps_marker_unconsumed
test_rearm_503_backend_refused_vs_cutover_quiesce

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact assertion-count floor (ADR-193): reported via printf + exit, never through
# pass()/fail(), so a neutered helper or a vanished test function cannot read green.
EXPECTED_ASSERTIONS=176
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf 'ASSERTION FLOOR: executed %d assertion(s), expected exactly %d\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
