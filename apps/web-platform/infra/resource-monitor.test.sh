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

# One owning EXIT trap for every tempdir this suite allocates (ADR-129 / #6734):
# per-test `mktemp -d` calls land under a suite-owned scratch dir via TMPDIR, so
# a suite that dies between allocation and its own `rm -rf` leaks nothing. The
# trap runs once, in this shell — a `$( … )` test subshell does not inherit it.
SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/resource-monitor-test.XXXXXX")"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

# Set up mocks in the given directory and run resource-monitor.sh.
#
# Environment toggles (set before calling):
#   MOCK_MEM_PCT=<int>       - memory utilization % reported by the meminfo mock (default: 50)
#   MOCK_CPU_PCT=<int>       - CPU utilization % reported by the /proc/stat mock (default: 10)
#   MOCK_SESSIONS=<int>      - active_sessions returned by the /internal/metrics curl mock (default: 0)
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

  # Mock curl -- captures args; for /internal/metrics URL returns a JSON body with
  # MOCK_SESSIONS; for Resend URL returns HTTP 200 via -w "%{http_code}".
  #
  # (#7898 §2) Transport-confinement inspection runs FIRST, before the fail
  # branch, so a failed send still proves its flags were present. Host-filtered
  # on the vendor host, so the UNcredentialed loopback metrics curl is excluded
  # by construction (it must NOT carry --proto '=https'). Violations are
  # WRITTEN, never exited on; the '*' compare is quoted (unquoted `== *` matches
  # anything and would make the argv row vacuous).
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
for arg in "\$@"; do
  if [[ "\$arg" == *"/internal/metrics"* ]]; then
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
# resolved from the inherited PATH so the farm is host-agnostic. The `head` mock
# execs /usr/bin/head by absolute path, so it needs no farm entry.
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
echo "--- Dual alert (mem=96% fires both CRIT and WARN) ---"

test_dual_alert_no_cooldown() {
  TOTAL=$((TOTAL + 1))
  local description="mem=96% with no cooldowns fires both CRIT and WARN"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=96 MOCK_CPU_PCT=10
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?

  local alert_count=0
  [[ -f "$mock_dir/curl_args" ]] && alert_count=$(grep -c 'api.resend.com' "$mock_dir/curl_args")

  if [[ "$actual_exit" -eq 0 ]] && [[ "$alert_count" -eq 2 ]] \
     && grep -qF "CRIT" "$mock_dir/curl_args" \
     && grep -qF "WARN" "$mock_dir/curl_args"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, alerts=$alert_count)"
    echo "        output: $output"
    [[ -f "$mock_dir/curl_args" ]] && echo "        curl_args: $(cat "$mock_dir/curl_args")"
  fi
  rm -rf "$mock_dir"
}

test_dual_alert_no_cooldown

echo ""
echo "--- Curl failure ---"

test_curl_failure() {
  TOTAL=$((TOTAL + 1))
  local description="curl failure on Resend POST exits 0 and logs warning"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10 MOCK_CURL_FAIL=1
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
  grep -qF -- "-t resource-monitor" "$largs" 2>/dev/null || ok=0
  grep -qF 'SOLEUR_RESOURCE_MONITOR_SEND_FAILED channel=resend http_code=000 rc=1' "$largs" 2>/dev/null || ok=0   # curl exit 1 → rc=1, code 000
  grep -qF "re_test_fake_key_123" "$largs" 2>/dev/null && ok=0
  [[ ! -f "$mock_dir/curl_violations" ]] || ok=0
  grep -qF "api.resend.com" "$mock_dir/curl_checked" 2>/dev/null || ok=0
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
# and counts inspected calls; `checked >= 1` is the vacuity floor. The loopback
# metrics curl is excluded by the stub's host filter, not by name.
assert_confined() {
  local description="$1" mock_dir="$2" actual_exit="$3" output="$4"
  local checked=0
  [[ -f "$mock_dir/curl_checked" ]] && checked=$(grep -c "api.resend.com" "$mock_dir/curl_checked" || true)
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

test_confined_mem_warn() {
  TOTAL=$((TOTAL + 1))
  local description="mem WARN send carries the four transport flags first, --noproxy exactly once"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_confined "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_confined_mem_warn

test_confined_cpu_warn() {
  TOTAL=$((TOTAL + 1))
  local description="cpu WARN send carries the four transport flags first, --noproxy exactly once"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=50 MOCK_CPU_PCT=90
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  assert_confined "$description" "$mock_dir" "$actual_exit" "$output"
  rm -rf "$mock_dir"
}

test_confined_cpu_warn

# The only off-box path is `logger`; when it is absent the alert must neither
# fail-stop (exit 0 contract) nor vanish silently (stderr names the gap).
test_logger_absent() {
  TOTAL=$((TOTAL + 1))
  local description="logger absent from PATH: exit 0, stderr carries logger=absent"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=82 MOCK_CPU_PCT=10 MOCK_CURL_FAIL=1 MOCK_LOGGER_ABSENT=1
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

echo ""
echo "--- /proc snapshot counter sanity ---"

# Catches drift in the resource-monitor.sh /proc/stat reader: if the delta
# sampler stops reading two snapshots (e.g., refactor drops the second head),
# stat-counter stays at 1 and CPU defaults to 0 — tests would silently pass.
test_proc_stat_counter() {
  TOTAL=$((TOTAL + 1))
  local description="/proc/stat delta reads exactly 2 snapshots per run"
  local mock_dir
  mock_dir=$(mktemp -d)
  local output actual_exit
  output=$(
    export MOCK_MEM_PCT=50 MOCK_CPU_PCT=30
    setup_mocks_and_run "$mock_dir" 2>&1
  ) && actual_exit=0 || actual_exit=$?
  local counter=0
  [[ -f "$mock_dir/stat-counter" ]] && counter=$(cat "$mock_dir/stat-counter")
  if [[ "$actual_exit" -eq 0 ]] && [[ "$counter" -eq 2 ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (exit=$actual_exit, counter=$counter)"
    echo "        output: $output"
  fi
  rm -rf "$mock_dir"
}

test_proc_stat_counter

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
