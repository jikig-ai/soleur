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

# One owning EXIT trap for every tempdir this suite allocates (ADR-129 / #6734):
# per-test `mktemp -d` calls land under a suite-owned scratch dir via TMPDIR, so
# a suite that dies between allocation and its own `rm -rf` leaks nothing. The
# trap runs once, in this shell — a `$( … )` test subshell does not inherit it.
SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/disk-monitor-test.XXXXXX")"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

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
  # for the -w "%{http_code}" pattern (real curl outputs the code on stdout).
  #
  # (#7898 §2) Transport-confinement inspection runs FIRST, before the fail
  # branch, so a failed send still proves its flags were present. Only
  # vendor-bound invocations are inspected (host-filtered), and each inspected
  # call is counted into curl_checked so the rows below have a vacuity floor.
  # Violations are WRITTEN, never exited on, so the stub's own exit code can
  # never mask one. The '*' compare is quoted: an unquoted `== *` matches
  # anything and would make the argv row vacuous.
  cat > "$mock_dir/curl" << MOCK
#!/bin/bash
vendor=""; scheme_http=0; has_proto=0
for arg in "\$@"; do
  case "\$arg" in
    *api.resend.com*) vendor="api.resend.com" ;;
    *.sentry.io*) vendor="sentry.io" ;;
  esac
  [[ "\$arg" == http://* ]] && scheme_http=1
  [[ "\$arg" == "--proto" ]] && has_proto=1
done
if [[ -n "\$vendor" ]]; then
  echo "\$vendor" >> "$mock_dir/curl_checked"
  if [[ "\${1:-}" != "--disable" || "\${2:-}" != "--noproxy" || "\${3:-}" != '*' \\
     || "\${4:-}" != "--proto" || "\${5:-}" != "=https" || "\${6:-}" != "-g" ]]; then
    echo "ARGV_ORDER host=\$vendor" >> "$mock_dir/curl_violations"
  fi
  n=0
  for arg in "\$@"; do
    if [[ "\$arg" == "--noproxy" ]]; then n=\$((n + 1)); fi
  done
  if [[ "\$n" -ne 1 ]]; then echo "NOPROXY_COUNT n=\$n" >> "$mock_dir/curl_violations"; fi
  # TLS-env canary exported by the harness: the script's unset prologue must
  # have cleared it before any credentialed curl ran.
  if [[ -n "\${SSLKEYLOGFILE:-}\${CURL_CA_BUNDLE:-}" ]]; then echo "TLS_ENV_LEAK" >> "$mock_dir/curl_violations"; fi
fi
# A plain-http (loopback) call must NOT carry --proto '=https' — a mechanical
# "confine every curl" sweep would break it silently (the stub answers 200).
if [[ "\$scheme_http" -eq 1 && "\$has_proto" -eq 1 ]]; then echo "PROTO_ON_HTTP" >> "$mock_dir/curl_violations"; fi
echo "\$*" >> "$mock_dir/curl_args"
if [[ "\${MOCK_CURL_FAIL:-}" == "1" ]]; then
  echo "000"
  exit 1
fi
echo "200"
exit 0
MOCK
  chmod +x "$mock_dir/curl"

  # Mock logger -- records the joined argv of every crit row the monitor ships
  # off-box (#7898 P6/P9). MOCK_LOGGER_ABSENT=1 leaves `logger` OFF the PATH
  # entirely (a symlink farm of the coreutils the script needs replaces the
  # inherited PATH), so the `logger=absent` stderr branch is exercised.
  if [[ "${MOCK_LOGGER_ABSENT:-}" != "1" ]]; then
    cat > "$mock_dir/logger" << MOCK
#!/bin/bash
echo "\$*" >> "$mock_dir/logger_args"
exit 0
MOCK
    chmod +x "$mock_dir/logger"
  fi

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
  if [[ "${MOCK_LOGGER_ABSENT:-}" == "1" ]]; then
    export PATH="$mock_dir:$(make_logger_absent_path "$mock_dir")"
  else
    export PATH="$mock_dir:$PATH"
  fi
  # TLS-env canary (#7898): the script's unset prologue must clear these before
  # any credentialed curl; the stub records TLS_ENV_LEAK if it still sees them.
  export SSLKEYLOGFILE="$mock_dir/keys.log" CURL_CA_BUNDLE="$mock_dir/ca.pem"
  # Run from a NON-EMPTY cwd so an unquoted `--noproxy *` in the script would
  # glob-expand before reaching the stub and fail the argv[3] check (T11).
  ( cd "$mock_dir" && bash "$MONITOR_SCRIPT" 2>&1 )
}

# A PATH with every coreutil the monitor needs and NO `logger` (#7898). Symlinks
# resolved from the inherited PATH so the farm is host-agnostic.
make_logger_absent_path() {
  local mock_dir="$1" farm="$1/no-logger-bin" bin
  mkdir -p "$farm"
  for bin in bash awk cat cut grep head jq mktemp mv rm sort tail touch tr wc sed; do
    local real
    real="$(command -v "$bin" 2>/dev/null || true)"
    [[ -n "$real" ]] && ln -sf "$real" "$farm/$bin"
  done
  echo "$farm"
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

# Test: 96% with no cooldowns fires both CRITICAL and WARNING alerts
test_dual_alert_no_cooldown() {
  TOTAL=$((TOTAL + 1))
  local description="96% with no cooldowns fires both CRITICAL and WARNING"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=96
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local curl_count=0
  # (#7898) the confined argv prefix precedes the pre-existing `-s -o /dev/null`
  [[ -f "$mock_dir/curl_args" ]] && curl_count=$(grep -c '^--disable --noproxy \* --proto =https -g -s -o /dev/null' "$mock_dir/curl_args" || true)

  if [[ "$actual_exit" -eq 0 ]] && [[ "$curl_count" -eq 2 ]] \
     && grep -qF "CRITICAL" "$mock_dir/curl_args" \
     && grep -qF "WARNING" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, curl_count=$curl_count)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
  rm -rf "$mock_dir"
}

test_dual_alert_no_cooldown

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

# Test: curl failure exits 0 and logs Resend API warning
test_curl_failure() {
  TOTAL=$((TOTAL + 1))
  local description="curl failure exits 0 and logs Resend API warning"
  local mock_dir
  mock_dir=$(mktemp -d)

  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=85
    export MOCK_CURL_FAIL=1
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  # (#7898 P9) a failed send must ALSO ship off-box: one `logger -p user.crit`
  # row carrying the marker + reason tokens (http_code, rc) and NEVER the key;
  # and the failing call itself must have carried the four transport flags.
  local ok=1 largs="$mock_dir/logger_args"
  [[ "$actual_exit" -eq 0 ]] || ok=0
  printf '%s\n' "$output" | grep -qF "Resend API POST failed" || ok=0
  [[ -f "$largs" ]] || ok=0
  grep -qF -- "-p user.crit" "$largs" 2>/dev/null || ok=0
  grep -qF -- "-t disk-monitor" "$largs" 2>/dev/null || ok=0
  grep -qF 'SOLEUR_DISK_MONITOR_SEND_FAILED channel=resend http_code=000 rc=1' "$largs" 2>/dev/null || ok=0   # curl exit 1 → rc=1, code 000
  grep -qF "re_test_fake_key_123" "$largs" 2>/dev/null && ok=0
  [[ ! -f "$mock_dir/curl_violations" ]] || ok=0
  [[ -f "$mock_dir/curl_checked" ]] || ok=0
  if [[ "$ok" -eq 1 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
    echo "        logger_args: $(cat "$largs" 2>/dev/null)"
    echo "        curl_violations: $(cat "$mock_dir/curl_violations" 2>/dev/null)"
  fi
  rm -rf "$mock_dir"
}

test_curl_failure

echo ""
echo "--- (#7898 §2) transport confinement: argv position + off-box refusal path ---"

# Every Resend-bound curl must carry `--disable --noproxy '*' --proto '=https' -g`
# as argv[1..6] with exactly one --noproxy. The stub writes violations to a file
# and counts inspected calls; `checked >= 1` is the vacuity floor (a host filter
# that stopped matching would otherwise read as "no violations").
assert_confined() {
  local description="$1" mock_dir="$2" actual_exit="$3" output="$4"
  local checked=0
  [[ -f "$mock_dir/curl_checked" ]] && checked=$(wc -l < "$mock_dir/curl_checked" | tr -d ' ')
  if [[ "$actual_exit" -eq 0 ]] && [[ ! -f "$mock_dir/curl_violations" ]] && [[ "$checked" -ge 1 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, checked=$checked, violations: $(cat "$mock_dir/curl_violations" 2>/dev/null))"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
}

test_confined_warning() {
  TOTAL=$((TOTAL + 1))
  local description="WARNING send carries the four transport flags first, --noproxy exactly once"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=82
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_confined "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_confined_warning

test_confined_critical() {
  TOTAL=$((TOTAL + 1))
  local description="CRITICAL send carries the four transport flags first, --noproxy exactly once"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=96
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_confined "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_confined_critical

# The only off-box path is `logger`; when it is absent the alert must neither
# fail-stop (exit 0 contract) nor vanish silently (stderr names the gap).
test_logger_absent() {
  TOTAL=$((TOTAL + 1))
  local description="logger absent from PATH: exit 0, stderr carries logger=absent"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_DF_USAGE=85 MOCK_CURL_FAIL=1 MOCK_LOGGER_ABSENT=1
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  if [[ "$actual_exit" -eq 0 ]] \
     && printf '%s\n' "$output" | grep -qF "Resend API POST failed" \
     && printf '%s\n' "$output" | grep -qF "logger=absent" \
     && [[ ! -f "$mock_dir/logger_args" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_logger_absent

# Static rows over the script source (#7898 review): a credentialed curl must
# never follow redirects (curl forwards a custom auth header cross-host on a
# 3xx; the Rule D linter has no -L limb), and no invocation may be
# path-qualified (a `/usr/bin/curl` bypasses this PATH stub — the exec rows'
# `checked` floor would also catch it; the linter's CURL_INVOKE DOES match it,
# so this is belt-and-braces for the stub's chokepoint claim). Anchored on the
# call form so a comment cannot satisfy either.
test_static_curl_shape() {
  TOTAL=$((TOTAL + 1))
  local description="no credentialed curl follows redirects and none is path-qualified"
  local redirects pathq
  redirects=$(grep -cE '^[[:space:]]*([A-Za-z_]+="?\$\()?curl .* (-L|--location)( |$)' "$MONITOR_SCRIPT" || true)
  pathq=$(grep -cE '(^|[[:space:]"(])/[A-Za-z0-9_./-]*/curl([[:space:]]|$)' "$MONITOR_SCRIPT" || true)
  if [[ "$redirects" -eq 0 && "$pathq" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $description (redirects=$redirects path-qualified=$pathq)"
  fi
}
test_static_curl_shape

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

# Anti-vacuity floor (ADR-193): the results line above is a human convention;
# CI reads only the exit status, so a deleted row-dispatch line would vanish
# green. Read the INDEPENDENT total and report directly — never through the
# PASS/FAIL accounting this backstops. Ratchet when adding rows.
if [[ "$TOTAL" -lt 15 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= 15. A row was deleted or its dispatch line removed.\n' "$TOTAL" >&2
  exit 1
fi

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
