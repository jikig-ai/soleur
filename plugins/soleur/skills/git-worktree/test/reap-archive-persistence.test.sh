#!/usr/bin/env bash
# 2026-09-28 reproducer for #9127: cleanup_merged_worktrees archives KB
# artifacts with plain `mv`. Where the artifact is TRACKED (a non-bare clone
# parked on main, a feature-branch checkout, or a bare root's HEAD-materialized
# mirror) the move has no persistence owner: nothing commits it, and the
# SOLEUR-GUARD-MAINRESET `git reset --hard HEAD` — or sync_bare_files'
# checkout-index mirroring — restores the tracked half while the untracked
# archive copy persists. Result: a live+archive twin ("stranded spec").
#
# The fix (ADR-258): every reap archive move persists via the checkout's own
# commit path, or is not made at all.
#   tracked + committable (feature branch) -> `git mv` + a pathspec-scoped
#     `chore(archive-kb)` commit on the current branch (SOLEUR_REAP_ARCHIVE_COMMITTED)
#   tracked + non-committable -> no move, SOLEUR_REAP_ARCHIVE_DEFERRED
#     reason=<main-checkout|detached|unborn|merge-in-progress|bare|
#             git-mv-failed|outside-git-root|unsafe-destination>
#   untracked -> plain `mv`, unchanged (no resurrection mechanism applies)
#
# The existing sibling suites cannot see this class: their fixtures are
# untracked files, where `mv` is tracking-agnostic. Every "tracked" fixture
# below asserts its tracked-ness BEFORE the reap (guard-matrix row 6) so a
# neutered fixture fails loud instead of passing vacuously.
#
# Plan: knowledge-base/project/plans/2026-09-28-fix-reaper-archive-tracked-kb-persistence-plan.md
# Issue: https://github.com/jikig-ai/soleur/issues/9127
#
# Run via:  bash plugins/soleur/skills/git-worktree/test/reap-archive-persistence.test.sh

set -uo pipefail

# Git-location tripwire (#7833). These suites drive worktree-manager.sh, which runs
# `git worktree remove`, `git branch -D` and `git reset --hard` -- the highest-damage git writes
# in the corpus. An inherited GIT_DIR aims all of them at the developer's real repository, so
# this file aborts rather than proceeding. Inline rather than sourcing test-helpers.sh, which
# would also import an assertion framework these suites do not use.
for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
          GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_TEMPLATE_DIR GIT_EXEC_PATH; do
  if [[ -n "${!_v:-}" && "${SOLEUR_GIT_TRIPWIRE_ALLOW:-0}" != "1" ]]; then
    printf 'FATAL: %s started with an inherited git-location environment (%s=%s).\n' \
      "${BASH_SOURCE[0]}" "$_v" "${!_v}" >&2
    printf 'Fix the ENTRY POINT: unset %s && <runner>\n' "$_v" >&2
    exit 97
  fi
done
unset _v

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
WM="$REPO_ROOT/plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh"

PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

TMP=$(mktemp -d) || { echo "FATAL: mktemp -d failed — refusing to run with an empty \$TMP, every fixture path would resolve against /" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# Resolved ONCE, with `pwd -P`: TMPDIR is routinely a symlink, and comparing an
# unresolved $TMP against a resolved toplevel false-FAILS every call.
TMP_REAL="$(cd "$TMP" && pwd -P)" || TMP_REAL=""
case "$TMP_REAL" in
  /*) : ;;
  *)  echo "FATAL: could not resolve the fixture root '$TMP' to an absolute path — refusing, an empty root makes the containment check match everything" >&2
      exit 2 ;;
esac
readonly TMP_REAL

# cd into a NON-BARE fixture, or refuse (see lease-protects-active.test.sh for
# the full rationale: a missing/absent fixture dir leaves git walking up to a
# LIVE repository).
cdx() {
  local target="$1" top
  if ! cd "$target" 2>/dev/null; then
    printf '  FAIL: fixture directory absent: %s\n' "$target" >&2
    printf '        refusing to run fixture commands in %s — that is a LIVE repository.\n' "$PWD" >&2
    : > "$TMP/.cdx-failed"
    exit 90
  fi
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || top=""
  case "${top:-<none>}" in
    "$TMP_REAL"|"$TMP_REAL"/*) return 0 ;;
  esac
  printf '  FAIL: %s exists, but its git toplevel is %s\n' "$target" "${top:-<not a git repository>}" >&2
  printf '        which is OUTSIDE the fixture root %s — refusing, git would write to that repository.\n' "$TMP_REAL" >&2
  : > "$TMP/.cdx-failed"
  exit 90
}

# cd into a BARE fixture, or refuse. A bare repo has no toplevel, so cdx cannot
# guard it; the containment property is identical (resolved path inside $TMP)
# plus a positive bare check so a non-bare dir can never slip this arm.
cdb() {
  local target="$1" resolved
  if ! cd "$target" 2>/dev/null; then
    printf '  FAIL: fixture directory absent: %s\n' "$target" >&2
    printf '        refusing to run fixture commands in %s — that is a LIVE repository.\n' "$PWD" >&2
    : > "$TMP/.cdx-failed"
    exit 90
  fi
  resolved="$(pwd -P)"
  case "$resolved" in
    "$TMP_REAL"|"$TMP_REAL"/*) ;;
    *) printf '  FAIL: %s resolved to %s, OUTSIDE the fixture root %s\n' "$target" "$resolved" "$TMP_REAL" >&2
       : > "$TMP/.cdx-failed"
       exit 90 ;;
  esac
  if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" != "true" ]]; then
    printf '  FAIL: %s is not a bare repository — cdb is the bare-fixture guard; use cdx\n' "$target" >&2
    : > "$TMP/.cdx-failed"
    exit 90
  fi
}

# Bare-`cd "` self-check — same construction as lease-protects-active.test.sh:
# strip comments, join continuations, flag any `cd "` whose logical line is not
# guarded by &&/||/if-while-until or routed through cdx/cdb.
_bare_cd="$(awk '
  BEGIN { start_ln = 1 }
  {
    l = $0
    sub(/(^|[[:space:]])#.*$/, "", l)
    line = line l
    if (sub(/\\[[:space:]]*$/, " ", line)) next
    if (line ~ /(^|[^[:alnum:]_])cd "/ \
        && line !~ /&&/ && line !~ /\|\|/ \
        && line !~ /(^|[[:space:]])(if|while|until)[[:space:]]+!?[[:space:]]*cd[[:space:]]"/ \
        && line !~ /(^|[^[:alnum:]_])(cdx|cdb)[[:space:]]/) print start_ln ": " line
    line = ""; start_ln = NR + 1
  }
' "${BASH_SOURCE[0]}")"
if [[ -n "$_bare_cd" ]]; then
  printf '  FAIL: unguarded cd site(s) in this suite — every fixture cd must go through cdx()/cdb():\n' >&2
  printf '%s\n' "$_bare_cd" >&2
  printf '        A bare cd here runs git in the CALLER CWD when the fixture is missing.\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# The body below is the CANONICAL copy, asserted byte-for-byte against every other copy by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh. Do not reword it in one file only. #7652
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

mk_lease_root() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/leases" "$d/locks" "$d/logs" || return 1
  # Pre-stamp the #7409 first-run arming hold: without it the reaper reports
  # rather than reaps on the first armed run and every assertion below would
  # pass for the wrong reason.
  : > "$d/reaper-armed" || return 1
}

# Build <bare> + <clone> where merged branch feat-victim carries TRACKED kb
# artifacts: a plan file (always) and the spec dir only when mode=tracked
# (mode=untracked writes the spec dir post-merge, never committed).
build_clone() {
  local bare="$1" clone="$2" spec_mode="$3"
  git init --bare -b main "$bare" >/dev/null || return 1
  git clone "$bare" "$clone" >/dev/null 2>&1 || return 1
  ( set -e
    cdx "$clone"
    git config user.email t@t
    git config user.name t
    git config commit.gpgsign false
    git commit --allow-empty -m seed >/dev/null
    git checkout -b feat-victim >/dev/null 2>&1
    mkdir -p knowledge-base/project/plans
    echo plan > "knowledge-base/project/plans/2026-01-01-feat-victim-plan.md"
    if [[ "$spec_mode" == tracked ]]; then
      mkdir -p knowledge-base/project/specs/feat-victim
      echo spec > knowledge-base/project/specs/feat-victim/spec.md
    fi
    git add knowledge-base
    # Backdated past the reaper's <10-minute recent-commit grace so the branch
    # is a real reap candidate, not a grace-skipped one (vacuous-green guard).
    GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
      git commit --date "2025-01-01T00:00:00Z" -m "victim kb artifacts" >/dev/null
    git checkout main >/dev/null 2>&1
    git merge --no-ff -m "merge feat-victim" feat-victim >/dev/null 2>&1
    if [[ "$spec_mode" == untracked ]]; then
      mkdir -p knowledge-base/project/specs/feat-victim
      echo spec > knowledge-base/project/specs/feat-victim/spec.md
    fi
    git push origin main feat-victim >/dev/null 2>&1
  )
}

# Run cleanup-merged inside fixture <dir> (non-bare via cdx); marker stream to
# <out>. rc is swallowed — every assertion keys on markers/disk state, and
# cleanup-merged returns 0 for most internal failures by design.
run_cleanup() {
  local dir="$1" out="$2"; shift 2
  assert_fixture_dir "$dir"; assert_fixture_dir "$out"
  ( cdx "$dir"
    env "$@" SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT" bash "$WM" cleanup-merged
  ) >"$out" 2>&1 || true
}

run_cleanup_bare() {
  local dir="$1" out="$2"; shift 2
  assert_fixture_dir "$dir"; assert_fixture_dir "$out"
  ( cdb "$dir"
    env "$@" SOLEUR_SESSION_STATE_ROOT="$LEASE_ROOT" bash "$WM" cleanup-merged
  ) >"$out" 2>&1 || true
}

is_tracked() { git -C "$1" ls-files --error-unmatch -- "$2" >/dev/null 2>&1; }

spec_live()  { [[ -e "$1/knowledge-base/project/specs/feat-victim" ]]; }
spec_arch()  { grep -q 'feat-victim' < <(ls "$1/knowledge-base/project/specs/archive/" 2>/dev/null); }
plan_live()  { [[ -f "$1/knowledge-base/project/plans/2026-01-01-feat-victim-plan.md" ]]; }
plan_arch()  { grep -q 'feat-victim' < <(ls "$1/knowledge-base/project/plans/archive/" 2>/dev/null); }

# ===========================================================================
# FIXTURE A — non-bare clone on `main`, TRACKED spec dir + plan file.
# The defect surface: today's plain `mv` + same-run/next-run `reset --hard`
# manufactures the twin. Expect: no move at all, DEFERRED reason=main-checkout.
# ===========================================================================
LEASE_ROOT="$TMP/lease-a"; mk_lease_root "$LEASE_ROOT"
BARE_A="$TMP/a-origin.git"; CLONE_A="$TMP/a-clone"
build_clone "$BARE_A" "$CLONE_A" tracked

# Precondition (guard-matrix row 6): the "tracked" fixture is really tracked.
if is_tracked "$CLONE_A" knowledge-base/project/specs/feat-victim/spec.md \
   && is_tracked "$CLONE_A" knowledge-base/project/plans/2026-01-01-feat-victim-plan.md; then
  pass "A precondition: spec dir + plan file are tracked on main"
else
  fail "A precondition: 'tracked' fixture is really untracked — the suite cannot see the class it tests"
fi
if [[ "$(git -C "$CLONE_A" rev-parse --abbrev-ref HEAD)" == "main" ]]; then
  pass "A precondition: checkout is on main"
else
  fail "A precondition: checkout is not on main"
fi

OUT_A="$TMP/a-out.txt"
run_cleanup "$CLONE_A" "$OUT_A"

if grep -q 'SOLEUR_REAP_ARCHIVE_DEFERRED .*reason=main-checkout' "$OUT_A"; then
  pass "A: tracked reap archive on main emits SOLEUR_REAP_ARCHIVE_DEFERRED reason=main-checkout"
else
  fail "A: no DEFERRED/main-checkout marker (output: $(grep -c 'SOLEUR_' "$OUT_A") SOLEUR lines)"
fi
if spec_live "$CLONE_A"; then
  pass "A: live spec dir still on disk after reap on main"
else
  fail "A: live spec dir was moved on main (non-committable checkout must not move tracked artifacts)"
fi
if is_tracked "$CLONE_A" knowledge-base/project/specs/feat-victim/spec.md; then
  pass "A: spec file still tracked after reap on main"
else
  fail "A: spec file lost index tracking on main"
fi
if spec_arch "$CLONE_A"; then
  fail "A: archive copy of spec dir was created on main — the twin mechanism"
else
  pass "A: no spec archive copy created on main"
fi
if plan_live "$CLONE_A" && ! plan_arch "$CLONE_A"; then
  pass "A: tracked plan file deferred too (live kept, no archive copy)"
else
  fail "A: tracked plan file was moved on main"
fi
if [[ -z "$(git -C "$CLONE_A" status --porcelain 2>/dev/null)" ]]; then
  pass "A: worktree clean after deferred reap"
else
  fail "A: worktree dirty after deferred reap: $(git -C "$CLONE_A" status --porcelain | head -3)"
fi
if ! grep -q 'chore(archive-kb)' < <(git -C "$CLONE_A" log --oneline -5 --format=%s); then
  pass "A: no commit landed on main"
else
  fail "A: a chore(archive-kb) commit landed on main — commits to main are prohibited"
fi

# Regression arm: same-run reset AND a second cleanup+reset pair (next-session).
git -C "$CLONE_A" reset --hard HEAD >/dev/null 2>&1
if spec_live "$CLONE_A" && ! spec_arch "$CLONE_A"; then
  pass "A: same-run reset --hard produces no live+archive twin"
else
  fail "A: reset --hard resurrected the twin (live+archive both present)"
fi
OUT_A2="$TMP/a2-out.txt"
run_cleanup "$CLONE_A" "$OUT_A2"
git -C "$CLONE_A" reset --hard HEAD >/dev/null 2>&1
if spec_live "$CLONE_A" && ! spec_arch "$CLONE_A"; then
  pass "A: next-session cleanup+reset still produces no twin"
else
  fail "A: a second cleanup/reset cycle manufactured the twin"
fi

# ===========================================================================
# FIXTURE B — clone on a FEATURE branch, tracked artifacts for a merged OTHER
# branch. Expect: git mv + pathspec-scoped chore(archive-kb) commit; a
# pre-staged unrelated file is never swept (AC5); an untracked brainstorm file
# in the same batch still plain-mv's (mixed batch, per-file classification).
# ===========================================================================
LEASE_ROOT="$TMP/lease-b"; mk_lease_root "$LEASE_ROOT"
BARE_B="$TMP/b-origin.git"; CLONE_B="$TMP/b-clone"
build_clone "$BARE_B" "$CLONE_B" tracked

( set -e
  cdx "$CLONE_B"
  git checkout -b feat-actor >/dev/null 2>&1
  echo unrelated > staged.txt
  git add staged.txt
  mkdir -p knowledge-base/project/brainstorms
  echo brainstorm > "knowledge-base/project/brainstorms/2026-01-01-feat-victim-brainstorm.md"
)

OUT_B="$TMP/b-out.txt"
run_cleanup "$CLONE_B" "$OUT_B"

if grep -q 'SOLEUR_REAP_ARCHIVE_COMMITTED' "$OUT_B"; then
  pass "B: committable checkout emits SOLEUR_REAP_ARCHIVE_COMMITTED"
else
  fail "B: no COMMITTED marker on a feature-branch reap (output: $(grep 'SOLEUR_' "$OUT_B" | head -5))"
fi

ARCH_COMMIT="$(git -C "$CLONE_B" log -1 --format=%s feat-actor 2>/dev/null)"
if [[ "$ARCH_COMMIT" == "chore(archive-kb): persist reap archive for feat-victim" ]]; then
  pass "B: scoped chore(archive-kb) commit is the feat-actor tip"
else
  fail "B: feat-actor tip is '$ARCH_COMMIT', not the archive commit"
fi

if grep -q '^R100' < <(git -C "$CLONE_B" show --name-status --format= feat-actor); then
  pass "B: commit records R100 renames (git mv, not add+delete)"
else
  fail "B: no R100 rename in the archive commit — the move was not `git mv`"
fi

# The commit's touched-path set equals EXACTLY the archive-move set.
# `git show --name-only` on a rename commit lists the DESTINATION paths
# (sources appear only via --name-status, asserted above as R100).
COMMIT_PATHS="$(git -C "$CLONE_B" show --name-only --format= feat-actor | LC_ALL=C sort)"
COMMIT_PATH_COUNT="$(printf '%s\n' "$COMMIT_PATHS" | grep -c .)"
BAD_PATHS="$(printf '%s\n' "$COMMIT_PATHS" | grep -vcE '^knowledge-base/project/(specs|plans)/archive/.*feat-victim' || true)"
if [[ "$COMMIT_PATH_COUNT" -eq 2 && "$BAD_PATHS" -eq 0 ]] \
   && grep -q 'specs/archive/.*feat-victim' <<<"$COMMIT_PATHS" \
   && grep -q 'plans/archive/.*feat-victim' <<<"$COMMIT_PATHS"; then
  pass "B: commit path-set is exactly the archive-move set (no staged.txt, no untracked brainstorm)"
else
  fail "B: commit path-set wrong: $(printf '%s' "$COMMIT_PATHS" | head -8)"
fi

if [[ "$(git -C "$CLONE_B" diff --cached --name-only)" == "staged.txt" ]]; then
  pass "B: pre-staged unrelated file still staged-and-uncommitted (AC5)"
else
  fail "B: staged.txt was swept or lost: index now '$(git -C "$CLONE_B" diff --cached --name-only | head -3)'"
fi

if [[ ! -e "$CLONE_B/knowledge-base/project/specs/feat-victim" ]] && spec_arch "$CLONE_B"; then
  pass "B: tracked spec dir moved live->archive via git mv"
else
  fail "B: spec dir did not reach archive/ on a committable checkout"
fi

# The untracked brainstorm file in the SAME batch plain-mv'd (per-file probe).
if grep -q 'feat-victim' < <(ls "$CLONE_B/knowledge-base/project/brainstorms/archive/" 2>/dev/null) \
   && ! is_tracked "$CLONE_B" "$(cd "$CLONE_B" 2>/dev/null && cd knowledge-base/project/brainstorms/archive 2>/dev/null && ls | grep feat-victim | head -1 | sed 's|^|knowledge-base/project/brainstorms/archive/|')"; then
  pass "B: untracked brainstorm file plain-mv'd in the same reap (mixed batch)"
else
  fail "B: untracked brainstorm file missing from archive or wrongly committed"
fi

# ===========================================================================
# FIXTURE C — untracked spec dir on `main`. Plain `mv` is a contract-permitted
# variant (guard-matrix row 7): untracked files cannot resurrect.
# ===========================================================================
LEASE_ROOT="$TMP/lease-c"; mk_lease_root "$LEASE_ROOT"
BARE_C="$TMP/c-origin.git"; CLONE_C="$TMP/c-clone"
build_clone "$BARE_C" "$CLONE_C" untracked

if spec_live "$CLONE_C" && ! is_tracked "$CLONE_C" knowledge-base/project/specs/feat-victim/spec.md; then
  pass "C precondition: spec dir present and untracked on main"
else
  fail "C precondition: untracked fixture is tracked or absent — vacuous fixture"
fi

OUT_C="$TMP/c-out.txt"
run_cleanup "$CLONE_C" "$OUT_C"

if spec_arch "$CLONE_C" && ! spec_live "$CLONE_C"; then
  pass "C: untracked spec dir still archives via plain mv on main"
else
  fail "C: untracked spec dir did not reach archive/ (plain-mv arm regressed)"
fi
if ! grep -q 'chore(archive-kb)' < <(git -C "$CLONE_C" log --oneline -5 --format=%s); then
  pass "C: untracked move produced no commit on main"
else
  fail "C: a commit landed on main for an untracked move"
fi
if plan_live "$CLONE_C" && ! plan_arch "$CLONE_C"; then
  pass "C: TRACKED plan file in the same reap was still deferred (per-file probe)"
else
  fail "C: tracked plan file moved on main — per-file classification failed"
fi

# ===========================================================================
# FIXTURE D — bare repo whose HEAD tracks the spec path (stale on-disk
# mirror). Expect DEFERRED reason=bare and zero disk churn of the mirror:
# sync_bare_files would only re-materialize a moved file anyway.
# ===========================================================================
LEASE_ROOT="$TMP/lease-d"; mk_lease_root "$LEASE_ROOT"
BARE_D="$TMP/d-bare.git"
git init --bare -b main "$BARE_D" >/dev/null
SEED_D="$TMP/d-seed"
git clone "$BARE_D" "$SEED_D" >/dev/null 2>&1
( set -e
  cdx "$SEED_D"
  git -c user.email=t@t -c user.name=t commit --allow-empty -m seed >/dev/null
  git checkout -b feat-victim >/dev/null 2>&1
  mkdir -p knowledge-base/project/specs/feat-victim
  echo spec > knowledge-base/project/specs/feat-victim/spec.md
  git add knowledge-base
  GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
    git -c user.email=t@t -c user.name=t commit --date "2025-01-01T00:00:00Z" -m "victim kb artifacts" >/dev/null
  git push origin feat-victim main >/dev/null 2>&1
)
# feat-victim tip IS main's tip => 'git branch --merged main' lists it.
git -C "$BARE_D" update-ref refs/heads/main "$(git -C "$BARE_D" rev-parse refs/heads/feat-victim)"
# cleanup-merged fetches origin — give the bare repo a working (self) remote.
git -C "$BARE_D" remote add origin "$BARE_D"
# The stale on-disk mirror: HEAD-tracked content parked at the live path.
mkdir -p "$BARE_D/knowledge-base/project/specs/feat-victim"
echo spec > "$BARE_D/knowledge-base/project/specs/feat-victim/spec.md"

# Precondition: the mirror path IS tracked in HEAD on the bare repo.
if [[ -n "$(git -C "$BARE_D" ls-tree -r HEAD --name-only -- knowledge-base/project/specs/feat-victim)" ]]; then
  pass "D precondition: mirror path is HEAD-tracked on the bare repo"
else
  fail "D precondition: mirror path not in HEAD — vacuous fixture"
fi

OUT_D="$TMP/d-out.txt"
run_cleanup_bare "$BARE_D" "$OUT_D"

if grep -q 'SOLEUR_REAP_ARCHIVE_DEFERRED .*reason=bare' "$OUT_D"; then
  pass "D: bare-root reap emits DEFERRED reason=bare"
else
  fail "D: no DEFERRED/bare marker (output: $(grep 'SOLEUR_' "$OUT_D" | head -5))"
fi
if spec_live "$BARE_D"; then
  pass "D: bare-root mirror left in place"
else
  fail "D: bare-root mirror was churned (moved) — sync_bare_files would re-materialize it"
fi
if spec_arch "$BARE_D"; then
  fail "D: an archive copy was produced on the bare root — the mirror-twin mechanism"
else
  pass "D: no archive copy produced on the bare root"
fi

# ===========================================================================
# FIXTURE E — feature-branch checkout where `git commit` fails (no resolvable
# identity). Expect STAGED: the staged rename payload persists so the session's
# own commits carry it.
# ===========================================================================
LEASE_ROOT="$TMP/lease-e"; mk_lease_root "$LEASE_ROOT"
BARE_E="$TMP/e-origin.git"; CLONE_E="$TMP/e-clone"
build_clone "$BARE_E" "$CLONE_E" tracked

( set -e
  cdx "$CLONE_E"
  # No local identity, and force failure if one is still resolved: the reap's
  # chore commit must fail deterministically on ANY host.
  git config --unset user.email 2>/dev/null || true
  git config --unset user.name 2>/dev/null || true
  git config user.useConfigOnly true
  git checkout -b feat-actor >/dev/null 2>&1
)
mkdir -p "$TMP/nohome"   # empty HOME + XDG_CONFIG_HOME => no --global identity either
# (git reads $XDG_CONFIG_HOME/git/config for global config; HOME alone is not enough)

OUT_E="$TMP/e-out.txt"
run_cleanup "$CLONE_E" "$OUT_E" "HOME=$TMP/nohome" "XDG_CONFIG_HOME=$TMP/nohome" "GIT_CONFIG_NOSYSTEM=1"

if grep -q 'SOLEUR_REAP_ARCHIVE_STAGED' "$OUT_E"; then
  pass "E: commit failure emits SOLEUR_REAP_ARCHIVE_STAGED"
else
  fail "E: no STAGED marker on commit failure (output: $(grep 'SOLEUR_' "$OUT_E" | head -5))"
fi
if ! grep -q 'chore(archive-kb)' < <(git -C "$CLONE_E" log --oneline -5 --format=%s feat-actor); then
  pass "E: no archive commit landed when commit failed"
else
  fail "E: chore commit landed despite the forced identity failure"
fi
if grep -qE '^R100|^A' < <(git -C "$CLONE_E" diff --cached --name-status); then
  pass "E: staged rename payload survives in the index for the session to carry"
else
  fail "E: archive move vanished instead of staying staged"
fi

# ===========================================================================
# FIXTURE F — detached HEAD. AC2 names detached; the HEAD arm must defer.
# ===========================================================================
LEASE_ROOT="$TMP/lease-f"; mk_lease_root "$LEASE_ROOT"
BARE_F="$TMP/f-origin.git"; CLONE_F="$TMP/f-clone"
build_clone "$BARE_F" "$CLONE_F" tracked

( set -e
  cdx "$CLONE_F"
  git checkout --detach HEAD >/dev/null 2>&1
)

if [[ "$(git -C "$CLONE_F" rev-parse --abbrev-ref HEAD)" == "HEAD" ]]; then
  pass "F precondition: checkout is detached"
else
  fail "F precondition: checkout is not detached"
fi

OUT_F="$TMP/f-out.txt"
run_cleanup "$CLONE_F" "$OUT_F"

if grep -q 'SOLEUR_REAP_ARCHIVE_DEFERRED .*reason=detached' "$OUT_F"; then
  pass "F: detached checkout emits DEFERRED reason=detached"
else
  fail "F: no DEFERRED/detached marker (output: $(grep 'SOLEUR_' "$OUT_F" | head -5))"
fi
if spec_live "$CLONE_F" && ! spec_arch "$CLONE_F"; then
  pass "F: tracked spec dir left live on a detached HEAD"
else
  fail "F: tracked spec dir moved on a detached HEAD"
fi

# ===========================================================================
# FIXTURE G — committable checkout where `git mv` fails (specs/ parent made
# read-only). Expect: DEFERRED reason=git-mv-failed for the spec, the tracked
# plan still commits, and no marker-free partial move.
# ===========================================================================
LEASE_ROOT="$TMP/lease-g"; mk_lease_root "$LEASE_ROOT"
BARE_G="$TMP/g-origin.git"; CLONE_G="$TMP/g-clone"
build_clone "$BARE_G" "$CLONE_G" tracked

( set -e
  cdx "$CLONE_G"
  git checkout -b feat-actor >/dev/null 2>&1
  # git mv needs write perms on the destination's parent chain; a read-only
  # specs/ fails every spec move deterministically on any host.
  chmod a-w knowledge-base/project/specs
)

OUT_G="$TMP/g-out.txt"
run_cleanup "$CLONE_G" "$OUT_G"
# Restore perms before assertions (and so the EXIT trap's rm -rf can clean up).
chmod -R u+w "$CLONE_G" 2>/dev/null || true

# One failure of fixture G was seen under shard contention with at most five marker
# lines on its first arm and nothing on the other two (cause unproven, #7376 class). $OUT_G
# lives under $TMP and the EXIT trap deletes it, so inline everything a reader
# needs to tell a STAGED outcome from a COMMITTED one from a hook failure,
# flattened to one line.
g_diag() {
  local markers tailout status log
  markers="$(grep 'SOLEUR_' "$OUT_G" 2>/dev/null | tr '\n' '|')"
  tailout="$(tail -20 "$OUT_G" 2>/dev/null | tr '\n' '|')"
  status="$(git --no-optional-locks -C "$CLONE_G" status --short 2>&1 | tr '\n' '|')"
  log="$(git -C "$CLONE_G" log --oneline -5 feat-actor 2>&1 | tr '\n' '|')"
  printf 'markers=[%s] tail20=[%s] status=[%s] log=[%s]' "$markers" "$tailout" "$status" "$log"
}

if grep -q 'SOLEUR_REAP_ARCHIVE_DEFERRED .*reason=git-mv-failed' "$OUT_G"; then
  pass "G: failed git mv emits DEFERRED reason=git-mv-failed (not a silent warn)"
else
  fail "G: no git-mv-failed marker ($(g_diag))"
fi
if spec_live "$CLONE_G" && ! spec_arch "$CLONE_G"; then
  pass "G: failed git mv left the spec dir live (no partial move, no plain-mv fallback)"
else
  fail "G: spec dir moved/archived despite the failed git mv ($(g_diag))"
fi
# The tracked plan file DID move (plans/ stayed writable) — its commit proves
# the mv-failure arm did not abort the reap loop mid-batch.
if grep -q 'chore(archive-kb)' < <(git -C "$CLONE_G" log --oneline -3 --format=%s feat-actor); then
  pass "G: tracked plan still committed — failed spec move did not abort the reap"
else
  fail "G: plan archive commit missing — the mv failure aborted the run ($(g_diag))"
fi
# The diagnostic only runs inside the three failure arms above, so nothing else
# exercises it: pin that it still emits every field a reader needs.
G_DIAG_OUT="$(g_diag)"
if [[ "$G_DIAG_OUT" == *"markers=["*"SOLEUR_"*"] tail20=["*"] status=["*"] log=["*"]" ]]; then
  pass "G: failure diagnostic carries SOLEUR_ markers, tail20, status and log"
else
  fail "G: failure diagnostic is missing a field: $G_DIAG_OUT"
fi

# ===========================================================================
# FIXTURE H — committable branch mid-merge (MERGE_HEAD present). A scoped
# commit is refused by git mid-merge and the payload would fold into the
# operator's merge commit — defer instead.
# ===========================================================================
LEASE_ROOT="$TMP/lease-h"; mk_lease_root "$LEASE_ROOT"
BARE_H="$TMP/h-origin.git"; CLONE_H="$TMP/h-clone"
build_clone "$BARE_H" "$CLONE_H" tracked

( set -e
  cdx "$CLONE_H"
  git checkout -b feat-actor >/dev/null 2>&1
  echo one > conflict.txt
  git add conflict.txt
  git commit -m actor-side >/dev/null
  git checkout -b feat-side main >/dev/null 2>&1
  echo two > conflict.txt
  git add conflict.txt
  git commit -m side >/dev/null
  git checkout feat-actor >/dev/null 2>&1
  # Conflicting merge -> MERGE_HEAD present on feat-actor.
  git merge feat-side >/dev/null 2>&1 || true
)

if git -C "$CLONE_H" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
   && [[ "$(git -C "$CLONE_H" rev-parse --abbrev-ref HEAD)" == "feat-actor" ]]; then
  pass "H precondition: merge in progress on a feature branch"
else
  fail "H precondition: merge did not produce MERGE_HEAD — vacuous fixture"
fi

OUT_H="$TMP/h-out.txt"
run_cleanup "$CLONE_H" "$OUT_H"

if grep -q 'SOLEUR_REAP_ARCHIVE_DEFERRED .*reason=merge-in-progress' "$OUT_H"; then
  pass "H: merge-in-progress checkout emits DEFERRED reason=merge-in-progress"
else
  fail "H: no merge-in-progress marker (output: $(grep 'SOLEUR_' "$OUT_H" | head -5))"
fi
if spec_live "$CLONE_H" && ! spec_arch "$CLONE_H"; then
  pass "H: tracked spec dir left live mid-merge (payload never folds into a merge commit)"
else
  fail "H: tracked spec dir moved mid-merge"
fi
if ! grep -q 'chore(archive-kb)' < <(git -C "$CLONE_H" log --oneline -3 --format=%s feat-actor); then
  pass "H: no archive commit landed during a merge"
else
  fail "H: chore commit landed mid-merge"
fi

# ===========================================================================
# FIXTURE I — branch literally named `feat-`: feature_slug strips to EMPTY,
# which would collapse the plans/brainstorms glob to `*` and sweep every file
# in the directory. The guard must refuse the batch entirely.
# ===========================================================================
LEASE_ROOT="$TMP/lease-i"; mk_lease_root "$LEASE_ROOT"
BARE_I="$TMP/i-origin.git"; CLONE_I="$TMP/i-clone"
git init --bare -b main "$BARE_I" >/dev/null
git clone "$BARE_I" "$CLONE_I" >/dev/null 2>&1
( set -e
  cdx "$CLONE_I"
  git config user.email t@t
  git config user.name t
  git config commit.gpgsign false
  git commit --allow-empty -m seed >/dev/null
  git checkout -b 'feat-' >/dev/null 2>&1
  mkdir -p knowledge-base/project/plans
  echo p > "knowledge-base/project/plans/2026-01-01-feat--plan.md"
  echo u > "knowledge-base/project/plans/2026-02-02-unrelated-plan.md"
  git add knowledge-base
  GIT_COMMITTER_DATE="2025-01-01T00:00:00Z" \
    git commit --date "2025-01-01T00:00:00Z" -m "kb artifacts" >/dev/null
  git checkout main >/dev/null 2>&1
  git merge --no-ff -m "merge feat-" 'feat-' >/dev/null 2>&1
  git push origin main 'feat-' >/dev/null 2>&1
  git checkout -b feat-actor >/dev/null 2>&1
)

OUT_I="$TMP/i-out.txt"
run_cleanup "$CLONE_I" "$OUT_I"

if [[ -f "$CLONE_I/knowledge-base/project/plans/2026-02-02-unrelated-plan.md" ]]; then
  pass "I: unrelated plan file survived — empty slug did not sweep the directory"
else
  fail "I: unrelated plan file was swept (empty-slug glob collapse)"
fi
if [[ -f "$CLONE_I/knowledge-base/project/plans/2026-01-01-feat--plan.md" ]]; then
  pass "I: the feat- plan file stayed live too (empty slug refuses the batch)"
else
  fail "I: feat- plan file moved — the guard should refuse, not partially move"
fi
if ! grep -q 'chore(archive-kb)' < <(git -C "$CLONE_I" log --oneline -3 --format=%s feat-actor); then
  pass "I: no archive commit produced for an empty feature slug"
else
  fail "I: a chore commit landed for the empty-slug sweep"
fi

# ===========================================================================
# Census (guard-matrix row 5): every KB archive move routes through
# reap_archive_persist. Extract the two caller regions and the helper body;
# a bare `mv`/`git mv` in a caller region is the defect class reborn.
# ===========================================================================
_arch_body="$(awk '/^archive_kb_files\(\) \{/,/^\}/' "$WM")"
_spec_block="$(awk '/Archive spec directory/,/Extract feature slug/' "$WM")"
_helper_body="$(awk '/^reap_archive_persist\(\) \{/,/^\}/' "$WM")"

_mv_cmds() { grep -vE '^[[:space:]]*#' | grep -cE '\b(git[[:space:]]+)?mv[[:space:]]' || true; }

if grep -q 'reap_archive_persist' <<<"$_arch_body" && [[ "$(printf '%s\n' "$_arch_body" | _mv_cmds)" -eq 0 ]]; then
  pass "census: archive_kb_files routes through reap_archive_persist, no bare mv"
else
  fail "census: archive_kb_files moves artifacts without the helper"
fi
if grep -q 'reap_archive_persist' <<<"$_spec_block" && [[ "$(printf '%s\n' "$_spec_block" | _mv_cmds)" -eq 0 ]]; then
  pass "census: spec-dir block routes through reap_archive_persist, no bare mv"
else
  fail "census: spec-dir block moves artifacts without the helper"
fi
if grep -q 'git -C "$GIT_ROOT" mv -- ' <<<"$_helper_body" && grep -qE '(^|[^[:alnum:]_])mv -- "\$src"' <<<"$_helper_body"; then
  pass "census: the helper owns both move arms (git mv + plain mv)"
else
  fail "census: reap_archive_persist does not own both move arms"
fi

echo ""
echo "=== $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
