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
#   sentinel  three censuses plus pins. Every `git diff|log|show ... --name-only|--name-status` (and `gh pr diff ... --name-only`) site in
#             (1) .github/workflows/*.yml, (2) tracked non-test *.sh *.py *.ts *.mjs under .claude/hooks, scripts, plugins/soleur/scripts,
#             plugins/soleur/skills/*/scripts, apps/web-platform/scripts and .github/scripts (Python/ts argv lists and `gh api .../files|.../compare`
#             readers included), and (3) the closed prose list (the ship, one-shot, work, qa, review, preflight and postmerge SKILL.md files plus the
#             converted references and agents) is CONVERTED -- `--ignore-submodules=none` AND (`-z` OR `--no-renames`) AND no swallowed failure
#             (`|| true`); a `gh api` files/compare reader must emit `(.previous_filename // empty)` -- or has a reasoned exemption row. Stale rows fail,
#             floors apply. PINNED_Z keeps what the census cannot see (prose, the previous_filename emitting form, flag-only sites).
#
# NOT COVERED (so a reader of a green run is not told more than it proves): skill prose outside the closed list (lesson and example text is
# out by construction); the prose pins check SPELLING and the failure arm, they do not execute prose; `--raw` readers (ci.yml e2e / shard-totality
# classifiers fail closed, executed by ci-classify-step-exec.test.sh); `git ls-files` / `ls-tree` readers; a reader built from a launcher array the
# scanner does not know. A conversion that leaves --no-renames off a `-z` site stays GREEN by the ruled predicate (D1); the PINNED_Z rows hold the
# three-flag form for the sites that matter.
#
# THE REMAINDER, reasoned (class | site | converted? | why). Every row is also a row of the exemption table named last; none is a deferral.
#   status letters are the data | ship-kb-archive-gate.sh, founder-check.py, lint-ratchet.py, battery-refusal-wait.sh/test-all.sh `-M` rows, review:118, preflight:304 | NC | the R/C row IS the input; --no-renames would erase it | CODE/PROSE
#   destination-only by design | legal lockstep, secret-scan fixture selection, brand-hex gate, check-sweep-completeness.sh, pr-overlap other-PR list | NC | the NEW path is the file that exists to be read; an old path would satisfy or pollute the check | WORKFLOW/CODE
#   flag-only standing ruling | test-all.sh, battery-refusal-wait.sh | NC | only --ignore-submodules=none was appended in this arc | CODE
#   already fail-closed or closed | lint-migration-api-grants/-immutability, parse-override.sh, lint-skill-body-budget.py, todos reads, ship-cmo-content-gate.sh | NC | a quoted name or an empty list lands on the safe side | CODE/PROSE
#   backstopped (CTO F1/F4) | archive-kb.sh, ship `HASH..HEAD` readers, ship CMO gates, work/qa structural-UI gate, work per-suite recipe | NC | an enforcing hook or required CI check re-reads the same input | CODE/PROSE
#   different data source | postmerge `gh pr diff`, one-shot:83, tweet-eligibility.sh, check-pr-body-vs-diff.sh | NC | gh offers no NUL output; advisory or fail-closed | CODE/PROSE
#   not a changed-path reader | conflict listings (--diff-filter=U), usage/message/lesson text, benchmark and replay tooling | NC | no gate reads the list | CODE/PROSE
#   everything else the census finds is converted (waves 1-3) and held by the three-flag predicate or a PINNED_Z row.
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
CENSUS_ROWS=0
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
WORK_ROOT="$(mktemp -d -t changed-path-readers.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
# A relative TMPDIR would make every path below relative; refuse it here so the root is provably absolute.
case "$WORK_ROOT" in /*) : ;; *) echo "FATAL: WORK_ROOT is not absolute: $WORK_ROOT" >&2; exit 2 ;; esac
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
  local name="$1" want="$2" p0=$PASS f0=$FAIL h0=$HELPER_ROWS s0=$STEP_ROWS c0=$CENSUS_ROWS dp df
  shift 2
  "$@" >/dev/null
  dp=$((PASS - p0)); df=$((FAIL - f0))
  PASS=$p0; FAIL=$f0; HELPER_ROWS=$h0; STEP_ROWS=$s0; CENSUS_ROWS=$c0
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

# LOCALE PROBE. Every UTF-8 row below (the Latin-1 name rows, the secret-scan rows) is only meaningful if C.UTF-8 really behaves as a UTF-8
# locale on THIS host: GNU grep must reject an invalid UTF-8 byte (count 0) where the byte locale accepts it (count 1). On a host without the
# locale the Latin-1 rows would pass VACUOUSLY, so this is a FATAL (printf + exit, never fail()), not a row.
HELPER_LC=C.UTF-8
# A child bash records the LC_ALL it STARTED under (BASH_ENV is read by every non-interactive bash, --norc or not), so a row that claims
# "ran under C.UTF-8" is checked against what the helper or step RECEIVED, not against what this harness meant to pass.
LC_RECORDER="$WORK_ROOT/lc-recorder.sh"
printf '%s\n' 'printf "%s\n" "${LC_ALL-<unset>}" >> "${LC_RECORD:-/dev/null}"' > "$LC_RECORDER"
_lc_utf8="$(printf '\351\n' | LC_ALL="$HELPER_LC" grep -c . 2>/dev/null)"
_lc_byte="$(printf '\351\n' | LC_ALL=C grep -c . 2>/dev/null)"
if [ "$_lc_utf8" != 0 ] || [ "$_lc_byte" != 1 ]; then
  printf 'FATAL: locale probe: LC_ALL=%s grep -c . on an invalid UTF-8 byte gave %s (want 0) and LC_ALL=C gave %s (want 1); the UTF-8 rows would pass vacuously on this host\n' \
    "$HELPER_LC" "$_lc_utf8" "$_lc_byte" >&2
  exit 1
fi

# The names git C-quotes (the point of every row), plus a glob-looking one.
NAME_E=$'\303\251.tf'
NAME_TAB=$'tab\ttwo.tf'
NAME_Q='q"uote.tf'
NAME_BS='back\slash.tf'
NAME_GLOB='glob[1].tf'
NL=$'\n'
CR=$'\r'

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
SHIM_GH_DIR="$WORK_ROOT/shim-gh"
mkdir -p "$SHIM_FAIL_DIR" "$SHIM_NODE_DIR" "$SHIM_GH_DIR" || exit 2
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
# A `gh` that answers EXACTLY the argv vectors the converted steps send (anything else exits 64, so a step that changes its call shape
# fails loudly instead of being answered by a permissive stub) and runs the step's REAL `--jq` program (jq) against a fixture, so the
# selector (`.filename, (.previous_filename // empty)`, the `::ENTRY::` marker) is under test, not a canned answer.
#   GH_STUB_MODE=compare : `gh api repos/$GH_STUB_REPO/commits/<sha> --jq P` prints $GH_STUB_PARENT; `gh api repos/$GH_STUB_REPO/compare/<a>...<b> --jq P`
#                          runs jq -r P on $GH_STUB_FIX (exit 1 when GH_STUB_FAIL=1)
#   GH_STUB_MODE=files   : `gh api --paginate repos/$GH_STUB_REPO/pulls/$GH_STUB_PR/files --jq P` runs jq -r P on $GH_STUB_FIX (exit 1 when GH_STUB_FAIL=1)
cat > "$SHIM_GH_DIR/gh" <<'SHIM'
#!/usr/bin/env bash
mode="${GH_STUB_MODE:-}"
bad() { echo "gh stub: unmodelled argv: $*" >&2; exit 64; }
case "$mode" in
  compare)
    [ "$#" -eq 4 ] && [ "$1" = api ] && [ "$3" = --jq ] || bad "$@"
    case "$2" in
      "repos/$GH_STUB_REPO/commits/"*) printf '%s\n' "${GH_STUB_PARENT-}"; exit 0 ;;
      "repos/$GH_STUB_REPO/compare/"*...*)
        [ "${GH_STUB_FAIL:-0}" = 1 ] && { echo "gh: HTTP 500" >&2; exit 1; }
        exec jq -r "$4" "$GH_STUB_FIX" ;;
    esac
    bad "$@" ;;
  files)
    if [ "$#" -eq 5 ] && [ "$1" = api ] && [ "$2" = --paginate ] && [ "$3" = "repos/$GH_STUB_REPO/pulls/$GH_STUB_PR/files" ] && [ "$4" = --jq ]; then
      [ "${GH_STUB_FAIL:-0}" = 1 ] && { echo "gh: HTTP 500" >&2; exit 1; }
      exec jq -r "$5" "$GH_STUB_FIX"
    fi
    bad "$@" ;;
  *) bad "$@" ;;
esac
SHIM
chmod +x "$SHIM_GH_DIR/gh"

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
H_LC_SEEN=""
run_helper_env() { # <dir> <NAME=value> <args...>   (cwd = dir; one env assignment for the helper only; H_LC_SEEN = the LC_ALL the helper's bash started under)
  local d="$1" e="$2" lcrec="$WORK_ROOT/io/h.lc"; shift 2
  assert_fixture_dir "$d"
  mkdir -p "$WORK_ROOT/io"
  : > "$lcrec"
  H_RC=0
  (cd "$d" && env "$e" BASH_ENV="$LC_RECORDER" LC_RECORD="$lcrec" bash "$HELPER" "$@") > "$WORK_ROOT/io/h.out" 2> "$WORK_ROOT/io/h.err" || H_RC=$?
  H_LC_SEEN="$(head -n 1 "$lcrec")"
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
h_expect_refused() { # <label>: the helper refused (rc 2) AND printed no list on stdout
  if [ "$H_RC" -eq 2 ] && [ -z "$H_OUT" ]; then h_ok "$1"; else h_bad "$1 (want rc=2 and an empty stdout; got rc=$H_RC out='$(printf '%s' "$H_OUT" | tr '\n' '|' | cut -c1-120)')"; fi
}
h_expect_lc() { # <label> <want>: the helper's bash really started under this LC_ALL
  if [ "$H_LC_SEEN" = "$2" ]; then h_ok "$1: the helper started under LC_ALL=$2"; else h_bad "$1: the helper started under LC_ALL='$H_LC_SEEN', want '$2'"; fi
}
h_expect_final_lf() { # <label> <file>: the file ends with a line feed (a `$(cat)` capture strips it, so this reads the file itself)
  if [ -s "$2" ] && [ "$(tail -c 1 "$2" | od -An -tx1 | tr -d ' \n')" = 0a ]; then h_ok "$1"; else h_bad "$1 (the last byte is not LF)"; fi
}
selftest_helper_verdicts() {
  mkdir -p "$WORK_ROOT/io"
  local o_out="$H_OUT" o_err="$H_ERR" o_rc="$H_RC" o_lc="$H_LC_SEEN"
  H_OUT=$'alpha\nbeta'; H_ERR=""; H_RC=0
  selftest_moved "h_expect_line accepts a listed line" pass h_expect_line "selftest" "beta"
  selftest_moved "h_expect_line rejects an absent line" fail h_expect_line "selftest" "gamma"
  selftest_moved "h_expect_line rejects a mere substring" fail h_expect_line "selftest" "alph"
  selftest_moved "h_expect_rc accepts the right rc" pass h_expect_rc "selftest" 0
  selftest_moved "h_expect_rc rejects a wrong rc" fail h_expect_rc "selftest" 2
  # A HIGHER wrong rc and a LOWER wrong rc: an `-eq` weakened to `-ge` or `-le` accepts one of them.
  H_RC=2
  selftest_moved "h_expect_rc rejects a higher rc than expected (2 where 1 wanted)" fail h_expect_rc "selftest" 1
  H_RC=1
  selftest_moved "h_expect_rc rejects a lower rc than expected (1 where 2 wanted)" fail h_expect_rc "selftest" 2
  H_RC=2; H_OUT=""
  selftest_moved "h_expect_refused accepts rc 2 with an empty stdout" pass h_expect_refused "selftest"
  H_RC=2; H_OUT="a-list-line"
  selftest_moved "h_expect_refused rejects rc 2 with a list on stdout" fail h_expect_refused "selftest"
  H_RC=0; H_OUT=""
  selftest_moved "h_expect_refused rejects rc 0 with an empty stdout" fail h_expect_refused "selftest"
  H_RC=1; H_OUT=""
  selftest_moved "h_expect_refused rejects rc 1 (a different failure)" fail h_expect_refused "selftest"
  printf 'a\nb\n' > "$WORK_ROOT/io/lf-yes.txt"; printf 'a\nb' > "$WORK_ROOT/io/lf-no.txt"
  selftest_moved "h_expect_final_lf accepts a file ending in LF" pass h_expect_final_lf "selftest" "$WORK_ROOT/io/lf-yes.txt"
  selftest_moved "h_expect_final_lf rejects a file whose last byte is not LF" fail h_expect_final_lf "selftest" "$WORK_ROOT/io/lf-no.txt"
  H_LC_SEEN="C"
  selftest_moved "h_expect_lc accepts the locale the helper started under" pass h_expect_lc "selftest" C
  selftest_moved "h_expect_lc rejects another locale" fail h_expect_lc "selftest" C.UTF-8
  H_OUT="$o_out"; H_ERR="$o_err"; H_RC="$o_rc"; H_LC_SEEN="$o_lc"
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
  local naive_lc
  naive_lc="$(printf '%s\n' "$P/"$'\351'".tf" | LC_ALL="$HELPER_LC" grep -E -e '^apps/' 2>/dev/null || true)"
  if [ "$naive_lc" != "$P/"$'\351'".tf" ]; then h_ok "precondition latin-1: a plain grep under LC_ALL=$HELPER_LC does NOT print the invalid-UTF-8 name (the rows below are not vacuous)"
  else h_bad "precondition latin-1: a plain grep under LC_ALL=$HELPER_LC printed the invalid-UTF-8 name, so the UTF-8 rows prove nothing"; fi
  run_helper_env "$d" LC_ALL="$HELPER_LC" --match '^apps/web-platform/infra/' origin/main...HEAD
  h_expect_lc "--match locale row" "$HELPER_LC"
  h_expect_rc "--match under LC_ALL=C.UTF-8 with an invalid-UTF-8 name exits 0" 0
  h_expect_line "--match under LC_ALL=C.UTF-8 prints the invalid-UTF-8 name raw" "$P/"$'\351'".tf"
  run_helper_env "$d" LC_ALL="$HELPER_LC" origin/main...HEAD
  h_expect_lc "plain locale row" "$HELPER_LC"
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
  # Row set 11: the option ALLOWLIST. Only `--cached`, `--staged`, `--merge-base`, `--diff-filter=*` and everything after `--` pass; every
  # other option is refused with rc 2 and an empty stdout, because a flag appended after the baked-in ones wins in git (`-M`, `-C`,
  # `--find-renames`, `--ignore-submodules=all`, `--no-renames`) or corrupts the list (`-ps`, `-sz`).
  new_row || { h_bad "could not build allowlist row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/allow-new.tf"; put_in "$d" "$P/keep.tf" "edited"
  commit_row || { h_bad "could not commit allowlist row"; return; }
  local fl
  for fl in -ps -sz -M -C --find-renames --ignore-submodules=all --no-renames --diff-filter; do
    run_helper "$d" "$fl" origin/main...HEAD
    h_expect_refused "allowlist: option $fl before the range is refused"
  done
  for fl in -ps -M --ignore-submodules=all --no-renames; do
    run_helper "$d" origin/main...HEAD "$fl"
    h_expect_refused "allowlist: option $fl after the range is refused"
  done
  run_helper "$d" origin/main...HEAD -- -s
  h_expect_rc "allowlist: everything after -- is a pathspec, never an option (a pathspec named -s)" 0
  run_helper "$d" --diff-filter=A origin/main...HEAD
  h_expect_rc "allowlist: --diff-filter=A is accepted" 0
  h_expect_line "allowlist: --diff-filter=A lists the added file" "$P/allow-new.tf"
  if h_has_line "$P/keep.tf"; then h_bad "allowlist: --diff-filter=A listed the modified file"; else h_ok "allowlist: --diff-filter=A leaves the modified file out"; fi
  run_helper "$d" --merge-base origin/main HEAD
  h_expect_rc "allowlist: --merge-base is accepted" 0
  h_expect_line "allowlist: --merge-base lists the changed file" "$P/allow-new.tf"
  free_row
  new_row || { h_bad "could not build staged row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/staged-new.tf"
  fg "$d" add -A
  run_helper "$d" --cached
  h_expect_rc "allowlist: --cached is accepted" 0
  h_expect_line "allowlist: --cached lists the staged file" "$P/staged-new.tf"
  run_helper "$d" --staged
  h_expect_rc "allowlist: --staged is accepted" 0
  h_expect_line "allowlist: --staged lists the staged file" "$P/staged-new.tf"
  free_row

  # Row set 12: output integrity. A closed or full stdout is rc 2 (a truncated list at rc 0 reads as a shorter diff), a successful plain
  # list ends in a line feed, and no mode leaves its temp file behind.
  new_row || { h_bad "could not build output row"; return; }
  d="$ROW_DIR"
  put_in "$d" "$P/out.tf"
  commit_row || { h_bad "could not commit output row"; return; }
  if [ -w /dev/full ]; then
    H_RC=0
    (cd "$d" && bash "$HELPER" origin/main...HEAD) > /dev/full 2> "$WORK_ROOT/io/h.err" || H_RC=$?
    h_expect_rc "plain mode with stdout on a full device exits 2" 2
  else
    h_bad "plain mode to a full device: /dev/full is not writable on this host, the row cannot run"
  fi
  run_helper "$d" origin/main...HEAD
  h_expect_final_lf "plain mode output ends with a line feed (read from the file, a capture strips it)" "$WORK_ROOT/io/h.out"
  run_helper "$d" --match '^apps/' origin/main...HEAD
  h_expect_final_lf "--match output ends with a line feed" "$WORK_ROOT/io/h.out"
  local priv="$WORK_ROOT/priv-tmp" probe_t
  mkdir -p "$priv"
  probe_t="$(TMPDIR="$priv" mktemp)"
  if [ -n "$probe_t" ] && [ -e "$probe_t" ] && [ "$(dirname "$probe_t")" = "$priv" ]; then h_ok "precondition tmp: mktemp honours TMPDIR=$priv (so an empty dir afterwards means something)"; else h_bad "precondition tmp: mktemp ignored TMPDIR"; fi
  rm -f -- "$probe_t"
  run_helper_env "$d" TMPDIR="$priv" origin/main...HEAD
  if [ -z "$(ls -A "$priv")" ]; then h_ok "plain mode leaves no temp file in TMPDIR"; else h_bad "plain mode left $(ls -A "$priv" | head -3 | tr '\n' ' ') in TMPDIR"; rm -rf -- "$priv"; mkdir -p "$priv"; fi
  run_helper_env "$d" TMPDIR="$priv" --match '^apps/' origin/main...HEAD
  if [ -z "$(ls -A "$priv")" ]; then h_ok "--match (a match) leaves no temp file in TMPDIR"; else h_bad "--match left a temp file in TMPDIR"; rm -rf -- "$priv"; mkdir -p "$priv"; fi
  run_helper_env "$d" TMPDIR="$priv" --match '^zzz-no-such-prefix/' origin/main...HEAD
  if [ -z "$(ls -A "$priv")" ]; then h_ok "--match (no match, rc 1) leaves no temp file in TMPDIR"; else h_bad "--match with no match left a temp file in TMPDIR"; rm -rf -- "$priv"; mkdir -p "$priv"; fi
  run_helper_env "$d" TMPDIR="$priv" origin/no-such-ref...HEAD
  if [ -z "$(ls -A "$priv")" ]; then h_ok "a git failure (rc 2) leaves no temp file in TMPDIR"; else h_bad "a git failure left a temp file in TMPDIR"; rm -rf -- "$priv"; mkdir -p "$priv"; fi
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
ss-lint	secret-scan.yml	secret-guards	lint-fixture-content
live-verify-gate	web-platform-release.yml	live-verify	gate
swm	pr-quality-guards.yml	quality-advisory	stray-worktree-marker-block
detect-wt	pr-quality-guards.yml	detect	f'
STEP_FLOOR=15
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
    AFTER_SHA) DEV="$ROW_HEAD" ;;
    REPO|GH_REPO) DEV="o/r" ;;
    PR_NUMBER) DEV=7 ;;
    *) return 1 ;;
  esac
  return 0
}

S_RC=0; S_LOG=""; S_OUT=""; S_LC_SEEN=""
RS_EXTRA=()   # extra NAME=value pairs for ONE run_step call (a scenario's gh-stub mode, a base SHA override); the caller resets it
# STEP_LC (default C, the weakest locale the harness pins) is the LC_ALL the step starts under: `STEP_LC=C.UTF-8 run_step ...`.
run_step() { # <step key> <arm> [fail verbs]   (cwd = $ROW_DIR; sets S_RC, S_LOG, S_OUT)
  local key="$1" arm="$2" verbs="${3:-}" k envargs=() path="$SHIM_GH_DIR:$SHIM_NODE_DIR:$PATH"
  local outf="$WORK_ROOT/io/gh-output-$ROW_SEQ" logf="$WORK_ROOT/io/log-$ROW_SEQ" tmpd="$WORK_ROOT/io/tmp-$ROW_SEQ"
  [ -s "$STEP_DIR/$key.sh" ] || { fail "$key: no extracted body"; S_RC=99; return; }
  local lcrec="$WORK_ROOT/io/lc-$ROW_SEQ"
  mkdir -p "$tmpd"; : > "$outf"; : > "$lcrec"
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if default_env_val "$arm" "$k"; then envargs+=("$k=$DEV"); else fail "$key: step declares env key $k not in DEFAULT_ENV: add $k to DEFAULT_ENV"; fi
  done < "$STEP_DIR/$key.env"
  [ -n "$verbs" ] && { path="$SHIM_FAIL_DIR:$path"; envargs+=("SHIM_FAIL_VERBS=$verbs" "REAL_GIT=$REAL_GIT"); }
  envargs+=(${RS_EXTRA[@]+"${RS_EXTRA[@]}"})
  assert_fixture_dir "$ROW_DIR"
  S_RC=0
  (cd "$ROW_DIR" && env -i PATH="$path" HOME="$WORK_ROOT/io" LC_ALL="${STEP_LC:-C}" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
      GITHUB_OUTPUT="$outf" RUNNER_TEMP="$tmpd" BASH_ENV="$LC_RECORDER" LC_RECORD="$lcrec" NODE_ARGV_FILE="$WORK_ROOT/io/argv-$ROW_SEQ" "${envargs[@]}" \
      bash --noprofile --norc -e "$STEP_DIR/$key.sh") > "$logf" 2>&1 || S_RC=$?
  S_LOG="$(cat "$logf")"
  S_OUT="$(cat "$outf")"
  S_LC_SEEN="$(head -n 1 "$lcrec")"
  STEP_ROWS=$((STEP_ROWS + 1))
  if [ "$S_LC_SEEN" != "${STEP_LC:-C}" ]; then fail "$key: the step started under LC_ALL='$S_LC_SEEN', the row asked for '${STEP_LC:-C}' (STEP_LC was not honoured)"; fi
}
expect_step_lc() { # <label> <want>: the step's bash really started under this LC_ALL
  if [ "$S_LC_SEEN" = "$2" ]; then s_ok "$1: the step started under LC_ALL=$2"; else fail "$1: the step started under LC_ALL='$S_LC_SEEN', want '$2'"; fi
}
nul_set_eq() { # <file> <names...>: the NUL-delimited records of <file> are EXACTLY these names (any order)
  local f="$1" g w found; shift
  local -a got=() want=("$@")
  [ -f "$f" ] || return 1
  mapfile -d '' -t got < "$f"
  [ "${#got[@]}" -eq "${#want[@]}" ] || return 1
  for w in "${want[@]}"; do
    found=0
    for g in "${got[@]}"; do if [ "$g" = "$w" ]; then found=1; break; fi; done
    [ "$found" -eq 1 ] || return 1
  done
  return 0
}
expect_nul_set() { # <label> <file> <names...>
  local lbl="$1" f="$2"; shift 2
  local -a got=()
  if nul_set_eq "$f" "$@"; then s_ok "$lbl"
  else
    [ -f "$f" ] && mapfile -d '' -t got < "$f"
    fail "$lbl: records differ: got ${#got[@]} [$(printf '%s|' "${got[@]}" | tr '\n\r' '~^' | cut -c1-200)] want ${#} [$(printf '%s|' "$@" | tr '\n\r' '~^' | cut -c1-200)]"
  fi
}
expect_no_wfcmd() { # <label>: no line of the step log, after trimming leading blanks (CR counts as a line break), starts with `::`
  local bad
  bad="$(tr '\r' '\n' <<<"$S_LOG" | grep -c -E '^[[:space:]]*::' || true)"
  if [ "$bad" -eq 0 ]; then s_ok "$1: no log line starts with a workflow command"; else fail "$1: $bad log line(s) start with '::' (a workflow-command injection): $(tr '\r\n' '^~' <<<"$S_LOG" | cut -c1-240)"; fi
}
flag_of() { printf '%s\n' "$S_OUT" | sed -n "s/^$1=//p" | tail -1; }
has_flag() { grep -q "^$1=" <<<"$S_OUT"; }
s_ok() { pass "$1"; }
expect_flag() { # <label> <flag> <want>
  local got; got="$(flag_of "$2")"
  if [ "$S_RC" -eq 0 ] && [ "$got" = "$3" ]; then s_ok "$1: $2=$3"
  else fail "$1: want $2=$3 got '$got' rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-220))"; fi
}
expect_step_rc() { # <label> <want rc> [log substring]: the step exited with exactly this status and (when given) its log says the substring
  if [ "$S_RC" -eq "$2" ] && { [ -z "${3-}" ] || grep -qF -- "$3" <<<"$S_LOG"; }; then s_ok "$1: rc=$2${3:+ and the log says '$3'}"
  else fail "$1: want rc=$2${3:+ and a log saying '$3'} got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; fi
}
expect_closed() { # <label> <flag>: the step fails (non-zero) and emitted NO value for the flag
  if [ "$S_RC" -ne 0 ] && ! has_flag "$2"; then s_ok "$1: fails closed (rc=$S_RC, no $2 emitted)"
  else fail "$1: want a non-zero exit and no $2 (rc=$S_RC out='$(printf '%s' "$S_OUT" | tr '\n' ' ')' log='$(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-160)')"; fi
}

selftest_step_verdicts() {
  local o_out="$S_OUT" o_log="$S_LOG" o_rc="$S_RC" o_lc="$S_LC_SEEN"
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
  # Exact, never a substring: a longer value that CONTAINS the wanted one must be rejected (a `[[ $got == *$want* ]]` mutant accepts it).
  S_LOG="::error::the cause"; S_RC=1
  selftest_moved "expect_step_rc accepts the right rc and a log substring" pass expect_step_rc "selftest" 1 "the cause"
  selftest_moved "expect_step_rc rejects a wrong rc" fail expect_step_rc "selftest" 0 "the cause"
  selftest_moved "expect_step_rc rejects a log without the substring" fail expect_step_rc "selftest" 1 "another cause"
  S_LOG=""
  S_OUT=$'flag=onward'; S_RC=0
  selftest_moved "expect_flag rejects a longer value containing the wanted one" fail expect_flag "selftest" flag on
  S_OUT=$'flag=on'; S_LC_SEEN=C
  selftest_moved "expect_step_lc accepts the locale the step started under" pass expect_step_lc "selftest" C
  selftest_moved "expect_step_lc rejects a step that started under another locale" fail expect_step_lc "selftest" C.UTF-8
  printf 'a\0b\nc\0d\0' > "$WORK_ROOT/io/nul-set.bin"
  selftest_moved "expect_nul_set accepts exactly the recorded names" pass expect_nul_set "selftest" "$WORK_ROOT/io/nul-set.bin" d $'b\nc' a
  selftest_moved "expect_nul_set rejects a missing name" fail expect_nul_set "selftest" "$WORK_ROOT/io/nul-set.bin" a $'b\nc'
  selftest_moved "expect_nul_set rejects an extra name" fail expect_nul_set "selftest" "$WORK_ROOT/io/nul-set.bin" a $'b\nc' d e
  selftest_moved "expect_nul_set rejects names that are only line-split fragments of a record" fail expect_nul_set "selftest" "$WORK_ROOT/io/nul-set.bin" a b c
  S_LOG=$'ok line\n  ::error::spoofed'
  selftest_moved "expect_no_wfcmd rejects an indented workflow command" fail expect_no_wfcmd "selftest"
  S_LOG=$'ok line\r::warning::spoofed'
  selftest_moved "expect_no_wfcmd rejects a workflow command after a CR" fail expect_no_wfcmd "selftest"
  S_LOG=$'ok line\n  zz?::error::neutralised'
  selftest_moved "expect_no_wfcmd accepts a neutralised log" pass expect_no_wfcmd "selftest"
  S_OUT="$o_out"; S_LOG="$o_log"; S_RC="$o_rc"; S_LC_SEEN="$o_lc"
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

# Unanchored, shape-preserving steps: a rename-away row, a control row, and the git-failure row (a failed diff reads as "run": hit=1).
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
  run_step "$key" pr diff; expect_flag "$lbl (a git failure reads as run: hit=1, never hit=0)" hit 1; free_row
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
    run_step infra-dirs "$arm"; expect_step_lc "$lbl (control)" C
    expect_flag "$lbl (control, LC_ALL=C)" directories '["apps/web-platform/infra"]'
    STEP_LC=C.UTF-8 run_step infra-dirs "$arm"; expect_step_lc "$lbl" C.UTF-8
    expect_flag "$lbl (step started under LC_ALL=C.UTF-8)" directories '["apps/web-platform/infra"]'
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
  local d lbl doc ok
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
  # (#12332) The required-doc match is a FIXED-string exact record match (`grep -zFxc`): near-miss names that a REGEX reading of
  # `docs/legal/privacy-policy.md` would accept (the `.` matches any byte) must NOT satisfy a required document.
  local ch tw
  lbl="legal-lockstep/pr/near-miss-X-twins"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"
  for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
    put_in "$d" "${doc%.md}Xmd" "edited"
  done
  commit_row || { fail "$lbl: commit"; return; }
  run_step legal-lockstep pr
  ok=1
  for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
    grep -qF "::error::  - $doc" <<<"$S_LOG" || ok=0
  done
  if [ "$S_RC" -eq 1 ] && [ "$ok" -eq 1 ]; then s_ok "$lbl: four near-miss twins named *Xmd (the . read as any byte) satisfy none of the required documents"
  else fail "$lbl: want rc=1 with all four documents reported missing, got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-240))"; fi
  free_row
  lbl="legal-lockstep/pr/near-miss-metachar-twins"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" apps/web-platform/server/dsar-export.ts "edited"
  ok=1
  for tw in 'docs/legal/privacy-policy.md|*' 'docs/legal/gdpr-policy.md|?' 'docs/legal/data-protection-disclosure.md|[' 'knowledge-base/legal/compliance-posture.md|\'; do
    doc="${tw%%|*}"; ch="${tw#*|}"
    put_in "$d" "${doc%.md}${ch}md" "edited"
  done
  commit_row || { fail "$lbl: commit"; return; }
  run_step legal-lockstep pr
  for doc in docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-protection-disclosure.md knowledge-base/legal/compliance-posture.md; do
    grep -qF "::error::  - $doc" <<<"$S_LOG" || ok=0
  done
  if [ "$S_RC" -eq 1 ] && [ "$ok" -eq 1 ]; then s_ok "$lbl: regex-metacharacter twins (* ? [ \\ in the dot position) satisfy none of the required documents"
  else fail "$lbl: want rc=1 with all four documents reported missing, got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-240))"; fi
  free_row
  # (#12332) The "Changed files in PR" log is attacker-chosen text: a LF or CR in a name could start a workflow command on its own line.
  lbl="legal-lockstep/pr/log-neutralises-control-bytes"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" "zz${NL}::error::spoofed" "edited"; put_in "$d" "cr${CR}::warning::spoofed2" "edited"; put_in "$d" docs/other.md "edited"
  commit_row || { fail "$lbl: commit"; return; }
  run_step legal-lockstep pr
  if [ "$S_RC" -eq 0 ] && grep -qF 'trivially passes' <<<"$S_LOG"; then s_ok "$lbl: the control-byte names do not change the verdict (no DSAR surface: trivially passes)"; else fail "$lbl: want rc=0 + 'trivially passes' got rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; fi
  expect_no_wfcmd "$lbl"
  if grep -qF 'zz?::error::spoofed' <<<"$S_LOG" && grep -qF 'cr?::warning::spoofed2' <<<"$S_LOG"; then s_ok "$lbl: both names are still listed, with the control byte shown as ?"; else fail "$lbl: the neutralised names are missing from the log ($(printf '%s' "$S_LOG" | tr '\n\r' '|~' | cut -c1-240))"; fi
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
  secret_scan_ctrl_rows
}

# (#12332) Names the `[[:cntrl:]]*$` end anchors and the `LC_ALL=C` on `grep --null-data` exist for, in BOTH selection steps, run under a
# UTF-8 locale (the harness default is C, which would hide the missing `LC_ALL=C`): a `.snap` name ending in CR, a learnings `.md` name
# ending in LF, and a fixture named by an invalid UTF-8 byte (UTF-8 grep would answer "Binary file matches" instead of printing it).
# The selected list (lint-files.txt) AND the linter argv must hold exactly these names, byte for byte; the control stays out.
secret_scan_ctrl_rows() {
  local d lbl arm key keep pdir='apps/web-platform/test/fixtures'
  local n_snap="x.snap${CR}" n_md="knowledge-base/project/learnings/a.md${NL}" n_ff="$pdir/"$'\377'".json" n_ctl="docs/${NAME_E}.json"
  local lf argvf
  for arm in pr push; do
    if [ "$arm" = pr ]; then key=ss-files-pr; else key=ss-files-nonpr; fi
    lbl="secret-scan/$arm/ctrl-and-invalid-utf8-names"
    new_row || { fail "$lbl: setup"; continue; }
    d="$ROW_DIR"
    put_in "$d" "$n_snap"; put_in "$d" "$n_md"; put_in "$d" "$n_ff"; put_in "$d" "$n_ctl"
    commit_row || { fail "$lbl: commit"; free_row; continue; }
    lf="$WORK_ROOT/io/tmp-$ROW_SEQ/lint-files.txt"; argvf="$WORK_ROOT/io/argv-$ROW_SEQ"
    # Preconditions: the names are really in the repository and git prints them NUL-delimited (so the fixtures are what the row claims).
    if [ "$(fg "$d" ls-files -z -- "$n_snap" "$n_md" "$n_ff" | tr -cd '\0' | wc -c)" -eq 3 ]; then pass "$lbl: precondition: the CR, LF and 0xFF names are tracked"; else fail "$lbl: precondition: the control-byte fixtures were not created"; fi
    STEP_LC=C.UTF-8 run_step "$key" "$arm"
    expect_step_lc "$lbl (selection)" C.UTF-8
    if [ "$S_RC" -ne 0 ]; then fail "$lbl: the selection step failed rc=$S_RC ($(printf '%s' "$S_LOG" | tr '\n' ' ' | cut -c1-200))"; else
      if [ "$arm" = pr ]; then
        expect_nul_set "$lbl: lint-files.txt holds exactly the .snap<CR>, learnings .md<LF> and 0xFF names (control excluded)" "$lf" "$n_snap" "$n_md" "$n_ff"
      else
        expect_nul_set "$lbl: lint-files.txt holds exactly the tracked fixture, .snap<CR>, learnings .md<LF> and 0xFF names (control excluded)" "$lf" "$pdir/keep.json" "$n_snap" "$n_md" "$n_ff"
      fi
      STEP_LC=C.UTF-8 run_step ss-lint "$arm"
      expect_step_lc "$lbl (linter step)" C.UTF-8
      if [ "$arm" = pr ]; then
        expect_nul_set "$lbl: the linter argv holds the same names byte for byte" "$argvf" "$n_snap" "$n_md" "$n_ff"
      else
        expect_nul_set "$lbl: the linter argv holds the same names byte for byte" "$argvf" "$pdir/keep.json" "$n_snap" "$n_md" "$n_ff"
      fi
    fi
    free_row
  done
}

# ── (#12246 remainder) steps that read a changed-path list from the compare / files API or a local diff and had no executing suite ─────
# web-platform-release.yml `live-verify` / `gate`: the compare API with a rename's previous_filename, the 300-entry cap, the empty pattern set.
gate_case() { # <name> <want triggered> <want gate_failed> <fixture json> [extra RS_EXTRA pairs...]
  local name="$1" wt="$2" wf="$3" fix="$4" lbl fixf lv="apps/web-platform/scripts/live-verify"
  shift 4
  lbl="live-verify-gate/$name"
  new_row || { fail "$lbl: setup"; return; }
  mkdir -p "$ROW_DIR/$lv" && cp "$REPO_ROOT/$lv/trigger-paths.txt" "$ROW_DIR/$lv/trigger-paths.txt" || { fail "$lbl: setup (trigger-paths.txt)"; free_row; return; }
  fixf="$WORK_ROOT/io/gate-fix-$ROW_SEQ.json"; printf '%s' "$fix" > "$fixf"
  RS_EXTRA=(GH_STUB_MODE=compare GH_STUB_REPO=o/r "GH_STUB_PARENT=parent0000000000000000000000000000000000" "GH_STUB_FIX=$fixf" "$@")
  run_step live-verify-gate pr
  RS_EXTRA=()
  expect_flag "$lbl" triggered "$wt"
  expect_flag "$lbl" gate_failed "$wf"
  free_row
}
live_verify_gate_rows() {
  local cap cap299 lbl lv="apps/web-platform/scripts/live-verify"
  fj() { jq -nc --argjson f "$1" '{files:$f}'; }
  gate_case plain-hit 1 0 "$(fj '[{"filename":"apps/web-platform/hooks/x.ts"}]')"
  gate_case plain-skip 0 0 "$(fj '[{"filename":"docs/readme.md"}]')"
  gate_case rename-away-from-a-gated-path 1 0 "$(fj '[{"filename":"docs/moved.ts","previous_filename":"apps/web-platform/hooks/x.ts","status":"renamed"}]')"
  gate_case rename-between-ungated-paths 0 0 "$(fj '[{"filename":"docs/b.md","previous_filename":"docs/a.md","status":"renamed"}]')"
  gate_case empty-file-list 0 0 "$(fj '[]')"
  cap="$(jq -nc '{files:[range(0;300)|{filename:("docs/f\(.).md")}]}')"
  gate_case at-the-300-entry-cap-reads-as-triggered 1 0 "$cap"
  cap299="$(jq -nc '{files:[range(0;299)|{filename:("docs/f\(.).md")}]}')"
  gate_case one-under-the-cap-is-judged-by-its-names 0 0 "$cap299"
  gate_case compare-api-failure-is-CANT-RUN 0 1 "$(fj '[]')" GH_STUB_FAIL=1
  gate_case files-null-is-CANT-RUN 0 1 '{"files":null}'
  gate_case files-absent-is-CANT-RUN 0 1 '{}'
  # An empty pattern set (comments only / missing file) fails the step: it would match nothing and SKIP every release.
  lbl="live-verify-gate/empty-pattern-set"
  new_row || { fail "$lbl: setup"; return; }
  mkdir -p "$ROW_DIR/$lv" && printf '# only a comment\n\n' > "$ROW_DIR/$lv/trigger-paths.txt" && printf '%s' "$(fj '[{"filename":"apps/web-platform/hooks/x.ts"}]')" > "$WORK_ROOT/io/gate-fix-$ROW_SEQ.json"
  RS_EXTRA=(GH_STUB_MODE=compare GH_STUB_REPO=o/r "GH_STUB_PARENT=parent0000000000000000000000000000000000" "GH_STUB_FIX=$WORK_ROOT/io/gate-fix-$ROW_SEQ.json")
  run_step live-verify-gate pr; RS_EXTRA=()
  expect_step_rc "$lbl (fails the step)" 1 "yielded no patterns"
  if has_flag triggered; then fail "$lbl: emitted triggered= despite the empty pattern set"; else s_ok "$lbl: no triggered= value emitted"; fi
  free_row
  lbl="live-verify-gate/missing-pattern-file"
  new_row || { fail "$lbl: setup"; return; }
  printf '%s' "$(fj '[{"filename":"apps/web-platform/hooks/x.ts"}]')" > "$WORK_ROOT/io/gate-fix-$ROW_SEQ.json"
  RS_EXTRA=(GH_STUB_MODE=compare GH_STUB_REPO=o/r "GH_STUB_PARENT=parent0000000000000000000000000000000000" "GH_STUB_FIX=$WORK_ROOT/io/gate-fix-$ROW_SEQ.json")
  run_step live-verify-gate pr; RS_EXTRA=()
  expect_step_rc "$lbl (fails the step, never SKIP)" 1
  free_row
  lbl="live-verify-gate/no-parent-commit"
  new_row || { fail "$lbl: setup"; return; }
  mkdir -p "$ROW_DIR/$lv" && cp "$REPO_ROOT/$lv/trigger-paths.txt" "$ROW_DIR/$lv/" && printf '%s' "$(fj '[]')" > "$WORK_ROOT/io/gate-fix-$ROW_SEQ.json"
  RS_EXTRA=(GH_STUB_MODE=compare GH_STUB_REPO=o/r "GH_STUB_PARENT=" "GH_STUB_FIX=$WORK_ROOT/io/gate-fix-$ROW_SEQ.json")
  run_step live-verify-gate pr; RS_EXTRA=()
  expect_step_rc "$lbl (an unresolvable parent fails the step)" 1 "could not resolve the parent"
  free_row
}

# pr-quality-guards.yml `quality-advisory` / `stray-worktree-marker-block`: a LOCAL diff in a real scratch repository (no gh).
swm_row() { # <label> <want rc> <log substring or ""> : the repo state is already committed in $ROW_DIR; BASE_SHA = $ROW_BASE
  run_step swm pr
  expect_step_rc "$1" "$2" "${3-}"
}
stray_marker_rows() {
  local lbl d plain
  lbl="swm/marker-with-a-non-ASCII-name"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" ".claude/worktrees/$NAME_E"; commit_row || { fail "$lbl: commit"; free_row; return; }
  if ! plain="$(fg "$ROW_DIR" diff --name-only "$ROW_BASE"..."$ROW_HEAD")"; then fail "$lbl: precondition: the plain diff failed"
  elif grep -Fxq -e ".claude/worktrees/$NAME_E" <<<"$plain"; then fail "$lbl: precondition: git did NOT C-quote the name; the row would pass vacuously"
  else swm_row "$lbl (the old plain diff dodged it by C-quoting)" 1 "Diff contains .claude/worktrees/"; fi
  free_row
  lbl="swm/marker-with-an-ASCII-name"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" .claude/worktrees/a; commit_row || { fail "$lbl: commit"; free_row; return; }
  swm_row "$lbl" 1 "Offending paths"; free_row
  lbl="swm/clean-diff-control"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" docs/other.md "edited"; commit_row || { fail "$lbl: commit"; free_row; return; }
  swm_row "$lbl (must-PASS)" 0 ""; free_row
  lbl="swm/unresolvable-base"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" docs/other.md "edited"; commit_row || { fail "$lbl: commit"; free_row; return; }
  RS_EXTRA=("BASE_SHA=dddddddddddddddddddddddddddddddddddddddd"); swm_row "$lbl (a failed diff fails the step, never an empty list)" 1 "git diff against the PR base failed"; RS_EXTRA=()
  free_row
  lbl="swm/newline-name-forging-a-marker-line"
  new_row || { fail "$lbl: setup"; return; }
  put_in "$ROW_DIR" "zz${NL}.claude/worktrees/q"; commit_row || { fail "$lbl: commit"; free_row; return; }
  swm_row "$lbl (a fragment line only adds a false positive on a BLOCK)" 1 "Offending paths"; free_row
  # The marker already exists at the base and is renamed AWAY: --no-renames lists its OLD path (default detection lists only the new one).
  lbl="swm/marker-renamed-away"
  new_row || { fail "$lbl: setup"; return; }
  d="$ROW_DIR"
  put_in "$d" .claude/worktrees/a; fg "$d" add -A && fg "$d" commit -q -m marker-at-base || { fail "$lbl: base commit"; free_row; return; }
  ROW_BASE="$(fg "$d" rev-parse HEAD)"
  fg "$d" mv .claude/worktrees/a docs-moved-a && commit_row || { fail "$lbl: commit"; free_row; return; }
  if ! plain="$(fg "$d" diff --name-only "$ROW_BASE"..."$ROW_HEAD")"; then fail "$lbl: precondition: the plain diff failed"
  elif grep -Fxq -e .claude/worktrees/a <<<"$plain"; then fail "$lbl: precondition: the plain diff lists the old path, so the row proves nothing"
  else swm_row "$lbl (the rename's OLD path is seen)" 1 ".claude/worktrees/a"; fi
  free_row
}

# pr-quality-guards.yml `detect` / `f`: the files API listing -> per-surface flags. The 3000-file cap must read as "run" (worktrees=true).
detect_case() { # <label> <fixture json> <stub fail 0|1> <want worktrees> [<want webplat>]
  local lbl="detect-wt/$1" fixf
  new_row || { fail "$lbl: setup"; return; }
  fixf="$WORK_ROOT/io/detect-fix-$ROW_SEQ.json"; printf '%s' "$2" > "$fixf"
  RS_EXTRA=(GH_STUB_MODE=files GH_STUB_REPO=o/r GH_STUB_PR=7 "GH_STUB_FIX=$fixf" "GH_STUB_FAIL=$3")
  run_step detect-wt pr; RS_EXTRA=()
  expect_flag "$lbl" worktrees "$4"
  if [ -n "${5-}" ]; then expect_flag "$lbl" webplat "$5"; fi
  free_row
}
detect_rows() {
  local n2999 n3000
  n2999="$(jq -nc '[range(0;2999)|{filename:("pad/f\(.).txt")}]')"
  n3000="$(jq -nc '[range(0;3000)|{filename:("pad/f\(.).txt")}]')"
  detect_case "2999-entries-no-marker-is-judged-by-its-names" "$n2999" 0 false false
  detect_case "3000-entries-reads-as-run-(cap)" "$n3000" 0 true true
  detect_case "api-failure-reads-as-run" '[]' 1 true true
  detect_case "marker-with-a-non-ASCII-name" "[{\"filename\":\".claude/worktrees/$NAME_E\"}]" 0 true false
  detect_case "marker-only-as-a-previous_filename" '[{"filename":"docs/x.md","previous_filename":".claude/worktrees/a","status":"renamed"}]' 0 true false
  detect_case "control-no-marker" '[{"filename":"docs/x.md"}]' 0 false false
}

section_steps() {
  echo "── steps"
  selftest_step_verdicts
  extract_steps
  # The DEFAULT_ENV subset check, once per step, against the arm it runs under: an undeclared key fails inside run_step.
  new_row || { fail "steps: could not build a row"; return; }
  commit_row
  local k
  for k in infra-dirs ci-filter ci-canary ci-propagation sentry-filter tenant-filter vendor-filter legal-lockstep cgate-changed ss-files-pr ss-files-nonpr ss-lint live-verify-gate swm detect-wt; do
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
  live_verify_gate_rows
  stray_marker_rows
  detect_rows
  if [ "$STEP_ROWS" -gt 0 ]; then pass "rows executed: $STEP_ROWS step executions"; else fail "zero step rows executed"; fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# SECTION sentinel
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# The exemption tables. Every table is a closed list of readers this PR knowingly leaves on a plain form, one row per SITE (two identical sites
# need two rows), never a line number; rows are keyed on the REPO-RELATIVE path (a same-named file elsewhere cannot consume a row), carry a
# reason, and a row that matches no site is STALE and fails. The converted-reader PREDICATE (CTO D1) is `--ignore-submodules=none` AND (`-z` OR
# `--no-renames`) AND no swallowed failure (`|| true`, `|| :`, `|| echo ""` after the reader); a site that meets it needs no row.
#   EXEMPT_TABLE       .github/workflows/*.yml
#   EXEMPT_CODE_TABLE  tracked non-test *.sh *.py *.ts *.mjs under the code roots (and `gh api .../files|.../compare` readers that do not emit
#                      previous_filename)
#   EXEMPT_PROSE       the closed SKILL.md / reference / agent list in PROSE_FILES (lesson and example text elsewhere is out of the census)
EXEMPT_TABLE='.github/workflows/pr-quality-guards.yml	"${diff_base}"...HEAD	enforce-legal-lockstep: a required legal document is matched as an exact DESTINATION record (grep -zFxc over the NUL list); --no-renames would list a renamed-away document by its OLD path and satisfy the lockstep, which the legal-doc-renamed-away row forbids; no gitlink can be a legal document or a DSAR surface path (executed by the steps section, pinned by PINNED_Z)
.github/workflows/pr-quality-guards.yml	--diff-filter=AMRT "$BASE_SHA"	the step refuses a C-quoted path under a scanned skill/agent directory itself (its own ^" check, fail closed)
.github/workflows/secret-scan.yml	git diff -z --name-only "${BASE_SHA}..${HEAD_SHA}"	lint-fixture-files-pr: only decides whether secret-scan.yml ITSELF is in the diff (exact-line grep on its own path); a failed read is caught by the second diff on the same range three lines later, which writes to a file under -e (executed by the steps section: secret-scan/pr/gitfail)
.github/workflows/secret-scan.yml	git diff -z --diff-filter=ACMR --name-only "${BASE_SHA}..${HEAD_SHA}"	lint-fixture-files-pr: a destination-only SELECT of the fixtures the linter must read (the filter names R so a rename selects its NEW path, the file that exists to be linted; --no-renames would add the vanished old path); no || true, a failed diff fails the step (executed by the steps section)
.github/workflows/skill-security-scan-postmerge.yml	--diff-filter=AMRT "$parent"	the step refuses a C-quoted path under a scanned skill/agent directory itself (its own ^" check, fail closed)
.github/workflows/reusable-release.yml	git diff --name-only HEAD~1 -- $PATH_FILTER	emptiness test only (is any path under the filter changed); pathspec-filtered
.github/workflows/web-platform-release.yml	--name-only "${WR_HEAD_SHA}~1" "$WR_HEAD_SHA" -- $RELEASE_PATH_FILTER	emptiness test only; pathspec-filtered
.github/workflows/tenant-integration.yml	git log --format= --name-only	emptiness test only (a migration was touched anywhere in the PR history)'

# The code census (second census, #12246 remainder): every site in a tracked non-test *.sh *.py *.ts *.mjs under the code roots that is NOT
# converted (--ignore-submodules=none AND (-z OR --no-renames) AND no swallowed failure) needs a row here: path<TAB>content anchor<TAB>reason.
# One row per SITE, keyed on the REPO-RELATIVE path (a same-named file elsewhere cannot consume a row). A row matching no site is STALE.
EXEMPT_CODE_TABLE='.claude/hooks/brand-hex-commit-gate.sh	git diff "$NAME_REF" --name-only -z	pre-commit first net (header: fail-open stance, the frontend-anti-slop scanner is the second net): scans the ADDED LINES of each changed file, so a rename is read by its new path (the old path holds no lines) and a gitlink has no lines; -z keeps a quoted name exact
.claude/hooks/git-commit-secret-scan.sh	check that '"'"'git diff --cached --name-only'"'"' lists exactly those files, then run the commit WITHOUT the paths (a plain commit	message text inside a printf string, not a reader
.claude/hooks/git-commit-secret-scan.sh	check that '"'"'git diff --cached --name-only'"'"' lists exactly those files, then run the commit WITHOUT the paths in the next	message text inside a printf string, not a reader
.claude/hooks/pre-merge-rebase.sh	-G'"'"'code-review'"'"' --name-only --format= -- todos/	the todos read: each name is looked up one by one (git show per name), and a quoted name fails that lookup (closed); a -z form would CREATE fragment lines that can point at a real tagged todo, so converting it would open the arm
.claude/hooks/pre-merge-rebase.sh	diff --name-only --diff-filter=U	advisory: lists conflicted paths in the deny message only
.claude/hooks/ship-cmo-content-gate.sh	"${BASE_REF}...${TIP}" 2>/dev/null | LC_ALL=C grep -zE	ALLOW reader that already carries all three flags; the trailing || true only keeps pipefail from aborting the hook, an empty list DENIES (fail closed, comment above the line); pinned by PINNED_Z
.claude/hooks/ship-kb-archive-gate.sh	--name-status -z --diff-filter=AMRCT	the status letters ARE the data: the gate reads R/C rows as old/new path pairs, so --no-renames would erase the rename it exists to see; already -z; a failed diff warns and skips the census (existing posture, not changed here)
.claude/hooks/ship-runbook-ssh-gate.sh	"$BASE"...HEAD -- '"'"'knowledge-base/engineering/operations/runbooks/*.md'"'"'	BLOCK reader that already carries all three flags and the NUL read; the || true is the hook documented fail-open posture (an unknown base or a git failure exits 0 before and after this line, header comment), pinned by PINNED_Z
.claude/hooks/skill-security-scan.sh	diff --cached --name-only --diff-filter=A	advisory: counts staged skill-override additions to choose a warning, a miss changes a stderr line only
.github/scripts/check-pr-body-vs-diff.sh	gh pr diff "$PR_NUMBER" --name-only	advisory by design: the check warns and exits 0 when gh fails (header), and a miss only changes a PR-body warning; gh offers no NUL output
.github/scripts/check-sweep-completeness.sh	gh pr diff "$PR_NUMBER" --name-only	the fallback route of an ALLOW reader: gh offers no NUL output, so the script refuses a [\r\n] name before the CR strip on every route and exits 1 (fail closed) when no route yields a changeset
.github/scripts/check-sweep-completeness.sh	gh pr diff --name-only'"'"' — fail-closed	message text in an ::error:: line, not a reader
.github/scripts/check-sweep-completeness.sh	gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/files"	ALLOW reader of DESTINATION names on purpose: pass 1 already catches a rename-away of a registered path through [[ -f ]], and an old name would let a dependent old path satisfy the check; it refuses a [\r\n] name (jq sentinel) and a listing at the 3000 cap exits 1
apps/web-platform/scripts/lint-migration-api-grants.sh	diff origin/main...HEAD --name-only --diff-filter=AMR -- '"'"'apps/web-platform/supabase/migrations/*.sql'"'"'	closed: a C-quoted migration name exits 2 (false red, never a skipped file) and the pathspec is *.sql, so no gitlink can match
apps/web-platform/scripts/lint-migration-immutability.sh	--no-renames --name-only -z "$BASE...$HEAD" -- '"'"'apps/web-platform/supabase/migrations/*.sql'"'"'	already NUL-delimited and rename-free with a failed diff failing closed (exit 2); the pathspec is *.sql, so --ignore-submodules=none could change nothing
apps/web-platform/scripts/rename-guard.sh	--find-renames=5% --find-copies=5%	BLOCK reader on the fail-closed LINE form (CTO G1): the log output goes to a file with no || true, awk and every grep -P run under LC_ALL=C, and a source or target path beginning with " exits 2 naming the cause; the NUL state machine was rejected (git log -z emits an empty token between commits); the R/C status letters are the data, so --no-renames is impossible; executed by scripts/rename-guard.test.sh
plugins/soleur/scripts/alpha-metrics.sh	git log --since=<onboard-date> --name-only	a hint printed to the operator, not a reader
plugins/soleur/scripts/lint-ratchet.py	"-M30%", "--no-ext-diff"	rename detection (-M30%) is the point of this read (it takes R rows); already -z
plugins/soleur/scripts/merge-effect-class.sh	git diff --name-only --no-renames origin/main...HEAD | merge-effect-class.sh --files-from -	usage example in a comment block, not a reader (the real reader takes the files API with previous_filename)
plugins/soleur/scripts/resolve-regenerable-conflicts.sh	git diff -z --name-only --diff-filter=A "$HEAD_SHA" "$TREE"	checks that a path the merge ADDS does not already exist on disk (-e per NUL record); a rename adds its new path, a gitlink adds no file; already NUL-delimited
plugins/soleur/scripts/resolve-regenerable-conflicts.sh	git diff --name-only --diff-filter=U	conflict listing (--diff-filter=U), not a changed-path reader
plugins/soleur/scripts/resolve-regenerable-conflicts.sh	git diff --cached -z --name-only "$TREE"	compares the index against the merged tree for set equality with the regenerated paths, over the NUL stream; any extra path, rename or gitlink makes the sets unequal and bails (fail closed)
plugins/soleur/scripts/sync-pr-behind.sh	git diff --name-only --diff-filter=U	conflict listing (--diff-filter=U) feeding a failure message, not a changed-path reader
plugins/soleur/skills/archive-kb/scripts/archive-kb.sh	git diff --name-status --diff-filter=AM "$base"...HEAD	CTO F1 ruling (row 6): under-archiving is backstopped by the enforcing ship-kb-archive-gate hook, which reads diff --name-status -z --diff-filter=AMRCT and cannot be defeated by the same input; PINNED_Z/exemption row for the hook is the enforcement
plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh	log "$head_sha" --pretty=format: --name-only --diff-filter=AMRC	candidate list (paths ever added) for pruning stale paths against the HEAD tree, quotePath=false keeps non-ASCII raw; a miss leaves a stale path in place, it cannot add a deletion
plugins/soleur/skills/preflight/scripts/founder-check.py	"log", "-z", "--reverse", "--topo-order", "--name-status", "-M"	history walk that follows a plan across renames: the R rows are the data (-M), already -z
plugins/soleur/skills/preflight/scripts/founder-check.py	"diff", "--name-only", merge_base, "HEAD", "--", PLANS_DIR	read through _nul_list, which injects -z (a quoted name stays exact) and returns [] on a failed git; keeps only *.md plan candidates by their destination path
plugins/soleur/skills/preflight/scripts/founder-check.py	"diff", "--name-only", "HEAD", "--", PLANS_DIR	read through _nul_list, which injects -z; the same destination-only candidate read for the working tree
plugins/soleur/skills/review/scripts/emit-review-trailer.sh	git diff --cached --name-only 2>/dev/null | sed	diagnostic listing of staged paths before the script refuses to run (it exits 2 either way)
plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh	diff --name-only origin/main...HEAD --ignore-submodules=none	standing ruling (non-goal): follows scripts/test-all.sh and only appends --ignore-submodules=none; the text is searched with an unanchored grep -F for two literals, so a quoted name still contains them, and a failed read prints unresolved
plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh	diff --name-only HEAD --ignore-submodules=none	standing ruling (non-goal): the same unanchored two-literal search over the working-tree diff; a failed read prints unresolved
plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh	diff --name-status -M HEAD --ignore-submodules=none	standing ruling (non-goal): -M name-status rows carry BOTH paths of a rename, so the unanchored literal search sees the old path; a failed read prints unresolved
plugins/soleur/skills/ship/scripts/battery-refusal-wait.sh	diff --name-status -M origin/main...HEAD --ignore-submodules=none	standing ruling (non-goal): -M name-status rows carry BOTH paths of a rename, so the unanchored literal search sees the old path; a failed read prints unresolved
plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh	pulls/$n/files?per_page=100" --paginate --jq '"'"'.[].filename'"'"'	reads ANOTHER open PR full file list (destination names, as GitHub lists them) after its first page hit the cap; a failure ends in cannot_check; the converted read is the own side (OWN_FILES)
plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh	git diff --name-only "$BASE_SHA...$HEAD_SHA" -- .gitleaks.toml .gitleaksignore .gitattributes	pathspec emptiness over three fixed config files: sets R_CFG only (plan classification: extra no-convert)
plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh	git diff "$BASE...$HEAD" --name-only --diff-filter=A	closed (plan classification): selects newly added override artifacts; a quoted name fails path_re and is never counted as a matched override, so the override does not take effect
scripts/affected-prepass-bench.sh	git -C "$REPO_ROOT" diff -z --diff-filter=A --name-only	benchmark tooling: builds a comma list of added edges for a timing run, never gates a merge
scripts/check-backstop-revision.sh	git diff --no-renames --name-only "${mb}...HEAD"	already rename-free (#12332) and matched with an exact-line grep -Fxq against fixed watched paths, so a quoted name cannot match a watched path
scripts/ci-battery-gate-replay.sh	git log --first-parent -n "$n" --format='"'"'tformat:@@@'"'"' --name-status -M	offline replay report over historical merges (reads status rows); a failed log exits 2
scripts/ci-oracle-review.sh	git diff --name-only --no-renames "$base" HEAD --	already rename-free with the status checked (a failure ends in finish fail api)
scripts/ci-pr-affected-replay.py	"diff-tree", "--no-commit-id", "--name-only", "-r", "-m", "--first-parent", "-z", sha	offline replay tooling over historical merge commits; already -z
scripts/ci-pr-affected-replay.py	"diff", "--name-status", "-z", "--no-renames", sha, "HEAD", "--"	offline replay tooling for the ratchet files a commit adds; already -z and rename-free
scripts/followthroughs/pr-battery-gate-saving-9323.sh	pulls/$pr/files?per_page=100" --jq '"'"'.[].filename'"'"'	follow-through watcher that reports a row (cut / fail / skip) per PR; a miss changes only a report line
scripts/lib/tweet-eligibility.sh	gh pr diff "$PR" --name-only	gh offers no NUL output; a failed read and an empty list both exit 1 (excluded, fail closed), and a quoted name can only miss a deny pattern on a path the operator reads in the draft before it is posted
scripts/lint-art30-reverification.sh	diff --name-status --no-renames --no-textconv	already rename-free over a fixed pathspec list (FILE_PATHS) with a failed read exiting 2
scripts/lint-skill-body-budget.py	"git", "diff", "--name-only", args.base, "HEAD"	closed: the lint only tests changed == {BUDGET_REL}; an extra quoted name makes the set unequal, which is the safe direction
scripts/lint-skill-body-budget.py	"git", "diff", "--name-only", "HEAD"	closed: the same set-equality test over the working tree
scripts/lint-skill-body-budget.py	"git", "diff", "--name-only", "--cached"	closed: the same set-equality test over the index
scripts/lint-trap-tempfile-ownership.py	"diff", "--name-only", "-z", "--diff-filter=d"	rule (c) new-entrant scoping SELECTS the files to lint by destination path (--diff-filter=d); already -z, a failed git exits 2
scripts/pre-push-ratchet-lane.sh	diff --no-renames --name-status "$BASE" origin/main	asks only whether a scripts/*.baseline.txt was ADDED (status letter A) on the main side of the merge delta; a failed read fires the lane (baseline-diff-error), so it fails toward coverage
scripts/pre-push-ratchet-lane.sh	diff --no-renames --name-status "$BASE" HEAD	asks only whether a scripts/*.baseline.txt was ADDED on the branch side; a failed read fires the lane (baseline-diff-error), so it fails toward coverage
scripts/test-all.sh	diff --cached --name-only --ignore-submodules=none	standing ruling (non-goal): test-all.sh only appends --ignore-submodules=none in this arc
scripts/test-all.sh	diff --cached --name-status -M --ignore-submodules=none	standing ruling (non-goal): -M name-status rows carry both paths of a rename; test-all.sh only appends --ignore-submodules=none in this arc
scripts/test-all.sh	diff --name-only HEAD --ignore-submodules=none	standing ruling (non-goal): test-all.sh only appends --ignore-submodules=none in this arc
scripts/test-all.sh	diff --name-only origin/main...HEAD --ignore-submodules=none	standing ruling (non-goal): test-all.sh only appends --ignore-submodules=none in this arc
scripts/test-all.sh	diff --name-status -M HEAD --ignore-submodules=none	standing ruling (non-goal): -M name-status rows carry both paths of a rename; test-all.sh only appends --ignore-submodules=none in this arc
scripts/test-all.sh	diff --name-status -M origin/main...HEAD --ignore-submodules=none	standing ruling (non-goal): -M name-status rows carry both paths of a rename; test-all.sh only appends --ignore-submodules=none in this arc
scripts/weakness-miner.sh	git log --since="$since" --diff-filter=A --name-only --format=	advisory miner: lists learning files added in a window for a report'
EXEMPT_PROSE='plugins/soleur/skills/ship/SKILL.md	git log origin/main..HEAD -G'"'"'code-review'"'"' --name-only --format= -- todos/	closed: the todo lookup is per name (a quoted name finds no file) and a -z form would create fragment lines (the same read stays plain in pre-merge-rebase.sh); backstop: the pre-merge-rebase hook runs the same read
plugins/soleur/skills/ship/SKILL.md	git diff --name-status HASH..HEAD -- plugins/soleur/commands/ plugins/soleur/skills/ plugins/soleur/agents/	NC (CTO F4): a HASH..HEAD slice cannot take the helper without loosening the origin/main...HEAD range pin, and the status letters are the data; backstop: the required test check (components.test.ts counts)
plugins/soleur/skills/ship/SKILL.md	git diff --name-status HASH..HEAD -- plugins/soleur/commands/ plugins/soleur/skills/ plugins/soleur/agents/	NC (CTO F4): the same HASH..HEAD component slice in the later checklist step; backstop: the required test check (components.test.ts counts)
plugins/soleur/skills/ship/SKILL.md	git diff --name-only --diff-filter=A HASH..HEAD	NC (CTO F4): a HASH..HEAD slice cannot take the helper without loosening the origin/main...HEAD range pin; backstop: the enforcing CI lints on the added files
plugins/soleur/skills/ship/SKILL.md	git diff --name-only origin/main...HEAD` for the (a) paths	NC (CTO F1 row P5): the CMO content gate detection; backstop: the ship-cmo-content-gate hook reads the same range with -z and denies (PINNED_Z)
plugins/soleur/skills/ship/SKILL.md	Run `git diff --name-only origin/main...HEAD` and check for `brand-guide.md`	NC (CTO F1 row P5): the CMO brand-guide detection; backstop: the ship-cmo-content-gate hook reads the same range with -z and denies (PINNED_Z)
plugins/soleur/skills/ship/SKILL.md	git diff --name-only HASH..HEAD -- apps/web-platform/ | head -1	NC (CTO F4): emptiness of a HASH..HEAD slice for a deploy-relevant check; backstop: the post-merge deploy verification (postmerge) and required CI checks
plugins/soleur/skills/ship/SKILL.md	git diff --name-only --diff-filter=U	conflict listing (--diff-filter=U), not a changed-path reader
plugins/soleur/skills/ship/SKILL.md	Intersect `git diff --name-only origin/main...HEAD` with `main`	lesson text: an investigation tip about a recurring DIRTY merge state, not an instruction a gate depends on
plugins/soleur/skills/ship/SKILL.md	git diff --name-only --diff-filter=AM HASH..HEAD -- .github/workflows/	NC (CTO F4): a HASH..HEAD slice cannot take the helper without loosening the range pin; backstop: the workflow lints in the required test check
plugins/soleur/skills/ship/SKILL.md	git diff --name-only --diff-filter=A HASH..HEAD -- '"'"'*/supabase/migrations/*.sql'"'"'	NC (CTO F4): a HASH..HEAD slice cannot take the helper without loosening the range pin; backstop: the migration lints (lint-migration-*.sh) in CI
plugins/soleur/skills/ship/SKILL.md	git diff --name-only --diff-filter=AM HASH..HEAD -- '"'"'*.tf'"'"'	NC (CTO F4): a HASH..HEAD slice cannot take the helper without loosening the range pin; backstop: infra-validation on the PR
plugins/soleur/skills/one-shot/SKILL.md	gh pr diff <M> --name-only	advisory: intersects a sibling PR file list with the paths the issue names to weight an abort decision; gh offers no NUL output and a miss changes only the weighting
plugins/soleur/skills/work/SKILL.md	git diff --name-only HEAD...origin/main` to identify files that diverged	advisory: prints a divergence WARN and skips silently on a git failure
plugins/soleur/skills/work/SKILL.md	If any file in `git diff --name-only origin/main...HEAD` (or named in the plan	NC (CTO F1): a reminder to draw down a baselined lint; backstop: the baseline ratchet lints in CI
plugins/soleur/skills/work/SKILL.md	for f in $(git diff --name-only origin/main...HEAD); do git grep -l	NC (CTO F1 row P9): a per-suite fallback recipe used only after the batch gate refused; backstop: the required test check runs every suite
plugins/soleur/skills/work/SKILL.md	If the diff (`git diff --name-only origin/main...HEAD` — the branch-vs-main merge-base diff	NC (CTO F1 row P8): structural-UI visual gate selection; backstop: the CI e2e check
plugins/soleur/skills/qa/SKILL.md	Run it when the diff (`git diff --name-only origin/main...HEAD` — the branch-vs-main merge-base diff	NC (CTO F1 row P8): structural-UI visual gate selection; backstop: the CI e2e check
plugins/soleur/skills/qa/SKILL.md	`git diff --name-only origin/main...HEAD`. **Why:**	lesson text on re-measuring a claimed pre-existing failure, not an instruction a gate depends on
plugins/soleur/skills/review/SKILL.md	$REVIEW_TMP/review-status.txt	NC (row P13): the status letters (A/D/R) are the data for the change-class counts; a failure of the sibling classify call selects the full panel (REVIEW-CLASSIFY-UNKNOWN)
plugins/soleur/skills/review/SKILL.md	Note: `git diff --name-only` does not distinguish added/deleted paths	explanatory note about why deletion-dominated counts need the status read, not a reader
plugins/soleur/skills/review/SKILL.md	run when `git diff main...HEAD --name-only` matches	NC (row P12): informational drift note (item 17); a miss only drops an informational line
plugins/soleur/skills/review/SKILL.md	Mechanical test: `git diff origin/main --name-only | xargs grep -l	lesson example inside a reviewer instruction, not a gate
plugins/soleur/skills/review/SKILL.md	Self-claimed cross-artifact contract drift	lesson text that names the reader in passing, not a gate
plugins/soleur/skills/review/SKILL.md	grep the SHAPE across `git diff --name-only origin/main...HEAD` the moment you fix it	lesson text: a sweep tip for the reviewer, not a gate
plugins/soleur/skills/review/SKILL.md	verify with `git diff origin/main...HEAD --name-only` (three-dot) before accepting	lesson text: advice to verify a reviewer claim by hand, not a gate
plugins/soleur/skills/preflight/SKILL.md	git diff --name-status origin/main...HEAD -- '"'"'*/bun.lock'"'"'	NC (plan row P13): the status letters are load-bearing for the lockfile sync check; backstop: the required lockfile-sync check
plugins/soleur/skills/postmerge/SKILL.md	apps/web-platform/infra/ci-deploy\.sh	different data source (the MERGED PR, which the helper cannot take); the match only raises PIPELINE_GATE_CHANGE; text pinned by deploy-arm.test.sh
plugins/soleur/skills/postmerge/SKILL.md	plugins/soleur/skills/(ship|postmerge)/SKILL	different data source (the MERGED PR, which the helper cannot take); the match only raises PIPELINE_GATE_CHANGE; line 217 text pinned by deploy-arm.test.sh
plugins/soleur/skills/postmerge/SKILL.md	gh pr diff <number> --name-only	different data source (the MERGED PR, which the helper cannot take): the listing step of a post-merge verification, advisory
plugins/soleur/skills/postmerge/SKILL.md	changed=$(gh pr diff <number> --name-only)	different data source (the MERGED PR, which the helper cannot take): a post-merge verification read, advisory
plugins/soleur/skills/postmerge/SKILL.md	(`gh pr diff <number> --name-only`), the merge	different data source (the MERGED PR, which the helper cannot take): a post-merge verification trigger, advisory
plugins/soleur/skills/postmerge/SKILL.md	git diff --name-status --diff-filter=AMRCT	the status letters are the data (R/C rows carry both paths) over a merge-base slice of a merged commit; a post-merge verification read, advisory'
SENT_FILE_FLOOR=100
SENT_SITE_FLOOR=20
CODE_FILE_FLOOR=800
CODE_SITE_FLOOR=85
PROSE_FILE_FLOOR=13
PROSE_SITE_FLOOR=34

# The code roots (git pathspecs) and the closed prose list the censuses read. The code list is the tracked files under the roots, NOT test files
# (`*.test.*`, `*.spec.*`, `/test/`, `/tests/`); members drift, so it is never enumerated here. The prose list is closed on purpose: tree-wide
# prose is lesson and example text, so only the skills whose instructions run a gate and the converted references and agents are censused.
CODE_ROOTS=(.claude/hooks scripts plugins/soleur/scripts apps/web-platform/scripts .github/scripts 'plugins/soleur/skills/*/scripts/*')
PROSE_FILES=(
  plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/one-shot/SKILL.md plugins/soleur/skills/work/SKILL.md
  plugins/soleur/skills/qa/SKILL.md plugins/soleur/skills/review/SKILL.md plugins/soleur/skills/preflight/SKILL.md
  plugins/soleur/skills/postmerge/SKILL.md
  plugins/soleur/skills/ship/references/settle-then-admin-merge.md plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md
  plugins/soleur/skills/ship/references/adr-ordinal-collision.md plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md
  plugins/soleur/agents/engineering/review/semgrep-sast.md plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md
)

# The hooks, scripts, workflows and prose this PR converts keep their NUL-delimited / rename-free read (file<TAB>diff-line regex). The census
# sees the flags on a plain `git diff` line; this list keeps what it CANNOT see: prose files, the `previous_filename` emitting form, flag-only
# sites and the spellings a census regex would let through.
PINNED_Z='.claude/hooks/ship-cmo-content-gate.sh	diff[^|]* -z( |$)
.claude/hooks/ship-cmo-content-gate.sh	LC_ALL=C grep -zE .\^\(plugins/soleur/docs/blog/
.claude/hooks/ship-runbook-ssh-gate.sh	diff[^|]* -z( |$)
plugins/soleur/scripts/changed-paths.sh	diff -z --no-renames --ignore-submodules=none --name-only
apps/web-platform/.github/workflows/constraint-gates.yml	changed_files=.*git diff -z --no-renames --ignore-submodules=none --name-only
.github/workflows/pr-quality-guards.yml	surface_files=.*git diff -z --no-renames --ignore-submodules=none --name-only
.github/workflows/pr-quality-guards.yml	git diff -z --name-only "\$\{diff_base\}"\.\.\.HEAD > "\$changed_nul"
.github/workflows/pr-quality-guards.yml	grep -zFxc -- "\$legal" "\$changed_nul"
.github/workflows/secret-scan.yml	CHANGED=.*git diff -z --name-only
plugins/soleur/skills/ship/references/settle-then-admin-merge.md	files="\$\(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only origin/main\.\.\.HEAD \| tr '"'"'\\n\\0'"'"' '"'"'\?\\n'"'"'\)"
scripts/pre-push-ratchet-lane.sh	git -C "\$REPO_ROOT" diff -z --no-renames --ignore-submodules=none --name-only "\$BASE" HEAD \\$
scripts/pre-push-ratchet-lane.sh	git -C "\$REPO_ROOT" diff -z --no-renames --ignore-submodules=none --name-only "\$BASE" origin/main \\$
.github/workflows/web-platform-release.yml	--jq '"'"'\(\.files\|length\), \(\.files\[\] \| \.filename, \(\.previous_filename // empty\)\)'"'"'
.github/workflows/registry-host-replace-dispatch.yml	jq -r '"'"'\.files\[\]\? \| \.filename, \(\.previous_filename // empty\)'"'"'
apps/web-platform/scripts/allowlist-diff.sh	git -C "\$\{REPO_ROOT\}" diff --no-renames --ignore-submodules=none --name-only "\$\{BASE_SHA\}\.\.\$\{HEAD_SHA\}" -- '"'"':\(top,literal\)\.gitleaks\.toml'"'"'
plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh	OWN_FILES="\$\(set -o pipefail; git diff -z --no-renames --ignore-submodules=none --name-only origin/main\.\.\.HEAD'

SENT_PY="$WORK_ROOT/sentinel.py"
cat > "$SENT_PY" <<'PY'
import os, re, sys
# usage: sentinel.py <table> <root> <mode: wf|code|prose> <files...>
# A site is one `git diff|log|show|diff-tree ... --name-only|--name-status` (or `gh pr diff ... --name-only`) read, in shell text, a
# Python/ts/mjs argv list, or (code mode) a `gh api .../files|.../compare` reader. It is CONVERTED when it carries
# `--ignore-submodules=none` AND (`-z` OR `--no-renames`) AND its failure is not swallowed; otherwise it needs a row in the table.
table_path, root, mode = sys.argv[1:4]
files = sys.argv[4:]
rows = []
for ln in open(table_path, encoding="utf-8").read().split("\n"):
    if not ln.strip() or ln.startswith("#"):
        continue
    f, a, r = ln.split("\t", 2)
    rows.append([f, a, r, False])
# A segment is cut at `|` (so `||` too), `;`, `&&` and a newline: NOT at a single `&` (the `&` of `2>&1`), NOT at `)`, so
# `git diff "$(git merge-base a b)"...HEAD --name-only` is one site. Between the launcher and the verb ANY option words are accepted
# (`--no-optional-locks`, `--literal-pathspecs`, `--git-dir "$X"`, `-C"$d"`, `-c k=v`), the launcher may be `git`, `$GIT` or `"${GIT[@]}"`,
# and the verb may be quoted (`git "diff"`).
SEG = r"(?:[^|;\n&]|&(?!&))"
GIT = re.compile(r"(?:\bgit\b|\"?\$\{GIT\[@\]\}\"?|\"?\$GIT\b\"?)" + SEG + r"*?\s[\"']?(?:diff|log|show|diff-tree)\b" + SEG + r"*")
GH = re.compile(r"\bgh\s+pr\s+diff\b" + SEG + r"*")
# Python / ts / mjs argv list: ["git", "diff", ...] / _git(["diff", ...]) / git_out_z(["log", ...]); the list may span lines.
ARGV = re.compile(r"\[\s*(?:[\"']git[\"']\s*,\s*)?[\"'](?:diff|log|show|diff-tree)[\"']\s*,([^\]]*)\]")
# A trailing `# comment` is not part of the command: `... --name-only a...b # was -z )` is still UNCONVERTED.
COMMENT = re.compile(r"(?:^|\s)#.*$")
NAMES = re.compile(r"--name-only|--name-status")
Z = re.compile(r"(?:^|[\s\"'])-z(?![\w-])")
NOREN = re.compile(r"(?:^|[\s\"'])--no-renames(?![\w-])")
SUBM = re.compile(r"--ignore-submodules=none(?![\w-])")
# A failure that is turned into "nothing changed": `|| true`, `|| :`, `|| echo ""` anywhere after the reader on the same logical line.
SWALLOW = re.compile(r"\|\|\s*(?:true\b|:(?:\s|\)|$)|echo\s+(?:\"\"|'')|echo\s*\)|\{\s*(?:true|:)\b)")
# API readers: a files / compare endpoint whose response names are read. Converted = the file also emits `previous_filename`
# through a defaulting expression (`(.previous_filename // empty)` or `// ""`): a bare token is satisfiable by a stub.
APIEP = re.compile(r"(?:\bgh\s+api\b|\bapi\s+[\"'])" + r"[^\n]*?(?:/pulls/[^\s\"']*/files|/compare/)")
PREV_OK = re.compile(r"\.filename\s*,\s*\(\s*\.previous_filename\s*//\s*(?:empty|\"\")\s*\)")


def strip_block(text):  # /* ... */ -> spaces, newlines kept
    return re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)


def shell_logical(text, ext):
    out = []
    cur = None
    lines = text.split("\n")
    for i, line in enumerate(lines, 1):
        if cur is None and re.match(r"^\s*//" if ext in ("ts", "mjs") else r"^\s*#", line):
            continue
        if cur is None:
            cur = [i, ""]
        cont = line.rstrip().endswith("\\")
        body = line.rstrip()[:-1] if cont else line
        body = COMMENT.sub("", body) if ext in ("sh", "yml", "py") else re.sub(r"(?:^|\s)//.*$", "", body)
        if cont:
            cur[1] += body.strip() + " "
            continue
        cur[1] += body.strip()
        out.append(tuple(cur))
        cur = None
    return out


def argv_flags(inner):
    toks = re.findall(r"[\"']([^\"']*)[\"']", inner)
    return toks


scanned = sites = exempt = apisites = 0
unlisted = []


def lookup(rel, ltxt):
    for r in rows:
        if not r[3] and r[0] == rel and r[1] in ltxt:
            r[3] = True
            return True
    return False


def converted(seg, tail, toks=None):
    if toks is not None:
        z = "-z" in toks
        nr = "--no-renames" in toks
        sm = "--ignore-submodules=none" in toks
    else:
        z = bool(Z.search(seg))
        nr = bool(NOREN.search(seg))
        sm = bool(SUBM.search(seg))
    return sm and (z or nr) and not SWALLOW.search(tail)


for path in files:
    try:
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
    except OSError:
        continue
    scanned += 1
    rel = os.path.relpath(path, root)
    ext = rel.rsplit(".", 1)[-1] if "." in rel else ""
    if ext in ("ts", "mjs"):
        text = strip_block(text)
    nocomment = None
    # shell-shaped text (also run on .py / .ts: a `git diff --name-only` string passed to a shell)
    for lineno, ltxt in (shell_logical(text, ext) if ext not in ("py", "ts", "mjs") else []):
        for rx in (GIT, GH):
            for m in rx.finditer(ltxt):
                seg = COMMENT.sub("", m.group(0)) if ext not in ("ts", "mjs") else m.group(0)
                if not NAMES.search(seg):
                    continue
                sites += 1
                tail = ltxt[m.end():]
                if rx is GIT and converted(seg, tail):
                    continue
                if lookup(rel, ltxt):
                    exempt += 1
                else:
                    unlisted.append("%s:%d :: %s" % (rel, lineno, seg.strip()[:110]))
    if ext in ("py", "ts", "mjs"):
        body = "\n".join(
            (re.sub(r"(?:^|\s)#.*$", "", ln) if ext == "py" else re.sub(r"(?:^|\s)//.*$", "", ln))
            for ln in text.split("\n")
        )
        for m in ARGV.finditer(body):
            toks = argv_flags(m.group(1))
            if not any(t in ("--name-only", "--name-status") for t in toks):
                continue
            sites += 1
            lineno = body.count("\n", 0, m.start()) + 1
            tail = body[m.end(): body.find("\n", m.end()) if body.find("\n", m.end()) >= 0 else len(body)]
            if converted("", tail, toks):
                continue
            ltxt = " ".join(body.split("\n")[lineno - 1: lineno + 1 + m.group(0).count("\n")])
            if lookup(rel, m.group(0).replace("\n", " ") + " " + ltxt):
                exempt += 1
            else:
                unlisted.append("%s:%d :: %s" % (rel, lineno, " ".join(m.group(0).split())[:110]))
    if mode == "code" and ext in ("sh", "py", "ts", "mjs"):
        logical_api = shell_logical(text, ext)
        live = "\n".join(t for _, t in logical_api)
        reads_names = re.search(r"filename", live) is not None
        prev_lines = [n for n, t in logical_api if PREV_OK.search(t)]
        for lineno, ltxt in logical_api:
            if APIEP.search(ltxt) and reads_names:
                apisites += 1
                sites += 1
                # the emitting form must sit on the reader or within the next 60 lines (the jq that reads the saved response), not anywhere in the file
                if PREV_OK.search(ltxt) or any(lineno - 10 <= n <= lineno + 60 for n in prev_lines):
                    continue
                if lookup(rel, ltxt):
                    exempt += 1
                else:
                    unlisted.append("%s:%d :: %s" % (rel, lineno, "gh api files/compare reader without a previous_filename emitting form: " + ltxt.strip()[:70]))
print("SCANNED %d" % scanned)
print("SITES %d" % sites)
print("EXEMPT %d" % exempt)
print("APISITES %d" % apisites)
for u in unlisted:
    print("UNLISTED " + u)
for r in rows:
    if not r[3]:
        print("STALE %s :: %s" % (r[0], r[1]))
PY

SENT_RC=0
sent_run() { # <table text> <root> <mode: wf|code|prose> <files...>  -> SENT_OUT, SENT_RC
  printf '%s\n' "$1" > "$WORK_ROOT/io/table.tsv"
  local root="$2" mode="$3"; shift 3
  SENT_RC=0
  SENT_OUT="$(python3 -I "$SENT_PY" "$WORK_ROOT/io/table.tsv" "$root" "$mode" "$@")" || SENT_RC=$?
}
sent_n() { printf '%s\n' "$SENT_OUT" | sed -n "s/^$1 //p" | head -1; }

# Every census reports through THIS function (so selftest_moved can drive it with one-violation inputs): ONE pass when nothing is unlisted
# or stale, otherwise one FAIL per violation. The site count joins CENSUS_ROWS (floored at the bottom of the file).
census_report() { # <label> <scanner output>
  local label="$1" out="$2" l n_sites n_bad=0
  n_sites="$(printf '%s\n' "$out" | sed -n 's/^SITES //p' | head -1)"
  CENSUS_ROWS=$((CENSUS_ROWS + ${n_sites:-0}))
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    n_bad=$((n_bad + 1))
    fail "sentinel $label: ${l#UNLISTED } -- every changed-path reader must carry --ignore-submodules=none and -z or --no-renames, with no swallowed failure (git diff -z --no-renames --ignore-submodules=none --name-only ... | tr '\\0' '\\n'): convert it or add a row with a reason to the $label exemption table"
  done < <(printf '%s\n' "$out" | grep '^UNLISTED' || true)
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    n_bad=$((n_bad + 1))
    fail "sentinel $label: stale exemption entry ${l#STALE }"
  done < <(printf '%s\n' "$out" | grep '^STALE' || true)
  if [ "$n_bad" -eq 0 ]; then pass "sentinel $label: 0 unlisted sites, 0 stale exemption entries (${n_sites:-0} sites)"; fi
}

# Every exemption row names a path, an anchor and a reason (a row without one is a silent waiver).
exempt_rows_check() { # <label> <table>
  local label="$1" n bad
  n="$(printf '%s\n' "$2" | grep -c . || true)"
  bad="$(printf '%s\n' "$2" | awk -F'\t' 'NF >= 1 && $0 != "" && (NF < 3 || $1 == "" || $2 == "" || length($3) < 20) { c++ } END { print c + 0 }')"
  if [ "$bad" -eq 0 ] && [ "$n" -ge 1 ]; then pass "sentinel $label: all $n exemption rows carry a path, an anchor and a reason"
  else fail "sentinel $label: $bad of $n exemption rows lack a path, an anchor or a reason of at least 20 characters"; fi
}

# One census over a file list: run the scanner, enforce the in-function floors (the `sentinel`-only dispatch has no bottom-of-file floor),
# report through census_report.
census_scan() { # <label> <table> <mode> <file floor> <site floor> <files...>
  local label="$1" tbl="$2" mode="$3" ffloor="$4" sfloor="$5" scanned sites exempt
  shift 5
  sent_run "$tbl" "$REPO_ROOT" "$mode" "$@"
  if [ "$SENT_RC" -ne 0 ]; then fail "sentinel $label: the scanner exited $SENT_RC (a malformed exemption row or a crash); it asserted nothing"; fi
  scanned="$(sent_n SCANNED)"; sites="$(sent_n SITES)"; exempt="$(sent_n EXEMPT)"
  if [ "${scanned:-0}" -ge "$ffloor" ]; then pass "sentinel $label: scanned $scanned tracked files (floor $ffloor)"; else fail "sentinel $label: scanned only ${scanned:-0} files, floor $ffloor (the scan glob or a root went stale)"; fi
  if [ "${sites:-0}" -ge "$sfloor" ]; then pass "sentinel $label: found $sites reader sites (floor $sfloor)"; else fail "sentinel $label: found only ${sites:-0} reader sites, floor $sfloor (the classifier stopped matching)"; fi
  census_report "$label" "$SENT_OUT"
  echo "census[$label]: ${sites:-0} sites, $(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED' || true) unlisted, $(printf '%s\n' "$SENT_OUT" | grep -c '^STALE' || true) stale (${exempt:-0} exempt)"
}

# One pinned row: comment lines are stripped first (a `# git diff -z ...` comment must not satisfy the pin), then the line regex must match.
PIN_ROOT="$REPO_ROOT"   # the tree the pins read; the self-tests point it at a synthetic tree, never at a live file
pinned_z_check() { # <file> <regex>
  local f="$1" rx="$2" body
  if [ ! -f "$PIN_ROOT/$f" ]; then fail "sentinel pinned: $f is missing"; return; fi
  body="$(grep -v '^[[:space:]]*#' "$PIN_ROOT/$f")"
  if grep -Eq -e "$rx" <<<"$body"; then pass "sentinel pinned: $f keeps its NUL-delimited read ($rx)"; else fail "sentinel pinned: $f lost its read (expected a non-comment line matching: $rx)"; fi
}

selftest_pinned() {
  # The positive control is a SYNTHETIC file: reverting a pinned token in the live helper must fail its own pinned row, not abort the run
  # here with a misleading "helper is inert" FATAL that hides every later row.
  local o_root="$PIN_ROOT"
  PIN_ROOT="$WORK_ROOT/pin-selftest"
  mkdir -p "$PIN_ROOT" || { printf 'FATAL: cannot create %s\n' "$PIN_ROOT" >&2; exit 1; }
  printf '%s\n' '# synthetic: git diff -z --no-renames only in this comment line' 'git diff -z --no-renames --name-only "$@"' > "$PIN_ROOT/synthetic.sh"
  selftest_moved "pinned_z_check accepts a pinned line that exists" pass pinned_z_check synthetic.sh 'diff -z --no-renames'
  selftest_moved "pinned_z_check rejects a regex no line matches" fail pinned_z_check synthetic.sh 'selftest-no-such-line-zzz'
  selftest_moved "pinned_z_check rejects a pin only a comment line satisfies" fail pinned_z_check synthetic.sh '^# synthetic: git diff -z'
  selftest_moved "pinned_z_check rejects a missing file" fail pinned_z_check no-such-file.sh 'diff'
  PIN_ROOT="$o_root"
}

# Skill prose is not executed here; this pins its SPELLING and its FAIL-CLOSED SHAPE, on comment-stripped text (a `# ...` line or a
# markdown heading never satisfies a pin), anchored on the call forms:
#   spelling   every `changed-paths.sh` is the whole call form `bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh"` (a bare or doubled
#              name resolves against the wrong cwd or an unset root);
#   range      every line naming the helper names `origin/main...HEAD` (the PR's own diff, never a default target);
#   ship       each gdpr/DPF/canonical `--match` assignment keeps `|| { [ $? -eq 1 ] || VAR=unknown; }` (rc 1 = no match; any other rc is
#              unknown and the gate runs);
#   preflight  the Step 0.1 cache line keeps `|| { rm -f <cache>; echo "PREFLIGHT-CACHE-MISSING..." }`, the Cache-missing rule keeps
#              `cache file absent => RUN`, and the SKIP predicate of Checks 1, 2, 6, 8 and 10 each says `cache file is absent, RUN`;
#   review     the classify call keeps `|| { ...REVIEW-CLASSIFY-UNKNOWN... }`.
SKILL_CALL='bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh"'
RX_CALL='bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh"'
SKILL_ROOT="$REPO_ROOT"   # the tree the skill pins read; the self-tests point it at a synthetic tree
skill_body() { # <sk> -> comment-stripped SKILL.md on stdout (rc 1 when the file is missing)
  local f="$SKILL_ROOT/plugins/soleur/skills/$1/SKILL.md"
  [ -f "$f" ] || return 1
  grep -v '^[[:space:]]*#' "$f"
}
skill_section() { # <sk> <heading ERE> -> comment-stripped body of the `##`/`###` section opening at that heading (code fences respected)
  awk -v pat="$2" '
    /^```/ { fence = !fence }
    !fence && ($0 ~ /^## / || $0 ~ /^### /) { if (on) exit; if ($0 ~ pat) { on = 1; next } }
    on && $0 !~ /^[[:space:]]*#/ { print }
  ' "$SKILL_ROOT/plugins/soleur/skills/$1/SKILL.md"
}
skill_spelling_pin() { # <sk>
  local sk="$1" body total good
  if ! body="$(skill_body "$sk")"; then fail "skill pin: plugins/soleur/skills/$sk/SKILL.md is missing"; return; fi
  total="$(grep -o -- 'changed-paths\.sh' <<<"$body" | wc -l)"
  good="$(grep -oF -- "$SKILL_CALL" <<<"$body" | wc -l)"
  if [ "$total" -ge 1 ] && [ "$total" -eq "$good" ]; then pass "skill pin: every changed-paths.sh in $sk/SKILL.md is the call form $SKILL_CALL ($good of $total)"
  else fail "skill pin: $sk/SKILL.md has $total changed-paths.sh mention(s) but only $good in the call form $SKILL_CALL"; fi
}
skill_range_pin() { # <sk>
  local sk="$1" body total ranged
  if ! body="$(skill_body "$sk")"; then fail "skill pin: $sk/SKILL.md is missing"; return; fi
  total="$(grep -c -- 'changed-paths\.sh' <<<"$body" || true)"
  ranged="$(grep -- 'changed-paths\.sh' <<<"$body" | grep -c -F -- 'origin/main...HEAD' || true)"
  if [ "$total" -ge 1 ] && [ "$total" -eq "$ranged" ]; then pass "skill pin: every changed-paths.sh line in $sk/SKILL.md names origin/main...HEAD ($ranged of $total)"
  else fail "skill pin: $sk/SKILL.md has $total changed-paths.sh line(s), only $ranged name origin/main...HEAD"; fi
}
skill_ship_handler_pin() {
  local body calls good v missing=""
  if ! body="$(skill_body ship)"; then fail "skill pin: ship/SKILL.md is missing"; return; fi
  calls="$(grep -c -E -- "=\\\$\\($RX_CALL --match " <<<"$body" || true)"
  good="$(grep -c -E -- "^([a-z_]+)=\\\$\\($RX_CALL --match .+ origin/main\\.\\.\\.HEAD\\) \\|\\| \\{ \\[ \\\$\\? -eq 1 \\] \\|\\| \\1=unknown; \\}\$" <<<"$body" || true)"
  for v in gdpr_gate_touch diff_match dpf_match ledger_touched plan_refs; do
    grep -q -E -- "^$v=\\\$\\($RX_CALL --match .+ origin/main\\.\\.\\.HEAD\\) \\|\\| \\{ \\[ \\\$\\? -eq 1 \\] \\|\\| $v=unknown; \\}\$" <<<"$body" || missing="$missing $v"
  done
  if [ -z "$missing" ] && [ "$calls" -ge 5 ] && [ "$calls" -eq "$good" ]; then pass "skill pin: the $calls ship --match assignments keep the fail-closed handler (|| { [ \$? -eq 1 ] || VAR=unknown; }) and origin/main...HEAD"
  else fail "skill pin: ship/SKILL.md --match assignments: $calls found, $good with the fail-closed handler + origin/main...HEAD; missing or malformed:${missing:- none by name}"; fi
}
skill_preflight_pin() {
  local body missing="" sec c
  if ! body="$(skill_body preflight)"; then fail "skill pin: preflight/SKILL.md is missing"; return; fi
  if grep -q -E -- "^$RX_CALL origin/main\\.\\.\\.HEAD > \"\\\$PREFLIGHT_TMP/[^\"]+\" \\|\\| \\{ rm -f \"\\\$PREFLIGHT_TMP/[^\"]+\"; echo \"PREFLIGHT-CACHE-MISSING" <<<"$body"; then
    pass "skill pin: the preflight Step 0.1 call writes the cache and, on failure, rm -f's it and prints PREFLIGHT-CACHE-MISSING"
  else fail "skill pin: preflight/SKILL.md lost the Step 0.1 form: $RX_CALL origin/main...HEAD > \"\$PREFLIGHT_TMP/...\" || { rm -f \"\$PREFLIGHT_TMP/...\"; echo \"PREFLIGHT-CACHE-MISSING..."; fi
  if grep -q -F -- 'cache file absent => RUN; `grep` rc 1 => SKIP' <<<"$body"; then pass "skill pin: the Cache-missing rule keeps 'cache file absent => RUN; grep rc 1 => SKIP'"
  else fail "skill pin: preflight/SKILL.md lost the Cache-missing rule wording 'cache file absent => RUN; \`grep\` rc 1 => SKIP'"; fi
  for c in 1 2 6 8 10; do
    sec="$(skill_section preflight "^### Check $c: ")"
    if [ -z "$sec" ]; then missing="$missing $c(no such section)"; continue; fi
    grep -q -F -- 'cache file is absent, RUN' <<<"$sec" || missing="$missing $c"
    grep -q -F -- 'SKIP' <<<"$sec" || missing="$missing $c(no SKIP)"
  done
  if [ -z "$missing" ]; then pass "skill pin: the SKIP predicate of preflight Checks 1, 2, 6, 8 and 10 each says 'cache file is absent, RUN'"
  else fail "skill pin: preflight Checks missing the 'cache file is absent, RUN' wording or a SKIP predicate:$missing"; fi
}
skill_review_pin() {
  local body
  if ! body="$(skill_body review)"; then fail "skill pin: review/SKILL.md is missing"; return; fi
  if grep -q -E -- "^[[:space:]]*$RX_CALL origin/main\\.\\.\\.HEAD > \"[^\"]+\" \\|\\| \\{ .*REVIEW-CLASSIFY-UNKNOWN" <<<"$body"; then pass "skill pin: the review classify call keeps its || { ... REVIEW-CLASSIFY-UNKNOWN ... } handler"
  else fail "skill pin: review/SKILL.md lost the classify form: $RX_CALL origin/main...HEAD > \"...\" || { ...REVIEW-CLASSIFY-UNKNOWN..."; fi
}
# ship gate semantics the handler shape alone cannot say: the vendor-cost ledger match is the EXACT path (anchored, `.` escaped, AMT so a deletion is
# not an edit) and `unknown` never exempts it; the Closes-after-verification gate tests `unknown` EXPLICITLY (else `grep ... $plan_refs` greps a file
# named `unknown`, prints nothing and lets `Closes` through).
skill_ship_semantics_pin() {
  local body missing=""
  if ! body="$(skill_body ship)"; then fail "skill pin: ship/SKILL.md is missing"; return; fi
  grep -q -F -- "--match '^knowledge-base/operations/expenses\.md\$' --diff-filter=AMT origin/main...HEAD)" <<<"$body" || missing="$missing ledger-regex-anchored-escaped-AMT"
  grep -q -F -- 'is not exactly `knowledge-base/operations/expenses.md` (`unknown` fires the gate)' <<<"$body" || missing="$missing ledger-exact-equality-rule"
  grep -q -F -- '[[ $plan_refs == unknown ]] && echo' <<<"$body" || missing="$missing plan_refs-explicit-unknown-branch"
  if [ -z "$missing" ]; then pass "skill pin: ship keeps the exact-path ledger match, the exact-equality exemption rule and the explicit plan_refs unknown branch"
  else fail "skill pin: ship/SKILL.md lost:$missing"; fi
}
# one-shot: its scope check is the plain-mode list (no --match), so it has no `VAR=unknown` handler; the failure arm is prose: exit 2/127 is a breach.
skill_oneshot_pin() {
  local body line
  if ! body="$(skill_body one-shot)"; then fail "skill pin: one-shot/SKILL.md is missing"; return; fi
  line="$(grep -F -- 'changed-paths.sh' <<<"$body" | head -n 1)"
  if grep -q -F -- 'exit 2/127 = scope unverified: treat as a breach' <<<"$line" && grep -q -F -- '^knowledge-base/project/(plans|specs)/' <<<"$line"; then
    pass "skill pin: the one-shot scope check keeps 'exit 2/127 = scope unverified: treat as a breach' and the anchored plans|specs containment regex on the helper line"
  else fail "skill pin: one-shot/SKILL.md lost the scope-check failure arm ('exit 2/127 = scope unverified: treat as a breach') or the ^knowledge-base/project/(plans|specs)/ containment regex on the helper line"; fi
}
# Converted references and agents: ONE exact capture shape per file (every mention of the helper is that shape, a trailing `# comment` is
# stripped first so `|| true # unknown` cannot hide), the failure-arm text is present, and the `:-` plugin-root arm is absent. risk-tier-and-fix-rounds.md
# spells the root `<plugin-root>` (it carries no plugin-root notice and is not a Read-surface doc), so its shape accepts that spelling.
# file<TAB>shape ERE (each mention must match it)<TAB>failure-arm fixed string<TAB>fixture line (the compliant tree)
REF_PINS="$(cat <<'TSV'
plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md	^legal_touch=\$\(bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh" --match '[^']+' origin/main\.\.\.HEAD\) \|\| \{ \[ \$\? -eq 1 \] \|\| legal_touch=unknown; \}$	|| { [ $? -eq 1 ] || legal_touch=unknown; }	legal_touch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match '^docs/legal/' origin/main...HEAD) || { [ $? -eq 1 ] || legal_touch=unknown; }
plugins/soleur/skills/ship/references/adr-ordinal-collision.md	^files=\$\(bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh" origin/main\.\.\.HEAD\) \|\| files=\$\(git ls-files\)$	|| files=$(git ls-files)	   files=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" origin/main...HEAD) || files=$(git ls-files)   # list unknown: sweep every tracked file
plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md	^files=\$\(bash (<plugin-root>|"\$\{CLAUDE_PLUGIN_ROOT\}")/scripts/changed-paths\.sh "\$PANEL_SHA"\.\.HEAD\) \|\| files=unknown$	|| files=unknown	   files=$(bash <plugin-root>/scripts/changed-paths.sh "$PANEL_SHA"..HEAD) || files=unknown   # unknown: spawn the full class panel
plugins/soleur/agents/engineering/review/semgrep-sast.md	`bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh" --diff-filter=ACMR origin/main\.\.\.HEAD`	If the helper exits 2 or 127 the file list is unknown: abort	2. Identify changed files with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --diff-filter=ACMR origin/main...HEAD`. If the helper exits 2 or 127 the file list is unknown: abort and report.
plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md	`bash "\$\{CLAUDE_PLUGIN_ROOT\}/scripts/changed-paths\.sh" origin/main\.\.\.HEAD`	exit 2/127 = inventory unknown	Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" origin/main...HEAD` and partition its list (exit 2/127 = inventory unknown: every category is in scope):
TSV
)"
skill_ref_pin() { # <repo-relative file> <shape ERE> <failure-arm fixed string>
  local rel="$1" shape="$2" arm="$3" f body mentions good
  f="$SKILL_ROOT/$rel"
  if [ ! -f "$f" ]; then fail "skill pin: $rel is missing"; return; fi
  body="$(grep -v '^[[:space:]]*#' "$f" | sed -E 's/[[:space:]]+# .*$//' | sed -E 's/^[[:space:]]+//')"
  mentions="$(grep -o -- 'changed-paths\.sh' <<<"$body" | wc -l)"
  good="$(grep -o -E -- "$shape" <<<"$body" | wc -l)"
  if [ "$mentions" -ge 1 ] && [ "$mentions" -eq "$good" ] && grep -q -F -- "$arm" <<<"$body" && ! grep -q -F -- 'CLAUDE_PLUGIN_ROOT:-' <<<"$body"; then
    pass "skill pin: every changed-paths.sh mention in $rel is the exact capture shape ($good of $mentions) with its failure arm and no :- root arm"
  else fail "skill pin: $rel has $mentions changed-paths.sh mention(s), $good in the exact capture shape; the failure arm '$arm' must be present and the :- root arm absent"; fi
}
skill_ref_pins() {
  local rel shape arm
  while IFS=$'\t' read -r rel shape arm _; do
    [ -n "$rel" ] || continue
    skill_ref_pin "$rel" "$shape" "$arm"
  done <<<"$REF_PINS"
}
skill_prose_pins() {
  local sk
  for sk in preflight ship review one-shot; do skill_spelling_pin "$sk"; done
  for sk in preflight ship review one-shot; do skill_range_pin "$sk"; done
  skill_ship_handler_pin
  skill_preflight_pin
  skill_review_pin
  skill_ship_semantics_pin
  skill_oneshot_pin
  skill_ref_pins
}

# Self-tests for the skill pins: a SYNTHETIC skills tree is the positive control (every pin passes, none fails), and each single defect
# below must move the FAIL counter. The whole of skill_prose_pins is run on each tree; counters are unwound like selftest_moved.
skill_fixture() { # <root>
  local r="$1/plugins/soleur/skills" call='bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh"'
  case "$1" in /*) : ;; *) return 1 ;; esac
  mkdir -p "$r/preflight" "$r/ship" "$r/review" "$r/one-shot" || return 1
  {
    printf '## Phase 0\n\n```bash\n'
    printf '%s origin/main...HEAD %s "$PREFLIGHT_TMP/preflight-diff-files.txt" || { rm -f "$PREFLIGHT_TMP/preflight-diff-files.txt"; echo "PREFLIGHT-CACHE-MISSING: helper failed"; }\n' "$call" '>'
    printf '```\n\n**Cache-missing rule.** Every SKIP predicate below reads: cache file absent => RUN; `grep` rc 1 => SKIP; rc 2 => RUN.\n\n'
    local c
    for c in 1 2 3 6 8 10; do
      printf '### Check %s: name\n\n# a comment line\nFor Check %s the cache file is absent, RUN. Otherwise `grep` rc 1 => return **SKIP**.\n\n' "$c" "$c"
    done
    printf '### Check 11: tail\n\nbody\n'
  } > "$1/plugins/soleur/skills/preflight/SKILL.md"
  {
    printf '```bash\n'
    printf 'gdpr_gate_touch=$(%s --match '"'"'^plugins/x/'"'"' origin/main...HEAD) || { [ $? -eq 1 ] || gdpr_gate_touch=unknown; }\n' "$call"
    printf 'diff_match=$(%s --match "$CANONICAL_REGEX" origin/main...HEAD) || { [ $? -eq 1 ] || diff_match=unknown; }\n' "$call"
    printf 'dpf_match=$(%s --match "$DPF_REGEX" origin/main...HEAD) || { [ $? -eq 1 ] || dpf_match=unknown; }\n' "$call"
    printf 'ledger_touched=$(%s --match %s --diff-filter=AMT origin/main...HEAD) || { [ $? -eq 1 ] || ledger_touched=unknown; }\n' "$call" "'^knowledge-base/operations/expenses\.md\$'"
    printf 'plan_refs=$(%s --match %s origin/main...HEAD) || { [ $? -eq 1 ] || plan_refs=unknown; }\n' "$call" "'^knowledge-base/project/(plans|specs)/'"
    printf '%s\n' "[[ \$plan_refs == unknown ]] && echo 'unverifiable: use Ref #N' || true"
    printf '%s\n' 'Rule. If a signal fires AND `ledger_touched` is not exactly `knowledge-base/operations/expenses.md` (`unknown` fires the gate), the change MUST carry a companion.'
    printf '```\n'
  } > "$1/plugins/soleur/skills/ship/SKILL.md"
  printf 'After the subagent returns, verify the scope: run `%s origin/main...HEAD` and confirm every listed path matches `^knowledge-base/project/(plans|specs)/`; exit 2/127 = scope unverified: treat as a breach and re-diff, never as in scope. Fallback `<base-sha>..HEAD`.\n' "$call" > "$1/plugins/soleur/skills/one-shot/SKILL.md"
  # The converted references and agents: the compliant fixture line of every REF_PINS row.
  local rrel rline
  while IFS=$'\t' read -r rrel _ _ rline; do
    [ -n "$rrel" ] || continue
    mkdir -p "$(dirname "$1/$rrel")" && printf '%s\n' "$rline" > "$1/$rrel" || return 1
  done <<<"$REF_PINS"
  printf '   %s origin/main...HEAD %s "$REVIEW_TMP/review-changed.txt" || { rc=$?; rm -f "$REVIEW_TMP/review-changed.txt"; echo "REVIEW-CLASSIFY-UNKNOWN: helper rc=$rc"; }\n' "$call" '>' > "$1/plugins/soleur/skills/review/SKILL.md"
}
skill_defect() { # <root> <sk> <python old> <python new>: apply ONE defect to the fixture (must apply exactly once)
  local target="$1/plugins/soleur/skills/$2/SKILL.md"
  case "$2" in */*) target="$1/$2" ;; esac   # a repo-relative path (a reference or an agent) instead of a skill name
  python3 -I - "$target" "$3" "$4" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    print("DEFECT NOT APPLIED: %d occurrences of %r" % (s.count(old), old)); sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(old, new.replace("\\n", "\n")))
PY
}
selftest_skill_tree() { # <name> <good|bad> <root>: skill_prose_pins on a synthetic tree; FAIL must move iff bad
  local name="$1" want="$2" root="$3" p0=$PASS f0=$FAIL o_root="$SKILL_ROOT" dp df
  SKILL_ROOT="$root"
  skill_prose_pins >/dev/null
  SKILL_ROOT="$o_root"
  dp=$((PASS - p0)); df=$((FAIL - f0)); PASS=$p0; FAIL=$f0
  if [ "$want" = bad ] && [ "$df" -lt 1 ]; then printf 'FATAL: self-test skill_prose_pins %s: a defective skills tree did not move the FAIL counter (pass+%s fail+%s); the pins are inert\n' "$name" "$dp" "$df" >&2; exit 1; fi
  if [ "$want" = good ] && { [ "$df" -ne 0 ] || [ "$dp" -lt 1 ]; }; then printf 'FATAL: self-test skill_prose_pins %s: the compliant synthetic tree did not pass cleanly (pass+%s fail+%s)\n' "$name" "$dp" "$df" >&2; exit 1; fi
  SELFTESTS=$((SELFTESTS + 1))
}
selftest_skill_pins() {
  local base="$WORK_ROOT/skill-selftest" t
  rm -rf -- "$base"; mkdir -p "$base" || { printf 'FATAL: cannot create %s\n' "$base" >&2; exit 1; }
  skill_fixture "$base/good" || { printf 'FATAL: cannot build the skill fixture\n' >&2; exit 1; }
  selftest_skill_tree "compliant tree" good "$base/good"
  # The spelling pin on its own: a bare helper name that DOES name the range (so only the spelling pin can object) must move its FAIL counter.
  local o_root="$SKILL_ROOT"
  t="$base/bad-bare-spelling-only"; mkdir -p "$t" && cp -a "$base/good/plugins" "$t/" || { printf 'FATAL: cannot copy the skill fixture\n' >&2; exit 1; }
  printf 'run changed-paths.sh origin/main...HEAD from the repo root\n' >> "$t/plugins/soleur/skills/review/SKILL.md"
  SKILL_ROOT="$t"
  selftest_moved "skill_spelling_pin rejects a bare helper name" fail skill_spelling_pin review
  SKILL_ROOT="$base/good"
  selftest_moved "skill_spelling_pin accepts the whole call form" pass skill_spelling_pin review
  SKILL_ROOT="$o_root"
  # name|skill|old|new  (the defect each pin exists to catch)
  local spec nm sk old new
  while IFS=$'\t' read -r nm sk old new; do
    [ -n "$nm" ] || continue
    t="$base/bad-$nm"; mkdir -p "$t" && cp -a "$base/good/plugins" "$t/" || { printf 'FATAL: cannot copy the skill fixture\n' >&2; exit 1; }
    skill_defect "$t" "$sk" "$old" "$new" || { printf 'FATAL: self-test defect %s did not apply\n' "$nm" >&2; exit 1; }
    selftest_skill_tree "$nm" bad "$t"
  done <<'DEFECTS'
a bare helper name on its own line	review	echo "REVIEW-CLASSIFY-UNKNOWN: helper rc=$rc"; }	echo "REVIEW-CLASSIFY-UNKNOWN: helper rc=$rc"; }\nsee changed-paths.sh for the details
the ship fail-closed handler dropped	ship	{ [ $? -eq 1 ] || dpf_match=unknown; }	{ dpf_match=unknown; }
a ship --match not on origin/main...HEAD	ship	--match "$DPF_REGEX" origin/main...HEAD)	--match "$DPF_REGEX" HEAD~1)
preflight PREFLIGHT-CACHE-MISSING dropped	preflight	echo "PREFLIGHT-CACHE-MISSING: helper failed"	echo "helper failed"
preflight cache rm -f dropped	preflight	{ rm -f "$PREFLIGHT_TMP/preflight-diff-files.txt"; echo	{ echo
preflight Check 6 cache-absent wording dropped	preflight	For Check 6 the cache file is absent, RUN.	For Check 6 the cache is simply read.
review REVIEW-CLASSIFY-UNKNOWN dropped	review	echo "REVIEW-CLASSIFY-UNKNOWN: helper rc=$rc"	echo "helper rc=$rc"
the ship ledger handler dropped (unknown would be read as touched)	ship	{ [ $? -eq 1 ] || ledger_touched=unknown; }	{ ledger_touched=unknown; }
the ship plan_refs match not on origin/main...HEAD	ship	--match '^knowledge-base/project/(plans|specs)/' origin/main...HEAD)	--match '^knowledge-base/project/(plans|specs)/' HEAD~1)
the ship ledger rule flipped so that unknown exempts the gate	ship	is not exactly `knowledge-base/operations/expenses.md` (`unknown` fires the gate)	is not empty (`unknown` exempts the gate)
the ship ledger match loses its escaped dot	ship	expenses\.md$' --diff-filter=AMT	expenses.md$' --diff-filter=AMT
the ship plan_refs unknown branch removed	ship	[[ $plan_refs == unknown ]] && echo	[[ -n $plan_refs ]] && echo
an uppercase LEDGER_TOUCHED handler (the renamed variable regrown)	ship	ledger_touched=$(bash	LEDGER_TOUCHED=$(bash
one-shot helper call garbled (bare name)	one-shot	scripts/changed-paths.sh" origin/main...HEAD`	scripts/changed-paths.shchanged-paths.sh" origin/main...HEAD`
one-shot helper call on a HEAD~1 range	one-shot	changed-paths.sh" origin/main...HEAD`	changed-paths.sh" HEAD~1`
one-shot scope-check breach arm dropped	one-shot	exit 2/127 = scope unverified: treat as a breach	exit 2/127 is ignored
a counsel-review capture without its unknown arm	plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md	|| { [ $? -eq 1 ] || legal_touch=unknown; }	|| true # unknown
a counsel-review capture whose unknown arm is hidden behind || true	plugins/soleur/skills/ship/references/counsel-review-clo-attestation.md	|| { [ $? -eq 1 ] || legal_touch=unknown; }	|| { [ $? -eq 1 ] || legal_touch=unknown; } || true
adr-ordinal-collision capture falling back to an empty list	plugins/soleur/skills/ship/references/adr-ordinal-collision.md	|| files=$(git ls-files)	|| true
a risk-tier capture without its unknown arm	plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md	|| files=unknown	|| true
a second helper call in a reference without the unknown arm	plugins/soleur/skills/review/references/risk-tier-and-fix-rounds.md	|| files=unknown	|| files=unknown\nmore=$(bash <plugin-root>/scripts/changed-paths.sh "$PANEL_SHA"..HEAD)
the :- root arm reintroduced in an agent body	plugins/soleur/agents/engineering/review/semgrep-sast.md	"${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh"	"${CLAUDE_PLUGIN_ROOT:-}/scripts/changed-paths.sh"
a semgrep-sast abort arm dropped	plugins/soleur/agents/engineering/review/semgrep-sast.md	If the helper exits 2 or 127 the file list is unknown: abort	If the helper fails, carry on
an observability-coverage-reviewer inventory-unknown arm dropped	plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md	exit 2/127 = inventory unknown	exit 2/127 is ignored
DEFECTS
}

# Synthetic CODE inputs for the scanner: one file per case under $sd/code, the scanner run in `code` mode against root=$sd. `want` is GREEN (one
# site, nothing unlisted) or RED (one site, exactly one unlisted). Bodies use \n escapes (printf %b).
synth_code() { # <label> <ext> <want GREEN|RED> <body with \n escapes> [number of sites, default 1]
  local label="$1" ext="$2" want="$3" body="$4" nsites="${5:-1}" f cdir="$WORK_ROOT/sent/code"
  assert_fixture_dir "$cdir"
  SYNTH_I=$((SYNTH_I + 1))
  f="$cdir/s$SYNTH_I.$ext"
  printf '%b\n' "$body" > "$f"
  sent_run "" "$WORK_ROOT/sent" code "$f"
  local sites unl
  sites="$(sent_n SITES)"; unl="$(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED' || true)"
  if [ "$SENT_RC" -eq 0 ] && [ "$sites" = "$nsites" ] && { { [ "$want" = GREEN ] && [ "$unl" = 0 ]; } || { [ "$want" = RED ] && [ "$unl" = 1 ]; }; }; then
    pass "sentinel code harness: $label is $want (one site)"
  else fail "sentinel code harness: $label want $want with $nsites site(s), got sites=$sites unlisted=$unl rc=$SENT_RC: $SENT_OUT"; fi
}

section_sentinel() {
  echo "── sentinel"
  # Harness rows against synthetic files (H1/H2): the comment-stripping step, the -c spelling, per-site entries, continuations.
  local sd="$WORK_ROOT/sent" SYNTH_I=0 l
  mkdir -p "$sd/code"
  # The census reports through census_report, so a one-violation input must move the FAIL counter exactly once and a clean one the PASS counter.
  local c_clean=$'SCANNED 1\nSITES 1\nEXEMPT 0\nAPISITES 0'
  selftest_moved "census_report accepts a clean scan" pass census_report selftest "$c_clean"
  selftest_moved "census_report rejects one unlisted site" fail census_report selftest "$c_clean"$'\nUNLISTED x.sh:3 :: git diff --name-only'
  selftest_moved "census_report rejects one stale entry" fail census_report selftest "$c_clean"$'\nSTALE x.sh :: a reader that was deleted'
  cat > "$sd/a.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          # git diff --name-only | grep -E '^x'
          echo done
YML
  sent_run "" "$sd" wf "$sd/a.yml"
  if [ "$(sent_n SITES)" = 0 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel H1: a comment line naming the phrase stays GREEN"; else fail "sentinel H1: comment line was scanned: $SENT_OUT"; fi
  cat > "$sd/b.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          echo "git diff --name-only | grep '^x'"
YML
  sent_run "" "$sd" wf "$sd/b.yml"
  if grep -q '^UNLISTED .*b\.yml:5' <<<"$SENT_OUT"; then pass "sentinel H1: the same text inside a run: string literal is RED, with file:line"; else fail "sentinel H1: run: literal not flagged: $SENT_OUT"; fi
  cat > "$sd/c.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          X=$(git -c core.quotePath=false diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
YML
  sent_run "" "$sd" wf "$sd/c.yml"
  if [ "$(sent_n SITES)" = 1 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel H2: a -c core.quotePath=false diff -z site passes"; else fail "sentinel H2: -z site flagged: $SENT_OUT"; fi
  cat > "$sd/d.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          A=$(git diff --name-only a...b)
          B=$(git diff --name-only a...b)
YML
  sent_run "d.yml	git diff --name-only a...b	only the first" "$sd" wf "$sd/d.yml"
  if [ "$(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED')" = 1 ]; then pass "sentinel: two sites in one file, one exemption row: the second is RED (entries are per site)"; else fail "sentinel: per-site accounting broke: $SENT_OUT"; fi
  sent_run "d.yml	git diff --name-only a...b	one
d.yml	git diff --name-only a...b	two
d.yml	a reader that was deleted	stale" "$sd" wf "$sd/d.yml"
  if grep -q '^STALE d.yml :: a reader that was deleted' <<<"$SENT_OUT" && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel: an entry that matches no site is STALE"; else fail "sentinel: stale accounting broke: $SENT_OUT"; fi
  # Rows are keyed on the REPO-RELATIVE path: a row for another directory's d.yml does not exempt this one (and is itself stale).
  sent_run "other/d.yml	git diff --name-only a...b	a row for another directory" "$sd" wf "$sd/d.yml"
  if [ "$(printf '%s\n' "$SENT_OUT" | grep -c '^UNLISTED')" = 2 ] && grep -q '^STALE other/d.yml' <<<"$SENT_OUT"; then pass "sentinel: an exemption row keyed on another path neither exempts a same-named file nor survives as non-stale"; else fail "sentinel: path keying broke: $SENT_OUT"; fi
  cat > "$sd/e.yml" <<'YML'
jobs:
  j:
    steps:
      - run: |
          X=$(git diff \
            --name-only "origin/${B}...HEAD" \
            | grep -E '^x')
YML
  sent_run "" "$sd" wf "$sd/e.yml"
  if grep -q '^UNLISTED .*e\.yml:5' <<<"$SENT_OUT"; then pass "sentinel: a backslash-continued reader is joined and caught"; else fail "sentinel: continuation not joined: $SENT_OUT"; fi

  # The spellings a narrow pattern let through. Each UNCONVERTED spelling is exactly one site and RED; each converted twin is one site and GREEN.
  local sp_i=0 sp_label sp_body
  while IFS='~' read -r sp_label sp_body; do
    [ -n "$sp_label" ] || continue
    sp_i=$((sp_i + 1))
    printf 'jobs:\n  j:\n    steps:\n      - run: |\n          %s\n' "$sp_body" > "$sd/sp$sp_i.yml"
    sent_run "" "$sd" wf "$sd/sp$sp_i.yml"
    if [ "$(sent_n SITES)" = 1 ] && grep -q "^UNLISTED .*sp$sp_i\\.yml:5" <<<"$SENT_OUT"; then pass "sentinel spelling: $sp_label is a RED site"
    else fail "sentinel spelling: $sp_label was not flagged as one unlisted site: $SENT_OUT"; fi
  done <<'SPELLINGS'
git -C "$d" diff~X=$(git -C "$d" diff --name-only a...b)
git --no-pager diff~X=$(git --no-pager diff --name-only a...b)
git diff with a nested $(...) in the range~X=$(git diff "$(git merge-base a b)"...HEAD --name-only)
a trailing comment naming -z~X=$(git diff --name-only a...b # was -z )
git --no-optional-locks~X=$(git --no-optional-locks diff --name-only a...b)
git --literal-pathspecs~X=$(git --literal-pathspecs diff --name-only a...b)
git --git-dir "$X" (space form)~X=$(git --git-dir "$GD" diff --name-only a...b)
git --git-dir=X --work-tree=Y~X=$(git --git-dir="$GD" --work-tree="$WT" diff --name-only a...b)
git -C"$d" (no space)~X=$(git -C"$d" diff --name-only a...b)
a $GIT launcher~X=$($GIT diff --name-only a...b)
a "${GIT[@]}" launcher~X=$("${GIT[@]}" diff --name-only a...b)
a quoted verb~X=$(git "diff" --name-only a...b)
a 2>&1 before the flag (single & is not a segment cut)~X=$(git diff a...b 2>&1 --name-only)
a bundled -zs is not a standalone -z~X=$(git diff --name-only -zs a...b)
git log with --name-only~X=$(git log --format= --name-only a..b)
a -z after && belongs to another command~X=$(git diff --name-only a...b) && echo -z
a -z after || belongs to another command~X=$(git diff --name-only a...b) || echo -z
a -z after ; belongs to another command~X=$(git diff --name-only a...b); echo -z
git diff-tree with --name-status~X=$(git diff-tree --no-commit-id --name-status -r HEAD)
-z alone is not enough (no --ignore-submodules=none)~X=$(git diff -z --name-only a...b | tr '\0' '\n')
-z and --no-renames without --ignore-submodules=none~X=$(git diff -z --no-renames --name-only a...b | tr '\0' '\n')
--ignore-submodules=none without -z or --no-renames~X=$(git diff --ignore-submodules=none --name-only a...b)
a swallowed failure (|| true) after a converted reader~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n' || true)
a swallowed failure (|| echo "") after a converted reader~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b 2>/dev/null || echo "")
a gh pr diff reader (no NUL output exists)~X=$(gh pr diff 5 --name-only)
SPELLINGS
  local sc_i=0 sc_label sc_body
  while IFS='~' read -r sc_label sc_body; do
    [ -n "$sc_label" ] || continue
    sc_i=$((sc_i + 1))
    printf 'jobs:\n  j:\n    steps:\n      - run: |\n          %s\n' "$sc_body" > "$sd/sc$sc_i.yml"
    sent_run "" "$sd" wf "$sd/sc$sc_i.yml"
    if [ "$(sent_n SITES)" = 1 ] && ! grep -q '^UNLISTED' <<<"$SENT_OUT"; then pass "sentinel control: the converted twin of $sc_label is GREEN (one site)"
    else fail "sentinel control: the converted twin of $sc_label was flagged or not counted: $SENT_OUT"; fi
  done <<'CONTROLS'
git -C "$d" diff~X=$(git -C "$d" diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git --no-pager diff~X=$(git --no-pager diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git diff with a nested $(...) in the range~X=$(git diff -z --no-renames --ignore-submodules=none "$(git merge-base a b)"...HEAD --name-only | tr '\0' '\n')
a trailing comment~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n') # note
git --no-optional-locks~X=$(git --no-optional-locks diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git --literal-pathspecs~X=$(git --literal-pathspecs diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git --git-dir "$X" (space form)~X=$(git --git-dir "$GD" diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git --git-dir=X --work-tree=Y~X=$(git --git-dir="$GD" --work-tree="$WT" diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
git -C"$d" (no space)~X=$(git -C"$d" diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
a $GIT launcher~X=$($GIT diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
a "${GIT[@]}" launcher~X=$("${GIT[@]}" diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
a quoted verb~X=$(git "diff" -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n')
a 2>&1 before the flag~X=$(git diff -z --no-renames --ignore-submodules=none a...b 2>&1 --name-only | tr '\0' '\n')
a standalone -z next to a bundled-looking word~X=$(git diff --name-only -z --no-renames --ignore-submodules=none a...b | tr '\0' '\n')
git log with --name-only~X=$(git log -z --no-renames --ignore-submodules=none --format= --name-only a..b | tr '\0' '\n')
a -z before && stays in the segment~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b) && echo done
a -z before || stays in the segment~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b) || echo done
a -z before ; stays in the segment~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b); echo done
git diff-tree with --name-status~X=$(git diff-tree -z --no-renames --ignore-submodules=none --no-commit-id --name-status -r HEAD | tr '\0' '\n')
--no-renames and --ignore-submodules=none without -z (the line form)~X=$(git diff --no-renames --ignore-submodules=none --name-only a...b)
a failure handled with || exit is not swallowed~X=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b | tr '\0' '\n') || exit 2
CONTROLS

  # CODE harness (the code census): shell, Python and ts call forms, comment stripping per physical line, the API readers.
  synth_code "a pathspec emptiness reader (allowlist-diff shape)" sh GREEN 'cfg="$(git -C "$R" diff --no-renames --ignore-submodules=none --name-only "$B..$H" -- ":(top,literal).gitleaks.toml")" || exit 2'
  synth_code "git log -z ... | tr" sh GREEN 'X=$(git log -z --no-renames --ignore-submodules=none --name-only --format= a..b | tr "\\0" "\\n")'
  synth_code "a mid-continuation backtick comment must not eat the flags after it" sh GREEN 'git log -z \\\n  --no-renames `# MUT:x` \\\n  --ignore-submodules=none --name-status a..b > f'
  synth_code "-z only in a trailing comment of an unconverted reader" sh RED 'X=$(git diff --name-only a...b) # -z --no-renames --ignore-submodules=none'
  synth_code "a plain reader after a compliant one in the same file" sh RED 'A=$(git diff -z --no-renames --ignore-submodules=none --name-only a...b)\nfi\nB=$(git diff --name-only c...d)' 2
  synth_code "Python git_out([diff, -z, --no-renames, --ignore-submodules=none, --name-only])" py GREEN 'out = git_out(["diff", "-z", "--no-renames", "--ignore-submodules=none", "--name-only", base])'
  synth_code "Python _git([diff, --name-only]) plain" py RED 'out = _git(["diff", "--name-only", base])'
  synth_code "Python argv spanning lines is joined and judged by ALL its tokens" py GREEN 'p = run(\n    ["git", "diff", "-z", "--no-renames",\n     "--ignore-submodules=none", "--name-only"],\n    cwd=root)'
  synth_code "Python -z only in a trailing comment" py RED 'out = _git(["diff", "--name-only", base])  # "-z", "--no-renames", "--ignore-submodules=none"'
  synth_code "Python argv with -z but no --ignore-submodules=none" py RED 'out = _git_z(["diff", "-z", "--name-only", base])'
  synth_code "ts Bun.spawnSync argv across lines" ts GREEN 'const p = Bun.spawnSync(\n  [\n    "git",\n    "diff",\n    "-z",\n    "--no-renames",\n    "--ignore-submodules=none",\n    "--name-only",\n  ],\n  { cwd },\n);'
  synth_code "ts plain argv with the flags only in a // comment" ts RED 'const p = Bun.spawnSync(["git", "diff", "--name-only"], { cwd }); // -z --no-renames --ignore-submodules=none'
  synth_code "ts plain argv with the flags only in a block comment" ts RED '/* "-z", "--no-renames", "--ignore-submodules=none" */\nconst p = Bun.spawnSync(["git", "diff", "--name-only"], { cwd });'
  # API readers: the emitting form `(.previous_filename // empty)` is required (a bare token is stub-satisfiable), also across a continuation line.
  synth_code "a files-API reader emitting previous_filename on a continuation line" sh GREEN 'out=$(gh api "repos/o/r/pulls/$n/files" --paginate --jq ".[] | .filename, \\\n  (.previous_filename // empty)")'
  synth_code "a files-API reader with .filename only" sh RED 'out=$(gh api "repos/o/r/pulls/$n/files" --paginate --jq ".[].filename")'
  synth_code "a files-API reader with a bare previous_filename token (not the emitting form)" sh RED 'out=$(gh api "repos/o/r/pulls/$n/files" --jq ".[] | .filename, .previous_filename")'
  synth_code "a compare-API reader with .filename only" sh RED 'out=$(gh api "repos/o/r/compare/$a...$b" --jq ".files[].filename")'
  # An exemption row for one path must not exempt the same text in another file (the code table is keyed on the repo-relative path).
  printf 'X=$(git diff --name-only a...b)\n' > "$sd/code/keyed.sh"
  sent_run "code/keyed.sh	git diff --name-only a...b	a row keyed on this exact relative path" "$sd" code "$sd/code/keyed.sh"
  if [ "$(sent_n EXEMPT)" = 1 ] && ! grep -q '^UNLISTED\|^STALE' <<<"$SENT_OUT"; then pass "sentinel code harness: a row keyed on the repo-relative path exempts exactly that file's site"; else fail "sentinel code harness: the keyed row did not exempt: $SENT_OUT"; fi

  # The live scan over the TRACKED workflows.
  local -a wf=() cf=() pf=() cf_all=()
  local f
  mapfile -t wf < <(git -C "$REPO_ROOT" ls-files '.github/workflows/*.yml' | sed "s|^|$REPO_ROOT/|")
  exempt_rows_check "workflow" "$EXEMPT_TABLE"
  census_scan "workflow" "$EXEMPT_TABLE" wf "$SENT_FILE_FLOOR" "$SENT_SITE_FLOOR" "${wf[@]}"
  # The live code census: tracked non-test *.sh *.py *.ts *.mjs under the code roots.
  mapfile -t cf_all < <(git -C "$REPO_ROOT" ls-files -- "${CODE_ROOTS[@]}" | grep -E '\.(sh|py|ts|mjs)$' | grep -vE '(\.test\.|\.spec\.|/test/|/tests/)' | sed "s|^|$REPO_ROOT/|")
  cf=("${cf_all[@]}")
  exempt_rows_check "code" "$EXEMPT_CODE_TABLE"
  census_scan "code" "$EXEMPT_CODE_TABLE" code "$CODE_FILE_FLOOR" "$CODE_SITE_FLOOR" "${cf[@]}"
  # The bounded prose census: the closed list of skills, references and agents whose instructions run a gate.
  for f in "${PROSE_FILES[@]}"; do pf+=("$REPO_ROOT/$f"); done
  exempt_rows_check "prose" "$EXEMPT_PROSE"
  census_scan "prose" "$EXEMPT_PROSE" prose "$PROSE_FILE_FLOOR" "$PROSE_SITE_FLOOR" "${pf[@]}"
  # The pinned must-keep-`-z` list.
  selftest_pinned
  selftest_skill_pins
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
# A single section (helper | steps | sentinel) is a developer aid; the floors below bind the FULL run that CI executes, and each is a
# literal bound adjacent to its test so the meta-guard (scripts/guard-vacuity-floor.test.sh) can construct a mutant for it.
total=$((PASS + FAIL))
if [ "$SECTION" != all ]; then
  # A section that executed nothing (its call deleted from the dispatch above, a glob gone stale) must not exit 0 as a "developer aid" run.
  case "$SECTION" in
    helper) [ "$HELPER_ROWS" -gt 0 ] || { printf '[FATAL] the helper section ran zero rows\n' >&2; exit 1; } ;;
    steps) [ "$STEP_ROWS" -gt 0 ] || { printf '[FATAL] the steps section executed zero steps\n' >&2; exit 1; } ;;
    sentinel) [ "$CENSUS_ROWS" -gt 0 ] || { printf '[FATAL] the sentinel section censused zero sites\n' >&2; exit 1; } ;;
  esac
  echo
  echo "helper rows: $HELPER_ROWS, executed steps: $STEP_ROWS"
  echo "Guard ($SECTION only, floors not applied): $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
  exit
fi
MIN_HELPER_ROWS=109
if [ "$HELPER_ROWS" -lt "$MIN_HELPER_ROWS" ]; then
  printf '[FATAL] helper floor: only %s helper rows ran, want >=%s\n' "$HELPER_ROWS" "$MIN_HELPER_ROWS" >&2
  exit 1
fi
MIN_STEP_ROWS=131
if [ "$STEP_ROWS" -lt "$MIN_STEP_ROWS" ]; then
  printf '[FATAL] steps floor: only %s step executions ran, want >=%s\n' "$STEP_ROWS" "$MIN_STEP_ROWS" >&2
  exit 1
fi
# Census sites examined across the workflow, code and prose censuses (exact: a removed reader must lower this floor in the same diff).
MIN_CENSUS_ROWS=139
if [ "$CENSUS_ROWS" -lt "$MIN_CENSUS_ROWS" ]; then
  printf '[FATAL] census floor: only %s reader sites were censused, want >=%s\n' "$CENSUS_ROWS" "$MIN_CENSUS_ROWS" >&2
  exit 1
fi
# Exact current total (the floor is the full count, not a margin below it): helper 109 + steps 180 + sentinel 119.
MIN_TOTAL=408
if [ "$total" -lt "$MIN_TOTAL" ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, want >=%s\n' "$total" "$MIN_TOTAL" >&2
  exit 1
fi
# Every positive control must have run (an inert verdict helper is caught inside selftest_moved; a skipped self-test is caught here).
if [ "$SELFTESTS" -ne 68 ]; then printf '[FATAL] self-test count: ran %s verdict-helper self-tests, want 68\n' "$SELFTESTS" >&2; exit 1; fi
echo
echo "helper rows: $HELPER_ROWS, executed steps: $STEP_ROWS"
echo "Guard: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
