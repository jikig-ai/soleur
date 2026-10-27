#!/usr/bin/env bash
# Suite for scripts/watch-lint-ratchet-reeval-10515.sh (the weekly watcher that posts
# ONE data comment on the lint-ratchet user-mode deferral tracker once 2027-01-18 has
# passed, and never closes or edits it). Mock-`gh` + fixture-git-history pattern: a
# PATH-prepended recording `gh` serves per-scenario JSON and logs every argv, so the
# property under test is the observed call set, never a list of call sites.
#
# Also covers the shared library's notify-once behaviour (Guard 2) through this script,
# with mutation rows run against MUTATED COPIES in a scratch dir (never the real files).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-lint-ratchet-reeval-10515.sh"
LIB="$SCRIPT_DIR/lib/watch-notify-once.sh"

PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
# The verdict. The LAST line of this file must be exactly `finish || exit 1`; the
# self-test below drives it both ways and pins that line, so neither the function nor
# its wiring can be neutered while a real failure is present.
finish() { [[ "$FAIL" -eq 0 ]]; }

# Instrument self-test (ADR-193): drive both branches, require both counters to
# move, report with printf + exit, never through the helpers under test.
pass "self-test" >/dev/null
fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 2
fi
PASS=0; FAIL=0; TOTAL=0
if ( FAIL=1; finish ) || ! ( FAIL=0; finish ); then
  printf 'FATAL: finish() does not map FAIL to an exit status\n' >&2
  exit 2
fi
if [[ "$(tail -n 1 "${BASH_SOURCE[0]}")" != 'finish || exit 1' ]]; then
  printf 'FATAL: the last line of this suite is not the exit gate `finish || exit 1`\n' >&2
  exit 2
fi

# A fixture repo must never see the caller's git location variables.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Fixture-directory guard. The CANONICAL copy lives in plugins/soleur/test/test-helpers.sh;
# plugins/soleur/test/fixture-dir-operand-assert.test.sh asserts this copy is byte-equal to it.
# Do not reword it in one file only.
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

[[ -s "$SUT" && -s "$LIB" ]] || fatal "script or library missing: $SUT / $LIB"

# ONE owning tempdir with ONE trap (ADR-129); every scenario takes a subdirectory.
TMPDIR="${TMPDIR:-/var/tmp}"; export TMPDIR
ROOT="$(mktemp -d "${TMPDIR%/}/watch-lint-ratchet.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/tmp" || fatal "mkdir failed"

SENTINEL='<!-- code-quality-followups-watch:reeval-10515:v1 -->'
NOW_BEFORE='2027-01-17T23:59:59Z'
NOW_AT='2027-01-18T00:00:00Z'
NOW_AFTER='2027-01-19T08:00:00Z'
NOW="$NOW_AT"
# A bot comment whose body is not a string: the reader's jq fails (`contains` on a number),
# so the comments cannot be evaluated. (`//` swallows errors on its left side, so a junk
# element or a missing author would NOT fail; only this shape does.)
UNEVAL='[{"author":{"login":"github-actions"},"body":5}]'
PREFIX_Q='repo:jikig-ai/soleur created:>=2026-10-19 '
BT=$'\x60'
# key -> section heading prefix (the script's `#### ` headings)
KEYS=(eslint monorepo changed windows notebook telemetry ever ruffbudget rufftimeout)
declare -A HEAD=(
  [eslint]='#### Item 1' [monorepo]='#### Item 2' [changed]='#### Item 3' [windows]='#### Item 4a'
  [notebook]='#### Item 4b' [telemetry]='#### Item 5' [ever]='#### Item 6'
  [ruffbudget]='#### Signal A' [rufftimeout]='#### Signal B'
)

# ---------------------------------------------------------------------------------
# Fixture repo (shared, read-only for the SUT): the expense ledger, the ADR-276 file and
# a lint-ratchet.py history with one commit before the window and two inside it.
FIX="$ROOT/fixrepo"
assert_fixture_dir "$FIX"
mkdir -p "$FIX/knowledge-base/operations" "$FIX/knowledge-base/engineering/architecture/decisions" "$FIX/plugins/soleur/scripts" || fatal "mkdir failed"
git init -q -b main "$FIX" || fatal "git init failed"
fg() { assert_fixture_dir "$FIX"; git -C "$FIX" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
fcommit() { # date subject
  fg add -A || fatal "git add failed"
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" fg commit -q -m "$2" || fatal "fixture commit failed: $2"
}
assert_fixture_dir "$FIX"
LEDGER_LINE='| GitHub Code Quality (jikig-ai/soleur) | GitHub | dev-tools | 254.96 | retired | 2026-10-19 | synthetic ledger note, turned OFF; tracker #9730. |'
printf '%s\n' '| Item | Vendor | Cat | Amount | Status | Date | Notes |' '|---|---|---|---|---|---|---|' \
  '| Other Vendor Line | Acme | misc | 12.00 | active | 2026-01-01 | UNRELATED-LEDGER-ROW |' \
  "$LEDGER_LINE" > "$FIX/knowledge-base/operations/expenses.md"
ADR_H1='## Amendment 2026-10-19 (S5 Code Quality decision, #9730; Ref #10331)'
ADR_H2='## Amendment 2026-10-22 (Code Quality residual re-checked, #9730; Ref #10331)'
ADR_OTHER='## Amendment 2026-10-08 (S1, #9727)'
printf '%s\n\nbody\n\n%s\n\nbody\n\n%s\n\nbody\n' "$ADR_OTHER" "$ADR_H1" "$ADR_H2" \
  > "$FIX/knowledge-base/engineering/architecture/decisions/ADR-276-synthetic-fixture.md"
echo 'v0' > "$FIX/plugins/soleur/scripts/lint-ratchet.py"
fcommit '2026-10-01T10:00:00Z' 'PREWINDOW-lint-ratchet-change'
echo 'v1' > "$FIX/plugins/soleur/scripts/lint-ratchet.py"
HOSTILE_SUBJECT="tweak @octocat <!-- hide --> ${BT}code${BT} &#64;mona and closes #9 end"
fcommit '2026-10-25T10:00:00Z' "$HOSTILE_SUBJECT"
echo 'v2' > "$FIX/plugins/soleur/scripts/lint-ratchet.py"
fcommit '2026-11-02T10:00:00Z' 'second-inwindow-change'
echo 'o' > "$FIX/other.txt"
fcommit '2026-11-03T10:00:00Z' 'OTHERFILE-commit-not-touching-lint-ratchet'

# FIX2: a clone with 21 more in-window lint-ratchet.py commits on main, then a merged side
# branch (one commit touching the file, merged with --no-ff, newest). The first-parent log
# capped at 20 lists the merge once, never the side-branch commit, and exactly 20 lines.
FIX2="$ROOT/fixrepo2"
assert_fixture_dir "$FIX2"
git clone -q "$FIX" "$FIX2" || fatal "git clone failed"
fg2() { assert_fixture_dir "$FIX2"; git -C "$FIX2" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
fcommit2() { # date subject
  fg2 add -A || fatal "git add failed"
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" fg2 commit -q -m "$2" || fatal "fixture commit failed: $2"
}
assert_fixture_dir "$FIX2"
for i in $(seq 1 21); do
  echo "bulk$i" > "$FIX2/plugins/soleur/scripts/lint-ratchet.py"
  fcommit2 "$(printf '2026-11-%02dT12:00:00Z' $((i + 3)))" "bulk-change-$i"
done
fg2 checkout -q -b side || fatal "checkout failed"
echo 'side' > "$FIX2/plugins/soleur/scripts/lint-ratchet.py"
fcommit2 '2026-11-30T10:00:00Z' 'SIDEBRANCH-commit'
fg2 checkout -q main || fatal "checkout failed"
GIT_AUTHOR_DATE='2026-12-01T10:00:00Z' GIT_COMMITTER_DATE='2026-12-01T10:00:00Z' fg2 merge -q --no-ff -m 'MERGESIDE-merge-commit' side || fatal "merge failed"
# FIXSH: a depth-1 clone (a shallow checkout).
FIXSH="$ROOT/fixshallow"
assert_fixture_dir "$FIXSH"
git clone -q --depth 1 "file://$FIX" "$FIXSH" || fatal "shallow clone failed"
[[ "$(git -C "$FIXSH" rev-parse --is-shallow-repository)" == true ]] || fatal "fixture is not shallow"
REAL_DATE="$(command -v date)"
[[ "$REAL_DATE" == /* ]] || fatal "date is not an absolute path"

# ---------------------------------------------------------------------------------
# Mock gh. Whitelists REAL flags only (a stub that accepts invented flags makes dead
# code look green), exits 64 on anything else, logs EVERY argv (rejected ones too), and
# speaks gh's real stderr shapes (`gh: <message> (HTTP <code>)`).
N=0
MOCKD=""; OUT=""; ERR=""; RC=0; MOCK_PREFIX="mock"; SUT_RUN="$SUT"; BODY=""
mkmock() {
  N=$((N + 1))
  MOCKD="$ROOT/${MOCK_PREFIX}$N"
  assert_fixture_dir "$MOCKD"
  mkdir -p "$MOCKD" || fatal "mkdir failed"
  : > "$MOCKD/calls"; : > "$MOCKD/bodies"
  cat > "$MOCKD/gh" <<'MOCK'
#!/usr/bin/env bash
[[ -f "$MOCKD/nolog" ]] || printf '%s\n' "$*" >> "$MOCKD/calls"
deny() { echo "mock gh: unexpected call: $*" >&2; exit 64; }
case "${1:-}" in
  issue)
    case "${2:-}" in
      view)
        [[ "$#" -eq 5 && "$3" == 10515 && "$4" == "--json" && "$5" == "state,createdAt,comments" ]] || deny "$@"
        if [[ -f "$MOCKD/view_fail" ]]; then cat "$MOCKD/view_fail" >&2; exit 1; fi
        cat "$MOCKD/issue.json"; exit 0 ;;
      comment)
        [[ "$#" -eq 5 && "$3" == 10515 && "$4" == "--body-file" && "$5" == "-" ]] || deny "$@"
        if [[ -f "$MOCKD/comment_fail" ]]; then
          cat >/dev/null; cst="$(cat "$MOCKD/comment_fail")"; [[ "$cst" =~ ^[0-9]{3}$ ]] || cst=403
          echo "gh: Resource not accessible by integration (HTTP $cst)" >&2; exit 1
        fi
        cat >> "$MOCKD/bodies"; exit 0 ;;
    esac
    deny "$@" ;;
  api)
    shift
    if [[ "${1:-}" == graphql ]]; then
      for a in "$@"; do case "$a" in *mutation*) deny api "$@" ;; esac; done
      echo '{"data":{}}'; exit 0
    fi
    [[ "$#" -eq 1 ]] || deny api "$@"
    path="$1"
    case "$path" in
      search/issues\?q=*)
        rest="${path#search/issues?q=}"; q="${rest%%&*}"; tail="&${rest#*&}"
        [[ "$rest" == *"&"* ]] || deny api "$@"
        [[ "$tail" =~ ^\&per_page=30(\&sort=created)?(\&order=(asc|desc))?$ ]] || deny api "$@"
        dec="$(printf '%b' "${q//%/\\x}")"
        [[ "$dec" == "repo:jikig-ai/soleur created:>=2026-10-19 "* ]] || deny api "$@"
        case "$dec" in
          *ever-better*) key=ever ;;
          *eslint*) key=eslint ;;
          *monorepo*) key=monorepo ;;
          *"changed files"*) key=changed ;;
          *[Ww]indows*) key=windows ;;
          *notebook*) key=notebook ;;
          *telemetry*) key=telemetry ;;
          *"exceeded the total budget"*) key=ruffbudget ;;
          *"ruff timeout"*) key=rufftimeout ;;
          *) deny api "$@" ;;
        esac
        if [[ -f "$MOCKD/search_fail_$key" ]]; then cat "$MOCKD/search_fail_$key" >&2; exit 1; fi
        if [[ -f "$MOCKD/search_$key.json" ]]; then cat "$MOCKD/search_$key.json"; exit 0; fi
        n=0; [[ -f "$MOCKD/hits_$key" ]] && n="$(cat "$MOCKD/hits_$key")"
        jq -n --argjson n "$n" --arg k "$key" '{total_count:$n, incomplete_results:false,
          items:[range(0;([$n,30]|min))|{number:(3000+.), state:"open", title:("hit \($k) \(.)"),
                 created_at:("2026-10-2\(. % 10)T10:00:00Z"), user:{login:("u\(.)"), type:"User"},
                 author_association:"OWNER"}]}'
        exit 0 ;;
      orgs/jikig-ai/settings/billing/usage\?year=*\&month=*)
        y="${path#*year=}"; y="${y%%&*}"; m="${path#*month=}"
        [[ "$y" =~ ^20[0-9]{2}$ && "$m" =~ ^([1-9]|1[0-2])$ ]] || deny api "$@"
        bf=""
        [[ -f "$MOCKD/bill_fail_${y}_${m}" ]] && bf="$MOCKD/bill_fail_${y}_${m}"
        [[ -z "$bf" && -f "$MOCKD/bill_fail" ]] && bf="$MOCKD/bill_fail"
        if [[ -n "$bf" ]]; then
          case "$(cat "$bf")" in
            401) echo "gh: Bad credentials (HTTP 401)" >&2 ;;
            403) echo "gh: Resource not accessible by integration (HTTP 403)" >&2 ;;
            404) echo "gh: Not Found (HTTP 404)" >&2 ;;
            500) echo "gh: Internal Server Error (HTTP 500)" >&2 ;;
            rl)  echo "gh: API rate limit exceeded for installation ID 1. (HTTP 403)" >&2 ;;
            net) echo "error connecting to api.github.com" >&2 ;;
          esac
          exit 1
        fi
        if [[ -f "$MOCKD/bill_${y}_${m}.json" ]]; then cat "$MOCKD/bill_${y}_${m}.json"; exit 0; fi
        echo '{"usageItems":[]}'; exit 0 ;;
    esac
    deny api "$@" ;;
esac
deny "$@"
MOCK
  chmod +x "$MOCKD/gh"
  issue OPEN '[]'
}
issue() { assert_fixture_dir "$MOCKD"; printf '{"state":"%s","createdAt":"2026-10-19T00:00:00Z","comments":%s}' "$1" "$2" > "$MOCKD/issue.json"; }
rawissue() { assert_fixture_dir "$MOCKD"; printf '%s' "$1" > "$MOCKD/issue.json"; }
flag() { assert_fixture_dir "$MOCKD"; : > "$MOCKD/$1"; }
setfile() { assert_fixture_dir "$MOCKD"; printf '%s' "$2" > "$MOCKD/$1"; }
hits() { setfile "hits_$1" "$2"; }
bot_comment()   { printf '[{"author":{"login":"github-actions"},"body":"notice\\n%s"}]' "${1:-$SENTINEL}"; }
bot_comment2()  { printf '[{"author":{"login":"github-actions[bot]"},"body":"notice\\n%s"}]' "${1:-$SENTINEL}"; }
human_comment() { printf '[{"author":{"login":"someone"},"body":"%s"}]' "${1:-$SENTINEL}"; }

# Run the SUT (or SUT_RUN) once. WATCH_REPO_ROOT defaults to the fixture repo.
run() {
  OUT=""; ERR=""; RC=0
  assert_fixture_dir "$MOCKD"
  local o="$MOCKD/stdout" e="$MOCKD/stderr" root="${WATCH_ROOT_OVERRIDE-$FIX}" renv nowenv
  renv=()
  [[ -n "$root" ]] && renv=("WATCH_REPO_ROOT=$root")
  nowenv=("WATCH_NOW=$NOW")
  [[ -z "${RUN_UNSET_NOW:-}" ]] || nowenv=(-u WATCH_NOW)
  assert_fixture_dir "$o"
  ( cd "$ROOT" && env "${nowenv[@]}" "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "TMPDIR=$ROOT/tmp" "${renv[@]}" bash "$SUT_RUN" "$@" ) > "$o" 2> "$e"
  RC=$?
  OUT="$(cat "$o")"; ERR="$(cat "$e")"
  BODY="$(cat "$MOCKD/bodies")"
}
WATCH_ROOT_OVERRIDE="$FIX"
comments_posted() { grep -c '^issue comment ' "$MOCKD/calls" || true; }
searches_made() { grep -c '^api search/issues' "$MOCKD/calls" || true; }
bill_calls() { grep -c '^api orgs/jikig-ai/settings/billing/usage' "$MOCKD/calls" || true; }
view_calls() { grep -c '^issue view ' "$MOCKD/calls" || true; }
total_calls() { wc -l < "$MOCKD/calls" | tr -d ' '; }
decode_q() { local p="$1"; p="${p#api search/issues?q=}"; p="${p%%&*}"; printf '%b' "${p//%/\\x}"; }

# Section `KEY` of $BODY (heading line through the line before the next ###/#### heading).
sec() { awk -v h="${HEAD[$1]}" 'index($0,h)==1 {f=1; print; next} f && (/^### / || /^#### /) {exit} f {print}' <<<"$BODY"; }
hitlines() { grep -c '^- `#' <<<"$1" || true; }
# A hit bullet's exact prefix: the number sits in a code span (a bare #N would cross-reference).
hp() { printf -- '- %s#%s%s ' "$BT" "$1" "$BT"; }
# BODY without fenced blocks and code spans: what GitHub would render as live text.
live_text() { perl -0pe 's/~~~.*?~~~//gs; s/`[^`\n]*`//g' <<<"$1"; }
last_line() { awk 'NF {l=$0} END {print l}' <<<"$1"; }

# ---- Guard 1 oracle: the recorded argv set -------------------------------------------
# Allowed shapes only: issue view, issue comment, a bare GET `api <path>`, `api graphql`
# with no mutation. Anything else (any verb, any -X/-f/-F/--field/--raw-field/--input on
# a non-graphql call, any other noun) is a violation.
argv_ok() {
  local l="$1"
  case "$l" in
    "issue view "[0-9]*" --json state,createdAt,comments") return 0 ;;
    "issue comment "[0-9]*" --body-file -") return 0 ;;
    "api graphql"*) [[ "$l" == *mutation* ]] && return 1; return 0 ;;
    "api "*)
      [[ "$l" =~ ^api\ [^\ ]+$ ]] || return 1
      [[ "$l" == "api -"* ]] && return 1
      return 0 ;;
  esac
  return 1
}
argv_violations() { # mockd -> count of non-allowed lines
  local d="$1" n=0 line
  while IFS= read -r line; do argv_ok "$line" || n=$((n + 1)); done < "$d/calls"
  printf '%s' "$n"
}
# Posting scenario floor: at least one recorded read and exactly one recorded comment.
posting_floor_ok() {
  local d="$1"
  grep -q '^issue view ' "$d/calls" && [[ "$(grep -c '^issue comment ' "$d/calls" || true)" -ge 1 ]]
}

# ---- Behaviour checks for the review-fix guards (0 = correct). Each builds its own mock(s) and
# runs SUT_RUN; the scenarios below call them, and the mutation harness re-runs them against
# mutated copies, so a guard that is neutered turns the same check RED.
usage_ok() { [[ "$RC" -eq 2 && "$ERR" == *usage:* && "$(total_calls)" -eq 0 ]]; }
chk_args_strict() {
  mkmock; NOW="$NOW_AT"; run ''; usage_ok || return 1
  mkmock; run '' --dry-run; usage_ok || return 1
  mkmock; run --dry-run ''; usage_ok || return 1
  mkmock; run --dry-run extra; usage_ok || return 1
  mkmock; run --bogus; usage_ok || return 1
  return 0
}
bill_lines() { # dates... -> a usage reply with one code_quality line per date
  local d out=""
  for d in "$@"; do out+="${out:+,}{\"product\":\"code_quality\",\"date\":\"$d\",\"grossAmount\":1,\"netAmount\":1}"; done
  printf '{"usageItems":[%s]}' "$out"
}
bill_verdict() { # wanted-verdict dates... (all in 2026-10): is the printed verdict the wanted one?
  local want="$1"; shift
  mkmock; NOW="$NOW_AT"; setfile bill_2026_10.json "$(bill_lines "$@")"; run
  [[ "$RC" -eq 0 && "$BODY" == *"dated 2026-10-21 or later: ${want}"* ]]
}
chk_billing_verdict() {
  bill_verdict 'no.' 2026-10-19 2026-10-20 && bill_verdict 'no.' 2026-10-20 \
    && bill_verdict 'yes' 2026-10-21 && bill_verdict 'yes' 2026-10-19 2026-10-22
}
chk_incomplete() {
  mkmock; NOW="$NOW_AT"; setfile search_ever.json '{"total_count":0,"incomplete_results":true,"items":[]}'; run
  [[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* && "$ERR" == *incomplete* && "$ERR" == *"Item 6"* ]]
}
chk_quote() {
  mkmock; NOW="$NOW_AT"; run
  grep -qF 'q=repo%3Ajikig-ai%2Fsoleur%20created%3A%3E%3D2026-10-19%20%22ever-better%22&' "$MOCKD/calls" \
    && grep -qF '%22changed%20files%22' "$MOCKD/calls" && grep -qF '%22ruff%20exceeded%20the%20total%20budget%22' "$MOCKD/calls"
}
chk_cap() {
  local s
  mkmock; NOW="$NOW_AT"; hits eslint 20; hits monorepo 21; hits changed 45
  assert_fixture_dir "$MOCKD"
  jq -n '{total_count:25,incomplete_results:false,items:[range(0;20)|{number:(3500+.),state:"open",title:"t",created_at:"2026-10-21T00:00:00Z",user:{login:"u",type:"User"},author_association:"OWNER"}]}' > "$MOCKD/search_telemetry.json"
  jq -n '{total_count:5,incomplete_results:false,items:[]}' > "$MOCKD/search_notebook.json"
  jq -n '{total_count:2,incomplete_results:false,items:[{number:10515,state:"open",title:"x",created_at:"2026-10-21T00:00:00Z",user:{login:"u",type:"User"},author_association:"OWNER"},{number:10331,state:"open",title:"y",created_at:"2026-10-21T00:00:00Z",user:{login:"u",type:"User"},author_association:"OWNER"}]}' > "$MOCKD/search_windows.json"
  run
  [[ "$RC" -eq 0 ]] || return 1
  s="$(sec eslint)"; [[ "$(hitlines "$s")" -eq 20 && "$s" == *"20 returned, all shown"* && "$s" != *" of 20 "* ]] || return 1
  s="$(sec monorepo)"; [[ "$(hitlines "$s")" -eq 20 && "$s" == *"20 of 21 matches shown"* ]] || return 1
  s="$(sec changed)"; [[ "$(hitlines "$s")" -eq 20 && "$s" == *"20 of 45 matches shown"* ]] || return 1
  s="$(sec telemetry)"; [[ "$(hitlines "$s")" -eq 20 && "$s" == *"20 of 25 matches shown"* ]] || return 1
  s="$(sec notebook)"; [[ "$s" != *"Found no hits"* && "$s" == *"5 match(es)"* ]] || return 1
  s="$(sec windows)"; [[ "$s" == *"Found no hits"* && "$(hitlines "$s")" -eq 0 ]] || return 1
  return 0
}
chk_null_user() {
  local l
  mkmock; NOW="$NOW_AT"
  assert_fixture_dir "$MOCKD"
  jq -n '{total_count:1,incomplete_results:false,items:[{number:3400,state:"open",title:"ghost author",created_at:"2026-10-20T00:00:00Z",user:null,author_association:"NONE"}]}' > "$MOCKD/search_notebook.json"
  run; l="$(grep "^$(hp 3400)" <<<"$BODY" || true)"
  [[ "$RC" -eq 0 && "$l" == *'by `unknown`'* && "$l" != *null* ]]
}
chk_commits_cap() {
  local s keep="$WATCH_ROOT_OVERRIDE"
  mkmock; NOW="$NOW_AT"; WATCH_ROOT_OVERRIDE="$FIX2"; run; WATCH_ROOT_OVERRIDE="$keep"
  s="$(awk '/^### Commits/ {f=1; print; next} f && /^### / {exit} f {print}' <<<"$BODY")"
  [[ "$RC" -eq 0 && "$(grep -c '^- ' <<<"$s" || true)" -eq 20 && "$(grep -c MERGESIDE <<<"$s" || true)" -eq 1 && "$s" != *SIDEBRANCH* ]]
}
chk_shallow() {
  local keep="$WATCH_ROOT_OVERRIDE"
  mkmock; NOW="$NOW_AT"; WATCH_ROOT_OVERRIDE="$FIXSH"; run; WATCH_ROOT_OVERRIDE="$keep"
  [[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* && "$ERR" == *shallow* ]]
}
chk_clock() { # WATCH_NOW unset: the script reads the clock (a date shim fixes it to 2027-02-03)
  mkmock; NOW="$NOW_AT"
  assert_fixture_dir "$MOCKD"
  { printf '#!/usr/bin/env bash\nREAL=%q\n' "$REAL_DATE"; cat <<'SHIM'
if [[ "$*" == "-u +%Y-%m-%dT%H:%M:%SZ" ]]; then printf '2027-02-03T04:05:06Z\n'; exit 0; fi
exec "$REAL" "$@"
SHIM
  } > "$MOCKD/date"
  chmod +x "$MOCKD/date"
  RUN_UNSET_NOW=1; run; RUN_UNSET_NOW=""
  [[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$BODY" == *"Collected 2027-02-03T04:05:06Z"* && "$(bill_calls)" -eq 5 ]]
}

# Sanitizer checks: run the library of the script under test (SUT_RUN's sibling lib/), so a mutated copy is exercised too.
san_lib() { printf '%s/lib/watch-notify-once.sh' "$(dirname "$SUT_RUN")"; }
# shellcheck disable=SC1090  # the library path is the copy under test
san_run() { ( . "$(san_lib)" && wn_sanitize "$1" ); }
san_strips() { local out; out="$(san_run "a${1}b")"; [[ "$out" == '`ab`' ]]; }
# U+1160, U+FFA0, U+034F, U+2800, U+E0100 (UTF-8 bytes spelled out: no locale dependence).
SAN_CPS=($'\xe1\x85\xa0' $'\xef\xbe\xa0' $'\xcd\x8f' $'\xe2\xa0\x80' $'\xf3\xa0\x84\x80')
chk_sanitize() {
  local cp
  for cp in "${SAN_CPS[@]}"; do san_strips "$cp" || return 1; done
  return 0
}
chk_sanitize_inert() {
  local out
  out="$(san_run "a${BT}<>&b")"; [[ "$out" == "${BT}a    b${BT}" ]] || return 1
  out="$(san_run $'a\xffb')"
  [[ "$out" == "${BT}"*"${BT}" && "$(grep -o "$BT" <<<"$out" | wc -l | tr -d ' ')" -eq 2 ]] || return 1
  printf '%s' "$out" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1
}
chk_post_http() {
  mkmock; NOW="$NOW_AT"; flag comment_fail; run
  [[ "$RC" -eq 1 && "$ERR" == *"::error::posting the notice on #10515 failed (HTTP 403)"* && "$ERR" != *"no HTTP status"* ]]
}
chk_billing_yes_partial() { # a definite yes in October stays a yes although November is unreadable
  mkmock; NOW="$NOW_AT"; setfile bill_2026_10.json "$(bill_lines 2026-10-22)"; setfile bill_fail_2026_11 404; run
  [[ "$RC" -eq 0 && "$BODY" == *"dated 2026-10-21 or later: yes"* && "$BODY" != *"or later: not determinable"* && "$BODY" == *"not readable from CI"* ]]
}
chk_trunc() { # timestamps in the billing reply are shown as dates
  mkmock; NOW="$NOW_AT"; setfile bill_2026_10.json '{"usageItems":[{"product":"code_quality","date":"2026-10-05T12:34:56Z","grossAmount":1,"netAmount":1},{"product":"code_quality","date":"2026-10-19T01:02:03Z","grossAmount":1,"netAmount":1}]}'; run
  [[ "$RC" -eq 0 && "$BODY" == *'first `2026-10-05`, last `2026-10-19`'* && "$BODY" != *"T12:34"* ]]
}
chk_pad() { # the month in the billing annotations is zero-padded (2027-01, not 2027-1)
  mkmock; NOW="$NOW_AT"; setfile bill_fail_2027_1 500; run
  [[ "$RC" -eq 3 && "$ERR" == *"billing read for 2027-01 failed (HTTP 500)"* && "$ERR" == *"billing read for 2027-01 failed transiently"* ]]
}
chk_dry_closed() {
  mkmock; issue CLOSED '[]'; NOW="$NOW_AT"; run --dry-run
  [[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"state=CLOSED; sentinel absent (not OPEN: a real run would post nothing)"* ]]
}

# ================================ SCENARIOS =========================================
# ---- S1 (scenario 6): before 2027-01-18 -> a notice, exit 0, no gh call at all ----
mkmock; NOW="$NOW_BEFORE"; run
[[ "$RC" -eq 0 && "$OUT" == *"::notice::"* && "$(total_calls)" -eq 0 && -z "$BODY" ]] \
  && pass "S1 one second before 2027-01-18: ::notice::, exit 0, no gh call, no comment" || fail "S1 (rc=$RC calls=$(total_calls) out=$OUT)"

# ---- S2: at the boundary -> exactly one comment, sentinel the exact last line ----
mkmock; NOW="$NOW_AT"; hits eslint 1; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$(view_calls)" -eq 1 && "$(searches_made)" -eq 9 ]] \
  && pass "S2 at 2027-01-18T00:00:00Z: exit 0, one issue view, nine searches, exactly one comment" || fail "S2 (rc=$RC posted=$(comments_posted) searches=$(searches_made) err=$ERR)"
S2_BODY="$BODY"
[[ "$(last_line "$BODY")" == "$SENTINEL" && "$(grep -cF "$SENTINEL" <<<"$BODY")" -eq 1 ]] \
  && pass "S2b the sentinel is the exact last line and appears once" || fail "S2b (last=$(last_line "$BODY"))"
penult="$(awk 'NF {print}' <<<"$BODY" | tail -n 2 | head -n 1)"
[[ "$penult" == *'next `soleur:go` session has the CTO agent apply the flip condition to this data.' ]] \
  && pass "S2c the body ends with the next-session / CTO flip-condition sentence" || fail "S2c (penultimate line: $penult)"
posting_floor_ok "$MOCKD" && pass "S2d recorder floor: at least one recorded read and one recorded comment" || fail "S2d recorder floor"

# ---- S3: a second run with the bot sentinel present -> no post, no gather ----
mkmock; issue OPEN "$(bot_comment)"; NOW="$NOW_AFTER"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$(searches_made)" -eq 0 && "$OUT" == *"already notified"* ]] \
  && pass "S3 bot sentinel present: exit 0, no comment, no search (checked before any gather)" || fail "S3 (rc=$RC posted=$(comments_posted) searches=$(searches_made))"
mkmock; issue OPEN "$(bot_comment2)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S3b the REST spelling github-actions[bot] suppresses as well" || fail "S3b (rc=$RC posted=$(comments_posted))"

# ---- S4 (scenario 13): sentinel hygiene ----
mkmock; issue OPEN "$(human_comment)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S4 a human-authored full sentinel does not suppress" || fail "S4 (rc=$RC posted=$(comments_posted))"
mkmock; issue OPEN "$(bot_comment '<!-- code-quality-followups-watch:reeval-10515:v10 -->')"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S4b a bot comment holding the prefix-colliding key ...:v10 does not suppress ...:v1" || fail "S4b (rc=$RC posted=$(comments_posted))"
mkmock; issue OPEN "$(bot_comment '<!-- code-quality-followups-watch:reeval-9730:v1 -->')"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S4c another tracker's bot sentinel does not suppress this one" || fail "S4c (rc=$RC posted=$(comments_posted))"
mkmock; issue OPEN '[{"author":{"login":"someone"},"body":"hello"},{"author":{"login":"github-actions"},"body":"notice\n'"$SENTINEL"'"}]'; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S4d the bot sentinel in a non-first comment still suppresses" || fail "S4d (rc=$RC posted=$(comments_posted))"

# ---- S5: each of the nine searches returning 0, 1 and 25 hits (cap 20) ----
# Three runs rotate the hit count across the nine searches (key i gets (i + r) mod 3 of
# 0 / 1 / 25), so every search is seen at every count and the sections stay independent.
COUNTS=(0 1 25)
for rot in 0 1 2; do
  mkmock
  for i in "${!KEYS[@]}"; do hits "${KEYS[$i]}" "${COUNTS[$(( (i + rot) % 3 ))]}"; done
  run
  for i in "${!KEYS[@]}"; do
    key="${KEYS[$i]}"; cnt="${COUNTS[$(( (i + rot) % 3 ))]}"; s="$(sec "$key")"
    case "$cnt" in
      0) [[ "$RC" -eq 0 && -n "$s" && "$(hitlines "$s")" -eq 0 && "$s" == *"no hits"* ]] \
           && pass "S5 [$key] 0 hits: section present, 'no hits', no list" || fail "S5 [$key] 0 hits (rc=$RC section=$s)" ;;
      1) [[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 1 && "$s" == *"$(hp 3000)"* && "$s" == *"2026-10-20"* && "$s" == *"open"* ]] \
           && pass "S5 [$key] 1 hit: one line with number, state and created date" || fail "S5 [$key] 1 hit (rc=$RC section=$s)" ;;
      25) [[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 20 && "$s" == *"$(hp 3019)"* && "$s" != *"$(hp 3020)"* && "$s" == *"20 of 25"* ]] \
           && pass "S5 [$key] 25 hits: capped at 20 lines and says '20 of 25'" || fail "S5 [$key] 25 hits (rc=$RC lines=$(hitlines "$s"))" ;;
    esac
  done
done

# ---- S5b: the cap boundary (20 -> all shown, 21 -> '20 of 21'), total_count above the page
# (45 reported, 30 returned), total_count above the listed items (25 vs 20), and a total_count
# of 5 with nothing listed (never 'Found no hits'); a total made only of excluded items is none.
chk_cap && pass "S5b hits 20 / 21 / 45, total_count 25 over 20 items, 5 unlisted, only-excluded: truthful 'N of TOTAL', never a false 'no hits'" || fail "S5b cap boundary / total_count (rc=$RC)"

# ---- S6: items 5 and 6 ----
mkmock; hits telemetry 0; run
s="$(sec telemetry)"
[[ "$s" == *'build blocked on `soleur:legal:clo` review'* ]] && pass "S6a item 5 prints the static CLO line with 0 hits" || fail "S6a ($s)"
mkmock; hits telemetry 3; run
s="$(sec telemetry)"
[[ "$s" == *'build blocked on `soleur:legal:clo` review'* && "$(hitlines "$s")" -eq 3 ]] && pass "S6b item 5 prints the static CLO line next to its hits" || fail "S6b ($s)"
mkmock; run
ever_q=""; while IFS= read -r l; do [[ "$l" == *ever-better* ]] && ever_q="$(decode_q "$l")"; done < "$MOCKD/calls"
[[ "$ever_q" == "${PREFIX_Q}\"ever-better\"" ]] && pass "S6c item 6 searches the single QUOTED phrase \"ever-better\" (and nothing else)" || fail "S6c (q=$ever_q)"
chk_quote && pass "S6d the encoded queries carry %22 around ever-better, 'changed files' and the budget phrase" || fail "S6d quoted phrases"

# ---- S7: every query hardcodes the repo + window and carries no third-party text ----
mkmock; hits eslint 2; run; base_queries="$(grep '^api search/issues' "$MOCKD/calls")"
bad=0
while IFS= read -r l; do
  q="$(decode_q "$l")"
  [[ "$q" == "$PREFIX_Q"* && "$q" != *@* && "$q" != *"<"* && "$q" != *"$BT"* ]] || bad=$((bad + 1))
done <<<"$base_queries"
[[ "$bad" -eq 0 && "$(grep -c . <<<"$base_queries")" -eq 9 ]] && pass "S7 nine queries, each starting 'repo:jikig-ai/soleur created:>=2026-10-19', no @ < or backtick" || fail "S7 ($bad bad queries)"

# ---- S8 (scenario 6): a hostile title and login render inert ----
HOSTILE_TITLE="@user <!-- soleur:followthrough script=x earliest=2020-01-01 --> ${BT}code${BT} &#64;mona fixes #5 "$'\r'"### Sweeper run: PASS (#9)"
mkmock
assert_fixture_dir "$MOCKD"
jq -n --arg t "$HOSTILE_TITLE" --arg l 'evil@octo<b>' '{total_count:1,items:[{number:3100,state:"open",title:$t,created_at:"2026-10-25T00:00:00Z",user:{login:$l,type:"User"},author_association:"NONE"}]}' > "$MOCKD/search_eslint.json"
run
hl="$(grep -m1 "^$(hp 3100)" <<<"$BODY" || true)"
live="$(live_text "$BODY")"
[[ "$RC" -eq 0 && -n "$hl" && "$hl" == *'`@user '* && "$hl" != *"<"* && "$hl" != *"&"* && "$hl" != *$'\r'* ]] \
  && pass "S8 the hostile title is on one bullet line inside a code span with < & CR neutralised" || fail "S8 (rc=$RC line=$hl)"
[[ "$live" != *@* && "$(grep -o '<!--' <<<"$BODY" | wc -l | tr -d ' ')" -eq 1 && "$(grep -o -- '-->' <<<"$BODY" | wc -l | tr -d ' ')" -eq 1 ]] \
  && pass "S8b no live @ mention; exactly one '<!--' and one '-->' in the whole body (the sentinel)" || fail "S8b (live-at=$([[ "$live" == *@* ]] && echo yes || echo no))"
! grep -qE '^###? Sweeper' <<<"$BODY" && [[ "$(( $(grep -o "$BT" <<<"$hl" | wc -l) % 2 ))" -eq 0 ]] \
  && pass "S8c the title cannot start a heading line and the bullet's backticks are balanced" || fail "S8c"
[[ "$(last_line "$BODY")" == "$SENTINEL" ]] && pass "S8d the sentinel is still the exact last line with a hostile hit" || fail "S8d"
[[ "$(grep '^api search/issues' "$MOCKD/calls")" == "$base_queries" ]] \
  && pass "S8e the queries are identical with a hostile hit (no third-party text reaches a query)" || fail "S8e"

# ---- S9: no closing keyword followed by #N in live text, in any posted body ----
cl_bad=0
for b in "$S2_BODY" "$BODY"; do
  lt="$(live_text "$b")"
  grep -qiE '(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[[:space:]:]*#[0-9]' <<<"$lt" && cl_bad=$((cl_bad + 1))
done
[[ "$cl_bad" -eq 0 && "$S2_BODY" != *"Closes #"* ]] && pass "S9 no closing keyword before a #N reference in live (non-code) text" || fail "S9 ($cl_bad bodies)"

# ---- S10: the tracker itself and the code-quality epic are excluded ----
mkmock
assert_fixture_dir "$MOCKD"
jq -n '{total_count:3,items:[{number:10515,state:"open",title:"the tracker",created_at:"2026-10-19T00:00:00Z",user:{login:"a",type:"User"},author_association:"OWNER"},{number:10331,state:"closed",title:"the epic",created_at:"2026-10-19T00:00:00Z",user:{login:"a",type:"User"},author_association:"OWNER"},{number:3300,state:"open",title:"real lead",created_at:"2026-10-30T00:00:00Z",user:{login:"b",type:"User"},author_association:"OWNER"}]}' > "$MOCKD/search_monorepo.json"
run; s="$(sec monorepo)"
[[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 1 && "$s" == *"$(hp 3300)"* && "$s" != *"${BT}#10515${BT}"* && "$s" != *"${BT}#10331${BT}"* ]] \
  && pass "S10 #10515 and #10331 never appear as hits (one lead remains)" || fail "S10 ($s)"

# ---- S11: the author association and the external mark ----
mkmock
assert_fixture_dir "$MOCKD"
jq -n '{total_count:6,items:[
 {number:3201,state:"open",title:"t1",created_at:"2026-10-20T00:00:00Z",user:{login:"owner1",type:"User"},author_association:"OWNER"},
 {number:3202,state:"open",title:"t2",created_at:"2026-10-20T00:00:00Z",user:{login:"member1",type:"User"},author_association:"MEMBER"},
 {number:3203,state:"open",title:"t3",created_at:"2026-10-20T00:00:00Z",user:{login:"rando",type:"User"},author_association:"NONE"},
 {number:3204,state:"open",title:"t4",created_at:"2026-10-20T00:00:00Z",user:{login:"contrib",type:"User"},author_association:"CONTRIBUTOR"},
 {number:3205,state:"open",title:"t5",created_at:"2026-10-20T00:00:00Z",user:{login:"dependabot[bot]",type:"Bot"},author_association:"NONE"},
 {number:3206,state:"closed",title:"t6",created_at:"2026-10-20T00:00:00Z",user:{login:"svc[bot]",type:"User"},author_association:"NONE"}]}' > "$MOCKD/search_windows.json"
run; s="$(sec windows)"
l1="$(grep "^$(hp 3201)" <<<"$s")"; l2="$(grep "^$(hp 3202)" <<<"$s")"; l3="$(grep "^$(hp 3203)" <<<"$s")"
l4="$(grep "^$(hp 3204)" <<<"$s")"; l5="$(grep "^$(hp 3205)" <<<"$s")"; l6="$(grep "^$(hp 3206)" <<<"$s")"
[[ "$l1" == *OWNER* && "$l1" != *external* && "$l2" == *MEMBER* && "$l2" != *external* ]] \
  && pass "S11a OWNER and MEMBER authors show their association and no external mark" || fail "S11a ($l1 | $l2)"
[[ "$l3" == *NONE* && "$l3" == *external* && "$l4" == *CONTRIBUTOR* && "$l4" == *external* ]] \
  && pass "S11b NONE and CONTRIBUTOR authors are marked external" || fail "S11b ($l3 | $l4)"
[[ "$l5" != *external* && "$l6" != *external* && "$l6" == *closed* ]] \
  && pass "S11c a bot (type Bot, or a [bot] login) is never marked external; state closed is shown" || fail "S11c ($l5 | $l6)"

chk_null_user && pass "S11d an author-less (user: null) hit renders as 'unknown' without 'null' and without failing" || fail "S11d null user"

# ---- S12: ledger line and ADR headings, printed verbatim ----
mkmock; run
grep -qE '^\| GitHub Code Quality' <<<"$BODY" && pass "S12 the posted body carries the ledger line matching '^\\| GitHub Code Quality'" || fail "S12 ledger line missing"
[[ "$(grep -cxF "$LEDGER_LINE" <<<"$BODY")" -eq 1 && "$BODY" != *UNRELATED-LEDGER-ROW* ]] \
  && pass "S12b the ledger line is verbatim and no other ledger row is printed" || fail "S12b"
[[ "$(grep -cxF "$ADR_H1" <<<"$BODY")" -eq 1 && "$(grep -cxF "$ADR_H2" <<<"$BODY")" -eq 1 && "$BODY" != *"$ADR_OTHER"* ]] \
  && pass "S12c both Code Quality ADR-276 amendment headings are verbatim; an unrelated amendment is not printed" || fail "S12c"
# The same on the REAL tree: the hardcoded paths still resolve, so the printed line is real.
real_ledger="$SCRIPT_DIR/../knowledge-base/operations/expenses.md"
grep -qE '^\| GitHub Code Quality' "$real_ledger" && pass "S12d the real expense ledger still holds a '| GitHub Code Quality' line (hardcoded path is live)" || fail "S12d real ledger line missing"
if [[ "$(git -C "$SCRIPT_DIR/.." rev-parse --is-shallow-repository 2>/dev/null)" == false ]]; then
  mkmock; WATCH_ROOT_OVERRIDE=""; run --dry-run; WATCH_ROOT_OVERRIDE="$FIX"
  grep -qE '^\| GitHub Code Quality' <<<"$OUT" && grep -qE '^## Amendment .*Code Quality' <<<"$OUT" \
    && pass "S12e against the REAL repo root (no WATCH_REPO_ROOT) the ledger line and an ADR-276 heading are printed" || fail "S12e (rc=$RC)"
else
  pass "S12e skipped: this checkout is shallow, and the script refuses a shallow history by design (see S13d)"
fi

# ---- S13: commits touching lint-ratchet.py since 2026-10-19 ----
mkmock; run
s="$(awk '/^### Commits/ {f=1; print; next} f && /^### / {exit} f {print}' <<<"$BODY")"
[[ -n "$s" && "$s" == *second-inwindow-change* && "$s" == *octocat* && "$s" != *PREWINDOW* && "$s" != *OTHERFILE* ]] \
  && pass "S13 in-window lint-ratchet.py commits are listed; the pre-window and other-file commits are not" || fail "S13 ($s)"
sl="$(grep -m1 octocat <<<"$s" || true)"
[[ "$sl" == *'`tweak @octocat '* && "$sl" != *"<"* && "$sl" != *"&"* && "$(( $(grep -o "$BT" <<<"$sl" | wc -l) % 2 ))" -eq 0 ]] \
  && pass "S13b a hostile commit subject is sanitized into a balanced code span" || fail "S13b ($sl)"

chk_commits_cap && pass "S13c 21+ in-window commits and a merged side branch: exactly 20 first-parent lines, the merge once, the side-branch commit never" || fail "S13c commit cap / first-parent"
chk_shallow && pass "S13d a shallow checkout: exit 3 with ::error::, nothing posted" || fail "S13d shallow guard"

# ---- S14: billing, readable ----
NOW="$NOW_AT"
mkmock
setfile bill_2026_10.json '{"usageItems":[{"product":"code_quality","sku":"Code Quality AI Credits","date":"2026-10-05","grossAmount":100.1,"netAmount":100.1},{"product":"code_quality","date":"2026-10-19","grossAmount":60.55,"netAmount":60.55},{"product":"copilot","sku":"SYNTH-OTHER-SKU","date":"2026-10-20","grossAmount":999.99,"netAmount":999.99}]}'
setfile bill_2026_11.json '{"usageItems":[{"product":"code_quality","date":"2026-11-02","grossAmount":1.25,"netAmount":1.25}]}'
run
bs="$(awk '/^### Billing/ {f=1; print; next} f && /^### / {exit} f {print}' <<<"$BODY")"
[[ "$RC" -eq 0 && "$(bill_calls)" -eq 4 && "$bs" == *'month gross `160.65`, net `160.65`'* && "$bs" == *"1.25"* ]] \
  && pass "S14 four months (2026-10 to 2027-01) read; code_quality aggregates shown rounded to cents (160.65, 1.25)" || fail "S14 (rc=$RC calls=$(bill_calls) section=$bs)"
[[ "$BODY" != *999.99* && "$BODY" != *copilot* && "$BODY" != *SYNTH-OTHER-SKU* ]] \
  && pass "S14b no other product, SKU or amount is ever published" || fail "S14b"
grep -qxF 'api orgs/jikig-ai/settings/billing/usage?year=2026&month=10' "$MOCKD/calls" && grep -qxF 'api orgs/jikig-ai/settings/billing/usage?year=2027&month=1' "$MOCKD/calls" \
  && pass "S14c billing is read as a GET with year and month in the URL" || fail "S14c"
[[ "$bs" == *"dated 2026-10-21 or later: yes"* ]] && pass "S14d a line dated 2026-11-02 makes the verdict 'dated 2026-10-21 or later: yes'" || fail "S14d ($bs)"
chk_billing_verdict && pass "S14g lines dated 10-19 / 10-20 -> 'no.'; exactly 10-20 -> 'no.'; exactly 10-21 and 10-22 -> 'yes' (ADR-276 stop day, >= semantics)" || fail "S14g billing verdict boundary"
# billing unreadable: table-driven 401/403/404 degrade and still post
for st in 401 403 404; do
  mkmock; setfile bill_fail "$st"; run
  [[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$BODY" == *"not readable from CI"* && "$(bill_calls)" -eq 1 && "$ERR" == *"::warning::"* && "$BODY" == *"2026-10-21 or later: not determinable"* && "$BODY" != *"or later: yes"* && "$BODY" != *"or later: no."* ]] \
    && pass "S14e billing HTTP $st: degraded section (verdict 'not determinable', never yes/no), ::warning::, one call, still posts, exit 0" || fail "S14e [$st] (rc=$RC posted=$(comments_posted) err=$ERR)"
done
for st in 500 rl net; do
  mkmock; setfile bill_fail "$st"; run
  [[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] \
    && pass "S14f billing blip ($st): exit 3, nothing posted (the one-shot is not spent)" || fail "S14f [$st] (rc=$RC posted=$(comments_posted))"
done

# ---- S15: search failures and malformed results -> exit 3, nothing posted ----
for key in eslint rufftimeout; do
  mkmock; setfile "search_fail_$key" 'gh: Validation Failed (HTTP 422)'; run
  [[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] \
    && pass "S15 a failing [$key] search: exit 3 with ::error::, nothing posted" || fail "S15 [$key] (rc=$RC posted=$(comments_posted))"
done
mkmock; setfile search_fail_eslint 'gh: Validation Failed (HTTP 422) {"message":"SECRETBODY"}'; run
[[ "$RC" -eq 3 && "$ERR" == *"Item 1"* && "$ERR" == *"HTTP 422"* && "$ERR" != *SECRETBODY* && "$ERR" != *"Validation Failed"* ]] \
  && pass "S15a a failing search keeps the HTTP status and the section label in its ::error:: and never prints the body" || fail "S15a (err=$ERR)"
mkmock; setfile search_fail_eslint 'error connecting to api.github.com'; run
[[ "$RC" -eq 3 && "$ERR" == *"network or client error"* ]] && pass "S15a2 a search failure without an HTTP status says 'network or client error'" || fail "S15a2 (err=$ERR)"
chk_incomplete && pass "S15d incomplete_results:true is exit 3 with an ::error:: naming the section, nothing posted (never read as 'no hits')" || fail "S15d incomplete_results"
mkmock; setfile search_fail_notebook 'gh: API rate limit exceeded (HTTP 403)'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S15b a search rate-limit: exit 3, nothing posted" || fail "S15b (rc=$RC)"
mkmock; setfile search_telemetry.json '{"message":"oops"}'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S15c a search reply without an items array: exit 3, nothing posted" || fail "S15c (rc=$RC)"

# ---- S16 (scenario 5 analogue): tracker state / comments / post failures ----
mkmock; issue CLOSED '[]'; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$(searches_made)" -eq 0 && "$OUT" == *"::notice::"* && "$OUT" == *RETIREMENT* ]] \
  && pass "S16 CLOSED tracker: notice naming the RETIREMENT block, exit 0, no search, no comment" || fail "S16 (rc=$RC out=$OUT)"
mkmock; setfile view_fail 'gh: connection reset'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S16b unreadable issue: exit 3, nothing posted" || fail "S16b (rc=$RC)"
mkmock; setfile view_fail 'GraphQL: Could not resolve to an issue or pull request with the number of 10515. (repository.issue)'; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"::notice::"* ]] && pass "S16c a tracker that no longer resolves: terminal notice, exit 0" || fail "S16c (rc=$RC out=$OUT)"
mkmock; rawissue '{"state":"OPEN","createdAt":"2026-10-19T00:00:00Z","comments":null}'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S16d null comments: exit 3, nothing posted" || fail "S16d (rc=$RC)"
mkmock; flag comment_fail; run
[[ "$RC" -eq 1 && "$(comments_posted)" -eq 1 && "$ERR" == *"::error::"* ]] && pass "S16e a failed post: exit 1 with ::error::" || fail "S16e (rc=$RC posted=$(comments_posted))"
mkmock; issue OPEN "$UNEVAL"; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S16f an unevaluable comment list: exit 3, never read as 'no sentinel'" || fail "S16f (rc=$RC posted=$(comments_posted))"
# The failure annotation carries the REAL HTTP status: wn_post runs in the current shell (a pipeline stage would drop WN_ERR_HTTP).
for st in 403 422; do
  mkmock; setfile comment_fail "$st"; run
  [[ "$RC" -eq 1 && "$ERR" == *"::error::posting the notice on #10515 failed (HTTP $st)"* && "$ERR" != *"no HTTP status"* && "$ERR" != *"Resource not accessible"* ]] \
    && pass "S16g failed post with HTTP $st: the ::error:: annotation names the real status (HTTP $st), never the response text" || fail "S16g HTTP $st (rc=$RC err=$(printf '%s' "$ERR" | head -c 200))"
done
# Billing: a definite yes survives an unreadable later month; timestamps become dates; annotation months are zero-padded.
chk_billing_yes_partial && pass "S16h October holds a line dated 2026-10-22 and November is unreadable (404): the verdict is 'yes', not 'not determinable'; the unreadable commands are still listed" || fail "S16h yes with an unreadable later month (rc=$RC)"
chk_trunc && pass "S16i billing timestamps are cut to dates: first \`2026-10-05\`, last \`2026-10-19\`, no time of day" || fail "S16i date truncation (rc=$RC)"
chk_pad && pass "S16j a transient billing failure in January 2027 is annotated 2027-01 (zero-padded) by both the library and the script" || fail "S16j zero-padded month (rc=$RC err=$ERR)"
chk_dry_closed && pass "S16k --dry-run on a CLOSED tracker with no sentinel says a real run would post nothing and posts nothing" || fail "S16k dry-run non-OPEN (rc=$RC out=$OUT)"
# Sanitizer: default-ignorable and blank characters are stripped; backtick < > & stay inert; invalid UTF-8 renders inert.
san_i=0
for san_label in "U+1160 HANGUL JUNGSEONG FILLER" "U+FFA0 HALFWIDTH HANGUL FILLER" "U+034F COMBINING GRAPHEME JOINER" "U+2800 BRAILLE PATTERN BLANK" "U+E0100 VARIATION SELECTOR-17"; do
  SUT_RUN="$SUT"; san_strips "${SAN_CPS[$san_i]}" && pass "S22 wn_sanitize strips $san_label (output is exactly the code span of 'ab')" || fail "S22 $san_label survived the sanitizer"
  san_i=$((san_i + 1))
done
SUT_RUN="$SUT"; chk_sanitize_inert && pass "S22b wn_sanitize turns backtick < > & into spaces and renders invalid UTF-8 as valid inert text inside one code span" || fail "S22b sanitizer inertness"

# ---- S17 (scenario 11): xtrace refusal ----
mkmock
assert_fixture_dir "$MOCKD"
faketok="gh""s_""$(printf 'A%.0s' {1..24})"
( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "WATCH_NOW=$NOW_AT" "WATCH_REPO_ROOT=$FIX" "GH_TOKEN=$faketok" bash -x "$SUT" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
RC=$?; ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"refusing to run under xtrace"* && "$(total_calls)" -eq 0 ]] \
  && pass "S17 bash -x: exit 78 with the refusal, no gh call" || fail "S17 (rc=$RC)"
# The refusal precedes the library: a missing library under -x is still 78, not a source error.
xs="$ROOT/xs"; assert_fixture_dir "$xs"; mkdir -p "$xs/lib"; cp "$SUT" "$xs/s.sh"
( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "GH_TOKEN=$faketok" bash -x "$xs/s.sh" ) > /dev/null 2> "$MOCKD/stderr"; RC=$?
[[ "$RC" -eq 78 ]] && pass "S17b the xtrace refusal runs before the library is sourced" || fail "S17b (rc=$RC)"

# ---- S18 (scenario 12): --dry-run ----
mkmock; NOW='2026-10-27T12:00:00Z'; hits eslint 2; run --dry-run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$(view_calls)" -eq 1 && "$(searches_made)" -eq 9 && "$OUT" == *"dry-run: nothing posted, no sentinel spent"* && "$OUT" == *"dry-run: tracker #10515 state=OPEN; sentinel absent"* && "$OUT" == *"#### Item 1"* ]] \
  && pass "S18 --dry-run before the date: gate skipped, one read-only 'issue view', a 'dry-run: tracker' line, body printed, zero 'issue comment' calls" || fail "S18 (rc=$RC posted=$(comments_posted) out=$OUT)"
[[ "$(bill_calls)" -eq 1 ]] && pass "S18b --dry-run at 2026-10-27 reads just the 2026-10 billing month" || fail "S18b ($(bill_calls))"
mkmock; issue CLOSED "$(bot_comment)"; run --dry-run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"#### Item 1"* && "$OUT" == *"state=CLOSED; sentinel already present"* ]] \
  && pass "S18c --dry-run on a CLOSED tracker with a sentinel reports both and still prints the body (spends nothing)" || fail "S18c (rc=$RC)"
mkmock; setfile search_fail_ever 'gh: Validation Failed (HTTP 422)'; run --dry-run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S18d --dry-run with a failing search still exits 3" || fail "S18d (rc=$RC)"
mkmock; setfile view_fail 'gh: connection reset'; run --dry-run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"::warning::dry-run: could not read #10515"* && "$OUT" == *"#### Item 1"* ]] \
  && pass "S18f --dry-run with an unreadable tracker warns, still prints the body, exits 0 (the read is non-fatal)" || fail "S18f (rc=$RC out=$OUT)"
NOW="$NOW_AT"
# A normal run right after a dry run still posts (nothing was spent).
mkmock; run --dry-run; assert_fixture_dir "$MOCKD"; : > "$MOCKD/calls"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S18e a real run after a dry run still posts once" || fail "S18e (rc=$RC posted=$(comments_posted))"

# ---- S19: usage errors (strict: none, or exactly --dry-run) ----
for bad_arg in --bogus --print-state extra; do
  mkmock; run "$bad_arg"
  usage_ok && pass "S19 argument '$bad_arg': exit 2 with usage, no gh call" || fail "S19 [$bad_arg] (rc=$RC err=$ERR)"
done
chk_args_strict && pass "S19b '', '' --dry-run, --dry-run '', --dry-run extra and --bogus: all exit 2 with usage and no gh call (an empty argument never runs the real path)" || fail "S19b strict arguments (rc=$RC)"

# ---- S21: the clock fallback ----
chk_clock && pass "S21 WATCH_NOW unset: the script reads the clock (date shim 2027-02-03): posts once, body dated from the shim, five billing months" || fail "S21 clock fallback (rc=$RC err=$ERR)"
NOW="$NOW_AT"

# ---- S20: the mock itself rejects unexpected invocations (exit 64) ----
mkmock
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh issue close 10515 ) >/dev/null 2>&1; r1=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh api -X POST repos/x ) >/dev/null 2>&1; r2=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh api repos/x -f a=b ) >/dev/null 2>&1; r3=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh api graphql -f 'query=mutation{x}' ) >/dev/null 2>&1; r4=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh issue edit 1 --add-label x ) >/dev/null 2>&1; r5=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh issue view 10514 --json state,createdAt,comments ) >/dev/null 2>&1; r6=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh issue comment 10514 --body-file - ) >/dev/null 2>&1 </dev/null; r7=$?
( env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" gh api 'search/issues?q=repo%3Ajikig-ai%2Fsoleur%20created%3A%3E%3D2026-10-19%20ratchet%20eslint&per_page=50&sort=created&order=desc' ) >/dev/null 2>&1; r8=$?
[[ "$r1" -eq 64 && "$r2" -eq 64 && "$r3" -eq 64 && "$r4" -eq 64 && "$r5" -eq 64 && "$r6" -eq 64 && "$r7" -eq 64 && "$r8" -eq 64 ]] \
  && pass "S20 the mock exits 64 on close, api -X/-f, a GraphQL mutation, issue edit, any tracker other than 10515 and any per_page other than 30 (and logs them)" || fail "S20 ($r1 $r2 $r3 $r4 $r5 $r6 $r7 $r8)"

# ---- G1: Guard 1, the recorded-argv oracle ----
# Control: the predicate must refuse non-allowed shapes and accept the four allowed ones.
ctl=1
for probe in 'issue close 10515' 'issue edit 10515 --add-label x' 'issue reopen 10515' 'issue comment 10515 --edit-last' 'label create x' 'pr merge 1' 'api -X POST repos/x' 'api repos/x -f a=b' 'api repos/x --method DELETE' 'api graphql -f query=mutation{x}' 'repo edit'; do
  argv_ok "$probe" && ctl=0
done
for probe in 'issue view 10515 --json state,createdAt,comments' 'issue comment 10515 --body-file -' 'api search/issues?q=x&per_page=30' 'api graphql -f query=query{viewer{login}}'; do
  argv_ok "$probe" || ctl=0
done
[[ "$ctl" -eq 1 ]] && pass "G1a the argv oracle refuses 11 non-allowed shapes and accepts the 4 allowed ones" || fail "G1a oracle control broken"
viol=0; nonempty=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  nonempty=$((nonempty + 1))
  viol=$((viol + $(argv_violations "$d")))
done
# The S20 mock deliberately logs 5 rejected calls; subtract them (they are the oracle's own probes).
[[ "$viol" -eq 5 && "$nonempty" -ge 20 ]] \
  && pass "G1b every recorded argv of every scenario is in {issue view, issue comment, api GET, api graphql} (only the 5 deliberate probes of S20 are outside)" || fail "G1b (violations=$viol over $nonempty mock dirs)"
# A read-only GraphQL query variant must stay GREEN (must-PASS non-canonical input).
argv_ok 'api graphql -f query=query{rateLimit{remaining}}' && pass "G1c a read-only GraphQL query is allowed" || fail "G1c"

# ---- W: the workflow facets of the reeval-10515 job (PyYAML; an absent workflow file or PyYAML FAILS, never skips) ----
WF="$SCRIPT_DIR/../.github/workflows/code-quality-followups-watch.yml"
assert_fixture_dir "$ROOT"
cat > "$ROOT/wfcheck.py" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML is not importable")
    sys.exit(3)
path = sys.argv[1]
doc = yaml.safe_load(open(path)) or {}
job = (doc.get("jobs") or {}).get("reeval-10515")
bad = []
if not isinstance(job, dict):
    bad.append("job reeval-10515 is missing")
else:
    steps = job.get("steps") or []
    co = steps[0] if len(steps) > 0 and isinstance(steps[0], dict) else {}
    rn = steps[1] if len(steps) > 1 and isinstance(steps[1], dict) else {}
    if "actions/checkout@" not in str(co.get("uses", "")):
        bad.append("step 1 is not actions/checkout")
    if (co.get("with") or {}).get("fetch-depth") != 0:
        bad.append("checkout fetch-depth is %r, want 0 (the watcher reads full git history)" % ((co.get("with") or {}).get("fetch-depth"),))
    if "watch-lint-ratchet-reeval-10515.sh" not in str(rn.get("run", "")):
        bad.append("run step does not invoke watch-lint-ratchet-reeval-10515.sh")
    env = rn.get("env") or {}
    for k in ("GH_TOKEN", "DRY_RUN", "GH_REPO"):
        if k not in env:
            bad.append("run step env lacks %s" % k)
    if "github.token" not in str(env.get("GH_TOKEN", "")):
        bad.append("GH_TOKEN is not the workflow token")
    if "github.repository" not in str(env.get("GH_REPO", "")):
        bad.append("GH_REPO is not github.repository")
    if "inputs.dry_run" not in str(env.get("DRY_RUN", "")):
        bad.append("DRY_RUN is not inputs.dry_run")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
WF_OUT=""; WF_RC=0
wf_run() { # FILE [python flags]
  if [[ ! -f "$1" ]]; then WF_RC=4; WF_OUT="workflow file absent: $1"; return; fi
  WF_OUT="$(python3 "${2:--I}" "$ROOT/wfcheck.py" "$1" 2>&1)"; WF_RC=$?
}
wf_mut() { # NAME PERL_SUBST -> $ROOT/wfmut-NAME.yml; rc 0 only when the mutation landed
  assert_fixture_dir "$ROOT"
  cp "$WF" "$ROOT/wfmut-$1.yml" || fatal "wf copy failed"
  perl -0pi -e "$2" "$ROOT/wfmut-$1.yml" || fatal "wf mutation perl failed"
  ! diff -q "$WF" "$ROOT/wfmut-$1.yml" >/dev/null 2>&1
}
wf_run "$WF"
[[ "$WF_RC" -eq 0 ]] && pass "W1 the workflow's reeval-10515 job: checkout with fetch-depth 0, runs this script, env GH_TOKEN / GH_REPO / DRY_RUN wired to the workflow token, repository and dry_run input" || fail "W1 (rc=$WF_RC: $WF_OUT)"
wf_mut depth 's/(reeval-10515:.*?fetch-depth: )0/${1}1/s' && landed=1 || landed=0
wf_run "$ROOT/wfmut-depth.yml"
[[ "$landed" -eq 1 && "$WF_RC" -eq 1 && "$WF_OUT" == *"fetch-depth"* ]] && pass "W2 mutated copy with fetch-depth 1 on the reeval-10515 job: the facet goes RED" || fail "W2 (landed=$landed rc=$WF_RC $WF_OUT)"
wf_mut nodry 's/(reeval-10515:.*?)          DRY_RUN: [^\n]*\n/$1/s' && landed=1 || landed=0
wf_run "$ROOT/wfmut-nodry.yml"
[[ "$landed" -eq 1 && "$WF_RC" -eq 1 && "$WF_OUT" == *"DRY_RUN"* ]] && pass "W3 mutated copy without the DRY_RUN env on the reeval-10515 job: the facet goes RED" || fail "W3 (landed=$landed rc=$WF_RC $WF_OUT)"
wf_mut script 's/(reeval-10515:.*?bash scripts\/)watch-lint-ratchet-reeval-10515\.sh/${1}watch-brand-hex-triggers-11177.sh/s' && landed=1 || landed=0
wf_run "$ROOT/wfmut-script.yml"
[[ "$landed" -eq 1 && "$WF_RC" -eq 1 && "$WF_OUT" == *"does not invoke"* ]] && pass "W4 mutated copy where the reeval-10515 job runs another script: the facet goes RED" || fail "W4 (landed=$landed rc=$WF_RC $WF_OUT)"
wf_run "$ROOT/no-such-workflow.yml"; r1=$WF_RC
[[ "$r1" -ne 0 ]] && pass "W5 an absent workflow file FAILS the facet (never skips)" || fail "W5 (rc $r1)"
wf_run "$WF" -IS
[[ "$WF_RC" -eq 3 && "$WF_OUT" == *"PyYAML"* ]] && pass "W6 with PyYAML unavailable the facet exits 3 (a loud FAIL in the real row, never a skip)" || fail "W6 (rc=$WF_RC $WF_OUT)"

# ---- Mutation harness: mutated COPIES in a scratch dir, a pristine diff proving each mutation landed, an unmutated control required green ----
mutate() { # file old new -> rewrites file; rc 1 when OLD is absent (the mutation could not land)
  local f="$1" old="$2" new="$3" s
  s="$(cat "$f"; printf x)"; s="${s%x}"
  [[ "$s" == *"$old"* ]] || return 1
  assert_fixture_dir "$f"
  printf '%s' "${s/"$old"/"$new"}" > "$f"
}
mkcopy() { # name -> $ROOT/mut_<name>/scripts/{sut,lib/}
  local d="$ROOT/mut_$1"
  assert_fixture_dir "$d"
  mkdir -p "$d/scripts/lib" || fatal "mkdir failed"
  cp "$SUT" "$d/scripts/watch-lint-ratchet-reeval-10515.sh"; cp "$LIB" "$d/scripts/lib/watch-notify-once.sh"
  chmod +x "$d/scripts/watch-lint-ratchet-reeval-10515.sh"
}
MOCK_PREFIX="mut"

# Behaviour checks (0 = correct behaviour). Each builds its own mock and runs SUT_RUN.
chk_post_happens()   { mkmock; NOW="$NOW_AT"; run; [[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$BODY" == *"$SENTINEL"* ]]; }
chk_bot_suppresses() { mkmock; NOW="$NOW_AFTER"; issue OPEN "$(bot_comment)"; run; [[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]]; }
chk_human_ignored()  { mkmock; NOW="$NOW_AFTER"; issue OPEN "$(human_comment)"; run; [[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]]; }
chk_junk_is_rc3()    { mkmock; NOW="$NOW_AFTER"; issue OPEN "$UNEVAL"; run; [[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]]; }
chk_gate_precedes()  { mkmock; NOW="$NOW_BEFORE"; issue OPEN '[]'; run; [[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]]; }
all_chk() {
  chk_post_happens && chk_bot_suppresses && chk_human_ignored && chk_junk_is_rc3 && chk_gate_precedes \
    && chk_args_strict && chk_billing_verdict && chk_incomplete && chk_quote && chk_cap && chk_null_user \
    && chk_commits_cap && chk_shallow && chk_clock \
    && chk_post_http && chk_sanitize && chk_sanitize_inert && chk_billing_yes_partial && chk_trunc && chk_pad && chk_dry_closed
}

# Control: the unmutated copy must be green on every check.
mkcopy ctl; SUT_RUN="$ROOT/mut_ctl/scripts/watch-lint-ratchet-reeval-10515.sh"
M0_OK=0
if all_chk; then M0_OK=1; pass "M0 the unmutated scratch copy is green on all twenty-one behaviour checks (control)"; else fail "M0 control copy is not green"; fi

# Run one mutation: NAME TARGET(lib|sut) OLD NEW CHECK-FN LABEL
mutation_row() {
  local name="$1" target="$2" old="$3" new="$4" chk="$5" label="$6" f pristine landed=0 control_green=0 mutant_red=0
  mkcopy "$name"
  if [[ "$target" == lib ]]; then f="$ROOT/mut_$name/scripts/lib/watch-notify-once.sh"; pristine="$LIB"
  else f="$ROOT/mut_$name/scripts/watch-lint-ratchet-reeval-10515.sh"; pristine="$SUT"; fi
  if mutate "$f" "$old" "$new" && ! cmp -s "$pristine" "$f"; then landed=1; fi
  if [[ "$landed" -eq 1 && "$(diff "$pristine" "$f" | grep -c '^[<>]' || true)" -ge 1 ]]; then :; else landed=0; fi
  control_green="$M0_OK"   # the unmutated copy's verdict on every check, from M0
  SUT_RUN="$ROOT/mut_$name/scripts/watch-lint-ratchet-reeval-10515.sh"; "$chk" || mutant_red=1
  SUT_RUN="$SUT"
  [[ "$landed" -eq 1 && "$control_green" -eq 1 && "$mutant_red" -eq 1 ]] \
    && pass "$label (mutation landed per pristine diff, control green, mutant RED)" || fail "$label (landed=$landed control_green=$control_green mutant_red=$mutant_red)"
}

# Guard 2 #1: delete the sentinel check -> the second run posts again.
mutation_row m2_1 lib '    wn_sentinel_present "$key"; rc=$?' '    rc=1' chk_bot_suppresses "G2#1 delete the sentinel check"
# Guard 2 #2: accept any author -> the human-sentinel scenario posts nothing.
mutation_row m2_2 lib '((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")' 'true' chk_human_ignored "G2#2 accept any comment author"
# Guard 2 #4: a jq failure in the reader is read as "absent" -> the malformed-comments scenario posts.
mutation_row m2_4 lib "| length' 2>/dev/null)\" || return 3" "| length' 2>/dev/null)\" || return 1" chk_junk_is_rc3 "G2#4 treat a reader jq failure as absent"
# Guard 2 #5: drop the earliest gate -> a pre-date run with an OPEN tracker and no comments posts.
mutation_row m2_5 lib '    wn_reached "$earliest"; rc=$?' '    rc=0' chk_gate_precedes "G2#5 drop the earliest-date gate"
# Harness row: remove the wn_post call -> the posting scenario must go RED.
mutation_row m2_h lib 'wn_post "$tracker" <<<"$payload"; then' 'cat >/dev/null <<<"$payload"; then' chk_post_happens "G2-harness remove the wn_post call"

# Review-fix guards (each: the mutated copy must go RED on the matching check).
mutation_row mr_trk sut 'TRACKER=10515' 'TRACKER=10514' chk_post_happens "RF the tracker number pinned by the mock (TRACKER=10514)"
mutation_row mr_wnp lib 'wn_post "$tracker" <<<"$payload"; then' 'wn_post 10514 <<<"$payload"; then' chk_post_happens "RF the tracker number pinned by the mock (wn_post hardcoded elsewhere)"
mutation_row mr_pp sut 'per_page=30' 'per_page=50' chk_post_happens "RF the per_page=30 pin"
mutation_row mr_args sut 'elif [[ $# -ne 0 ]]; then' 'elif [[ "${1:-}" == --bogus ]]; then' chk_args_strict "RF strict arguments (an empty argument must not run the real path)"
mutation_row mr_ge sut '! "${last:0:10}" < "$WN_BILLING_STOP_EXPECTED_BY"' '"${last:0:10}" >'' "$WN_BILLING_STOP_EXPECTED_BY"' chk_billing_verdict "RF billing stop day compared with > instead of >="
mutation_row mr_yes sut 'then code_after=1; fi' 'then code_after=0; fi' chk_billing_verdict "RF billing 'yes' verdict (code_after never set)"
mutation_row mr_inc sut '.incomplete_results == true) then error' '.incomplete_results == "never") then error' chk_incomplete "RF incomplete_results is an error"
mutation_row mr_quote sut "'\"ever-better\"'" "'ever-better'" chk_quote "RF the ever-better phrase is quoted in the query"
mutation_row mr_cap sut '[[ "$total" -gt "$shown" ]]' '[[ "$total" -ge "$shown" ]]' chk_cap "RF the cap boundary (-gt vs -ge) and N of TOTAL"
mutation_row mr_user sut '(.user.login // "")' '.user.login' chk_null_user "RF user: null tolerated via (.user.login // \"\")"
mutation_row mr_fp sut '--first-parent ' '' chk_commits_cap "RF --first-parent (a merged side branch counted once)"
mutation_row mr_mc sut '--max-count=20 ' '' chk_commits_cap "RF --max-count=20"
mutation_row mr_sh sut 'rev-parse --is-shallow-repository' 'rev-parse --is-bare-repository' chk_shallow "RF the shallow-clone guard"
mutation_row mr_pipe lib 'wn_post "$tracker" <<<"$payload"; then' 'printf "%s\n" "$payload" | wn_post "$tracker"; then' chk_post_http "RF wn_post as a pipeline stage loses the HTTP status (the pipe form must not return)"
mutation_row mr_di lib '\p{Default_Ignorable_Code_Point}' '' chk_sanitize "RF default-ignorable code points are stripped"
mutation_row mr_2800 lib '\x{2800}' '' chk_sanitize "RF U+2800 (blank braille) is stripped"
mutation_row mr_yp sut 'if (( code_after == 1 )); then' 'if false; then' chk_billing_yes_partial "RF a definite yes survives an unreadable later month"
mutation_row mr_tr sut 'span_date "${first:0:10}"' 'span_date "$first"' chk_trunc "RF billing first/last are cut to dates"
mutation_row mr_pad lib 'billing read for ${tag} failed (' 'billing read for ${y}-${m} failed (' chk_pad "RF the library's billing annotation zero-pads the month"
mutation_row mr_dc lib 'notopen=" (not OPEN: a real run would post nothing)"' 'notopen=""' chk_dry_closed "RF dry-run on a non-OPEN tracker says a real run would post nothing"
mutation_row mr_clk lib '${WATCH_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}' '${WATCH_NOW:-2000-01-01T00:00:00Z}' chk_clock "RF the clock fallback reads date"

# Guard 1 #1: `gh issue close` added after the post -> the recorded argv set exposes it.
mkcopy g1; SUT_RUN="$ROOT/mut_g1/scripts/watch-lint-ratchet-reeval-10515.sh"
if mutate "$SUT_RUN" 'exit "$rc"' 'gh issue close 10515 >/dev/null 2>&1; exit "$rc"' && ! cmp -s "$SUT" "$SUT_RUN"; then g1_landed=1; else g1_landed=0; fi
mkmock; NOW="$NOW_AT"; run; g1_viol="$(argv_violations "$MOCKD")"
SUT_RUN="$SUT"
[[ "$g1_landed" -eq 1 && "$g1_viol" -ge 1 ]] && pass "G1-mutation-1 'gh issue close' appended to the script is caught by the recorded-argv oracle" || fail "G1-mutation-1 (landed=$g1_landed violations=$g1_viol)"
# Guard 1 #2: a mock that logs nothing -> the recorder floor must refuse it.
mkmock; flag nolog; NOW="$NOW_AT"; run
if posting_floor_ok "$MOCKD"; then fail "G1-mutation-2 a mock that logs nothing still satisfies the floor"; else pass "G1-mutation-2 a mock that logs nothing fails the recorder floor (a dead recorder cannot pass)"; fi
NOW="$NOW_AT"
MOCK_PREFIX="mock"

# Exit-gate check (behavioural): this same suite, re-run with ONE injected failure, must
# exit EXACTLY 1. An `exit 0` placed before the gate, a reset FAIL counter, or a neutered
# exit path would all give 0 here; the FATAL below runs before any of them can.
if [[ -z "${WLR_INJECT_FAIL:-}" ]]; then
  WLR_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: the exit gate returned %s (expected 1) with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
# Anti-vacuity floor (ADR-193). The threshold is declared on the line IMMEDIATELY
# above the `if`, not with the other constants: guard-vacuity-floor builds its mutant
# by slicing the floor block plus the CONTIGUOUS simple assignments above it.
MIN_ASSERTIONS=152
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
finish || exit 1
