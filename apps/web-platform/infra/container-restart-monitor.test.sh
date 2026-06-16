#!/usr/bin/env bash
set -euo pipefail

# Tests for container-restart-monitor.sh (#5417 Deliverable B / AC5/AC6).
# Mirrors resource-monitor.test.sh: subshell isolation, PATH-prepended mock
# binaries, env toggles for behavior control. Mocks `docker`, `journalctl`,
# `curl`, `date`; points STATE_DIR / CGROUP_ROOT / ENV_FILE at a tmpdir.
#
# Behavior under test (the restart-classification state machine):
#   - deploy (container_id change, RestartCount reset) → NO alert, baseline reset
#   - same container_id, RestartCount delta ≥ threshold in window → ALERT
#   - fresh container already RestartCount>0 (immediate crash-loop) → ALERT
#   - container absent (docker inspect non-zero, deploy stop/rm window) → exit 0,
#     no false-healthy, baseline preserved
#   - OOM corroboration: classify OOM via cgroup memory.events oom_kill delta
#     AND/OR exit-137 AND/OR journald, NOT .State.OOMKilled alone (cgroup-v2
#     child-cgroup false-negative)
#   - Resend POST failure still posts the Sentry event (mirror) + logs warning
#   - recovery: a single "cleared" notification when the rolling rate returns to
#     0 after an alert
#   - named constants RESTART_THRESHOLD / RESTART_WINDOW_SECS / COOLDOWN_SECONDS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/container-restart-monitor.sh"

PASS=0
FAIL=0
TOTAL=0

# Set up mocks in the given dir and run container-restart-monitor.sh.
#
# Env toggles (export before calling):
#   MOCK_DOCKER_ID        - container id reported by docker inspect (default cid-A)
#   MOCK_RESTART_COUNT    - RestartCount (default 0)
#   MOCK_OOMKILLED        - .State.OOMKilled true|false (default false)
#   MOCK_EXITCODE         - .State.ExitCode (default 0)
#   MOCK_DOCKER_ABSENT=1  - docker inspect exits non-zero (container gone)
#   MOCK_OOM_COUNTER      - cgroup memory.events oom_kill counter (default 0)
#   MOCK_JOURNAL_OOM=1    - journalctl -k prints an oom-kill line
#   MOCK_DATE_EPOCH       - epoch from date +%s (default 1700000000)
#   MOCK_RESEND_FAIL=1    - Resend POST returns HTTP 500
#   MOCK_NO_WEBHOOK=1     - leave RESEND_API_KEY unset
#
# Files: $mock_dir/curl_args (one line per curl invocation)
setup_mocks_and_run() {
  local mock_dir="$1"
  local cid="${MOCK_DOCKER_ID:-cid-A}"

  export STATE_DIR="$mock_dir"
  export CGROUP_ROOT="$mock_dir/cgroup"
  export CONTAINER="soleur-web-platform"
  mkdir -p "$CGROUP_ROOT/system.slice/docker-${cid}.scope"
  printf 'oom_kill %s\n' "${MOCK_OOM_COUNTER:-0}" \
    > "$CGROUP_ROOT/system.slice/docker-${cid}.scope/memory.events"

  # Env file (Resend key)
  local env_file="$mock_dir/env"
  if [[ "${MOCK_NO_WEBHOOK:-}" != "1" ]]; then
    printf 'RESEND_API_KEY=%s\n' "re_test_fake_key_123" > "$env_file"
  else
    : > "$env_file"
  fi
  export ENV_FILE="$env_file"
  # Sentry env present so the Sentry channel is exercised in tests.
  export SENTRY_INGEST_DOMAIN="ingest.example.test"
  export SENTRY_PROJECT_ID="4321"
  export SENTRY_PUBLIC_KEY="pubkey_test"

  # Mock docker — only `docker inspect` is intercepted; absence simulated.
  cat > "$mock_dir/docker" << MOCK
#!/bin/bash
if [[ "\${1:-}" == "inspect" ]]; then
  if [[ "\${MOCK_DOCKER_ABSENT:-}" == "1" ]]; then
    echo "Error: No such object: ${CONTAINER}" >&2
    exit 1
  fi
  # Emit: Id RestartCount OOMKilled ExitCode
  echo "${cid} ${MOCK_RESTART_COUNT:-0} ${MOCK_OOMKILLED:-false} ${MOCK_EXITCODE:-0}"
  exit 0
fi
exit 0
MOCK
  chmod +x "$mock_dir/docker"

  cat > "$mock_dir/journalctl" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_JOURNAL_OOM:-}" == "1" ]]; then
  echo "kernel: Out of memory: Killed process 1234 (node) total-vm:..."
fi
exit 0
MOCK
  chmod +x "$mock_dir/journalctl"

  cat > "$mock_dir/curl" << MOCK
#!/bin/bash
echo "\$*" >> "$mock_dir/curl_args"
if [[ "\${MOCK_RESEND_FAIL:-}" == "1" ]]; then
  for arg in "\$@"; do
    if [[ "\$arg" == *"api.resend.com"* ]]; then echo "500"; exit 0; fi
  done
fi
echo "200"
exit 0
MOCK
  chmod +x "$mock_dir/curl"

  cat > "$mock_dir/hostname" << 'MOCK'
#!/bin/bash
echo "test-server-cx33"
MOCK
  chmod +x "$mock_dir/hostname"

  cat > "$mock_dir/date" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "+%s" ]]; then
  echo "${MOCK_DATE_EPOCH:-1700000000}"
  exit 0
fi
/usr/bin/date "$@"
MOCK
  chmod +x "$mock_dir/date"

  export PATH="$mock_dir:$PATH"
  bash "$MONITOR_SCRIPT" 2>&1
}

# Seed a baseline state file (container_id restart_count oom_counter epoch).
seed_baseline() {
  local mock_dir="$1" cid="$2" count="$3" oom="${4:-0}" epoch="${5:-1699990000}"
  printf '%s %s %s %s\n' "$cid" "$count" "$oom" "$epoch" \
    > "$mock_dir/container-restart-monitor.state"
}

resend_hit() { grep -qF "api.resend.com" "$1/curl_args" 2>/dev/null; }
sentry_hit() { grep -qF "ingest.example.test" "$1/curl_args" 2>/dev/null; }

assert_no_alert() {
  local desc="$1" mock_dir="$2" rc="$3" out="$4"
  if [[ "$rc" -eq 0 ]] && ! resend_hit "$mock_dir" && ! sentry_hit "$mock_dir"; then
    PASS=$((PASS + 1)); echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc (rc=$rc)"; echo "        out: $out"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl: $(cat "$mock_dir/curl_args")"
  fi
}

assert_alert() {
  local desc="$1" mock_dir="$2" rc="$3" out="$4" needle="${5:-}"
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  resend_hit "$mock_dir" || ok=0
  sentry_hit "$mock_dir" || ok=0
  if [[ -n "$needle" ]]; then grep -qiF "$needle" "$mock_dir/curl_args" 2>/dev/null || ok=0; fi
  if [[ "$ok" -eq 1 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $desc (rc=$rc, needle=$needle)"; echo "        out: $out"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl: $(cat "$mock_dir/curl_args")"
  fi
}

echo "=== container-restart-monitor.sh tests ==="
echo ""

echo "--- (a) deploy: container_id change + count reset → no alert ---"
t_deploy_no_alert() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-OLD" 5 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-NEW MOCK_RESTART_COUNT=0; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_no_alert "deploy (id change, count reset) does not alert" "$d" "$rc" "$out"
  # baseline must now track the NEW container
  if grep -q "^cid-NEW " "$d/container-restart-monitor.state" 2>/dev/null; then
    PASS=$((PASS+1)); echo "  PASS: baseline reset to the new container id"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: baseline not reset (state: $(cat "$d/container-restart-monitor.state" 2>/dev/null))"
  fi
  TOTAL=$((TOTAL+1))
  rm -rf "$d"
}
t_deploy_no_alert

echo ""
echo "--- (b) same container, count delta ≥ threshold → alert ---"
t_increment_alert() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert "same-id count 0→3 (≥threshold) alerts via Sentry+Resend" "$d" "$rc" "$out"
  rm -rf "$d"
}
t_increment_alert

echo ""
echo "--- (b2) same container, delta below threshold → no alert (boundary, AC6) ---"
t_below_threshold() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=2; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_no_alert "same-id count 0→2 (<threshold=3) does not alert" "$d" "$rc" "$out"
  rm -rf "$d"
}
t_below_threshold

echo ""
echo "--- (c) fresh container already count>0 → alert ---"
t_fresh_crashing() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-OLD" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-NEW MOCK_RESTART_COUNT=3; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert "fresh container (id change) already count>0 alerts" "$d" "$rc" "$out"
  rm -rf "$d"
}
t_fresh_crashing

echo ""
echo "--- (d) container absent → exit 0, no alert, baseline preserved ---"
t_absent() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 1 0
  local out rc
  out=$(export MOCK_DOCKER_ABSENT=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_no_alert "container absent (deploy stop/rm window) → exit 0, no false-healthy" "$d" "$rc" "$out"
  TOTAL=$((TOTAL+1))
  if grep -q "^cid-A 1 " "$d/container-restart-monitor.state" 2>/dev/null; then
    PASS=$((PASS+1)); echo "  PASS: baseline preserved across absent tick"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: baseline clobbered (state: $(cat "$d/container-restart-monitor.state" 2>/dev/null))"
  fi
  rm -rf "$d"
}
t_absent

echo ""
echo "--- (e) OOM corroboration — each signal classifies OOM in ISOLATION ---"
# Each case arms EXACTLY ONE of the four OOM signals (cgroup oom_kill delta,
# exit-137, journald, .State.OOMKilled) with the other three clear, and asserts
# the alert is class=OOM via an OOM-class-specific needle ("OOM restart churn",
# the Sentry message — a crash-class alert says "crash restart churn"). The
# cgroup-only case (e1) is the load-bearing one: it is the ONLY signal that
# catches the child-cgroup bwrap kill, so deleting `(( OOM_DELTA > 0 ))` from the
# monitor's OOM OR must turn e1 RED (the prior single bundled case stayed green).
OOM_NEEDLE="OOM restart churn"

t_oom_cgroup_only() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_OOMKILLED=false \
        MOCK_EXITCODE=0 MOCK_OOM_COUNTER=2; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert "cgroup memory.events oom_kill delta ALONE classifies OOM (child-cgroup case)" "$d" "$rc" "$out" "$OOM_NEEDLE"
  rm -rf "$d"
}
t_oom_cgroup_only

t_oom_exit137_only() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_OOMKILLED=false \
        MOCK_EXITCODE=137 MOCK_OOM_COUNTER=0; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert "exit-137 ALONE classifies OOM" "$d" "$rc" "$out" "$OOM_NEEDLE"
  rm -rf "$d"
}
t_oom_exit137_only

t_oom_journald_only() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_OOMKILLED=false \
        MOCK_EXITCODE=0 MOCK_OOM_COUNTER=0 MOCK_JOURNAL_OOM=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert "journald oom-kill line ALONE classifies OOM" "$d" "$rc" "$out" "$OOM_NEEDLE"
  rm -rf "$d"
}
t_oom_journald_only

t_oom_oomkilled_only() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_OOMKILLED=true \
        MOCK_EXITCODE=0 MOCK_OOM_COUNTER=0; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  assert_alert ".State.OOMKilled=true ALONE classifies OOM" "$d" "$rc" "$out" "$OOM_NEEDLE"
  rm -rf "$d"
}
t_oom_oomkilled_only

t_crash_not_oom() {
  # Negative-space: a storm with NO OOM signal must be class=crash, NOT OOM.
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_OOMKILLED=false \
        MOCK_EXITCODE=1 MOCK_OOM_COUNTER=0; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] && resend_hit "$d" && sentry_hit "$d" || ok=0
  grep -qiF "$OOM_NEEDLE" "$d/curl_args" 2>/dev/null && ok=0   # must NOT be OOM-classed
  grep -qF "crash restart churn" "$d/curl_args" 2>/dev/null || ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: no OOM signal → class=crash (not OOM)";
  else FAIL=$((FAIL+1)); echo "  FAIL: crash classification (rc=$rc) curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_crash_not_oom

echo ""
echo "--- (f) Resend POST failure still posts the Sentry mirror + warns ---"
t_resend_fail_mirror() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_RESEND_FAIL=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" || ok=0                                   # mirror still posted
  printf '%s\n' "$out" | grep -qiF "resend" || ok=0          # warning logged
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: Resend failure still mirrors to Sentry + logs warning";
  else FAIL=$((FAIL+1)); echo "  FAIL: resend-fail mirror (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_resend_fail_mirror

echo ""
echo "--- (g) recovery: rolling rate back to 0 after alert → one 'cleared' note ---"
t_recovery() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  # Baseline same id+count (no new restarts), but an 'alerted' flag is set and
  # the rolling events file is empty/expired → recovery notification.
  seed_baseline "$d" "cid-A" 7 0
  : > "$d/container-restart-monitor.events"        # no recent events → rate 0
  touch "$d/container-restart-monitor.alerted"     # a prior alert is open
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=7; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qiE "clear|recover|resolved" "$d/curl_args" 2>/dev/null || ok=0
  [[ -f "$d/container-restart-monitor.alerted" ]] && ok=0   # flag must be cleared
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: recovery notification fires once and clears the alerted flag";
  else FAIL=$((FAIL+1)); echo "  FAIL: recovery (rc=$rc) curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_recovery

echo ""
echo "--- (h) missing env file / Resend key → exit 0 with warning ---"
t_missing_env() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_NO_WEBHOOK=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  # Sentry channel does not need RESEND; alert still posts to Sentry, exit 0.
  if [[ "$rc" -eq 0 ]]; then PASS=$((PASS+1)); echo "  PASS: missing Resend key still exits 0 (Sentry channel independent)";
  else FAIL=$((FAIL+1)); echo "  FAIL: missing env exit (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_missing_env

echo ""
echo "--- (j) cooldown: a within-window second storm is email-suppressed ---"
t_cooldown_suppressed() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  echo "1699999000" > "$d/container-restart-monitor.cooldown"   # 1000s ago < 3600 cooldown
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_DATE_EPOCH=1700000000; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  ! resend_hit "$d" || ok=0                                     # email suppressed
  ! sentry_hit "$d" || ok=0                                     # both channels gated by cooldown
  printf '%s\n' "$out" | grep -qiF "cooldown" || ok=0           # logged the suppression reason
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: active cooldown suppresses the alert send (logged)";
  else FAIL=$((FAIL+1)); echo "  FAIL: cooldown suppression (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_cooldown_suppressed

echo ""
echo "--- (k) deploy during an open alert does NOT emit a false 'CLEARED' ---"
t_deploy_during_storm_no_recovery() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  # An alert is open (ALERTED_FILE present); a deploy lands (container_id change)
  # which truncates the rolling window → RATE 0. The recovery branch must NOT
  # fire because IS_DEPLOY=true (a deploy reset is not a genuine recovery).
  seed_baseline "$d" "cid-OLD" 7 0
  touch "$d/container-restart-monitor.alerted"
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-NEW MOCK_RESTART_COUNT=0; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qiE "clear|recover|resolved" "$d/curl_args" 2>/dev/null && ok=0   # NO false CLEARED
  [[ -f "$d/container-restart-monitor.alerted" ]] || ok=0                 # flag stays open
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: deploy-during-storm does not emit a false 'CLEARED'; alert stays open";
  else FAIL=$((FAIL+1)); echo "  FAIL: deploy-during-storm recovery suppression (rc=$rc) curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_deploy_during_storm_no_recovery

echo ""
echo "--- (i) named constants present (AC6) ---"
t_constants() {
  TOTAL=$((TOTAL + 1))
  local n
  n=$(grep -cE '^readonly (RESTART_THRESHOLD|RESTART_WINDOW_SECS|COOLDOWN_SECONDS)=' "$MONITOR_SCRIPT" || true)
  if [[ "$n" -eq 3 ]]; then PASS=$((PASS+1)); echo "  PASS: RESTART_THRESHOLD/RESTART_WINDOW_SECS/COOLDOWN_SECONDS are named constants";
  else FAIL=$((FAIL+1)); echo "  FAIL: expected 3 named constants, found $n"; fi
}
t_constants

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
