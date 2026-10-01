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
EVIL_BASE=""
WARN_BASE=""
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
  if [[ -n "$DISK_BASE" ]]; then
    assert_fixture_dir "$DISK_BASE"
    rm -rf "$DISK_BASE"
  fi
  if [[ -n "$EVIL_BASE" ]]; then
    assert_fixture_dir "$EVIL_BASE"
    rm -rf "$EVIL_BASE"
  fi
  if [[ -n "$WARN_BASE" ]]; then
    assert_fixture_dir "$WARN_BASE"
    rm -rf "$WARN_BASE"
  fi
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
# SBX_TEST_CANDIDATES (space-separated) exists so the CI-vs-local skip policy below is itself
# testable (the self-invocation arm near the end points it at nothing).
read -r -a _cands <<< "${SBX_TEST_CANDIDATES:-/var/tmp ${XDG_CACHE_HOME:-$HOME/.cache} $HOME}"
for cand in "${_cands[@]}"; do
  if [[ -d "$cand" && -w "$cand" ]]; then
    fst="$(findmnt -no FSTYPE --target "$cand" 2>/dev/null || true)"
    if [[ -n "$fst" && "$fst" != "tmpfs" && "$fst" != "ramfs" ]]; then
      DISK_BASE="$(mktemp -d "$cand/soleur-sandbox-test.XXXXXXXX")"; break
    fi
  fi
done
if [[ -z "$DISK_BASE" ]]; then
  # A vacuous pass on CI is the defect: every arm below would be silently skipped while the
  # job reads green. CI fails; a developer box on all-tmpfs skips LOUDLY (0 cases run).
  if [[ -n "${CI:-}" ]]; then
    echo "FAIL: no non-tmpfs writable dir on CI — the sandbox allocator arms cannot run (a vacuous pass is the defect)" >&2
    exit 1
  fi
  echo "SKIPPED: no non-tmpfs writable dir — 0 sandbox allocator cases ran (NOT a pass; run on a host with a disk-backed /var/tmp or ~/.cache)" >&2
  exit 0
fi
export SOLEUR_SANDBOX_BASES="$DISK_BASE"

# A fixture repo with a dirty tree: tracked + modified, tracked + deleted, untracked,
# gitignored, a knowledge-base dir, and a node_modules dir.
SRC="$TESTROOT/src"
assert_fixture_dir "$SRC"
mkdir -p "$SRC/knowledge-base" "$SRC/node_modules/pkg" "$SRC/sub" "$SRC/apps/web/node_modules/pkg"
git -C "$SRC" init -q
printf 'node_modules/\n*.log\n' > "$SRC/.gitignore"
printf 'clean\n' > "$SRC/a.txt"
printf 'gone\n' > "$SRC/d.txt"
printf 'kb\n' > "$SRC/knowledge-base/k.md"
printf 'nested\n' > "$SRC/sub/n.txt"
printf 'nm\n' > "$SRC/node_modules/pkg/index.js"
printf 'appnm\n' > "$SRC/apps/web/node_modules/pkg/index.js"
printf '{}\n' > "$SRC/apps/web/package.json"
git -C "$SRC" add -A
git -C "$SRC" commit -q -m fixture
printf 'DIRTY-EDIT\n' > "$SRC/a.txt"          # modified tracked
rm -f "$SRC/d.txt"                              # deleted tracked
printf 'untracked\n' > "$SRC/u.txt"             # untracked, not ignored
printf 'ignored\n' > "$SRC/ign.log"             # ignored
# A hostile/accidental UNTRACKED .soleur-owned in the source: if the tar stream carried it, it
# would be extracted AFTER the allocator's marker and overwrite it (pid=1 => an immortal dir).
printf 'pid=1\nschema=1\nns=pid:[planted]\n' > "$SRC/.soleur-owned"

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
  if ! grep -Fq 'planted' "$SBX/.soleur-owned" && ! grep -Fxq 'pid=1' "$SBX/.soleur-owned" && grep -Eq '^ns=pid:\[[0-9]+\]$' "$SBX/.soleur-owned"; then
    pass "a .soleur-owned planted in the SOURCE tree does not overwrite the allocator's marker"
  else fail "planted source .soleur-owned overwrote the sandbox marker: $(tr '\n' ' ' < "$SBX/.soleur-owned")"; fi
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

echo "== new --link-node-modules from a cwd that is NOT the source tree =="
# The apps/*/node_modules glob must expand under the SOURCE tree, not the caller's cwd.
ELSEWHERE="$TESTROOT/elsewhere"; assert_fixture_dir "$ELSEWHERE"; mkdir -p "$ELSEWHERE"
cases=$((cases + 1)); SBX2B=""
if SBX2B="$(cd "$ELSEWHERE" && SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new lnk2 --link-node-modules 2>/dev/null)"; then
  if [[ -L "$SBX2B/apps/web/node_modules" && "$(readlink "$SBX2B/apps/web/node_modules")" == "$SRC/apps/web/node_modules" ]]; then
    pass "apps/<x>/node_modules is linked when cwd != source (glob anchored at the source tree)"
  else fail "apps/web/node_modules not linked from a foreign cwd"; fi
  cases=$((cases + 1))
  if [[ -L "$SBX2B/node_modules" ]]; then pass "root node_modules also linked from a foreign cwd"; else fail "root node_modules not linked from a foreign cwd"; fi
  soleur_sandbox_rm "$SBX2B" >/dev/null 2>&1 || true
else
  fail "new --link-node-modules from a foreign cwd returned non-zero"
fi

echo "== owner pid override =="
cases=$((cases + 1))
SBX3=""
if SBX3="$(SOLEUR_SCRATCH_OWNER_PID=424242 new_sbx own)" && grep -Fxq 'pid=424242' "$SBX3/.soleur-owned"; then
  pass "SOLEUR_SCRATCH_OWNER_PID wins for the marker pid"
else fail "owner pid override not honored"; fi
[[ -n "$SBX3" ]] && soleur_sandbox_rm "$SBX3" >/dev/null 2>&1 || true

echo "== owner pid: ppid-walk to the first non-shell ancestor (not \$\$, not \$PPID) =="
# python3 -> bash -c -> bash inner.sh: the allocating shell has $$ = inner, $PPID = the middle
# shell; only the documented walk reaches python (comm python3, not a shell/env wrapper).
cat > "$TESTROOT/ow-inner.sh" <<'EOF_INNER'
#!/usr/bin/env bash
source "$1"
soleur_sandbox_new ow
EOF_INNER
OW_PIDFILE="$TESTROOT/ow.pid"; SBX_OW=""
if command -v python3 >/dev/null 2>&1; then
  SBX_OW="$(SOLEUR_SANDBOX_SRC="$SRC" python3 -c '
import os, subprocess, sys
open(sys.argv[1], "w").write(str(os.getpid()))
r = subprocess.run(["bash", "-c", "bash \"$1\" \"$2\"; exit $?", "_", sys.argv[2], sys.argv[3]], capture_output=True, text=True)
sys.stdout.write(r.stdout)
' "$OW_PIDFILE" "$TESTROOT/ow-inner.sh" "$LIB" 2>/dev/null || true)"
fi
cases=$((cases + 1))
if [[ -n "$SBX_OW" && -d "$SBX_OW" && -f "$OW_PIDFILE" ]]; then
  ow_py="$(cat "$OW_PIDFILE")"; ow_mk="$(sed -n 's/^pid=//p' "$SBX_OW/.soleur-owned")"
  if [[ -n "$ow_py" && "$ow_mk" == "$ow_py" ]]; then pass "marker pid ($ow_mk) is the first non-shell ancestor (the python3 parent), skipping both wrapper shells"
  else fail "marker pid '$ow_mk' != documented ancestor '$ow_py' (ppid-walk replaced by \$\$ / \$PPID?)"; fi
  soleur_sandbox_rm "$SBX_OW" >/dev/null 2>&1 || true
else
  fail "owner-pid probe could not allocate (python3 missing or new failed)"
fi

echo "== a sandbox whose owner is DEAD classifies marker:<pid> and its owner reads dead =="
sleep 0 & DEADP=$!; wait "$DEADP" 2>/dev/null || true
SBX_D=""
cases=$((cases + 1))
if SBX_D="$(SOLEUR_SCRATCH_OWNER_PID="$DEADP" new_sbx dead)"; then
  TCLIB="$REPO_ROOT/plugins/soleur/scripts/lib/tmp-classify.sh"
  cls_d="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$TESTROOT/dead-ledger.log" XDG_STATE_HOME="$TESTROOT/dead-state" TMP_CLASSIFY_AGE_FLOOR_MIN=0 bash -c 'source "$1"; tc_classify_entry "$2"' _ "$TCLIB" "$SBX_D" 2>/dev/null || true)"
  if [[ "$cls_d" == "marker:$DEADP" ]]; then pass "dead-owner sandbox classifies marker:$DEADP (the reapers can attribute it)"; else fail "dead-owner sandbox classified [$cls_d], want marker:$DEADP"; fi
  cases=$((cases + 1))
  # The reap chain's first two conjuncts, without the (slow, whole-/proc) in-use map the full
  # tc_reap_decide builds: the declared owner resolves from the marker and is NOT alive.
  verdict_d="$(env -i PATH="$PATH" HOME="$HOME" SOLEUR_PURGE_LEDGER="$TESTROOT/dead-ledger.log" XDG_STATE_HOME="$TESTROOT/dead-state" bash -c 'source "$1"; if tc_owner_pid_verify "$2"; then if tc_owner_alive "$TC_PID"; then echo "alive:$TC_PID"; else echo "dead:$TC_PID:$TC_DECL_KIND"; fi; else echo "unverified"; fi' _ "$TCLIB" "$SBX_D" 2>/dev/null || true)"
  if [[ "$verdict_d" == "dead:$DEADP:marker" ]]; then pass "owner resolves from the marker and reads DEAD (reap-eligible by the declared-owner conjuncts)"; else fail "owner verdict [$verdict_d] for a dead-owner sandbox, want dead:$DEADP:marker"; fi
  soleur_sandbox_rm "$SBX_D" >/dev/null 2>&1 || true
else
  fail "could not allocate the dead-owner sandbox"
fi

echo "== rm refusals (each leaves the dir in place) =="
mk_valid_marker() { printf 'pid=%s\nschema=1\nns=pid:[1]\n' "$$" > "$1/.soleur-owned"; }
expect_refused() { # description dir
  local desc="$1" d="$2" rc=0
  cases=$((cases + 1))
  soleur_sandbox_rm "$d" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -ne 0 && -e "$d" ]]; then pass "refuses: $desc"; else fail "did NOT refuse: $desc (rc=$rc)"; fi
}
assert_fixture_dir "$DISK_BASE"
UNMARKED="$DISK_BASE/soleur-sbx.nomark.AAAAAAAA"; assert_fixture_dir "$UNMARKED"; mkdir -p "$UNMARKED"; printf 'x\n' > "$UNMARKED/keep"
expect_refused "soleur-sbx name but no marker" "$UNMARKED"
BADNAME="$DISK_BASE/other.BBBBBBBB"; mkdir -p "$BADNAME"; mk_valid_marker "$BADNAME"
expect_refused "valid marker but name is not soleur-sbx.*" "$BADNAME"
OUTSIDE="$TESTROOT/soleur-sbx.out.CCCCCCCC"; mkdir -p "$OUTSIDE"; mk_valid_marker "$OUTSIDE"
expect_refused "valid marker + name but realpath is outside every scratch base" "$OUTSIDE"
GARBAGE="$DISK_BASE/soleur-sbx.garb.DDDDDDDD"; assert_fixture_dir "$GARBAGE"; mkdir -p "$GARBAGE"; printf 'hello\n' > "$GARBAGE/.soleur-owned"
expect_refused "marker present but malformed" "$GARBAGE"
# One fixture per conjunct: GARBAGE fails pid= AND schema= at once, so on its own either
# check could be deleted unnoticed. Each fixture below is valid in every OTHER respect.
NOSCHEMA="$DISK_BASE/soleur-sbx.noschema.LLLLLLLL"; assert_fixture_dir "$NOSCHEMA"; mkdir -p "$NOSCHEMA"; printf 'keep\n' > "$NOSCHEMA/keep"
assert_fixture_dir "$NOSCHEMA"; printf 'pid=%s\nns=pid:[1]\n' "$$" > "$NOSCHEMA/.soleur-owned"
expect_refused "valid pid= but NO schema=1" "$NOSCHEMA"
NOPID="$DISK_BASE/soleur-sbx.nopid.MMMMMMMM"; assert_fixture_dir "$NOPID"; mkdir -p "$NOPID"; printf 'keep\n' > "$NOPID/keep"
assert_fixture_dir "$NOPID"; printf 'schema=1\nns=pid:[1]\n' > "$NOPID/.soleur-owned"
expect_refused "valid schema=1 but NO pid=" "$NOPID"
NONS="$DISK_BASE/soleur-sbx.nons.NNNNNNNN"; assert_fixture_dir "$NONS"; mkdir -p "$NONS"; printf 'keep\n' > "$NONS/keep"
assert_fixture_dir "$NONS"; printf 'pid=%s\nschema=1\n' "$$" > "$NONS/.soleur-owned"
expect_refused "valid pid= + schema=1 but NO ns= (the classifier would veto it)" "$NONS"
SYMMK="$DISK_BASE/soleur-sbx.symmk.OOOOOOOO"; assert_fixture_dir "$SYMMK"; mkdir -p "$SYMMK"; printf 'keep\n' > "$SYMMK/keep"
printf 'pid=%s\nschema=1\nns=pid:[1]\n' "$$" > "$TESTROOT/real-marker"; ln -s "$TESTROOT/real-marker" "$SYMMK/.soleur-owned"
expect_refused "marker is a SYMLINK to an otherwise valid marker" "$SYMMK"
# Prefix-sibling parent: $DISK_BASE-evil starts with the base's path but is NOT the base.
EVIL_BASE="${DISK_BASE}-evil"; assert_fixture_dir "$EVIL_BASE"; mkdir -p "$EVIL_BASE/soleur-sbx.evil.PPPPPPPP"; mk_valid_marker "$EVIL_BASE/soleur-sbx.evil.PPPPPPPP"
expect_refused "valid sandbox whose parent is a PREFIX-sibling of the base ($DISK_BASE-evil)" "$EVIL_BASE/soleur-sbx.evil.PPPPPPPP"
mkdir -p "$DISK_BASE/nest/soleur-sbx.deep.QQQQQQQQ"; mk_valid_marker "$DISK_BASE/nest/soleur-sbx.deep.QQQQQQQQ"
expect_refused "valid sandbox nested one level BELOW the base (parent != base)" "$DISK_BASE/nest/soleur-sbx.deep.QQQQQQQQ"
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

echo "== rm: trailing slash accepted, already-removed path named as such =="
cases=$((cases + 1)); SBX_TS=""; rc=0
SBX_TS="$(new_sbx ts)" || true
if [[ -n "$SBX_TS" ]]; then
  soleur_sandbox_rm "$SBX_TS/" >"$TESTROOT/ts.out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && ! -e "$SBX_TS" ]]; then pass "rm '<sandbox>/' (trailing slash) removes the sandbox"; else fail "rm with a trailing slash refused or left the dir (rc=$rc: $(head -c 200 "$TESTROOT/ts.out"))"; fi
  cases=$((cases + 1)); rc=0
  soleur_sandbox_rm "$SBX_TS" >"$TESTROOT/gone.out" 2>&1 || rc=$?
  if [[ "$rc" -eq 1 ]] && grep -q 'does not exist' "$TESTROOT/gone.out"; then pass "rm of an already-removed sandbox is rc=1 and says 'does not exist'"; else fail "already-removed rm: rc=$rc msg=$(head -c 200 "$TESTROOT/gone.out")"; fi
else
  fail "could not allocate the trailing-slash sandbox"
fi

echo "== new: a base outside /tmp and /var/tmp warns that only soleur_sandbox_rm reclaims it =="
WARN_BASE="$(mktemp -d "$HOME/.soleur-sbx-warn-test.XXXXXXXX")"
cases=$((cases + 1)); rc=0
( _soleur_sandbox_fstype() { printf 'ext4'; }; SOLEUR_SANDBOX_BASES="$WARN_BASE" SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new wb >"$TESTROOT/wb.out" 2>"$TESTROOT/wb.err" ) || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'WARNING' "$TESTROOT/wb.err" && grep -q 'soleur_sandbox_rm' "$TESTROOT/wb.err"; then pass "non-/tmp, non-/var/tmp base warns (reclaimed only by soleur_sandbox_rm)"; else fail "no reclaim warning for a ~/.cache-style base (rc=$rc: $(head -c 200 "$TESTROOT/wb.err"))"; fi
# Control (unconditional, so the case count is host-independent): the reapers' own scan root /tmp as
# the base must NOT warn. fstype is stubbed (it may be tmpfs here); the one sandbox this allocates
# is removed through the allocator's own remover before the arm ends.
cases=$((cases + 1)); rc=0
( _soleur_sandbox_fstype() { printf 'ext4'; }; SOLEUR_SANDBOX_BASES="/tmp" SOLEUR_SANDBOX_SRC="$SRC" soleur_sandbox_new wc >"$TESTROOT/wc.out" 2>"$TESTROOT/wc.err" ) || rc=$?
CTL_SBX="$(cat "$TESTROOT/wc.out" 2>/dev/null || true)"
if [[ -n "$CTL_SBX" && -d "$CTL_SBX" ]]; then SOLEUR_SANDBOX_BASES="/tmp" soleur_sandbox_rm "$CTL_SBX" >/dev/null 2>&1 || true; fi
if [[ "$rc" -eq 0 ]] && ! grep -q 'reclaimed only' "$TESTROOT/wc.err"; then pass "control: a base under /tmp or /var/tmp (the reapers' scan roots) does not warn"; else fail "control base warned or failed (rc=$rc)"; fi
echo "== default bases honour XDG_CACHE_HOME (like soleur_scratch_root) =="
cases=$((cases + 1))
xdg_out="$(unset SOLEUR_SANDBOX_BASES; XDG_CACHE_HOME=/xdg/cache HOME=/h _soleur_sandbox_bases | tr '\n' ' ')"
noxdg_out="$(unset SOLEUR_SANDBOX_BASES XDG_CACHE_HOME; HOME=/h _soleur_sandbox_bases | tr '\n' ' ')"
if [[ "$xdg_out" == *"/xdg/cache"* && "$xdg_out" != *"/h/.cache"* && "$noxdg_out" == *"/h/.cache"* ]]; then pass "XDG_CACHE_HOME replaces \$HOME/.cache in the default base list"; else fail "default bases ignore XDG_CACHE_HOME (xdg='$xdg_out' noxdg='$noxdg_out')"; fi

echo "== scratch-session cleanup deletes only the root begin() allocated =="
# The exported SOLEUR_SCRATCH_SESSION_ROOT is attacker/caller-writable state; a '..' in it passes
# a */soleur-run.* substring pin. The delete must be pinned to the path begin() allocated.
VICTIM="$DISK_BASE/victim"; assert_fixture_dir "$VICTIM"; mkdir -p "$VICTIM"; printf 'precious\n' > "$VICTIM/data"
cases=$((cases + 1)); rc=0
bash -c '
  set -euo pipefail
  source "$1"
  soleur_scratch_session_begin "$2"
  own="$SOLEUR_SCRATCH_SESSION_ROOT"
  printf "%s" "$own" > "$3"
  SOLEUR_SCRATCH_SESSION_ROOT="$own/../victim"
  _soleur_scratch_cleanup
' _ "$LIB" "$DISK_BASE" "$TESTROOT/own-root" >/dev/null 2>&1 || rc=$?
own_root="$(cat "$TESTROOT/own-root" 2>/dev/null || true)"
if [[ "$rc" -eq 0 && -f "$VICTIM/data" ]]; then pass "cleanup with a '..'-redirected SOLEUR_SCRATCH_SESSION_ROOT leaves the victim intact"; else fail "cleanup followed the exported var out of its root (rc=$rc, victim data missing=$([[ -f "$VICTIM/data" ]] && echo no || echo YES))"; fi
cases=$((cases + 1))
if [[ -n "$own_root" && ! -e "$own_root" ]]; then pass "control: the begin()-allocated root itself IS deleted by the same cleanup"; else fail "cleanup did not delete its own allocated root ($own_root)"; fi
if [[ -n "$own_root" && -d "$own_root" ]]; then
  assert_fixture_dir "$own_root"
  rm -rf "$own_root"
fi

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
# Environment-independent bound: the sandbox is a copy of exactly the files git would list, so the
# expected size is du of THAT set (+25% + 32 MB of directory/block slack) — not a fixed number that
# rots as the repo grows. The size is reported either way.
cases=$((cases + 1))
REAL=""
if REAL="$(cd "$REPO_ROOT" && soleur_sandbox_new real 2>"$TESTROOT/real.err")"; then
  kb="$(du -sk "$REAL" | cut -f1)"
  exp_kb="$(cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard -- . ':(exclude)knowledge-base' \
    | while IFS= read -r -d '' f; do if [[ -e "$f" || -L "$f" ]]; then printf '%s\0' "$f"; fi; done \
    | { xargs -0 -r du -sk 2>/dev/null || true; } | awk '{ s += $1 } END { print s + 0 }')"
  bound_kb=$(( exp_kb * 125 / 100 + 32 * 1024 ))
  echo "  [info] real-repo sandbox: ${kb} KB (expected from git ls-files: ${exp_kb} KB, bound ${bound_kb} KB)"
  if [[ "$exp_kb" -gt 0 && "$kb" -le "$bound_kb" ]]; then pass "real-repo sandbox is ${kb} KB, within the bound derived from the tracked+untracked file set"; else fail "real-repo sandbox is ${kb} KB vs bound ${bound_kb} KB (expected ${exp_kb} KB from git ls-files)"; fi
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

echo "== skip policy: no disk-backed base FAILS on CI and skips loudly (rc 0, never silent) elsewhere =="
cases=$((cases + 1)); rc=0
env CI=1 SBX_TEST_CANDIDATES="$TESTROOT/no-such-dir" bash "${BASH_SOURCE[0]}" >/dev/null 2>"$TESTROOT/skip-ci.err" || rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'FAIL' "$TESTROOT/skip-ci.err"; then pass "CI + no non-tmpfs dir => rc 1 (a vacuous pass is the defect)"; else fail "CI skip policy rc=$rc (want 1)"; fi
cases=$((cases + 1)); rc=0
env -u CI SBX_TEST_CANDIDATES="$TESTROOT/no-such-dir" bash "${BASH_SOURCE[0]}" >/dev/null 2>"$TESTROOT/skip-local.err" || rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'SKIPPED' "$TESTROOT/skip-local.err"; then pass "local + no non-tmpfs dir => rc 0 with a loud SKIPPED line"; else fail "local skip policy rc=$rc (want 0 + SKIPPED)"; fi

echo
# Case floor: the EXACT expected count, compared and exited on directly — deliberately NOT through
# pass()/fail(), so a deleted/short-circuited arm cannot hide behind a green helper tally. Bump in
# lockstep when an arm is added or removed.
EXPECTED_CASES=57
printf 'cases=%s expected=%s\n' "$cases" "$EXPECTED_CASES"
if [[ "$cases" -ne "$EXPECTED_CASES" ]]; then
  printf 'FAIL: ran %s cases, expected exactly %s (an arm was dropped or added without updating EXPECTED_CASES)\n' "$cases" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$fails" -eq 0 ]]; then
  echo "PASS: $pass_n checks across $cases cases"
  exit 0
fi
echo "FAIL: $fails failed of $cases cases ($pass_n ok)" >&2
exit 1
