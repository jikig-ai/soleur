#!/usr/bin/env bash
# Tests for infra-config-install.sh — the pinned root-run escalation helper that
# infra-config-apply.sh invokes via sudo to write the 7 managed files into their
# root-owned destination directories (#4827).
#
# The helper is the security boundary for the wildcard-free sudoers grant
# (Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install): sudo
# permits the command with ANY arguments, so the helper itself enforces that the
# destination is in a hardcoded allowlist and that mode/owner match its
# authoritative table (a deploy user cannot setuid/chown a root binary). The
# payload is read from STDIN, not a file path, so there is no caller-controlled
# source to symlink-swap (#4827 security review P1).
#
# Runs in a tmpdir sandbox; no root required (TEST_DESTDIR redirects writes and
# skips chown, exactly as infra-config-apply.sh does).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/infra-config-install.sh"
HANDLER="${SCRIPT_DIR}/infra-config-apply.sh"

PASS=0
FAIL=0
TMPDIR_ROOT=""

# Exit codes the helper contract pins:
#   0 = installed, 3 = rejected (allowlist / mode-owner mismatch / dest-symlink),
#   1 = install failure, 2 = usage
readonly RC_OK=0
readonly RC_REJECTED=3

setup() {
  TMPDIR_ROOT=$(mktemp -d)
  export TEST_DESTDIR="${TMPDIR_ROOT}/dest"
  mkdir -p "$TEST_DESTDIR/usr/local/bin" \
           "$TEST_DESTDIR/etc/systemd/system" \
           "$TEST_DESTDIR/etc/webhook" \
           "$TEST_DESTDIR/etc/sudoers.d"
}

teardown() {
  rm -rf "$TMPDIR_ROOT"
  unset TEST_DESTDIR
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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — '$needle' not in '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_written() {
  local desc="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo "  FAIL: $desc — file was written: $path"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

assert_file_mode() {
  local desc="$1" path="$2" expected_mode="$3"
  local actual_mode
  actual_mode=$(stat -c '%a' "$path" 2>/dev/null || echo "missing")
  assert_eq "$desc" "$expected_mode" "$actual_mode"
}

# Run the helper with payload on stdin; capture stderr + rc.
# Usage: run_helper <payload> <dest> <mode> <owner>  → sets HELPER_RC, HELPER_ERR
run_helper() {
  local payload="$1" dest="$2" mode="$3" owner="$4"
  HELPER_RC=0
  HELPER_ERR=$(printf '%s' "$payload" | bash "$HELPER" "$dest" "$mode" "$owner" 2>&1 1>/dev/null) || HELPER_RC=$?
}

# --- Test 1: Happy path — allowlisted dest installs stdin payload with correct mode ---
test_install_allowlisted() {
  echo "TEST: install — allowlisted dest writes stdin payload + mode atomically"
  setup
  local content="#!/bin/bash"$'\n'"echo hi"

  local rc=0
  printf '%s' "$content" | bash "$HELPER" "/usr/local/bin/ci-deploy.sh" "755" "root:root" || rc=$?
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
  assert_eq "installed content matches stdin" "$content" "$(cat "$dest")"

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
  run_helper "evil" "/etc/passwd" "644" "root:root"
  assert_eq "helper rejects dest not in allowlist" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is dest_not_allowlisted" "$HELPER_ERR" "dest_not_allowlisted"
  assert_not_written "rejected dest not written" "${TEST_DESTDIR}/etc/passwd"
  teardown
}

# --- Test 3: Allowlist rejection — path traversal toward a managed dir is refused ---
test_reject_traversal() {
  echo "TEST: install — traversal-style dest is rejected (rc=3)"
  setup
  run_helper "evil" "/usr/local/bin/../../../etc/cron.d/evil" "644" "root:root"
  assert_eq "helper rejects traversal dest" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is dest_not_allowlisted" "$HELPER_ERR" "dest_not_allowlisted"
  assert_not_written "traversal dest not written" "${TEST_DESTDIR}/etc/cron.d/evil"
  teardown
}

# --- Test 4: dest-symlink rejection — refuse writing through a symlinked dest ---
test_reject_dest_symlink() {
  echo "TEST: install — symlinked destination is rejected (rc=3)"
  setup
  # Pre-plant a symlink at an allowlisted dest pointing elsewhere.
  local victim="${TMPDIR_ROOT}/victim"
  printf 'original' > "$victim"
  ln -s "$victim" "${TEST_DESTDIR}/usr/local/bin/ci-deploy.sh"

  run_helper "payload" "/usr/local/bin/ci-deploy.sh" "755" "root:root"
  assert_eq "helper rejects symlinked dest" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is dest_symlink" "$HELPER_ERR" "dest_symlink"
  assert_eq "symlink victim untouched" "original" "$(cat "$victim")"
  teardown
}

# --- Test 5: All 7 managed dests are accepted with their authoritative spec ---
# Each entry is "dest|mode|owner" — mode/owner MUST match the helper's internal
# table (caller-supplied values that disagree are rejected, #4827 hardening).
# The sudoers dest is intentionally absent (root-managed, not helper-writable).
test_all_managed_dests_accepted() {
  echo "TEST: install — every FILE_MAP dest is allowlisted (11, sudoers excluded)"
  setup
  local specs=(
    "/usr/local/bin/ci-deploy.sh|755|root:root"
    "/usr/local/bin/ci-deploy-wrapper.sh|755|root:root"
    "/etc/systemd/system/webhook.service|644|root:root"
    "/usr/local/bin/cat-deploy-state.sh|755|root:root"
    "/usr/local/bin/canary-bundle-claim-check.sh|755|root:root"
    "/etc/webhook/hooks.json|640|root:deploy"
    "/usr/local/bin/cat-infra-config-state.sh|755|root:root"
    "/usr/local/bin/inngest-enumerate-reminders.sh|755|root:root"
    "/usr/local/bin/inngest-rearm-reminders.sh|755|root:root"
    "/usr/local/bin/inngest-wiped-volume-verify.sh|755|root:root"
    "/usr/local/bin/cat-inngest-verify-state.sh|755|root:root"
    "/usr/local/bin/inngest-inventory.sh|755|root:root"
  )
  local accepted=0 entry d mode owner rc
  for entry in "${specs[@]}"; do
    IFS='|' read -r d mode owner <<< "$entry"
    rc=0
    printf 'payload-%s' "$(basename "$d")" | bash "$HELPER" "$d" "$mode" "$owner" 2>/dev/null || rc=$?
    [[ "$rc" == "$RC_OK" ]] && accepted=$((accepted + 1))
  done
  assert_eq "all 12 managed dests accepted" "12" "$accepted"
  teardown
}

# --- Test 6: Sudoers dest is rejected (root-managed, #4827 security review) ---
# A deploy user invoking the helper directly must NOT be able to write the
# grant-definition file (it could install `NOPASSWD: ALL`).
test_reject_sudoers_dest() {
  echo "TEST: install — sudoers dest is rejected (rc=3)"
  setup
  run_helper "deploy ALL=(root) NOPASSWD: ALL" "/etc/sudoers.d/deploy-inngest-bootstrap" "440" "root:root"
  assert_eq "helper rejects the sudoers dest" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is dest_not_allowlisted" "$HELPER_ERR" "dest_not_allowlisted"
  assert_not_written "sudoers dest not written" "${TEST_DESTDIR}/etc/sudoers.d/deploy-inngest-bootstrap"
  teardown
}

# --- Test 7: setuid escalation via caller mode is rejected (#4827 hardening) ---
# mode/owner come from the helper's internal table, not the caller — a deploy
# user passing mode=4755 to setuid a root binary is refused. Uses an ALLOWLISTED
# dest so the allowlist passes and the MODE check is the gate actually exercised.
test_reject_setuid_mode() {
  echo "TEST: install — caller mode mismatch (setuid attempt) is rejected (rc=3)"
  setup
  run_helper "payload" "/usr/local/bin/ci-deploy.sh" "4755" "root:root"
  assert_eq "helper rejects setuid mode" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is mode_mismatch (not allowlist short-circuit)" "$HELPER_ERR" "mode_mismatch"
  assert_not_written "setuid-mode call wrote nothing" "${TEST_DESTDIR}/usr/local/bin/ci-deploy.sh"
  teardown
}

# --- Test 8: owner-seize via caller owner is rejected (#4827 hardening) ---
test_reject_owner_seize() {
  echo "TEST: install — caller owner mismatch (chown seize) is rejected (rc=3)"
  setup
  run_helper "payload" "/usr/local/bin/ci-deploy.sh" "755" "deploy:deploy"
  assert_eq "helper rejects owner seize" "$RC_REJECTED" "$HELPER_RC"
  assert_contains "reason is owner_mismatch" "$HELPER_ERR" "owner_mismatch"
  assert_not_written "owner-seize call wrote nothing" "${TEST_DESTDIR}/usr/local/bin/ci-deploy.sh"
  teardown
}

# --- Test 9: usage error — wrong arg count exits 2 ---
test_usage_error() {
  echo "TEST: install — wrong arg count exits 2"
  setup
  local rc=0
  printf 'x' | bash "$HELPER" "/usr/local/bin/ci-deploy.sh" "755" 2>/dev/null || rc=$?
  assert_eq "helper exits 2 on wrong arg count" "2" "$rc"
  teardown
}

# --- Test 10: DEST_SPEC ↔ FILE_MAP cardinality lockstep (cross-file invariant) ---
# The helper's DEST_SPEC table and the handler's FILE_MAP must agree on the
# managed dest set (minus the root-managed sudoers). Assert equal cardinality so
# adding a FILE_MAP entry without updating DEST_SPEC fails loudly here.
test_dest_spec_filemap_lockstep() {
  echo "TEST: DEST_SPEC count == FILE_MAP count (cross-file lockstep)"
  local filemap_count dest_spec_count
  # FILE_MAP entries look like: "ENV_VAR|/dest/path|mode|owner"
  filemap_count=$(grep -cE '^\s*"[A-Z_]+_B64\|/' "$HANDLER")
  # DEST_SPEC keys look like: ["/dest/path"]="mode owner"
  dest_spec_count=$(grep -cE '^\s*\["/' "$HELPER")
  assert_eq "FILE_MAP has 12 managed dests" "12" "$filemap_count"
  assert_eq "DEST_SPEC has 12 managed dests" "12" "$dest_spec_count"
  assert_eq "DEST_SPEC and FILE_MAP cardinality match" "$filemap_count" "$dest_spec_count"
  # The sudoers dest must be in NEITHER (root-managed).
  if grep -q '/etc/sudoers.d/deploy-inngest-bootstrap' "$HELPER"; then
    echo "  FAIL: sudoers dest must not appear in the helper allowlist"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: sudoers dest absent from helper allowlist"
    PASS=$((PASS + 1))
  fi
}

# --- Run all tests ---
echo "=== infra-config-install.sh test suite ==="
test_install_allowlisted
test_reject_nonallowlisted_dest
test_reject_traversal
test_reject_dest_symlink
test_all_managed_dests_accepted
test_reject_sudoers_dest
test_reject_setuid_mode
test_reject_owner_seize
test_usage_error
test_dest_spec_filemap_lockstep
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
