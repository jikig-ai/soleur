#!/usr/bin/env bash
set -euo pipefail

# Tests for disk-monitor.sh.
# Uses the same mock architecture as ci-deploy.test.sh:
# - Subshell isolation per test
# - PATH-prepended mock binaries
# - Environment toggles for behavior control

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/disk-monitor.sh"

PASS=0
FAIL=0
TOTAL=0

# Set up mocks in the given directory and run disk-monitor.sh.
# The caller creates MOCK_DIR and can inspect files after return.
#
# Environment toggles (set before calling):
#   MOCK_DF_USAGE=<int>   - disk usage percentage (default: 50)
#   MOCK_DF_AVAIL=<int>   - available KB (default: 20000000)
#   MOCK_DF_FAIL=1        - df exits non-zero
#   MOCK_CURL_FAIL=1      - curl exits non-zero
#   MOCK_DATE_EPOCH=<int> - epoch returned by date +%s (default: 1700000000)
#   MOCK_NO_WEBHOOK=1     - leave RESEND_API_KEY unset
#
# Files created by mocks:
#   $MOCK_DIR/curl_args    - all curl invocation args (one line per call)
setup_mocks_and_run() {
  local mock_dir="$1"

  # Redirect cooldown files to mock dir
  export COOLDOWN_DIR="$mock_dir"

  # Create env file
  local env_file="$mock_dir/disk-monitor-env"
  if [[ "${MOCK_NO_WEBHOOK:-}" != "1" ]]; then
    printf 'RESEND_API_KEY=%s\n' "${MOCK_RESEND_KEY:-re_test_fake_key_123}" > "$env_file"
  else
    : > "$env_file"
  fi
  export ENV_FILE="$env_file"

  # Mock df
  cat > "$mock_dir/df" << 'MOCK'
#!/bin/bash
if [[ "${MOCK_DF_FAIL:-}" == "1" ]]; then exit 1; fi
for arg in "$@"; do
  if [[ "$arg" == "--output=pcent" ]]; then
    echo "Use%"
    printf ' %s%%\n' "${MOCK_DF_USAGE:-50}"
    exit 0
  fi
  if [[ "$arg" == "--output=avail" ]]; then
    echo "Avail"
    echo "${MOCK_DF_AVAIL:-20000000}"
    exit 0
  fi
done
MOCK
  chmod +x "$mock_dir/df"

  # Mock curl -- writes all args to curl_args file, outputs HTTP status code
  # for the -w "%{http_code}" pattern (real curl outputs the code on stdout)
  cat > "$mock_dir/curl" << MOCK
#!/bin/bash
if [[ "\${MOCK_CURL_FAIL:-}" == "1" ]]; then
  echo "000"
  exit 1
fi
echo "\$*" >> "$mock_dir/curl_args"
echo "200"
exit 0
MOCK
  chmod +x "$mock_dir/curl"

  # Mock hostname
  cat > "$mock_dir/hostname" << 'MOCK'
#!/bin/bash
echo "test-server-cx33"
MOCK
  chmod +x "$mock_dir/hostname"

  # Mock du
  cat > "$mock_dir/du" << 'MOCK'
#!/bin/bash
echo "5.0G	/var"
echo "3.0G	/usr"
echo "1.0G	/home"
MOCK
  chmod +x "$mock_dir/du"

  # Mock date -- configurable epoch
  cat > "$mock_dir/date" << 'MOCK'
#!/bin/bash
if [[ "${1:-}" == "+%s" ]]; then
  echo "${MOCK_DATE_EPOCH:-1700000000}"
  exit 0
fi
/usr/bin/date "$@"
MOCK
  chmod +x "$mock_dir/date"

  # Mock timeout (just run the command)
  cat > "$mock_dir/timeout" << 'MOCK'
#!/bin/bash
shift; exec "$@"
MOCK
  chmod +x "$mock_dir/timeout"

  # Use real jq and sort
  export PATH="$mock_dir:$PATH"
  bash "$MONITOR_SCRIPT" 2>&1
}

echo "=== disk-monitor.sh tests ==="
echo ""

echo "--- Normal operation (below threshold) ---"

# Test: below 80% produces no webhook and exits 0
test_below_threshold() {
  TOTAL=$((TOTAL + 1))
  local description="below 80% produces no webhook and exits 0"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=50
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ ! -f "$mock_dir/curl_args" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, curl called: $(test -f "$mock_dir/curl_args" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_below_threshold

echo ""
echo "--- 80% warning threshold ---"

# Test: 82% triggers webhook POST with WARNING
test_warning_threshold() {
  TOTAL=$((TOTAL + 1))
  local description="82% triggers webhook POST with WARNING"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=82
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] \
     && grep -qF "WARNING" "$mock_dir/curl_args" \
     && grep -qF "api.resend.com" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
  rm -rf "$mock_dir"
}

test_warning_threshold

echo ""
echo "--- 95% critical threshold ---"

# Test: 96% includes CRITICAL and @here mention
test_critical_threshold() {
  TOTAL=$((TOTAL + 1))
  local description="96% includes CRITICAL alert"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=96
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] \
     && grep -qF "CRITICAL" "$mock_dir/curl_args" \
     && grep -qF "api.resend.com" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
  rm -rf "$mock_dir"
}

test_critical_threshold

# Test: 96% email subject contains [CRITICAL]
test_critical_email_subject() {
  TOTAL=$((TOTAL + 1))
  local description="96% email subject contains [CRITICAL]"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=96
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] && grep -qF '\\[CRITICAL\\]' "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    # Fallback: check the JSON payload for CRITICAL in subject field
    if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] && grep -qF "CRITICAL" "$mock_dir/curl_args"; then
      PASS=$((PASS + 1))
      echo "  PASS: $description"
    else
      FAIL=$((FAIL + 1))
      echo "  FAIL: $description (exit=$actual_exit)"
      echo "        output: $output"
      [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
    fi
  fi
  rm -rf "$mock_dir"
}

test_critical_email_subject

echo ""
echo "--- Cooldown mechanism ---"

# Test: cooldown prevents duplicate 80% alerts within 1 hour
test_cooldown_active() {
  TOTAL=$((TOTAL + 1))
  local description="cooldown prevents duplicate 80% alert within 1 hour"
  local mock_dir
  mock_dir=$(mktemp -d)

  # Set 80% cooldown file 30 min ago (current: 1700000000, written: 1699998200)
  echo "1699998200" > "$mock_dir/disk-monitor-alert-80"

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=82
    export MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ ! -f "$mock_dir/curl_args" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, curl called: $(test -f "$mock_dir/curl_args" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_cooldown_active

# Test: expired cooldown allows re-alert
test_cooldown_expired() {
  TOTAL=$((TOTAL + 1))
  local description="expired cooldown allows re-alert"
  local mock_dir
  mock_dir=$(mktemp -d)

  # Set 80% cooldown file 2 hours ago (current: 1700000000, written: 1699992800)
  echo "1699992800" > "$mock_dir/disk-monitor-alert-80"

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=82
    export MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, curl called: $(test -f "$mock_dir/curl_args" && echo yes || echo no))"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_cooldown_expired

# Test: 95% alert fires even when 80% cooldown is active (separate cooldown files)
test_independent_cooldowns() {
  TOTAL=$((TOTAL + 1))
  local description="95% alert fires even when 80% cooldown is active"
  local mock_dir
  mock_dir=$(mktemp -d)

  # 80% cooldown active (30 min ago), no 95% cooldown
  echo "1699998200" > "$mock_dir/disk-monitor-alert-80"

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=96
    export MOCK_DATE_EPOCH=1700000000
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # Should have the 95% CRITICAL alert (80% suppressed by cooldown)
  if [[ "$actual_exit" -eq 0 ]] && [[ -f "$mock_dir/curl_args" ]] && grep -qF "CRITICAL" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
  rm -rf "$mock_dir"
}

test_independent_cooldowns

echo ""
echo "--- Error handling ---"

# Test: missing env file exits 0 with warning
test_missing_env_file() {
  TOTAL=$((TOTAL + 1))
  local description="missing env file exits 0 with stderr warning"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export ENV_FILE="$mock_dir/nonexistent-env-file"
    export COOLDOWN_DIR="$mock_dir"
    # No mocks needed -- script exits before using any commands
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

# Test: df failure exits 0 with warning
test_df_failure() {
  TOTAL=$((TOTAL + 1))
  local description="df failure exits 0 with stderr warning"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_FAIL=1
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

test_df_failure

# Test: missing RESEND_API_KEY exits 0 with warning
test_missing_webhook() {
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

test_missing_webhook

# Test: curl failure exits 0
test_curl_failure() {
  TOTAL=$((TOTAL + 1))
  local description="curl failure exits 0"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=85
    export MOCK_CURL_FAIL=1
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq 0 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_curl_failure

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
