#!/usr/bin/env bash
# Tests for infra-config-apply.sh — the webhook handler for /hooks/infra-config.
# Runs in a tmpdir sandbox; no root required.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HANDLER="${SCRIPT_DIR}/infra-config-apply.sh"

# #7095 — managed-file cardinality, DERIVED from the handler's own FILE_MAP rather than pinned
# as a literal. The previous hardcoded 15 had to be edited in lockstep with every FILE_MAP
# addition, which is the drift these counts exist to detect; a stale literal turns a real
# regression and a routine addition into the same red. MANAGED_N ratchets automatically.
MANAGED_N=$(sed -n '/^FILE_MAP=(/,/^)/p' "$HANDLER" | grep -cE '^[[:space:]]*"[A-Z0-9_]+\|')
if [[ "${MANAGED_N:-0}" -lt 15 ]]; then
  echo "FATAL: derived MANAGED_N=$MANAGED_N from $HANDLER FILE_MAP — parse is broken; every count assertion below would be vacuous" >&2
  exit 2
fi
MANAGED_MINUS_1=$((MANAGED_N - 1))

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

# #6178: the handler now reads each payload as a FILE PATH — hooks.json.tmpl's infra-config
# hook uses pass-file-to-command + base64decode, so webhook writes the DECODED content to a
# temp file and passes its PATH via the env var (this dodges the 128KB MAX_ARG_STRLEN exec-env
# ceiling that ci-deploy.sh's ~140KB base64 blew, killing fork/exec with E2BIG). So these test
# env vars hold PATHS to files with the already-decoded content — NOT base64 strings.
_payload_file() {  # <content> → prints a fresh temp-file path holding exactly that content
  local f; f=$(mktemp "${TMPDIR_ROOT}/payload.XXXXXX"); printf '%s' "$1" > "$f"; printf '%s' "$f"
}
export_valid_env_vars() {
  export CI_DEPLOY_SH_B64=$(_payload_file "#!/bin/bash")
  export CI_DEPLOY_WRAPPER_SH_B64=$(_payload_file "#!/bin/bash")
  export WEBHOOK_SERVICE_B64=$(_payload_file "[Unit]")
  export CAT_DEPLOY_STATE_SH_B64=$(_payload_file "#!/bin/bash")
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(_payload_file "#!/bin/bash")
  export HOOKS_JSON_B64=$(_payload_file '{}')
  export CAT_INFRA_CONFIG_STATE_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_ENUMERATE_REMINDERS_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_REARM_REMINDERS_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_WIPED_VOLUME_VERIFY_SH_B64=$(_payload_file "#!/bin/bash")
  export CAT_INNGEST_VERIFY_STATE_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_INVENTORY_SH_B64=$(_payload_file "#!/bin/bash")
  export GIT_LOCK_CHARDEVICE_SWEEP_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_REGISTRY_PROBE_SH_B64=$(_payload_file "#!/bin/bash")
  export INNGEST_DOUBLEFIRE_PROBE_SH_B64=$(_payload_file "#!/bin/bash")
  # #7095 — the re-deliverable Doppler credential + the two drop-ins re-pointing the
  # generated units (vector, inngest-heartbeat) at it. The credential payload MUST be valid
  # KEY=VALUE: infra-config-install.sh rejects a malformed /etc/default/* payload outright
  # (envfile_shape), which is the guard that stops a bad render bricking the delivery channel.
  export SOLEUR_DOPPLER_TOKEN_B64=$(_payload_file "DOPPLER_TOKEN=dp.st.test-fixture")
  export VECTOR_DOPPLER_TOKEN_CONF_B64=$(_payload_file "[Service]")
  export INNGEST_HEARTBEAT_DOPPLER_TOKEN_CONF_B64=$(_payload_file "[Service]")
  export INNGEST_SERVER_DOPPLER_TOKEN_CONF_B64=$(_payload_file "[Service]")
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
  assert_file_exists "git-lock-chardevice-sweep.sh written (#5934)" "$TEST_DESTDIR/usr/local/bin/git-lock-chardevice-sweep.sh"

  assert_file_mode "ci-deploy.sh is executable" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh" "755"
  assert_file_mode "git-lock-chardevice-sweep.sh is executable (#5934)" "$TEST_DESTDIR/usr/local/bin/git-lock-chardevice-sweep.sh" "755"
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
  export CI_DEPLOY_SH_B64=$(_payload_file "$content")

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
  assert_eq "files_written is MANAGED_N ($MANAGED_N)" "$MANAGED_N" "$files_written"
  assert_eq "files_failed is 0" "0" "$files_failed"
  assert_eq "files_total is MANAGED_N ($MANAGED_N)" "$MANAGED_N" "$files_total"

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

# --- Test 7: State file partial failure — unreadable payload file ---
test_state_file_partial_failure() {
  echo "TEST: state file — partial failure with an unreadable payload file"
  setup
  export_valid_env_vars
  # #6178: payloads are now FILE PATHS (pass-file-to-command). Point one at a path that
  # does not exist so the handler's cp fails (reason=payload_file_unreadable) while the
  # rest still land — the per-file failure contract.
  export CI_DEPLOY_SH_B64="${TMPDIR_ROOT}/does-not-exist-payload"

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
  echo "TEST: one missing env var — the other MANAGED_N-1 files still written (#4804)"
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

  # State JSON counts: MANAGED_N-1 written, 1 failed, MANAGED_N total (one env var deliberately missing)
  local files_written files_failed files_total
  files_written=$(jq -r '.files_written' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_failed=$(jq -r '.files_failed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  files_total=$(jq -r '.files_total' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "files_written is MANAGED_N-1 ($MANAGED_MINUS_1)" "$MANAGED_MINUS_1" "$files_written"
  assert_eq "files_failed is 1" "1" "$files_failed"
  assert_eq "files_total is MANAGED_N ($MANAGED_N)" "$MANAGED_N" "$files_total"

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

  # The helper must be invoked once per managed file (15 total; sudoers is
  # root-managed and not in FILE_MAP, #4827 security review).
  local calls
  calls=$([[ -f "$helper_log" ]] && wc -l < "$helper_log" | tr -d ' ' || echo 0)
  assert_eq "escalation helper invoked once per file ($MANAGED_N)" "$MANAGED_N" "$calls"

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
  assert_eq "prod-mode files_written is MANAGED_N ($MANAGED_N)" "$MANAGED_N" "$files_written"
  assert_eq "prod-mode exit_code is 0" "0" "$exit_code"

  teardown
}

# --- #5509: b64 delivery-surface parity (push ↔ FILE_MAP ↔ pass-environment) ---
# The three surfaces that carry a host file from the push payload to disk MUST
# enumerate the SAME key set: push-infra-config.sh payload "<key>_b64", this
# handler's FILE_MAP <ENV>|, and hooks.json.tmpl's pass-environment-to-command
# envname. A key in push + FILE_MAP but MISSING from pass-environment means the
# file is pushed but never written (missing_env) — the silent break #5509 review
# caught (inngest-inventory.sh was in 11 surfaces but not the pass-environment bridge).
test_b64_delivery_parity() {
  local push="${SCRIPT_DIR}/push-infra-config.sh"
  local hooks="${SCRIPT_DIR}/hooks.json.tmpl"
  local push_keys map_vars pass_vars
  push_keys=$(grep -oE '"[a-z0-9_]+_b64":' "$push" | sed -E 's/"([a-z0-9_]+)":/\1/' | tr '[:lower:]' '[:upper:]' | sort -u)
  map_vars=$(sed -n '/^FILE_MAP=(/,/^)/p' "$HANDLER" | grep -oE '"[A-Z0-9_]+_B64\|' | tr -d '"|' | sort -u)
  pass_vars=$(grep -oE '"envname": "[A-Z0-9_]+_B64"' "$hooks" | sed -E 's/.*"([A-Z0-9_]+)".*/\1/' | sort -u)
  if [[ "$push_keys" == "$map_vars" && "$map_vars" == "$pass_vars" ]]; then
    echo "  PASS: push payload ↔ FILE_MAP ↔ pass-environment b64 key sets are identical ($(echo "$push_keys" | wc -l | tr -d ' ') keys)"; PASS=$((PASS + 1));
  else
    echo "  FAIL: b64 delivery-surface drift (a file pushed but not env-bridged is written nowhere)"
    echo "    push vs FILE_MAP diff:"; comm -3 <(echo "$push_keys") <(echo "$map_vars") | sed 's/^/      /'
    echo "    FILE_MAP vs pass-environment diff:"; comm -3 <(echo "$map_vars") <(echo "$pass_vars") | sed 's/^/      /'
    FAIL=$((FAIL + 1)); fi
}

# --- #6178: orphan-hook self-check — a hooks.json execute-command pointing at a
# /usr/local/bin script NOT on disk after the push is a DANGLING HOOK (webhook
# fork/exec's a missing file → empty HTTP 500). The handler must flag it LOUD
# (files[] reason=orphan_hook_command + exit 1 + SOLEUR_INFRA_CONFIG_HOOK_ORPHAN
# marker), while a hook pointing at a delivered FILE_MAP script is NOT flagged.
test_orphan_hook_selfcheck() {
  echo "TEST: orphan-hook self-check — dangling hook command fails loud (#6178)"
  setup
  export_valid_env_vars
  # hooks.json referencing one DELIVERED script (inngest-inventory.sh ∈ FILE_MAP)
  # and one UNDELIVERED script (orphan-missing.sh ∉ FILE_MAP → never on disk).
  export HOOKS_JSON_B64=$(_payload_file '[{"id":"good","execute-command":"/usr/local/bin/inngest-inventory.sh"},{"id":"orphan","execute-command":"/usr/local/bin/orphan-missing.sh"}]')

  local rc=0
  bash "$HANDLER" 2>/dev/null || rc=$?
  assert_eq "handler exits 1 on dangling hook" "1" "$rc"

  local orphan_reason good_flagged
  orphan_reason=$(jq -r '.files[] | select(.file == "/usr/local/bin/orphan-missing.sh") | .reason' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "orphan hook reason is orphan_hook_command" "orphan_hook_command" "$orphan_reason"

  # The delivered script's hook must NOT be flagged as orphan.
  good_flagged=$(jq -r '[.files[] | select(.file == "/usr/local/bin/inngest-inventory.sh" and .reason == "orphan_hook_command")] | length' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "delivered-script hook not flagged as orphan" "0" "$good_flagged"

  if grep -q "SOLEUR_INFRA_CONFIG_HOOK_ORPHAN" "$LOGGER_LOG" 2>/dev/null; then
    echo "  PASS: SOLEUR_INFRA_CONFIG_HOOK_ORPHAN marker emitted"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no SOLEUR_INFRA_CONFIG_HOOK_ORPHAN marker in logger output"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- #7103 R2 3.2: the DROPIN_TRY_RESTART grant, all three halves ---
# v1 of this work added only the Cmnd_Alias. An alias with no paired User_Spec grants NOTHING:
# every restart would be denied at runtime while a shape-only assertion on the alias stayed
# green — the exact silent-no-op the GIT_LOCK_CHARDEVICE_SWEEP header records ("sudo denies the
# sweep ... and the durable remediation is a SILENT no-op", #5934). Every other alias in the file
# is paired; this asserts the new one is too, in BOTH provisioning paths.
#
# The two argv are pinned here as data and reused by the lockstep assertion, so the units and
# their exact invocation form have ONE definition in this suite rather than three copies.
DROPIN_RESTART_ARGV=(
  "/usr/bin/systemctl try-restart inngest-heartbeat.service"
  "/usr/bin/systemctl try-restart vector.service"
)
test_dropin_restart_grant() {
  echo "TEST: sudoers — DROPIN_TRY_RESTART alias, User_Spec, and cloud-init mirror"
  local sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"
  local server_tf="${SCRIPT_DIR}/server.tf"
  local expected_alias="Cmnd_Alias DROPIN_TRY_RESTART = ${DROPIN_RESTART_ARGV[0]}, ${DROPIN_RESTART_ARGV[1]}"

  # (a) The alias, with byte-exact argv. sudo matches the FULL resolved command, so an absolute
  # path or a stray flag here is a denial at runtime, not a widening.
  if grep -qxF "$expected_alias" "$sudoers"; then
    echo "  PASS: sudoers declares the alias with the exact argv"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: sudoers missing exact alias line: $expected_alias"
    FAIL=$((FAIL + 1))
  fi

  # (b) The User_Spec that actually activates it. This is the half v1 omitted.
  if grep -qxF "deploy ALL=(root) NOPASSWD: DROPIN_TRY_RESTART" "$sudoers"; then
    echo "  PASS: sudoers pairs the alias with a deploy User_Spec"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: sudoers declares DROPIN_TRY_RESTART but never grants it to deploy"
    FAIL=$((FAIL + 1))
  fi

  # (c) Both halves mirrored into cloud-init (fresh hosts). Indented there, so match on the
  # config-line shape rather than requiring a whole-line equality.
  local ci_alias ci_spec
  ci_alias=$(grep -cE "^[[:space:]]*Cmnd_Alias DROPIN_TRY_RESTART = " "$cloud_init" || true)
  ci_spec=$(grep -cE "^[[:space:]]*deploy ALL=\(root\) NOPASSWD: DROPIN_TRY_RESTART[[:space:]]*$" "$cloud_init" || true)
  assert_eq "cloud-init mirrors the alias" "1" "$ci_alias"
  assert_eq "cloud-init mirrors the User_Spec" "1" "$ci_spec"

  # (d) The post-write assertion on the SSH bootstrap leg, mirroring the two that already guard
  # INFRA_CONFIG_INSTALL and GIT_LOCK_CHARDEVICE_SWEEP. Without it a sudoers that silently failed
  # to install would surface only as denied restarts much later.
  if grep -qE '"grep -q DROPIN_TRY_RESTART /etc/sudoers\.d/deploy-inngest-bootstrap"' "$server_tf"; then
    echo "  PASS: server.tf remote-exec asserts the grant landed"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: server.tf bootstrap leg does not assert DROPIN_TRY_RESTART landed"
    FAIL=$((FAIL + 1))
  fi

  # (e) NON-VACUITY: the units named in the grant must be the units the RESTART_MAP drives.
  # A grant for units the script never restarts, or a script restarting units the grant omits,
  # both read as "green" on (a)-(d) alone.
  local unit
  for unit in inngest-heartbeat.service vector.service; do
    if grep -qE "^[[:space:]]*\"?${unit}\"?" <(sed -n '/^RESTART_MAP=(/,/^)/p' "$HANDLER"); then
      echo "  PASS: RESTART_MAP drives $unit"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $unit is granted in sudoers but absent from the handler's RESTART_MAP"
      FAIL=$((FAIL + 1))
    fi
  done
}

# --- #7103 R2 3.10/3.11: unit reconciliation ------------------------------------------------
# These drive the predicate through the INFRA_CONFIG_SYSTEMCTL* seams. Without them every unit
# resolves to unit_inactive on a dev box or CI runner — the loop runs, reports, and exercises
# none of the logic worth testing. Measured before these existed: the suite was 70/70 green
# while the entire staleness/grading path was unreachable.
#
# The stubs are STATEFUL and argv-VALIDATING, both deliberately:
#   - stateful, because the contract under test is a TRANSITION (a timestamp that advances). A
#     stub returning one fixed answer cannot tell a restart that worked from one that did not,
#     so the grading arms would pass against an implementation that never re-read anything.
#   - argv-validating (exit 64), because a stub answering regardless of its arguments puts the
#     fixture seam ABOVE the code under test: the handler could query the wrong property, or
#     invoke the wrong verb, and every assertion would still be green.

# Write the two stubs into $1. Fixture state lives in $STUB_STATE as <unit>.<Property> files;
# arming <unit>.after.<Property> makes the restart stub apply that value, which is how a
# restart's EFFECT is scripted independently of its exit code.
make_restart_stubs() {
  local bindir="$1"
  cat > "$bindir/sc-show" <<'STUB'
#!/usr/bin/env bash
# Contract: show <unit> -p <Property> --value. Anything else is a caller defect, not a miss.
[[ "$1" == "show"   ]] || { echo "stub: expected 'show', got '$1'" >&2; exit 64; }
[[ "$3" == "-p"     ]] || { echo "stub: expected '-p', got '$3'" >&2; exit 64; }
[[ "$5" == "--value" ]] || { echo "stub: expected '--value', got '$5'" >&2; exit 64; }
f="$STUB_STATE/$2.$4"
[[ -f "$f" ]] && cat "$f"
exit 0
STUB
  cat > "$bindir/sc-restart" <<'STUB'
#!/usr/bin/env bash
# Records the FULL argv so ordering and sudoers lockstep are both checkable.
printf '%s\n' "$*" >> "$STUB_CALLS"
[[ "$1" == "try-restart" ]] || { echo "stub: expected 'try-restart', got '$1'" >&2; exit 64; }
unit="$2"
[[ -f "$STUB_STATE/$unit.deny" ]] && exit 1
for p in ActiveState ExecMainStartTimestamp NRestarts; do
  [[ -f "$STUB_STATE/$unit.after.$p" ]] && cp "$STUB_STATE/$unit.after.$p" "$STUB_STATE/$unit.$p"
done
exit 0
STUB
  chmod +x "$bindir/sc-show" "$bindir/sc-restart"
}

# systemd's own rendering of a timestamp, so `date -d` in the handler parses exactly the shape
# it will meet in production rather than a convenient ISO string.
sd_ts() { date -u -d "@$1" '+%a %Y-%m-%d %H:%M:%S UTC'; }

# Arm a unit's pre-restart state, and optionally the state a successful restart lands it in.
arm_unit() {
  local unit="$1" active="$2" ts_epoch="$3"
  printf '%s' "$active" > "$STUB_STATE/$unit.ActiveState"
  if [[ -n "$ts_epoch" ]]; then printf '%s' "$(sd_ts "$ts_epoch")" > "$STUB_STATE/$unit.ExecMainStartTimestamp"
  else : > "$STUB_STATE/$unit.ExecMainStartTimestamp"; fi
  printf '0' > "$STUB_STATE/$unit.NRestarts"
}
arm_after() {
  local unit="$1" active="$2" ts_epoch="$3"
  printf '%s' "$active" > "$STUB_STATE/$unit.after.ActiveState"
  [[ -n "$ts_epoch" ]] && printf '%s' "$(sd_ts "$ts_epoch")" > "$STUB_STATE/$unit.after.ExecMainStartTimestamp"
  printf '1' > "$STUB_STATE/$unit.after.NRestarts"
}

restart_setup() {
  setup
  export_valid_env_vars
  make_restart_stubs "$TMPDIR_ROOT/bin"
  export STUB_STATE="$TMPDIR_ROOT/stubstate"; mkdir -p "$STUB_STATE"
  export STUB_CALLS="$TMPDIR_ROOT/calls.log"; : > "$STUB_CALLS"
  export INFRA_CONFIG_SYSTEMCTL_SHOW="$TMPDIR_ROOT/bin/sc-show"
  export INFRA_CONFIG_SYSTEMCTL="$TMPDIR_ROOT/bin/sc-restart"
  # The settle sleep is a real 2s in prod; the suite must not pay it. Pinned to 0 explicitly
  # rather than left to a stubbed sleep, so the handler's own default stays observable.
  export INFRA_CONFIG_RESTART_SETTLE_SECS=0
}
restart_teardown() {
  unset STUB_STATE STUB_CALLS INFRA_CONFIG_SYSTEMCTL_SHOW INFRA_CONFIG_SYSTEMCTL \
        INFRA_CONFIG_RESTART_SETTLE_SECS
  teardown
}

# Read one field out of the restarts array for a unit.
restart_field() {
  jq -r --arg u "$1" --arg f "$2" '.restarts[] | select(.unit == $u) | .[$f]' \
    "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING"
}

test_reconcile_stale_fires_and_disarms() {
  echo "TEST: reconcile — a stale unit is restarted, and a second apply does NOT restart it"
  restart_setup
  # Started an hour before the files it depends on ⇒ stale. The restart lands it in the future,
  # so the SAME fixtures on a second apply must now read as not_stale: the predicate has to
  # self-disarm, or the handler restarts vector on every apply forever.
  arm_unit  vector.service            active "$(( $(date +%s) - 3600 ))"
  arm_after vector.service            active "$(( $(date +%s) + 3600 ))"
  arm_unit  inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true

  assert_eq "stale unit action is restarted"     "restarted"    "$(restart_field vector.service action)"
  assert_eq "stale unit reason is stale_config"  "stale_config" "$(restart_field vector.service reason)"
  # Non-vacuity: the stub must actually have been invoked. Without this the arms above could
  # all be satisfied by a handler that never called anything.
  if grep -qxF "try-restart vector.service" "$STUB_CALLS"; then
    echo "  PASS: the restart seam was invoked with the expected argv"; PASS=$((PASS + 1))
  else
    echo "  FAIL: restart seam never invoked (calls: $(tr '\n' ';' < "$STUB_CALLS"))"; FAIL=$((FAIL + 1))
  fi
  # The advanced timestamp must be REPORTED, not just used internally — it is what the
  # post-apply follow-through probe reads.
  local tb ta
  tb=$(restart_field vector.service exec_main_start_ts_before)
  ta=$(restart_field vector.service exec_main_start_ts_after)
  if [[ "$ta" -gt "$tb" ]]; then
    echo "  PASS: exec_main_start_ts advanced in the report ($tb -> $ta)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: reported timestamps did not advance ($tb -> $ta)"; FAIL=$((FAIL + 1))
  fi

  # --- second apply, same fixtures: must self-disarm ---
  : > "$STUB_CALLS"
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "second apply skips the now-current unit" "not_stale" "$(restart_field vector.service reason)"
  if [[ -s "$STUB_CALLS" ]]; then
    echo "  FAIL: predicate did not self-disarm — restarted again ($(tr '\n' ';' < "$STUB_CALLS"))"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: predicate self-disarmed (no restart attempted on the second apply)"; PASS=$((PASS + 1))
  fi
  restart_teardown
}

test_reconcile_inactive_short_circuits() {
  echo "TEST: reconcile — an inactive unit is skipped with NO restart attempted"
  restart_setup
  arm_unit vector.service            inactive ""
  arm_unit inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "inactive unit action" "skipped"       "$(restart_field vector.service action)"
  assert_eq "inactive unit reason" "unit_inactive" "$(restart_field vector.service reason)"
  # try-restart is a deliberate no-op on an inactive unit and STILL EXITS 0, so an attempt here
  # would grade as a successful restart that never happened. Assert no attempt was made at all.
  if [[ -s "$STUB_CALLS" ]]; then
    echo "  FAIL: attempted a restart on an inactive unit ($(tr '\n' ';' < "$STUB_CALLS"))"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: no restart attempted on an inactive unit"; PASS=$((PASS + 1))
  fi
  restart_teardown
}

test_reconcile_noop_not_active() {
  echo "TEST: reconcile — a unit that dies right after fork grades as noop_not_active"
  restart_setup
  # try-restart returns 0 the moment the unit forks. On a Type=simple unit that 0 means
  # "forked", not "running" — so the exit code alone would certify a unit that immediately died.
  arm_unit  vector.service            active "$(( $(date +%s) - 3600 ))"
  arm_after vector.service            failed "$(( $(date +%s) + 3600 ))"
  arm_unit  inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "post-fork death action" "failed"          "$(restart_field vector.service action)"
  assert_eq "post-fork death reason" "noop_not_active" "$(restart_field vector.service reason)"
  assert_eq "reported active state is the observed one" "failed" "$(restart_field vector.service active)"
  restart_teardown
}

test_reconcile_did_not_advance() {
  echo "TEST: reconcile — rc=0 with an unchanged start timestamp is restart_did_not_advance"
  restart_setup
  # Active afterwards AND exit 0, but the process never re-exec'd. Graded on effect, this is a
  # failure; graded on exit code it would be a success.
  arm_unit vector.service            active "$(( $(date +%s) - 3600 ))"
  arm_after vector.service           active ""   # no timestamp change armed
  arm_unit inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "unchanged timestamp action" "failed"                  "$(restart_field vector.service action)"
  assert_eq "unchanged timestamp reason" "restart_did_not_advance" "$(restart_field vector.service reason)"
  restart_teardown
}

test_reconcile_sudo_denied() {
  echo "TEST: reconcile — a denied sudo gets its own enum, never a unit-state one"
  restart_setup
  arm_unit vector.service            active "$(( $(date +%s) - 3600 ))"
  touch "$STUB_STATE/vector.service.deny"
  arm_unit inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "denial action" "failed"      "$(restart_field vector.service action)"
  # A provisioning defect must not be reported as a property of the unit — #5934 is the case
  # where a swallowed denial became a silent no-op nobody noticed until the next incident.
  assert_eq "denial reason" "sudo_denied" "$(restart_field vector.service reason)"
  assert_eq "denial records the non-zero rc" "1" "$(restart_field vector.service rc)"
  restart_teardown
}

test_reconcile_timestamp_unparseable() {
  echo "TEST: reconcile — a non-empty unreadable timestamp is reported, not guessed at"
  restart_setup
  arm_unit vector.service active 0
  printf 'not-a-timestamp' > "$STUB_STATE/vector.service.ExecMainStartTimestamp"
  arm_unit inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "unparseable action" "skipped"                "$(restart_field vector.service action)"
  assert_eq "unparseable reason" "timestamp_unparseable"  "$(restart_field vector.service reason)"
  # Treating unparseable as stale would restart on every apply while reporting success.
  if [[ -s "$STUB_CALLS" ]]; then
    echo "  FAIL: attempted a restart on an unreadable timestamp"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: no restart attempted on an unreadable timestamp"; PASS=$((PASS + 1))
  fi
  restart_teardown
}

test_reconcile_vector_ordered_last() {
  echo "TEST: reconcile — vector is restarted LAST (asserted on emitted order)"
  restart_setup
  # Both stale, so both are attempted and the ORDER is observable. Asserted on the order the
  # calls actually happened in, not on the order of the declarations that produced them.
  arm_unit  vector.service            active "$(( $(date +%s) - 3600 ))"
  arm_after vector.service            active "$(( $(date +%s) + 3600 ))"
  arm_unit  inngest-heartbeat.service active "$(( $(date +%s) - 3600 ))"
  arm_after inngest-heartbeat.service active "$(( $(date +%s) + 3600 ))"
  bash "$HANDLER" >/dev/null 2>&1 || true
  local n_calls last_call
  n_calls=$(grep -c 'try-restart' "$STUB_CALLS" || true)
  last_call=$(grep 'try-restart' "$STUB_CALLS" | tail -1)
  assert_eq "both stale units were attempted" "2" "$n_calls"
  # Restarting vector blinks the log stream every post-apply assertion is read through, so it
  # must be the last thing this handler disturbs.
  assert_eq "vector.service is the final restart" "try-restart vector.service" "$last_call"
  # And the marker order matches, since that is what an operator reads.
  local last_marker
  last_marker=$(grep 'SOLEUR_INFRA_CONFIG_RESTART' "$LOGGER_LOG" | tail -1)
  if [[ "$last_marker" == *"unit=vector.service"* ]]; then
    echo "  PASS: vector is also last in the emitted markers"; PASS=$((PASS + 1))
  else
    echo "  FAIL: last marker was not vector: $last_marker"; FAIL=$((FAIL + 1))
  fi
  restart_teardown
}

test_reconcile_survives_missing_inputs() {
  echo "TEST: reconcile — absent dests and a broken show still reach the post-write block"
  restart_setup
  # stat on an absent dest exits 1 and systemctl show can fail outright. Under set -euo pipefail
  # an unguarded read would kill the handler MID-LOOP: the EXIT trap would overwrite the state
  # with files_total:0/"unhandled" and the webhook self-restart would never run — a delivered
  # hooks.json written but never activated (#4804's freeze, made deterministic).
  cat > "$TMPDIR_ROOT/bin/sc-show" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$TMPDIR_ROOT/bin/sc-show"
  rm -f "${TEST_DESTDIR}/etc/default/soleur-doppler-token"
  bash "$HANDLER" >/dev/null 2>&1 || true

  local total written
  total=$(jq -r '.files_total'   "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  written=$(jq -r '.files_written' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING")
  assert_eq "delivery accounting is intact despite the failing reads" "$total" "$written"
  assert_eq "files_total is the full managed set" "$MANAGED_N" "$total"
  # The array must still be emitted, in EVERY outcome — an absent key is indistinguishable from
  # a handler too old to have one, and the gate treats those differently.
  assert_eq "restarts array still covers every unit" "2" \
    "$(jq -r '.restarts | length' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  assert_eq "state reports the v2 contract" "2" \
    "$(jq -r '.schema_version' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  restart_teardown
}

test_reconcile_unchanged_content_preserves_mtime() {
  echo "TEST: reconcile — a content-identical re-delivery does not re-trigger the predicate"
  restart_setup
  arm_unit vector.service            active "$(( $(date +%s) + 3600 ))"
  arm_unit inngest-heartbeat.service inactive ""
  bash "$HANDLER" >/dev/null 2>&1 || true
  local dropin="${TEST_DESTDIR}/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf"
  local m1 m2
  m1=$(stat -c %Y "$dropin" 2>/dev/null || echo 0)
  # Second apply, byte-identical payload. If the write bumped mtime, the drop-in would look
  # newer than the running process on every apply and restart a unit that is not stale.
  sleep 1
  bash "$HANDLER" >/dev/null 2>&1 || true
  m2=$(stat -c %Y "$dropin" 2>/dev/null || echo 0)
  assert_eq "identical re-delivery preserved the drop-in mtime" "$m1" "$m2"
  assert_eq "and reports it as unchanged" "false" \
    "$(jq -r --arg f /etc/systemd/system/vector.service.d/10-vector-doppler-token.conf \
        '.files[] | select(.file == $f) | .changed' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  # But the WRITE still happened — status ok, sha present. Skipping the write would drop the
  # per-apply re-assertion of mode/owner that repairs a drifted credential.
  assert_eq "the write itself is still unconditional" "ok" \
    "$(jq -r --arg f /etc/systemd/system/vector.service.d/10-vector-doppler-token.conf \
        '.files[] | select(.file == $f) | .status' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  restart_teardown
}

test_sudoers_caller_argv_lockstep() {
  echo "TEST: lockstep — the argv the handler sends is the argv sudoers grants"
  # Sudoers matching is EXACT. A drift between the grant and the caller does not widen anything;
  # it DENIES, and a denied restart is a silent no-op unless something pins the two together.
  local sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"
  # Extract the granted commands from each provisioning path, one per line.
  local granted_sudoers granted_cloudinit
  granted_sudoers=$(sed -n 's/^Cmnd_Alias DROPIN_TRY_RESTART = //p' "$sudoers" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  granted_cloudinit=$(sed -n 's/^[[:space:]]*Cmnd_Alias DROPIN_TRY_RESTART = //p' "$cloud_init" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  assert_eq "both provisioning paths grant the same argv" "$granted_sudoers" "$granted_cloudinit"

  # The caller's resolved argv: the seam default, plus the verb and unit from RESTART_MAP.
  local seam_default
  # shellcheck disable=SC2016 -- the single quotes hold a sed SCRIPT; the ${...} inside is the
  # literal text being matched in the handler's source, not an expansion we want performed here.
  seam_default=$(sed -n 's/^SYSTEMCTL_RESTART="\${INFRA_CONFIG_SYSTEMCTL:-\(.*\)}"$/\1/p' "$HANDLER")
  assert_eq "the restart seam defaults to a sudo-prefixed absolute systemctl" \
    "sudo /usr/bin/systemctl" "$seam_default"

  local unit expected n_matched=0
  while IFS='|' read -r unit _; do
    [[ -n "$unit" ]] || continue
    # Strip the sudo prefix: sudoers grants the command sudo will RUN, not the sudo call itself.
    expected="${seam_default#sudo } try-restart $unit"
    if grep -qxF "$expected" <<<"$granted_sudoers"; then
      echo "  PASS: sudoers grants exactly what the handler sends for $unit"; PASS=$((PASS + 1))
    else
      echo "  FAIL: handler would send '$expected' — not granted. Granted: $(tr '\n' ';' <<<"$granted_sudoers")"
      FAIL=$((FAIL + 1))
    fi
    n_matched=$((n_matched + 1))
  done < <(sed -n '/^RESTART_MAP=(/,/^)/p' "$HANDLER" | sed -n 's/^[[:space:]]*"\([^|]*\)|\(.*\)"$/\1|\2/p')

  # Non-vacuity: a broken extraction would yield an empty work-list and "pass" having compared
  # nothing. Also pins that the grant has no members the map does not drive, in both directions.
  assert_eq "every RESTART_MAP unit was checked" "2" "$n_matched"
  assert_eq "the grant has no units the handler never restarts" "$n_matched" \
    "$(grep -c . <<<"$granted_sudoers")"
}

# --- Run all tests ---
echo "=== infra-config-apply.sh test suite ==="
test_dropin_restart_grant
test_reconcile_stale_fires_and_disarms
test_reconcile_inactive_short_circuits
test_reconcile_noop_not_active
test_reconcile_did_not_advance
test_reconcile_sudo_denied
test_reconcile_timestamp_unparseable
test_reconcile_vector_ordered_last
test_reconcile_survives_missing_inputs
test_reconcile_unchanged_content_preserves_mtime
test_sudoers_caller_argv_lockstep
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
test_b64_delivery_parity
test_orphan_hook_selfcheck
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
