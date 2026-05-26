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
  chmod +x "$TMPDIR_ROOT/bin/systemd-run" "$TMPDIR_ROOT/bin/systemctl" "$TMPDIR_ROOT/bin/sudo"
  export PATH="$TMPDIR_ROOT/bin:$PATH"
  # Stub out daemon-reload and self-restart for test mode
  export INFRA_CONFIG_TEST_MODE=1
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
  unset TEST_DESTDIR INFRA_CONFIG_TEST_MODE
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

  export CI_DEPLOY_SH_B64=$(echo -n "#!/bin/bash\necho deploy" | base64 -w0)
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "#!/bin/bash\necho wrapper" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "[Unit]\nDescription=test" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "#!/bin/bash\necho state" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "#!/bin/bash\necho canary" | base64 -w0)
  export DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64=$(echo -n "deploy ALL=(root) NOPASSWD: /usr/bin/bash" | base64 -w0)
  export HOOKS_JSON_B64=$(echo -n '{"id":"deploy"}' | base64 -w0)

  bash "$HANDLER"
  local rc=$?
  assert_eq "handler exits 0" "0" "$rc"

  assert_file_exists "ci-deploy.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh"
  assert_file_exists "ci-deploy-wrapper.sh written" "$TEST_DESTDIR/usr/local/bin/ci-deploy-wrapper.sh"
  assert_file_exists "webhook.service written" "$TEST_DESTDIR/etc/systemd/system/webhook.service"
  assert_file_exists "cat-deploy-state.sh written" "$TEST_DESTDIR/usr/local/bin/cat-deploy-state.sh"
  assert_file_exists "canary-bundle-claim-check.sh written" "$TEST_DESTDIR/usr/local/bin/canary-bundle-claim-check.sh"
  assert_file_exists "sudoers written" "$TEST_DESTDIR/etc/sudoers.d/deploy-inngest-bootstrap"
  assert_file_exists "hooks.json written" "$TEST_DESTDIR/etc/webhook/hooks.json"

  assert_file_mode "ci-deploy.sh is executable" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh" "755"
  assert_file_mode "hooks.json is 640" "$TEST_DESTDIR/etc/webhook/hooks.json" "640"

  teardown
}

# --- Test 2: Missing env var rejection ---
test_missing_env_var() {
  echo "TEST: missing env var — handler rejects"
  setup

  # Set all but one required var
  export CI_DEPLOY_SH_B64=$(echo -n "test" | base64 -w0)
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "test" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "test" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "test" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "test" | base64 -w0)
  export DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64=$(echo -n "test" | base64 -w0)
  unset HOOKS_JSON_B64  # missing

  if bash "$HANDLER" 2>/dev/null; then
    echo "  FAIL: handler should have failed with missing HOOKS_JSON_B64"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: handler rejected missing env var"
    PASS=$((PASS + 1))
  fi

  teardown
}

# --- Test 3: Empty env var rejection ---
test_empty_env_var() {
  echo "TEST: empty env var — handler rejects"
  setup

  export CI_DEPLOY_SH_B64=""
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "test" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "test" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "test" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "test" | base64 -w0)
  export DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64=$(echo -n "test" | base64 -w0)
  export HOOKS_JSON_B64=$(echo -n "test" | base64 -w0)

  if bash "$HANDLER" 2>/dev/null; then
    echo "  FAIL: handler should have failed with empty CI_DEPLOY_SH_B64"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: handler rejected empty env var"
    PASS=$((PASS + 1))
  fi

  teardown
}

# --- Test 4: visudo failure halts sudoers install ---
test_visudo_failure() {
  echo "TEST: visudo failure — sudoers NOT installed"
  setup

  # Replace mock visudo with one that fails
  printf '#!/bin/sh\nexit 1\n' > "$TMPDIR_ROOT/bin/visudo"
  chmod +x "$TMPDIR_ROOT/bin/visudo"

  export CI_DEPLOY_SH_B64=$(echo -n "test" | base64 -w0)
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "test" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "test" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "test" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "test" | base64 -w0)
  export DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64=$(echo -n "bad sudoers" | base64 -w0)
  export HOOKS_JSON_B64=$(echo -n '{}' | base64 -w0)

  # Handler should still succeed (other files written) but sudoers must NOT be installed
  bash "$HANDLER" 2>/dev/null || true

  if [[ -f "$TEST_DESTDIR/etc/sudoers.d/deploy-inngest-bootstrap" ]]; then
    echo "  FAIL: sudoers file was installed despite visudo failure"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: sudoers file correctly NOT installed on visudo failure"
    PASS=$((PASS + 1))
  fi

  # Other files should still be written
  assert_file_exists "ci-deploy.sh still written" "$TEST_DESTDIR/usr/local/bin/ci-deploy.sh"
  assert_file_exists "hooks.json still written" "$TEST_DESTDIR/etc/webhook/hooks.json"

  teardown
}

# --- Test 5: Atomic write — no partial file at destination ---
test_atomic_write() {
  echo "TEST: atomic write — destination only has complete file"
  setup

  local content="line1\nline2\nline3\nthis is the end"
  export CI_DEPLOY_SH_B64=$(echo -n "$content" | base64 -w0)
  export CI_DEPLOY_WRAPPER_SH_B64=$(echo -n "test" | base64 -w0)
  export WEBHOOK_SERVICE_B64=$(echo -n "test" | base64 -w0)
  export CAT_DEPLOY_STATE_SH_B64=$(echo -n "test" | base64 -w0)
  export CANARY_BUNDLE_CLAIM_CHECK_SH_B64=$(echo -n "test" | base64 -w0)
  export DEPLOY_INNGEST_BOOTSTRAP_SUDOERS_B64=$(echo -n "test" | base64 -w0)
  export HOOKS_JSON_B64=$(echo -n "test" | base64 -w0)

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

# --- Run all tests ---
echo "=== infra-config-apply.sh test suite ==="
test_happy_path
test_missing_env_var
test_empty_env_var
test_visudo_failure
test_atomic_write
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
