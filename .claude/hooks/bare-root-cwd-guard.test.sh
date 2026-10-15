#!/usr/bin/env bash
# Tests for .claude/hooks/bare-root-cwd-guard.sh (issue #10383).
#
# Synthesized fixtures only: throwaway repos under one mktemp root, built with git plumbing
# (hash-object / commit-tree / update-ref) so no fixture needs a commit identity of its own.
# No `set -e`: this is an accumulate-then-exit suite, and every deliberately non-zero call is
# captured with `rc=0; x=$(...) || rc=$?` so a failing call cannot abort before it is reported.

set -uo pipefail

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs. Sourced after the
# EXIT trap above on purpose: the lib composes with a trap that already exists.
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/lib/test-incident-sandbox.sh"

HELPER="$SCRIPT_DIR/bare-root-cwd-guard.sh"
MARKER="SOLEUR_BARE_ROOT_CWD source=session-start"

# The shared fixture git environment: sweeps every inherited GIT_* location variable (a hook-
# exported GIT_DIR would otherwise aim these writes at the caller's repo), pins a ceiling,
# config and identity.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "$SCRIPT_DIR/../../plugins/soleur/test/lib/git-fixture-env.sh"
git_fixture_env "$SANDBOX" || { printf '[FATAL] git_fixture_env refused %s\n' "$SANDBOX" >&2; exit 2; }

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
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

command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }
if [[ ! -x "$HELPER" ]]; then
  echo "FAIL: $HELPER not executable or missing — GREEN required"
  exit 1
fi

# --- accounting ---------------------------------------------------------------------------
PASS=0
FAIL=0
FAILURES=()
EXECUTED=()
CUR=""
CASE_N=0
EMPTY_CASES=()

# A case that executed no assertion is an empty case, whatever the totals say.
close_case() {
  if [[ -n "$CUR" ]] && (( CASE_N == 0 )); then EMPTY_CASES+=("$CUR"); fi
}
begin() { close_case; EXECUTED+=("$1"); CUR="$1"; CASE_N=0; }
ok() { PASS=$((PASS + 1)); CASE_N=$((CASE_N + 1)); printf '  ok   %s: %s\n' "$CUR" "$1"; }
bad() { FAIL=$((FAIL + 1)); CASE_N=$((CASE_N + 1)); FAILURES+=("$CUR: $1"); printf '  FAIL %s: %s\n' "$CUR" "$1"; }
eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}

# Instrument self-test: drive each verdict helper once and require its counter to move. A helper
# that silently stopped counting would otherwise report an empty suite as a clean one.
_p=$PASS
_f=$FAIL
CUR="selftest"
ok "selftest-pass" >/dev/null
bad "selftest-fail" >/dev/null
eq "selftest-eq-pass" "a" "a" >/dev/null
eq "selftest-eq-fail" "a" "b" >/dev/null
if (( PASS != _p + 2 || FAIL != _f + 2 )); then
  printf 'FATAL: instrument self-test: ok/bad/eq did not move their counters\n' >&2
  exit 1
fi
PASS=$_p
FAIL=$_f
FAILURES=()
CUR=""
CASE_N=0

# --- fixture builders -----------------------------------------------------------------------
# seed_main <dir>: one empty-tree commit on refs/heads/main, through plumbing only.
seed_main() {
  local d="$1" t c
  assert_fixture_dir "$d"
  t=$(git -C "$d" hash-object -t tree -w /dev/null) || return 1
  c=$(git -C "$d" commit-tree "$t" -m seed) || return 1
  git -C "$d" update-ref refs/heads/main "$c" || return 1
}

# mk_bare_root: the real layout — a normal repo with a `.git` directory and on-disk files, then
# `core.bare true` (same shape as bare-head-self-heal.test.sh's builder; mirrored deliberately:
# a shared helper would couple two suites' fixtures to one definition).
mk_bare_root() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  git -C "$d" config core.bare true || return 1
}

# mk_true_bare: `git init --bare`, gitdir == dir (the second bare shape; out of scope).
mk_true_bare() {
  local d="$1"
  assert_fixture_dir "$d"
  git init -q --bare "$d" || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}

mk_plain() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}

# mk_wtmask: a clone whose EFFECTIVE core.bare reads true only through
# config.worktree (extensions.worktreeConfig + `git config --worktree`). The
# predicate reads the config FILE, so this MUST stay silent — the only fixture
# that distinguishes `git config --file` from an effective-config read
# (#10386 review, mutation survivor).
mk_wtmask() {
  local d="$1"
  mk_plain "$d" || return 1
  git -C "$d" config extensions.worktreeConfig true || return 1
  git -C "$d" config --worktree core.bare true || return 1
}

# mk_imposter: a subdir inside a live worktree carrying a skeleton `.git` dir
# whose config says bare=true but which is NOT the gitdir git resolves — the
# ONLY fixture that exercises the --absolute-git-dir identity term (deleting
# term 3 is otherwise a silent survivor, #10386 review).
mk_imposter() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/sub/.git"
  git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  printf '[core]\n\tbare = true\n' > "$d/sub/.git/config"
}

# run_helper <dir>: sets OUT (stdout) and RC (exit status).
run_helper() {
  RC=0
  OUT=$(bash "$HELPER" "$1" 2>/dev/null) || RC=$?
}

count_marker() {
  awk '/^SOLEUR_BARE_ROOT_CWD /{n++} END{print n+0}' <<<"$1"
}

# --- helper cases ---------------------------------------------------------------------------
echo "bare-root-cwd-guard.test.sh"

begin G1
d="$SANDBOX/g1"; mk_bare_root "$d" || bad "fixture"
run_helper "$d"
eq "bare root fires exactly one marker line" "1" "$(count_marker "$OUT")"
eq "marker first line is the documented literal" "$MARKER" "$(sed -n 1p <<<"$OUT")"
eq "redirect block opens" "[bare-root-cwd]" "$(sed -n 2p <<<"$OUT" | cut -d' ' -f1)"
case "$OUT" in
  *"--yes create"*) ok "redirect names the worktree creation path" ;;
  *) bad "redirect block does not name --yes create" ;;
esac
case "$OUT" in
  *".env"*) ok "block warns the root .env is not project configuration" ;;
  *) bad "block does not warn about .env" ;;
esac
eq "exit status is 0" "0" "$RC"

begin G2
d="$SANDBOX/g2"; mk_true_bare "$d" || bad "fixture"
run_helper "$d"
eq "true bare (gitdir == dir; a mirror or server repo): silent" "" "$OUT"
eq "true bare: exit status is 0" "0" "$RC"

begin G3
d="$SANDBOX/g3"; mk_plain "$d" || bad "fixture"
run_helper "$d"
eq "plain clone: silent" "" "$OUT"
eq "plain clone: exit status is 0" "0" "$RC"

begin G4
root="$SANDBOX/g4"; mk_bare_root "$root" || bad "fixture"
wt="$SANDBOX/g4-wt"
git -C "$root" worktree add -q -b wtbranch "$wt" main || bad "worktree fixture"
run_helper "$wt"
eq "linked worktree of a bare repo: silent" "" "$OUT"
eq "linked worktree: exit status is 0" "0" "$RC"
run_helper "$root"
eq "control: the bare root itself still fires" "1" "$(count_marker "$OUT")"

begin G5
d="$SANDBOX/g5"; mk_plain "$d" || bad "fixture"
printf 'not a git config\n' > "$d/.git/config"
run_helper "$d"
eq "masked/corrupt config: silent (never a false marker)" "" "$OUT"
eq "masked config: exit status is 0" "0" "$RC"

begin G6
r="$SANDBOX/g6-real"; mk_bare_root "$r" || bad "fixture"
sdir="$SANDBOX/g6-sym"; mkdir -p "$sdir"
ln -s "$r/.git" "$sdir/.git"
run_helper "$sdir"
eq "a .git SYMLINK to another root's .git: silent" "" "$OUT"
eq "symlinked .git: exit status is 0" "0" "$RC"
run_helper "$r"
eq "control: the real bare root still fires" "1" "$(count_marker "$OUT")"

begin G7
d="$SANDBOX/g7-notrepo"; mkdir -p "$d"
run_helper "$d"
eq "not a repo: silent" "" "$OUT"
eq "not a repo: exit status is 0" "0" "$RC"
b="$SANDBOX/g7b"; mk_bare_root "$b" || bad "fixture"
RC=0
OUT=$(cd "$b" && bash "$HELPER" "$SANDBOX/g7-does-not-exist" 2>/dev/null) || RC=$?
eq "nonexistent dir: silent (a failed cd must not fall through to the caller's own repo)" "" "$OUT"
eq "nonexistent dir: exit status is 0" "0" "$RC"

begin G8
a="$SANDBOX/g8a"; mk_bare_root "$a" || bad "fixture"
b="$SANDBOX/g8b"; mk_plain "$b" || bad "fixture"
RC=0
OUT=$(GIT_DIR="$b/.git" bash "$HELPER" "$a" 2>/dev/null) || RC=$?
eq "inherited GIT_DIR: the NAMED repo is still detected" "1" "$(count_marker "$OUT")"
RC=0
OUT=$(GIT_DIR="$a/.git" bash "$HELPER" "$b" 2>/dev/null) || RC=$?
eq "inherited GIT_DIR: a plain clone is not retroactively marked" "" "$OUT"

begin G9
d="$SANDBOX/g9"; mk_bare_root "$d" || bad "fixture"
run_helper "$d"
lines=$(wc -l <<<"$OUT" | tr -d ' ')
if (( lines <= 12 )); then ok "output is bounded (${lines} lines)"; else bad "output is unbounded (${lines} lines)"; fi
RC=0
OUT=$(cd "$d" && bash "$HELPER" 2>/dev/null) || RC=$?
eq "no-arg run defaults to \$PWD and fires" "1" "$(count_marker "$OUT")"
p="$SANDBOX/g9p"; mk_plain "$p" || bad "fixture"
RC=0
OUT=$(cd "$p" && bash "$HELPER" 2>/dev/null) || RC=$?
eq "no-arg run at a plain clone: silent" "" "$OUT"

begin G10
d="$SANDBOX/g10"; mk_wtmask "$d" || bad "fixture"
run_helper "$d"
eq "worktreeConfig-masked bare: silent (predicate reads the config FILE)" "" "$OUT"
eq "worktreeConfig: exit status is 0" "0" "$RC"

begin G11
d="$SANDBOX/g11"; mk_imposter "$d" || bad "fixture"
run_helper "$d/sub"
eq "imposter .git inside a worktree: silent (gitdir identity term)" "" "$OUT"
eq "imposter: exit status is 0" "0" "$RC"
run_helper "$d"
eq "control: the host plain clone is also silent" "" "$OUT"

begin G12
d="$SANDBOX/g12"$'\n'"INJECTED-LINE"; mk_bare_root "$d" || bad "fixture"
run_helper "$d"
eq "a path containing a newline still detects" "1" "$(count_marker "$OUT")"
injected=$(sed -n '2,$p' <<<"$OUT" | grep -cv '^\[bare-root-cwd\] ' || true)
eq "the newline in the path cannot inject an unprefixed line" "0" "$injected"

# --- parity anchor ----------------------------------------------------------------------------
# The SAME three-term predicate is inlined in git-repo-readiness-diag.sh (the plugin script
# cannot depend on a repo hook). This row pins the two copies' observable agreement: every
# fixture above that fires here must fire there and vice versa, so the diag suite's fixtures
# and this suite's stay one population. The byte-level parity check lives in
# plugins/soleur/test/git-repo-readiness-diag.test.sh (the consumer side).
begin G13
diag="$(cd -P "$SCRIPT_DIR/../../plugins/soleur/skills/git-worktree/scripts" && pwd)/git-repo-readiness-diag.sh"
if [[ -x "$diag" ]]; then
  d="$SANDBOX/g13"; mk_bare_root "$d" || bad "fixture"
  RC=0
  DOUT=$(cd "$d" && bash "$diag" 2>/dev/null) || RC=$?
  case "$DOUT" in
    *SOLEUR_GIT_REPO_READY=true*) ok "diag still reports the bare root READY" ;;
    *) bad "diag lost its READY verdict at the bare root" ;;
  esac
else
  bad "diag script not executable at $diag"
fi

# --- totals -----------------------------------------------------------------------------------
close_case
printf '\n%d passed, %d failed (%d cases)\n' "$PASS" "$FAIL" "${#EXECUTED[@]}"
if (( ${#EMPTY_CASES[@]} > 0 )); then
  printf 'EMPTY CASES (executed no assertion): %s\n' "${EMPTY_CASES[*]}" >&2
  FAIL=$((FAIL + ${#EMPTY_CASES[@]}))
fi
if (( FAIL > 0 )); then
  printf 'failures:\n' >&2
  printf '  %s\n' "${FAILURES[@]}" >&2
  exit 1
fi
exit 0
