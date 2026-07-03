#!/usr/bin/env bash
# Tests for git-lock-chardevice-sweep.sh — the privileged, non-blind #5934
# substrate remediation (ADR-081). The live run needs root + a real device node,
# so these tests pin the SCOPE + BRANCH LOGIC via seams, exactly as the plan AC6
# requires: (i) removes a plain char-device lock, (ii) umounts-then-rms a
# bind-mounted node (rather than failing EBUSY), (iii) leaves a regular lock
# untouched, (iv) leaves index.lock untouched.
#
# The remediation logic (remediate_node) is decoupled from discovery
# (discover_targets owns the `-type c`/name filter) so the umount-then-rm branch
# is testable WITHOUT CAP_SYS_ADMIN via GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS + a mock
# `umount` on PATH. The real char-device cases (i) are additionally skip-guarded on
# mknod capability, mirroring worktree-manager-stale-lock-diag.test.sh's Test 4c.
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash apps/web-platform/infra/git-lock-chardevice-sweep.test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/git-lock-chardevice-sweep.sh"

PASS=0
FAIL=0
SKIPPED=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc — '$needle' not found"; FAIL=$((FAIL + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Mock `umount` on PATH: record each invocation to a log, then remove the target
# (simulating a successful unmount that frees the node for the subsequent rm). This
# lets the umount-then-rm ORDERING be asserted without a real mount.
MOCKBIN="$TMP/mockbin"
mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/umount" <<'EOF'
#!/usr/bin/env bash
# Records the umount call; ignores a leading -l flag. Does NOT remove the file —
# the sweep's own `rm -f` must do that, so the test proves rm runs AFTER umount.
log="${MOCK_UMOUNT_LOG:?}"
args=()
for a in "$@"; do [[ "$a" == "-l" ]] && continue; args+=("$a"); done
echo "umount ${args[*]}" >> "$log"
exit 0
EOF
chmod +x "$MOCKBIN/umount"
export MOCK_UMOUNT_LOG="$TMP/umount.log"
: > "$MOCK_UMOUNT_LOG"
export PATH="$MOCKBIN:$PATH"

echo "=== git-lock-chardevice-sweep.sh scope + branch logic ==="
echo ""

# Source the target (BASH_SOURCE guard prevents main() from running on source).
# shellcheck source=/dev/null
source "$TARGET"

# ---------------------------------------------------------------------------
echo "Test (iii)+(iv): discovery leaves a REGULAR config.lock and index.lock untouched"
WS="$TMP/workspaces"
mkdir -p "$WS/ws-a/.git"
printf 'real-writer\n' > "$WS/ws-a/.git/config.lock"       # REGULAR -> not -type c
printf 'live-index\n'  > "$WS/ws-a/.git/index.lock"        # REGULAR + wrong name
GIT_LOCK_SWEEP_ROOT="$WS"
targets="$(discover_targets | tr '\0' '\n')"
if [[ -z "$targets" ]]; then
  echo "  PASS: discover_targets returns nothing for regular locks"; PASS=$((PASS + 1))
else
  echo "  FAIL: discover_targets matched a non-char-device path"; echo "    got: $targets"; FAIL=$((FAIL + 1))
fi
assert_eq "regular config.lock preserved" "true" "$([[ -f "$WS/ws-a/.git/config.lock" ]] && echo true || echo false)"
assert_eq "index.lock preserved" "true" "$([[ -f "$WS/ws-a/.git/index.lock" ]] && echo true || echo false)"

# ---------------------------------------------------------------------------
echo "Test (ii): bind-mounted node -> umount BEFORE rm (branch=umount-then-rm)"
# Use a regular-file stand-in + FORCE_MOUNTPOINTS seam so the mountpoint branch is
# exercised without CAP_SYS_ADMIN. The mock umount records the call but does NOT
# delete; the sweep's own rm must remove the file AFTER umount — proving ordering.
NODE="$TMP/bound-node.lock"
printf 'stand-in\n' > "$NODE"
: > "$MOCK_UMOUNT_LOG"
# shellcheck disable=SC2034  # consumed by the sourced remediate_node/is_mountpoint (shellcheck cannot trace through `source`); the passing test proves the read
GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS="$NODE"
set +e
OUT="$(remediate_node "$NODE" 2>&1)"; RC=$?
set -e
unset GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS
assert_eq "remediate_node returns 0 on bind-mounted node" "0" "$RC"
assert_contains "branch=umount-then-rm marker emitted" "$OUT" "branch=umount-then-rm"
assert_contains "SOLEUR_CHARDEV_SWEEP_REMOVED emitted" "$OUT" "SOLEUR_CHARDEV_SWEEP_REMOVED"
assert_contains "umount was invoked on the node" "$(cat "$MOCK_UMOUNT_LOG")" "umount $NODE"
assert_eq "node removed AFTER umount (rm ran)" "false" "$([[ -e "$NODE" ]] && echo true || echo false)"

# ---------------------------------------------------------------------------
echo "Test (ii-fail): umount failure -> LOUD FAILED marker, rc!=0, node NOT rm'd"
# Swap in a failing umount to prove the sweep does NOT silently rm a still-mounted
# node (that would 'succeed' while the wedge persists).
cat > "$MOCKBIN/umount" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCKBIN/umount"
NODE2="$TMP/busy-node.lock"
printf 'busy\n' > "$NODE2"
# shellcheck disable=SC2034  # consumed by the sourced remediate_node (see above)
GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS="$NODE2"
set +e
OUT2="$(remediate_node "$NODE2" 2>&1)"; RC2=$?
set -e
unset GIT_LOCK_SWEEP_FORCE_MOUNTPOINTS
if (( RC2 != 0 )); then echo "  PASS: remediate_node returns non-zero on umount failure"; PASS=$((PASS + 1));
else echo "  FAIL: remediate_node must fail when umount fails"; FAIL=$((FAIL + 1)); fi
assert_contains "FAILED marker with reason=umount-failed" "$OUT2" "reason=umount-failed"
assert_eq "node NOT rm'd when still mounted" "true" "$([[ -e "$NODE2" ]] && echo true || echo false)"
# Restore the succeeding mock for any later cases.
cat > "$MOCKBIN/umount" <<'EOF'
#!/usr/bin/env bash
log="${MOCK_UMOUNT_LOG:?}"; args=()
for a in "$@"; do [[ "$a" == "-l" ]] && continue; args+=("$a"); done
echo "umount ${args[*]}" >> "$log"; exit 0
EOF
chmod +x "$MOCKBIN/umount"

# ---------------------------------------------------------------------------
echo "Test (i): PLAIN char-device lock -> branch=rm, removed (needs CAP_MKNOD)"
WS2="$TMP/workspaces2"
mkdir -p "$WS2/ws-b/.git"
if mknod "$WS2/ws-b/.git/config.lock" c 1 3 2>/dev/null; then
  GIT_LOCK_SWEEP_ROOT="$WS2"
  # End-to-end via main(): discovery finds the node, remediate_node clears it.
  set +e
  MAIN_OUT="$(GIT_LOCK_SWEEP_STATE="$TMP/state.json" main 2>&1)"; MAIN_RC=$?
  set -e
  assert_eq "main returns 0 after clearing a plain char-device lock" "0" "$MAIN_RC"
  assert_contains "branch=rm marker for plain inode" "$MAIN_OUT" "branch=rm"
  assert_contains "REMOVED marker emitted" "$MAIN_OUT" "SOLEUR_CHARDEV_SWEEP_REMOVED"
  assert_contains "rdev discriminator on marker (1:3 for /dev/null-major:minor)" "$MAIN_OUT" "rdev=1:3"
  assert_eq "char-device lock removed" "false" "$([[ -e "$WS2/ws-b/.git/config.lock" ]] && echo true || echo false)"
  assert_contains "state file records removed=1" "$(cat "$TMP/state.json" 2>/dev/null)" "\"removed\":1"
else
  echo "  SKIP: mknod denied (no CAP_MKNOD) — plain char-device case needs a privileged runner"
  SKIPPED=$((SKIPPED + 1))
fi

# ---------------------------------------------------------------------------
echo "Test (idempotent): main over a CLEAN root -> no-op, rc 0, removed=0"
WS3="$TMP/workspaces3"
mkdir -p "$WS3/ws-c/.git"
GIT_LOCK_SWEEP_ROOT="$WS3"
set +e
CLEAN_OUT="$(GIT_LOCK_SWEEP_STATE="$TMP/state-clean.json" main 2>&1)"; CLEAN_RC=$?
set -e
assert_eq "main is a no-op on a clean root (rc 0)" "0" "$CLEAN_RC"
assert_contains "DONE marker reports removed=0" "$CLEAN_OUT" "removed=0"

# ---------------------------------------------------------------------------
echo "Test (absent root): missing ROOT -> rc 0, no crash"
GIT_LOCK_SWEEP_ROOT="$TMP/does-not-exist"
set +e
( GIT_LOCK_SWEEP_STATE="$TMP/state-absent.json" main >/dev/null 2>&1 ); ABS_RC=$?
set -e
assert_eq "main tolerates an absent ROOT" "0" "$ABS_RC"

# ---------------------------------------------------------------------------
echo "Test (TOCTOU re-assert): a non-char-device / out-of-root target is SKIPPED, not rm'd"
# remediate_node re-verifies the node is still a char device AND under sweep_root
# before any destructive op (defense-in-depth against a live-volume ancestor swap).
# A regular-file path that is NOT in FORCE_MOUNTPOINTS must be skipped loudly.
GIT_LOCK_SWEEP_ROOT="$TMP/ws-root"; mkdir -p "$GIT_LOCK_SWEEP_ROOT"
STRAY="$TMP/outside/config.lock"; mkdir -p "$(dirname "$STRAY")"; printf 'x\n' > "$STRAY"
set +e
TOCTOU_OUT="$(remediate_node "$STRAY" 2>&1)"; TOCTOU_RC=$?
set -e
assert_eq "remediate_node returns 0 (skip, not fail) on a non-target" "0" "$TOCTOU_RC"
assert_contains "SKIPPED marker emitted for a non-char-device" "$TOCTOU_OUT" "SOLEUR_CHARDEV_SWEEP_SKIPPED"
assert_eq "stray file NOT removed by the re-assert guard" "true" "$([[ -e "$STRAY" ]] && echo true || echo false)"

# ---------------------------------------------------------------------------
echo "Test (deploy wiring): ci-deploy.sh invokes the sweep, guarded + bounded + best-effort"
CID="$SCRIPT_DIR/ci-deploy.sh"
assert_contains "ci-deploy.sh invokes the installed sweep" "$(cat "$CID")" "/usr/local/bin/git-lock-chardevice-sweep.sh"
assert_contains "invocation is -x guarded (inert until delivered)" "$(cat "$CID")" "[[ -x /usr/local/bin/git-lock-chardevice-sweep.sh ]]"
assert_contains "invocation is wall-clock bounded (no fleet-wide deploy hang)" "$(cat "$CID")" "timeout"
assert_contains "invocation is best-effort (never blocks a deploy)" "$(cat "$CID")" "git-lock-chardevice-sweep.sh || true"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Skipped: $SKIPPED"
if (( FAIL == 0 )); then
  echo "ALL EXECUTED TESTS PASSED ($SKIPPED skipped)"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
