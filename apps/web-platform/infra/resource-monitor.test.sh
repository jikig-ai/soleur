#!/usr/bin/env bash
set -euo pipefail

# Tests for resource-monitor.sh.
# Mirrors disk-monitor.test.sh: subshell isolation, PATH-prepended mock binaries,
# environment toggles for behavior control. Curl mock uses `echo "$*"` dump,
# never `${!@}` indirect expansion (learning 2026-04-05).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/resource-monitor.sh"

PASS=0
FAIL=0
TOTAL=0

# Set up mocks in the given directory and run resource-monitor.sh.
#
# Environment toggles (set before calling):
#   MOCK_MEM_PCT=<int>       - memory utilization % reported by the meminfo mock (default: 50)
#   MOCK_CPU_PCT=<int>       - CPU utilization % reported by the /proc/stat mock (default: 10)
#   MOCK_SESSIONS=<int>      - active_sessions returned by the /health curl mock (default: 0)
#   MOCK_CURL_FAIL=1         - curl exits non-zero
#   MOCK_DATE_EPOCH=<int>    - epoch returned by date +%s (default: 1700000000)
#   MOCK_NO_WEBHOOK=1        - leave RESEND_API_KEY unset
#
# Files created by mocks:
#   $MOCK_DIR/curl_args      - all curl invocation args (one line per call)
setup_mocks_and_run() {
  local mock_dir="$1"

  export COOLDOWN_DIR="$mock_dir"
  export PROC_ROOT="$mock_dir/proc"
  mkdir -p "$PROC_ROOT"

  # Fabricate /proc/meminfo so MemAvailable = MOCK_MEM_PCT derives cleanly.
  # 10,000,000 kB total. used = total * pct / 100 → available = total - used.
  local mem_pct="${MOCK_MEM_PCT:-50}"
  local mem_total=10000000
  local mem_used=$(( mem_total * mem_pct / 100 ))
  local mem_available=$(( mem_total - mem_used ))
  printf 'MemTotal:       %d kB\nMemFree:        %d kB\nMemAvailable:   %d kB\n' \
    "$mem_total" 0 "$mem_available" > "$PROC_ROOT/meminfo"

  # Fabricate two /proc/stat snapshots so the delta yields MOCK_CPU_PCT %.
  # Shape: cpu user nice system idle iowait irq softirq
  # Snapshot 1 is fixed; snapshot 2 advances total by 100 and idle by (100 - pct).
  local cpu_pct="${MOCK_CPU_PCT:-10}"
  local stat_file="$PROC_ROOT/stat"
  local stat_file_next="$PROC_ROOT/stat.next"
  printf 'cpu  1000 0 500 8000 0 0 0\nintr 0\n' > "$stat_file"
  local user2=$(( 1000 + cpu_pct ))
  local idle2=$(( 8000 + (100 - cpu_pct) ))
  printf 'cpu  %d 0 500 %d 0 0 0\nintr 0\n' "$user2" "$idle2" > "$stat_file_next"

  # Env file
  local env_file="$mock_dir/resource-monitor-env"
  if [[ "${MOCK_NO_WEBHOOK:-}" != "1" ]]; then
    printf 'RESEND_API_KEY=%s\n' "${MOCK_RESEND_KEY:-re_test_fake_key_123}" > "$env_file"
  else
    : > "$env_file"
  fi
  export ENV_FILE="$env_file"

  # Mock head -- advance /proc/stat on second invocation so the delta sampler
  # reads snapshot-1 then snapshot-2. Only intercepts `head -1 <path>`;
  # other invocations delegate to real head.
  cat > "$mock_dir/head" << MOCK
#!/bin/bash
if [[ "\${1:-}" == "-1" && "\${2:-}" == "$PROC_ROOT/stat" ]]; then
  counter_file="$mock_dir/stat-counter"
  count=0
  [[ -f "\$counter_file" ]] && count=\$(cat "\$counter_file")
  count=\$(( count + 1 ))
  echo "\$count" > "\$counter_file"
  if [[ "\$count" -eq 1 ]]; then
    /usr/bin/head -1 "$PROC_ROOT/stat"
  else
    /usr/bin/head -1 "$PROC_ROOT/stat.next"
  fi
  exit 0
fi
exec /usr/bin/head "\$@"
MOCK
  chmod +x "$mock_dir/head"

  # Mock sleep -- no-op so the 1-sec CPU delta window doesn't slow tests.
  cat > "$mock_dir/sleep" << 'MOCK'
#!/bin/bash
exit 0
MOCK
  chmod +x "$mock_dir/sleep"

  # Mock curl -- captures args; for /health URL returns a JSON body with
  # MOCK_SESSIONS; for Resend URL returns HTTP 200 via -w "%{http_code}".
  cat > "$mock_dir/curl" << MOCK
#!/bin/bash
if [[ "\${MOCK_CURL_FAIL:-}" == "1" ]]; then
  echo "000"
  exit 1
fi
echo "\$*" >> "$mock_dir/curl_args"
for arg in "\$@"; do
  if [[ "\$arg" == *"/health"* ]]; then
    echo "{\"active_sessions\": \${MOCK_SESSIONS:-0}}"
    exit 0
  fi
done
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

assert_no_alert() {
  local description="$1" mock_dir="$2" actual_exit="$3" output="$4"
  if [[ "$actual_exit" -eq 0 ]] && ! grep -qF "api.resend.com" "$mock_dir/curl_args" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
}

assert_alert_contains() {
  local description="$1" mock_dir="$2" actual_exit="$3" output="$4" needle="$5"
  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] \
     && grep -qF "api.resend.com" "$mock_dir/curl_args" \
     && grep -qF "$needle" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, needle=$needle)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
}

echo "=== resource-monitor.sh tests ==="
echo ""

echo "--- Below thresholds ---"

test_below_thresholds() {
  TOTAL=$((TOTAL + 1))
  local description="mem=50% cpu=10% → no email, exit 0"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=50 MOCK_CPU_PCT=10
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_no_alert "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_below_thresholds

echo ""
echo "--- Memory warn threshold ---"

test_mem_warn() {
  TOTAL=$((TOTAL + 1))
  local description="mem=82% fires WARN email (no prior cooldown)"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_alert_contains "$description" "$mock_dir" "$actual_exit" "$output" "WARN"
  rm -rf "$mock_dir"
}

test_mem_warn

echo ""
echo "--- Cooldown mechanism ---"

test_mem_warn_cooldown_active() {
  TOTAL=$((TOTAL + 1))
  local description="mem=82% with active mem-warn cooldown → no email"
  local mock_dir
  mock_dir=$(mktemp -d)
  # Set mem-warn cooldown 30 min ago (current=1700000000, written=1699998200)
  echo "1699998200" > "$mock_dir/resource-monitor-alert-mem-warn"
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10 MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_no_alert "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_mem_warn_cooldown_active

test_mem_crit_fires_over_active_warn_cooldown() {
  TOTAL=$((TOTAL + 1))
  local description="mem=96% fires CRIT even when mem-warn cooldown active (per-threshold)"
  local mock_dir
  mock_dir=$(mktemp -d)
  # mem-warn cooldown active, no mem-crit cooldown
  echo "1699998200" > "$mock_dir/resource-monitor-alert-mem-warn"
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=96 MOCK_CPU_PCT=10 MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_alert_contains "$description" "$mock_dir" "$actual_exit" "$output" "CRIT"
  rm -rf "$mock_dir"
}

test_mem_crit_fires_over_active_warn_cooldown

test_cooldown_expired() {
  TOTAL=$((TOTAL + 1))
  local description="expired cooldown allows re-alert"
  local mock_dir
  mock_dir=$(mktemp -d)
  # 2 hours ago: 1700000000 - 7200 = 1699992800
  echo "1699992800" > "$mock_dir/resource-monitor-alert-mem-warn"
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10 MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_alert_contains "$description" "$mock_dir" "$actual_exit" "$output" "WARN"
  rm -rf "$mock_dir"
}

test_cooldown_expired

echo ""
echo "--- Error handling ---"

test_missing_env_file() {
  TOTAL=$((TOTAL + 1))
  local description="missing env file exits 0 with stderr warning"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export ENV_FILE="$mock_dir/nonexistent-env-file"
    export COOLDOWN_DIR="$mock_dir"
    export PROC_ROOT="$mock_dir/proc"
    bash "$MONITOR_SCRIPT" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qiF "warning"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_missing_env_file

test_missing_resend_key() {
  TOTAL=$((TOTAL + 1))
  local description="missing RESEND_API_KEY exits 0 with stderr warning"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_NO_WEBHOOK=1
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]] && printf '%s\n' "$output" | grep -qiF "warning"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_missing_resend_key

echo ""
echo "--- CPU warn threshold ---"

test_cpu_warn() {
  TOTAL=$((TOTAL + 1))
  local description="cpu=90% fires WARN email"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=50 MOCK_CPU_PCT=90
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_alert_contains "$description" "$mock_dir" "$actual_exit" "$output" "CPU"
  rm -rf "$mock_dir"
}

test_cpu_warn

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
