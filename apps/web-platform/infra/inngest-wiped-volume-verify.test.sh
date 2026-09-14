#!/usr/bin/env bash
# Tests for inngest-wiped-volume-verify.sh — the OPT-IN, emptiness-gated,
# destructive end-to-end durability proof (#5450, AC3/B1/F2/P2-sec-b).
#
# The script's safety contract is what these tests pin (the live run is out of
# scope): it must ABORT before any wipe when a real armed reminder is present
# (B1 — the postgres-uri check ALWAYS passes post-#5459 and protects nothing),
# and its throwaway marker must post ZERO comments to any real issue (an
# unregistered named-check fires a run but the handler rejects it before any
# octokit call — P2-sec-b).
#
# Seams: INNGEST_ENUMERATE_CMD (stub), mock curl on PATH (captures arm body +
# scripts health/functions), mock systemctl on PATH (records stop/start order),
# INNGEST_DATA_DIR (temp dir wiped instead of /var/lib/inngest),
# INNGEST_VERIFY_EXECSTART (the ExecStart string the postgres-uri sanity reads),
# INNGEST_VERIFY_MARKER_ID (deterministic id), INNGEST_VERIFY_STATE (temp).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-wiped-volume-verify.sh"

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
assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc — unexpectedly found '$needle'"; FAIL=$((FAIL + 1)); fi
}

MOCKBIN=""
ARM_LOG=""
ENUM_STUB=""
setup() {
  MOCKBIN=$(mktemp -d)
  ARM_LOG="${MOCKBIN}/arm.log"; : > "$ARM_LOG"
  # mock curl: arm POST → 202 and log the --data-binary body; GET health → 200 body
  # {"status":200}; /v0/gql functions query → a 1-cron GraphQL response (#5517);
  # GET /v1/functions (the unregistered route) → a 404 text body, so a script still
  # using the old path reads 0 functions and aborts (the RED this drives).
  cat > "${MOCKBIN}/curl" <<MOCK
#!/usr/bin/env bash
url="\${!#}"
body=""; prev=""; outfile=""
for a in "\$@"; do
  case "\$prev" in --data-binary|-d) body="\$a" ;; -o) outfile="\$a" ;; esac
  prev="\$a"
done
case "\$url" in
  *schedule-reminder*) [[ -n "\$body" ]] && echo "ARM_BODY: \$body" >> "$ARM_LOG"; printf '202' ;;
  *health*)    [[ -n "\$outfile" ]] && printf '{"status":200,"message":"OK"}' > "\$outfile"; printf '200' ;;
  # /v0/gql functions query (body on stdout) → wrapped GraphQL functions response.
  # (Explicit if, not \${:-default}: a brace-heavy JSON default terminates the
  # parameter expansion at its first '}'.)
  *v0/gql*)      if [[ -n "\${WVV_FUNCTIONS_BODY:-}" ]]; then printf '%s' "\$WVV_FUNCTIONS_BODY"; else printf '%s' '{"data":{"functions":[{"slug":"cron-x"}]}}'; fi ;;
  # /v1/functions is an UNREGISTERED 404 route in v1.19.4 (#5517).
  *v1/functions*) printf '404 page not found' ;;
  *) printf '200' ;;
esac
MOCK
  chmod +x "${MOCKBIN}/curl"
  # mock systemctl: record verb order to a file. The two read-only unit-shape queries answer
  # like systemd (stdout is the state; is-active rc 3 when not active, is-enabled rc 1 on
  # disabled) from WVV_UNIT_ACTIVE / WVV_UNIT_ENABLED — default active+enabled (a serving unit).
  cat > "${MOCKBIN}/systemctl" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/systemctl.log"
case "\$1" in
  is-active)  s="\${WVV_UNIT_ACTIVE:-active}"; echo "\$s"; [[ "\$s" == active ]] || exit 3 ;;
  is-enabled) s="\${WVV_UNIT_ENABLED:-enabled}"; echo "\$s"; [[ "\$s" == enabled ]] || exit 1 ;;
esac
exit 0
MOCK
  chmod +x "${MOCKBIN}/systemctl"
  # mock sudo: strip the prefix, exec the rest (so mocked systemctl runs)
  cat > "${MOCKBIN}/sudo" <<'MOCK'
#!/usr/bin/env bash
exec "$@"
MOCK
  chmod +x "${MOCKBIN}/sudo"
}
teardown() { rm -rf "$MOCKBIN"; }

# Stub enumerate that prints $ENUM_STUB_JSON
make_enum_stub() {
  ENUM_STUB="${MOCKBIN}/enum-stub.sh"
  cat > "$ENUM_STUB" <<MOCK
#!/usr/bin/env bash
printf '%s' '${1}'
MOCK
  chmod +x "$ENUM_STUB"
}

# Stub enumerate that FAILS (exit 1, no output) and records that it ran.
make_failing_enum_stub() {
  ENUM_STUB="${MOCKBIN}/enum-stub.sh"
  cat > "$ENUM_STUB" <<MOCK
#!/usr/bin/env bash
echo ran >> "${MOCKBIN}/enum.log"
exit 1
MOCK
  chmod +x "$ENUM_STUB"
}

# Count unit-changing systemctl verbs; prints 0 (not "") when systemctl was never invoked.
count_unit_verbs() {
  if [[ -f "${MOCKBIN}/systemctl.log" ]]; then grep -cE '^(stop|start|restart) ' "${MOCKBIN}/systemctl.log" || true; else echo 0; fi
}

run_verify() {
  local data_dir execstart
  data_dir="${MOCKBIN}/inngest-data"; mkdir -p "$data_dir"; echo "sqlite" > "$data_dir/main.db"
  execstart="${1:-/usr/local/bin/inngest start --sqlite-dir /var/lib/inngest --postgres-max-open-conns 10}"
  PATH="${MOCKBIN}:$PATH" \
    INNGEST_ENUMERATE_CMD="$ENUM_STUB" \
    INNGEST_DATA_DIR="$data_dir" \
    INNGEST_VERIFY_EXECSTART="$execstart" \
    INNGEST_VERIFY_MARKER_ID="${INNGEST_VERIFY_MARKER_ID:-}" \
    INNGEST_VERIFY_STATE="${MOCKBIN}/verify.state" \
    INNGEST_MANUAL_TRIGGER_SECRET="test-secret" \
    INNGEST_VERIFY_SETTLE_SECS=0 \
    WVV_FUNCTIONS_BODY="${WVV_FUNCTIONS_BODY:-}" \
    bash "$TARGET" 2>&1
}

echo "=== inngest-wiped-volume-verify.sh tests ==="
assert_eq "script exists and is executable" "1" "$([[ -x "$TARGET" ]] && echo 1 || echo 0)"

# --- Test 1 (KEY, B1): a real armed reminder present → ABORT before any wipe ---
test_abort_on_real_reminder() {
  setup
  make_enum_stub '[{"reminder_id":"rem-real","fire_at":"2026-06-18T12:00:00Z","actor":"platform","action":{"type":"issue-comment","issue":7,"body":"x"}}]'
  local out rc=0
  out=$(run_verify) || rc=$?
  assert_eq "exits non-zero when a real reminder is armed" "1" "$rc"
  assert_contains "abort message names the armed-reminder safety gate" "$out" "armed reminder"
  # The data dir must be untouched (no wipe), and systemctl never stopped inngest.
  assert_eq "data dir NOT wiped on abort" "sqlite" "$(cat "${MOCKBIN}/inngest-data/main.db")"
  # The quiesce gate runs FIRST (read-only is-active/is-enabled), so systemctl IS queried — but no
  # verb that changes the unit may appear.
  assert_eq "no stop/start/restart verb on abort" "0" "$(count_unit_verbs)"
  teardown
}

# --- Test 2 (B1 secondary): no durable sentinel in ExecStart → ABORT (durable sanity) ---
test_abort_on_non_durable_backend() {
  setup
  make_enum_stub '[]'
  local out rc=0
  out=$(run_verify "/usr/local/bin/inngest start --sqlite-dir /var/lib/inngest") || rc=$?
  assert_eq "exits non-zero when ExecStart lacks --postgres-max-open-conns sentinel" "1" "$rc"
  assert_contains "abort names the durable-backend sanity" "$out" "postgres-max-open-conns"
  assert_eq "data dir NOT wiped (non-durable)" "sqlite" "$(cat "${MOCKBIN}/inngest-data/main.db")"
  teardown
}

# --- Test 3 (P2-sec-b): clean gate → throwaway armed as UNREGISTERED named-check ---
# (fires a run, posts NO comment) — NEVER issue-comment to a real issue.
test_throwaway_posts_no_comment() {
  setup
  make_enum_stub '[]'
  run_verify >/dev/null 2>&1 || true
  local body; body=$(grep '^ARM_BODY:' "$ARM_LOG" | head -1)
  assert_contains "throwaway armed at all" "$body" "named-check"
  assert_not_contains "throwaway is NOT an issue-comment (no real-issue post)" "$body" '"type":"issue-comment"'
  assert_contains "throwaway uses the sentinel unregistered check" "$body" "cutover-verify-noop"
  teardown
}

# --- Test 4: clean gate → stop precedes wipe precedes start; data dir wiped ---
test_happy_wipe_order() {
  setup
  make_enum_stub '[]'
  local rc=0
  run_verify >/dev/null 2>&1 || rc=$?
  assert_eq "exits 0 on clean verify" "0" "$rc"
  local sclog; sclog=$(cat "${MOCKBIN}/systemctl.log" 2>/dev/null || echo "")
  assert_contains "stops inngest-server" "$sclog" "stop inngest-server.service"
  assert_contains "starts inngest-server" "$sclog" "start inngest-server.service"
  # stop must come before start
  local stop_ln start_ln
  stop_ln=$(grep -n 'stop inngest-server' "${MOCKBIN}/systemctl.log" | head -1 | cut -d: -f1)
  start_ln=$(grep -n 'start inngest-server' "${MOCKBIN}/systemctl.log" | head -1 | cut -d: -f1)
  assert_eq "stop precedes start" "1" "$([[ "$stop_ln" -lt "$start_ln" ]] && echo 1 || echo 0)"
  assert_eq "data dir wiped (main.db gone)" "0" "$([[ -e "${MOCKBIN}/inngest-data/main.db" ]] && echo 1 || echo 0)"
  # terminal state file written with exit_code 0
  assert_eq "verify-state exit_code 0" "0" "$(jq -r .exit_code "${MOCKBIN}/verify.state")"
  teardown
}

# --- Test 5: marker id is unique across runs (no fixed id) ---
test_marker_unique() {
  setup; make_enum_stub '[]'; run_verify >/dev/null 2>&1 || true
  local id1; id1=$(grep '^ARM_BODY:' "$ARM_LOG" | head -1 | sed 's/^ARM_BODY: //' | jq -r .reminder_id)
  teardown
  setup; make_enum_stub '[]'; sleep 1; run_verify >/dev/null 2>&1 || true
  local id2; id2=$(grep '^ARM_BODY:' "$ARM_LOG" | head -1 | sed 's/^ARM_BODY: //' | jq -r .reminder_id)
  teardown
  assert_eq "two runs produce distinct marker ids" "1" "$([[ "$id1" != "$id2" ]] && echo 1 || echo 0)"
  assert_contains "marker id is a recognizable sentinel" "$id1" "wiped-volume-verify"
}

# --- Test 1b (B1 hardening): a real reminder is NOT dodged by spoofing the
# sentinel reminder_id prefix — the unregistered-check signal is unforgeable.
# A real reminder cannot carry action.check == the noop sentinel (a real
# named-check must resolve in CHECK_REGISTRY), so an issue-comment reminder with
# a spoofed __wiped-volume-verify- id is still counted as real → ABORT.
test_abort_on_spoofed_prefix_real_reminder() {
  setup
  make_enum_stub '[{"reminder_id":"__wiped-volume-verify-SPOOF__","fire_at":"2026-06-18T12:00:00Z","actor":"platform","action":{"type":"issue-comment","issue":7,"body":"real"}}]'
  local out rc=0
  out=$(run_verify) || rc=$?
  assert_eq "spoofed-prefix issue-comment reminder still ABORTS (not dodged)" "1" "$rc"
  assert_eq "data dir NOT wiped on spoofed-prefix abort" "sqlite" "$(cat "${MOCKBIN}/inngest-data/main.db")"
  teardown
}

# --- Test 6 (#5517): post-restart functions probe reads /v0/gql, aborts on 0 ---
# GET /v1/functions is a 404 in v1.19.4 (would always read 0 → false no_functions
# abort after a healthy restart). The probe must read the GraphQL functions query;
# an empty functions array (no SDK re-sync yet) still aborts loud (durability gate).
test_no_functions_aborts_loud() {
  setup
  make_enum_stub '[]'
  local out rc=0
  out=$(WVV_FUNCTIONS_BODY='{"data":{"functions":[]}}' run_verify) || rc=$?
  assert_eq "empty /v0/gql functions after restart → abort non-zero" "1" "$rc"
  assert_contains "abort names the no_functions durability gate" "$out" "functions returned 0"
  teardown
}

# --- Test 7 (#6921/#8077): the web unit is QUIESCED by op=quiesce-web → refuse ---
# `is-active ∈ {inactive, failed}` AND `is-enabled == disabled` is the shape only op=quiesce-web
# writes; this script's `start` would re-arm the scheduler the cutover deliberately stopped. The gate
# runs BEFORE Gate 1 (enumeration): a quiesced host has no serving inngest, so the enumeration FAILS
# there, and a gate after it would report enumerate_failed — hiding the real reason. The stub
# enumeration below fails, and the reason must still be quiesced_refused, with the enumeration
# never run and no stop/start.
test_abort_when_quiesced() {
  local active
  for active in inactive failed; do
    setup
    make_failing_enum_stub
    local out rc=0
    out=$(WVV_UNIT_ACTIVE="$active" WVV_UNIT_ENABLED=disabled run_verify) || rc=$?
    assert_eq "quiesced ($active+disabled) exits non-zero" "1" "$rc"
    assert_eq "quiesced ($active+disabled) + failing enumeration → reason quiesced_refused (not enumerate_failed)" "quiesced_refused" \
      "$(jq -r .reason "${MOCKBIN}/verify.state" 2>/dev/null || echo "<no state>")"
    assert_eq "quiesced ($active+disabled) the enumeration never ran (gate precedes Gate 1)" "0" \
      "$(if [[ -f "${MOCKBIN}/enum.log" ]]; then grep -c '^ran$' "${MOCKBIN}/enum.log" || true; else echo 0; fi)"
    assert_contains "quiesced ($active+disabled) abort names op=rollback" "$out" "op=rollback"
    local sclog; sclog=$(cat "${MOCKBIN}/systemctl.log" 2>/dev/null || echo "")
    assert_contains "quiesced ($active+disabled) the unit shape was actually queried (non-vacuity)" "$sclog" "is-enabled inngest-server.service"
    assert_eq "quiesced ($active+disabled) no stop/start in the systemctl log" "0" \
      "$(count_unit_verbs)"
    assert_eq "quiesced ($active+disabled) data dir NOT wiped" "sqlite" "$(cat "${MOCKBIN}/inngest-data/main.db")"
    assert_eq "quiesced ($active+disabled) throwaway marker NOT armed" "0" "$(grep -c '^ARM_BODY:' "$ARM_LOG" || true)"
    teardown
  done
  # Non-vacuity for the rows above: NOT quiesced + the same failing enumeration → enumerate_failed.
  setup
  make_failing_enum_stub
  local rc3=0
  run_verify >/dev/null 2>&1 || rc3=$?
  assert_eq "not quiesced + failing enumeration → exits 1" "1" "$rc3"
  assert_eq "not quiesced + failing enumeration → reason enumerate_failed (the stub does fail)" "enumerate_failed" \
    "$(jq -r .reason "${MOCKBIN}/verify.state" 2>/dev/null || echo "<no state>")"
  assert_eq "not quiesced + failing enumeration → the enumeration stub ran (enum.log is the real signal)" "1" \
    "$(if [[ -f "${MOCKBIN}/enum.log" ]]; then grep -c '^ran$' "${MOCKBIN}/enum.log" || true; else echo 0; fi)"
  teardown
  # Re-assert before the first unit verb: op=quiesce-web lands WHILE the enumeration and the marker
  # arm run (the first shape read says serving, every later read says quiesced) → still refused,
  # after the enumeration, with no stop/start.
  setup
  make_enum_stub '[]'
  cat > "${MOCKBIN}/systemctl" <<MOCK
#!/usr/bin/env bash
echo "\$*" >> "${MOCKBIN}/systemctl.log"
n=\$(grep -c "^\$1 " "${MOCKBIN}/systemctl.log")
case "\$1" in
  is-active)  if [[ \$n -le 1 ]]; then echo active; exit 0; fi; echo inactive; exit 3 ;;
  is-enabled) if [[ \$n -le 1 ]]; then echo enabled; exit 0; fi; echo disabled; exit 1 ;;
esac
exit 0
MOCK
  chmod +x "${MOCKBIN}/systemctl"
  local rc5=0
  run_verify >/dev/null 2>&1 || rc5=$?
  assert_eq "quiesced mid-run (after Gate 0) → exits 1" "1" "$rc5"
  assert_eq "quiesced mid-run → reason quiesced_refused (the pre-stop re-assert)" "quiesced_refused" \
    "$(jq -r .reason "${MOCKBIN}/verify.state" 2>/dev/null || echo "<no state>")"
  assert_eq "quiesced mid-run → no stop/start in the systemctl log" "0" "$(count_unit_verbs)"
  assert_eq "quiesced mid-run → data dir NOT wiped" "sqlite" "$(cat "${MOCKBIN}/inngest-data/main.db")"
  teardown
  # Must-PASS: inactive but ENABLED (a crashed/stopped armed unit) is not quiesced → proceeds.
  setup
  make_enum_stub '[]'
  local rc2=0
  WVV_UNIT_ACTIVE=inactive WVV_UNIT_ENABLED=enabled run_verify >/dev/null 2>&1 || rc2=$?
  assert_eq "inactive+ENABLED is not quiesced → verify proceeds (exit 0)" "0" "$rc2"
  teardown
  # Must-PASS: ACTIVE but disabled (someone ran `systemctl disable` on a serving unit) is not the
  # quiesced shape — `disabled` alone is never sufficient → proceeds, not refused.
  setup
  make_enum_stub '[]'
  local rc4=0
  WVV_UNIT_ACTIVE=active WVV_UNIT_ENABLED=disabled run_verify >/dev/null 2>&1 || rc4=$?
  assert_eq "active+DISABLED is not quiesced → verify proceeds (exit 0)" "0" "$rc4"
  assert_eq "active+DISABLED terminal reason is verify_passed (not quiesced_refused)" "verify_passed" \
    "$(jq -r .reason "${MOCKBIN}/verify.state" 2>/dev/null || echo "<no state>")"
  teardown
}

test_abort_on_real_reminder
test_abort_on_spoofed_prefix_real_reminder
test_abort_when_quiesced
test_abort_on_non_durable_backend
test_throwaway_posts_no_comment
test_happy_wipe_order
test_no_functions_aborts_loud
test_marker_unique

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
# Exact assertion floor: a deleted, skipped or early-returning row changes the dispatched count.
readonly EXPECTED_ASSERTIONS=49
if (( PASS + FAIL != EXPECTED_ASSERTIONS )); then
  printf '  FAIL: dispatched %s assertions, expected exactly %s — a row was added, removed or skipped\n' "$((PASS + FAIL))" "$EXPECTED_ASSERTIONS"
  exit 1
fi
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
