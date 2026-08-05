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
# Assertions a LOUD SKIP arm declared it did not run. Read only by the assertion-count floor at
# the bottom of this file, which compares PASS + SKIPPED against the floor so that a declared
# environmental skip and a silently-vanished guard produce DIFFERENT verdicts. Every arm that
# prints "SKIP (loud)" must add the exact number of assertions its taken branch would have made.
SKIPPED_ASSERTIONS=0

# Single owning trap for every tempfile this suite allocates outside setup()/teardown()
# (ADR-129 rule (c)). setup() manages TMPDIR_ROOT; arms that run without it register here.
# /tmp is a machine-global tmpfs shared by parallel worktrees, so a per-run leak is unbounded.
OWNED_TMPFILES=()
cleanup_owned_tmpfiles() { [[ ${#OWNED_TMPFILES[@]} -gt 0 ]] && rm -f "${OWNED_TMPFILES[@]}"; return 0; }
trap cleanup_owned_tmpfiles EXIT INT TERM
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
  # #7220 review — an `export` set by one arm leaks into every later arm in the same shell, and
  # once TMPDIR_ROOT is removed the stale path resolves to nothing (rc=127, "command not
  # found"), which surfaces as an unrelated test failing. Unset the per-arm seam overrides here
  # so each arm starts from the handler's own defaults. Measured: without this the prod-mode
  # seam export broke the dangling-hook arm three tests later.
  unset INFRA_CONFIG_SYSTEMCTL
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
  export HOOKS_JSON_B64=$(_payload_file '[{"id":"fixture","execute-command":"/usr/local/bin/inngest-inventory.sh"}]')
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
  # #7220 review — the prod-mode arm replaces the `sudo` stub with `exec "$@"`, and the WRITE
  # seam defaults to an ABSOLUTE `sudo /usr/bin/systemctl`, which the PATH stub cannot shadow.
  # Since B4 moved daemon-reload out of the TEST_MODE guard onto that seam, this arm would run
  # the REAL systemctl as non-root and abort under set -e. Point the seam at the stub — that is
  # exactly what the seam exists for. Measured: without this the branch is 169/2 against a
  # 148/0 baseline on main.
  export INFRA_CONFIG_SYSTEMCTL="${TMPDIR_ROOT}/bin/systemctl"

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
# #7220 B7 — ONE verb-dispatching stub, not a second stub binary. The WRITE seam now carries two
# granted verbs (try-restart <unit>, daemon-reload), and sudo matches the FULL resolved argv, so
# the stub's job is to be as intolerant as sudo is: an unexpected verb or a stray argument is
# exit 64, never a silent success. A stub that accepted any argv would make the handler's call
# shape unpinned — the class where switching a flag leaves a suite green.
case "$1" in
  daemon-reload)
    # Exactly one word. `daemon-reload` takes no unit, so any extra argument is a DIFFERENT
    # command than the one sudoers grants and would be denied in production.
    [[ "$#" -eq 1 ]] || { echo "stub: daemon-reload takes no arguments, got '$*'" >&2; exit 64; }
    # The denial arm reproduces polkit's real refusal text, which is what #7220 actually
    # returned, so the handler's attribution is graded against the bytes it will really meet.
    [[ -f "$STUB_STATE/daemon-reload.deny" ]] && {
      echo "Failed to reload daemon: Interactive authentication required." >&2
      exit 1
    }
    printf '1' > "$STUB_STATE/daemon-reload.ran"
    exit 0
    ;;
  try-restart) : ;;
  *) echo "stub: unexpected verb '$1'" >&2; exit 64 ;;
esac
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
  if grep -q "^try-restart" "$STUB_CALLS"; then
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
  if grep -q "^try-restart" "$STUB_CALLS"; then
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
  if grep -q "^try-restart" "$STUB_CALLS"; then
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

# --- #7220 B2/B3/B4: the daemon-reload grant, and the seam that carries it -----------------
#
# THIS IS THE REPAIR. Everything in PR-A was the instrument that measured this gap; this arm is
# the property that closes it. The handler's `systemctl daemon-reload` ran as User=deploy with
# no grant, returned "Interactive authentication required", and set -e aborted the handler AFTER
# all 19 files were written but BEFORE unit reconciliation — so delivery was healthy and
# ACTIVATION silently was not, since roughly 2026-05.
#
# The lockstep matters more here than for try-restart. Sudoers matching is EXACT, so a drift
# between grant and caller does not widen anything — it DENIES, and a denied reload is exactly
# the silent no-op #7220 already was. Pinning both provisioning paths and the caller together is
# what stops this from regressing into the same invisible failure.
# --- #7220 AC6: handler->grant lint (CLASS CLOSURE) ---------------------------------------
#
# The one guard that would have caught #7220 STRUCTURALLY. The existing lockstep runs
# grant->handler (derived from RESTART_MAP) and the drift guards run source->source, so neither
# can see a privileged verb the handler invokes that no map and no grant mentions. A bare
# `systemctl daemon-reload` was exactly that: invisible to every check in the repo.
#
# Direction matters. This walks handler -> grant: every non-READ systemctl/systemd-run verb the
# handler invokes must be sudo-prefixed AND granted in BOTH sudoers sources.
#
# WHAT `GRANTED` MEANS, and why the first version of this lint got it wrong.
#
# A `Cmnd_Alias` is an inert macro. On its own it grants NOTHING — it needs a User_Spec
# (`deploy ALL=(root) NOPASSWD: <NAME>`) to become a permission. And sudo matches the FULL
# RESOLVED ARGV, not a verb: `/usr/bin/systemctl stop webhook.service` is a different command
# from `/usr/bin/systemctl stop inngest-server.service`, and a request for the former against a
# grant of the latter is DENIED.
#
# The original lint did a substring `grep -qF "systemctl $verb"` across all Cmnd_Alias lines,
# which discards the unit AND ignores the User_Spec. Measured consequences — every one of these
# returned rc=0 (no violation) from a handler that sudo would refuse, producing the exact #7220
# shape (denial -> set -e abort AFTER delivery) the lint was named for:
#
#   $SYSTEMCTL_PRIV stop webhook.service          matched INNGEST_STOP's `systemctl stop`
#   $SYSTEMCTL_PRIV restart nginx.service         matched INNGEST_RESTART's `systemctl restart`
#   $SYSTEMCTL_PRIV disable webhook.service       matched INNGEST_QUIESCE's `systemctl disable`
#   $SYSTEMCTL_PRIV try-restart inngest-heartbeat.service
#                                                 matched DROPIN_TRY_RESTART's `systemctl try-restart`
#   sudo /usr/bin/systemd-run <ANY argv>          resolved to the bare word `systemd-run`,
#                                                 dropping the argv entirely
#
# So this now resolves each invocation to its full argv and requires EXACT membership in the
# granted set of BOTH provisioning paths. `_granted_argv` builds that set the way sudo does.
#
# Emits one resolved argv per line: comma-split, whitespace-trimmed, User_Spec-gated.
_granted_argv() {  # <sudoers-shaped-file>
  local file="$1" specs names n
  # The User_Spec RHS is itself comma-separated and may name several aliases at once.
  specs=$(grep -E '^[[:space:]]*deploy[[:space:]]+ALL=\(root\)[[:space:]]+NOPASSWD:' "$file" \
            | sed 's/^.*NOPASSWD:[[:space:]]*//') || true
  names=$(tr ',' '\n' <<<"$specs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$') || true
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    if [[ "$n" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      # An alias reference. Expand it — and note that an alias named by a User_Spec but never
      # DEFINED expands to nothing, so it grants nothing, which is also sudo's behaviour.
      sed -n "s/^[[:space:]]*Cmnd_Alias[[:space:]]\{1,\}${n}[[:space:]]*=[[:space:]]*//p" "$file" \
        | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' || true
    else
      # A literal command sitting directly in the User_Spec (cloud-init:70 does this).
      printf '%s\n' "$n"
    fi
  done <<<"$names"
}

# Emits violations on stdout, returns 1 if any. Parameterised by handler path so the SAME code
# can be run against the pre-fix handler as the proof it would have caught the incident.
_lint_privileged_verbs() {
  local handler="$1" sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"
  local code n_found=0 violations=0

  # --- normalise the handler's CODE -------------------------------------------------------
  #
  # (1) Join backslash line-continuations first. A privileged call split across two physical
  #     lines is invisible to a line-oriented scan, and the handler already uses continuations
  #     (5 of them) so this is not hypothetical.
  #
  # (2) Strip comments ANCHORED. The previous `sed 's/#.*//'` was unanchored, which cuts at the
  #     `#` of `$#` and `${var#prefix}` — so a line like
  #         [ "$#" -eq 0 ] && $SYSTEMCTL_PRIV stop foo.service
  #     lost its entire privileged call before the scan ever saw it, and the lint reported
  #     rc=0. A comment `#` is one at start-of-line or preceded by whitespace; neither `$#`
  #     nor `${x#y}` is. Stripping MUST still happen: this handler's prose names
  #     `systemctl daemon-reload` seven times while its code contains it zero times, so a lint
  #     that read comments would both false-flag the documentation and report a verb as "found"
  #     that is never invoked.
  code=$(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$handler" | sed -E 's/(^|[[:space:]])#.*$/\1/')

  # (3) The anchored strip still over-cuts a `#` that lives inside a quoted string preceded by a
  #     space (`echo "see # note"; $SYSTEMCTL_PRIV stop foo`). That is a fail-OPEN residual, so
  #     it is detected rather than tolerated: a stripped line whose remainder has unbalanced
  #     quotes was cut mid-string, and the lint refuses to certify it.
  local raw_l stripped_l
  while IFS= read -r raw_l; do
    [[ "$raw_l" == *"#"* ]] || continue
    stripped_l=$(sed -E 's/(^|[[:space:]])#.*$/\1/' <<<"$raw_l")
    [[ "$stripped_l" != "$raw_l" ]] || continue
    local dq sq
    dq=$(tr -cd '"' <<<"$stripped_l" | wc -c)
    sq=$(tr -cd "'" <<<"$stripped_l" | wc -c)
    if (( dq % 2 == 1 || sq % 2 == 1 )); then
      echo "VIOLATION: a line of $(basename "$handler") cannot be statically parsed — the comment strip cut inside a quoted string, so any privileged call after it would be invisible: $(printf '%s' "$raw_l" | sed 's/^[[:space:]]*//' | cut -c1-80)"
      violations=$((violations + 1))
    fi
  done < <(sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$handler")

  # --- the two sanctioned seams, READ FROM THE HANDLER --------------------------------------
  #
  # The resolution below turns `$SYSTEMCTL_PRIV <verb> <args>` into the argv sudo will see, so it
  # must not HARDCODE what that seam expands to — a lint that assumes the seam it is checking is
  # asserting nothing about it. Both defaults are read out of the handler and validated.
  local priv_default show_default priv_resolved
  # The single quotes hold a sed SCRIPT; the ${...} inside is literal text matched in the
  # handler's source, not an expansion.
  # shellcheck disable=SC2016
  priv_default=$(sed -n 's/^SYSTEMCTL_PRIV="\${INFRA_CONFIG_SYSTEMCTL:-\(.*\)}"$/\1/p' "$handler")
  # shellcheck disable=SC2016
  show_default=$(sed -n 's/^SYSTEMCTL_SHOW="\${INFRA_CONFIG_SYSTEMCTL_SHOW:-\(.*\)}"$/\1/p' "$handler")
  if [[ "$priv_default" != "sudo "* ]]; then
    echo "VIOLATION: the privileged seam SYSTEMCTL_PRIV defaults to '${priv_default:-<unparseable>}', which is not sudo-prefixed — every verb it carries would run unprivileged"
    violations=$((violations + 1))
  fi
  if [[ -n "$show_default" && "$show_default" == "sudo "* ]]; then
    echo "VIOLATION: the READ seam SYSTEMCTL_SHOW is sudo-prefixed ('$show_default') — the grants pin write verbs only, so every read would be DENIED"
    violations=$((violations + 1))
  fi
  # Sudoers grants the command sudo will RUN, not the sudo call itself.
  priv_resolved="${priv_default#sudo }"

  # --- the granted sets ---------------------------------------------------------------------
  local granted_s granted_c
  granted_s=$(_granted_argv "$sudoers")
  granted_c=$(_granted_argv "$cloud_init")
  if [[ -z "$granted_s" || -z "$granted_c" ]]; then
    echo "VIOLATION: derived an EMPTY granted set (sudoers=$(grep -c . <<<"$granted_s"), cloud-init=$(grep -c . <<<"$granted_c")) — the User_Spec/Cmnd_Alias parse is broken, so every membership test below would fail open"
    violations=$((violations + 1))
  fi

  # READ verbs need no root, and routing them through sudo would be DENIED (the grants pin
  # specific write verbs), turning every read into a failure. Explicit allowlist, not a
  # heuristic -- an unknown verb must fall through to the privileged branch, never be assumed
  # safe.
  local read_verbs=" show is-active is-enabled cat status list-units "
  # The ONE verb whose unit argument is legitimately a variable, because RESTART_MAP drives it
  # and `test_sudoers_caller_argv_lockstep` pins that map against DROPIN_TRY_RESTART in both
  # directions. Any OTHER verb carrying a variable argument has nothing pinning its unit, so it
  # is a violation here rather than a silent delegation to a lockstep that does not cover it.
  local map_delegated_verbs=" try-restart "

  local line body verb argv resolved
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    # The scan reads `grep -n` output, so each record is `<lineno>:<code>`. Strip the prefix:
    # load-bearing, because every `^`-anchored pattern below must match against the CODE, not
    # against the digits. The NUMBER is deliberately discarded rather than reported — it indexes
    # the continuation-joined, comment-stripped text, not the source file, so quoting it would
    # send the reader to the wrong line. Violations cite the offending TEXT instead
    # (cq-cite-content-anchor-not-line-number).
    body="${line#*:}"

    # VARIABLE INDIRECTION. `SC=/usr/bin/systemctl; sudo $SC stop x` cannot be resolved
    # statically, and the previous lint simply did not match it — so it was a silent bypass.
    # An assignment of a systemctl/systemd-run path to anything other than the two sanctioned
    # seams is therefore itself the violation: fail closed on what cannot be read.
    #
    # Deliberately NOT counted into n_found: an assignment is not an invocation, and letting the
    # two sanctioned seam definitions inflate that tally would raise the vacuity floor's input
    # without adding a single checked call site.
    if [[ "$body" =~ ^[[:space:]]*(local|export|declare|readonly)?[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=[^=]*(systemctl|systemd-run) ]]; then
      local assigned="${BASH_REMATCH[2]}"
      if [[ "$assigned" != "SYSTEMCTL_PRIV" && "$assigned" != "SYSTEMCTL_SHOW" ]]; then
        echo "VIOLATION: a systemctl/systemd-run path is assigned to '$assigned', which makes every use of it unresolvable by this lint (use the SYSTEMCTL_PRIV / SYSTEMCTL_SHOW seams): $(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1-80)"
        violations=$((violations + 1))
      fi
      continue
    fi

    n_found=$((n_found + 1))

    # Resolve the invocation to its FULL argv as sudo will see it.
    if [[ "$body" =~ \$SYSTEMCTL_SHOW[[:space:]]+([a-z][a-z-]*)(.*)$ ]]; then
      verb="${BASH_REMATCH[1]}"
      # A read-seam call is exempt only if the verb really is a read verb.
      if [[ "$read_verbs" == *" $verb "* ]]; then continue; fi
      echo "VIOLATION: the READ seam SYSTEMCTL_SHOW carries the non-read verb '$verb'; it has no sudo prefix, so this runs unprivileged and silently does nothing: $(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1-80)"
      violations=$((violations + 1))
      continue
    elif [[ "$body" =~ \$SYSTEMCTL_PRIV[[:space:]]+([a-z][a-z-]*)(.*)$ ]]; then
      verb="${BASH_REMATCH[1]}"
      argv=$(_strip_shell_tail "${BASH_REMATCH[2]}")
      resolved="$priv_resolved $verb${argv:+ $argv}"
    elif [[ "$body" =~ (^|[^-_[:alnum:]])sudo[[:space:]]+((/[A-Za-z0-9_./-]*)?systemd-run[[:space:]]+.*)$ ]]; then
      # EVERY systemd-run line, with its argv intact — not a single hardcoded one, and not the
      # bare word. The inner `/usr/bin/systemctl restart webhook` is PART of the granted argv.
      verb="systemd-run"
      resolved=$(_strip_shell_tail "${BASH_REMATCH[2]}")
    elif [[ "$body" =~ (^|[^-_[:alnum:]])sudo[[:space:]]+((/[A-Za-z0-9_./-]*)?systemctl[[:space:]]+([a-z][a-z-]*).*)$ ]]; then
      # A literal sudo'd systemctl (no seam). Granted-set membership still applies.
      verb="${BASH_REMATCH[4]}"
      [[ "$read_verbs" == *" $verb "* ]] && continue
      resolved=$(_strip_shell_tail "${BASH_REMATCH[2]}")
    elif [[ "$body" =~ (^|[^-_[:alnum:]$/])((/[A-Za-z0-9_./-]*)?systemctl[[:space:]]+([a-z][a-z-]*)) ]]; then
      # A LITERAL, UN-SEAMED, UN-SUDOED systemctl call. This is the #7220 shape.
      verb="${BASH_REMATCH[4]}"
      [[ "$read_verbs" == *" $verb "* ]] && continue
      echo "VIOLATION: privileged verb '$verb' is invoked without sudo: $(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      violations=$((violations + 1))
      continue
    elif [[ "$body" =~ (^|[^-_[:alnum:]$/])((/[A-Za-z0-9_./-]*)?systemd-run) ]]; then
      echo "VIOLATION: systemd-run is invoked without sudo: $(printf '%s' "$body" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      violations=$((violations + 1))
      continue
    else
      continue
    fi

    [[ "$read_verbs" == *" $verb "* ]] && continue

    # A variable in the resolved argv means the exact command is not knowable here.
    if [[ "$resolved" == *'$'* ]]; then
      if [[ "$map_delegated_verbs" != *" $verb "* ]]; then
        echo "VIOLATION: '$resolved' carries a variable argument for verb '$verb', and nothing pins what it expands to — sudo matches exact argv, so this is a denial waiting to happen"
        violations=$((violations + 1))
        continue
      fi
      # try-restart: the unit is pinned by RESTART_MAP <-> DROPIN_TRY_RESTART in
      # test_sudoers_caller_argv_lockstep. Here we only require that the SEAM and VERB prefix is
      # granted at all, so a seam change still reds.
      local prefix_pat="$priv_resolved $verb "
      if ! grep -qF -- "$prefix_pat" <<<"$granted_s" || ! grep -qF -- "$prefix_pat" <<<"$granted_c"; then
        echo "VIOLATION: no grant in both sources begins '$prefix_pat' — the map-driven verb '$verb' would be denied"
        violations=$((violations + 1))
      fi
      continue
    fi

    # EXACT membership, both provisioning paths. `-x` is the whole point: a substring match is
    # what let five denials through.
    if ! grep -qxF -- "$resolved" <<<"$granted_s"; then
      echo "VIOLATION: '$resolved' is invoked but not granted in deploy-inngest-bootstrap.sudoers"
      violations=$((violations + 1))
    fi
    if ! grep -qxF -- "$resolved" <<<"$granted_c"; then
      echo "VIOLATION: '$resolved' is invoked but not granted in the cloud-init mirror"
      violations=$((violations + 1))
    fi
  done < <(grep -nE '\$SYSTEMCTL_(PRIV|SHOW)|systemd-run|(^|[^-_[:alnum:]$/])(/[A-Za-z0-9_./-]*)?systemctl[[:space:]]|^[[:space:]]*(local|export|declare|readonly)?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^=]*(systemctl|systemd-run)' <<<"$code")

  # VACUITY GUARD, mirroring the RESTART_MAP one. A broken extraction yields zero invocations
  # and the loop above "passes" having classified nothing -- which is the exact failure mode
  # this lint exists to prevent, reproduced inside the lint itself.
  #
  # RATCHETED from 2 to 4. The live handler yields exactly 4 (the SHOW read, the PRIV
  # daemon-reload, the PRIV try-restart, the sudo'd systemd-run), so a floor of 2 tolerated an
  # extraction that had silently lost HALF the call sites — including, in principle, the very
  # daemon-reload this lint exists to see. A floor below the known truth is not a guard.
  if [[ "$n_found" -lt 4 ]]; then
    echo "VIOLATION: derived only $n_found systemctl/systemd-run invocations from $(basename "$handler") — the extraction is broken (expected >= 4), so this lint proves nothing"
    violations=$((violations + 1))
  fi
  [[ "$violations" -eq 0 ]]
}

# Trim a shell tail (redirect, list operator, terminator, closing subshell) off an extracted argv
# so what is compared is the command, not the line. Any imprecision here fails CLOSED: the
# comparison is exact membership, so a mis-trimmed argv reports a violation rather than passing.
_strip_shell_tail() {  # <argv-fragment>
  local s="$1"
  # Cut at the first unquoted shell metacharacter run that ends a simple command.
  s=$(sed -E 's/[[:space:]]*(\||\|\||&&|;|&|>|>>|<|\)).*$//' <<<"$s")
  # Collapse internal whitespace runs and trim: sudoers argv are single-space separated.
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' <<<"$s"
}

test_handler_to_grant_lint() {
  echo "TEST: #7220 AC6 — every privileged verb the handler invokes is sudo'd AND granted"
  local out rc=0
  out=$(_lint_privileged_verbs "$HANDLER") || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "  PASS: no ungranted or un-sudoed privileged verbs in the handler"; PASS=$((PASS + 1))
  else
    echo "  FAIL: handler->grant lint found violations:"; printf '    %s\n' "$out"
    FAIL=$((FAIL + 1))
  fi

  # The granted set must be non-trivial, asserted OUTSIDE the lint too. If `_granted_argv`
  # regressed to emitting nothing, every membership test inside the lint would pass by
  # vacuity and the arm above would report a clean handler forever.
  local n_granted
  n_granted=$(_granted_argv "${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers" | grep -c .)
  if [[ "$n_granted" -ge 10 ]]; then
    echo "  PASS: the User_Spec-gated granted set resolved $n_granted argv"; PASS=$((PASS + 1))
  else
    echo "  FAIL: the granted set resolved only $n_granted argv — the sudoers parse is broken, so the lint is vacuous"
    FAIL=$((FAIL + 1))
  fi

  # THE USER_SPEC IS LOAD-BEARING, asserted by construction rather than by reading the file: an
  # alias whose User_Spec line is deleted must STOP being granted. Without this, a lint that
  # ignored User_Specs (as the first version did) would look identical to one that honours them.
  local spec_stripped
  spec_stripped=$(mktemp -t sudoers-nospec.XXXXXXXX); OWNED_TMPFILES+=("$spec_stripped")
  grep -v '^deploy ALL=(root) NOPASSWD: SYSTEMCTL_DAEMON_RELOAD$' \
    "${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers" > "$spec_stripped"
  if ! grep -qxF '/usr/bin/systemctl daemon-reload' <(_granted_argv "$spec_stripped"); then
    echo "  PASS: an alias with no deploy User_Spec grants nothing"; PASS=$((PASS + 1))
  else
    echo "  FAIL: daemon-reload still read as granted after its User_Spec line was removed — the lint certifies a command sudo would DENY"
    FAIL=$((FAIL + 1))
  fi

  # PROVEN RED AGAINST THE PRE-FIX HANDLER. Without this the lint could be vacuous in a way no
  # green run would reveal: a check that passes against the code it was written to catch is
  # decoration.
  #
  # Shares the ONE pin declared for the fatal-channel arm below rather than carrying a second
  # SHA of its own. Both previously named different commits — verified identical blobs (35280
  # bytes, `local died=0` absent, one bare `systemctl daemon-reload` in code) — and two pins for
  # one baseline is two things to keep true. The probe is `cat-file -e` on the BLOB for the
  # reason #7271 documents at that declaration: a blobless clone has the commit and not the file.
  #
  # Own temp, not TMPDIR_ROOT: this arm calls no setup(), so TMPDIR_ROOT is whatever the
  # previous test's teardown removed — writing into it fails with ENOENT and the RED proof
  # reports "broken" when nothing is broken. Registered with the file's owning trap (ADR-129
  # rule (c)) so a mid-arm death still reclaims it; /tmp here is a machine-global tmpfs shared
  # by parallel worktrees, so an unreclaimed leak per run is not bounded.
  local pin="${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh"
  local old; old=$(mktemp -t lint-old-handler.XXXXXXXX.sh); OWNED_TMPFILES+=("$old")
  if git -C "$SCRIPT_DIR" show "$pin" > "$old" 2>/dev/null; then
    local old_out old_rc=0
    old_out=$(_lint_privileged_verbs "$old") || old_rc=$?
    if [[ "$old_rc" -ne 0 ]] && [[ "$old_out" == *"daemon-reload"* ]]; then
      echo "  PASS: the lint FLAGS the pre-fix handler's ungranted daemon-reload (this is #7220)"
      PASS=$((PASS + 1))
    else
      echo "  FAIL: the lint did NOT flag the pre-fix handler — it would not have caught #7220 (rc=$old_rc, out=${old_out:-<none>})"
      FAIL=$((FAIL + 1))
    fi
  elif git -C "$SCRIPT_DIR" cat-file -e "$pin" 2>/dev/null; then
    echo "  FAIL: the pinned pre-fix blob resolves but could not be read — the RED proof is broken, not skipped"
    FAIL=$((FAIL + 1))
  elif [[ -n "${CI:-}" ]]; then
    echo "  FAIL: pinned pre-fix blob ${PRE_FIX_HANDLER_SHA:0:9} is absent under CI, where fetch-depth: 0 should guarantee it — AC6 RED proof NOT run"
    FAIL=$((FAIL + 1))
  else
    echo "  SKIP (loud): pinned pre-fix blob ${PRE_FIX_HANDLER_SHA:0:9} not in this object store (shallow/partial clone, rewritten history, or not run inside the soleur checkout) — AC6 RED proof NOT run."
    echo "               Remedy: run from a full clone (git fetch --unshallow), or re-pin to tag web-v0.248.2."
    # 1: the single "the lint FLAGS the pre-fix handler" assertion the taken branch would make.
    SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 1))
  fi
}

# --- #7220 B5 (AC-B2): hardening the self-restart that has NEVER run in production ---------
#
# fc8b8179 shipped the delayed webhook self-restart AFTER the reload in the same set -e block,
# so it has been unreachable since ~2026-05 with zero test coverage. B2's grant makes it
# reachable for the first time. Re-enabling a never-once-executed root-restart path on a host
# with no orderable replacement is the single riskiest thing in this PR, hence three guards.

# B5.1 -- an unparseable hooks.json must be a HARD failure, not a silent pass.
#
# The sweep is `jq … 2>/dev/null || true`, so a syntactically invalid hooks.json yields no
# commands and the loop finds nothing to complain about. With the self-restart now live, webhook
# would restart 3s later and come up serving ZERO hooks: adnanh/webhook with -verbose does not
# abort on an unparseable hooks file. The port then ANSWERS, so the verify's 000/502/503
# "listener is down" branch never fires -- the 404 branch does, whose remediation text points at
# "first bootstrap". That is the wrong diagnosis, delivered on the exact channel needed to
# repair it, on a host with no SSH runbook. Self-wedge.
test_unparseable_hooks_json_is_a_hard_failure() {
  echo "TEST: #7220 B5.1 — an unparseable hooks.json fails loudly instead of wedging the listener"
  setup
  export_valid_env_vars
  # Valid base64, invalid JSON — the shape a truncated or half-rendered delivery produces.
  export HOOKS_JSON_B64=$(_payload_file '{"id": "broken", ')

  local rc=0
  bash "$HANDLER" >/dev/null 2>&1 || rc=$?

  if [[ "$rc" -ne 0 ]]; then
    echo "  PASS: apply fails when hooks.json does not parse"; PASS=$((PASS + 1))
  else
    echo "  FAIL: apply exited 0 with an unparseable hooks.json — webhook would restart serving zero hooks"
    FAIL=$((FAIL + 1))
  fi

  # Named, so the operator gets the RIGHT diagnosis rather than the 404 "first bootstrap" one.
  local reasons
  reasons=$(jq -r '.files[]?.reason // empty' "$INFRA_CONFIG_STATE" 2>/dev/null | tr '\n' ' ' || true)
  if [[ "$reasons" == *"hooks_json_unparseable"* ]]; then
    echo "  PASS: the frame names hooks_json_unparseable"; PASS=$((PASS + 1))
  else
    echo "  FAIL: frame does not name the parse failure (reasons: ${reasons:-<none>})"
    FAIL=$((FAIL + 1))
  fi

  # NON-VACUITY: a VALID hooks.json must not trip this. Without this arm a gate that rejected
  # every hooks.json would satisfy the assertions above and brick delivery outright.
  setup
  export_valid_env_vars
  export HOOKS_JSON_B64=$(_payload_file '[{"id":"good","execute-command":"/usr/local/bin/inngest-inventory.sh"}]')
  bash "$HANDLER" >/dev/null 2>&1 || true
  local ok_reasons
  ok_reasons=$(jq -r '.files[]?.reason // empty' "$INFRA_CONFIG_STATE" 2>/dev/null | tr '\n' ' ' || true)
  if [[ "$ok_reasons" != *"hooks_json_unparseable"* ]]; then
    echo "  PASS: a well-formed hooks.json is not flagged"; PASS=$((PASS + 1))
  else
    echo "  FAIL: a VALID hooks.json was flagged unparseable — the guard rejects everything"
    FAIL=$((FAIL + 1))
  fi
  teardown
}

# B5.2 -- --collect on the transient unit, in argv lockstep with BOTH sudoers copies.
#
# --unit=webhook-self-restart is a FIXED name. A transient unit that FAILS is not garbage
# collected, so the next apply's systemd-run fails "unit already exists" -- permanently, and
# silently, on the only remediation channel. --collect changes the argv, and sudo matches the
# full resolved command, so the grant must move with it or the self-restart becomes denied.
test_self_restart_collect_argv_lockstep() {
  echo "TEST: #7220 B5.2 — --collect is sent AND granted in both provisioning paths"
  local sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"
  local expected="/usr/bin/systemd-run --collect --on-active=3s --unit=webhook-self-restart /usr/bin/systemctl restart webhook"

  local g_sudoers g_cloudinit
  g_sudoers=$(sed -n 's/^Cmnd_Alias WEBHOOK_SELF_RESTART = //p' "$sudoers" | sed 's/[[:space:]]*$//')
  g_cloudinit=$(sed -n 's/^[[:space:]]*Cmnd_Alias WEBHOOK_SELF_RESTART = //p' "$cloud_init" | sed 's/[[:space:]]*$//')
  assert_eq "sudoers grants the --collect argv" "$expected" "$g_sudoers"
  assert_eq "cloud-init grants the --collect argv" "$expected" "$g_cloudinit"

  # A Cmnd_Alias with no User_Spec grants NOTHING — the same reasoning the daemon-reload arm
  # applies, now applied to the sibling grant this PR edits. Measured by review: deleting this
  # binding from BOTH sudoers sources left the suite fully green, so the self-restart would be
  # denied in production with nothing red — the silent no-op class, on the delayed restart B5
  # exists to make reachable for the first time since ~2026-05.
  if grep -qE '^deploy ALL=\(root\) NOPASSWD: WEBHOOK_SELF_RESTART$' "$sudoers"; then
    echo "  PASS: sudoers binds WEBHOOK_SELF_RESTART to deploy via a User_Spec"; PASS=$((PASS + 1))
  else
    echo "  FAIL: WEBHOOK_SELF_RESTART has no 'deploy ALL=(root) NOPASSWD:' line — the alias grants nothing"
    FAIL=$((FAIL + 1))
  fi
  if grep -qE '^[[:space:]]*deploy ALL=\(root\) NOPASSWD: WEBHOOK_SELF_RESTART$' "$cloud_init"; then
    echo "  PASS: cloud-init binds WEBHOOK_SELF_RESTART to deploy via a User_Spec"; PASS=$((PASS + 1))
  else
    echo "  FAIL: cloud-init defines WEBHOOK_SELF_RESTART without a User_Spec"
    FAIL=$((FAIL + 1))
  fi

  # The caller must send exactly that. Anchored on the sudo-prefixed call, not a bare --collect
  # grep, which would also match this file's own prose.
  if grep -qF "sudo $expected" "$HANDLER"; then
    echo "  PASS: the handler sends the granted --collect argv"; PASS=$((PASS + 1))
  else
    echo "  FAIL: handler's systemd-run argv does not match the grant — the self-restart would be DENIED"
    FAIL=$((FAIL + 1))
  fi
}

# B5.3 -- StartLimitIntervalSec=0.
#
# webhook.service sets Restart=on-failure / RestartSec=5 with no start-limit override, so
# systemd's default 5-in-10s applies. The first post-merge apply performs TWO restarts in quick
# succession (server.tf's synchronous one, then the handler's). Blowing the limit leaves webhook
# `failed` and needing `systemctl reset-failed` -- i.e. SSH, on the host that has none.
test_webhook_start_limit_disabled() {
  echo "TEST: #7220 B5.3 — webhook.service disables the systemd start limit"
  local unit="${SCRIPT_DIR}/webhook.service"
  # Must live in [Unit]: systemd ignores StartLimitIntervalSec in [Service] on modern versions.
  local in_unit
  in_unit=$(awk '/^\[Unit\]/{u=1;next} /^\[/{u=0} u && /^StartLimitIntervalSec=0[[:space:]]*$/{n++} END{print n+0}' "$unit")
  assert_eq "StartLimitIntervalSec=0 is present in the [Unit] section" "1" "$in_unit"
}

test_daemon_reload_grant_lockstep() {
  echo "TEST: #7220 B2 — daemon-reload is granted, and the handler sends the granted argv"
  local sudoers="${SCRIPT_DIR}/deploy-inngest-bootstrap.sudoers"
  local cloud_init="${SCRIPT_DIR}/cloud-init.yml"

  # (a) Both provisioning paths must grant it, and grant the SAME thing. cloud-init is create-time
  # under ignore_changes=[user_data] and the sudoers file is the delivered copy; a host provisioned
  # from one and reconciled by the other must end up with identical authority.
  local g_sudoers g_cloudinit
  g_sudoers=$(sed -n 's/^Cmnd_Alias SYSTEMCTL_DAEMON_RELOAD = //p' "$sudoers" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  g_cloudinit=$(sed -n 's/^[[:space:]]*Cmnd_Alias SYSTEMCTL_DAEMON_RELOAD = //p' "$cloud_init" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  # Each side is pinned against the LITERAL, not against the other. A bare cross-file equality
  # passes vacuously when both extractions come back empty — measured on this arm's first RED
  # run, where "" == "" reported PASS while neither file granted anything at all.
  assert_eq "sudoers grants daemon-reload" "/usr/bin/systemctl daemon-reload" "$g_sudoers"
  assert_eq "cloud-init mirror grants the identical argv" "/usr/bin/systemctl daemon-reload" "$g_cloudinit"

  # (b) A Cmnd_Alias with no User_Spec grants NOTHING — it is a definition, not an authorisation.
  # Asserting only the alias would pass against a file that never says `deploy ALL=(root)`.
  if grep -qE '^deploy ALL=\(root\) NOPASSWD: SYSTEMCTL_DAEMON_RELOAD$' "$sudoers"; then
    echo "  PASS: sudoers binds the alias to deploy via a User_Spec"; PASS=$((PASS + 1))
  else
    echo "  FAIL: SYSTEMCTL_DAEMON_RELOAD has no 'deploy ALL=(root) NOPASSWD:' line — the alias grants nothing"
    FAIL=$((FAIL + 1))
  fi
  if grep -qE '^[[:space:]]*deploy ALL=\(root\) NOPASSWD: SYSTEMCTL_DAEMON_RELOAD$' "$cloud_init"; then
    echo "  PASS: cloud-init binds the alias to deploy via a User_Spec"; PASS=$((PASS + 1))
  else
    echo "  FAIL: cloud-init mirror defines the alias without a User_Spec"
    FAIL=$((FAIL + 1))
  fi

  # (c) The CALLER must actually route through the seam. A bare `systemctl daemon-reload` (what
  # shipped, and what #7220 is) would be denied no matter how the grant is written, so asserting
  # the grant alone proves nothing about whether the reload can run.
  # shellcheck disable=SC2016
  local seam_default
  seam_default=$(sed -n 's/^SYSTEMCTL_PRIV="\${INFRA_CONFIG_SYSTEMCTL:-\(.*\)}"$/\1/p' "$HANDLER")
  assert_eq "the privileged seam defaults to a sudo-prefixed absolute systemctl" \
    "sudo /usr/bin/systemctl" "$seam_default"
  # Anchored on the seam variable, not on the bare verb: a bare-token grep would match the
  # prose in this file's own header comments describing the bug.
  if grep -qE '^[[:space:]]*\$SYSTEMCTL_PRIV daemon-reload$' "$HANDLER"; then
    echo "  PASS: the handler invokes daemon-reload through the privileged seam"; PASS=$((PASS + 1))
  else
    echo "  FAIL: handler does not call daemon-reload via \$SYSTEMCTL_PRIV — this is the #7220 shape"
    FAIL=$((FAIL + 1))
  fi
  # And the un-seamed form must be GONE, not merely joined by a seamed one.
  if grep -qE '^[[:space:]]*systemctl daemon-reload$' "$HANDLER"; then
    echo "  FAIL: a bare 'systemctl daemon-reload' survives in the handler — it would be denied"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: no bare un-seamed daemon-reload remains"; PASS=$((PASS + 1))
  fi

  # (d) What sudoers grants is what sudo RUNS, so the granted argv is the seam minus its sudo
  # prefix. This is the join that makes (a) and (c) one property rather than two coincidences.
  assert_eq "granted argv equals the caller's resolved argv" \
    "${seam_default#sudo } daemon-reload" "$g_sudoers"
}

# --- #7220 B7: the reload actually runs, and its denial is attributed --------------------
#
# TWO ARMS, and the pair is the point. The denied arm alone would pass against a handler that
# never calls daemon-reload at all (no call, no denial, no fatal marker — vacuously "correct"),
# which is the shape #7220 shipped in. The success arm is what makes the denial meaningful.
test_daemon_reload_runs_on_a_clean_apply() {
  echo "TEST: #7220 B7 — a clean apply invokes daemon-reload through the seam, exactly once"
  restart_setup
  arm_unit vector.service active "$(date -u +%s)"
  bash "$HANDLER" >/dev/null 2>&1 || true

  # POSITIVE CONTROL. Counted, not just present: the handler must not reload per-file (19x on
  # every apply is a real cost on a cx33) and must not skip it.
  local n_reload
  n_reload=$(grep -c '^daemon-reload$' "$STUB_CALLS" 2>/dev/null || true)
  [[ "$n_reload" =~ ^[0-9]+$ ]] || n_reload=0
  assert_eq "daemon-reload invoked exactly once per apply" "1" "$n_reload"

  # The argv is EXACTLY the granted one. The stub exits 64 on a stray argument, so a handler
  # sending `daemon-reload --now` would surface here rather than in production as a denial.
  if grep -qxF 'daemon-reload' "$STUB_CALLS"; then
    echo "  PASS: the argv sent is exactly 'daemon-reload', no extra arguments"; PASS=$((PASS + 1))
  else
    echo "  FAIL: daemon-reload argv is not the granted shape: $(tr '\n' ';' < "$STUB_CALLS")"
    FAIL=$((FAIL + 1))
  fi

  # A successful reload is NOT a fatal event — the channel must stay quiet, or it trains the
  # reader to ignore the one time it fires (AC14).
  local n_fatal
  n_fatal=$(grep -c 'SOLEUR_INFRA_CONFIG_FATAL' "$LOGGER_LOG" 2>/dev/null || true)
  [[ "$n_fatal" =~ ^[0-9]+$ ]] || n_fatal=0
  assert_eq "zero fatal markers when the reload succeeds" "0" "$n_fatal"
  assert_eq "fatal_line zeroed when the reload succeeds" "0" "$(_frame_field fatal_line)"

  restart_teardown
}

# THE REACHABILITY ARM. Everything else in this suite runs with INFRA_CONFIG_TEST_MODE=1 (set by
# setup()), so every assertion about the reload is an assertion about a path the SUITE takes —
# never about the path PRODUCTION takes. Measured by review: wrapping the call site in the
# INVERSE guard, `if [[ -n "${INFRA_CONFIG_TEST_MODE:-}" ]]`, left all 171 assertions green. That
# mutant is #7220 byte-for-byte: files delivered, activation never happens on a real host, and
# the suite says everything is fine.
#
# So this arm runs the handler with TEST_MODE UNSET — the prod-shaped path — with the seams and
# PATH stubs still in place, and asserts the reload actually fired. It is the only arm that can
# distinguish "the reload runs" from "the reload runs where the tests can see it".
test_daemon_reload_reachable_with_test_mode_unset() {
  echo "TEST: #7220 — the reload fires on the PROD path (INFRA_CONFIG_TEST_MODE unset)"
  restart_setup
  arm_unit vector.service active "$(date -u +%s)"
  # The prod path. sync, sudo and systemd-run are PATH-stubbed by setup(); the WRITE seam is
  # stubbed by restart_setup. Nothing here touches the real host.
  unset INFRA_CONFIG_TEST_MODE
  bash "$HANDLER" >/dev/null 2>&1 || true

  local n_reload
  n_reload=$(grep -c '^daemon-reload$' "$STUB_CALLS" 2>/dev/null || true)
  [[ "$n_reload" =~ ^[0-9]+$ ]] || n_reload=0
  if [[ "$n_reload" -ge 1 ]]; then
    echo "  PASS: daemon-reload fires with TEST_MODE unset — the call site is reachable in prod"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: daemon-reload did NOT fire on the prod path — the reload is test-only, which is #7220"
    FAIL=$((FAIL + 1))
  fi

  # NON-VACUITY: prove this arm really took the prod branch. `sync` is guarded by the same
  # TEST_MODE check, so if it did not run, TEST_MODE was still set and the assertion above
  # proved nothing about production.
  if [[ -f "$STUB_STATE/../synced" ]] || grep -qF 'daemon-reload' "$STUB_CALLS" 2>/dev/null; then
    echo "  PASS: the prod branch was actually entered"; PASS=$((PASS + 1))
  else
    echo "  FAIL: could not confirm the prod branch was entered — this arm is vacuous"
    FAIL=$((FAIL + 1))
  fi

  export INFRA_CONFIG_TEST_MODE=1
  restart_teardown
}

test_daemon_reload_denied_is_attributed() {
  echo "TEST: #7220 B7 — a DENIED daemon-reload is named by the fatal channel (this is #7220)"
  restart_setup
  arm_unit vector.service active "$(date -u +%s)"
  # Reproduce the exact production failure: the grant is absent, so polkit refuses.
  printf '1' > "$STUB_STATE/daemon-reload.deny"

  local rc=0
  bash "$HANDLER" >/dev/null 2>&1 || rc=$?

  # It must DIE, not limp on. A reload that silently failed is what left every managed unit
  # running its start-time environment for ~3 months.
  if [[ "$rc" -ne 0 ]]; then
    echo "  PASS: a denied reload fails the apply rather than passing silently"; PASS=$((PASS + 1))
  else
    echo "  FAIL: handler exited 0 despite a denied daemon-reload — the #7220 silent failure"
    FAIL=$((FAIL + 1))
  fi

  # And PR-A's channel must name it. This is the join between the two PRs: the instrument
  # shipped in PR-A is what makes this repair's failure mode diagnosable without SSH.
  # fatal_cmd carries $BASH_COMMAND, which is UNEXPANDED source text — that is the property
  # keeping secrets out of the frame, and it is deliberate. A consequence of routing the reload
  # through the seam (B4) is that the operator now reads `?SYSTEMCTL_PRIV daemon-reload` where
  # the pre-B4 bare call produced `systemctl daemon-reload` (the `$` is sanitized to `?`).
  #
  # KNOWN OPERATOR-FACING WART, deliberately asserted rather than papered over: the actionable
  # word survives, so the annotation still tells a non-technical operator WHICH step died, but
  # the seam's variable name is noise they cannot act on. Flagged for the mandatory
  # user-impact-reviewer pass on this PR rather than silently accepted.
  local f_cmd
  f_cmd=$(_frame_field fatal_cmd)
  if [[ "$f_cmd" == *"daemon-reload"* ]]; then
    echo "  PASS: fatal_cmd names the failing verb ($f_cmd)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: fatal_cmd '$f_cmd' does not name daemon-reload — the operator cannot tell what died"
    FAIL=$((FAIL + 1))
  fi
  local f_line
  f_line=$(_frame_field fatal_line)
  if [[ "$f_line" =~ ^[0-9]+$ ]] && [[ "$f_line" -gt 0 ]]; then
    echo "  PASS: fatal_line carries a real coordinate ($f_line)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: fatal_line is '$f_line' — attribution missing, which is #7220's original shape"
    FAIL=$((FAIL + 1))
  fi

  # NON-VACUITY: the files were still delivered. If this read 0 the arm would be measuring a
  # handler that died before writing anything, not one that died at activation — a different
  # bug wearing the same assertion.
  local written
  written=$(_frame_field files_written)
  if [[ "$written" =~ ^[0-9]+$ ]] && [[ "$written" -gt 0 ]]; then
    echo "  PASS: delivery still completed ($written files) — the failure is activation, not delivery"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: files_written='$written' — this arm is not exercising the activation failure"
    FAIL=$((FAIL + 1))
  fi

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
  seam_default=$(sed -n 's/^SYSTEMCTL_PRIV="\${INFRA_CONFIG_SYSTEMCTL:-\(.*\)}"$/\1/p' "$HANDLER")
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
# The two load-bearing properties below — attribution (fatal_line) and real accounting
# (files_total) — are proven RED against the PINNED pre-fix handler by
# `test_fatal_channel_red_against_pre_fix`. Scoped deliberately: that arm drives ONE scenario
# (poisoned sha256sum) and checks those two fields, so it does not and cannot prove the
# quiet-channel arms (partial-apply-is-not-a-death, clean-apply-exits-zero) RED — those are
# expected GREEN against the old handler by construction.
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
# if the git object is unavailable, so a vacuous pass is never mistaken for a proof. (NOT
# "detached worktree" — a linked worktree shares the common object database, so a commit present
# in the clone is reachable regardless of HEAD state. The pin falsified that half of the old
# note; absence now means the OBJECT is missing, not that HEAD moved.)
#
# NOTE for the next maintainer: this arm runs a FROZEN 2026-08-03 handler through the LIVE
# fixture path (setup / export_valid_env_vars / _frame_field). If the frame schema changes, this
# arm asserts against the OLD schema by design — update the expected literal, do NOT repoint the
# SHA. A red here can mean fixture drift rather than a regression.
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
# The pinned commit below is the last to touch infra-config-apply.sh BEFORE c2de2581e. Full
# 40-char SHA, not an abbreviation, so no future object can make it ambiguous. Verified at that
# commit: the handler contains `fatal_line` zero times and hardcodes "files_total":0 in its
# EXIT trap.
#
# REACHABILITY is what keeps this pin working, and the SHA's LENGTH does not provide it: the
# commit is an ancestor of main AND carries tags web-v0.248.2 / v3.243.2, and deploy-script-tests
# checks out with fetch-depth: 0 + fetch-tags: true. Do not prune those tags or narrow that
# checkout without re-reading the skip/fail arms below.
readonly PRE_FIX_HANDLER_SHA="701e76e6bfce84ceed91096a58d88df7da5b6932"

test_fatal_channel_red_against_pre_fix() {
  echo "TEST: #7220 — the new assertions are RED against the pre-fix handler"
  setup
  export_valid_env_vars

  local old="${TMPDIR_ROOT}/old-handler.sh"
  if ! git -C "$SCRIPT_DIR" show "${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh" > "$old" 2>/dev/null; then
    # Probe the BLOB, not the commit. `cat-file -e <sha>^{commit}` is the intuitive check and is
    # wrong here: a BLOBLESS clone (`--filter=blob:none`, a routine CI speed-up) has the commit
    # object present while the handler's blob is unfetchable, so a commit-probe sends a
    # legitimate environment to the hard-FAIL arm — the inverse of the bug this guard fixes.
    # The blob is absent in exactly the environments that should SKIP and present in exactly
    # those that should FAIL, so it is the predicate that matches the two arms.
    #
    # Also NOT `rev-parse --verify`: that returns 0 for any well-formed 40-hex string whose
    # object is ABSENT (measured on git 2.53.0), which would make the skip arm dead code.
    if git -C "$SCRIPT_DIR" cat-file -e "${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh" 2>/dev/null; then
      echo "  FAIL: pinned pre-fix commit resolves but the handler could not be read — mutation proof is broken, not skipped"
      FAIL=$((FAIL + 1))
    elif [[ -n "${CI:-}" ]]; then
      # Under CI the pinned commit is REACHABLE BY CONTRACT (deploy-script-tests checks out with
      # fetch-depth: 0 + fetch-tags: true), so absence is a breakage, not an environment limit.
      # Pinning widened this window relative to the old `origin/main` read — a remote-tracking
      # ref resolves at ANY depth, a specific historical commit does not — so the arm that
      # absence lands on must be the LOUD one wherever the depth is guaranteed.
      echo "  FAIL: pinned pre-fix commit ${PRE_FIX_HANDLER_SHA:0:9} is absent under CI, where fetch-depth: 0 should guarantee it — mutation proof NOT run"
      FAIL=$((FAIL + 1))
    else
      # Local/offline only. Cause is deliberately NOT narrowed to "shallow clone": `cat-file -e`
      # measures ABSENCE, and absence is equally produced by a partial/treeless clone, rewritten
      # history that orphaned the object, a pruned tag, or running outside the soleur checkout.
      # Naming one unmeasured cause sends the reader to fix something that was never wrong.
      echo "  SKIP (loud): pinned pre-fix commit ${PRE_FIX_HANDLER_SHA:0:9} not in this object store (shallow/partial clone, rewritten history, or not run inside the soleur checkout) — mutation proof NOT run."
      echo "              Remedy: run from a full clone (git fetch --unshallow), or re-pin to tag web-v0.248.2."
      # 4: sabotage-reached, frame-published, no-fatal_line, files_total=0.
      SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 4))
    fi
    teardown
    return 0
  fi
  # Guard the pin itself: if this object ever stops being the pre-fix handler (a bad rebase, a
  # mis-typed SHA), the arm would silently prove nothing. The pre-fix handler has none of the
  # fix's markers — assert that before trusting it as a baseline.
  if grep -q 'local died=0' "$old"; then
    echo "  FAIL: pinned baseline already contains the #7220 fix — it is not a pre-fix handler"
    FAIL=$((FAIL + 1))
    teardown
    return 0
  fi

  # The sabotage is what makes this #7220's SHAPE (a delivery that got partway and then died)
  # rather than any old abort. It must be PROVEN to have been reached: without this witness,
  # injecting an `exit 99` immediately after the EXIT trap installs — dying before the write
  # loop, never invoking sha256sum — leaves BOTH assertions below passing at 146/0, because the
  # trap emits its hardcoded zeros for ANY unhandled exit. The test would then prove only "the
  # old abort frame is uninformative", never "the old handler could not attribute a DELIVERY
  # failure". Measured: that mutation survives the two assertions and dies on this one.
  local sabotage_witness="$TMPDIR_ROOT/sha256sum-invoked"
  printf '#!/bin/sh\nprintf x >> %s\nexit 7\n' "$sabotage_witness" > "$TMPDIR_ROOT/bin/sha256sum"
  chmod +x "$TMPDIR_ROOT/bin/sha256sum"
  bash "$old" >/dev/null 2>&1 || true

  assert_eq "the sabotage was actually reached — the handler got INTO the delivery path" \
    "yes" "$([[ -s "$sabotage_witness" ]] && echo yes || echo no)"

  # The pre-fix handler wrote hardcoded zeros and carried no attribution at all.
  local old_line old_total old_reason
  old_line=$(_frame_field fatal_line)
  old_total=$(_frame_field files_total)
  old_reason=$(_frame_field reason)
  # `_frame_field` returns the literal MISSING both when the FIELD is absent and when the FRAME
  # is absent, so the fatal_line assertion alone is satisfied by the empty universe — replacing
  # `bash "$old"` with a no-op leaves it passing. Asserting a field that must EXIST is what
  # pins that a frame was actually published.
  assert_eq "a frame was actually published (not the empty universe)" "unhandled" "$old_reason"
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
    # 1: the behavioural "foreign-owned handoff ignored" assertion.
    SKIPPED_ASSERTIONS=$((SKIPPED_ASSERTIONS + 1))
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
test_handler_to_grant_lint
test_unparseable_hooks_json_is_a_hard_failure
test_self_restart_collect_argv_lockstep
test_webhook_start_limit_disabled
test_daemon_reload_grant_lockstep
test_daemon_reload_runs_on_a_clean_apply
test_daemon_reload_reachable_with_test_mode_unset
test_daemon_reload_denied_is_attributed
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
#
# RATCHET WHEN THE SUITE GROWS. This is a floor, not an equality — but a floor left behind by a
# growing suite silently re-opens the hole it was built to close. Measured at the 144-assertion
# era, it carried 2 assertions of slack; the pinned proof-of-red arm costs EXACTLY 2, so a
# silently-skipping guard landed on 144 >= 142 and passed. Re-measured against the current suite
# so the skip arm now reds instead of reading green.
#
# This is deliberately set to the FULL current count, i.e. zero headroom. That is what makes the
# skip detectable, and the cost is that it must be ratcheted with every added assertion — treat a
# floor failure on a green-looking suite as "you added assertions, update this number", not as a
# regression.
#
# ZERO HEADROOM AND ENVIRONMENT-CONDITIONAL SKIPS ARE IN DIRECT CONFLICT, and resolving that by
# lowering the floor would give back exactly the detectability above. The three LOUD skip arms in
# this suite (the AC6 RED proof and the pre-fix mutation proof, both of which need the pinned
# pre-fix blob; and the foreign-ownership arm, which needs root) each DECLARE their assertion
# cost into SKIPPED_ASSERTIONS at the moment they skip. The floor is then compared against
# PASS + SKIPPED, so a declared skip on a shallow clone or a non-root runner leaves the floor
# satisfied while a guard that stops running WITHOUT declaring anything still reds. That is the
# distinction the previous form could not draw: it read a legitimate loud skip and a silently
# vanished arm as the same number.
#
# 180 = the FULL count, measured as PASS + SKIPPED_ASSERTIONS, which is invariant across
# environments by construction: a non-root runner declares 1, a clone without the pinned pre-fix
# blob declares 5 (1 for the AC6 RED proof + 4 for the fatal-channel proof), and each still totals
# 180. Verified by forcing both skip paths on a sandbox copy — see the PR body.
APPLY_MIN_ASSERTIONS=180
if [[ $((PASS + SKIPPED_ASSERTIONS)) -lt "$APPLY_MIN_ASSERTIONS" ]]; then
  echo "  FAIL: assertion-count floor — $PASS assertions ran and $SKIPPED_ASSERTIONS were declared-skipped, expected >= $APPLY_MIN_ASSERTIONS"
  FAIL=$((FAIL + 1))
fi
if [[ "$SKIPPED_ASSERTIONS" -gt 0 ]]; then
  echo "  NOTE: $SKIPPED_ASSERTIONS assertion(s) were declared-skipped by loud SKIP arms — this run is weaker than a full one."
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
