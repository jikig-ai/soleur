#!/usr/bin/env bash

# Tests for the bare-repo-in-`.git` layout defect (#7394).
#
# THE DEFECT. `ensure_bare_config`'s round-6 non-bare guard treats "`git_dir` is a
# `.git` DIRECTORY" as a pure-filesystem proof of a normal clone and returns early.
# That is true for the Concierge workspace layout it was written for (#5934 round 6),
# but the operator's CLI repo is a BARE repo stored in a `.git` subdirectory:
# `<root>/.git` is a real directory AND `core.bare = true`. The guard matches, the
# surgery is skipped, and `ensure_bare_config` is DEAD CODE on that layout.
#
# THE CONSEQUENCE. Nothing breaks the config pair that wedges worktrees:
# `core.bare = true` in the SHARED `.git/config` together with
# `extensions.worktreeConfig = true`. Under that extension git resolves `core.bare`
# per-worktree, and a linked worktree that does not set `bare = false` in its OWN
# `config.worktree` inherits `true` from the shared config — so git considers a
# perfectly valid worktree BARE. `git rev-parse --show-toplevel` then fatals, the
# script's `IS_IN_WORKTREE` is false, and every `require_working_tree`-gated
# subcommand (`draft-pr`, …) refuses with "Cannot run from bare repo root".
#
# VERIFIED REPRODUCTION CONDITION (git 2.53.0). The wedge requires the CONJUNCTION of
#   (i)   `extensions.worktreeConfig = true` in the shared `.git/config`,
#   (ii)  `core.bare = true` in the shared `.git/config`, and
#   (iii) the linked worktree's own `config.worktree` not setting `bare = false`.
# Removing (i) alone fixes it. The issue as filed names (ii) and (iii) but NOT (i),
# so its root cause is correct-but-incomplete: on a clone where the extension is
# absent the bug is LATENT, not absent — `worktree-manager.sh` is the only in-repo
# production setter of that key.
#
# THE FIX UNDER TEST (three surfaces):
#   Phase 2  — decide bare-ness from `core.bare` read out of the shared config FILE
#              rather than from the gitdir's SHAPE, still defaulting to SKIP. The
#              round-6 mask protection is preserved because a masked config read
#              degrades to "absent", which routes to SKIP.
#   Phase 3  — REVERSE the polarity: stop enabling `extensions.worktreeConfig`,
#              defensively remove it, and KEEP `core.bare` in the shared config.
#   Phase 4/5 — seed `core.bare = false` into each worktree's own `config.worktree`
#              at create time, and self-heal an already-poisoned worktree at
#              detection time (blast radius 1 — the shared config is NOT touched).
#
# Fixtures are synthesized with `git init` / `git clone --bare`
# (`cq-test-fixtures-synthesized-only`). Cases that need a DIFFERENT detection state
# source the script in a FRESH SUBSHELL from inside the fixture: `IS_BARE`,
# `IS_IN_WORKTREE`, `GIT_ROOT` and `WORKTREE_DIR` are computed at SOURCE time, so
# re-sourcing in the same shell silently reuses the first computation.
#
# Run: bash plugins/soleur/test/worktree-manager-bare-in-dotgit-layout.test.sh

set -euo pipefail

# Clear ALL git env vars that leak when this test runs inside a git hook/worktree.
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SCRIPT="$SCRIPT_DIR/../skills/git-worktree/scripts/worktree-manager.sh"

# `/tmp` is a machine-global 4 GiB tmpfs shared by every parallel worktree; a direct
# invocation of this suite (the inner loop while editing the thing under test) would
# otherwise inherit it and make verdicts a function of another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

echo "=== worktree-manager.sh — bare-repo-in-.git layout (#7394) ==="
echo ""

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

GIT_VERSION="$(git --version)"
echo "  (git: $GIT_VERSION)"
echo ""

# --- shared seed: a normal repo with one commit, the source for every clone --------
SEED="$TMP/seed"
git init -q -b main "$SEED" >/dev/null 2>&1
git -C "$SEED" config user.email "test@test.local"
git -C "$SEED" config user.name "Test"
git -C "$SEED" commit -q --allow-empty -m "init"

# ---------------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------------

# new_bare_in_dotgit <root> — the operator's layout: a BARE repo whose gitdir IS
# <root>/.git (a real directory) with core.bare=true. This is ADR-099 row 3's root
# and is exactly what `[[ -d <root>/.git ]]` cannot discriminate from a normal clone.
new_bare_in_dotgit() {
  local root="$1"
  mkdir -p "$root"
  git clone -q --bare "$SEED" "$root/.git" >/dev/null 2>&1
  git config --file "$root/.git/config" user.email "test@test.local"
  git config --file "$root/.git/config" user.name "Test"
}

# new_genuine_bare <dir> — the classic bare layout: gitdir IS the root (repo.git).
new_genuine_bare() {
  git clone -q --bare "$SEED" "$1" >/dev/null 2>&1
  git config --file "$1/config" user.email "test@test.local"
  git config --file "$1/config" user.name "Test"
}

# poison_pair <shared-config> — install the wedging pair. `extensions.*` is only
# honoured at repositoryformatversion 1, so both keys are required to reproduce.
poison_pair() {
  git config --file "$1" core.repositoryformatversion 1
  git config --file "$1" extensions.worktreeConfig true
}

# add_worktree <root> <name> — raw `git worktree add`, NO worktree-manager involvement.
add_worktree() {
  git -C "$1" worktree add -q "$1/.worktrees/$2" -b "$2" main >/dev/null 2>&1
}

# admin_dir <root> <name> — the worktree's own admin dir (holds config.worktree).
admin_dir() { echo "$1/.git/worktrees/$2"; }

# run_sourced <cwd> <code> — source worktree-manager.sh FRESH in a subshell at <cwd>
# so init-time detection (IS_BARE / IS_IN_WORKTREE / GIT_ROOT / WORKTREE_DIR) is
# recomputed for that fixture, then eval <code>.
#
# Source-time output is deliberately NOT discarded. The detection-time self-heal runs
# DURING the source, so both its success marker and its failure diagnostics are emitted
# there — redirecting the source to /dev/null would make every assertion about those
# messages unable to fail, which is the vacuous-green shape this suite exists to prevent.
# Assertions anchor on their own literals (`RWT_OK`, `^WTDIR=`), so the extra lines are
# inert. A `exit` inside the sourced script terminates this subshell before <code> runs —
# which is the behaviour Case 12 asserts.
run_sourced() {
  local cwd="$1" code="$2"
  (
    cd "$cwd" || exit 90
    # shellcheck source=/dev/null
    source "$SCRIPT"
    eval "$code"
  )
}

# Source once in a normal checkout for the cases that drive ensure_bare_config
# directly by overriding GIT_ROOT (the Test-17 convention in the sibling suite).
# The BASH_SOURCE[0] == $0 guard means main() does NOT run on source.
HOSTWS="$TMP/hostws"
git init -q -b main "$HOSTWS" >/dev/null 2>&1
git -C "$HOSTWS" config user.email "test@test.local"
git -C "$HOSTWS" config user.name "Test"
cd "$HOSTWS"
# shellcheck source=/dev/null
source "$SCRIPT"

_SAVED_GIT_ROOT="$GIT_ROOT"
restore_root() { GIT_ROOT="$_SAVED_GIT_ROOT"; }

# ---------------------------------------------------------------------------------
echo "Case 1: [R8] a row-3 POISONED worktree — require_working_tree SUCCEEDS from inside it"
# Attributed to PHASE 5 (detection-time self-heal), NOT to ensure_bare_config: the
# recovery must work for a worktree that already exists, without any create-path run.
C1="$TMP/c1"
new_bare_in_dotgit "$C1"
poison_pair "$C1/.git/config"
add_worktree "$C1" "feat-a"
C1_WT="$C1/.worktrees/feat-a"

# Precondition: the fixture really is wedged (guards against a vacuous PASS).
C1_PRE="$(git -C "$C1_WT" rev-parse --is-bare-repository 2>/dev/null || echo ERR)"
assert_eq "true" "$C1_PRE" "fixture precondition: the poisoned worktree really does report bare"

set +e
C1_OUT="$(run_sourced "$C1_WT" 'require_working_tree && echo RWT_OK' 2>&1)"
C1_RC=$?
set -e
if (( C1_RC == 0 )) && printf '%s' "$C1_OUT" | grep -qF 'RWT_OK'; then
  echo "  PASS: require_working_tree succeeds from inside the poisoned worktree"; PASS=$((PASS + 1))
else
  echo "  FAIL: require_working_tree refused from inside a VALID worktree (the #7394 symptom)"
  printf '%s\n' "$C1_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 2: bare-in-.git, CLEAN — ensure_bare_config NORMALIZES instead of returning early"
# The dead-code proof. Today the `*/.git && -d` guard returns 0 before any work.
C2="$TMP/c2"
new_bare_in_dotgit "$C2"
git config --file "$C2/.git/config" core.worktree "/stale/path"   # the row-3 leftover
GIT_ROOT="$C2"
set +e; C2_OUT="$(ensure_bare_config 2>&1)"; C2_RC=$?; set -e
restore_root
assert_eq "0" "$C2_RC" "ensure_bare_config returns 0 on the bare-in-.git layout"
assert_eq "true" "$(git config --file "$C2/.git/config" --get core.bare 2>/dev/null || echo __ABSENT__)" \
  "shared core.bare RETAINED (reversed polarity — it is no longer unset)"
assert_eq "__ABSENT__" "$(git config --file "$C2/.git/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "extensions.worktreeConfig ABSENT (never enabled; defensively removed)"
assert_eq "__ABSENT__" "$(git config --file "$C2/.git/config" --get core.worktree 2>/dev/null || echo __ABSENT__)" \
  "stale core.worktree removed (this step is retained from the old behaviour)"
if printf '%s' "$C2_OUT" | grep -qF 'SOLEUR_GIT_BARE_POISON' && printf '%s' "$C2_OUT" | grep -qF 'branch=healed'; then
  echo "  PASS: SOLEUR_GIT_BARE_POISON … branch=healed emitted (work was done)"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected branch=healed when normalization actually changed something"
  printf '%s\n' "$C2_OUT" | sed 's/^/    /'; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 3: bare-in-.git + row-3 POISON — the pair is BROKEN, post-state matches row 1"
C3="$TMP/c3"
new_bare_in_dotgit "$C3"
poison_pair "$C3/.git/config"
add_worktree "$C3" "feat-b"
GIT_ROOT="$C3"
set +e; C3_OUT="$(ensure_bare_config 2>&1)"; C3_RC=$?; set -e
restore_root
assert_eq "0" "$C3_RC" "ensure_bare_config returns 0 on the poisoned bare-in-.git layout"
assert_eq "__ABSENT__" "$(git config --file "$C3/.git/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "the poisoning half of the pair is REMOVED"
assert_eq "true" "$(git config --file "$C3/.git/config" --get core.bare 2>/dev/null || echo __ABSENT__)" \
  "core.bare RETAINED — the bare root must keep reporting bare (fact 7)"
C3_WT_BARE="$(git -C "$C3/.worktrees/feat-b" rev-parse --is-bare-repository 2>/dev/null || echo ERR)"
assert_eq "false" "$C3_WT_BARE" "the linked worktree no longer reports bare"
if printf '%s' "$C3_OUT" | grep -qF 'branch=healed'; then
  echo "  PASS: branch=healed emitted for the poisoned fixture"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected branch=healed on a poisoned fixture"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 4: GENUINE bare (gitdir IS the root) + linked worktree — same invariant"
C4="$TMP/c4/repo.git"
mkdir -p "$TMP/c4"
new_genuine_bare "$C4"
poison_pair "$C4/config"
git -C "$C4" worktree add -q "$TMP/c4/wt-a" -b "wt-a" main >/dev/null 2>&1
GIT_ROOT="$C4"
set +e; C4_OUT="$(ensure_bare_config 2>&1)"; C4_RC=$?; set -e
restore_root
assert_eq "0" "$C4_RC" "ensure_bare_config returns 0 on a genuine bare repo"
assert_eq "__ABSENT__" "$(git config --file "$C4/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "genuine-bare path also removes the extension (polarity is layout-independent)"
assert_eq "false" "$(git -C "$TMP/c4/wt-a" rev-parse --is-bare-repository 2>/dev/null || echo ERR)" \
  "genuine-bare linked worktree no longer reports bare"
if printf '%s' "$C4_OUT" | grep -qF 'branch=healed'; then
  echo "  PASS: branch=healed emitted on the genuine-bare layout too"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected branch=healed on the genuine-bare fixture"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 5: NEGATIVE — a normal non-bare clone gets ZERO config writes (pins #6184)"
C5="$TMP/c5"
git init -q -b main "$C5" >/dev/null 2>&1
git -C "$C5" config user.email "test@test.local"
git -C "$C5" config user.name "Test"
cp -p "$C5/.git/config" "$TMP/c5-config.before"
GIT_ROOT="$C5"
set +e; C5_OUT="$(ensure_bare_config 2>&1)"; C5_RC=$?; set -e
restore_root
assert_eq "0" "$C5_RC" "ensure_bare_config returns 0 on a normal clone"
if cmp -s "$TMP/c5-config.before" "$C5/.git/config"; then
  echo "  PASS: .git/config is BYTE-IDENTICAL (no write of any kind)"; PASS=$((PASS + 1))
else
  echo "  FAIL: normal clone's .git/config was modified — #6184 regression"
  diff -u "$TMP/c5-config.before" "$C5/.git/config" | sed 's/^/    /' || true
  FAIL=$((FAIL + 1))
fi
# The guard SKIPS before the normalization block, so no POISON marker may be emitted.
# Without this, a future change that falls through on a non-bare clone would be silent.
if printf '%s' "$C5_OUT" | grep -qF 'SOLEUR_GIT_BARE_POISON'; then
  echo "  FAIL: emitted a bare-config marker on a NON-bare clone (guard fell through)"
  printf '%s\n' "$C5_OUT" | sed 's/^/    /'; FAIL=$((FAIL + 1))
else
  echo "  PASS: no bare-config marker on a non-bare clone (skip path held)"; PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 6: NEGATIVE — MASKED shared config still short-circuits (pins #5934 round 6)"
# The mask-safety argument for reading core.bare out of the config FILE: the read
# degrades to "absent", which routes to SKIP — the same branch as before.
C6="$TMP/c6"
git init -q -b main "$C6" >/dev/null 2>&1
rm -f "$C6/.git/config"
ln -s /dev/null "$C6/.git/config"      # char device by dereference == the live mask
GIT_ROOT="$C6"
set +e; C6_OUT="$(ensure_bare_config 2>&1)"; C6_RC=$?; set -e
restore_root
assert_eq "0" "$C6_RC" "masked-config clone still returns 0 (graceful degrade, not a wedge)"
if printf '%s' "$C6_OUT" | grep -qF 'SOLEUR_GIT_CONFIG_MASK_SKIP' \
   && printf '%s' "$C6_OUT" | grep -qF 'branch=non-bare-skip'; then
  echo "  PASS: benign SOLEUR_GIT_CONFIG_MASK_SKIP … branch=non-bare-skip emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected the benign mask-skip diagnostic on a masked config"
  printf '%s\n' "$C6_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi
if printf '%s' "$C6_OUT" | grep -qE 'worktree wedge|soleur-tmp|mv:'; then
  echo "  FAIL: attempted a write against a masked config"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no write attempted against the masked config"; PASS=$((PASS + 1))
fi
if [[ -L "$C6/.git/config" ]]; then
  echo "  PASS: the masked node itself was left untouched"; PASS=$((PASS + 1))
else
  echo "  FAIL: the masked config node was clobbered"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 7: INVARIANT — no reachable state leaves extension ENABLED while shared core.bare is present"
# Asserted across every fixture this suite has driven ensure_bare_config over, so a
# future change that re-introduces the pair anywhere reds here rather than in prod.
C7_VIOLATIONS=0
for cfg in "$C2/.git/config" "$C3/.git/config" "$C4/config" "$C5/.git/config"; do
  [[ -f "$cfg" ]] || continue
  _ext="$(git config --file "$cfg" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)"
  _bare="$(git config --file "$cfg" --get core.bare 2>/dev/null || echo __ABSENT__)"
  if [[ "$_ext" == "true" && "$_bare" != "__ABSENT__" ]]; then
    echo "    VIOLATION: $cfg has extension=true AND core.bare=$_bare"
    C7_VIOLATIONS=$((C7_VIOLATIONS + 1))
  fi
done
assert_eq "0" "$C7_VIOLATIONS" "zero (extension-enabled + shared core.bare) states across all driven fixtures"

# ---------------------------------------------------------------------------------
echo "Case 8: already-poisoned worktree, ensure_bare_config NOT called — self-heal alone recovers"
# Proves the Phase 5 recovery is independent of the create path AND that its blast
# radius is exactly 1: the SHARED config must come out byte-unchanged.
C8="$TMP/c8"
new_bare_in_dotgit "$C8"
poison_pair "$C8/.git/config"
add_worktree "$C8" "feat-c"
C8_WT="$C8/.worktrees/feat-c"
cp -p "$C8/.git/config" "$TMP/c8-shared.before"
set +e
C8_OUT="$(run_sourced "$C8_WT" 'require_working_tree && echo RWT_OK' 2>&1)"
C8_RC=$?
set -e
if (( C8_RC == 0 )) && printf '%s' "$C8_OUT" | grep -qF 'RWT_OK'; then
  echo "  PASS: self-heal alone makes require_working_tree succeed"; PASS=$((PASS + 1))
else
  echo "  FAIL: self-heal did not recover the already-poisoned worktree"
  printf '%s\n' "$C8_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi
if cmp -s "$TMP/c8-shared.before" "$C8/.git/config"; then
  echo "  PASS: SHARED config byte-unchanged (blast radius stays at 1 worktree)"; PASS=$((PASS + 1))
else
  echo "  FAIL: self-heal touched the SHARED config — blast radius exceeded"
  diff -u "$TMP/c8-shared.before" "$C8/.git/config" | sed 's/^/    /' || true
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 9: after create — the new worktree's own config.worktree carries core.bare=false"
C9="$TMP/c9"
new_bare_in_dotgit "$C9"

# [R-fact4] Baseline FIRST, in this same case: a raw `git worktree add` creates NO
# config.worktree at all. The plan originally claimed an EMPTY one; measured false.
# Assert NON-EXISTENCE (`! -e`) — never "exists and is 0 bytes".
add_worktree "$C9" "raw-baseline"
if [[ ! -e "$(admin_dir "$C9" raw-baseline)/config.worktree" ]]; then
  echo "  PASS: baseline — raw 'git worktree add' creates NO config.worktree"; PASS=$((PASS + 1))
else
  echo "  FAIL: baseline falsified — raw worktree add DID create a config.worktree"; FAIL=$((FAIL + 1))
fi

set +e
C9_OUT="$(run_sourced "$C9" 'YES_FLAG=true; create_worktree "feat-seeded" "main" >/dev/null 2>&1; echo CREATE_RC=$?' 2>&1)"
set -e
C9_SEEDED="$(admin_dir "$C9" feat-seeded)/config.worktree"
if [[ -f "$C9_SEEDED" ]]; then
  echo "  PASS: create seeded a config.worktree for the new worktree"; PASS=$((PASS + 1))
else
  echo "  FAIL: create did not seed the new worktree's config.worktree ($C9_SEEDED)"
  printf '%s\n' "$C9_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi
assert_eq "false" "$(git config --file "$C9_SEEDED" --get core.bare 2>/dev/null || echo __ABSENT__)" \
  "seeded config.worktree pins core.bare=false"

# ---------------------------------------------------------------------------------
echo "Case 10: after ensure_bare_config on a clean fixture, the ROOT still reports bare (fact 7)"
# Pins the retired end state: the issue's hand workaround (unset core.bare) makes the
# bare ROOT report as a normal working tree, which is why the polarity was reversed
# rather than the workaround being codified.
assert_eq "true" "$(git -C "$C2" rev-parse --is-bare-repository 2>/dev/null || echo ERR)" \
  "the bare ROOT still reports bare after normalization"

# ---------------------------------------------------------------------------------
echo "Case 11: [R1] already-CLEAN fixture — returns 0, emits branch=clean, no wedge"
# RED against today's atomic_git_config: the defensive removal uses --unset-all, whose
# FR2 read-first fast path currently matches only the literal '--unset', so it falls
# through to the native writer and `--unset-all` on an ABSENT key exits 5 — which
# would wedge every already-healthy repo.
C11="$TMP/c11"
new_bare_in_dotgit "$C11"    # core.bare=true, extension ABSENT == already clean
GIT_ROOT="$C11"
set +e; C11_OUT="$(ensure_bare_config 2>&1)"; C11_RC=$?; set -e
restore_root
assert_eq "0" "$C11_RC" "already-clean bare-in-.git returns 0 (does NOT wedge on --unset-all)"
if printf '%s' "$C11_OUT" | grep -qF 'SOLEUR_GIT_BARE_POISON' \
   && printf '%s' "$C11_OUT" | grep -qF 'branch=clean'; then
  echo "  PASS: SOLEUR_GIT_BARE_POISON … branch=clean emitted"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected SOLEUR_GIT_BARE_POISON … branch=clean on an already-clean repo"
  printf '%s\n' "$C11_OUT" | sed 's/^/    /'
  FAIL=$((FAIL + 1))
fi
if printf '%s' "$C11_OUT" | grep -qF 'worktree wedge:'; then
  echo "  FAIL: emitted a wedge give-up on an already-healthy repo"; FAIL=$((FAIL + 1))
else
  echo "  PASS: no 'worktree wedge:' give-up on an already-healthy repo"; PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 12: [R5] self-heal target UNWRITABLE — fails loud with an actionable message"
C12="$TMP/c12"
new_bare_in_dotgit "$C12"
poison_pair "$C12/.git/config"
add_worktree "$C12" "feat-d"
C12_ADMIN="$(admin_dir "$C12" feat-d)"
if [[ "$(id -u)" == "0" ]]; then
  echo "  SKIP: running as root — chmod a-w does not deny the owner"
else
  chmod a-w "$C12_ADMIN"
  set +e
  C12_OUT="$(run_sourced "$C12/.worktrees/feat-d" 'require_working_tree && echo RWT_OK' 2>&1)"
  C12_RC=$?
  set -e
  chmod u+w "$C12_ADMIN"
  if (( C12_RC != 0 )); then
    echo "  PASS: exits non-zero instead of proceeding into git commands that will fatal"; PASS=$((PASS + 1))
  else
    echo "  FAIL: returned success despite being unable to write the recovery config"; FAIL=$((FAIL + 1))
  fi
  if printf '%s' "$C12_OUT" | grep -qF 'SOLEUR_GIT_BARE_SELFHEAL' \
     && printf '%s' "$C12_OUT" | grep -qF 'branch=failed'; then
    echo "  PASS: SOLEUR_GIT_BARE_SELFHEAL … branch=failed emitted"; PASS=$((PASS + 1))
  else
    echo "  FAIL: expected SOLEUR_GIT_BARE_SELFHEAL … branch=failed"
    printf '%s\n' "$C12_OUT" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
  fi
  if printf '%s' "$C12_OUT" | grep -qF "$C12_ADMIN"; then
    echo "  PASS: message names the ABSOLUTE path it could not write"; PASS=$((PASS + 1))
  else
    echo "  FAIL: message does not name the absolute unwritable path"; FAIL=$((FAIL + 1))
  fi
  if printf '%s' "$C12_OUT" | grep -qiE 'permission|ownership|read-only|disk'; then
    echo "  PASS: message names likely causes"; PASS=$((PASS + 1))
  else
    echo "  FAIL: message does not name likely causes"; FAIL=$((FAIL + 1))
  fi
  # The message this replaces — do NOT fall back to it (the plan's Third defect).
  if printf '%s' "$C12_OUT" | grep -qF 'Run from an existing worktree'; then
    echo "  FAIL: fell back to the uninformative 'Run from an existing worktree' text"; FAIL=$((FAIL + 1))
  else
    echo "  PASS: did not fall back to the uninformative bare-root text"; PASS=$((PASS + 1))
  fi
fi

# ---------------------------------------------------------------------------------
echo "Case 13: [R3] after self-heal, WORKTREE_DIR is <root>/.worktrees and create lands there"
# Asserting require_working_tree returns 0 is NOT sufficient: if the recovery runs
# AFTER the WORKTREE_DIR assignment, GIT_ROOT is still the pre-heal value
# (<common>/worktrees/<name>) and every subsequent create lands in the admin dir.
C13="$TMP/c13"
new_bare_in_dotgit "$C13"
poison_pair "$C13/.git/config"
add_worktree "$C13" "feat-e"
set +e
C13_WTDIR="$(run_sourced "$C13/.worktrees/feat-e" 'echo "WTDIR=$WORKTREE_DIR"' 2>&1 | grep -oP '(?<=^WTDIR=).*' || true)"
set -e
assert_eq "$C13/.worktrees" "$C13_WTDIR" "WORKTREE_DIR resolves to <root>/.worktrees after the heal"
set +e
run_sourced "$C13/.worktrees/feat-e" 'YES_FLAG=true; create_worktree "feat-f" "main" >/dev/null 2>&1' >/dev/null 2>&1
set -e
if [[ -d "$C13/.worktrees/feat-f" ]]; then
  echo "  PASS: a subsequent create lands under <root>/.worktrees"; PASS=$((PASS + 1))
else
  echo "  FAIL: subsequent create did not land under <root>/.worktrees"; FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------------
echo "Case 14: [R-arch2] NEGATIVE — normal .git-DIRECTORY clone whose shared config says core.bare=true"
# The state the Phase 2 guard newly falls through on. Intended behaviour, asserted
# EXPLICITLY: the reversed polarity makes the fall-through HARMLESS — both remaining
# operations are unsets of ABSENT keys, so the run performs zero writes and the
# config comes out byte-identical. (This is the same fixture shape as the sibling
# suite's Test 23, which must stay green.)
C14="$TMP/c14"
git init -q -b main "$C14" >/dev/null 2>&1
git -C "$C14" config user.email "test@test.local"
git -C "$C14" config user.name "Test"
git -C "$C14" config core.bare true
cp -p "$C14/.git/config" "$TMP/c14-config.before"
GIT_ROOT="$C14"
set +e; C14_OUT="$(ensure_bare_config 2>&1)"; C14_RC=$?; set -e
restore_root
assert_eq "0" "$C14_RC" "corrupted-non-bare clone returns 0 (no refusal, no wedge)"
if cmp -s "$TMP/c14-config.before" "$C14/.git/config"; then
  echo "  PASS: .git/config byte-identical — the fall-through performs zero writes"; PASS=$((PASS + 1))
else
  echo "  FAIL: the corrupted non-bare clone's config was modified"
  diff -u "$TMP/c14-config.before" "$C14/.git/config" | sed 's/^/    /' || true
  FAIL=$((FAIL + 1))
fi
assert_eq "__ABSENT__" "$(git config --file "$C14/.git/config" --get extensions.worktreeConfig 2>/dev/null || echo __ABSENT__)" \
  "extension still absent (never enabled under the reversed polarity)"
# [R-arch2] The intended behaviour on this fall-through, asserted rather than implied:
# the run reaches the normalization block, finds nothing to do, and says so.
if printf '%s' "$C14_OUT" | grep -qF 'branch=clean'; then
  echo "  PASS: falls through and reports branch=clean (nothing to heal)"; PASS=$((PASS + 1))
else
  echo "  FAIL: expected branch=clean on the corrupted non-bare clone"
  printf '%s\n' "$C14_OUT" | sed 's/^/    /'; FAIL=$((FAIL + 1))
fi

echo ""
print_results
