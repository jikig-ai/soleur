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

# One owning EXIT trap for every tempdir this suite allocates (ADR-129 / #6734):
# per-test `mktemp -d` calls land under a suite-owned scratch dir via TMPDIR, so
# a suite that dies between allocation and its own `rm -rf` leaks nothing. The
# trap runs once, in this shell — a `$( … )` test subshell does not inherit it.
SUITE_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/container-restart-monitor-test.XXXXXX")"
export TMPDIR="$SUITE_SCRATCH"
trap 'rm -rf "$SUITE_SCRATCH"' EXIT

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
#   MOCK_SENTRY_FAIL=1    - Sentry store POST returns HTTP 500 (#7898)
#   MOCK_CURL_EXIT=<n>    - every curl exits <n> with code 000 (transport failure)
#   MOCK_NO_WEBHOOK=1     - leave RESEND_API_KEY unset
#   MOCK_SENTRY_HOST      - SENTRY_INGEST_DOMAIN (default: the POSITIVE synthetic
#                           fixture o0000000.ingest.de.sentry.io — #7898 pin)
#   MOCK_SENTRY_KEY       - SENTRY_PUBLIC_KEY (default: 32 synthetic hex)
#   MOCK_SENTRY_UNSET=1   - leave the whole Sentry triple unset
#   MOCK_LOGGER_ABSENT=1  - `logger` is OFF the PATH entirely (#7898)
#
# Files: $mock_dir/curl_args (one line per curl invocation), curl_checked /
#        curl_violations (#7898 argv inspection), logger_args (crit rows)
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
  # Sentry env present so the Sentry channel is exercised in tests. The default
  # is the POSITIVE synthetic fixture that the #7898 destination pin accepts
  # (ADR-214: a vendor-shaped synthetic host, never an env-declared seam). The
  # old `ingest.example.test` / `pubkey_test` values live on as the NEGATIVE
  # fixtures in the pin rows below.
  if [[ "${MOCK_SENTRY_UNSET:-}" == "1" ]]; then
    unset SENTRY_INGEST_DOMAIN SENTRY_PROJECT_ID SENTRY_PUBLIC_KEY
  else
    export SENTRY_INGEST_DOMAIN="${MOCK_SENTRY_HOST:-o0000000.ingest.de.sentry.io}"
    export SENTRY_PROJECT_ID="${MOCK_SENTRY_PROJECT:-4321}"
    export SENTRY_PUBLIC_KEY="${MOCK_SENTRY_KEY:-0123456789abcdef0123456789abcdef}"
  fi

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

  # (#7898 §2) Transport-confinement inspection runs FIRST. Host-filtered on the
  # two vendor hosts; every inspected call is counted into curl_checked so the
  # alert rows can pin `checked == 2` (Sentry + Resend — a filter that silently
  # dropped .sentry.io would read 1). Violations are WRITTEN, never exited on;
  # the '*' compare is quoted (unquoted `== *` matches anything).
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
if [[ -n "\${MOCK_CURL_EXIT:-}" ]]; then echo "000"; exit "\$MOCK_CURL_EXIT"; fi
if [[ "\${MOCK_RESEND_FAIL:-}" == "1" && "\$vendor" == "api.resend.com" ]]; then echo "500"; exit 0; fi
if [[ "\${MOCK_SENTRY_FAIL:-}" == "1" && "\$vendor" == "sentry.io" ]]; then echo "500"; exit 0; fi
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
  # off-box (#7898 P6/P9). MOCK_LOGGER_ABSENT=1 leaves `logger` OFF the PATH.
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

# Seed a baseline state file (container_id restart_count oom_counter epoch).
seed_baseline() {
  local mock_dir="$1" cid="$2" count="$3" oom="${4:-0}" epoch="${5:-1699990000}"
  printf '%s %s %s %s\n' "$cid" "$count" "$oom" "$epoch" \
    > "$mock_dir/container-restart-monitor.state"
}

resend_hit() { grep -qF "api.resend.com" "$1/curl_args" 2>/dev/null; }
# Greps the POSITIVE Sentry host (folded form) — a request to the unfolded
# `O0000000.INGEST…` or to a refused host must not satisfy this.
sentry_hit() { grep -qF "https://o0000000.ingest.de.sentry.io/" "$1/curl_args" 2>/dev/null; }

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
  # (#7898 P9) the failed send ships off-box as a crit row: marker + http code,
  # never the key
  grep -qF -- "-p user.crit" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF -- "-t container-restart-monitor" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF 'SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=resend http_code=500 rc=0' "$d/logger_args" 2>/dev/null || ok=0   # transport ok, vendor refused
  grep -qF "re_test_fake_key_123" "$d/logger_args" 2>/dev/null && ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: Resend failure still mirrors to Sentry + logs warning";
  else FAIL=$((FAIL+1)); echo "  FAIL: resend-fail mirror (rc=$rc) out: $out"; echo "        logger: $(cat "$d/logger_args" 2>/dev/null)"; fi
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
  # (#7898) the deliberate skip ships a SEND_SKIPPED row — never SEND_FAILED.
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" || ok=0
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_SKIPPED channel=resend reason=unset" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF "_SEND_FAILED" "$d/logger_args" 2>/dev/null && ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: missing Resend key still exits 0 (Sentry channel independent); SEND_SKIPPED reason=unset row";
  else FAIL=$((FAIL+1)); echo "  FAIL: missing env exit (rc=$rc) out: $out"; echo "        logger: $(cat "$d/logger_args" 2>/dev/null)"; fi
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
echo "--- (l) #7898 §2: transport confinement (argv position, both vendors) ---"
# Both credentialed curls (Sentry store + Resend) must carry the four flags as
# argv[1..6] with exactly one --noproxy. `checked == 2` pins that the stub saw
# BOTH members — a host filter that silently dropped .sentry.io would read 1 and
# pass an unconfined Sentry call (under a full mock an invocation count is not a
# wall-clock quantity, so pinning it is sound).
t_confined_alert() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local checked=0
  [[ -f "$d/curl_checked" ]] && checked=$(wc -l < "$d/curl_checked" | tr -d ' ')
  if [[ "$rc" -eq 0 && ! -f "$d/curl_violations" && "$checked" -eq 2 ]]; then
    PASS=$((PASS+1)); echo "  PASS: alert tick: Sentry + Resend curls both confined (checked=2, no violations)"
  else
    FAIL=$((FAIL+1)); echo "  FAIL: confinement (rc=$rc checked=$checked) violations: $(cat "$d/curl_violations" 2>/dev/null)"; echo "        curl: $(cat "$d/curl_args" 2>/dev/null)"
  fi
  rm -rf "$d"
}
t_confined_alert

echo ""
echo "--- (m) #7898 §2: Sentry destination pin (Guard 1) ---"
# (a) refused apex: the kept NEGATIVE fixture. No Sentry curl, a REFUSED marker
# with a reason TOKEN (never the host), the Resend email still fires carrying
# the refusal note, exit 0, and no logger argv carries the refused host.
t_pin_refused_host() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_HOST=ingest.example.test; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qF "example.test" "$d/curl_args" 2>/dev/null && ok=0            # no Sentry curl to the refused host
  resend_hit "$d" || ok=0                                                # Resend channel survives
  grep -qF "sentry channel refused" "$d/curl_args" 2>/dev/null || ok=0  # note rides the email payload
  printf '%s\n' "$out" | grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=host-shape" || ok=0
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=host-shape" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF "example.test" "$d/logger_args" 2>/dev/null && ok=0          # reason token only, never the host
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: refused ingest host → no Sentry curl, marker+crit row (reason token), email carries the note, exit 0";
  else FAIL=$((FAIL+1)); echo "  FAIL: refused-host row (rc=$rc) out: $out"; echo "        curl: $(cat "$d/curl_args" 2>/dev/null)"; echo "        logger: $(cat "$d/logger_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_pin_refused_host

# (b) must-PASS non-canonical: uppercase + one trailing dot folds to the
# positive host and the Sentry curl fires to the FOLDED host.
t_pin_folded_host() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_HOST="O0000000.INGEST.DE.SENTRY.IO."; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" || ok=0                                                # folded host in the request
  grep -qF "INGEST.DE.SENTRY.IO" "$d/curl_args" 2>/dev/null && ok=0     # never the raw value
  printf '%s\n' "$out" | grep -qF "_REFUSED channel=sentry" && ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: uppercase + trailing-dot host is accepted and the request uses the folded host";
  else FAIL=$((FAIL+1)); echo "  FAIL: folded-host row (rc=$rc) out: $out"; echo "        curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_pin_folded_host

# (c) smuggling: a path/query suffix and a percent-encoded separator (which a
# deny-list arm would pass to curl's own hostname check) are both refused.
t_pin_smuggled_host() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  local ok=1 host out rc
  for host in "o0000000.ingest.de.sentry.io/?x=" "evil.example%2F.ingest.de.sentry.io"; do
    rm -rf "$d"; d=$(mktemp -d); seed_baseline "$d" "cid-A" 0 0
    out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_HOST="$host"; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
    [[ "$rc" -eq 0 ]] || ok=0
    grep -qF "sentry.io" "$d/curl_args" 2>/dev/null && ok=0             # no Sentry curl at all
    printf '%s\n' "$out" | grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=host-shape" || ok=0
    resend_hit "$d" || ok=0
  done
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: path/query suffix and %2F-encoded separator are refused with reason=host-shape";
  else FAIL=$((FAIL+1)); echo "  FAIL: smuggled-host row (rc=$rc, last host=$host) out: $out"; echo "        curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_pin_smuggled_host

# (d) key shape: the kept NEGATIVE key fixture (not 32 hex) with a valid host.
t_pin_bad_key() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_KEY=pubkey_test; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" && ok=0
  printf '%s\n' "$out" | grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=key-shape" || ok=0
  grep -qF "pubkey_test" "$d/logger_args" 2>/dev/null && ok=0
  resend_hit "$d" || ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo  "  PASS: non-hex public key is refused with reason=key-shape; email still fires";
  else FAIL=$((FAIL+1)); echo "  FAIL: bad-key row (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_pin_bad_key

# (d2) project shape: a traversal suffix on the project id with a valid host/key.
t_pin_bad_project() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_PROJECT="4321/../evil"; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qF "sentry.io" "$d/curl_args" 2>/dev/null && ok=0
  printf '%s\n' "$out" | grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_REFUSED channel=sentry reason=project-shape" || ok=0
  resend_hit "$d" || ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo  "  PASS: non-numeric project id is refused with reason=project-shape; email still fires";
  else FAIL=$((FAIL+1)); echo "  FAIL: bad-project row (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_pin_bad_project

# (e) triple UNSET on an alert tick: the pre-existing "Sentry env unset" branch
# is kept verbatim and — under set -u — must not abort before the Resend send
# (the only surviving channel).
t_pin_triple_unset() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_UNSET=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qF "sentry.io" "$d/curl_args" 2>/dev/null && ok=0
  printf '%s\n' "$out" | grep -qF "Sentry env unset" || ok=0
  printf '%s\n' "$out" | grep -qF "_REFUSED channel=sentry" && ok=0     # unset is not a refusal
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_SKIPPED channel=sentry reason=unset" "$d/logger_args" 2>/dev/null || ok=0   # but it is shipped off-box
  resend_hit "$d" || ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: triple unset → 'Sentry env unset' log + SEND_SKIPPED row, no refusal marker, Resend still fires, exit 0";
  else FAIL=$((FAIL+1)); echo "  FAIL: triple-unset row (rc=$rc) out: $out"; echo "        curl: $(cat "$d/curl_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_pin_triple_unset

echo ""
echo "--- (n) #7898: logger absent from PATH → exit 0, stderr names the gap ---"
t_logger_absent() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_RESEND_FAIL=1 MOCK_LOGGER_ABSENT=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" || ok=0
  printf '%s\n' "$out" | grep -qF "logger=absent" || ok=0
  [[ -f "$d/logger_args" ]] && ok=0
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: logger absent: alert still posts, exit 0, stderr carries logger=absent";
  else FAIL=$((FAIL+1)); echo "  FAIL: logger-absent row (rc=$rc) out: $out"; fi
  rm -rf "$d"
}
t_logger_absent

echo ""
echo "--- (o) #7898 P9: failed sends ship a SEND_FAILED row per channel ---"
t_sentry_500() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_SENTRY_FAIL=1; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  sentry_hit "$d" || ok=0
  resend_hit "$d" || ok=0
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=sentry http_code=500 rc=0" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF "channel=resend" "$d/logger_args" 2>/dev/null && ok=0     # Resend side was healthy
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: Sentry 500 → SEND_FAILED channel=sentry http_code=500 rc=0; Resend still sends";
  else FAIL=$((FAIL+1)); echo "  FAIL: sentry-500 row (rc=$rc) out: $out"; echo "        logger: $(cat "$d/logger_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_sentry_500

t_curl_exit_7() {
  TOTAL=$((TOTAL + 1)); local d; d=$(mktemp -d)
  seed_baseline "$d" "cid-A" 0 0
  local out rc
  out=$(export MOCK_DOCKER_ID=cid-A MOCK_RESTART_COUNT=3 MOCK_CURL_EXIT=7; setup_mocks_and_run "$d" 2>&1) && rc=0 || rc=$?
  local ok=1
  [[ "$rc" -eq 0 ]] || ok=0
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=sentry http_code=000 rc=7" "$d/logger_args" 2>/dev/null || ok=0
  grep -qF "SOLEUR_CONTAINER_RESTART_MONITOR_SEND_FAILED channel=resend http_code=000 rc=7" "$d/logger_args" 2>/dev/null || ok=0
  [[ ! -f "$d/curl_violations" ]] || ok=0      # the failing calls still carried the flags
  if [[ "$ok" -eq 1 ]]; then PASS=$((PASS+1)); echo "  PASS: curl exit 7 on both channels → http_code=000 rc=7 rows, flags present, exit 0";
  else FAIL=$((FAIL+1)); echo "  FAIL: curl-exit-7 row (rc=$rc) out: $out"; echo "        logger: $(cat "$d/logger_args" 2>/dev/null)"; fi
  rm -rf "$d"
}
t_curl_exit_7

# Static rows over the script source (#7898 review): a credentialed curl must
# never follow redirects (curl forwards a custom auth header cross-host on a
# 3xx), and no invocation may be path-qualified (a `/usr/bin/curl` bypasses
# this PATH stub AND the Rule D linter's CURL_INVOKE regex). Anchored on the
# call form so a comment cannot satisfy either.
t_static_curl_shape() {
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
t_static_curl_shape

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

# Anti-vacuity floor (ADR-193): the results line above is a human convention;
# CI reads only the exit status, so a deleted row-dispatch line would vanish
# green. Read the INDEPENDENT total and report directly — never through the
# PASS/FAIL accounting this backstops. Ratchet when adding rows.
if [[ "$TOTAL" -lt 29 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d row(s) ran, expected >= 29. A row was deleted or its dispatch line removed.\n' "$TOTAL" >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
