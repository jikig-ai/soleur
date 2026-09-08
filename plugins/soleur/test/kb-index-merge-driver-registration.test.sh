#!/usr/bin/env bash
#
# Registration suite for the knowledge-base index merge driver (#7935).
#
# SEPARATE FROM THE FUNCTIONAL SUITE ON PURPOSE. That one asks "does the driver
# merge correctly"; this one asks "does the driver get REGISTERED, everywhere it
# has to be, without ever blocking the session that registers it". The two have
# different fixture shapes and different failure meanings, and a red run should
# say which question failed.
#
# WHY THE STAKES ARE HIGH FOR A SCRIPT THIS SMALL. It writes to a `.git/config`
# that every linked worktree on the machine shares — the same file that holds
# `core.hooksPath`. A bug that clobbered that key would silently disarm every
# lefthook gate across every worktree at once, which is a far worse outcome than
# the unregistered merge driver this script exists to prevent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

INSTALL="$REPO_ROOT/scripts/install-kb-merge-driver.sh"
DRIVER="$REPO_ROOT/scripts/merge-kb-index.sh"
RENDER_LIB="$REPO_ROOT/scripts/lib/kb-index-render.sh"
GEN="$REPO_ROOT/scripts/generate-kb-index.sh"
KEY="merge.kb-index.driver"

export TMPDIR="${TMPDIR:-/var/tmp}"

WORK=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT INT TERM HUP
WORK="$(mktemp -d -t kbreg.XXXXXXXX)"
assert_fixture_dir "$WORK"

# Hermetic: no global or system config reaches the fixtures, so the developer's
# own registration (which this very PR installs on every machine that runs the
# suite) cannot make an unregistered assertion vacuously pass.
run_install() {
  local dir="$1"
  assert_fixture_dir "$dir"
  ( cd "$dir" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$INSTALL" )
}
cfg() {
  local dir="$1" key="$2"
  assert_fixture_dir "$dir"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$dir" config --get "$key" 2>/dev/null || true
}
new_repo() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q -b trunk "$dir"
  printf '%s' "$dir"
}

echo "=== AC7/T10: registration is idempotent, and restores a deleted key ==="
R="$(new_repo idem)"
rc1=0; run_install "$R" >/dev/null 2>&1 || rc1=$?
v1="$(cfg "$R" "$KEY")"
rc2=0; run_install "$R" >/dev/null 2>&1 || rc2=$?
v2="$(cfg "$R" "$KEY")"
assert_eq "0" "$rc1" "AC7: first run exits 0"
assert_eq "0" "$rc2" "AC7: second run exits 0"
assert_eq "$v1" "$v2" "AC7: the value is unchanged by a second run"
assert_eq "1" "$([[ -n "$v1" ]] && echo 1 || echo 0)" "AC7: the key is actually set"
assert_eq "1" "$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$R" config --get-all "$KEY" | wc -l | tr -d ' ')" \
  "AC7: exactly one value is stored, not a multivar accumulation"
# A run against an already-correct config must perform NO write. Observed via
# the config file's mtime rather than asserted in prose.
touch -d '2020-01-01 00:00:00' "$R/.git/config"
before="$(stat -c %Y "$R/.git/config")"
run_install "$R" >/dev/null 2>&1
after="$(stat -c %Y "$R/.git/config")"
assert_eq "$before" "$after" "AC7: an already-correct config is not rewritten"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$R" config --unset "$KEY"
assert_eq "" "$(cfg "$R" "$KEY")" "T10: the key is gone after --unset"
run_install "$R" >/dev/null 2>&1
assert_eq "$v1" "$(cfg "$R" "$KEY")" "T10: a later run restores the deleted key"

echo "=== AC8: the stored value is worktree-portable, with no absolute path ==="
assert_eq "0" "$(printf '%s' "$v1" | grep -c '^/' || true)" "AC8: the stored value does not begin with an absolute path"
assert_eq "0" "$(printf '%s' "$v1" | grep -cE '(^| )/[A-Za-z]' || true)" "AC8: no absolute path appears anywhere in the value"
assert_eq "1" "$(printf '%s' "$v1" | grep -c 'scripts/merge-kb-index.sh' || true)" "AC8: the value names the driver relatively"

echo "=== AC9: registration never arms the worktree-config wedge ==="
# ADR-173 keeps extensions.worktreeConfig unset deliberately; its stated
# re-evaluation trigger is a new setter appearing anywhere in the toolchain.
# COMMENT LINES ARE STRIPPED FIRST. The script DOCUMENTS that it never touches
# these keys, so a bare-literal count reads 1 against a script that is correct —
# the third instance of cq-assert-anchor-not-bare-token in this one change
# (AC24's `eval` and AC26's CODEOWNERS basenames were the others). The shape
# recurs whenever a guard's subject is a NEGATIVE constraint, because stating
# the constraint requires naming the forbidden literal.
assert_eq "0" "$(grep -vE '^[[:space:]]*#' "$INSTALL" | grep -cE 'extensions\.worktreeConfig|config\.worktree' || true)" \
  "AC9: no worktree-config setter appears in the script's CODE"
assert_eq "" "$(cfg "$R" extensions.worktreeConfig)" "AC9: extensions.worktreeConfig is still unset after registration"
# Porcelain only: the script must never rewrite .git/config as a file.
assert_eq "0" "$(grep -cE '>[[:space:]]*"?\$?[A-Za-z_]*(GIT_DIR|\.git)/config' "$INSTALL" || true)" \
  "AC9: the script never redirects output over .git/config"

echo "=== AC10: a held config.lock never blocks the session ==="
R2="$(new_repo locked)"
: > "$R2/.git/config.lock"
lock_rc=0
lock_err="$( ( cd "$R2" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$INSTALL" ) 2>&1 >/dev/null )" || lock_rc=$?
assert_eq "0" "$lock_rc" "AC10: exits 0 even though the config could not be written"
assert_contains "$lock_err" "install-kb-merge-driver" "AC10: a diagnostic reaches stderr"
assert_eq "" "$(cfg "$R2" "$KEY")" "AC10: and it honestly did not register"
rm -f "$R2/.git/config.lock"

echo "=== AC10b: outside a git repository is not an error ==="
mkdir -p "$WORK/norepo"
nr_rc=0
( cd "$WORK/norepo" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CEILING_DIRECTORIES="$WORK" bash "$INSTALL" ) >/dev/null 2>&1 || nr_rc=$?
assert_eq "0" "$nr_rc" "AC10b: a non-repository directory exits 0 rather than failing an npm install"

echo "=== T17: N parallel registrations converge without corruption ==="
# Parallel agent sessions across many worktrees can fire SessionStart at the
# same instant, which is the shape of the incident this script's caution comes
# from. Sequential idempotency (T10 above) does not cover it.
R3="$(new_repo parallel)"
pids=()
for _ in 1 2 3 4 5 6; do
  ( cd "$R3" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null bash "$INSTALL" >/dev/null 2>&1 ) &
  pids+=($!)
done
par_fail=0
for p in "${pids[@]}"; do wait "$p" || par_fail=1; done
assert_eq "0" "$par_fail" "T17: every parallel run exits 0"
assert_eq "1" "$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$R3" config --get-all "$KEY" | wc -l | tr -d ' ')" \
  "T17: the parallel runs converge on exactly one value"
assert_eq "$v1" "$(cfg "$R3" "$KEY")" "T17: and it is the correct value"
cfg_rc=0
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$R3" config --list >/dev/null 2>&1 || cfg_rc=$?
assert_eq "0" "$cfg_rc" "T17: the config file is not corrupt"

echo "=== T11/AC8: the relative command resolves when git merges from a SUBDIRECTORY ==="
# This is the assertion that makes AC8 more than a string check: it drives a
# real merge from a nested CWD, with the driver registered exactly as the
# install script stores it — relative, nothing baked in.
R4="$(new_repo subdir)"
mkdir -p "$R4/scripts/lib" "$R4/knowledge-base/engineering" "$R4/knowledge-base/project" "$R4/nested/deeper"
cp "$DRIVER" "$R4/scripts/merge-kb-index.sh"
cp "$RENDER_LIB" "$R4/scripts/lib/kb-index-render.sh"
printf 'placeholder\n' > "$R4/nested/deeper/keep.txt"
printf '# Alpha\n' > "$R4/knowledge-base/engineering/alpha.md"
printf '# Beta\n'  > "$R4/knowledge-base/project/beta.md"
gen4() { KB_DIR="$R4/knowledge-base" bash "$GEN" >/dev/null 2>&1; }
# `assert_fixture_dir` is NOT optional here. This helper was a copy of fx_git
# with that line removed, in a suite whose own header explains that a bug here
# disarms every lefthook gate across every worktree at once. `git -C ""` does not
# error — it operates on the CURRENT directory, which under TEST_GROUP=scripts is
# the developer's live worktree.
g4() { assert_fixture_dir "$R4"; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$R4" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
gen4
printf 'knowledge-base/INDEX.md merge=kb-index\n' > "$R4/.gitattributes"
g4 add -A; g4 commit -q -m base
run_install "$R4" >/dev/null 2>&1
assert_eq "$v1" "$(cfg "$R4" "$KEY")" "T11: the fixture is registered with the production relative value"
g4 checkout -q -b side
printf '# Gamma\n' > "$R4/knowledge-base/engineering/gamma.md"; gen4
g4 add -A; g4 commit -q -m side
g4 checkout -q trunk
printf '# Delta\n' > "$R4/knowledge-base/project/delta.md"; gen4
g4 add -A; g4 commit -q -m trunkside
sub_rc=0
# The whole point: CWD is two levels down when the merge runs.
( cd "$R4/nested/deeper" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -c user.email=t@t -c user.name=t -c commit.gpgsign=false merge --no-ff -m m side ) >/dev/null 2>&1 || sub_rc=$?
assert_eq "0" "$sub_rc" "T11: a merge run from a subdirectory completes"
I4="$R4/knowledge-base/INDEX.md"
assert_eq "1" "$(grep -c 'engineering/gamma\.md' "$I4" || true)" "T11: the side row survives a subdirectory merge"
assert_eq "1" "$(grep -c 'project/delta\.md' "$I4" || true)" "T11: the trunk row survives a subdirectory merge"
assert_eq "0" "$(grep -c '^<<<<<<< kb-index' "$I4" || true)" "T11: no sentinel — the relative path resolved"

echo "=== AC11: both registration surfaces are wired ==="
# STRUCTURAL, NOT A SUBSTRING COUNT. `grep -c '<name>' >= 1` over a whole file
# asserts existence while its MESSAGE claims placement, and the presence
# direction is the dangerous one: any non-load-bearing occurrence keeps it green.
# Measured — re-homing the command out of SessionStart onto a PostToolUse matcher
# that never fires left this suite at 29/29 ALL TESTS PASSED with the driver
# registered on no real session. Nothing else in the repo asserts this matcher.
assert_eq "1" "$(jq -r '[.scripts.prepare // "" | select(test("install-kb-merge-driver"))] | length' "$REPO_ROOT/package.json")" \
  "AC11: package.json's prepare script (not merely the file) invokes the registrar"
assert_eq "1" "$(jq -r '[.hooks.SessionStart[]? | select((.matcher // "") | test("startup")) | .hooks[]? | select(.type == "command") | select(.command | test("install-kb-merge-driver"))] | length' "$REPO_ROOT/.claude/settings.json")" \
  "AC11: the registrar is a SessionStart command hook on a matcher that includes startup"

# ASSERTION-HELPER POSITIVE CONTROL — see the twin in kb-index-merge-driver.test.sh.
# The floor counts PASS+FAIL+SKIPPED, so it discriminates dispatch and not
# verdict: neutering assert_eq's comparison to `if true` reports a full green
# byte-identically to a real pass, and no floor value can see it.
_pc_p="$PASS"; _pc_f="$FAIL"
assert_eq "control" "control" "positive control: assert_eq can PASS"
assert_eq "control" "MISMATCH-EXPECTED" "positive control: assert_eq can FAIL (this FAIL line is expected)"
if (( PASS != _pc_p + 1 )); then
  printf 'POSITIVE CONTROL BROKEN: PASS moved %d -> %d, expected exactly +1.\n' "$_pc_p" "$PASS" >&2; exit 1
fi
if (( FAIL != _pc_f + 1 )); then
  printf 'POSITIVE CONTROL BROKEN: FAIL moved %d -> %d, expected exactly +1.\n' "$_pc_f" "$FAIL" >&2; exit 1
fi
PASS=$_pc_p; FAIL=$_pc_f

print_results 29
