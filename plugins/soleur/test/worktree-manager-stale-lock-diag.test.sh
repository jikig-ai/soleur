#!/usr/bin/env bash

# Tests for worktree-manager.sh sweep_stale_git_locks() structured blind-surface
# diagnostics + ensure_bare_config() fail-loud contract.
#
# The Concierge agent-sandbox is a BLIND execution surface (no ls/stat/findmnt),
# so the deployed sweep IS the only diagnostic instrument. These tests pin:
#   - a grep-able SOLEUR_GIT_LOCK_DIAG line on STDOUT for any PRESENT lock,
#     carrying type/owner/perms/mtime/age/mount;
#   - regular-file-only removal with errno capture on failure;
#   - non-regular locks (dir/symlink/mount) DETECTED + REPORTED loudly
#     (SOLEUR_GIT_LOCK_UNREMOVABLE reason=non-regular-lock), never auto-removed;
#   - the sweep returns non-zero iff a config-write lock remained unremovable;
#   - ensure_bare_config() refuses the shared-config writes on an unremovable
#     lock (no doomed EEXIST write) and its callers are set -e-safe (create paths
#     exit clean; cleanup_merged_worktrees CONTINUES).
#
# Fixtures synthesized per cq-test-fixtures-synthesized-only.
# Run: bash plugins/soleur/test/worktree-manager-stale-lock-diag.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh sweep_stale_git_locks() blind-surface diagnostics ==="
echo ""

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Source the script inside a valid work-tree so the repo-readiness gate at
#     the top passes (it exit-3s in a repo-less dir). The BASH_SOURCE==$0 guard
#     means main() does NOT run on source. ---
WORKSPACE="$TMP/workspace"
git init -q -b main "$WORKSPACE"
git -C "$WORKSPACE" config user.email "test@test.local"
git -C "$WORKSPACE" config user.name "Test"
cd "$WORKSPACE"
# shellcheck source=/dev/null
source "$SCRIPT"

OLD_MTIME='2020-01-01T00:00:00'   # unambiguously stale vs any sane threshold

# run_sweep <git_dir> [threshold] -> sets SW_OUT (stdout), SW_ERR (stderr), SW_RC
run_sweep() {
  local d="$1" thr="${2:-60}"
  set +e
  SW_OUT="$(sweep_stale_git_locks "$d" "$thr" 2>"$TMP/sweep.err")"
  SW_RC=$?
  set -e
  SW_ERR="$(cat "$TMP/sweep.err")"
}

new_lockdir() { local d; d="$(mktemp -d "$TMP/gitdir.XXXXXX")"; echo "$d"; }

# ---------------------------------------------------------------------------
echo "Test 1: present + regular + stale -> DIAG type=regular, removed, Swept 1, rc 0"
D=$(new_lockdir)
printf 'lockpid\n' > "$D/config.lock"
touch -d "$OLD_MTIME" "$D/config.lock"
run_sweep "$D" 60
assert_contains "$SW_OUT" "SOLEUR_GIT_LOCK_DIAG" "DIAG line emitted"
assert_contains "$SW_OUT" "type=regular" "type=regular in DIAG"
assert_contains "$SW_OUT" "Swept 1" "Swept 1 reported"
assert_file_not_exists "$D/config.lock" "stale regular lock removed"
assert_eq "0" "$SW_RC" "sweep returns 0 on clean removal"

# ---------------------------------------------------------------------------
echo "Test 2: present + regular + fresh -> DIAG emitted, preserved, rc 0, no Swept"
D=$(new_lockdir)
printf 'fresh\n' > "$D/config.lock"   # mtime = now, age ~0
run_sweep "$D" 60
assert_contains "$SW_OUT" "SOLEUR_GIT_LOCK_DIAG" "DIAG emitted for present-fresh lock"
assert_contains "$SW_OUT" "type=regular" "fresh lock typed regular"
assert_file_exists "$D/config.lock" "fresh lock preserved (in-flight-writer safety)"
assert_eq "0" "$SW_RC" "fresh lock -> rc 0"
if [[ "$SW_OUT" == *"Swept"* ]]; then
  echo "  FAIL: fresh lock must not report Swept"; FAIL=$((FAIL + 1))
else
  echo "  PASS: fresh lock not swept"; PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 3: future-dated lock (mtime now+3600) -> preserved (clock-skew), rc 0"
D=$(new_lockdir)
printf 'future\n' > "$D/config.lock"
touch -d "@$(( $(date +%s) + 3600 ))" "$D/config.lock"
run_sweep "$D" 60
assert_file_exists "$D/config.lock" "future-dated lock preserved"
assert_eq "0" "$SW_RC" "future-dated lock -> rc 0 (clock-skew guard)"

# ---------------------------------------------------------------------------
echo "Test 4: directory lock -> type=dir, UNREMOVABLE non-regular, preserved, rc!=0"
D=$(new_lockdir)
mkdir "$D/config.lock"
touch -d "$OLD_MTIME" "$D/config.lock"
run_sweep "$D" 60
assert_contains "$SW_OUT" "type=dir" "directory lock typed dir"
assert_contains "$SW_OUT" "SOLEUR_GIT_LOCK_UNREMOVABLE" "UNREMOVABLE emitted for dir lock"
assert_contains "$SW_OUT" "reason=non-regular-lock" "dir lock reason=non-regular-lock"
assert_eq "true" "$([[ -d "$D/config.lock" ]] && echo true || echo false)" "dir lock NOT removed"
if (( SW_RC != 0 )); then echo "  PASS: sweep returns non-zero on dir lock"; PASS=$((PASS + 1));
else echo "  FAIL: sweep must return non-zero on dir lock"; FAIL=$((FAIL + 1)); fi

# ---------------------------------------------------------------------------
echo "Test 5: symlink lock -> type=symlink, UNREMOVABLE, link+target preserved, rc!=0"
D=$(new_lockdir)
printf 'target\n' > "$D/target"
touch -d "$OLD_MTIME" "$D/target"
ln -s target "$D/config.lock"
touch -h -d "$OLD_MTIME" "$D/config.lock" 2>/dev/null || true
run_sweep "$D" 60
assert_contains "$SW_OUT" "type=symlink" "symlink lock typed symlink"
assert_contains "$SW_OUT" "reason=non-regular-lock" "symlink lock reason=non-regular-lock"
assert_eq "true" "$([[ -L "$D/config.lock" ]] && echo true || echo false)" "symlink NOT removed"
assert_file_exists "$D/target" "symlink target preserved"
if (( SW_RC != 0 )); then echo "  PASS: sweep returns non-zero on symlink lock"; PASS=$((PASS + 1));
else echo "  FAIL: sweep must return non-zero on symlink lock"; FAIL=$((FAIL + 1)); fi

# ---------------------------------------------------------------------------
echo "Test 6: regular stale, rm fails (read-only parent) -> UNREMOVABLE errno, rc!=0, loud line present"
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — DAC bypass means read-only parent cannot force rm failure"
  SKIPPED=$((SKIPPED + 1))
else
  D=$(new_lockdir)
  printf 'stuck\n' > "$D/config.lock"
  touch -d "$OLD_MTIME" "$D/config.lock"
  chmod a-w "$D"                       # read-only parent -> rm EACCES/EPERM
  run_sweep "$D" 60
  chmod u+w "$D"                       # restore so cleanup can rm -rf
  assert_contains "$SW_OUT" "SOLEUR_GIT_LOCK_UNREMOVABLE" "UNREMOVABLE emitted on rm failure"
  if [[ "$SW_OUT" == *"errno=EACCES"* || "$SW_OUT" == *"errno=EPERM"* ]]; then
    echo "  PASS: errno label captured (EACCES/EPERM)"; PASS=$((PASS + 1))
  else
    echo "  FAIL: expected errno=EACCES or errno=EPERM"; echo "    got: $SW_OUT"; FAIL=$((FAIL + 1))
  fi
  assert_contains "$SW_OUT" "reason=rm-failed" "reason=rm-failed on rm failure"
  if (( SW_RC != 0 )); then echo "  PASS: sweep returns non-zero on rm failure"; PASS=$((PASS + 1));
  else echo "  FAIL: sweep must return non-zero on rm failure"; FAIL=$((FAIL + 1)); fi
fi

# ---------------------------------------------------------------------------
echo "Test 7: sentinel tokens on STDOUT with no ANSI color codes"
D=$(new_lockdir)
mkdir "$D/config.lock"
touch -d "$OLD_MTIME" "$D/config.lock"
run_sweep "$D" 60
if printf '%s' "$SW_OUT" | grep -qF 'SOLEUR_GIT_LOCK_'; then
  echo "  PASS: SOLEUR_GIT_LOCK_ tokens present on stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: SOLEUR_GIT_LOCK_ tokens missing from stdout"; FAIL=$((FAIL + 1))
fi
# The DIAG/UNREMOVABLE lines must be free of ESC (\033) color codes.
diag_lines="$(printf '%s\n' "$SW_OUT" | grep 'SOLEUR_GIT_LOCK_' || true)"
if printf '%s' "$diag_lines" | grep -q $'\033'; then
  echo "  FAIL: sentinel line carries ANSI color codes (breaks grep)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: sentinel lines are plain (no ANSI)"; PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 8: ensure_bare_config() on unremovable lock -> no config write, rc!=0"
BARE=$(new_lockdir)                    # acts as GIT_ROOT (no .git subdir -> git_dir=GIT_ROOT)
printf '[core]\n\tsentinel = untouched\n' > "$BARE/config"
CONFIG_BEFORE="$(cat "$BARE/config")"
mkdir "$BARE/config.lock"              # non-regular -> unremovable
touch -d "$OLD_MTIME" "$BARE/config.lock"
GIT_ROOT="$BARE"
set +e
EBC_OUT="$(ensure_bare_config 2>"$TMP/ebc.err")"
EBC_RC=$?
set -e
if (( EBC_RC != 0 )); then echo "  PASS: ensure_bare_config returns non-zero on wedge"; PASS=$((PASS + 1));
else echo "  FAIL: ensure_bare_config must return non-zero on wedge"; FAIL=$((FAIL + 1)); fi
assert_eq "$CONFIG_BEFORE" "$(cat "$BARE/config")" "shared config NOT mutated (no doomed write)"
assert_contains "$EBC_OUT" "SOLEUR_GIT_LOCK_UNREMOVABLE" "sweep UNREMOVABLE surfaced via ensure_bare_config stdout"

# ---------------------------------------------------------------------------
echo "Test 9: cleanup_merged_worktrees-style caller CONTINUES past a wedged ensure_bare_config"
# Drive the real dispatch: a wedged local repo (no remote -> fetch fails gracefully).
# With the guard, ensure_bare_config's non-zero return is caught and the run
# continues to the fetch step which returns 0. Without the guard, set -e aborts
# the whole process (non-zero exit). We assert exit 0.
REPO="$TMP/cleanup-repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.email "test@test.local"
git -C "$REPO" config user.name "Test"
mkdir "$REPO/.git/config.lock"                          # non-regular -> unremovable
touch -d "$OLD_MTIME" "$REPO/.git/config.lock"
set +e
( cd "$REPO" && bash "$SCRIPT" cleanup-merged ) >"$TMP/cleanup.out" 2>"$TMP/cleanup.err"
CLEAN_RC=$?
set -e
if (( CLEAN_RC == 0 )); then
  echo "  PASS: cleanup-merged continued past wedge (exit 0, no set -e abort)"; PASS=$((PASS + 1))
else
  echo "  FAIL: cleanup-merged aborted on wedge (exit $CLEAN_RC)"; sed 's/^/    /' "$TMP/cleanup.err"; FAIL=$((FAIL + 1))
fi
# The blind-surface sentinel must have surfaced on stdout during the run.
if grep -qF 'SOLEUR_GIT_LOCK_' "$TMP/cleanup.out"; then
  echo "  PASS: sentinel surfaced on cleanup-merged stdout"; PASS=$((PASS + 1))
else
  echo "  FAIL: sentinel missing from cleanup-merged stdout"; FAIL=$((FAIL + 1))
fi

echo ""
print_results
