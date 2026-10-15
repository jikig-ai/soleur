#!/usr/bin/env bash
# Tests for plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh —
# the SOLEUR_BARE_ROOT_CWD source=readiness-diag arm (#10383) and predicate parity
# with .claude/hooks/bare-root-cwd-guard.sh.
#
# Synthesized fixtures only. No `set -e`: accumulate-then-exit; every deliberately
# non-zero call is captured with `rc=0; x=$(...) || rc=$?`.

set -uo pipefail

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DIAG="$SCRIPT_DIR/../skills/git-worktree/scripts/git-repo-readiness-diag.sh"
GUARD="$SCRIPT_DIR/../../../.claude/hooks/bare-root-cwd-guard.sh"

# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"
git_fixture_env "$SANDBOX" || { printf '[FATAL] git_fixture_env refused %s\n' "$SANDBOX" >&2; exit 2; }

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
[[ -x "$DIAG" ]] || { echo "FAIL: $DIAG not executable or missing"; exit 1; }
[[ -x "$GUARD" ]] || { echo "FAIL: $GUARD not executable or missing"; exit 1; }

PASS=0; FAIL=0; FAILURES=(); CUR=""; CASE_N=0
begin() { CUR="$1"; CASE_N=0; }
ok() { PASS=$((PASS + 1)); CASE_N=$((CASE_N + 1)); printf '  ok   %s: %s\n' "$CUR" "$1"; }
bad() { FAIL=$((FAIL + 1)); CASE_N=$((CASE_N + 1)); FAILURES+=("$CUR: $1"); printf '  FAIL %s: %s\n' "$CUR" "$1"; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }

seed_main() {
  local d="$1" t c
  assert_fixture_dir "$d"
  t=$(git -C "$d" hash-object -t tree -w /dev/null) || return 1
  c=$(git -C "$d" commit-tree "$t" -m seed) || return 1
  git -C "$d" update-ref refs/heads/main "$c" || return 1
}
mk_bare_root() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d"; git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  git -C "$d" config core.bare true || return 1
}
mk_plain() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d"; git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}
run_diag() { RC=0; OUT=$(cd "$1" && bash "$DIAG" 2>/dev/null) || RC=$?; }

echo "git-repo-readiness-diag.test.sh"

begin D1
d="$SANDBOX/d1"; mk_bare_root "$d" || bad "fixture"
run_diag "$d"
case "$OUT" in
  *SOLEUR_GIT_REPO_READY=true*) ok "bare root still READY" ;;
  *) bad "bare root lost READY ($OUT)" ;;
esac
case "$OUT" in
  *SOLEUR_BARE_ROOT_CWD\ source=readiness-diag*) ok "bare root emits the diag marker" ;;
  *) bad "bare root missing the diag marker ($OUT)" ;;
esac

begin D2
d="$SANDBOX/d2"; mk_plain "$d" || bad "fixture"
run_diag "$d"
case "$OUT" in
  *SOLEUR_GIT_REPO_READY=true*) ok "worktree still READY" ;;
  *) bad "worktree lost READY" ;;
esac
case "$OUT" in
  *SOLEUR_BARE_ROOT_CWD*) bad "plain clone emitted the marker" ;;
  *) ok "plain clone emits READY only, no marker" ;;
esac

begin D3
d="$SANDBOX/d3"; mk_plain "$d" || bad "fixture"
printf 'not a git config\n' > "$d/.git/config"
run_diag "$d"
case "$OUT" in
  *SOLEUR_BARE_ROOT_CWD*) bad "masked-config clone emitted the marker" ;;
  *) ok "masked config: no marker" ;;
esac

begin D4
root="$SANDBOX/d4"; mk_bare_root "$root" || bad "fixture"
wt="$SANDBOX/d4-wt"
git -C "$root" worktree add -q -b wtbranch "$wt" main || bad "worktree fixture"
run_diag "$wt"
case "$OUT" in
  *SOLEUR_GIT_REPO_READY=true*) ok "linked worktree READY" ;;
  *) bad "linked worktree lost READY" ;;
esac
case "$OUT" in
  *SOLEUR_BARE_ROOT_CWD*) bad "linked worktree of a bare repo emitted the marker" ;;
  *) ok "linked worktree: no marker" ;;
esac

begin D5
# Parity: the diag copy and the hook copy must agree on every fixture class the
# hook suite enumerates. Derive it behaviourally, not by grep: run both on the
# same fixtures and require identical fire/no-fire verdicts.
parity_ok=1
for shape in bare plain masked sym nonrepo; do
  case "$shape" in
    bare)    d="$SANDBOX/p-bare"; mk_bare_root "$d" ;;
    plain)   d="$SANDBOX/p-plain"; mk_plain "$d" ;;
    masked)  d="$SANDBOX/p-masked"; mk_plain "$d"; printf 'bad\n' > "$d/.git/config" ;;
    sym)     r="$SANDBOX/p-sym-real"; mk_bare_root "$r"; d="$SANDBOX/p-sym"; mkdir -p "$d"; ln -s "$r/.git" "$d/.git" ;;
    nonrepo) d="$SANDBOX/p-nonrepo"; mkdir -p "$d" ;;
  esac
  RC=0; GOUT=$(bash "$GUARD" "$d" 2>/dev/null) || RC=$?
  g_fires=0; [[ "$GOUT" == SOLEUR_BARE_ROOT_CWD* ]] && g_fires=1
  run_diag "$d"
  d_fires=0; [[ "$OUT" == *SOLEUR_BARE_ROOT_CWD* ]] && d_fires=1
  if [[ "$g_fires" != "$d_fires" ]]; then
    parity_ok=0; bad "parity: shape=$shape guard=$g_fires diag=$d_fires"
  fi
done
if [[ "$parity_ok" == "1" ]]; then ok "guard and diag predicates agree on all 5 fixture classes"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then printf 'failures:\n' >&2; printf '  %s\n' "${FAILURES[@]}" >&2; exit 1; fi
exit 0
