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
# The granted argv are pinned here as data and reused by the lockstep assertion, so the units and
# their exact invocation form have ONE definition in this suite rather than three copies.
# inngest-heartbeat.service was here and is deliberately gone: a timer-driven Type=oneshot with no
# RemainAfterExit re-reads its drop-in on the next tick after daemon-reload, so the grant bought
# nothing and cost a standing root-restart capability. See RESTART_MAP in the handler.
DROPIN_RESTART_ARGV=(
  "/usr/bin/systemctl try-restart vector.service"
)
test_dropin_restart_grant() {
  echo "TEST: sudoers — DROPIN_TRY_RESTART alias, User_Spec, and cloud-init mirror"
  local sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"
  local server_tf="${SCRIPT_DIR}/server.tf"
  # Joined from the array rather than indexed, so the assertion survives the grant growing or
  # shrinking without silently reading only its first two members.
  local expected_alias joined
  joined=$(printf '%s, ' "${DROPIN_RESTART_ARGV[@]}"); joined="${joined%, }"
  expected_alias="Cmnd_Alias DROPIN_TRY_RESTART = ${joined}"

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
  # DERIVED from the live grant, never a hardcoded pair. A literal list is a FIRST-MEMBER guard:
  # it can only notice units it already knows about, so a unit ADDED to the grant — the direction
  # that widens privilege — passes unnoticed. Deriving it means the population this arm walks
  # grows with the grant automatically.
  local unit granted_units n_units=0
  granted_units=$(grep -E '^Cmnd_Alias DROPIN_TRY_RESTART = ' "$sudoers" \
    | sed 's/^Cmnd_Alias DROPIN_TRY_RESTART = //' \
    | tr ',' '\n' \
    | sed -n 's#.*try-restart[[:space:]]\{1,\}\([^[:space:],]\{1,\}\).*#\1#p')
  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    n_units=$((n_units + 1))
    if grep -qE "^[[:space:]]*\"?${unit}\"?" <(sed -n '/^RESTART_MAP=(/,/^)/p' "$HANDLER"); then
      echo "  PASS: RESTART_MAP drives $unit"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: $unit is granted in sudoers but absent from the handler's RESTART_MAP"
      FAIL=$((FAIL + 1))
    fi
  done <<<"$granted_units"

  # Non-vacuity: a broken derivation yields an empty list and this arm "passes" having compared
  # nothing — the exact shape the (e) header warns about one level up.
  if [[ "$n_units" -ge 1 ]]; then
    echo "  PASS: the grant derivation found $n_units unit(s) to check"; PASS=$((PASS + 1))
  else
    echo "  FAIL: derived ZERO granted units from the sudoers alias — every check in (e) was vacuous"
    FAIL=$((FAIL + 1))
  fi
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
# A bare `exit 1` cannot distinguish a sudo REFUSAL from a failed restart JOB, and the handler now
# separates them because they have different owners and different remediations. Each arm therefore
# emits the stderr its real counterpart emits, on stderr, exactly as sudo/systemctl do.
[[ -f "$STUB_STATE/$unit.deny" ]] && {
  echo "Sorry, user deploy is not allowed to execute '/usr/bin/systemctl try-restart $unit' as root on soleur-web-platform." >&2
  exit 1
}
[[ -f "$STUB_STATE/$unit.jobfail" ]] && {
  echo "Job for $unit failed because the control process exited with error code. See \"systemctl status $unit\" for details." >&2
  exit 1
}
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

# How many units RESTART_MAP drives, DERIVED from the handler. Assertions about "every unit" are
# expressed against this rather than a literal, because a literal count is the cheapest thing to
# make green by dropping a registration — which is the exact class #7103 R5 exists to close.
restart_map_count() {
  sed -n '/^RESTART_MAP=(/,/^)/p' "$HANDLER" \
    | sed -n 's/^[[:space:]]*"\([^|]*\)|.*"$/\1/p' | grep -c . || true
}

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
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "denial action" "failed"      "$(restart_field vector.service action)"
  # A provisioning defect must not be reported as a property of the unit — #5934 is the case
  # where a swallowed denial became a silent no-op nobody noticed until the next incident.
  assert_eq "denial reason" "sudo_denied" "$(restart_field vector.service reason)"
  assert_eq "denial records the non-zero rc" "1" "$(restart_field vector.service rc)"
  restart_teardown
}

# The OTHER side of the same discriminator. Without this arm the suite has only one fixture for
# "try-restart returned non-zero", so collapsing both branches back into a single `sudo_denied`
# — the defect being fixed — would stay green. try-restart returns non-zero when the restart JOB
# fails too, and reporting that as a sudoers defect sends an agent at a grant server.tf already
# asserts is present, leaving it no next lever short of SSH.
test_reconcile_restart_job_failure_is_not_a_denial() {
  echo "TEST: reconcile — a failed restart JOB is not reported as a sudo denial"
  restart_setup
  arm_unit vector.service active "$(( $(date +%s) - 3600 ))"
  touch "$STUB_STATE/vector.service.jobfail"
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "job-failure action" "failed" "$(restart_field vector.service action)"
  assert_eq "job-failure reason" "restart_invocation_failed" "$(restart_field vector.service reason)"
  assert_eq "job-failure records the non-zero rc" "1" "$(restart_field vector.service rc)"
  restart_teardown
}

test_reconcile_timestamp_unparseable() {
  echo "TEST: reconcile — a non-empty unreadable timestamp is reported, not guessed at"
  restart_setup
  arm_unit vector.service active 0
  printf 'not-a-timestamp' > "$STUB_STATE/vector.service.ExecMainStartTimestamp"
  bash "$HANDLER" >/dev/null 2>&1 || true
  assert_eq "unparseable action" "failed"                 "$(restart_field vector.service action)"
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
  # Every mapped unit armed stale, so all are attempted and the ORDER is observable. Asserted on
  # the order the calls actually happened in, not on the order of the declarations that produced
  # them. The expected call count is DERIVED from RESTART_MAP: re-pinning a literal here is how a
  # dropped registration goes green.
  local u
  while IFS= read -r u; do
    [[ -n "$u" ]] || continue
    arm_unit  "$u" active "$(( $(date +%s) - 3600 ))"
    arm_after "$u" active "$(( $(date +%s) + 3600 ))"
  done < <(sed -n '/^RESTART_MAP=(/,/^)/p' "$HANDLER" | sed -n 's/^[[:space:]]*"\([^|]*\)|.*"$/\1/p')
  bash "$HANDLER" >/dev/null 2>&1 || true
  local n_calls last_call expected_calls
  expected_calls=$(restart_map_count)
  # `|| true` on BOTH captures. The sibling above carried it and this one did not, so a
  # legitimate no-match killed the suite here — before the assertion written to name that exact
  # failure could report, and taking the six test functions after it with it.
  n_calls=$(grep -c 'try-restart' "$STUB_CALLS" || true)
  last_call=$(grep 'try-restart' "$STUB_CALLS" | tail -1 || true)
  assert_eq "every stale mapped unit was attempted" "$expected_calls" "$n_calls"
  # Non-vacuity: a broken derivation would make the line above compare 0 against 0.
  if [[ "$expected_calls" -ge 1 ]]; then
    echo "  PASS: RESTART_MAP derivation is non-empty ($expected_calls unit(s))"; PASS=$((PASS + 1))
  else
    echo "  FAIL: derived ZERO units from RESTART_MAP — the ordering assertion is vacuous"; FAIL=$((FAIL + 1))
  fi
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
  assert_eq "restarts array still covers every unit" "$(restart_map_count)" \
    "$(jq -r '.restarts | length' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  assert_eq "state reports the v2 contract" "2" \
    "$(jq -r '.schema_version' "$INFRA_CONFIG_STATE" 2>/dev/null || echo MISSING)"
  restart_teardown
}

test_reconcile_unchanged_content_preserves_mtime() {
  echo "TEST: reconcile — a content-identical re-delivery does not re-trigger the predicate"
  restart_setup
  arm_unit vector.service            active "$(( $(date +%s) + 3600 ))"
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
  # The single quotes below hold a sed SCRIPT; the ${...} inside is literal text being matched in
  # the handler's source, not an expansion we want performed here.
  # shellcheck disable=SC2016
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
  assert_eq "every RESTART_MAP unit was checked" "$(restart_map_count)" "$n_matched"
  # …and that derived count is itself non-zero, so the line above cannot pass 0 against 0.
  if [[ "$n_matched" -ge 1 ]]; then
    echo "  PASS: the lockstep walked $n_matched unit(s)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: the lockstep walked ZERO units — the argv comparison was vacuous"; FAIL=$((FAIL + 1))
  fi
  assert_eq "the grant has no units the handler never restarts" "$n_matched" \
    "$(grep -c . <<<"$granted_sudoers")"
}

# =============================================================================================
# #7220 — the no-SSH fatal-error channel.
#
# The bug these arms exist for: `systemctl daemon-reload` ran as User=deploy with no sudoers
# grant, `set -e` aborted AFTER 19/19 files were written, and the EXIT trap published a frame of
# HARDCODED ZEROS. The CI gate then reported `files_total=0` — the precise opposite of what had
# happened — with no line, no command and no rc. The handler could fail; it could not say how.
#
# Every arm below is proven RED against the PINNED pre-fix handler by
# `test_fatal_channel_red_against_pre_fix` at the end of this block.
# =============================================================================================

# Helper: the handler's frame, or the literal string MISSING.
_frame_field() {  # <field>
  jq -r --arg f "$1" '.[$f] // "MISSING"' "$INFRA_CONFIG_STATE" 2>/dev/null || echo "MISSING"
}

# --- #7220 A1.3 + A8.2: the `exit 64` guard fires ABOVE the counters ---
# Two defects in one shape. Before the trap hoist, START_TS / the state-file resets / the EXIT
# trap all sat BELOW the RESTART_SETTLE_SECS guard, so `exit 64` (a) left the PREVIOUS run's
# frame on disk — a stale GREEN certifying an apply that delivered nothing — and (b) wrote no
# frame of its own. This arm drives a real clean apply first so there IS a stale green to serve.
test_fatal_channel_exit64_replaces_stale_frame() {
  echo "TEST: #7220 — exit 64 above the counters replaces the stale frame (AC7, AC13)"
  setup
  export_valid_env_vars

  # 1. A clean apply, so a GREEN frame with exit_code=0 is on disk.
  bash "$HANDLER" >/dev/null 2>&1 || true
  local prior_exit; prior_exit=$(_frame_field exit_code)
  assert_eq "precondition: a clean apply left a green frame" "0" "$prior_exit"

  # 2. Now poison the guard. This exits 64 before TOTAL_COUNT/WRITTEN_COUNT exist.
  INFRA_CONFIG_RESTART_SETTLE_SECS=abc bash "$HANDLER" >/dev/null 2>&1 || true

  # The frame must be THIS run's, not the previous one's.
  assert_eq "exit 64 publishes its own frame, not the prior green one" "64" "$(_frame_field exit_code)"
  assert_eq "the death is attributed with the process status" "64" "$(_frame_field fatal_rc)"
  assert_eq "reason is unhandled" "unhandled" "$(_frame_field reason)"

  # AC13 — the `${VAR:-0}` defaults. Measured on bash 5.2.21: a BARE $WRITTEN_COUNT here makes
  # an abort in this window write NO FRAME AT ALL under `set -u`, which
  # cat-infra-config-state.sh then reports as `no_prior_apply` — "the handler never ran". The
  # instrument would erase exactly the death it exists to report. So assert the frame parses.
  if jq -e . "$INFRA_CONFIG_STATE" >/dev/null 2>&1; then
    echo "  PASS: an abort above the counters still writes well-formed JSON"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: abort above the counters produced no/invalid frame — the :-0 defaults regressed"
    FAIL=$((FAIL + 1))
  fi
  assert_eq "counters default to 0 rather than aborting the printf" "0" "$(_frame_field files_written)"

  teardown
}

# --- #7220 A8.1: a fatal inside `$( )` still reaches the frame (AC9) ---
# `local_sha=$(sha256sum "$tmpfile" | awk …)` is an UNGUARDED command substitution containing a
# pipeline, inside the write loop. A failure there assigns FATAL_* in the CHILD, so a
# variable-based handoff would leave the parent's EXIT trap publishing a frame with no
# attribution — while the frame is the transport-independent arm of this channel. The handoff is
# a FILE for exactly this reason.
test_fatal_channel_subshell_attribution() {
  echo "TEST: #7220 — a fatal inside a command substitution still reaches the frame (AC9)"
  setup
  export_valid_env_vars
  # Break sha256sum only. The sanitizer path (printf|tr|tr|cut) does not use it.
  printf '#!/bin/sh\nexit 7\n' > "$TMPDIR_ROOT/bin/sha256sum"
  chmod +x "$TMPDIR_ROOT/bin/sha256sum"

  bash "$HANDLER" >/dev/null 2>&1 || true

  local fline fcmd
  fline=$(_frame_field fatal_line)
  fcmd=$(_frame_field fatal_cmd)

  if [[ "$fline" =~ ^[0-9]+$ ]] && [[ "$fline" -gt 0 ]]; then
    echo "  PASS: fatal_line crossed the subshell boundary (line=$fline)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: fatal_line=$fline — the ERR->EXIT handoff did not cross the subshell"
    FAIL=$((FAIL + 1))
  fi

  # Non-vacuity: the command text must actually be there, else the absence assertions in the
  # secret arm below would pass on an empty string.
  #
  # This assertion ALSO pins the handoff's last-writer-wins semantics, so do not "improve" the
  # ERR trap to keep the FIRST write. Measured both ways on bash 5.2.21: the failing construct
  # here is a PIPELINE (`local_sha=$(sha256sum … | awk …)`), and for a pipeline bash reports the
  # LAST ELEMENT — so first-writer-wins records `awk "{print $1}"`, naming a command that
  # SUCCEEDED, and this assertion goes RED. The outer frame is coarser but never wrong.
  case "$fcmd" in
    *sha256sum*) echo "  PASS: fatal_cmd names the failing command, not a succeeded pipeline element"; PASS=$((PASS + 1)) ;;
    *) echo "  FAIL: fatal_cmd=<$fcmd> does not name sha256sum (last-writer-wins handoff regressed?)"; FAIL=$((FAIL + 1)) ;;
  esac

  # The frame stays valid JSON and carries REAL accounting, not the hardcoded zeros of #7220.
  if jq -e . "$INFRA_CONFIG_STATE" >/dev/null 2>&1; then
    echo "  PASS: frame remains well-formed JSON with a sanitized command"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: frame is not valid JSON — the sanitizer let a quote or backslash through"
    FAIL=$((FAIL + 1))
  fi
  assert_eq "files_total is the REAL count, not the #7220 hardcoded 0" "$MANAGED_N" "$(_frame_field files_total)"

  # The journald arm of the same fact, via the AC14b seam.
  if grep -q 'SOLEUR_INFRA_CONFIG_FATAL' "$LOGGER_LOG" 2>/dev/null; then
    echo "  PASS: SOLEUR_INFRA_CONFIG_FATAL emitted to the journald arm"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: no SOLEUR_INFRA_CONFIG_FATAL marker — the no-SSH channel is silent"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- #7220 A8.3: a secret-bearing variable never leaks its VALUE (AC11) ---
# MEASURED (bash 5.2.21 target image AND 5.3.9): $BASH_COMMAND is UNEXPANDED — it carries the
# literal source text `--token="$SECRET"`, never the value. That, not the sanitizer, is what
# makes this safe: the sanitizer's charset `A-Za-z0-9 ._:/=-` PRESERVES a `dp.st.…` token
# intact, so if BASH_COMMAND ever expanded, this channel would ship credentials to Better Stack.
# The arm therefore asserts the value is absent AND that the variable NAME is present — without
# the second half the absence check passes vacuously on an empty fatal_cmd.
test_fatal_channel_no_secret_leak() {
  echo "TEST: #7220 — a failing command's secret-bearing variable leaks no VALUE (AC11)"
  setup
  export_valid_env_vars
  local secret="dp.st.SUPERSECRETVALUE7220"
  # A seam whose VALUE is a secret and whose invocation fails unhandled inside the write loop.
  printf '#!/bin/sh\nexit 7\n' > "$TMPDIR_ROOT/bin/sha256sum"
  chmod +x "$TMPDIR_ROOT/bin/sha256sum"

  SOLEUR_SECRET_PROBE="$secret" bash "$HANDLER" >/dev/null 2>&1 || true

  if grep -qF "$secret" "$INFRA_CONFIG_STATE" 2>/dev/null; then
    echo "  FAIL: the secret VALUE reached the state frame"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: no secret value in the frame"
    PASS=$((PASS + 1))
  fi
  if grep -qF "$secret" "$LOGGER_LOG" 2>/dev/null; then
    echo "  FAIL: the secret VALUE reached the journald arm"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: no secret value in \$LOGGER_LOG"
    PASS=$((PASS + 1))
  fi
  # Anti-vacuity — prove the channel was actually carrying command text at the time.
  case "$(_frame_field fatal_cmd)" in
    *sha256sum*) echo "  PASS: non-vacuous — fatal_cmd was populated"; PASS=$((PASS + 1)) ;;
    *) echo "  FAIL: fatal_cmd empty — the absence assertions above were vacuous"; FAIL=$((FAIL + 1)) ;;
  esac

  # THE ABOVE IS NOT THE PROPERTY. Review caught that honestly: the handler never reads
  # SOLEUR_SECRET_PROBE, and the failing command's source text (`local_sha=$(sha256sum …)`)
  # names no secret-bearing variable — so the absence assertions hold by FIXTURE CONSTRUCTION,
  # not by mechanism. They would still pass against a handler that fully expanded $BASH_COMMAND.
  #
  # The real safety argument is a BASH invariant: $BASH_COMMAND carries the literal SOURCE TEXT,
  # unexpanded. That matters because the sanitizer is NOT a redactor — its charset
  # `A-Za-z0-9 ._:/=-` preserves a `dp.st.…` token intact. So pin the invariant itself, under
  # the same shell settings and the same trap shape the handler uses.
  local probe_out
  probe_out=$(bash -c '
    set -euo pipefail; set -o errtrace
    SECRET="dp.st.LEAKCANARY7220"
    trap '"'"'printf "%s" "$BASH_COMMAND" > "'"$TMPDIR_ROOT"'/bc.txt"'"'"' ERR
    /nonexistent-probe-7220 --token="$SECRET"
  ' 2>/dev/null; cat "$TMPDIR_ROOT/bc.txt" 2>/dev/null || true)

  if [[ -n "$probe_out" ]] && [[ "$probe_out" != *"dp.st.LEAKCANARY7220"* ]] && [[ "$probe_out" == *'$SECRET'* ]]; then
    echo "  PASS: \$BASH_COMMAND is UNEXPANDED — it carries the literal \$SECRET, never the value"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: \$BASH_COMMAND expansion invariant broken — the sanitizer does NOT redact, so"
    echo "        this channel would ship credentials to Better Stack. Captured: <$probe_out>"
    FAIL=$((FAIL + 1))
  fi

  # The invariant above is voided by exactly one construct class: `eval`, or sourcing generated
  # text — both re-expand before the trap sees the command. Nothing else in the file pins this,
  # so a future `eval` would silently convert the fatal channel into a token exfiltrator.
  local n_eval
  n_eval=$(grep -cE '(^|[^A-Za-z_])eval[[:space:]]' "$HANDLER" 2>/dev/null || true)
  [[ "$n_eval" =~ ^[0-9]+$ ]] || n_eval=0
  assert_eq "the handler contains no \`eval\` (the construct that would void non-expansion)" "0" "$n_eval"
  # The frame must contain no raw quote or newline, which is what keeps it parseable.
  if jq -e . "$INFRA_CONFIG_STATE" >/dev/null 2>&1; then
    echo "  PASS: frame parses (no raw quote/backslash/newline survived the sanitizer)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: frame does not parse"
    FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- #7220 A8.4 (P0): the instrument must not become the outage (AC10) ---
# MEASURED on bash 5.2.21 and 5.3.9: a failing command inside an ARMED EXIT trap both fires ERR
# and turns `exit 0` into rc=1 — and `trap - ERR` ALONE suppresses the marker but NOT the status
# flip. Enriching this trap without capture-first + disarm + `|| true` + `exit "$rc"` would turn
# a GREEN apply RED on the one host with no SSH runbook. This arm is that guard.
test_fatal_channel_clean_apply_exits_zero() {
  echo "TEST: #7220 — a clean apply still exits 0 with the enriched trap (AC10, AC14)"
  setup
  export_valid_env_vars

  local rc=0
  bash "$HANDLER" >/dev/null 2>&1 || rc=$?
  assert_eq "clean apply exits 0 — the instrument did not flip the status" "0" "$rc"
  assert_eq "frame reports exit_code 0" "0" "$(_frame_field exit_code)"

  # AC14 second half: ZERO false fatal markers on a healthy run. This is the only executable
  # mitigation for the biggest behavioural risk of this change — a channel that cries wolf on
  # every green apply trains the reader to ignore the one that matters.
  local n_fatal
  n_fatal=$(grep -c 'SOLEUR_INFRA_CONFIG_FATAL' "$LOGGER_LOG" 2>/dev/null || true)
  [[ "$n_fatal" =~ ^[0-9]+$ ]] || n_fatal=0
  assert_eq "zero SOLEUR_INFRA_CONFIG_FATAL markers on a clean apply" "0" "$n_fatal"

  # fatal_* are emitted UNCONDITIONALLY (AC12), zeroed when ERR never fired.
  assert_eq "fatal_rc zeroed on success" "0" "$(_frame_field fatal_rc)"
  assert_eq "fatal_line zeroed on success" "0" "$(_frame_field fatal_line)"

  # No handoff residue left behind to poison the NEXT run's attribution.
  if [[ -e "${INFRA_CONFIG_STATE}.fatal" ]]; then
    echo "  FAIL: .fatal handoff file survived a clean apply — next run would misattribute"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: .fatal handoff cleaned up"
    PASS=$((PASS + 1))
  fi

  teardown
}

# --- #7220: PROVE THE ARMS ABOVE ARE RED AGAINST THE PINNED PRE-FIX HANDLER ---
# A regression guard that passes against the code it was written to catch is decoration. This
# runs the pre-#7220 handler from git and asserts it FAILS the two load-bearing properties:
# attribution (fatal_line) and real accounting (files_total). Skips loudly rather than silently
# if the git object is unavailable (shallow clone / detached worktree), so a vacuous pass is
# never mistaken for a proof.
#
# The pre-fix handler, pinned to an IMMUTABLE commit — NOT `origin/main`.
#
# `origin/main` is the natural thing to write here and is exactly wrong: the moment the fix
# merges, main carries the FIXED handler and these two assertions invert and fail forever. A
# guard pinned to a moving ref consumes its own fix — that is #7220's second defect, filed after
# PR-A merged as c2de2581e and turned this suite permanently red (144 passed, 2 failed on every
# infra PR). A pinned SHA instead asserts that a specific historical handler failed these
# properties, which stays true forever. Do not "helpfully" restore the branch name.
#
# 701e76e6b = the last commit to touch infra-config-apply.sh BEFORE c2de2581e. Full 40-char SHA,
# not the abbreviation, so no future object can make it ambiguous. Verified at that commit: the
# handler contains `fatal_line` zero times and hardcodes "files_total":0 in its EXIT trap.
readonly PRE_FIX_HANDLER_SHA="701e76e6bfce84ceed91096a58d88df7da5b6932"

test_fatal_channel_red_against_pre_fix() {
  echo "TEST: #7220 — the new assertions are RED against the pre-fix handler"
  setup
  export_valid_env_vars

  local old="${TMPDIR_ROOT}/old-handler.sh"
  if ! git -C "$SCRIPT_DIR" show "${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh" > "$old" 2>/dev/null; then
    # FAIL, not SKIP, when the pinned commit IS present but the show fails — that is a real
    # breakage, not an unavailable environment. A silent skip here makes the PR's only
    # proof-of-red one `fetch-depth: 1` away from not existing, and nothing downstream
    # consumes a skip. (CI checks out with fetch-depth: 0, so the skip arm should not fire.)
    if git -C "$SCRIPT_DIR" cat-file -e "${PRE_FIX_HANDLER_SHA}^{commit}" 2>/dev/null; then
      echo "  FAIL: pinned pre-fix commit resolves but the handler could not be read — mutation proof is broken, not skipped"
      FAIL=$((FAIL + 1))
    else
      echo "  SKIP (loud): pinned pre-fix commit ${PRE_FIX_HANDLER_SHA:0:9} unavailable (shallow clone) — mutation proof NOT run"
    fi
    teardown
    return 0
  fi

  printf '#!/bin/sh\nexit 7\n' > "$TMPDIR_ROOT/bin/sha256sum"
  chmod +x "$TMPDIR_ROOT/bin/sha256sum"
  bash "$old" >/dev/null 2>&1 || true

  # The pre-fix handler wrote hardcoded zeros and carried no attribution at all.
  local old_line old_total
  old_line=$(_frame_field fatal_line)
  old_total=$(_frame_field files_total)
  assert_eq "pre-fix handler carried NO fatal_line (this is #7220)" "MISSING" "$old_line"
  assert_eq "pre-fix handler reported the hardcoded files_total=0" "0" "$old_total"

  teardown
}

# --- #7220 review: the two arms the original fixture set could not see ---
#
# Every fatal-channel arm above drives a DEATH, so the suite could only ever confirm the channel
# fires — never that it stays quiet, and never that it fires when a frame was already published.
# Both gaps were live bugs. These two arms sit on the other side of the `died` predicate.

# A routine partial delivery is NOT a death. `missing_env` is the documented #4804 self-heal
# window — the expected outcome of every FILE_MAP addition — and it exits 1 for ACCOUNTING while
# publishing a correct frame. Before the fix this emitted `FATAL: line=0 rc=1 cmd=`, which the
# follow-through probe hard-FAILs on, so a normal self-heal would have reported #7220 as unfixed.
test_fatal_channel_partial_apply_is_not_a_death() {
  echo "TEST: #7220 — a routine partial apply emits ZERO fatal markers (review finding)"
  setup
  export_valid_env_vars
  unset CAT_INFRA_CONFIG_STATE_SH_B64   # the #4804 host-drift shape

  local rc=0
  bash "$HANDLER" >/dev/null 2>&1 || rc=$?
  assert_eq "partial apply still exits 1 (accounting, not death)" "1" "$rc"
  assert_eq "the frame keeps the REAL partial accounting" "$MANAGED_MINUS_1" "$(_frame_field files_written)"

  local n_fatal
  n_fatal=$(grep -c 'SOLEUR_INFRA_CONFIG_FATAL' "$LOGGER_LOG" 2>/dev/null || true)
  [[ "$n_fatal" =~ ^[0-9]+$ ]] || n_fatal=0
  assert_eq "ZERO fatal markers on a documented self-heal — the channel must not cry wolf" "0" "$n_fatal"
  assert_eq "no fabricated attribution" "0" "$(_frame_field fatal_line)"

  teardown
}

# A death AFTER the frame is published must CORRECT the frame, not leave it green. The webhook
# self-restart is a second ungranted `sudo` running after `.final` exists; before the fix its
# failure left `exit_code:0` on disk and `adjudicate_infra_config` PASSED — #7220's own shape
# relocated ~200 lines later, invisible to the instrument built for it.
test_fatal_channel_death_after_publish_corrects_the_frame() {
  echo "TEST: #7220 — a death AFTER publish rewrites the frame instead of leaving it green"
  setup
  export_valid_env_vars
  # Deny ONLY systemd-run, so delivery and reconciliation both succeed first.
  printf '#!/bin/sh\ncase "$*" in *systemd-run*) exit 1 ;; esac\nexit 0\n' > "$TMPDIR_ROOT/bin/sudo"
  chmod +x "$TMPDIR_ROOT/bin/sudo"
  unset INFRA_CONFIG_TEST_MODE   # the self-restart is gated out in test mode

  bash "$HANDLER" >/dev/null 2>&1 || true

  # The whole point: a frame that says 0 here is the false green.
  assert_eq "frame reports the TRUE non-zero status, not the published 0" "1" "$(_frame_field exit_code)"
  assert_eq "the post-publish death is named as its own shape" "fatal_after_publish" "$(_frame_field reason)"
  local fline; fline=$(_frame_field fatal_line)
  if [[ "$fline" =~ ^[0-9]+$ ]] && [[ "$fline" -gt 0 ]]; then
    echo "  PASS: the death is attributed to a line ($fline)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: fatal_line=$fline — a post-publish death lost its attribution"; FAIL=$((FAIL + 1))
  fi
  # Correcting the frame must not discard what the run actually earned.
  assert_eq "delivery accounting survives the rewrite" "$MANAGED_N" "$(_frame_field files_total)"
  if [[ "$(jq '.files | length' "$INFRA_CONFIG_STATE" 2>/dev/null || echo 0)" -eq "$MANAGED_N" ]]; then
    echo "  PASS: files[] preserved through the correction"; PASS=$((PASS + 1))
  else
    echo "  FAIL: files[] was discarded when the frame was corrected"; FAIL=$((FAIL + 1))
  fi

  teardown
}

# --- #7220 review: the handoff is an INPUT, so it needs a trust gate that can fail ---
#
# Since #7220 the `.fatal` handoff decides fatal_line, which the gate turns into `fatal_mode=1`,
# which SUPPRESSES two genuine diagnostics. STATE_FILE defaults under /var/lock -> /run/lock,
# mode 1777 and NOT covered by webhook.service's PrivateTmp — so any local UID can create that
# path first. `-O` (owned by the effective UID) is what stops a planted file steering the
# operator to a fabricated line while silencing the real ones.
#
# This arm exists because a mutation battery caught that dropping `-O` left the suite fully
# GREEN. A security guard whose deletion nothing notices is not a guard.
test_fatal_channel_handoff_requires_ownership() {
  echo "TEST: #7220 — the .fatal handoff is ownership-gated before it is believed (review finding)"
  setup

  # STRUCTURAL: anchored on the shell test construct, which a comment cannot produce (verified
  # unique in-file). Also pins ORDER — a trust gate below the read is not a trust gate.
  local guard_line read_line
  guard_line=$(grep -n -- '-O "\$FATAL_FILE"' "$HANDLER" | head -1 | cut -d: -f1)
  read_line=$(grep -n 'IFS= read -r f_rc' "$HANDLER" | head -1 | cut -d: -f1)
  if [[ -n "$guard_line" ]]; then
    echo "  PASS: the handoff read is ownership-gated (line $guard_line)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: no -O ownership gate on \$FATAL_FILE — a planted handoff would be believed"
    FAIL=$((FAIL + 1))
  fi
  if [[ -n "$guard_line" && -n "$read_line" && "$guard_line" -lt "$read_line" ]]; then
    echo "  PASS: the gate precedes the read"; PASS=$((PASS + 1))
  else
    echo "  FAIL: ownership gate at '$guard_line' does not precede the read at '$read_line'"
    FAIL=$((FAIL + 1))
  fi

  # BEHAVIOURAL, when the environment can actually express foreign ownership. Skips LOUDLY —
  # a silent skip here would read exactly like a pass.
  if [[ "$(id -u)" -eq 0 ]] && id -u nobody >/dev/null 2>&1; then
    export_valid_env_vars
    printf '#!/bin/sh\nexit 7\n' > "$TMPDIR_ROOT/bin/sha256sum"; chmod +x "$TMPDIR_ROOT/bin/sha256sum"
    printf '1\n999999\nPLANTED_FABRICATED_COMMAND\n' > "${INFRA_CONFIG_STATE}.fatal"
    chown nobody "${INFRA_CONFIG_STATE}.fatal" 2>/dev/null || true
    bash "$HANDLER" >/dev/null 2>&1 || true
    case "$(_frame_field fatal_cmd)" in
      *PLANTED_FABRICATED_COMMAND*)
        echo "  FAIL: a foreign-owned handoff was believed — fabricated attribution reached the frame"
        FAIL=$((FAIL + 1)) ;;
      *)
        echo "  PASS: foreign-owned handoff ignored; attribution came from this process only"
        PASS=$((PASS + 1)) ;;
    esac
  else
    echo "  SKIP (loud): not root, so foreign ownership cannot be expressed here — the structural"
    echo "               assertions above are the only coverage in this environment."
  fi

  teardown
}

# --- Run all tests ---
echo "=== infra-config-apply.sh test suite ==="
test_fatal_channel_handoff_requires_ownership
test_fatal_channel_partial_apply_is_not_a_death
test_fatal_channel_death_after_publish_corrects_the_frame
test_fatal_channel_exit64_replaces_stale_frame
test_fatal_channel_subshell_attribution
test_fatal_channel_no_secret_leak
test_fatal_channel_clean_apply_exits_zero
test_fatal_channel_red_against_pre_fix
test_dropin_restart_grant
test_reconcile_stale_fires_and_disarms
test_reconcile_inactive_short_circuits
test_reconcile_noop_not_active
test_reconcile_did_not_advance
test_reconcile_sudo_denied
test_reconcile_restart_job_failure_is_not_a_denial
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
# --- #7220 review: ASSERTION-COUNT FLOOR ---------------------------------------------------
# Measured: removing the new arm invocations from the runner took this suite 144 -> 110 passed,
# 0 failed, exit 0. Nothing noticed. A floor makes that loud.
APPLY_MIN_ASSERTIONS=142
if [[ "$PASS" -lt "$APPLY_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor — only $PASS assertions ran, expected >= $APPLY_MIN_ASSERTIONS"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
