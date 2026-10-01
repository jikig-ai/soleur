#!/usr/bin/env bash
# test-soleur-sandbox.sh — arms for soleur_sandbox_new / soleur_sandbox_rm
# (scripts/lib/scratch-root.sh) and the thin CLI scripts/soleur-sandbox.sh.
#
# The allocator hands agents a small, owned, DISK-BACKED work copy of the tree, and `rm`
# DELETES a directory on request — so every refusal conjunct is asserted in BOTH directions
# (a valid sandbox is removed; each single-conjunct violation is refused and left in place).
#
# Test scratch discipline: the suite's own scratch lives under TESTROOT (mktemp) plus DISK_BASE,
# a private disk-backed base this suite creates and injects through SOLEUR_SANDBOX_BASES. Both
# are removed by this file's OWN EXIT trap, installed BEFORE anything is sourced. Every sandbox
# the suite allocates is removed through soleur_sandbox_rm (the trap enumerates DISK_BASE).
#
# AUTHORING CONSTRAINTS (see work/SKILL.md):
#   - Never `producer | grep -q` under pipefail; grep a FILE or use `grep -c`.
#   - Deliberately-nonzero commands inside `$(...)` need `|| true` under set -e.
#   - `cases` increments at the CALL SITE, never inside pass()/fail().

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/scratch-root.sh"
CLI="$REPO_ROOT/scripts/soleur-sandbox.sh"

pass_n=0; fails=0; cases=0
pass() { pass_n=$((pass_n + 1)); echo "  [ok] $1"; }
fail() { fails=$((fails + 1)); echo "  [FAIL] $1" >&2; }

TESTROOT="$(mktemp -d -t soleur-sandbox-test.XXXXXXXX)"
DISK_BASE=""
# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires
# it); do not reword.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
cleanup() {
  local s
  # Sandboxes first, through the allocator's own remover (the contract under test), found by
  # enumerating the private DISK_BASE (a subshell-allocated path cannot be registered in the
  # parent); the blanket rm of the two private bases below is only the backstop.
  if declare -F soleur_sandbox_rm >/dev/null 2>&1 && [[ -n "$DISK_BASE" && -d "$DISK_BASE" ]]; then
    for s in "$DISK_BASE"/soleur-sbx.*; do
      [[ -d "$s" ]] && SOLEUR_SANDBOX_BASES="$DISK_BASE" soleur_sandbox_rm "$s" >/dev/null 2>&1 || true
    done
  fi
  assert_fixture_dir "$TESTROOT"; rm -rf "$TESTROOT"
  [[ -n "$DISK_BASE" ]] && { assert_fixture_dir "$DISK_BASE"; rm -rf "$DISK_BASE"; }
  return 0
}
trap cleanup EXIT

# Fixture-env adoption (#7833/#7849): fixture git writes run under the synthesized identity.
source "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
git_fixture_env "$TESTROOT" || { echo "FATAL: git_fixture_env refused fixture root $TESTROOT" >&2; exit 2; }

# Under the battery test-all.sh exports its own session root; keep arms un-nested.
unset SOLEUR_SCRATCH_SESSION_ROOT SOLEUR_SCRATCH_OWNER_PID SOLEUR_SCRATCH_BASE SOLEUR_SANDBOX_SRC SOLEUR_SANDBOX_BASES

# shellcheck source=scripts/lib/scratch-root.sh
source "$LIB" 2>/dev/null || { echo "FATAL: cannot source $LIB" >&2; exit 2; }

# DISK_BASE: a private, real-filesystem (non-tmpfs) base this suite owns.
for cand in /var/tmp "${XDG_CACHE_HOME:-$HOME/.cache}" "$HOME"; do
  if [[ -d "$cand" && -w "$cand" ]]; then
    fst="$(findmnt -no FSTYPE --target "$cand" 2>/dev/null || true)"
    if [[ -n "$fst" && "$fst" != "tmpfs" && "$fst" != "ramfs" ]]; then
      DISK_BASE="$(mktemp -d "$cand/soleur-sandbox-test.XXXXXXXX")"; break
    fi
  fi
done
if [[ -z "$DISK_BASE" ]]; then
  echo "  [skip] no non-tmpfs writable dir — sandbox allocator arms untestable here"
  exit 0
fi
export SOLEUR_SANDBOX_BASES="$DISK_BASE"

# A fixture repo with a dirty tree: tracked + modified, tracked + deleted, untracked,
# gitignored, a knowledge-base dir, and a node_modules dir.
SRC="$TESTROOT/src"
assert_fixture_dir "$SRC"
mkdir -p "$SRC/knowledge-base" "$SRC/node_modules/pkg" "$SRC/sub"
git -C "$SRC" init -q
printf 'node_modules/\n*.log\n' > "$SRC/.gitignore"
printf 'clean\n' > "$SRC/a.txt"
printf 'gone\n' > "$SRC/d.txt"
printf 'kb\n' > "$SRC/knowledge-base/k.md"
printf 'nested\n' > "$SRC/sub/n.txt"
printf 'nm\n' > "$SRC/node_modules/pkg/index.js"
git -C "$SRC" add -A
git -C "$SRC" commit -q -m fixture
printf 'DIRTY-EDIT\n' > "$SRC/a.txt"          # modified tracked
rm -f "$SRC/d.txt"                              # deleted tracked
printf 'untracked\n' > "$SRC/u.txt"             # untracked, not ignored
printf 'ignored\n' > "$SRC/ign.log"             # ignored

new_sbx() { # label [flags...] — prints path (cleanup enumerates DISK_BASE)
  local out
  out="$(SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new "$@" 2>"$TESTROOT/new.err")" || return $?
  printf '%s' "$out"
}

echo "== functions exist =="
cases=$((cases + 1))
if declare -F soleur_sandbox_new >/dev/null && declare -F soleur_sandbox_rm >/dev/null; then
  pass "soleur_sandbox_new / soleur_sandbox_rm are defined"
else
  fail "soleur_sandbox_new / soleur_sandbox_rm are not defined in scratch-root.sh"
  echo "FAIL ($fails): allocator not implemented"; exit 1
fi

echo "== new: happy path on the dirty fixture =="
SBX=""
cases=$((cases + 1))
if SBX="$(new_sbx fx)"; then pass "new rc=0"; else fail "new returned non-zero"; fi
if [[ -n "$SBX" && -d "$SBX" ]]; then
  cases=$((cases + 1))
  case "$SBX" in "$DISK_BASE"/soleur-sbx.fx.????????) pass "path is <base>/soleur-sbx.<label>.XXXXXXXX under the injected base" ;; *) fail "unexpected path shape: $SBX" ;; esac
  cases=$((cases + 1))
  if [[ -f "$SBX/.soleur-owned" ]] && grep -Eq '^pid=[0-9]+$' "$SBX/.soleur-owned" && grep -Fxq 'schema=1' "$SBX/.soleur-owned"; then
    pass ".soleur-owned marker carries a numeric pid= and schema=1"
  else fail "marker missing or malformed"; fi
  cases=$((cases + 1))
  owner="$(sed -n 's/^pid=//p' "$SBX/.soleur-owned")"
  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then pass "default owner pid ($owner) is a live process"; else fail "default owner pid '$owner' is not live"; fi
  cases=$((cases + 1))
  if [[ ! -e "$SBX/.git" ]]; then pass "no .git in the sandbox"; else fail ".git leaked into the sandbox"; fi
  cases=$((cases + 1))
  if [[ "$(cat "$SBX/a.txt")" == "DIRTY-EDIT" ]]; then pass "dirty (modified) tracked file is copied as-is"; else fail "a.txt is not the dirty version"; fi
  cases=$((cases + 1))
  if [[ -f "$SBX/u.txt" ]]; then pass "untracked, non-ignored file is copied"; else fail "u.txt missing"; fi
  cases=$((cases + 1))
  if [[ -f "$SBX/sub/n.txt" ]]; then pass "nested tracked file is copied"; else fail "sub/n.txt missing"; fi
  cases=$((cases + 1))
  if [[ ! -e "$SBX/d.txt" ]]; then pass "tracked-but-deleted file is absent (and did not abort the copy)"; else fail "d.txt present"; fi
  cases=$((cases + 1))
  if [[ ! -e "$SBX/ign.log" ]]; then pass "gitignored file is not copied"; else fail "ign.log copied"; fi
  cases=$((cases + 1))
  if [[ ! -e "$SBX/knowledge-base" ]]; then pass "knowledge-base/ is excluded by default"; else fail "knowledge-base/ copied"; fi
  cases=$((cases + 1))
  if [[ ! -e "$SBX/node_modules" && ! -L "$SBX/node_modules" ]]; then pass "node_modules is NOT linked by default"; else fail "node_modules present by default"; fi

  echo "== rm: happy path =="
  cases=$((cases + 1))
  if soleur_sandbox_rm "$SBX" >/dev/null 2>&1 && [[ ! -e "$SBX" ]]; then pass "rm removes a valid sandbox"; else fail "rm did not remove a valid sandbox"; fi
fi

echo "== new --link-node-modules =="
cases=$((cases + 1))
SBX2=""
if SBX2="$(new_sbx lnk --link-node-modules)"; then
  if [[ -L "$SBX2/node_modules" ]] && [[ "$(readlink "$SBX2/node_modules")" == "$SRC/node_modules" ]]; then pass "node_modules is a symlink to the live tree"; else fail "node_modules not linked"; fi
  cases=$((cases + 1))
  if grep -q 'WARNING' "$TESTROOT/new.err"; then pass "link mode warns about write-through (#8800 hazard)"; else fail "no write-through warning on stderr"; fi
  cases=$((cases + 1))
  soleur_sandbox_rm "$SBX2" >/dev/null 2>&1 || true
  if [[ ! -e "$SBX2" && -f "$SRC/node_modules/pkg/index.js" ]]; then pass "rm removes the link, never the live target"; else fail "rm followed the node_modules symlink (or left the sandbox)"; fi
else
  fail "new --link-node-modules returned non-zero"
fi

echo "== owner pid override =="
cases=$((cases + 1))
SBX3=""
if SBX3="$(SOLEUR_SCRATCH_OWNER_PID=424242 new_sbx own)" && grep -Fxq 'pid=424242' "$SBX3/.soleur-owned"; then
  pass "SOLEUR_SCRATCH_OWNER_PID wins for the marker pid"
else fail "owner pid override not honored"; fi
[[ -n "$SBX3" ]] && soleur_sandbox_rm "$SBX3" >/dev/null 2>&1 || true

echo "== rm refusals (each leaves the dir in place) =="
mk_valid_marker() { printf 'pid=%s\nschema=1\nns=pid:[1]\n' "$$" > "$1/.soleur-owned"; }
expect_refused() { # description dir
  local desc="$1" d="$2" rc=0
  cases=$((cases + 1))
  soleur_sandbox_rm "$d" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 && -e "$d" ]]; then pass "refuses: $desc"; else fail "did NOT refuse: $desc (rc=$rc)"; fi
}
UNMARKED="$DISK_BASE/soleur-sbx.nomark.AAAAAAAA"; mkdir -p "$UNMARKED"; printf 'x\n' > "$UNMARKED/keep"
expect_refused "soleur-sbx name but no marker" "$UNMARKED"
BADNAME="$DISK_BASE/other.BBBBBBBB"; mkdir -p "$BADNAME"; mk_valid_marker "$BADNAME"
expect_refused "valid marker but name is not soleur-sbx.*" "$BADNAME"
OUTSIDE="$TESTROOT/soleur-sbx.out.CCCCCCCC"; mkdir -p "$OUTSIDE"; mk_valid_marker "$OUTSIDE"
expect_refused "valid marker + name but realpath is outside every scratch base" "$OUTSIDE"
GARBAGE="$DISK_BASE/soleur-sbx.garb.DDDDDDDD"; mkdir -p "$GARBAGE"; printf 'hello\n' > "$GARBAGE/.soleur-owned"
expect_refused "marker present but malformed" "$GARBAGE"
SYMTGT="$DISK_BASE/soleur-sbx.tgt.EEEEEEEE"; mkdir -p "$SYMTGT"; mk_valid_marker "$SYMTGT"
SYMLNK="$DISK_BASE/soleur-sbx.lnk.FFFFFFFF"; ln -s "$SYMTGT" "$SYMLNK"
cases=$((cases + 1)); rc=0
soleur_sandbox_rm "$SYMLNK" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && -d "$SYMTGT" ]]; then pass "refuses: a symlink named like a sandbox (target intact)"; else fail "did NOT refuse a symlinked sandbox path (rc=$rc)"; fi
cases=$((cases + 1)); rc=0
soleur_sandbox_rm "" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then pass "refuses: empty argument"; else fail "empty argument accepted"; fi
cases=$((cases + 1)); rc=0
(cd "$DISK_BASE" && soleur_sandbox_rm "soleur-sbx.nomark.AAAAAAAA" >/dev/null 2>&1) || rc=$?
if [[ "$rc" -ne 0 && -e "$UNMARKED" ]]; then pass "refuses: relative path"; else fail "relative path accepted (rc=$rc)"; fi
cases=$((cases + 1)); rc=0
soleur_sandbox_rm "$DISK_BASE" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && -d "$DISK_BASE" ]]; then pass "refuses: the scratch base itself"; else fail "scratch base itself accepted (rc=$rc)"; fi

echo "== new fails closed without a disk-backed base =="
cases=$((cases + 1)); rc=0
( _soleur_sandbox_fstype() { printf 'tmpfs'; }; SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new tm >/dev/null 2>"$TESTROOT/tm.err" ) || rc=$?
tm_left="$(find "$DISK_BASE" -maxdepth 1 -name 'soleur-sbx.tm.*' | wc -l | tr -d ' ')"
if [[ "$rc" -ne 0 && "$tm_left" == "0" ]]; then pass "new refuses (rc!=0) when every candidate base is tmpfs, allocating nothing"; else fail "new did not fail closed on tmpfs-only (rc=$rc left=$tm_left)"; fi
cases=$((cases + 1)); rc=0
( SOLEUR_SANDBOX_BASES="$TESTROOT/does-not-exist" SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new nb >/dev/null 2>&1 ) || rc=$?
if [[ "$rc" -ne 0 ]]; then pass "new refuses when no candidate base exists"; else fail "new succeeded with no usable base"; fi
cases=$((cases + 1)); rc=0
SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new '../evil' >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then pass "new rejects a label with path separators"; else fail "path-traversal label accepted"; fi

echo "== size on the REAL repo (this tree, dirty state included) =="
cases=$((cases + 1))
REAL=""
if REAL="$(cd "$REPO_ROOT" && soleur_sandbox_new real 2>"$TESTROOT/real.err")"; then
  kb="$(du -sk "$REAL" | cut -f1)"
  if [[ "$kb" -lt $((320 * 1024)) ]]; then pass "real-repo sandbox is ${kb} KB (< 320 MB)"; else fail "real-repo sandbox is ${kb} KB (>= 320 MB)"; fi
  cases=$((cases + 1))
  if [[ ! -e "$REAL/.git" && ! -e "$REAL/knowledge-base" ]]; then pass "real-repo sandbox has no .git and no knowledge-base/"; else fail "real-repo sandbox carries .git or knowledge-base/"; fi
  cases=$((cases + 1))
  if soleur_sandbox_rm "$REAL" >/dev/null 2>&1 && [[ ! -e "$REAL" ]]; then pass "real-repo sandbox removed via soleur_sandbox_rm"; else fail "real-repo sandbox not removed"; fi
else
  fail "new failed on the real repo: $(head -3 "$TESTROOT/real.err" | tr '\n' ' ')"
fi

echo "== CLI: new prints the path, rm takes the path (cross-Bash-call contract) =="
cases=$((cases + 1))
CLI_OUT="" ; rc=0
CLI_OUT="$(cd "$SRC" && bash "$CLI" new cli 2>"$TESTROOT/cli.err")" || rc=$?
if [[ "$rc" -eq 0 && "$CLI_OUT" == "$DISK_BASE"/soleur-sbx.cli.???????? && -d "$CLI_OUT" ]]; then
  pass "CLI new prints exactly the sandbox path on stdout"
  cases=$((cases + 1)); rc=0
  # A different process: the path alone must be enough to remove it.
  bash "$CLI" rm "$CLI_OUT" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && ! -e "$CLI_OUT" ]]; then pass "CLI rm <path> removes it from a separate invocation"; else fail "CLI rm failed (rc=$rc)"; fi
else
  fail "CLI new failed or printed unexpected stdout (rc=$rc out='$CLI_OUT')"
fi
cases=$((cases + 1)); rc=0
bash "$CLI" bogus >/dev/null 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "CLI unknown subcommand exits 2"; else fail "CLI unknown subcommand rc=$rc (want 2)"; fi
cases=$((cases + 1)); rc=0
bash "$CLI" rm "$UNMARKED" >/dev/null 2>&1 || rc=$?
if [[ "$rc" -ne 0 && -e "$UNMARKED" ]]; then pass "CLI rm refuses an unmarked path"; else fail "CLI rm accepted an unmarked path (rc=$rc)"; fi

echo
if [[ "$fails" -eq 0 ]]; then
  echo "PASS: $pass_n checks across $cases cases"
  exit 0
fi
echo "FAIL: $fails failed of $cases cases ($pass_n ok)" >&2
exit 1
