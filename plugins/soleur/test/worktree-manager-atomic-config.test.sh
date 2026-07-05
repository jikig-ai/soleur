#!/usr/bin/env bash

# Tests for worktree-manager.sh atomic_git_config() — the targeted fix for the
# Concierge config.lock worktree-creation wedge (#5912).
#
# Root cause (confirmed forensic): `.git/config.lock` in the Concierge sandbox is a
# NON-REGULAR path (a masked character device), an artifact of the sandbox
# filesystem/masking layer. git's config writer creates `config.lock` via
# open(O_CREAT|O_EXCL); the pre-existing device node makes EVERY `git config` write
# fail EEXIST ("could not lock config file … : File exists"), permanently wedging
# worktree creation with no in-sandbox self-heal.
#
# atomic_git_config composes:
#   FR2 read-first idempotence — a `key value` set whose value already matches, or an
#       `--unset` of an already-absent key, is a zero-write fast path (reads never
#       take the lock, so this works even while wedged).
#   FR3 gated lockless writer — clean/absent lock -> native `git config` (preserves
#       git's flock serialization for healthy concurrent writers). Wedged
#       (non-regular) lock -> redirect git's own writer to a same-dir temp copy
#       (cp -p, preserving perms/owner) + atomic `mv -f` rename over the target; git
#       creates <temp>.lock, a CLEAN path distinct from the masked <file>.lock, so the
#       write never touches the wedge.
#   TR3 symlink-config guard — when <file> itself is a symlink, resolve to its target
#       so the rename preserves the indirection instead of clobbering the link.
#
# The wedged-fallback branch is exercised without root using a DIRECTORY at
# config.lock (also non-regular -> the identical O_CREAT|O_EXCL EEXIST failure), plus
# a symlink; a real character-device fixture is attempted via `mknod` when the
# environment permits (root/CAP_MKNOD), else skipped. Fixtures synthesized per
# cq-test-fixtures-synthesized-only.
#
# Run: bash plugins/soleur/test/worktree-manager-atomic-config.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

echo "=== worktree-manager.sh atomic_git_config() lockless-writer fix ==="
echo ""

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

# Source the script inside a valid work-tree so the repo-readiness gate at the top
# passes (it exit-3s in a repo-less dir). The BASH_SOURCE==$0 guard means main()
# does NOT run on source.
WORKSPACE="$TMP/workspace"
git init -q -b main "$WORKSPACE"
git -C "$WORKSPACE" config user.email "test@test.local"
git -C "$WORKSPACE" config user.name "Test"
cd "$WORKSPACE"
# shellcheck source=/dev/null
source "$SCRIPT"

new_gitdir() { mktemp -d "$TMP/gitdir.XXXXXX"; }

# seed_config <dir> — write a minimal shared config with a sentinel section.
seed_config() { printf '[core]\n\tsentinel = seed\n' > "$1/config"; }

# get_val <dir> <key> — read a config value (never takes the lock).
get_val() { git config --file "$1/config" --get "$2" 2>/dev/null || echo "__ABSENT__"; }

# no_temp_leftovers <dir> — assert no atomic_git_config temp artifact remains.
no_temp_leftovers() {
  local d="$1" label="$2"
  if compgen -G "$d/config*.soleur-tmp.*" >/dev/null 2>&1; then
    echo "  FAIL: $label — leftover soleur-tmp artifact in $d"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label — no soleur-tmp leftovers"; PASS=$((PASS + 1))
  fi
}

# run_agc <args...> — invoke atomic_git_config set-e-safely; sets AGC_RC.
run_agc() {
  set +e
  atomic_git_config "$@" >"$TMP/agc.out" 2>"$TMP/agc.err"
  AGC_RC=$?
  set -e
}

# ---------------------------------------------------------------------------
echo "Test 1: native path on a CLEAN (no lock) config -> value written, rc 0, no temp"
D=$(new_gitdir); seed_config "$D"
run_agc "$D/config" section.alpha one
assert_eq "0" "$AGC_RC" "native write returns 0"
assert_eq "one" "$(get_val "$D" section.alpha)" "native write set the value"
no_temp_leftovers "$D" "native path"

# ---------------------------------------------------------------------------
echo "Test 2: FR2 read-first — value already present is a zero-write skip (rc 0)"
# Definitive gate: make the parent dir READ-ONLY so ANY write (native or lockless)
# would fail. read-first must skip the write entirely and still return 0.
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — DAC bypass means read-only dir cannot force a write failure"
  SKIPPED=$((SKIPPED + 1))
else
  D=$(new_gitdir); seed_config "$D"
  git config --file "$D/config" section.beta already   # establish current value
  chmod a-w "$D"                                        # any write now fails
  run_agc "$D/config" section.beta already              # SAME value -> must skip write
  chmod u+w "$D"
  assert_eq "0" "$AGC_RC" "read-first skipped the write (rc 0 despite read-only dir)"
  assert_eq "already" "$(get_val "$D" section.beta)" "value unchanged after skip"
fi

# ---------------------------------------------------------------------------
echo "Test 3: FR2 read-first — --unset of an ALREADY-ABSENT key is a zero-write skip"
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — read-only dir cannot force a write failure"
  SKIPPED=$((SKIPPED + 1))
else
  D=$(new_gitdir); seed_config "$D"
  chmod a-w "$D"
  run_agc "$D/config" --unset section.ghost             # key absent -> skip
  chmod u+w "$D"
  assert_eq "0" "$AGC_RC" "unset-absent skipped the write (rc 0 despite read-only dir)"
fi

# ---------------------------------------------------------------------------
echo "Test 4: FR3 gated LOCKLESS on a wedged DIRECTORY lock -> value written, rc 0"
# Fixture non-vacuity: prove a NATIVE git config write genuinely fails here first.
D=$(new_gitdir); seed_config "$D"
git config --file "$D/config" section.gamma old
mkdir "$D/config.lock"                                  # non-regular -> wedged
set +e; git config --file "$D/config" section.probe x >/dev/null 2>&1; NATIVE_RC=$?; set -e
if (( NATIVE_RC != 0 )); then
  echo "  PASS: fixture is non-vacuous — native git config fails against the wedged dir lock"; PASS=$((PASS + 1))
else
  echo "  FAIL: fixture vacuous — native git config unexpectedly succeeded"; FAIL=$((FAIL + 1))
fi
run_agc "$D/config" section.gamma new                   # must route lockless
assert_eq "0" "$AGC_RC" "lockless write returns 0 on wedged dir lock"
assert_eq "new" "$(get_val "$D" section.gamma)" "lockless write updated the value"
assert_eq "true" "$([[ -d "$D/config.lock" ]] && echo true || echo false)" "wedged dir lock left untouched"
no_temp_leftovers "$D" "lockless dir-lock path"

# ---------------------------------------------------------------------------
echo "Test 5: FR3 gated LOCKLESS on a wedged SYMLINK lock -> value written, rc 0"
D=$(new_gitdir); seed_config "$D"
ln -s /nonexistent-target "$D/config.lock"             # symlink -> non-regular -> wedged
run_agc "$D/config" section.delta v5
assert_eq "0" "$AGC_RC" "lockless write returns 0 on wedged symlink lock"
assert_eq "v5" "$(get_val "$D" section.delta)" "lockless write updated the value"
assert_eq "true" "$([[ -L "$D/config.lock" ]] && echo true || echo false)" "wedged symlink lock left untouched"

# ---------------------------------------------------------------------------
echo "Test 6: TR3 symlink-CONFIG guard — rename preserves the indirection"
D=$(new_gitdir)
printf '[core]\n\tsentinel = real\n' > "$D/config.real"
ln -s config.real "$D/config"                          # config IS a symlink
mkdir "$D/config.lock"                                  # force lockless path
run_agc "$D/config" section.epsilon v6
assert_eq "0" "$AGC_RC" "lockless write through symlinked config returns 0"
assert_eq "true" "$([[ -L "$D/config" ]] && echo true || echo false)" "config still a symlink (not clobbered)"
assert_eq "v6" "$(git config --file "$D/config.real" --get section.epsilon 2>/dev/null || echo MISS)" "value landed in the symlink TARGET"

# ---------------------------------------------------------------------------
echo "Test 7: LOCKLESS --unset removes a key on a wedged lock (rc 0)"
D=$(new_gitdir); seed_config "$D"
git config --file "$D/config" section.doomed byebye
mkdir "$D/config.lock"                                  # wedged
run_agc "$D/config" --unset section.doomed
assert_eq "0" "$AGC_RC" "lockless unset returns 0"
assert_eq "__ABSENT__" "$(get_val "$D" section.doomed)" "key removed via lockless unset"

# ---------------------------------------------------------------------------
echo "Test 8: TR2 — lockless write preserves the config file's permissions (cp -p)"
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — perm semantics differ under DAC bypass"
  SKIPPED=$((SKIPPED + 1))
else
  D=$(new_gitdir); seed_config "$D"
  chmod 0640 "$D/config"
  mkdir "$D/config.lock"                                # force lockless
  run_agc "$D/config" section.perm p8
  assert_eq "0" "$AGC_RC" "lockless write returns 0"
  assert_eq "640" "$(stat -c '%a' "$D/config")" "config mode preserved (cp -p) after atomic rename"
fi

# ---------------------------------------------------------------------------
echo "Test 9: TR4 high-fidelity — real CHARACTER-DEVICE lock when mknod is permitted"
D=$(new_gitdir); seed_config "$D"
if mknod "$D/config.lock" c 1 3 2>/dev/null; then      # /dev/null-class char device
  run_agc "$D/config" section.chardev v9
  assert_eq "0" "$AGC_RC" "lockless write returns 0 against a real char-device lock"
  assert_eq "v9" "$(get_val "$D" section.chardev)" "value written past the char-device wedge"
  assert_eq "true" "$([[ -c "$D/config.lock" ]] && echo true || echo false)" "char-device left untouched"
else
  echo "  SKIP: mknod not permitted (needs root/CAP_MKNOD) — dir+symlink fixtures cover the branch"
  SKIPPED=$((SKIPPED + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 10: GLOB masking (temp's OWN lock also masked) -> FAIL-CLOSED + distinct sentinel"
# Simulates the spec's BLOCKING ASSUMPTION being FALSE: the sandbox masks *.lock as a
# glob, so config.soleur-tmp.$$.lock is ALSO an unwritable non-regular path. The
# lockless writer must fail-closed (config untouched, rc!=0) and emit the distinct
# SOLEUR_GIT_LOCK_TEMP_WEDGED sentinel so a blind-surface session can tell glob-masking
# apart from the now-fixed single-path wedge. $$ here == atomic_git_config's $$ (a
# redirection is not a subshell), so the temp lock path is predictable.
D=$(new_gitdir); seed_config "$D"
ORIG_GLOB="$(cat "$D/config")"
mkdir "$D/config.lock"                                  # primary wedge -> routes lockless
mkdir "$D/config.soleur-tmp.$$.lock"                    # glob: temp's clean lock ALSO masked
run_agc "$D/config" section.glob v10
if (( AGC_RC != 0 )); then echo "  PASS: glob case fails CLOSED (rc!=0), not silently"; PASS=$((PASS + 1));
else echo "  FAIL: glob case must fail closed"; FAIL=$((FAIL + 1)); fi
assert_eq "$ORIG_GLOB" "$(cat "$D/config")" "shared config byte-identical (no partial mutation under glob)"
if grep -qF 'SOLEUR_GIT_LOCK_TEMP_WEDGED' "$TMP/agc.out"; then
  echo "  PASS: distinct SOLEUR_GIT_LOCK_TEMP_WEDGED sentinel emitted for glob diagnosis"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected SOLEUR_GIT_LOCK_TEMP_WEDGED sentinel on the temp-write-failure branch"; FAIL=$((FAIL + 1))
fi
if compgen -G "$D/config.soleur-tmp.*" >/dev/null 2>&1 && [[ -f "$D/config.soleur-tmp.$$" ]]; then
  echo "  FAIL: regular temp file orphaned after glob failure"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no regular temp file orphaned (only the pre-planted .lock dir remains)"; PASS=$((PASS + 1))
fi
rm -rf "$D/config.soleur-tmp.$$.lock"

# ---------------------------------------------------------------------------
echo "Test 11: lockless cp -p failure (unreadable target) -> rc!=0, temp cleaned up"
# Exercises the cp-failure error arm and its cleanup (regression guard: the branch must
# rm the partial temp before returning, matching every sibling error path).
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — DAC bypass means an unreadable target cannot force cp failure"
  SKIPPED=$((SKIPPED + 1))
else
  D=$(new_gitdir); seed_config "$D"
  git config --file "$D/config" section.keep v11         # give it content
  mkdir "$D/config.lock"                                 # wedged -> lockless
  chmod 000 "$D/config"                                  # cp -p read fails (EACCES)
  run_agc "$D/config" section.new nope
  chmod 0644 "$D/config"                                 # restore for asserts/cleanup
  if (( AGC_RC != 0 )); then echo "  PASS: cp-failure returns non-zero"; PASS=$((PASS + 1));
  else echo "  FAIL: cp-failure must return non-zero"; FAIL=$((FAIL + 1)); fi
  no_temp_leftovers "$D" "cp-failure cleanup"
  assert_eq "v11" "$(get_val "$D" section.keep)" "original config content intact after cp failure"
fi

# ---------------------------------------------------------------------------
echo "Test 12: #4826 ensure_bare_config is a NO-OP on a normal (non-bare) repo"
# The #4826 regression: ensure_bare_config unconditionally enabled extensions.worktreeConfig,
# which on a normal Concierge clone forces git to read the sandbox-masked (unreadable)
# .git/config.worktree and fatals EVERY git command. Fix: a `.git` DIRECTORY ⇒ non-bare ⇒
# the whole bare-accommodation is skipped, so `git worktree add` runs natively with NO
# shared-config surgery (no worktreeConfig, no config.lock write, no masked-file read).
WS12=$(mktemp -d "$TMP/nonbare.XXXXXX"); git init -q -b main "$WS12" >/dev/null 2>&1
_SAVED_GIT_ROOT="$GIT_ROOT"
GIT_ROOT="$WS12"
set +e; ensure_bare_config >"$TMP/ebc.out" 2>&1; EBC_RC=$?; set -e
GIT_ROOT="$_SAVED_GIT_ROOT"
assert_eq "0" "$EBC_RC" "ensure_bare_config returns 0 (no-op) on a non-bare repo"
assert_eq "__ABSENT__" "$(git config --file "$WS12/.git/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "extensions.worktreeConfig NOT set on the non-bare repo (the #4826 regression is gone)"
if git config --file "$WS12/.git/config" --get core.repositoryformatversion 2>/dev/null | grep -qx 1; then
  echo "  FAIL: repositoryformatversion bumped to 1 on a non-bare repo"; FAIL=$((FAIL + 1))
else
  echo "  PASS: repositoryformatversion left at plain-repo default on the non-bare repo"; PASS=$((PASS + 1))
fi

echo ""
print_results
