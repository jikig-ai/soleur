#!/usr/bin/env bash
# Tests for infra-config-apply.sh — the webhook handler for /hooks/infra-config.
# Runs in a tmpdir sandbox; no root required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="${SCRIPT_DIR}/infra-config-apply.sh"

PASS=0
FAIL=0
TMPDIR_ROOT=""

setup() {
  TMPDIR_ROOT=$(mktemp -d)
  export TEST_DESTDIR="${TMPDIR_ROOT}/dest"
  mkdir -p "$TEST_DESTDIR/usr/local/bin" \
           "$TEST_DESTDIR/etc/systemd/system" \
           "$TEST_DESTDIR/etc/webhook" \
           "$TEST_DESTDIR/etc/default" \
           "$TEST_DESTDIR/etc/sudoers.d"
  # Mock visudo that always passes
  mkdir -p "$TMPDIR_ROOT/bin"
  printf '#!/bin/sh\nexit 0\n' > "$TMPDIR_ROOT/bin/visudo"
  chmod +x "$TMPDIR_ROOT/bin/visudo"
  # Mock systemd-run + systemctl (no-ops in test)
  printf '#!/bin/sh\nexit 0\n' > "$TMPDIR_ROOT/bin/systemd-run"
  printf '#!/bin/sh\nexit 0\n' > "$TMPDIR_ROOT/bin/systemctl"
  printf '#!/bin/sh\nexit 0\n' > "$TMPDIR_ROOT/bin/sudo"
  # Mock sync (no-op in test)
  printf '#!/bin/sh\nexit 0\n' > "$TMPDIR_ROOT/bin/sync"
  chmod +x "$TMPDIR_ROOT/bin/systemd-run" "$TMPDIR_ROOT/bin/systemctl" "$TMPDIR_ROOT/bin/sudo" "$TMPDIR_ROOT/bin/sync"
  # Mock logger that captures calls to a file
  LOGGER_LOG="${TMPDIR_ROOT}/logger.log"
  printf '#!/bin/sh\necho "$@" >> "%s"\n' "$LOGGER_LOG" > "$TMPDIR_ROOT/bin/logger"
  chmod +x "$TMPDIR_ROOT/bin/logger"
  export PATH="$TMPDIR_ROOT/bin:$PATH"
  # Redirect state file to sandbox
  export INFRA_CONFIG_STATE="${TMPDIR_ROOT}/infra-config-apply.state"
  # Stub out daemon-reload and self-restart for test mode
  export INFRA_CONFIG_TEST_MODE=1
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
  unset TEST_DESTDIR INFRA_CONFIG_TEST_MODE INFRA_CONFIG_STATE
  unset INFRA_CONFIG_STAGING_DIR INFRA_CONFIG_INSTALL_HELPER
}

export_valid_env_vars() {
  export CI_DEPLOY_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "[Unit]" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export HOOKS_JSON_B64=$(echo -n '{}' | base64 -w0)
  export CAT_INFRA_CONFIG_STATE_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export INNGEST_ENUMERATE_REMINDERS_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export INNGEST_REARM_REMINDERS_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export INNGEST_WIPED_VOLUME_VERIFY_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
  export CAT_INNGEST_VERIFY_STATE_SH_B64=$(echo -n "#!/bin/bash" | base64 -w0)
}

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — file not found: $path"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_mode() {
  local desc="$1" path="$2" expected_mode="$3"
  local actual_mode
  actual_mode=$(stat -c '%a' "$path" 2>/dev/null || echo "missing")
  if [[ "$actual_mode" == "$expected_mode" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — mode mismatch"
    echo "    expected: $expected_mode"
    echo "    actual:   $actual_mode"
    FAIL=$((FAIL + 1))
  fi
}

# --- Test 1: Happy path — all files written with correct content and permissions ---
test_happy_path() {
  echo "TEST: happy path — all managed files written"
  setup

  export_valid_env_vars

  bash "$HANDLER"
  local rc=$?
  assert_eq "handler exits 0" "0" "$rc"

  assert_file_exists "ci-deploy.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh"
  assert_file_exists "ci-deploy-wrapper.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy-wrapper.sh"
  assert_file_exists "webhook.service written" "$TEST_DESTDIR/etc/systemd/system/webhook.service"
  assert_file_exists "cat-deploy-state.sh written" "$TEST_DESTDIR/usr/local/bin/cat-deploy-state.sh"
  assert_file_exists "canary-bundle-claim-check.sh written" "$TEST_DESTDIR/usr/local/bin/canary-bundle-claim-check.sh"
  assert_file_exists "hooks.json written" "$TEST_DESTDIR/etc/webhook/hooks.json"
  # #4827: the sudoers grant is NO LONGER webhook-managed (root-only delivery) —
  # the handler must not write it even in sandbox mode.
  if [[ -f "$TEST_DESTDIR/etc/sudoers.d/deploy-inngest-bootstrap" ]]; then
    echo "  FAIL: sudoers must not be written by the handler (#4827 root-managed)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: sudoers correctly not written by the handler"
    PASS=$((PASS + 1))
  fi
  assert_file_exists "cat-infra-config-state.sh written" "$TEST_DESTDIR/usr/local/bin/cat-infra-config-state.sh"

  assert_file_mode "ci-deploy.sh is executable" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh" "755"
  assert_file_mode "hooks.json is 640" "$TEST_DESTDIR/etc/webhook/hooks.json" "640"

  teardown
}

# --- Test 2: Missing env var → exits non-zero (partial-apply contract, #4804) ---
# Post-#4804 the handler no longer aborts all writes on a missing var; it records
# a per-file missing_env failure, writes the rest, and exits 1. This test pins the
# exit-code + per-file-failure dimension; test_missing_env_partial_write pins the
# "other files still written" dimension.
test_missing_env_var() {
  echo "TEST: missing env var — exits non-zero with a per-file missing_env failure"
  setup

  # Set all but one required var
  export_valid_env_vars
  unset HOOKS_JSON_B64  # missing

  local rc=0
  bash "$HANDLER" 2>/dev/null || rc=$?
  assert_eq "handler exits 1 on missing var" "1" "$rc"

  local files_failed missing_reason
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  missing_reason=$(jq -r '.files[] | select(.file == "/etc/webhook/hooks.json") | .reason' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "files_failed is 1" "1" "$files_failed"
  assert_eq "missing file reason is missing_env" "missing_env" "$missing_reason"

  teardown
}

# --- Test 3: Empty env var → exits non-zero with a per-file missing_env failure ---
# An empty (vs unset) payload var takes the same missing_env arm (`-z` covers both).
test_empty_env_var() {
  echo "TEST: empty env var — exits non-zero with a per-file missing_env failure"
  setup

  export_valid_env_vars
  export CI_DEPLOY_SH_B64=""

  local rc=0
  bash "$HANDLER" 2>/dev/null || rc=$?
  assert_eq "handler exits 1 on empty var" "1" "$rc"

  local files_failed empty_reason
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  empty_reason=$(jq -r '.files[] | select(.file == "/usr/local/bin/ci-deploy.sh") | .reason' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "files_failed is 1" "1" "$files_failed"
  assert_eq "empty-var file reason is missing_env" "missing_env" "$empty_reason"

  teardown
}

# --- Test 5: Atomic write — no partial file at destination ---
test_atomic_write() {
  echo "TEST: atomic write — destination only has complete file"
  setup

  local content="line1\nline2\nline3\nthis is the end"
  export_valid_env_vars
  export CI_DEPLOY_SH_B64=$(echo -n "$content" | base64 -w0)

  bash "$HANDLER"

  local actual
  actual=$(cat "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh")
  assert_eq "file content matches exactly" "$content" "$actual"

  # Verify no temp files left behind in the destination dirs
  local stray
  stray=$(find "$TEST_DESTDIR" -name 'tmp.*' -o -name '.tmp*' 2>/dev/null | wc -l)
  assert_eq "no stray temp files" "0" "$stray"

  teardown
}

# --- Test 6: State file happy path — all files succeed ---
test_state_file_happy_path() {
  echo "TEST: state file — happy path with per-file SHA and status ok"
  setup
  export_valid_env_vars

  bash "$HANDLER" 2>/dev/null

  assert_file_exists "state file written" "$INFRA_CONFIG_STATE"

  local exit_code files_written files_failed
  exit_code=$(jq -r '.exit_code' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_written=$(jq -r '.files_written' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  local files_total
  files_total=$(jq -r '.files_total' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "exit_code is 0" "0" "$exit_code"
  assert_eq "files_written is 11" "11" "$files_written"
  assert_eq "files_failed is 0" "0" "$files_failed"
  assert_eq "files_total is 11" "11" "$files_total"

  local first_file_status first_file_sha
  first_file_status=$(jq -r '.files[0].status' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  first_file_sha=$(jq -r '.files[0].sha256' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "first file status is ok" "ok" "$first_file_status"
  if [[ "$first_file_sha" =~ ^[a-f0-9]{64}$ ]]; then
    echo "  PASS: first file has valid SHA256"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: first file SHA256 invalid: $first_file_sha"
    FAIL=$((FAIL + 1))
  fi

  local start_ts end_ts
  start_ts=$(jq -r '.start_ts' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  end_ts=$(jq -r '.end_ts' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  if [[ "$start_ts" =~ ^[0-9]+$ ]] && [[ "$end_ts" =~ ^[0-9]+$ ]]; then
    echo "  PASS: timestamps are numeric"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: timestamps not numeric (start=$start_ts, end=$end_ts)"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- Test 7: State file partial failure — bad base64 ---
test_state_file_partial_failure() {
  echo "TEST: state file — partial failure with bad base64"
  setup
  export_valid_env_vars
  # Inject invalid base64 for one file
  export CI_DEPLOY_SH_B64="!!!not-valid-base64!!!"

  bash "$HANDLER" 2>/dev/null || true

  assert_file_exists "state file written on partial failure" "$INFRA_CONFIG_STATE"

  local exit_code files_failed
  exit_code=$(jq -r '.exit_code' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "exit_code is non-zero" "1" "$exit_code"
  if [[ "$files_failed" =~ ^[0-9]+$ ]] && [[ "$files_failed" -gt 0 ]]; then
    echo "  PASS: files_failed > 0"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: files_failed should be > 0, got $files_failed"
    FAIL=$((FAIL + 1))
  fi

  local failed_file_status
  failed_file_status=$(jq -r '.files[] | select(.file == "/usr/local/bin/ci-deploy.sh") | .status' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "failed file status" "failed" "$failed_file_status"

  local ok_count
  ok_count=$(jq '[.files[] | select(.status == "ok")] | length' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "0")
  if [[ "$ok_count" =~ ^[0-9]+$ ]] && [[ "$ok_count" -gt 0 ]]; then
    echo "  PASS: other files still succeeded ($ok_count ok)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no files succeeded despite only 1 bad input"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- Test 9: Logger output uses correct tag ---
test_logger_tag() {
  echo "TEST: logger — output uses infra-config-apply tag"
  setup
  export_valid_env_vars

  bash "$HANDLER" 2>/dev/null

  if [[ -f "$LOGGER_LOG" ]] && grep -q "infra-config-apply" "$LOGGER_LOG"; then
    echo "  PASS: logger called with correct tag"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no logger calls with tag infra-config-apply"
    FAIL=$((FAIL + 1))
  fi

  if grep -q "starting:" "$LOGGER_LOG" 2>/dev/null; then
    echo "  PASS: logger start message present"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no logger start message"
    FAIL=$((FAIL + 1))
  fi

  if grep -q "complete:" "$LOGGER_LOG" 2>/dev/null; then
    echo "  PASS: logger completion message present"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no logger completion message"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- Test 10: Self-restart ordering — state file before systemd-run ---
test_restart_ordering() {
  echo "TEST: restart ordering — state file written before systemd-run"
  setup
  export_valid_env_vars
  unset INFRA_CONFIG_TEST_MODE

  local order_log="${TMPDIR_ROOT}/order.log"
  # Replace systemd-run mock to record call time relative to state file
  cat > "$TMPDIR_ROOT/bin/sudo" <<MOCK
#!/bin/sh
if echo "\$@" | grep -q "systemd-run"; then
  if [ -f "$INFRA_CONFIG_STATE" ]; then
    echo "systemd-run: state_file_exists=true" >> "$order_log"
  else
    echo "systemd-run: state_file_exists=false" >> "$order_log"
  fi
fi
exit 0
MOCK
  chmod +x "$TMPDIR_ROOT/bin/sudo"

  bash "$HANDLER" 2>/dev/null

  if [[ -f "$order_log" ]] && grep -q "state_file_exists=true" "$order_log"; then
    echo "  PASS: state file exists when systemd-run is called"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: state file should exist before systemd-run"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- Test 11: EXIT trap writes unhandled state on crash ---
test_exit_trap_unhandled() {
  echo "TEST: EXIT trap — writes unhandled state on non-zero exit"
  setup
  export_valid_env_vars
  # Make first dest dir read-only so mv fails, triggering set -e abort and EXIT trap
  chmod 000 "$TEST_DESTDIR/usr/local/bin"

  bash "$HANDLER" 2>/dev/null || true

  if [[ -f "$INFRA_CONFIG_STATE" ]]; then
    local reason
    reason=$(jq -r '.reason' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
    assert_eq "exit trap writes unhandled reason" "unhandled" "$reason"
  else
    echo "  FAIL: no state file written by EXIT trap"
    FAIL=$((FAIL + 1))
  fi

  chmod 755 "$TEST_DESTDIR/usr/local/bin"
  teardown
}

# --- Test 12: Partial write — one missing env var writes the other 6 (#4804) ---
# Regression guard for the chicken-and-egg freeze: when the host's stale
# hooks.json fails to pass a newly-added payload key, the corresponding env var
# is empty on the host. The handler must record a per-file missing_env failure
# and STILL write the other files (crucially the new hooks.json that re-aligns
# the env mapping), instead of the former upfront all-or-nothing exit 1 that
# wrote nothing and froze every file.
test_missing_env_partial_write() {
  echo "TEST: one missing env var — other 10 files still written (#4804)"
  setup
  export_valid_env_vars
  unset CAT_INFRA_CONFIG_STATE_SH_B64  # simulate host hooks.json drift on the newest key

  local rc=0
  bash "$HANDLER" 2>/dev/null || rc=$?
  assert_eq "handler exits 1 on partial failure" "1" "$rc"

  # The 6 present files are still written
  assert_file_exists "ci-deploy.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh"
  assert_file_exists "ci-deploy-wrapper.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy-wrapper.sh"
  assert_file_exists "webhook.service written" "$TEST_DESTDIR/etc/systemd/system/webhook.service"
  assert_file_exists "cat-deploy-state.sh written" "$TEST_DESTDIR/usr/local/bin/cat-deploy-state.sh"
  assert_file_exists "canary-bundle-claim-check.sh written" "$TEST_DESTDIR/usr/local/bin/canary-bundle-claim-check.sh"
  assert_file_exists "hooks.json written (self-heals env mapping)" "$TEST_DESTDIR/etc/webhook/hooks.json"

  # The missing-env file is NOT written
  if [[ -f "$TEST_DESTDIR/usr/local/bin/cat-infra-config-state.sh" ]]; then
    echo "  FAIL: missing-env file should not be written"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: missing-env file correctly not written"
    PASS=$((PASS + 1))
  fi

  # State JSON counts: 10 written, 1 failed, 11 total
  local files_written files_failed files_total
  files_written=$(jq -r '.files_written' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_total=$(jq -r '.files_total' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "files_written is 10" "10" "$files_written"
  assert_eq "files_failed is 1" "1" "$files_failed"
  assert_eq "files_total is 11" "11" "$files_total"

  # The missing file's entry records status:failed, reason:missing_env
  local mstatus mreason
  mstatus=$(jq -r '.files[] | select(.file == "/usr/local/bin/cat-infra-config-state.sh") | .status' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  mreason=$(jq -r '.files[] | select(.file == "/usr/local/bin/cat-infra-config-state.sh") | .reason' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "missing file status is failed" "failed" "$mstatus"
  assert_eq "missing file reason is missing_env" "missing_env" "$mreason"

  teardown
}

# --- Test 13: Prod-mode escalated install — stage in deploy-writable dir, escalate via helper (#4827) ---
# RED-first: the current handler mktemps INSIDE each root-owned dest dir, which
# EACCESes as the deploy user. The fix stages the decoded payload in a
# deploy-writable staging dir and escalates the install to root via a pinned
# sudoers helper, piping the payload over STDIN (no caller-controlled source path,
# #4827 security review P1). This test asserts the handler (a) does NOT EACCES on a
# root-owned dest dir (it exits 0) and (b) invokes the pinned helper once per file
# with the correct (dest, mode, owner) AND the decoded payload on stdin. Runs in
# "prod mode" (TEST_DESTDIR unset) with a mocked sudo + helper recorder so no real
# root path is touched.
test_prod_mode_escalated_move() {
  echo "TEST: prod-mode escalated install — stage + escalate via pinned helper (#4827)"
  # Safety rail: the pre-fix handler mktemps in the REAL dest dirs. As a non-root
  # user that EACCESes (the intended RED signal). As root it would clobber real
  # system files, so refuse to run this case as root (CI runs non-root; the
  # sibling test_exit_trap_unhandled already assumes non-root).
  if [[ "$(id -u)" == "0" ]]; then
    echo "  SKIP: prod-mode escalation test must run as non-root"
    return 0
  fi
  setup
  # Switch from sandbox (test) mode to prod mode: unset TEST_DESTDIR so the
  # handler takes the escalated-write branch. Keep INFRA_CONFIG_TEST_MODE=1 so the
  # post-write self-restart block stays stubbed.
  unset TEST_DESTDIR

  # Deploy-writable staging dir (sandbox stand-in for /var/lock).
  export INFRA_CONFIG_STAGING_DIR="${TMPDIR_ROOT}/staging"
  mkdir -p "$INFRA_CONFIG_STAGING_DIR"

  # Helper recorder: append "dest|mode|owner|<stdin-payload>" per invocation,
  # write nothing. Reading stdin proves the handler pipes the decoded payload (the
  # P1 stdin contract) rather than passing a swappable file path.
  local helper_log="${TMPDIR_ROOT}/helper.log"
  export INFRA_CONFIG_INSTALL_HELPER="${TMPDIR_ROOT}/bin/infra-config-install-mock"
  printf '#!/bin/sh\nprintf "%%s|%%s|%%s|" "$1" "$2" "$3" >> "%s"\ncat >> "%s"\nprintf "\\n" >> "%s"\nexit 0\n' \
    "$helper_log" "$helper_log" "$helper_log" > "$INFRA_CONFIG_INSTALL_HELPER"
  chmod +x "$INFRA_CONFIG_INSTALL_HELPER"

  # Mock sudo to transparently exec its arguments (so `sudo helper ...` runs the
  # recorder) while PRESERVING stdin. Overrides the exit-0 stub from setup().
  printf '#!/bin/sh\nexec "$@"\n' > "$TMPDIR_ROOT/bin/sudo"
  chmod +x "$TMPDIR_ROOT/bin/sudo"

  export_valid_env_vars

  local rc=0
  bash "$HANDLER" 2>/dev/null || rc=$?
  assert_eq "handler exits 0 in prod mode" "0" "$rc"

  # The helper must be invoked once per managed file (7 total; sudoers is
  # root-managed and not in FILE_MAP, #4827 security review).
  local calls
  calls=$([[ -f "$helper_log" ]] && wc -l < "$helper_log" | tr -d ' ' || echo 0)
  assert_eq "escalation helper invoked once per file (11)" "11" "$calls"

  # The handler exiting 0 proves it staged in INFRA_CONFIG_STAGING_DIR rather than
  # mktemp-ing in a root-owned dest dir (which would EACCES as non-root) — the
  # exact bug this fix removes. Confirm the staging dir is the one configured.
  assert_eq "staging dir is the deploy-writable sandbox" "${TMPDIR_ROOT}/staging" "$INFRA_CONFIG_STAGING_DIR"

  # Spot-check the ci-deploy.sh invocation: correct (dest, mode, owner) AND the
  # decoded payload piped over stdin (export_valid_env_vars sets it to "#!/bin/bash").
  local cideploy_line
  cideploy_line=$(grep '^/usr/local/bin/ci-deploy.sh|' "$helper_log" 2>/dev/null || echo "")
  if [[ "$cideploy_line" == "/usr/local/bin/ci-deploy.sh|755|root:root|#!/bin/bash" ]]; then
    echo "  PASS: ci-deploy.sh escalated with dest+mode+owner and decoded payload on stdin"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ci-deploy.sh escalation wrong: '$cideploy_line'"
    FAIL=$((FAIL + 1))
  fi

  # State JSON should report all 7 written, exit 0.
  local files_written exit_code
  files_written=$(jq -r '.files_written' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  exit_code=$(jq -r '.exit_code' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "prod-mode files_written is 11" "11" "$files_written"
  assert_eq "prod-mode exit_code is 0" "0" "$exit_code"

  teardown
}

# --- Run all tests ---
echo "=== infra-config-apply.sh test suite ==="
test_happy_path
test_missing_env_var
test_empty_env_var
test_atomic_write
test_state_file_happy_path
test_state_file_partial_failure
test_logger_tag
test_restart_ordering
test_exit_trap_unhandled
test_missing_env_partial_write
test_prod_mode_escalated_move
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
