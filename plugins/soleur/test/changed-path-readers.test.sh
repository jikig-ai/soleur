#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard -- the changed-path READERS (#12332): the shared helper, every converted workflow step EXECUTED, and the census sentinel.
#
# PROPERTY. A reader that lists a pull request's changed paths and matches them against a gated surface must (1) see the EXACT bytes of a
# name git would C-quote (a non-ASCII byte, tab, `"`, `\`), (2) list a rename's OLD path (a rename away from a gated surface is a change to it;
# the one exception is an exact-file "was this document updated" check), (3) list a gitlink that configuration hides, and (4) fail toward
# running or blocking when git fails, never read a failed diff as "nothing changed".
#
# THREE SECTIONS, one file (selectable by argument: helper | steps | sentinel; default all).
#   helper    plugins/soleur/scripts/changed-paths.sh against real scratch repositories.
#   steps     the `run:` body of each converted workflow step, extracted from the YAML in ONE PyYAML call and EXECUTED under the weakest
#             shell Actions can pick (`bash -e {0}`: errexit, NO pipefail) in a scratch clone, against named scenarios. A text pin
#             certifies spelling; this certifies behaviour (see ci-classify-step-exec.test.sh, the precedent).
#   sentinel  every `git diff|log|show ... --name-only|--name-status` (and `gh pr diff ... --name-only`) site in .github/workflows/*.yml is
#             NUL-delimited (`-z`) or listed in the exemption table below with a reason; stale entries fail; the converted hooks and scripts
#             keep `-z` (a pinned list).
#
# NOT COVERED by the sentinel (so a reader of a green run is not told more than it proves): skill prose in preflight/ship/review (the
# sentinel section pins each skill's SPELLING of the helper call, one row per SKILL.md; it does not execute that prose); the hooks and top-level scripts/ not on the pinned list below (about twenty
# unconverted sites, a known remainder); `--raw` readers (ci.yml e2e / shard-totality classifiers, executed by ci-classify-step-exec.test.sh);
# readers that call `gh api` or `git ls-files` rather than a diff.
# KNOWN REMAINDER, named (unconverted, no filing; tracked as a comment on the arc tracker #12246): hooks pre-merge-rebase.sh (532/818/854),
# skill-security-scan.sh (64, advisory), scripts/hooks/pre-push, scripts/pre-push-ratchet-lane.sh (358/360); scripts lint-credential-path-literals.py (328),
# lint-infra-no-human-steps.py (502), lint-shell-trace-credential-refusal.py (2487), lint-skill-body-budget.py (169), lint-migration-api-grants.sh,
# lint-migration-fk-preconditions.sh; plugins/soleur/scripts affected-tests.sh (685-705), merge-effect-class.sh (103), pr-overlap-preflight.sh, archive-kb.sh;
# apps/web-platform/scripts allowlist-diff.sh (46), sdk-bump-sandbox-gate.sh (175); .github/scripts check-pr-body-vs-diff.sh, check-sweep-completeness.sh
# (destination-only `gh api` filenames); ci.yml `--raw` classifiers; fix-constraints-stage-a.yml (-z without --no-renames); unconverted skill prose in
# review (391), preflight (132/304), ship, one-shot, postmerge, work, qa and four agents/*.md.
#
# ANCHOR. The stored values are the DEFAULT_ENV map, the per-step expected-flag map and the exemption table in THIS file. A diff that edits a
# workflow and this file together proves consistency, not integrity; the outside mover is the required `test` check executing this suite
# against the PR's own YAML, plus the reviewer reading the diff of the maps and the exemption reasons.
#
# Auto-discovered by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/plugins/soleur/scripts/changed-paths.sh"
WF_DIR="$REPO_ROOT/.github/workflows"
SECTION="${1:-all}"
case "$SECTION" in all|helper|steps|sentinel) : ;; *) echo "usage: changed-path-readers.test.sh [helper|steps|sentinel]" >&2; exit 2 ;; esac

PASS=0
FAIL=0
HELPER_ROWS=0
STEP_ROWS=0
pass() { PASS=$((PASS + 1)); echo "ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }

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

# One owning root for every fixture, removed on ANY exit path. The EXIT trap is registered BEFORE the fixture library is sourced.
WORK_ROOT="$(mktemp -d /var/tmp/changed-path-readers.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK_ROOT"
trap 'rm -rf "$WORK_ROOT"' EXIT
# shellcheck source=./lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"
git_fixture_env "$WORK_ROOT" || { echo "FATAL: git_fixture_env refused $WORK_ROOT" >&2; exit 2; }

# Instrument self-test: pass()/fail() must each move their own counter (a suite whose verdict function is inert reports green forever).
_p0=$PASS; _f0=$FAIL
pass "instrument self-test (expected)" >/dev/null
fail "instrument self-test (expected, subtracted)" >/dev/null
if [ "$PASS" -ne $((_p0 + 1)) ] || [ "$FAIL" -ne $((_f0 + 1)) ]; then
  printf 'FATAL: pass()/fail() did not each move their counter\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0

# Positive controls for the verdict-owning helpers (h_expect_line, h_expect_rc, expect_flag, expect_closed, pinned_z_check): each is
# fed a value it must REJECT (and one it must accept) and its counter must move. The call runs in THIS shell so the counters are real;
# its transcript is discarded and the PASS/FAIL/row tallies are unwound afterwards, so the assertion floors stay exact. A failed
# self-test reports through printf + exit, never through the helper under test.
SELFTESTS=0
selftest_moved() { # <name> <pass|fail> <command...>
  local name="$1" want="$2" p0=$PASS f0=$FAIL h0=$HELPER_ROWS s0=$STEP_ROWS dp df
  shift 2
  "$@" >/dev/null
  dp=$((PASS - p0)); df=$((FAIL - f0))
  PASS=$p0; FAIL=$f0; HELPER_ROWS=$h0; STEP_ROWS=$s0
  if [ "$want" = fail ] && { [ "$df" -ne 1 ] || [ "$dp" -ne 0 ]; }; then
    printf 'FATAL: self-test %s: a wrong value did not move the FAIL counter (pass+%s fail+%s); the helper is inert\n' "$name" "$dp" "$df" >&2; exit 1
  fi
  if [ "$want" = pass ] && { [ "$dp" -ne 1 ] || [ "$df" -ne 0 ]; }; then
    printf 'FATAL: self-test %s: a right value did not move the PASS counter (pass+%s fail+%s)\n' "$name" "$dp" "$df" >&2; exit 1
  fi
  SELFTESTS=$((SELFTESTS + 1))
}

command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 missing; this suite asserted nothing" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq missing; the infra-validation step needs it" >&2; exit 3; }
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML missing; the steps section cannot extract run: bodies" >&2; exit 3; }
[ -f "$HELPER" ] || { echo "FATAL: $HELPER missing (the file under test is repo-owned)" >&2; exit 1; }

REAL_GIT="$(command -v git)"
export REAL_GIT

# The names git C-quotes (the point of every row), plus a glob-looking one.
NAME_E=$'\303\251.tf'
NAME_TAB=$'tab\ttwo.tf'
NAME_Q='q"uote.tf'
NAME_BS='back\slash.tf'
NAME_GLOB='glob[1].tf'
NAME_NL=$'nl-a\nb.tf'
NL=$'\n'

fg() { local d="$1"; shift; assert_fixture_dir "$d"; git -C "$d" "$@"; }

# ── the template: ONE base repository, a bare origin, copied per row (cp -a) ─────────────────────────────────────────────────
TPL="$WORK_ROOT/tpl"
TPL_WORK="$TPL/work"
TPL_ORIGIN="$TPL/origin.git"
put_in() { # <dir> <relpath> [content]
  mkdir -p "$(dirname "$1/$2")" && printf '%s\n' "${3:-$2}" > "$1/$2"
}
build_template() {
  assert_fixture_dir "$TPL"
  mkdir -p "$TPL_WORK" || return 1
  fg "$TPL_WORK" init -q -b main || return 1
  local f
  for f in \
    apps/web-platform/infra/keep.tf apps/cla-evidence/infra/keep.tf infra/github/keep.tf apps/web-platform/infra/sentry/keep.tf \
    apps/web-platform/server/keep.ts apps/web-platform/server/dsar-export.ts apps/web-platform/server/agent-env.ts \
    apps/web-platform/app/api/account/export/keep.ts apps/web-platform/Dockerfile \
    plugins/soleur/docs/keep.md plugins/soleur/skills/gdpr-gate/references/keep.md \
    docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md \
    apps/web-platform/test/fixtures/keep.json docs/other.md README.md .github/workflows/secret-scan.yml; do
    put_in "$TPL_WORK" "$f" "content of $f"
  done
  fg "$TPL_WORK" add -A && fg "$TPL_WORK" commit -q -m base || return 1
  git clone -q --bare "$TPL_WORK" "$TPL_ORIGIN" || return 1
  fg "$TPL_WORK" remote add origin "$TPL_ORIGIN" && fg "$TPL_WORK" fetch -q origin || return 1
  return 0
}

ROW_SEQ=0
ROW_DIR=""
ROW_BASE=""
ROW_HEAD=""
new_row() {
  ROW_SEQ=$((ROW_SEQ + 1))
  ROW_DIR="$WORK_ROOT/rows/r$ROW_SEQ"
  assert_fixture_dir "$ROW_DIR"
  mkdir -p "$WORK_ROOT/rows" && cp -a "$TPL_WORK" "$ROW_DIR" || return 1
  ROW_BASE="$(fg "$ROW_DIR" rev-parse HEAD)" || return 1
  fg "$ROW_DIR" checkout -q -b pr || return 1
  ROW_HEAD="$ROW_BASE"
}
free_row() { assert_fixture_dir "$ROW_DIR"; rm -rf -- "$ROW_DIR"; }
commit_row() {
  fg "$ROW_DIR" add -A && fg "$ROW_DIR" commit -q --allow-empty -m change && ROW_HEAD="$(fg "$ROW_DIR" rev-parse HEAD)"
}
scn_name() { # <qe|qtab|qquote|qbs>
  case "$1" in qe) printf '%s' "$NAME_E" ;; qtab) printf '%s' "$NAME_TAB" ;; qquote) printf '%s' "$NAME_Q" ;; qbs) printf '%s' "$NAME_BS" ;; esac
}
add_gitlink() { # <dir> <path> : a gitlink whose submodule config says ignore=all, plus the local config
  local d="$1" p="$2"
  assert_fixture_dir "$d"
  printf '[submodule "sm"]\n\tpath = %s\n\turl = https://example.invalid/sm.git\n\tignore = all\n' "$p" > "$d/.gitmodules"
  mkdir -p "$d/$p"   # an empty directory keeps `git add -A` from staging the gitlink as deleted
  fg "$d" update-index --add --cacheinfo "160000,$ROW_BASE,$p" && fg "$d" config diff.ignoreSubmodules all
}

# A failing-git shim: any `git` invocation naming a verb in SHIM_FAIL_VERBS exits 128; everything else is the real git.
SHIM_FAIL_DIR="$WORK_ROOT/shim-fail"
SHIM_NODE_DIR="$WORK_ROOT/shim-node"
mkdir -p "$SHIM_FAIL_DIR" "$SHIM_NODE_DIR" || exit 2
cat > "$SHIM_FAIL_DIR/git" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
  for v in ${SHIM_FAIL_VERBS:-diff}; do
    if [ "$a" = "$v" ]; then echo "shim: injected git failure on '$v'" >&2; exit 128; fi
  done
done
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$SHIM_FAIL_DIR/git"
# A recording `node`: writes its argv after the script path, NUL-separated, to $NODE_ARGV_FILE.
cat > "$SHIM_NODE_DIR/node" <<'SHIM'
#!/usr/bin/env bash
shift
: > "$NODE_ARGV_FILE"
for a in "$@"; do printf '%s\0' "$a" >> "$NODE_ARGV_FILE"; done
SHIM
chmod +x "$SHIM_NODE_DIR/node"

if ! build_template; then echo "FATAL: could not build the template repository" >&2; exit 2; fi

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# SECTION helper
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
H_OUT=""; H_ERR=""; H_RC=0
run_helper() { # <dir> <args...>   (cwd = dir)
  local d="$1"; shift
  assert_fixture_dir "$d"
  mkdir -p "$WORK_ROOT/io"
  H_RC=0
  (cd "$d" && bash "$HELPER" "$@") > "$WORK_ROOT/io/h.out" 2> "$WORK_ROOT/io/h.err" || H_RC=$?
  H_OUT="$(cat "$WORK_ROOT/io/h.out")"
  H_ERR="$(cat "$WORK_ROOT/io/h.err")"
}
run_helper_env() { # <dir> <NAME=value> <args...>   (cwd = dir; one env assignment for the helper only)
  local d="$1" e="$2"; shift 2
  assert_fixture_dir "$d"
  mkdir -p "$WORK_ROOT/io"
  H_RC=0
  (cd "$d" && env "$e" bash "$HELPER" "$@") > "$WORK_ROOT/io/h.out" 2> "$WORK_ROOT/io/h.err" || H_RC=$?
  H_OUT="$(cat "$WORK_ROOT/io/h.out")"
  H_ERR="$(cat "$WORK_ROOT/io/h.err")"
}
h_ok() { HELPER_ROWS=$((HELPER_ROWS + 1)); pass "helper: $1"; }
h_bad() { HELPER_ROWS=$((HELPER_ROWS + 1)); fail "helper: $1"; }
h_has_line() { LC_ALL=C grep -Fxq -e "$1" <<<"$H_OUT"; }
h_expect_line() { # <label> <exact line>
  if h_has_line "$2"; then h_ok "$1"; else h_bad "$1 (want line '$2'; got rc=$H_RC '$(printf '%s' "$H_OUT" | tr '\n' '|' | cut -c1-200)')"; fi
}
h_expect_rc() { # <label> <rc>
  if [ "$H_RC" -eq "$2" ]; then h_ok "$1"; else h_bad "$1 (want rc=$2 got rc=$H_RC; err='$(printf '%s' "$H_ERR" | cut -c1-120)')"; fi
}
selftest_helper_verdicts() {
  local o_out="$H_OUT" o_err="$H_ERR" o_rc="$H_RC"
  H_OUT=$'alpha\nbeta'; H_ERR=""; H_RC=0
  selftest_moved "h_expect_line accepts a listed line" pass h_expect_line "selftest" "beta"
  selftest_moved "h_expect_line rejects an absent line" fail h_expect_line "selftest" "gamma"
  selftest_moved "h_expect_line rejects a mere substring" fail h_expect_line "selftest" "alph"
  selftest_moved "h_expect_rc accepts the right rc" pass h_expect_rc "selftest" 0
  selftest_moved "h_expect_rc rejects a wrong rc" fail h_expect_rc "selftest" 2
  H_OUT="$o_out"; H_ERR="$o_err"; H_RC="$o_rc"
}
precondition_quoted() { # <label> <dir> <range> <raw path>: the PLAIN diff must C-quote this name (else the row below proves nothing)
  local plain
  if ! plain="$(fg "$2" diff --name-only "$3")"; then h_bad "precondition $1: the plain diff itself failed"; return; fi
  if LC_ALL=C grep -Fxq -e "$4" <<<"$plain"; then
    h_bad "precondition $1: the plain diff lists the RAW name, so git did not C-quote it and the row would pass vacuously"
  elif grep -q '^"' <<<"$plain"; then
    h_ok "precondition $1: the plain diff C-quotes it"
  else
    h_bad "precondition $1: the plain diff lists neither the raw name nor a quoted form"
  fi
}

section_helper() {
  echo "── helper"
  selftest_helper_verdicts
  local P='apps/web-platform/infra' d
  # Row set 1: specials, rename-away, outside control and a glob name, all in one PR (a newline name is row set 6).
  new_row || { h_bad "could not build row 1"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/$NAME_E"; put_in "$d" "$P/$NAME_TAB"; put_in "$d" "$P/$NAME_Q"; put_in "$d" "$P/$NAME_BS"
  put_in "$d" "$P/$NAME_GLOB"; put_in "$d" "zz-outside/$NAME_E"
  mkdir -p "$d/zz-outside" && fg "$d" mv "$P/keep.tf" zz-outside/keep.tf
  commit_row || { h_bad "could not commit row 1"; return; }
  precondition_quoted "é" "$d" origin/main...HEAD "$P/$NAME_E"
  precondition_quoted "tab" "$d" origin/main...HEAD "$P/$NAME_TAB"
  precondition_quoted "double quote" "$d" origin/main...HEAD "$P/$NAME_Q"
  precondition_quoted "backslash" "$d" origin/main...HEAD "$P/$NAME_BS"
  run_helper "$d" origin/main...HEAD
  h_expect_rc "origin/main...HEAD exits 0" 0
  h_expect_line "é name arrives raw" "$P/$NAME_E"
  h_expect_line "tab name arrives raw" "$P/$NAME_TAB"
  h_expect_line "double-quote name arrives raw" "$P/$NAME_Q"
  h_expect_line "backslash name arrives raw" "$P/$NAME_BS"
  h_expect_line "glob-looking name arrives raw" "$P/$NAME_GLOB"
  h_expect_line "rename-away lists the OLD path" "$P/keep.tf"
  h_expect_line "rename-away lists the new path too" "zz-outside/keep.tf"
  h_expect_line "control path outside every surface is listed (it is a change)" "zz-outside/$NAME_E"
  run_helper "$d" --match '^apps/web-platform/infra/' origin/main...HEAD
  h_expect_rc "--match with matches exits 0" 0
  if [ "$(grep -c . <<<"$H_OUT")" -eq 6 ]; then h_ok "--match prints exactly the 6 surface lines (4 specials, glob, old keep.tf)"
  else h_bad "--match line count: want 6 got $(grep -c . <<<"$H_OUT") ($(printf '%s' "$H_OUT" | tr '\n' '|' | cut -c1-200))"; fi
  if h_has_line "zz-outside/$NAME_E"; then h_bad "--match leaked the control path outside the surface"; else h_ok "--match excludes the control path outside the surface"; fi
  run_helper "$d" --match '^zzz-no-such-prefix/' origin/main...HEAD
  h_expect_rc "--match with no match exits 1 (not 0)" 1
  if [ -z "$H_OUT" ]; then h_ok "--match with no match prints nothing"; else h_bad "--match with no match printed '$H_OUT'"; fi
  run_helper "$d" --match '[' origin/main...HEAD
  h_expect_rc "--match with an invalid ERE exits 2" 2
  run_helper "$d" --match '^apps/' origin/no-such-ref...HEAD
  h_expect_rc "--match with an unresolvable range exits 2 (a git failure is never 'no match')" 2
  run_helper "$d" origin/no-such-ref...HEAD
  h_expect_rc "an unresolvable range exits 2" 2
  if [ -z "$H_OUT" ]; then h_ok "an unresolvable range prints no list"; else h_bad "an unresolvable range printed '$H_OUT'"; fi
  if grep -qF 'git diff failed' <<<"$H_ERR"; then h_ok "a git failure says so on stderr"; else h_bad "a git failure stderr: '$H_ERR'"; fi
  H_RC=0
  (cd "$d" && SHIM_FAIL_VERBS=diff PATH="$SHIM_FAIL_DIR:$PATH" bash "$HELPER" origin/main...HEAD) > "$WORK_ROOT/io/h.out" 2> "$WORK_ROOT/io/h.err" || H_RC=$?
  H_OUT="$(cat "$WORK_ROOT/io/h.out")"
  h_expect_rc "an injected git failure on a VALID range exits non-zero" 2
  H_RC=0
  (cd "$d" && SHIM_FAIL_VERBS=diff PATH="$SHIM_FAIL_DIR:$PATH" bash "$HELPER" --match '^apps/' origin/main...HEAD) > "$WORK_ROOT/io/h.out" 2> "$WORK_ROOT/io/h.err" || H_RC=$?
  h_expect_rc "--match: an injected git failure exits 2, not 1" 2
  free_row

  # Row set 2: a gitlink under a committed ignore=all AND a local diff.ignoreSubmodules=all.
  new_row || { h_bad "could not build gitlink row"; return; }
  d="$ROW_DIR"
  add_gitlink "$d" "$P/sm"
  commit_row || { h_bad "could not commit gitlink row"; return; }
  local plainsm
  if ! plainsm="$(fg "$d" diff --name-only origin/main...HEAD)"; then h_bad "precondition gitlink: the plain diff failed"
  elif grep -Fxq -e "$P/sm" <<<"$plainsm"; then h_bad "precondition gitlink: the plain diff lists the gitlink, so the config hid nothing"
  else h_ok "precondition gitlink: the plain diff hides it"; fi
  run_helper "$d" origin/main...HEAD
  h_expect_line "a config-hidden gitlink is listed" "$P/sm"
  free_row

  # Row set 3: diff.relative=true, run from a subdirectory.
  new_row || { h_bad "could not build relative row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/new.tf"
  fg "$d" config diff.relative true
  commit_row || { h_bad "could not commit relative row"; return; }
  local plainrel
  plainrel="$(cd "$d/apps/web-platform" && "$REAL_GIT" diff --name-only origin/main...HEAD)"
  if [ "$plainrel" = "infra/new.tf" ]; then h_ok "precondition diff.relative: the plain diff from a subdirectory is cwd-relative"
  else h_bad "precondition diff.relative: plain diff from the subdirectory printed '$plainrel'"; fi
  run_helper "$d/apps/web-platform" origin/main...HEAD
  h_expect_line "diff.relative=true from a subdirectory still prints repo-root-relative paths" "$P/new.tf"
  free_row

  # Row set 4: the --cached and worktree argument forms.
  new_row || { h_bad "could not build cached row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/$NAME_Q"
  fg "$d" add -A
  run_helper "$d" --cached
  h_expect_line "--cached lists a staged double-quote name raw" "$P/$NAME_Q"
  run_helper "$d" HEAD
  h_expect_line "the HEAD form lists the same staged name raw" "$P/$NAME_Q"
  free_row

  # Row set 5: empty diff, usage, and not-a-repository.
  new_row || { h_bad "could not build empty row"; return; }
  d="$ROW_DIR"
  run_helper "$d" origin/main...HEAD
  h_expect_rc "an empty diff exits 0" 0
  if [ -z "$H_OUT" ]; then h_ok "an empty diff prints nothing"; else h_bad "an empty diff printed '$H_OUT'"; fi
  run_helper "$d" --match '^apps/' origin/main...HEAD
  h_expect_rc "--match on an empty diff exits 1" 1
  run_helper "$d"
  h_expect_rc "no arguments exits 2" 2
  if grep -qi 'usage' <<<"$H_ERR"; then h_ok "no arguments prints a usage line"; else h_bad "no arguments stderr: '$H_ERR'"; fi
  run_helper "$d" --match '^apps/'
  h_expect_rc "--match with no diff arguments exits 2 (never defaults to a diff target)" 2
  run_helper "$d" --match
  h_expect_rc "--match with no pattern exits 2" 2
  run_helper "$d" --help
  h_expect_rc "an unsupported flag exits 2" 2
  run_helper "$d" -z origin/main...HEAD
  h_expect_rc "an output-format flag exits 2" 2
  free_row

  # Row set 6: a changed path holding a newline cannot be one line of a list, so the diff is UNKNOWN (rc 2) and stdout is not a list.
  # Otherwise the fragment after the newline (`docs/legal/privacy-policy.md`) is a "path" the caller may match and ALLOW on.
  new_row || { h_bad "could not build newline row"; return; }
  d="$ROW_DIR"
  put_in "$d" "zz${NL}docs/legal/privacy-policy.md"
  commit_row || { h_bad "could not commit newline row"; return; }
  local lfsplit
  if ! lfsplit="$(fg "$d" diff -z --name-only origin/main...HEAD | tr '\0' '\n')"; then h_bad "precondition newline: the NUL list itself failed"
  elif grep -Fxq -e 'docs/legal/privacy-policy.md' <<<"$lfsplit"; then h_ok "precondition newline: an LF-split of the list WOULD yield the satisfying fragment line"
  else h_bad "precondition newline: the LF-split has no fragment line, the rows below prove nothing"; fi
  run_helper "$d" origin/main...HEAD
  h_expect_rc "a changed path holding a newline exits 2" 2
  if [ -z "$H_OUT" ]; then h_ok "a newline path prints no list on stdout"; else h_bad "a newline path printed a list: '$(printf '%s' "$H_OUT" | tr '\n' '|' | cut -c1-160)'"; fi
  if grep -qi 'newline' <<<"$H_ERR"; then h_ok "a newline path says so on stderr"; else h_bad "a newline path stderr: '$H_ERR'"; fi
  run_helper "$d" --match '^docs/' origin/main...HEAD
  h_expect_rc "--match: a changed path holding a newline exits 2 (the fragment never satisfies the match)" 2
  if [ -z "$H_OUT" ]; then h_ok "--match: a newline path prints no matches"; else h_bad "--match: a newline path printed '$(printf '%s' "$H_OUT" | tr '\n' '|' | cut -c1-160)'"; fi
  free_row

  # Row set 7: output-format flags the helper refuses (each leaves stdout empty at rc 0, which a caller would read as "nothing
  # changed"). Run on a PR with a change AND on an empty diff: `--exit-code` is only distinguishable from a git failure when empty.
  local dchg dempty flag tag dd outf
  new_row || { h_bad "could not build flag row"; return; }
  dchg="$ROW_DIR"
  put_in "$dchg" "$P/flag.tf"
  commit_row || { h_bad "could not commit flag row"; return; }
  new_row || { h_bad "could not build flag empty row"; return; }
  dempty="$ROW_DIR"
  for tag in changed empty; do
    if [ "$tag" = changed ]; then dd="$dchg"; else dd="$dempty"; fi
    for flag in -s --no-patch -q --quiet --exit-code; do
      run_helper "$dd" "$flag" origin/main...HEAD
      h_expect_rc "refused flag $flag exits 2 ($tag diff)" 2
    done
    outf="$WORK_ROOT/io/refused-output-$tag.txt"
    rm -f "$outf"
    run_helper "$dd" "--output=$outf" origin/main...HEAD
    h_expect_rc "refused flag --output=FILE exits 2 ($tag diff)" 2
    if [ ! -e "$outf" ]; then h_ok "--output=FILE created no file ($tag diff)"; else h_bad "--output=FILE wrote $outf ($tag diff)"; fi
    run_helper "$dd" --output "$outf" origin/main...HEAD
    h_expect_rc "refused flag --output FILE exits 2 ($tag diff)" 2
    if [ ! -e "$outf" ]; then h_ok "--output FILE created no file ($tag diff)"; else h_bad "--output FILE wrote $outf ($tag diff)"; fi
  done
  assert_fixture_dir "$dchg"; rm -rf -- "$dchg"
  free_row

  # Row set 8: an unwritable TMPDIR is UNKNOWN (rc 2 with a temp-file message), never "none match" (rc 1).
  new_row || { h_bad "could not build tmpdir row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/tmpdir.tf"
  commit_row || { h_bad "could not commit tmpdir row"; return; }
  run_helper_env "$d" TMPDIR=/nonexistent/changed-paths-fixture origin/main...HEAD
  h_expect_rc "an unwritable TMPDIR exits 2" 2
  if grep -qF 'temp file' <<<"$H_ERR" && [ -z "$H_OUT" ]; then h_ok "an unwritable TMPDIR says so on stderr and prints no list"; else h_bad "unwritable TMPDIR: out='$H_OUT' err='$H_ERR'"; fi
  run_helper_env "$d" TMPDIR=/nonexistent/changed-paths-fixture --match '^zzz-no-such-prefix/' origin/main...HEAD
  h_expect_rc "--match with an unwritable TMPDIR exits 2, never 1 (none match)" 2
  run_helper_env "$d" TMPDIR=/nonexistent/changed-paths-fixture --match '^apps/' origin/main...HEAD
  h_expect_rc "--match that WOULD match, with an unwritable TMPDIR, still exits 2" 2
  free_row

  # Row set 9: a name holding an invalid UTF-8 byte (Latin-1 \351) under a UTF-8 locale: GNU grep would answer "binary file matches".
  new_row || { h_bad "could not build latin-1 row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/"$'\351'".tf"
  commit_row || { h_bad "could not commit latin-1 row"; return; }
  precondition_quoted "latin-1" "$d" origin/main...HEAD "$P/"$'\351'".tf"
  run_helper_env "$d" LC_ALL=C.UTF-8 --match '^apps/web-platform/infra/' origin/main...HEAD
  h_expect_rc "--match under LC_ALL=C.UTF-8 with an invalid-UTF-8 name exits 0" 0
  h_expect_line "--match under LC_ALL=C.UTF-8 prints the invalid-UTF-8 name raw" "$P/"$'\351'".tf"
  run_helper_env "$d" LC_ALL=C.UTF-8 origin/main...HEAD
  h_expect_line "plain mode under LC_ALL=C.UTF-8 prints the invalid-UTF-8 name raw" "$P/"$'\351'".tf"
  free_row

  # Row set 10: a LARGE list (> 64 KiB of names) in --match mode: every match is printed and the exit is 0 (a `grep -q` on a pipe
  # would SIGPIPE the writer past the pipe buffer; a here-string spills to a temp file).
  new_row || { h_bad "could not build large row"; return; }
  d="$ROW_DIR"
  mkdir -p "$d/$P/bulk" || { h_bad "could not mkdir bulk"; return; }
  local i pad='xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
  for i in $(seq -w 1 1200); do : > "$d/$P/bulk/long-name-for-padding-$i-$pad.tf"; done
  commit_row || { h_bad "could not commit large row"; return; }
  run_helper "$d" --match '^apps/web-platform/infra/bulk/' origin/main...HEAD
  h_expect_rc "--match over a >64 KiB list exits 0" 0
  if [ "$(wc -c < "$WORK_ROOT/io/h.out")" -gt 65536 ]; then h_ok "precondition large: the matched output is larger than a 64 KiB pipe buffer"; else h_bad "precondition large: output only $(wc -c < "$WORK_ROOT/io/h.out") bytes"; fi
  if [ "$(grep -c . <<<"$H_OUT")" -eq 1200 ]; then h_ok "--match over a >64 KiB list prints all 1200 matches"; else h_bad "--match over a large list printed $(grep -c . <<<"$H_OUT") lines, want 1200"; fi
  free_row
  mkdir -p "$WORK_ROOT/nogit"
  run_helper "$WORK_ROOT/nogit" origin/main...HEAD
  h_expect_rc "outside a git work tree exits 2" 2
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# SECTION steps
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
STEP_DIR="$WORK_ROOT/steps"
mkdir -p "$STEP_DIR" "$WORK_ROOT/io" || exit 2

# The extraction manifest: key<TAB>workflow<TAB>job<TAB>step id. The extracted-step count has a floor, and a missing step is a FAIL.
STEP_MANIFEST='infra-dirs	infra-validation.yml	detect-changes	dirs
ci-filter	ci.yml	detect-changes	filter
ci-canary	ci.yml	guards-advisory	trigger-canary
ci-propagation	ci.yml	guards-advisory	trigger-propagation
sentry-filter	apply-sentry-infra.yml	detect-changes	filter
tenant-filter	tenant-integration.yml	detect-changes	filter
vendor-filter	vendor-pin-verify.yml	detect-changes	filter
legal-lockstep	pr-quality-guards.yml	quality-guards	enforce-legal-lockstep
cgate-changed	pr-quality-guards.yml	quality-advisory	constraint-gates-changed
ss-files-pr	secret-scan.yml	secret-guards	lint-fixture-files-pr
ss-files-nonpr	secret-scan.yml	secret-guards	lint-fixture-files-nonpr
ss-lint	secret-scan.yml	secret-guards	lint-fixture-content'
STEP_FLOOR=12
EXTRACTED=0

extract_steps() {
  local out rc=0
  out="$(python3 -I - "$WF_DIR" "$STEP_DIR" "$STEP_MANIFEST" <<'PY'
import sys, yaml, os
wf_dir, out_dir, manifest = sys.argv[1:4]
docs = {}
bad = 0
n = 0
for line in manifest.splitlines():
    key, wf, job, sid = line.split("\t")
    if wf not in docs:
        docs[wf] = yaml.safe_load(open(os.path.join(wf_dir, wf)))
    steps = (docs[wf].get("jobs", {}).get(job) or {}).get("steps") or []
    hit = [s for s in steps if s.get("id") == sid]
    if len(hit) != 1:
        print("MISSING %s (%s / %s / %s): %d steps found" % (key, wf, job, sid, len(hit)))
        bad += 1
        continue
    s = hit[0]
    if "run" not in s:
        print("NORUN %s" % key); bad += 1; continue
    if "shell" in s:
        print("SHELLKEY %s: the step declares shell:, so plain bash -e {0} is not what Actions runs" % key); bad += 1; continue
    if "${{" in s["run"]:
        print("EXPR %s: the run: body holds a ${{ }} expression; pass it through env: instead" % key); bad += 1; continue
    open(os.path.join(out_dir, key + ".sh"), "w").write(s["run"])
    open(os.path.join(out_dir, key + ".env"), "w").write("\n".join(sorted((s.get("env") or {}).keys())) + "\n")
    n += 1
print("EXTRACTED %d" % n)
sys.exit(1 if bad else 0)
PY
  )" || rc=$?
  EXTRACTED="$(printf '%s\n' "$out" | sed -n 's/^EXTRACTED //p' | tail -1)"
  EXTRACTED="${EXTRACTED:-0}"
  # Process substitution, not a pipe: a `| while` body runs in a subshell and its fail() would never move the counter.
  local l
  while IFS= read -r l; do fail "extract: $l"; done < <(grep -E '^(MISSING|NORUN|SHELLKEY|EXPR)' <<<"$out")
  if [ "$rc" -ne 0 ]; then fail "extraction reported problems (rc=$rc)"; fi
  if [ "$EXTRACTED" -ge "$STEP_FLOOR" ]; then pass "extracted $EXTRACTED run: bodies (floor $STEP_FLOOR)"
  else fail "extracted only $EXTRACTED run: bodies, floor $STEP_FLOOR (a renamed step id must not read as 0 checked, exit 0)"; fi
}

# DEFAULT_ENV: the value of every env: key a converted step declares, per scenario arm. A step declaring a key not named here fails
# with "add KEY to DEFAULT_ENV" instead of silently running with the key unset.
DEV=""
default_env_val() { # <arm: pr|push|mg> <KEY>  -> DEV
  case "$2" in
    EVENT_NAME) case "$1" in pr) DEV=pull_request ;; push) DEV=push ;; mg) DEV=merge_group ;; esac ;;
    BASE_REF) if [ "$1" = push ]; then DEV=""; else DEV=main; fi ;;
    BEFORE_SHA) if [ "$1" = push ]; then DEV="$ROW_BASE"; else DEV=""; fi ;;
    MERGE_SHA) DEV="$ROW_HEAD" ;;
    GH_TOKEN) DEV="not-a-token-fixture-value" ;;
    MERGE_GROUP_BASE_SHA) if [ "$1" = mg ]; then DEV="$ROW_BASE"; else DEV=""; fi ;;
    BASE_SHA) DEV="$ROW_BASE" ;;
    HEAD_SHA) DEV="$ROW_HEAD" ;;
    *) return 1 ;;
  esac
  return 0
}

S_RC=0; S_LOG=""; S_OUT=""
# STEP_LC (default C, the weakest locale the harness pins) is the LC_ALL the step starts under: `STEP_LC=C.UTF-8 run_step ...`.
run_step() { # <step key> <arm> [fail verbs]   (cwd = $ROW_DIR; sets S_RC, S_LOG, S_OUT)
  local key="$1" arm="$2" verbs="${3:-}" k envargs=() path="$SHIM_NODE_DIR:$PATH"
  local outf="$WORK_ROOT/io/gh-output-$ROW_SEQ" logf="$WORK_ROOT/io/log-$ROW_SEQ" tmpd="$WORK_ROOT/io/tmp-$ROW_SEQ"
  [ -s "$STEP_DIR/$key.sh" ] || { fail "$key: no extracted body"; S_RC=99; return; }
  mkdir -p "$tmpd"; : > "$outf"
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if default_env_val "$arm" "$k"; then envargs+=("$k=$DEV"); else fail "$key: step declares env key $k not in DEFAULT_ENV: add $k to DEFAULT_ENV"; fi
  done < "$STEP_DIR/$key.env"
  [ -n "$verbs" ] && { path="$SHIM_FAIL_DIR:$path"; envargs+=("SHIM_FAIL_VERBS=$verbs" "REAL_GIT=$REAL_GIT"); }
  assert_fixture_dir "$ROW_DIR"
  S_RC=0
  (cd "$ROW_DIR" && env -i PATH="$path" HOME="$WORK_ROOT/io" LC_ALL="${STEP_LC:-C}" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
      GITHUB_OUTPUT="$outf" RUNNER_TEMP="$tmpd" NODE_ARGV_FILE="$WORK_ROOT/io/argv-$ROW_SEQ" "${envargs[@]}" \
      bash --noprofile --norc -e "$STEP_DIR/$key.sh") > "$logf" 2>&1 || S_RC=$?
  S_LOG="$(cat "$logf")"
  S_OUT="$(cat "$outf")"
  STEP_ROWS=$((STEP_ROWS + 1))
}
flag_of() { printf '%s\n' "$S_OUT" | sed -n "s/^$1=//p" | tail -1; }
has_flag() { grep -q "^$1=" <<<"$S_OUT"; }
s_ok() { pass "$1"; }
expect_flag() { # <label> <flag> <want>
  local got; got="$(flag_of "$2")"
  if [ "$S_RC" -eq 0 ] && [ "$got" = "$3" ]; then s_ok "$1: $2=$3"
  else fail "$1: want $2=$3 got '$got' rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-220))"; fi
}
expect_closed() { # <label> <flag>: the step fails (non-zero) and emitted NO value for the flag
  if [ "$S_RC" -ne 0 ] && ! has_flag "$2"; then s_ok "$1: fails closed (rc=$S_RC, no $2 emitted)"
  else fail "$1: want a non-zero exit and no $2 (rc=$S_RC out='$(printf '%s' "$S_OUT" | tr '\n' ' ')' log='$(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-160)')"; fi
}

selftest_step_verdicts() {
  local o_out="$S_OUT" o_log="$S_LOG" o_rc="$S_RC"
  S_OUT=$'other=1\nflag=on'; S_LOG=""; S_RC=0
  selftest_moved "expect_flag accepts the right value" pass expect_flag "selftest" flag on
  selftest_moved "expect_flag rejects a wrong value" fail expect_flag "selftest" flag off
  S_RC=1
  selftest_moved "expect_flag rejects the right value under a non-zero rc" fail expect_flag "selftest" flag on
  S_OUT=""; S_RC=1
  selftest_moved "expect_closed accepts a non-zero rc with no value" pass expect_closed "selftest" flag
  S_RC=0
  selftest_moved "expect_closed rejects a zero rc" fail expect_closed "selftest" flag
  S_OUT="flag=on"; S_RC=1
  selftest_moved "expect_closed rejects an emitted value" fail expect_closed "selftest" flag
  S_OUT="$o_out"; S_LOG="$o_log"; S_RC="$o_rc"
}

# Scenario preconditions (H1): the plain diff must really hide what the row claims the converted step now sees.
scn_precondition() { # <label> <scn> <prefix> <keep>
  local plain name
  if ! plain="$(fg "$ROW_DIR" diff --name-only "$ROW_BASE"..."$ROW_HEAD")"; then fail "$1: precondition: the plain diff failed"; return 1; fi
  case "$2" in
    qe|qtab|qquote|qbs)
      name="$3/$(scn_name "$2")"
      if grep -Fxq -e "$name" <<<"$plain"; then fail "$1: precondition: git did NOT C-quote the name; the row would pass vacuously"; return 1; fi ;;
    rename)
      if grep -Fxq -e "$4" <<<"$plain"; then fail "$1: precondition: the plain diff lists the rename's old path"; return 1; fi ;;
    gitlink)
      if grep -Fxq -e "$3/sm" <<<"$plain"; then fail "$1: precondition: the plain diff lists the gitlink"; return 1; fi ;;
  esac
  return 0
}
apply_scn() { # <scn> <prefix> <keep>
  local d="$ROW_DIR"
  case "$1" in
    qe|qtab|qquote|qbs) put_in "$d" "$2/$(scn_name "$1")" ;;
    rename) mkdir -p "$d/zz-outside" && fg "$d" mv "$3" "zz-outside/$(basename "$3")" ;;
    gitlink) add_gitlink "$d" "$2/sm" ;;
    outside) put_in "$d" "zz-outside/$NAME_E"; put_in "$d" "zz-outside/$NAME_Q"; put_in "$d" "zz-outside/$NAME_BS" ;;
    none) : ;;
  esac
}

ALLROOTS='["apps/cla-evidence/infra","apps/web-platform/infra","infra/github"]'

# A flag step: key arm flag on off prefix keep failmode(err|closed|value:<v>)
flag_step_rows() {
  local key="$1" arm="$2" flag="$3" on="$4" off="$5" prefix="$6" keep="$7" failmode="$8" scn lbl
  for scn in qe qtab qquote qbs rename gitlink outside gitfail; do
    lbl="$key/$arm/$scn"
    new_row || { fail "$lbl: could not build the row"; continue; }
    if [ "$scn" != gitfail ]; then
      apply_scn "$scn" "$prefix" "$keep"
    else
      apply_scn qe "$prefix" "$keep"
    fi
    if ! commit_row; then fail "$lbl: could not commit the row"; free_row; continue; fi
    if ! scn_precondition "$lbl" "$scn" "$prefix" "$keep"; then free_row; continue; fi
    case "$scn" in
      outside) run_step "$key" "$arm"; expect_flag "$lbl (control outside the surface)" "$flag" "$off" ;;
      gitfail)
        run_step "$key" "$arm" diff
        case "$failmode" in
          value:*) expect_flag "$lbl (git fails: the step's own fail-safe)" "$flag" "${failmode#value:}" ;;
          closed) expect_closed "$lbl (git fails)" "$flag" ;;
          err)
            expect_closed "$lbl (git fails)" "$flag"
            if grep -qF '::error::' <<<"$S_LOG"; then s_ok "$lbl: an ::error:: annotation names the failure"; else fail "$lbl: no ::error:: annotation ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-160))"; fi ;;
        esac ;;
      *) run_step "$key" "$arm"; expect_flag "$lbl" "$flag" "$on" ;;
    esac
    free_row
  done
}

# Unanchored, shape-preserving steps: a rename-away row, a control row, and the step's existing `|| true` (a git failure reads as hit=0) UNCHANGED.
advisory_rows() { # <key> <keep>
  local key="$1" keep="$2" lbl
  lbl="$key/pr/rename"
  new_row && apply_scn rename x "$keep" && commit_row && scn_precondition "$lbl" rename x "$keep" || { fail "$lbl: setup"; return; }
  run_step "$key" pr; expect_flag "$lbl" hit 1; free_row
  lbl="$key/pr/outside"
  new_row && apply_scn outside x x && commit_row || { fail "$lbl: setup"; return; }
  run_step "$key" pr; expect_flag "$lbl (control outside the surface)" hit 0; free_row
  lbl="$key/pr/gitfail"
  new_row && apply_scn rename x "$keep" && commit_row || { fail "$lbl: setup"; return; }
  run_step "$key" pr diff; expect_flag "$lbl (hit=0 on a git failure is this step's existing `|| true`, UNCHANGED by this PR)" hit 0; free_row
}

infra_shape_rows() { # arm
  local arm="$1" spec path want lbl
  for spec in \
    "infra/github/main.tf|[\"infra/github\"]|top-level" \
    "apps/web-platform/infra/sentry/x.tf|[\"apps/web-platform/infra\"]|single-ancestor-nested" \
    "apps/web-platform/infra/a/b/c/d.tf|[\"apps/web-platform/infra\"]|deep-nested" \
    "apps/cla-evidence/infra/${NAME_E}|[\"apps/cla-evidence/infra\"]|second-root-é" \
    "docs/${NAME_E}|[]|outside-é"; do
    path="${spec%%|*}"; spec="${spec#*|}"; want="${spec%%|*}"; lbl="infra-dirs/$arm/shape-${spec#*|}"
    new_row || { fail "$lbl: setup"; continue; }
    put_in "$ROW_DIR" "$path"
    commit_row || { fail "$lbl: commit"; free_row; continue; }
    run_step infra-dirs "$arm"; expect_flag "$lbl" directories "$want"
    free_row
  done
}

# infra-validation `dirs` step: the locale, the failed-diff plan matrix, and a control byte in a directory name.
infra_extra_rows() { # arm
  local arm="$1" lbl plain raw="apps/web-platform/infra/"$'\351'".tf"
  # A Latin-1 name is an invalid UTF-8 byte sequence: under a UTF-8 locale grep says "binary file matches" and the root would vanish.
  # The harness pins LC_ALL=C for every step, so the UTF-8 run is explicit; the C-locale run is the control.
  lbl="infra-dirs/$arm/latin1-name"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" "$raw"
  commit_row || { fail "$lbl: commit"; free_row; return; }
  if ! plain="$(fg "$ROW_DIR" diff --name-only "$ROW_BASE"..."$ROW_HEAD")"; then fail "$lbl: precondition: the plain diff failed"
  elif LC_ALL=C grep -Fxq -e "$raw" <<<"$plain"; then fail "$lbl: precondition: git did NOT C-quote the Latin-1 name; the row would pass vacuously"
  else
    run_step infra-dirs "$arm"; expect_flag "$lbl (control, LC_ALL=C)" directories '["apps/web-platform/infra"]'
    STEP_LC=C.UTF-8 run_step infra-dirs "$arm"; expect_flag "$lbl (step started under LC_ALL=C.UTF-8)" directories '["apps/web-platform/infra"]'
  fi
  free_row
  if [ "$arm" != pr ]; then return; fi
  # A failed pull_request diff validates every root but leaves the terraform-plan matrix EMPTY (the credential-bearing job).
  lbl="infra-dirs/pr/gitfail-plan-matrix"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" apps/web-platform/infra/new.tf
  commit_row || { fail "$lbl: commit"; free_row; return; }
  run_step infra-dirs pr; expect_flag "$lbl (control, diff succeeds: the plan matrix mirrors directories)" plan_directories '["apps/web-platform/infra"]'
  run_step infra-dirs pr diff
  expect_flag "$lbl (git fails: validate covers every root)" directories "$ALLROOTS"
  expect_flag "$lbl (git fails: the plan matrix is EMPTY, not every root)" plan_directories '[]'
  free_row
  # A directory name carrying a CR must not reach a `::warning::` workflow command; a plain name with the sentinel still warns.
  lbl="infra-dirs/pr/cr-dir-plan-skip"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" "infra/x"$'\r'"/main.tf"; put_in "$ROW_DIR" "infra/x"$'\r'"/.pr-plan-skip" "skip: fixture"
  commit_row || { fail "$lbl: commit"; free_row; return; }
  run_step infra-dirs pr
  expect_flag "$lbl (the CR root is in directories)" directories '["infra/x\r"]'
  expect_flag "$lbl (the CR root carries the sentinel, so it is out of the plan matrix)" plan_directories '[]'
  if grep -qF '::warning::excluding' <<<"$S_LOG"; then fail "$lbl: a workflow-command annotation was emitted for a directory name holding a control byte ($(printf '%s' "$S_LOG" | tr '\n\r' '|~' | cut -c1-200))"
  else s_ok "$lbl: no ::warning:: annotation for a control-byte directory name"; fi
  free_row
  lbl="infra-dirs/pr/plain-dir-plan-skip"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" infra/github/.pr-plan-skip "skip: fixture"; put_in "$ROW_DIR" infra/github/new.tf
  commit_row || { fail "$lbl: commit"; free_row; return; }
  run_step infra-dirs pr
  expect_flag "$lbl (control: a sentinel root is out of the plan matrix)" plan_directories '[]'
  if grep -qF '::warning::excluding infra/github from the terraform-plan matrix' <<<"$S_LOG"; then s_ok "$lbl: control: an ordinary sentinel root still emits its ::warning::"
  else fail "$lbl: control: the ordinary ::warning:: is missing ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; fi
  free_row
}

legal_rows() {
  local d lbl
  lbl="legal-lockstep/pr/control-no-surface"
  new_row && put_in "$ROW_DIR" docs/other.md "edited" && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 0 ] && grep -qF 'trivially passes' <<<"$S_LOG"; then s_ok "$lbl: trivially passes"; else fail "$lbl: want rc=0 + 'trivially passes' got rc=$S_RC"; fi
  free_row
  lbl="legal-lockstep/pr/surface-renamed-away"
  new_row && mkdir -p "$ROW_DIR/zz-outside" && fg "$ROW_DIR" mv apps/web-platform/server/dsar-export.ts zz-outside/dsar-export.ts && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 1 ] && grep -qF 'FAILED' <<<"$S_LOG"; then s_ok "$lbl: a rename AWAY from a DSAR surface file still requires the legal docs"; else fail "$lbl: want rc=1 + FAILED got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; fi
  free_row
  lbl="legal-lockstep/mg/surface-renamed-away"
  new_row && mkdir -p "$ROW_DIR/zz-outside" && fg "$ROW_DIR" mv apps/web-platform/server/dsar-export.ts zz-outside/dsar-export.ts && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep mg
  if [ "$S_RC" -eq 1 ] && grep -qF 'FAILED' <<<"$S_LOG"; then s_ok "$lbl: the merge_group arm judges the same way"; else fail "$lbl: want rc=1 got rc=$S_RC"; fi
  free_row
  lbl="legal-lockstep/pr/surface-é-name"
  new_row && put_in "$ROW_DIR" "apps/web-platform/app/api/account/export/$NAME_E" && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 1 ] && grep -qF 'FAILED' <<<"$S_LOG"; then s_ok "$lbl: a non-ASCII surface name is a surface hit"; else fail "$lbl: want rc=1 got rc=$S_RC"; fi
  free_row
  lbl="legal-lockstep/pr/legal-doc-renamed-away"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"; put_in "$d" docs/legal/gdpr-policy.md "edited"
  put_in "$d" docs/legal/data-protection-disclosure.md "edited"; put_in "$d" knowledge-base/legal/compliance-posture.md "edited"
  mkdir -p "$d/zz-outside" && fg "$d" mv docs/legal/privacy-policy.md zz-outside/privacy-policy.md && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 1 ] && grep -qF '::error::  - docs/legal/privacy-policy.md' <<<"$S_LOG"; then s_ok "$lbl: a legal document renamed AWAY is still reported missing (destination-only read)"
  else fail "$lbl: want rc=1 + privacy-policy.md reported missing got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-240))"; fi
  free_row
  lbl="legal-lockstep/pr/all-updated"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"; put_in "$d" docs/legal/privacy-policy.md "edited"; put_in "$d" docs/legal/gdpr-policy.md "edited"
  put_in "$d" docs/legal/data-protection-disclosure.md "edited"; put_in "$d" knowledge-base/legal/compliance-posture.md "edited"
  commit_row || { fail "$lbl: commit"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 0 ] && grep -qF 'Gate passes' <<<"$S_LOG"; then s_ok "$lbl: surface + all four documents updated passes (must-PASS)"; else fail "$lbl: want rc=0 + 'Gate passes' got rc=$S_RC"; fi
  free_row
  # (#12332) The legal-docs match reads the NUL stream: a DIRECTORY name holding a newline must not split into extra "lines"
  # that satisfy a required document (`zz<LF>docs/legal/privacy-policy.md` is not `docs/legal/privacy-policy.md`).
  lbl="legal-lockstep/pr/lf-named-twins"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  local doc lfsplit ok=1
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"
  for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
    put_in "$d" "zz${NL}$doc" "edited"
  done
  commit_row || { fail "$lbl: commit"; return; }
  if ! lfsplit="$(fg "$d" diff -z --name-only "$ROW_BASE"..."$ROW_HEAD" | tr '\0' '\n')"; then fail "$lbl: precondition: the NUL list failed"; ok=0; else
    for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
      grep -Fxq -e "$doc" <<<"$lfsplit" || { fail "$lbl: precondition: an LF-split would not yield the line $doc; the row proves nothing"; ok=0; }
    done
  fi
  if [ "$ok" -eq 1 ]; then
    run_step legal-lockstep pr
    if [ "$S_RC" -eq 1 ] && grep -qF 'FAILED' <<<"$S_LOG" && grep -qF '::error::  - docs/legal/privacy-policy.md' <<<"$S_LOG"; then s_ok "$lbl: four LF-named twins of the legal documents do NOT satisfy the lockstep gate"
    else fail "$lbl: want rc=1 + FAILED + privacy-policy.md missing got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-240))"; fi
  fi
  free_row
  lbl="legal-lockstep/pr/lf-named-twins-plus-real-docs"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"
  for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
    put_in "$d" "zz${NL}$doc" "edited"; put_in "$d" "$doc" "edited"
  done
  commit_row || { fail "$lbl: commit"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 0 ] && grep -qF 'Gate passes' <<<"$S_LOG"; then s_ok "$lbl: control: the four real documents present passes even beside LF-named twins"; else fail "$lbl: want rc=0 + 'Gate passes' got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; fi
  free_row
  lbl="legal-lockstep/pr/gitfail"
  new_row && put_in "$ROW_DIR" docs/other.md "edited" && commit_row || { fail "$lbl: setup"; return; }
  run_step legal-lockstep pr diff
  if [ "$S_RC" -ne 0 ] && ! grep -qF 'trivially passes' <<<"$S_LOG"; then s_ok "$lbl: a git failure fails the step, it does not pass trivially"; else fail "$lbl: want a non-zero exit, got rc=$S_RC"; fi
  free_row
}

# secret-scan: the selection steps and the linter step, with a recording `node`. Names reach the linter argv byte-for-byte.
SS_WANT=""
ss_argv() { # prints the recorded argv, one per line, sorted (C locale)
  local f="$WORK_ROOT/io/argv-$ROW_SEQ"
  [ -f "$f" ] || return 0
  local -a a=()
  mapfile -d '' -t a < "$f"
  [ "${#a[@]}" -gt 0 ] && printf '%s\n' "${a[@]}" | LC_ALL=C sort
}
secret_scan_rows() {
  local d lbl got pdir='apps/web-platform/test/fixtures' sdir='tests/scripts/fixtures'
  # pull_request arm: three special fixture names + one control outside the patterns.
  lbl="secret-scan/pr/special-names"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" "$pdir/é\"q.json"; put_in "$d" "$pdir/b\\s.json"; put_in "$d" "$sdir/$NAME_TAB"; put_in "$d" "docs/${NAME_E}.json"
  commit_row || { fail "$lbl: commit"; return; }
  run_step ss-files-pr pr
  if [ "$S_RC" -ne 0 ]; then fail "$lbl: the selection step failed rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; else
    run_step ss-lint pr
    got="$(ss_argv)"
    SS_WANT="$(printf '%s\n' "$pdir/é\"q.json" "$pdir/b\\s.json" "$sdir/$NAME_TAB" | LC_ALL=C sort)"
    if [ "$S_RC" -eq 0 ] && [ "$got" = "$SS_WANT" ]; then s_ok "$lbl: the accented, quoted, backslash and tab names reach the linter argv intact; the control stays out"
    else fail "$lbl: linter argv differs (rc=$S_RC): got [$(printf '%s' "$got" | tr '\n' '|')] want [$(printf '%s' "$SS_WANT" | tr '\n' '|')]"; fi
  fi
  free_row
  # pull_request arm, the workflow itself in the diff: the FULL tracked tree is selected.
  lbl="secret-scan/pr/workflow-in-diff"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" .github/workflows/secret-scan.yml "edited"; put_in "$d" "$pdir/é\"q.json"
  commit_row || { fail "$lbl: commit"; return; }
  run_step ss-files-pr pr
  run_step ss-lint pr
  got="$(ss_argv)"
  SS_WANT="$(printf '%s\n' "$pdir/keep.json" "$pdir/é\"q.json" | LC_ALL=C sort)"
  if [ "$S_RC" -eq 0 ] && [ "$got" = "$SS_WANT" ]; then s_ok "$lbl: the full tracked tree is selected through the NUL chain"; else fail "$lbl: got [$(printf '%s' "$got" | tr '\n' '|')] want [$(printf '%s' "$SS_WANT" | tr '\n' '|')] rc=$S_RC"; fi
  free_row
  # pull_request arm, nothing in scope.
  lbl="secret-scan/pr/nothing-in-scope"
  new_row && put_in "$ROW_DIR" docs/other.md "edited" && commit_row || { fail "$lbl: setup"; return; }
  run_step ss-files-pr pr
  run_step ss-lint pr
  if [ "$S_RC" -eq 0 ] && grep -qF 'No fixture/golden/snapshot files in scope' <<<"$S_LOG" && [ ! -s "$WORK_ROOT/io/argv-$ROW_SEQ" ]; then s_ok "$lbl: an empty selection skips the linter (control)"
  else fail "$lbl: want the skip message and no linter call, rc=$S_RC"; fi
  free_row
  # pull_request arm, git fails: the step must FAIL, never print the skip message.
  lbl="secret-scan/pr/gitfail"
  new_row && put_in "$ROW_DIR" "$pdir/é\"q.json" && commit_row || { fail "$lbl: setup"; return; }
  run_step ss-files-pr pr diff
  if [ "$S_RC" -ne 0 ] && [ ! -s "$WORK_ROOT/io/tmp-$ROW_SEQ/lint-files.txt" ]; then s_ok "$lbl: a failed diff fails the selection step (it does not select nothing)"
  else fail "$lbl: want a non-zero exit and no selected list, rc=$S_RC"; fi
  free_row
  # push / schedule arm: every tracked fixture, NUL-delimited.
  lbl="secret-scan/nonpr/special-names"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" "$pdir/é\"q.json"; put_in "$d" "$pdir/b\\s.json"; put_in "$d" "$sdir/$NAME_TAB"; put_in "$d" "docs/${NAME_E}.json"
  commit_row || { fail "$lbl: commit"; return; }
  run_step ss-files-nonpr push
  run_step ss-lint push
  got="$(ss_argv)"
  SS_WANT="$(printf '%s\n' "$pdir/keep.json" "$pdir/é\"q.json" "$pdir/b\\s.json" "$sdir/$NAME_TAB" | LC_ALL=C sort)"
  if [ "$S_RC" -eq 0 ] && [ "$got" = "$SS_WANT" ]; then s_ok "$lbl: the push/schedule arm selects the same names through the NUL chain"; else fail "$lbl: got [$(printf '%s' "$got" | tr '\n' '|')] want [$(printf '%s' "$SS_WANT" | tr '\n' '|')] rc=$S_RC"; fi
  free_row
  lbl="secret-scan/nonpr/gitfail"
  new_row && commit_row || { fail "$lbl: setup"; return; }
  run_step ss-files-nonpr push ls-files
  if [ "$S_RC" -ne 0 ]; then s_ok "$lbl: a failed ls-files fails the push/schedule selection step"; else fail "$lbl: want a non-zero exit, got rc=0"; fi
  free_row
}

section_steps() {
  echo "── steps"
  selftest_step_verdicts
  extract_steps
  # The DEFAULT_ENV subset check, once per step, against the arm it runs under: an undeclared key fails inside run_step.
  new_row || { fail "steps: could not build a row"; return; }
  commit_row
  local k
  for k in infra-dirs ci-filter ci-canary ci-propagation sentry-filter tenant-filter vendor-filter legal-lockstep cgate-changed ss-files-pr ss-files-nonpr ss-lint; do
    if [ ! -f "$STEP_DIR/$k.env" ]; then
      fail "$k: no extracted .env file (the step was not extracted)"
    elif grep -q . "$STEP_DIR/$k.env"; then
      local bad=0 key
      while IFS= read -r key; do
        [ -n "$key" ] || continue
        default_env_val pr "$key" || { fail "$k: step declares env key $key not in DEFAULT_ENV: add $key to DEFAULT_ENV"; bad=1; }
      done < "$STEP_DIR/$k.env"
      [ "$bad" -eq 0 ] && pass "$k: every declared env: key is in DEFAULT_ENV"
    else
      pass "$k: declares no env: keys"
    fi
  done
  free_row
  # `^`-anchored steps. key arm flag on off prefix keep failmode
  flag_step_rows infra-dirs pr directories '["apps/web-platform/infra"]' '[]' apps/web-platform/infra apps/web-platform/infra/keep.tf "value:$ALLROOTS"
  flag_step_rows infra-dirs push directories '["apps/web-platform/infra"]' '[]' apps/web-platform/infra apps/web-platform/infra/keep.tf "value:$ALLROOTS"
  infra_shape_rows pr
  infra_shape_rows push
  infra_extra_rows pr
  infra_extra_rows push
  flag_step_rows ci-filter pr docs true false plugins/soleur/docs plugins/soleur/docs/keep.md value:true
  flag_step_rows sentry-filter pr sentry true false apps/web-platform/infra/sentry apps/web-platform/infra/sentry/keep.tf err
  flag_step_rows tenant-filter pr tenant true false apps/web-platform/server apps/web-platform/server/keep.ts err
  flag_step_rows vendor-filter pr vendor true false plugins/soleur/skills/gdpr-gate/references plugins/soleur/skills/gdpr-gate/references/keep.md err
  flag_step_rows cgate-changed pr changed true false apps/web-platform/infra apps/web-platform/infra/keep.tf closed
  # Shape-preserving, unanchored steps.
  advisory_rows ci-canary apps/web-platform/Dockerfile
  advisory_rows ci-propagation apps/web-platform/server/agent-env.ts
  legal_rows
  secret_scan_rows
  if [ "$STEP_ROWS" -gt 0 ]; then pass "rows executed: $STEP_ROWS step executions"; else fail "zero step rows executed"; fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# SECTION sentinel
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# The exemption table: file<TAB>content anchor<TAB>reason. One row per SITE (two identical sites need two rows), never a line number. A
# row that matches no site is STALE and fails. Keep this short: every row is a reader this PR knowingly leaves on the plain form.
EXEMPT_TABLE='ci.yml	git diff --no-renames --name-only origin/main...HEAD 2>/dev/null	trigger-canary step: the match is an unanchored substring grep (no ^), not a prefix test; the diff ends `2>/dev/null || true`, so a git failure reads as hit=0 (unchanged by this PR; no comment in the step documents it)
ci.yml	git diff --no-renames --name-only origin/main...HEAD 2>/dev/null	trigger-propagation step: the match is an unanchored substring grep (no ^), not a prefix test; the diff ends `2>/dev/null || true`, so a git failure reads as hit=0 (unchanged by this PR; no comment in the step documents it)
pr-quality-guards.yml	gh pr diff "$PR_NUMBER" --repo "$GH_REPO" --name-only	the gh CLI offers no NUL-delimited output; the match is the fixed ASCII prefix .claude/worktrees/; the `|| true` after grep also masks a gh failure (unchanged by this PR)
pr-quality-guards.yml	--diff-filter=AMRT "$BASE_SHA"	the step refuses a C-quoted path under a scanned skill/agent directory itself (its own ^" check, fail closed)
skill-security-scan-postmerge.yml	--diff-filter=AMRT "$parent"	the step refuses a C-quoted path under a scanned skill/agent directory itself (its own ^" check, fail closed)
reusable-release.yml	git diff --name-only HEAD~1 -- $PATH_FILTER	emptiness test only (is any path under the filter changed); pathspec-filtered
web-platform-release.yml	--name-only "${WR_HEAD_SHA}~1" "$WR_HEAD_SHA" -- $RELEASE_PATH_FILTER	emptiness test only; pathspec-filtered
tenant-integration.yml	git log --format= --name-only	emptiness test only (a migration was touched anywhere in the PR history)'
SENT_FILE_FLOOR=100
SENT_SITE_FLOOR=20

# The hooks and scripts this PR converts keep `-z` (file<TAB>diff-line regex).
PINNED_Z='.claude/hooks/ship-cmo-content-gate.sh	diff[^|]* -z( |$)
.claude/hooks/ship-cmo-content-gate.sh	LC_ALL=C grep -zE .\^\(plugins/soleur/docs/blog/
.claude/hooks/ship-runbook-ssh-gate.sh	diff[^|]* -z( |$)
plugins/soleur/scripts/changed-paths.sh	diff -z --no-renames --ignore-submodules=none --name-only
apps/web-platform/.github/workflows/constraint-gates.yml	changed_files=.*git diff -z --no-renames --ignore-submodules=none --name-only
.github/workflows/pr-quality-guards.yml	surface_files=.*git diff -z --no-renames --ignore-submodules=none --name-only
.github/workflows/pr-quality-guards.yml	git diff -z --name-only "\$\{diff_base\}"\.\.\.HEAD > "\$changed_nul"
.github/workflows/pr-quality-guards.yml	grep -zFxc -- "\$legal" "\$changed_nul"
.github/workflows/secret-scan.yml	CHANGED=.*git diff -z --name-only'

SENT_PY="$WORK_ROOT/sentinel.py"
cat > "$SENT_PY" <<'PY'
import re, sys
table_path = sys.argv[1]
files = sys.argv[2:]
rows = []
for ln in open(table_path, encoding="utf-8").read().split("\n"):
    if not ln.strip() or ln.startswith("#"):
        continue
    f, a, r = ln.split("\t", 2)
    rows.append([f, a, r, False])
# A segment is cut only at `|`, `;`, `&` and a newline: NOT at `)`, so `git diff "$(git merge-base a b)"...HEAD --name-only` is one site.
GIT = re.compile(r"\bgit(?:\s+(?:-c\s+\S+|-C\s+(?:\"[^\"]*\"|'[^']*'|\S+)|--no-pager|-P|--git-dir=\S+|--work-tree=\S+))*\s+(?:diff|log|show|diff-tree)\b[^|;&\n]*")
GH = re.compile(r"\bgh\s+pr\s+diff\b[^|;&\n]*")
# A trailing `# comment` is not part of the command: `... --name-only a...b # was -z )` is still UNCONVERTED.
COMMENT = re.compile(r"(?:^|\s)#.*$")
NAMES = re.compile(r"--name-only|--name-status")
Z = re.compile(r"(?:^|\s)-z(?![\w-])")
scanned = sites = exempt = 0
unlisted = []
for path in files:
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    scanned += 1
    base = path.rsplit("/", 1)[-1]
    logical = []
    cur = None
    for i, line in enumerate(text.split("\n"), 1):
        if cur is None and re.match(r"^\s*#", line):
            continue
        if cur is None:
            cur = [i, ""]
        if line.endswith("\\"):
            cur[1] += line[:-1].strip() + " "
            continue
        cur[1] += line.strip()
        logical.append(tuple(cur))
        cur = None
    for lineno, ltxt in logical:
        for rx in (GIT, GH):
            for m in rx.finditer(ltxt):
                seg = COMMENT.sub("", m.group(0))
                if not NAMES.search(seg):
                    continue
                sites += 1
                if Z.search(seg):
                    continue
                hit = None
                for r in rows:
                    if not r[3] and r[0] == base and r[1] in ltxt:
                        hit = r
                        break
                if hit:
                    hit[3] = True
                    exempt += 1
                else:
                    unlisted.append("%s:%d :: %s" % (path, lineno, seg.strip()[:110]))
print("SCANNED %d" % scanned)
print("SITES %d" % sites)
print("EXEMPT %d" % exempt)
for u in unlisted:
    print("UNLISTED " + u)
for r in rows:
    if not r[3]:
        print("STALE %s :: %s" % (r[0], r[1]))
PY

sent_run() { # <table text> <files...>  -> SENT_OUT
  printf '%s\n' "$1" > "$WORK_ROOT/io/table.tsv"; shift
  SENT_OUT="$(python3 -I "$SENT_PY" "$WORK_ROOT/io/table.tsv" "$@")"
}
sent_n() { printf '%s\n' "$SENT_OUT" | sed -n "s/^$1 //p" | head -1; }

# One pinned row: comment lines are stripped first (a `# git diff -z ...` comment must not satisfy the pin), then the line regex must match.
pinned_z_check() { # <file> <regex>
  local f="$1" rx="$2" body
  if [ ! -f "$REPO_ROOT/$f" ]; then fail "sentinel pinned: $f is missing"; return; fi
  body="$(grep -v '^[[:space:]]*#' "$REPO_ROOT/$f")"
  if grep -Eq -e "$rx" <<<"$body"; then pass "sentinel pinned: $f keeps its NUL-delimited read ($rx)"; else fail "sentinel pinned: $f lost its read (expected a non-comment line matching: $rx)"; fi
}

selftest_pinned() {
  selftest_moved "pinned_z_check accepts a pinned line that exists" pass pinned_z_check plugins/soleur/scripts/changed-paths.sh 'diff -z --no-renames'
  selftest_moved "pinned_z_check rejects a regex no line matches" fail pinned_z_check plugins/soleur/scripts/changed-paths.sh 'selftest-no-such-line-zzz'
  selftest_moved "pinned_z_check rejects a pin only a comment line satisfies" fail pinned_z_check plugins/soleur/scripts/changed-paths.sh '^# changed-paths.sh -- print the changed-path list'
}

# Skill prose is not executed here; this pins its SPELLING: every `changed-paths.sh` in a skill is the whole call form
# `bash "${CLAUDE_PLUGIN_ROOT:-}/scripts/changed-paths.sh"` (a bare or doubled name resolves against the wrong cwd or an unset root).
SKILL_CALL='bash "${CLAUDE_PLUGIN_ROOT:-}/scripts/changed-paths.sh"'
skill_prose_pins() {
  local sk f body total good
  for sk in preflight ship review; do
    f="plugins/soleur/skills/$sk/SKILL.md"
    if [ ! -f "$REPO_ROOT/$f" ]; then fail "skill pin: $f is missing"; continue; fi
    body="$(grep -v '^[[:space:]]*#' "$REPO_ROOT/$f")"
    total="$(grep -o -- 'changed-paths\.sh' <<<"$body" | wc -l)"
    good="$(grep -oF -- "$SKILL_CALL" <<<"$body" | wc -l)"
    if [ "$total" -ge 1 ] && [ "$total" -eq "$good" ]; then pass "skill pin: every changed-paths.sh in $sk/SKILL.md is the call form $SKILL_CALL ($good of $total)"
    else fail "skill pin: $f has $total changed-paths.sh mention(s) but only $good in the call form $SKILL_CALL"; fi
  done
}

section_sentinel() {
  echo "── sentinel"
  # Harness rows against synthetic workflow files (H1/H2): the comment-stripping step, the -c spelling, per-site entries, continuations.
  local sd="$WORK_ROOT/sent"
  mkdir -p "$sd"
  cat > "$sd/a.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          # git diff --name-only | grep -E '^x'
          echo done
YML
  sent_run "" "$sd/a.yml"
  if [ "$(sent_n SITES)" = 0 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel H1: a comment line naming the phrase stays GREEN"; else fail "sentinel H1: comment line was scanned: $SENT_OUT"; fi
  cat > "$sd/b.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          echo "git diff --name-only | grep '^x'"
YML
  sent_run "" "$sd/b.yml"
  if grep -q '^UNLISTED .*b\.yml:5' <<<"$SENT_OUT"; then pass "sentinel H1: the same text inside a run: string literal is RED, with file:line"; else fail "sentinel H1: run: literal not flagged: $SENT_OUT"; fi
  cat > "$sd/c.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          X=$(git -c core.quotePath=false diff -z --no-renames --name-only a...b | tr '\0' '\n')
YML
  sent_run "" "$sd/c.yml"
  if [ "$(sent_n SITES)" = 1 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel H2: a -c core.quotePath=false diff -z site passes"; else fail "sentinel H2: -z site flagged: $SENT_OUT"; fi
  cat > "$sd/d.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          A=$(git diff --name-only a...b)
          B=$(git diff --name-only a...b)
YML
  sent_run "d.yml	git diff --name-only a...b	only the first" "$sd/d.yml"
  if [ "$(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED')" = 1 ]; then pass "sentinel: two sites in one file, one exemption row: the second is RED (entries are per site)"; else fail "sentinel: per-site accounting broke: $SENT_OUT"; fi
  sent_run "d.yml	git diff --name-only a...b	one
d.yml	git diff --name-only a...b	two
d.yml	a reader that was deleted	stale" "$sd/d.yml"
  if grep -q '^STALE d.yml :: a reader that was deleted' <<<"$SENT_OUT" && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel: an entry that matches no site is STALE"; else fail "sentinel: stale accounting broke: $SENT_OUT"; fi
  cat > "$sd/e.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          X=$(git diff \
            --name-only "origin/${B}...HEAD" \
            | grep -E '^x')
YML
  sent_run "" "$sd/e.yml"
  if grep -q '^UNLISTED .*e\.yml:5' <<<"$SENT_OUT"; then pass "sentinel: a backslash-continued reader is joined and caught"; else fail "sentinel: continuation not joined: $SENT_OUT"; fi

  # The spellings a narrow pattern let through. Each UNCONVERTED spelling is exactly one site and RED; each converted twin is one site and GREEN.
  local sp_i=0 sp_label sp_body
  while IFS='~' read -r sp_label sp_body; do
    [ -n "$sp_label" ] || continue
    sp_i=$((sp_i + 1))
    printf 'jobs:\n  j:\n    steps:\n      - run: |\n          %s\n' "$sp_body" > "$sd/sp$sp_i.yml"
    sent_run "" "$sd/sp$sp_i.yml"
    if [ "$(sent_n SITES)" = 1 ] && grep -q "^UNLISTED .*sp$sp_i\\.yml:5" <<<"$SENT_OUT"; then pass "sentinel spelling: $sp_label is a RED site"
    else fail "sentinel spelling: $sp_label was not flagged as one unlisted site: $SENT_OUT"; fi
  done <<'SPELLINGS'
git -C "$d" diff~X=$(git -C "$d" diff --name-only a...b)
git --no-pager diff~X=$(git --no-pager diff --name-only a...b)
git diff with a nested $(...) in the range~X=$(git diff "$(git merge-base a b)"...HEAD --name-only)
a trailing comment naming -z~X=$(git diff --name-only a...b # was -z )
SPELLINGS
  local sc_i=0 sc_label sc_body
  while IFS='~' read -r sc_label sc_body; do
    [ -n "$sc_label" ] || continue
    sc_i=$((sc_i + 1))
    printf 'jobs:\n  j:\n    steps:\n      - run: |\n          %s\n' "$sc_body" > "$sd/sc$sc_i.yml"
    sent_run "" "$sd/sc$sc_i.yml"
    if [ "$(sent_n SITES)" = 1 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel control: the converted twin of $sc_label is GREEN (one site)"
    else fail "sentinel control: the converted twin of $sc_label was flagged or not counted: $SENT_OUT"; fi
  done <<'CONTROLS'
git -C "$d" diff~X=$(git -C "$d" diff -z --name-only a...b | tr '\0' '\n')
git --no-pager diff~X=$(git --no-pager diff -z --name-only a...b | tr '\0' '\n')
git diff with a nested $(...) in the range~X=$(git diff -z "$(git merge-base a b)"...HEAD --name-only | tr '\0' '\n')
a trailing comment~X=$(git diff -z --name-only a...b | tr '\0' '\n') # note
CONTROLS

  # The live scan over the TRACKED workflows.
  local -a wf=()
  mapfile -t wf < <(git -C "$REPO_ROOT" ls-files '.github/workflows/*.yml' | sed "s|^|$REPO_ROOT/|")
  sent_run "$EXEMPT_TABLE" "${wf[@]}"
  local scanned sites exempt nunl nstale
  scanned="$(sent_n SCANNED)"; sites="$(sent_n SITES)"; exempt="$(sent_n EXEMPT)"
  nunl="$(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED')"; nstale="$(printf '%s\n' "$SENT_OUT" | grep -c '^STALE')"
  if [ "${scanned:-0}" -ge "$SENT_FILE_FLOOR" ]; then pass "sentinel: scanned $scanned tracked workflow files (floor $SENT_FILE_FLOOR)"; else fail "sentinel: scanned only ${scanned:-0} workflow files, floor $SENT_FILE_FLOOR (the scan glob went stale)"; fi
  if [ "${sites:-0}" -ge "$SENT_SITE_FLOOR" ]; then pass "sentinel: found $sites reader sites (floor $SENT_SITE_FLOOR)"; else fail "sentinel: found only ${sites:-0} reader sites, floor $SENT_SITE_FLOOR (the classifier stopped matching)"; fi
  if [ "$nunl" -eq 0 ]; then pass "sentinel: 0 unlisted sites"; else
    while IFS= read -r l; do
      fail "sentinel: ${l#UNLISTED } -- every changed-path reader must carry a standalone -z (git diff -z --no-renames --ignore-submodules=none --name-only ... | tr '\\0' '\\n'): add -z or add a row to EXEMPT_TABLE"
    done < <(printf '%s\n' "$SENT_OUT" | grep '^UNLISTED')
  fi
  if [ "$nstale" -eq 0 ]; then pass "sentinel: 0 stale exemption entries"; else while IFS= read -r l; do fail "sentinel: stale exemption entry ${l#STALE }"; done < <(printf '%s\n' "$SENT_OUT" | grep '^STALE'); fi
  echo "census: ${sites:-0} sites, $nunl unlisted, $nstale stale ($exempt exempt)"
  # The pinned must-keep-`-z` list.
  selftest_pinned
  local row
  while IFS= read -r row; do
    pinned_z_check "${row%%$'\t'*}" "${row#*$'\t'}"
  done <<< "$PINNED_Z"
  skill_prose_pins
}

case "$SECTION" in
  all) section_helper; section_steps; section_sentinel ;;
  helper) section_helper ;;
  steps) section_steps ;;
  sentinel) section_sentinel ;;
esac

# Assertion floors: a green run that executed nothing is the failure this block exists to refuse (H3).
total=$((PASS + FAIL))
if [ "$SECTION" = all ] || [ "$SECTION" = helper ]; then
  if [ "$HELPER_ROWS" -lt 76 ]; then printf '[FATAL] helper floor: only %s helper rows ran, want >=76\n' "$HELPER_ROWS" >&2; exit 1; fi
fi
if [ "$SECTION" = all ] || [ "$SECTION" = steps ]; then
  if [ "$STEP_ROWS" -lt 99 ]; then printf '[FATAL] steps floor: only %s step executions ran, want >=99\n' "$STEP_ROWS" >&2; exit 1; fi
fi
# Exact current totals (the floors are the full count, not a margin below it): helper 76 + steps 116 + sentinel 30.
case "$SECTION" in all) floor=222 ;; helper) floor=76 ;; steps) floor=116 ;; sentinel) floor=30 ;; esac
# Every positive control must have run (an inert verdict helper is caught inside selftest_moved; a skipped self-test is caught here).
case "$SECTION" in all) want_self=14 ;; helper) want_self=5 ;; steps) want_self=6 ;; sentinel) want_self=3 ;; esac
if [ "$SELFTESTS" -ne "$want_self" ]; then printf '[FATAL] self-test count: ran %s verdict-helper self-tests, want %s\n' "$SELFTESTS" "$want_self" >&2; exit 1; fi
if [ "$total" -lt "$floor" ]; then printf '[FATAL] assertion floor: only %s assertions ran, want >=%s\n' "$total" "$floor" >&2; exit 1; fi
echo
echo "helper rows: $HELPER_ROWS, executed steps: $STEP_ROWS"
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
