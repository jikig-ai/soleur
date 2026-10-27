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
        [[ "$#" -eq 5 && "$3" =~ ^[0-9]+$ && "$4" == "--json" && "$5" == "state,createdAt,comments" ]] || deny "$@"
        if [[ -f "$MOCKD/view_fail" ]]; then cat "$MOCKD/view_fail" >&2; exit 1; fi
        cat "$MOCKD/issue.json"; exit 0 ;;
      comment)
        [[ "$#" -eq 5 && "$3" =~ ^[0-9]+$ && "$4" == "--body-file" && "$5" == "-" ]] || deny "$@"
        if [[ -f "$MOCKD/comment_fail" ]]; then cat >/dev/null; echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; fi
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
        [[ "$tail" =~ ^\&per_page=[0-9]+(\&sort=created)?(\&order=(asc|desc))?$ ]] || deny api "$@"
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
          items:[range(0;$n)|{number:(3000+.), state:"open", title:("hit \($k) \(.)"),
                 created_at:("2026-10-2\(. % 10)T10:00:00Z"), user:{login:("u\(.)"), type:"User"},
                 author_association:"OWNER"}]}'
        exit 0 ;;
      orgs/jikig-ai/settings/billing/usage\?year=*\&month=*)
        y="${path#*year=}"; y="${y%%&*}"; m="${path#*month=}"
        [[ "$y" =~ ^20[0-9]{2}$ && "$m" =~ ^([1-9]|1[0-2])$ ]] || deny api "$@"
        if [[ -f "$MOCKD/bill_fail" ]]; then
          case "$(cat "$MOCKD/bill_fail")" in
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
  local o="$MOCKD/stdout" e="$MOCKD/stderr" root="${WATCH_ROOT_OVERRIDE-$FIX}" renv
  renv=()
  [[ -n "$root" ]] && renv=("WATCH_REPO_ROOT=$root")
  ( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "WATCH_NOW=$NOW" "TMPDIR=$ROOT/tmp" "${renv[@]}" bash "$SUT_RUN" "$@" ) > "$o" 2> "$e"
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
hitlines() { grep -c '^- #' <<<"$1" || true; }
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

# ================================ SCENARIOS =========================================
# ---- S1 (scenario 6): before 2027-01-18 -> a notice, exit 0, no gh call at all ----
mkmock; NOW="$NOW_BEFORE"; run
[[ "$RC" -eq 0 && "$OUT" == *"::notice::"* && "$(total_calls)" -eq 0 && -z "$BODY" ]] \
  && pass "S1 one second before 2027-01-18: ::notice::, exit 0, no gh call, no comment" || fail "S1 (rc=$RC calls=$(total_calls) out=$OUT)"

# ---- S2: at the boundary -> exactly one comment, sentinel the exact last line ----
mkmock; NOW="$NOW_AT"; hits eslint 1; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$(view_calls)" -eq 1 && "$(searches_made)" -eq 9 ]] \
  && pass "S2 at 2027-01-18T00:00:00Z: exit 0, one issue view, nine searches, exactly one comment" || fail "S2 (rc=$RC posted=$(comments_posted) searches=$(searches_made) err=$ERR)"
S2_MOCK="$MOCKD"; S2_BODY="$BODY"
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
      1) [[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 1 && "$s" == *"- #3000 "* && "$s" == *"2026-10-20"* && "$s" == *"open"* ]] \
           && pass "S5 [$key] 1 hit: one line with number, state and created date" || fail "S5 [$key] 1 hit (rc=$RC section=$s)" ;;
      25) [[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 20 && "$s" == *"- #3019 "* && "$s" != *"- #3020 "* && "$s" == *"20 of 25"* ]] \
           && pass "S5 [$key] 25 hits: capped at 20 lines and says '20 of 25'" || fail "S5 [$key] 25 hits (rc=$RC lines=$(hitlines "$s"))" ;;
    esac
  done
done

# ---- S6: items 5 and 6 ----
mkmock; hits telemetry 0; run
s="$(sec telemetry)"
[[ "$s" == *'build blocked on `soleur:legal:clo` review'* ]] && pass "S6a item 5 prints the static CLO line with 0 hits" || fail "S6a ($s)"
mkmock; hits telemetry 3; run
s="$(sec telemetry)"
[[ "$s" == *'build blocked on `soleur:legal:clo` review'* && "$(hitlines "$s")" -eq 3 ]] && pass "S6b item 5 prints the static CLO line next to its hits" || fail "S6b ($s)"
mkmock; run
ever_q=""; while IFS= read -r l; do [[ "$l" == *ever-better* ]] && ever_q="$(decode_q "$l")"; done < "$MOCKD/calls"
[[ "$ever_q" == "${PREFIX_Q}ever-better" ]] && pass "S6c item 6 searches the single keyword ever-better (and nothing else)" || fail "S6c (q=$ever_q)"

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
jq -n --arg t "$HOSTILE_TITLE" --arg l 'evil@octo<b>' '{total_count:1,items:[{number:3100,state:"open",title:$t,created_at:"2026-10-25T00:00:00Z",user:{login:$l,type:"User"},author_association:"NONE"}]}' > "$MOCKD/search_eslint.json"
run
hl="$(grep -m1 '^- #3100 ' <<<"$BODY" || true)"
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
jq -n '{total_count:3,items:[{number:10515,state:"open",title:"the tracker",created_at:"2026-10-19T00:00:00Z",user:{login:"a",type:"User"},author_association:"OWNER"},{number:10331,state:"closed",title:"the epic",created_at:"2026-10-19T00:00:00Z",user:{login:"a",type:"User"},author_association:"OWNER"},{number:3300,state:"open",title:"real lead",created_at:"2026-10-30T00:00:00Z",user:{login:"b",type:"User"},author_association:"OWNER"}]}' > "$MOCKD/search_monorepo.json"
run; s="$(sec monorepo)"
[[ "$RC" -eq 0 && "$(hitlines "$s")" -eq 1 && "$s" == *"- #3300 "* && "$s" != *"- #10515"* && "$s" != *"- #10331"* ]] \
  && pass "S10 #10515 and #10331 never appear as hits (one lead remains)" || fail "S10 ($s)"

# ---- S11: the author association and the external mark ----
mkmock
jq -n '{total_count:6,items:[
 {number:3201,state:"open",title:"t1",created_at:"2026-10-20T00:00:00Z",user:{login:"owner1",type:"User"},author_association:"OWNER"},
 {number:3202,state:"open",title:"t2",created_at:"2026-10-20T00:00:00Z",user:{login:"member1",type:"User"},author_association:"MEMBER"},
 {number:3203,state:"open",title:"t3",created_at:"2026-10-20T00:00:00Z",user:{login:"rando",type:"User"},author_association:"NONE"},
 {number:3204,state:"open",title:"t4",created_at:"2026-10-20T00:00:00Z",user:{login:"contrib",type:"User"},author_association:"CONTRIBUTOR"},
 {number:3205,state:"open",title:"t5",created_at:"2026-10-20T00:00:00Z",user:{login:"dependabot[bot]",type:"Bot"},author_association:"NONE"},
 {number:3206,state:"closed",title:"t6",created_at:"2026-10-20T00:00:00Z",user:{login:"svc[bot]",type:"User"},author_association:"NONE"}]}' > "$MOCKD/search_windows.json"
run; s="$(sec windows)"
l1="$(grep '^- #3201 ' <<<"$s")"; l2="$(grep '^- #3202 ' <<<"$s")"; l3="$(grep '^- #3203 ' <<<"$s")"
l4="$(grep '^- #3204 ' <<<"$s")"; l5="$(grep '^- #3205 ' <<<"$s")"; l6="$(grep '^- #3206 ' <<<"$s")"
[[ "$l1" == *OWNER* && "$l1" != *external* && "$l2" == *MEMBER* && "$l2" != *external* ]] \
  && pass "S11a OWNER and MEMBER authors show their association and no external mark" || fail "S11a ($l1 | $l2)"
[[ "$l3" == *NONE* && "$l3" == *external* && "$l4" == *CONTRIBUTOR* && "$l4" == *external* ]] \
  && pass "S11b NONE and CONTRIBUTOR authors are marked external" || fail "S11b ($l3 | $l4)"
[[ "$l5" != *external* && "$l6" != *external* && "$l6" == *closed* ]] \
  && pass "S11c a bot (type Bot, or a [bot] login) is never marked external; state closed is shown" || fail "S11c ($l5 | $l6)"

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
mkmock; WATCH_ROOT_OVERRIDE=""; run --dry-run; WATCH_ROOT_OVERRIDE="$FIX"
grep -qE '^\| GitHub Code Quality' <<<"$OUT" && grep -qE '^## Amendment .*Code Quality' <<<"$OUT" \
  && pass "S12e against the REAL repo root (no WATCH_REPO_ROOT) the ledger line and an ADR-276 heading are printed" || fail "S12e (rc=$RC)"

# ---- S13: commits touching lint-ratchet.py since 2026-10-19 ----
mkmock; run
s="$(awk '/^### Commits/ {f=1; print; next} f && /^### / {exit} f {print}' <<<"$BODY")"
[[ -n "$s" && "$s" == *second-inwindow-change* && "$s" == *octocat* && "$s" != *PREWINDOW* && "$s" != *OTHERFILE* ]] \
  && pass "S13 in-window lint-ratchet.py commits are listed; the pre-window and other-file commits are not" || fail "S13 ($s)"
sl="$(grep -m1 octocat <<<"$s" || true)"
[[ "$sl" == *'`tweak @octocat '* && "$sl" != *"<"* && "$sl" != *"&"* && "$(( $(grep -o "$BT" <<<"$sl" | wc -l) % 2 ))" -eq 0 ]] \
  && pass "S13b a hostile commit subject is sanitized into a balanced code span" || fail "S13b ($sl)"

# ---- S14: billing, readable ----
mkmock
setfile bill_2026_10.json '{"usageItems":[{"product":"code_quality","sku":"Code Quality AI Credits","date":"2026-10-05","grossAmount":100.5,"netAmount":100.5},{"product":"code_quality","date":"2026-10-19","grossAmount":60.25,"netAmount":60.25},{"product":"copilot","sku":"SYNTH-OTHER-SKU","date":"2026-10-20","grossAmount":999.99,"netAmount":999.99}]}'
setfile bill_2026_11.json '{"usageItems":[{"product":"code_quality","date":"2026-11-02","grossAmount":1.25,"netAmount":1.25}]}'
run
bs="$(awk '/^### Billing/ {f=1; print; next} f && /^### / {exit} f {print}' <<<"$BODY")"
[[ "$RC" -eq 0 && "$(bill_calls)" -eq 4 && "$bs" == *"160.75"* && "$bs" == *"1.25"* ]] \
  && pass "S14 four months (2026-10 to 2027-01) read; code_quality aggregates shown (160.75, 1.25)" || fail "S14 (rc=$RC calls=$(bill_calls) section=$bs)"
[[ "$BODY" != *999.99* && "$BODY" != *copilot* && "$BODY" != *SYNTH-OTHER-SKU* ]] \
  && pass "S14b no other product, SKU or amount is ever published" || fail "S14b"
grep -qxF 'api orgs/jikig-ai/settings/billing/usage?year=2026&month=10' "$MOCKD/calls" && grep -qxF 'api orgs/jikig-ai/settings/billing/usage?year=2027&month=1' "$MOCKD/calls" \
  && pass "S14c billing is read as a GET with year and month in the URL" || fail "S14c"
[[ "$bs" == *"after 2026-10-19"* ]] && pass "S14d the section states whether code_quality usage is dated after 2026-10-19" || fail "S14d"
# billing unreadable: table-driven 401/403/404 degrade and still post
for st in 401 403 404; do
  mkmock; setfile bill_fail "$st"; run
  [[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$BODY" == *"not readable from CI"* && "$(bill_calls)" -eq 1 && "$ERR" == *"::warning::"* ]] \
    && pass "S14e billing HTTP $st: degraded section, ::warning::, one call, still posts, exit 0" || fail "S14e [$st] (rc=$RC posted=$(comments_posted) err=$ERR)"
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

# ---- S17 (scenario 11): xtrace refusal ----
mkmock
faketok="gh""s_""$(printf 'A%.0s' {1..24})"
( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "WATCH_NOW=$NOW_AT" "WATCH_REPO_ROOT=$FIX" "GH_TOKEN=$faketok" bash -x "$SUT" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
RC=$?; ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"refusing to run under xtrace"* && "$(total_calls)" -eq 0 ]] \
  && pass "S17 bash -x: exit 78 with the refusal, no gh call" || fail "S17 (rc=$RC)"
# The refusal precedes the library: a missing library under -x is still 78, not a source error.
xs="$ROOT/xs"; mkdir -p "$xs/lib"; cp "$SUT" "$xs/s.sh"
( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "GH_TOKEN=$faketok" bash -x "$xs/s.sh" ) > /dev/null 2> "$MOCKD/stderr"; RC=$?
[[ "$RC" -eq 78 ]] && pass "S17b the xtrace refusal runs before the library is sourced" || fail "S17b (rc=$RC)"

# ---- S18 (scenario 12): --dry-run ----
mkmock; NOW='2026-10-27T12:00:00Z'; hits eslint 2; run --dry-run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$(view_calls)" -eq 0 && "$(searches_made)" -eq 9 && "$OUT" == *"dry-run: nothing posted, no sentinel spent"* && "$OUT" == *"#### Item 1"* ]] \
  && pass "S18 --dry-run before the date: gate skipped, body printed, zero 'issue comment' and zero 'issue view' calls" || fail "S18 (rc=$RC posted=$(comments_posted) out=$OUT)"
[[ "$(bill_calls)" -eq 1 ]] && pass "S18b --dry-run at 2026-10-27 reads just the 2026-10 billing month" || fail "S18b ($(bill_calls))"
mkmock; issue CLOSED "$(bot_comment)"; run --dry-run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"#### Item 1"* ]] \
  && pass "S18c --dry-run ignores a CLOSED tracker and an existing sentinel (reads nothing, spends nothing)" || fail "S18c (rc=$RC)"
mkmock; setfile search_fail_ever 'gh: Validation Failed (HTTP 422)'; run --dry-run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S18d --dry-run with a failing search still exits 3" || fail "S18d (rc=$RC)"
NOW="$NOW_AT"
# A normal run right after a dry run still posts (nothing was spent).
mkmock; run --dry-run; : > "$MOCKD/calls"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S18e a real run after a dry run still posts once" || fail "S18e (rc=$RC posted=$(comments_posted))"

# ---- S19: usage errors ----
for bad_arg in --bogus --print-state extra; do
  mkmock; run "$bad_arg"
  [[ "$RC" -eq 2 && "$ERR" == *usage:* && "$(total_calls)" -eq 0 ]] && pass "S19 argument '$bad_arg': exit 2 with usage, no gh call" || fail "S19 [$bad_arg] (rc=$RC err=$ERR)"
done
mkmock; run --dry-run extra
[[ "$RC" -eq 2 && "$(total_calls)" -eq 0 ]] && pass "S19b --dry-run with an extra argument: exit 2, no gh call" || fail "S19b (rc=$RC)"

# ---- S20: the mock itself rejects unexpected invocations (exit 64) ----
mkmock
( PATH="$MOCKD:$PATH" MOCKD="$MOCKD" gh issue close 10515 ) >/dev/null 2>&1; r1=$?
( PATH="$MOCKD:$PATH" MOCKD="$MOCKD" gh api -X POST repos/x ) >/dev/null 2>&1; r2=$?
( PATH="$MOCKD:$PATH" MOCKD="$MOCKD" gh api repos/x -f a=b ) >/dev/null 2>&1; r3=$?
( PATH="$MOCKD:$PATH" MOCKD="$MOCKD" gh api graphql -f 'query=mutation{x}' ) >/dev/null 2>&1; r4=$?
( PATH="$MOCKD:$PATH" MOCKD="$MOCKD" gh issue edit 1 --add-label x ) >/dev/null 2>&1; r5=$?
[[ "$r1" -eq 64 && "$r2" -eq 64 && "$r3" -eq 64 && "$r4" -eq 64 && "$r5" -eq 64 ]] \
  && pass "S20 the mock exits 64 on close, api -X/-f, a GraphQL mutation and issue edit (and logs them)" || fail "S20 ($r1 $r2 $r3 $r4 $r5)"

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

# ---- Mutation harness: mutated COPIES in a scratch dir, a pristine diff proving each mutation landed, an unmutated control required green ----
mutate() { # file old new -> rewrites file; rc 1 when OLD is absent (the mutation could not land)
  local f="$1" old="$2" new="$3" s
  s="$(cat "$f"; printf x)"; s="${s%x}"
  [[ "$s" == *"$old"* ]] || return 1
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
all_chk() { chk_post_happens && chk_bot_suppresses && chk_human_ignored && chk_junk_is_rc3 && chk_gate_precedes; }

# Control: the unmutated copy must be green on every check.
mkcopy ctl; SUT_RUN="$ROOT/mut_ctl/scripts/watch-lint-ratchet-reeval-10515.sh"
M0_OK=0
if all_chk; then M0_OK=1; pass "M0 the unmutated scratch copy is green on all five behaviour checks (control)"; else fail "M0 control copy is not green"; fi

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
mutation_row m2_h lib '| wn_post "$tracker"; then' '| cat >/dev/null; then' chk_post_happens "G2-harness remove the wn_post call"

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
MIN_ASSERTIONS=92
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
finish || exit 1
