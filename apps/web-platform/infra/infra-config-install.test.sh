#!/usr/bin/env bash
# Tests for infra-config-install.sh — the pinned root-run escalation helper that
# infra-config-apply.sh invokes via sudo to write the 8 managed files into their
# root-owned destination directories (#4827).
#
# The helper is the security boundary for the wildcard-free sudoers grant
# (Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install): sudo
# permits the command with ANY arguments, so the helper itself enforces that the
# destination is in a hardcoded allowlist and that the staged source is not a
# TOCTOU-attackable symlink / wrong-owner file. Mirrors the inngest-bootstrap
# precedent's symlink/owner guards (ci-deploy.sh:693-702).
#
# Runs in a tmpdir sandbox; no root required (TEST_DESTDIR redirects writes and
# skips chown, exactly as infra-config-apply.sh does).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/infra-config-install.sh"

PASS=0
FAIL=0
TMPDIR_ROOT=""

# Exit codes the helper contract pins:
#   0 = installed, 3 = rejected (allowlist / TOCTOU), 1 = install failure, 2 = usage
readonly RC_OK=0
readonly RC_REJECTED=3

setup() {
  TMPDIR_ROOT=$(mktemp -d)
  export TEST_DESTDIR="${TMPDIR_ROOT}/dest"
  mkdir -p "$TEST_DESTDIR/usr/local/bin" \
           "$TEST_DESTDIR/etc/systemd/system" \
           "$TEST_DESTDIR/etc/webhook" \
           "$TEST_DESTDIR/etc/sudoers.d"
  STAGING="${TMPDIR_ROOT}/staging"
  mkdir -p "$STAGING"
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
  unset TEST_DESTDIR
}

# Stage a decoded payload file the way the handler would (deploy-writable dir).
stage_payload() {
  local name="$1" content="${2:-#!/bin/bash}"
  local src="${STAGING}/${name}"
  printf '%s' "$content" > "$src"
  echo "$src"
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

assert_file_mode() {
  local desc="$1" path="$2" expected_mode="$3"
  local actual_mode
  actual_mode=$(stat -c '%a' "$path" 2>/dev/null || echo "missing")
  assert_eq "$desc" "$expected_mode" "$actual_mode"
}

# --- Test 1: Happy path — allowlisted dest installs with correct content + mode ---
test_install_allowlisted() {
  echo "TEST: install — allowlisted dest writes content + mode atomically"
  setup
  local src; src=$(stage_payload "ci-deploy.sh" "#!/bin/bash\necho hi")

  local rc=0
  bash "$HELPER" "$src" "/usr/local/bin/ci-deploy.sh" "755" "root:root" || rc=$?
  assert_eq "helper exits 0 for allowlisted dest" "$RC_OK" "$rc"

  local dest="${TEST_DESTDIR}/usr/local/bin/ci-deploy.sh"
  if [[ -f "$dest" ]]; then
    echo "  PASS: file installed at dest"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: file not installed at dest"
    FAIL=$((FAIL + 1))
  fi
  assert_file_mode "installed file mode is 755" "$dest" "755"
  assert_eq "installed content matches src" "$(cat "$src")" "$(cat "$dest")"

  # No stray temp file left in the dest dir.
  local stray
  stray=$(find "${TEST_DESTDIR}/usr/local/bin" -name 'tmp.*' 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "no stray temp file in dest dir" "0" "$stray"

  teardown
}

# --- Test 2: Allowlist rejection — non-managed dest is refused (install_rejected) ---
test_reject_nonallowlisted_dest() {
  echo "TEST: install — non-allowlisted dest is rejected (rc=3)"
  setup
  local src; src=$(stage_payload "evil")

  local rc=0
  bash "$HELPER" "$src" "/etc/passwd" "644" "root:root" 2>/dev/null || rc=$?
  assert_eq "helper rejects dest not in allowlist" "$RC_REJECTED" "$rc"

  if [[ -f "${TEST_DESTDIR}/etc/passwd" ]]; then
    echo "  FAIL: rejected dest was written anyway"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: rejected dest not written"
    PASS=$((PASS + 1))
  fi

  teardown
}

# --- Test 3: Allowlist rejection — path traversal toward a managed dir is refused ---
test_reject_traversal() {
  echo "TEST: install — traversal-style dest is rejected (rc=3)"
  setup
  local src; src=$(stage_payload "evil")

  local rc=0
  bash "$HELPER" "$src" "/usr/local/bin/../../../etc/cron.d/evil" "644" "root:root" 2>/dev/null || rc=$?
  assert_eq "helper rejects traversal dest" "$RC_REJECTED" "$rc"

  teardown
}

# --- Test 4: TOCTOU — symlinked staging source is refused ---
test_reject_symlink_src() {
  echo "TEST: install — symlinked staging source is rejected (rc=3)"
  setup
  local real; real=$(stage_payload "real")
  local link="${STAGING}/link"
  ln -s "$real" "$link"

  local rc=0
  bash "$HELPER" "$link" "/usr/local/bin/ci-deploy.sh" "755" "root:root" 2>/dev/null || rc=$?
  assert_eq "helper rejects symlinked source" "$RC_REJECTED" "$rc"

  teardown
}

# --- Test 5: All 7 managed dests are accepted with their authoritative spec ---
# Each entry is "dest|mode|owner" — mode/owner MUST match the helper's internal
# table (caller-supplied values that disagree are rejected, #4827 hardening).
# The sudoers dest is intentionally absent (root-managed, not helper-writable).
test_all_managed_dests_accepted() {
  echo "TEST: install — every FILE_MAP dest is allowlisted (7, sudoers excluded)"
  setup
  local specs=(
    "/usr/local/bin/ci-deploy.sh|755|root:root"
    "/usr/local/bin/ci-deploy-wrapper.sh|755|root:root"
    "/etc/systemd/system/webhook.service|644|root:root"
    "/usr/local/bin/cat-deploy-state.sh|755|root:root"
    "/usr/local/bin/canary-bundle-claim-check.sh|755|root:root"
    "/etc/webhook/hooks.json|640|root:deploy"
    "/usr/local/bin/cat-infra-config-state.sh|755|root:root"
  )
  local accepted=0 entry d mode owner src rc
  for entry in "${specs[@]}"; do
    IFS='|' read -r d mode owner <<< "$entry"
    src=$(stage_payload "payload-$(basename "$d")")
    rc=0
    bash "$HELPER" "$src" "$d" "$mode" "$owner" 2>/dev/null || rc=$?
    [[ "$rc" == "$RC_OK" ]] && accepted=$((accepted + 1))
  done
  assert_eq "all 7 managed dests accepted" "7" "$accepted"

  teardown
}

# --- Test 6: Sudoers dest is rejected (root-managed, #4827 security review) ---
# A deploy user invoking the helper directly must NOT be able to write the
# grant-definition file (it could install `NOPASSWD: ALL`).
test_reject_sudoers_dest() {
  echo "TEST: install — sudoers dest is rejected (rc=3)"
  setup
  local src; src=$(stage_payload "evil-sudoers" "deploy ALL=(root) NOPASSWD: ALL")

  local rc=0
  bash "$HELPER" "$src" "/etc/sudoers.d/deploy-inngest-bootstrap" "440" "root:root" 2>/dev/null || rc=$?
  assert_eq "helper rejects the sudoers dest" "$RC_REJECTED" "$rc"

  teardown
}

# --- Test 7: setuid escalation via caller mode is rejected (#4827 hardening) ---
# mode/owner come from the helper's internal table, not the caller — a deploy
# user passing mode=4755 to setuid a root binary is refused.
test_reject_setuid_mode() {
  echo "TEST: install — caller mode mismatch (setuid attempt) is rejected (rc=3)"
  setup
  local src; src=$(stage_payload "ci-deploy.sh")

  local rc=0
  bash "$HELPER" "$src" "/usr/local/bin/ci-deploy.sh" "4755" "root:root" 2>/dev/null || rc=$?
  assert_eq "helper rejects setuid mode" "$RC_REJECTED" "$rc"

  if [[ -f "${TEST_DESTDIR}/usr/local/bin/ci-deploy.sh" ]]; then
    echo "  FAIL: setuid-mode call wrote the file anyway"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: setuid-mode call wrote nothing"
    PASS=$((PASS + 1))
  fi

  teardown
}

# --- Test 8: owner-seize via caller owner is rejected (#4827 hardening) ---
test_reject_owner_seize() {
  echo "TEST: install — caller owner mismatch (chown seize) is rejected (rc=3)"
  setup
  local src; src=$(stage_payload "ci-deploy.sh")

  local rc=0
  bash "$HELPER" "$src" "/usr/local/bin/ci-deploy.sh" "755" "deploy:deploy" 2>/dev/null || rc=$?
  assert_eq "helper rejects owner seize" "$RC_REJECTED" "$rc"

  teardown
}

# --- Run all tests ---
echo "=== infra-config-install.sh test suite ==="
test_install_allowlisted
test_reject_nonallowlisted_dest
test_reject_traversal
test_reject_symlink_src
test_all_managed_dests_accepted
test_reject_sudoers_dest
test_reject_setuid_mode
test_reject_owner_seize
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
