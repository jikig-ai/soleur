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
echo "Test 12: #6184 ensure_bare_config is a NO-OP on a normal (non-bare) repo"
# The #6184 regression: ensure_bare_config unconditionally enabled extensions.worktreeConfig,
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
  "extensions.worktreeConfig NOT set on the non-bare repo (the #6184 regression is gone)"
if git config --file "$WS12/.git/config" --get core.repositoryformatversion 2>/dev/null | grep -qx 1; then
  echo "  FAIL: repositoryformatversion bumped to 1 on a non-bare repo"; FAIL=$((FAIL + 1))
else
  echo "  PASS: repositoryformatversion left at plain-repo default on the non-bare repo"; PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 13: #6184 round-5 — guard STILL fires on a normal repo when GIT_ROOT is EMPTY"
# The round-4 guard was `[[ -d "\$GIT_ROOT/.git" ]]` alone. In the live sandbox GIT_ROOT
# resolved EMPTY (git rev-parse --show-toplevel returned nothing under the masked config),
# so the check became `[[ -d "/.git" ]]` → false → the guard did NOT fire and the surgery
# wedged on the masked config.lock (user's cleanup-merged, 2026-07-06). The hardened guard
# adds git's authoritative `--is-bare-repository` with a `${GIT_ROOT:-.}` CWD fallback, so a
# normal clone skips even when GIT_ROOT is empty. Simulate it: cd INTO the repo, blank
# GIT_ROOT, plant a masked lock, and assert NO wedge + NO config write.
WS13=$(mktemp -d "$TMP/emptyroot.XXXXXX"); git init -q -b main "$WS13" >/dev/null 2>&1
mkdir "$WS13/.git/config.lock"   # non-regular (masked) lock — a write attempt would wedge
_SAVED_GIT_ROOT="$GIT_ROOT"; _SAVED_PWD="$PWD"
cd "$WS13"; GIT_ROOT=""          # the exact sandbox failure: empty GIT_ROOT, CWD is the repo
set +e; ensure_bare_config >"$TMP/ebc13.out" 2>&1; EBC13_RC=$?; set -e
GIT_ROOT="$_SAVED_GIT_ROOT"; cd "$_SAVED_PWD"
assert_eq "0" "$EBC13_RC" "ensure_bare_config returns 0 with empty GIT_ROOT (git fallback fires)"
if grep -qE "mv:|worktree wedge|config.soleur-tmp" "$TMP/ebc13.out"; then
  echo "  FAIL: WEDGED on empty GIT_ROOT — the round-4 regression is NOT fixed"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no config-write wedge on empty GIT_ROOT (hardened guard held)"; PASS=$((PASS + 1))
fi
assert_eq "__ABSENT__" "$(git config --file "$WS13/.git/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "worktreeConfig NOT set with empty GIT_ROOT (no surgery ran)"
rm -rf "$WS13/.git/config.lock"

# ---------------------------------------------------------------------------
# T14–T17 — the #6184 identity-authority inversion (non-bare Concierge wedge).
#
# ensure_worktree_identity was written for the bare CLI dev repo (bare repo carries a
# bot LOCAL, operator's --GLOBAL is the human → force global over local). On the
# non-bare Concierge workspace that topology is INVERTED: the host seeds the shared
# config with the per-workspace OWNER as the LOCAL identity, while the sandbox image
# bakes a github-actions[bot] --GLOBAL. The old "force global over local" logic tried
# to overwrite the correct owner via a raw `git config --local` write → EEXIST on the
# masked config.lock → RC=255 wedge (and, had it "succeeded", it would have
# misattributed the operator's commits to the bot). The fix RESPECTS a present local
# identity and only sets from global when local is ABSENT (via atomic_git_config).
# Fixtures synthesized only (cq-test-fixtures-synthesized-only); GIT_CONFIG_GLOBAL
# points every "global" write at an isolated file so the operator's real ~/.gitconfig
# is never touched.
# ---------------------------------------------------------------------------
echo "Test 14: #6184 PRIMARY — respect the host-seeded OWNER local identity (non-bare + masked lock)"
# Non-bare repo + linked worktree; seed the shared config with a DISTINCTIVE OWNER
# identity; set a DIFFERENT global (the sandbox bot); plant a non-regular
# .git/config.lock. This is the exact `local ≠ global` branch that fired the raw write
# at old :615-616. Proxy caveat: a DIRECTORY stand-in exercises the O_CREAT|O_EXCL
# EEXIST class (same failure git hits on the real rdev=1:3 chardevice); the true
# chardevice node is only reachable under mknod/root (see Test 9).
MAIN14=$(mktemp -d "$TMP/main14.XXXXXX"); git init -q -b main "$MAIN14" >/dev/null 2>&1
git -C "$MAIN14" config user.email "owner@workspace.example"   # host-seeded OWNER (shared/common)
git -C "$MAIN14" config user.name "Workspace Owner"
git -C "$MAIN14" commit -q --allow-empty -m init >/dev/null 2>&1
WT14="$MAIN14/wt"; git -C "$MAIN14" worktree add -q "$WT14" -b feat14 >/dev/null 2>&1
FAKE_GLOBAL14="$MAIN14/fake-global"                            # isolated — never the real ~/.gitconfig
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL14" git config --global user.email "gha-bot@users.noreply.github.com"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL14" git config --global user.name "github-actions[bot]"
mkdir "$MAIN14/.git/config.lock"                              # masked lock — a raw --local write would EEXIST
# Call under ACTIVE set -e (subshell) — the faithful create_worktree call context. The
# OLD "force global over local" code attempts the raw --local write here, EEXISTs on the
# masked lock, and set -e aborts with RC=255 (the live wedge). The fix returns 0.
set +e
( set -euo pipefail
  export GIT_CONFIG_GLOBAL="$FAKE_GLOBAL14"
  ensure_worktree_identity "$WT14"
) >"$TMP/ewi14.out" 2>&1
EWI14_RC=$?
set -e
assert_eq "0" "$EWI14_RC" "ensure_worktree_identity returns 0 under set -e (owner respected, no write attempted)"
assert_eq "owner@workspace.example" "$(git -C "$WT14" config --local --get user.email 2>/dev/null || echo MISS)" \
  "local user.email STILL the OWNER (not the sandbox bot global)"
assert_eq "Workspace Owner" "$(git -C "$WT14" config --local --get user.name 2>/dev/null || echo MISS)" \
  "local user.name STILL the OWNER (not the sandbox bot global)"
if grep -q "SOLEUR_GIT_LOCK_IDENTITY" "$TMP/ewi14.out"; then
  echo "  FAIL: respect-owner no-op must emit NO identity marker (drift/ wedge sentinels are for the set-from-global path only)"; FAIL=$((FAIL + 1))
else
  echo "  PASS: respect-owner no-op emitted no identity marker"; PASS=$((PASS + 1))
fi
rm -rf "$MAIN14/.git/config.lock"

# ---------------------------------------------------------------------------
echo "Test 15: #6184 set-when-absent — set from global via atomic_git_config lockless path (rc 0)"
# Non-bare + worktree with NO local identity + a global set + a non-regular config.lock.
# The identity must be set from global through the lockless writer and land in the
# RESOLVED common-dir config, plus emit the benign DIAG precondition marker.
MAIN15=$(mktemp -d "$TMP/main15.XXXXXX"); git init -q -b main "$MAIN15" >/dev/null 2>&1
git -C "$MAIN15" -c user.email=temp@t -c user.name=temp commit -q --allow-empty -m init >/dev/null 2>&1
WT15="$MAIN15/wt"; git -C "$MAIN15" worktree add -q "$WT15" -b feat15 >/dev/null 2>&1
git -C "$MAIN15" config --unset user.email 2>/dev/null || true   # ensure NO local identity in the shared config
git -C "$MAIN15" config --unset user.name 2>/dev/null || true
FAKE_GLOBAL15="$MAIN15/fake-global"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL15" git config --global user.email "global@dev.example"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL15" git config --global user.name "Global Dev"
mkdir "$MAIN15/.git/config.lock"                              # masked → atomic_git_config must route lockless
set +e
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL15" ensure_worktree_identity "$WT15" >"$TMP/ewi15.out" 2>&1
EWI15_RC=$?
set -e
assert_eq "0" "$EWI15_RC" "set-when-absent returns 0 via the lockless path"
assert_eq "global@dev.example" "$(git config --file "$MAIN15/.git/config" --get user.email 2>/dev/null || echo MISS)" \
  "identity set from global landed in the RESOLVED common-dir config"
assert_eq "Global Dev" "$(git config --file "$MAIN15/.git/config" --get user.name 2>/dev/null || echo MISS)" \
  "name set from global landed in the common-dir config"
if grep -qF "SOLEUR_GIT_LOCK_IDENTITY_DIAG source=ensure_worktree_identity reason=identity-drift-set-from-global" "$TMP/ewi15.out"; then
  echo "  PASS: benign DIAG precondition marker emitted on the set-from-global branch"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected the benign SOLEUR_GIT_LOCK_IDENTITY_DIAG precondition marker"; FAIL=$((FAIL + 1))
fi
assert_eq "true" "$([[ -d "$MAIN15/.git/config.lock" ]] && echo true || echo false)" "masked lock left untouched (lockless write)"
rm -rf "$MAIN15/.git/config.lock"

# ---------------------------------------------------------------------------
echo "Test 16: #6184 set -e ordering — drive the FAILURE through the wrapped call site under active set -e"
# A faithful reproduction of create_worktree's `if ! ensure_worktree_identity …; then
# <red>; exit 1; fi`. `if !`-wrapping DISARMS errexit inside the function body, so a
# bare failing write would silently fall through to success (vacuous green). Force
# common-dir-unresolved (a non-repo worktree_path) and assert: the WEDGED sentinel is
# PRINTED (survives errexit), the function returns 1, the caller emits its red error,
# and the wrapped block exits non-zero.
NONREPO16=$(mktemp -d "$TMP/nonrepo16.XXXXXX")               # not a git repo → --git-common-dir fails
FAKE_GLOBAL16="$NONREPO16/fake-global"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL16" git config --global user.email "g@dev.example"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL16" git config --global user.name "G Dev"
set +e
( set -euo pipefail
  export GIT_CONFIG_GLOBAL="$FAKE_GLOBAL16"
  if ! ensure_worktree_identity "$NONREPO16"; then
    echo "RED_ERROR: cannot create worktree — git identity could not be set"
    exit 1
  fi
  echo "UNEXPECTED_SUCCESS"
) >"$TMP/ewi16.out" 2>&1
EWI16_RC=$?
set -e
if (( EWI16_RC != 0 )); then echo "  PASS: wrapped call site exits non-zero (graceful, not a bare abort)"; PASS=$((PASS + 1));
else echo "  FAIL: wrapped call site must exit non-zero on the identity wedge"; FAIL=$((FAIL + 1)); fi
if grep -qF "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=common-dir-unresolved" "$TMP/ewi16.out"; then
  echo "  PASS: common-dir-unresolved sentinel PRINTED (survived the disarmed errexit)"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected the SOLEUR_GIT_LOCK_IDENTITY_WEDGED common-dir-unresolved sentinel"; FAIL=$((FAIL + 1))
fi
if grep -qF "RED_ERROR" "$TMP/ewi16.out"; then echo "  PASS: caller emitted its contextual red error"; PASS=$((PASS + 1));
else echo "  FAIL: caller red error missing"; FAIL=$((FAIL + 1)); fi
if grep -qF "UNEXPECTED_SUCCESS" "$TMP/ewi16.out"; then echo "  FAIL: vacuous success — the function fell through the disarmed errexit"; FAIL=$((FAIL + 1));
else echo "  PASS: no vacuous success"; PASS=$((PASS + 1)); fi

# ---------------------------------------------------------------------------
echo "Test 17: #6184 bare-layout regression — ensure_bare_config flow unchanged on a bare repo"
# Complements Tests 12/13: a genuine bare repo (no .git subdir) still gets the
# bare-accommodation surgery (extensions.worktreeConfig=true) via the atomic path.
BARE17=$(mktemp -d "$TMP/bare17.XXXXXX")
git init -q --bare -b main "$BARE17/repo.git" >/dev/null 2>&1
_SAVED_GIT_ROOT="$GIT_ROOT"
GIT_ROOT="$BARE17/repo.git"
set +e; ensure_bare_config >"$TMP/ebc17.out" 2>&1; EBC17_RC=$?; set -e
GIT_ROOT="$_SAVED_GIT_ROOT"
assert_eq "0" "$EBC17_RC" "ensure_bare_config returns 0 on a genuine bare repo (regression guard)"
if git config --file "$BARE17/repo.git/config" --get extensions.worktreeConfig 2>/dev/null | grep -qx true; then
  echo "  PASS: bare accommodation still enables extensions.worktreeConfig (bare path unchanged)"; PASS=$((PASS + 1))
else
  echo "  FAIL: bare repo lost its extensions.worktreeConfig surgery — bare-layout regression"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 18: #6184 F1 — bot-shaped LOCAL is OVERRIDDEN by a human --global (bare-dev #2815 guard)"
# The bare CLI dev repo frequently inherits a github-actions[bot] LOCAL at the common-dir;
# every worktree inherits it. A pure "respect present local" would keep the bot and produce
# bot-authored commits that fail the CLA gate (#2815). The bot-aware fix must PREFER the
# human --global over a bot-shaped local. (RED against the presence-only respect-local rule,
# which returns 0 and keeps the bot.)
MAIN18=$(mktemp -d "$TMP/main18.XXXXXX"); git init -q -b main "$MAIN18" >/dev/null 2>&1
git -C "$MAIN18" config user.email "1234+github-actions[bot]@users.noreply.github.com"  # inherited BOT local
git -C "$MAIN18" config user.name "github-actions[bot]"
git -C "$MAIN18" commit -q --allow-empty -m init >/dev/null 2>&1
WT18="$MAIN18/wt"; git -C "$MAIN18" worktree add -q "$WT18" -b feat18 >/dev/null 2>&1
FAKE_GLOBAL18="$MAIN18/fake-global"                            # the HUMAN operator --global
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL18" git config --global user.email "human@dev.example"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL18" git config --global user.name "Human Dev"
set +e
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL18" ensure_worktree_identity "$WT18" >"$TMP/ewi18.out" 2>&1
EWI18_RC=$?
set -e
assert_eq "0" "$EWI18_RC" "bot-local override returns 0"
assert_eq "human@dev.example" "$(git config --file "$MAIN18/.git/config" --get user.email 2>/dev/null || echo MISS)" \
  "bot-shaped local user.email OVERRIDDEN by the human global (not left as the bot)"
assert_eq "Human Dev" "$(git config --file "$MAIN18/.git/config" --get user.name 2>/dev/null || echo MISS)" \
  "bot-shaped local user.name OVERRIDDEN by the human global"
if grep -qF "SOLEUR_GIT_LOCK_IDENTITY_DIAG source=ensure_worktree_identity reason=identity-drift-override-bot-local" "$TMP/ewi18.out"; then
  echo "  PASS: override-bot-local DIAG marker emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected the identity-drift-override-bot-local DIAG marker"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
echo "Test 19: #6184 F2 — a bot-shaped --global is REFUSED, never silently written (no misattribution)"
# Concierge host-seeding failed/raced → LOCAL absent, and the sandbox image --global is the
# bot. Writing it would silently misattribute the owner's commits (the Layer-A harm). The
# fix must REFUSE: emit the wedge sentinel + return 1 (fail loud), NOT author as the bot.
# (RED against the pre-fix code, which sets from the bot global and returns 0.)
MAIN19=$(mktemp -d "$TMP/main19.XXXXXX"); git init -q -b main "$MAIN19" >/dev/null 2>&1
git -C "$MAIN19" -c user.email=temp@t -c user.name=temp commit -q --allow-empty -m init >/dev/null 2>&1
WT19="$MAIN19/wt"; git -C "$MAIN19" worktree add -q "$WT19" -b feat19 >/dev/null 2>&1
git -C "$MAIN19" config --unset user.email 2>/dev/null || true   # LOCAL absent (seed failed)
git -C "$MAIN19" config --unset user.name 2>/dev/null || true
FAKE_GLOBAL19="$MAIN19/fake-global"                              # the sandbox BOT global
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL19" git config --global user.email "gha-bot@users.noreply.github.com"
GIT_CONFIG_GLOBAL="$FAKE_GLOBAL19" git config --global user.name "github-actions[bot]"
set +e
( set -euo pipefail
  export GIT_CONFIG_GLOBAL="$FAKE_GLOBAL19"
  ensure_worktree_identity "$WT19"
) >"$TMP/ewi19.out" 2>&1
EWI19_RC=$?
set -e
if (( EWI19_RC != 0 )); then echo "  PASS: bot-global refusal returns non-zero (fail loud)"; PASS=$((PASS + 1));
else echo "  FAIL: bot-shaped global must be refused with a non-zero return, not written"; FAIL=$((FAIL + 1)); fi
if grep -qF "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=bot-global-refused" "$TMP/ewi19.out"; then
  echo "  PASS: bot-global-refused wedge sentinel emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected the reason=bot-global-refused wedge sentinel"; FAIL=$((FAIL + 1))
fi
assert_eq "MISS" "$(git config --file "$MAIN19/.git/config" --get user.email 2>/dev/null || echo MISS)" \
  "the bot global was NOT written into the common-dir config (no misattribution)"

echo ""
print_results
