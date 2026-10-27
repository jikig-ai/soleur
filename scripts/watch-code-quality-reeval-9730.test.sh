#!/usr/bin/env bash
# Suite for scripts/watch-code-quality-reeval-9730.sh (the date-gated watcher that posts
# ONE data comment on the Code Quality re-evaluation tracker #9730 and never closes it) and,
# through it, for the shared library scripts/lib/watch-notify-once.sh. Mock-`gh` pattern: a
# PATH-prepended recording `gh` serves per-scenario issue JSON, GraphQL counts and billing
# responses and logs every argv, so the property under test is the OBSERVED call set (Guard 1)
# and the observed post count (Guard 2), never a list of call sites.
#
# Guards covered here (plan: knowledge-base/project/plans/2026-10-27-chore-autonomous-start-
# followthroughs-plan.md, "Guard Contract"):
#   Guard 1  read-only, notify-only write set: recorded-argv oracle (the comment argv pinned
#            exactly) + ONE static allowlist census (R5; spans the lib, the sibling watchers that
#            exist at run time and the workflow; also flags non-gh egress and gh-through-a-variable)
#            + per-job workflow permissions (PyYAML; absent workflow or PyYAML FAILS).
#   Guard 2  notify-once with a bot-only sentinel.
# Each guard's mutation rows run against a MUTATED COPY of the script/lib in a scratch dir,
# after an unmutated control of the same scenario went green.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-code-quality-reeval-9730.sh"
LIB="$SCRIPT_DIR/lib/watch-notify-once.sh"
WF="$SCRIPT_DIR/../.github/workflows/code-quality-followups-watch.yml"

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

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX WN_DRY_RUN WATCH_NOW
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
ROOT="$(mktemp -d "${TMPDIR%/}/watch-cq-9730.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/tmp" || fatal "mkdir failed"

SENTINEL='<!-- code-quality-followups-watch:reeval-9730:v1 -->'
NOW_BEFORE='2026-11-13T09:17:00Z'
NOW_AFTER='2026-11-16T09:17:00Z'
N=0
MOCKD=""; OUT=""; ERR=""; RC=0; NOW="$NOW_AFTER"; RUN_SUT="$SUT"

# ------------------------------------------------------------------ the mock gh ----
# Whitelists REAL flags only (learning 2026-09-25: a stub that accepts invented flags makes
# dead code look green), emits gh's real stderr shape (`gh: ... (HTTP 403)`), logs EVERY argv
# first (the `# LOGLINE` marker is what the dead-recorder mutation removes) and exits 64 on
# anything it does not know. GraphQL counts are deterministic per day: opened = DD + MM,
# merged = DD, so the expected totals are computable without the script.
cat > "$ROOT/gh.template" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCKD/calls" # LOGLINE
case "$*" in
  "issue view 9730 --json state,createdAt,comments")
    if [[ -f "$MOCKD/view_fail" ]]; then
      case "$(cat "$MOCKD/view_fail")" in
        gone) echo "GraphQL: Could not resolve to an issue or pull request with the number of 9730. (repository.issue)" >&2 ;;
        404) echo "gh: Not Found (HTTP 404)" >&2 ;;
        410) echo "gh: This issue was deleted (HTTP 410)" >&2 ;;
        *) echo "gh: Bad Gateway (HTTP 502)" >&2 ;;
      esac
      exit 1
    fi
    cat "$MOCKD/issue.json"; exit 0 ;;
  "issue comment 9730 --body-file -")
    if [[ -f "$MOCKD/comment_fail" ]]; then cat >/dev/null; echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1; fi
    cat >> "$MOCKD/bodies"; exit 0 ;;
esac
if [[ $# -eq 4 && "$1 $2 $3" == "api graphql -f" && "$4" == query=* ]]; then
  q="${4#query=}"
  case "$q" in *[Mm][Uu][Tt][Aa][Tt][Ii][Oo][Nn]*) echo "mock gh: a graphql mutation is refused" >&2; exit 64 ;; esac
  n=$(( $(cat "$MOCKD/gql_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MOCKD/gql_n"
  mode="$(cat "$MOCKD/gql_mode" 2>/dev/null || echo ok)"
  if [[ "$mode" == fail2 && "$n" -eq 2 ]]; then echo "gh: You have exceeded a secondary rate limit (HTTP 403)" >&2; exit 1; fi
  nsearch="$(printf '%s' "$q" | grep -o 'search(' | wc -l)"
  aliases="$(printf '%s' "$q" | grep -oE '[om][0-9]+: search\(query: "repo:jikig-ai/soleur is:pr (created|merged):[0-9]{4}-[0-9]{2}-[0-9]{2}", type: ISSUE, first: 1\) \{ issueCount \}' || true)"
  nal="$(printf '%s\n' "$aliases" | grep -c . || true)"
  if [[ "$nsearch" -ne "$nal" || "$nal" -eq 0 ]]; then echo "mock gh: unexpected graphql shape" >&2; exit 64; fi
  if [[ "$nsearch" -gt 40 ]]; then echo "mock gh: more than 40 search aliases in one request (chunking broke)" >&2; exit 64; fi
  if [[ "$mode" == errors ]]; then echo '{"errors":[{"message":"boom"}],"data":null}'; exit 0; fi
  re='^([om][0-9]+): search\(query: "repo:jikig-ai/soleur is:pr (created|merged):([0-9]{4}-[0-9]{2}-[0-9]{2})"'
  json='{"data":{'; sep=''
  while IFS= read -r a; do
    [[ "$a" =~ $re ]] || exit 64
    al="${BASH_REMATCH[1]}"; kind="${BASH_REMATCH[2]}"; day="${BASH_REMATCH[3]}"
    dd=$((10#${day:8:2})); mm=$((10#${day:5:2}))
    if [[ "$kind" == created ]]; then c=$((dd + mm)); else c=$dd; fi
    [[ "$mode" == partial && "$al" == m3 ]] && continue
    [[ "$mode" == nullcount && "$al" == o1 ]] && c=null
    [[ "$mode" == floatcount && "$al" == o1 ]] && c=2.5
    json+="${sep}\"${al}\":{\"issueCount\":${c}}"; sep=','
  done <<<"$aliases"
  printf '%s}}\n' "$json"; exit 0
fi
bre='^orgs/jikig-ai/settings/billing/usage\?year=([0-9]{4})&month=([0-9]{1,2})$'
if [[ $# -eq 2 && "$1" == api && "$2" =~ $bre ]]; then
  bm="${BASH_REMATCH[2]}"
  mode="$(cat "$MOCKD/billing_$bm" 2>/dev/null || cat "$MOCKD/billing_mode" 2>/dev/null || echo ok)"
  case "$mode" in
    401) echo "gh: Requires authentication (HTTP 401)" >&2; exit 1 ;;
    403) echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1 ;;
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    502) echo "gh: Bad Gateway (HTTP 502)" >&2; exit 1 ;;
    429) echo "gh: Too Many Requests (HTTP 429)" >&2; exit 1 ;;
    ratelimit) echo "gh: API rate limit exceeded for installation (HTTP 403)" >&2; exit 1 ;;
    secondary) echo "gh: secondary limit hit, slow down (HTTP 403)" >&2; exit 1 ;;
    late) printf '{"usageItems":[{"date":"2026-%02d-19T00:00:00Z","product":"code_quality","sku":"x","grossAmount":1,"netAmount":1},{"date":"2026-%02d-22T00:00:00Z","product":"code_quality","sku":"x","grossAmount":2,"netAmount":2}]}\n' "$bm" "$bm"; exit 0 ;;
    dated-*) printf '{"usageItems":[{"date":"%sT00:00:00Z","product":"code_quality","sku":"x","grossAmount":1,"netAmount":1}]}\n' "${mode#dated-}"; exit 0 ;;
    gn) printf '{"usageItems":[{"date":"2026-%02d-05T00:00:00Z","product":"Code Quality","sku":"x","grossAmount":10,"netAmount":4},{"date":"2026-%02d-15T00:00:00Z","product":"copilot_agent","sku":"x","grossAmount":7777.77,"netAmount":7777.77}]}\n' "$bm" "$bm"; exit 0 ;;
    garbage) echo 'not json'; exit 0 ;;
    noitems) echo '{"message":"nothing"}'; exit 0 ;;
    ok)
      other='{"date":"2026-MM-15T00:00:00Z","product":"copilot_agent","sku":"Agent Premium Requests","grossAmount":7777.77,"netAmount":7777.77}'
      case "$bm" in
        9) printf '{"usageItems":[{"date":"2026-09-22T00:00:00Z","product":"code_quality","sku":"Code Quality AI Credits","grossAmount":2.21,"netAmount":2.21},{"date":"2026-09-30T00:00:00Z","product":"code_quality","sku":"Code Quality AI Credits","grossAmount":92.1,"netAmount":92.1},%s]}\n' "${other/MM/09}" ;;
        10) printf '{"usageItems":[{"date":"2026-10-01T00:00:00Z","product":"code_quality","sku":"Code Quality AI Credits","grossAmount":100,"netAmount":100},{"date":"2026-10-19T00:00:00Z","product":"code_quality","sku":"Code Quality AI Credits","grossAmount":60.65,"netAmount":60.65},%s]}\n' "${other/MM/10}" ;;
        *) printf '{"usageItems":[%s]}\n' "${other/MM/$(printf '%02d' "$bm")}" ;;
      esac
      exit 0 ;;
  esac
fi
echo "mock gh: unexpected invocation: $*" >&2
exit 64
MOCK

mkmock() {
  N=$((N + 1))
  MOCKD="$ROOT/mock$N"
  assert_fixture_dir "$MOCKD"
  mkdir -p "$MOCKD" || fatal "mkdir failed"
  cp "$ROOT/gh.template" "$MOCKD/gh" && chmod +x "$MOCKD/gh" || fatal "mock install failed"
  : > "$MOCKD/calls"; : > "$MOCKD/bodies"
  NOW="$NOW_AFTER"; RUN_SUT="$SUT"
  issue OPEN '[]'
}
issue() { assert_fixture_dir "$MOCKD"; printf '{"state":"%s","createdAt":"2026-10-19T10:00:00Z","comments":%s}' "$1" "$2" > "$MOCKD/issue.json"; }
rawissue() { assert_fixture_dir "$MOCKD"; printf '%s' "$1" > "$MOCKD/issue.json"; }
flag() { assert_fixture_dir "$MOCKD"; printf '%s' "${2:-1}" > "$MOCKD/$1"; }
bot_comment()  { jq -cn --arg s "$SENTINEL" '[{author:{login:"github-actions"},body:("notice\n"+$s)}]'; }
bot_comment2() { jq -cn --arg s "$SENTINEL" '[{author:{login:"github-actions[bot]"},body:("notice\n"+$s)}]'; }
human_comment() { jq -cn --arg s "$SENTINEL" '[{author:{login:"someone"},body:$s}]'; }
bot_with() { jq -cn --arg s "$1" '[{author:{login:"github-actions"},body:("notice\n"+$s)}]'; }

run_with() {
  local sut="$1"; shift
  OUT=""; ERR=""; RC=0
  assert_fixture_dir "$MOCKD"
  ( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "TMPDIR=$ROOT/tmp" GH_REPO=jikig-ai/soleur "WATCH_NOW=$NOW" WATCH_CHUNK_PAUSE=0 bash "$sut" "$@" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
  RC=$?
  OUT="$(cat "$MOCKD/stdout")"; ERR="$(cat "$MOCKD/stderr")"
}
run() { run_with "$RUN_SUT" "$@"; }
posted() { grep -c '^issue comment ' "$MOCKD/calls" || true; }
ncalls() { grep -c -- "$1" "$MOCKD/calls" || true; }
body() { cat "$MOCKD/bodies"; }

# ------------------------------------------------------- Guard 1: oracle + census ----
# Recorded-argv oracle: every recorded gh call must be EXACTLY `issue view <N> --json
# state,createdAt,comments`, EXACTLY `issue comment <N> --body-file -` (no --edit-last,
# --delete-last, -R or extra argument), a GraphQL read (no mutation) or a single-path GET `api`
# call. Prints each offending line.
oracle_bad_lines() {
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      "issue view "*) [[ "$line" =~ ^issue\ view\ [0-9]+\ --json\ state,createdAt,comments$ ]] || echo "$line" ;;
      "issue comment "*) [[ "$line" =~ ^issue\ comment\ [0-9]+\ --body-file\ -$ ]] || echo "$line" ;;
      "api graphql -f query="*) case "$line" in *[Mm][Uu][Tt][Aa][Tt][Ii][Oo][Nn]*) echo "$line" ;; esac ;;
      "api "*) [[ "$line" =~ ^api\ [^-[:space:]][^[:space:]]*$ ]] || echo "$line" ;;
      *) echo "$line" ;;
    esac
  done < "$1"
}
oracle_count() { local o; o="$(oracle_bad_lines "$1/calls")"; if [[ -z "$o" ]]; then echo 0; else printf '%s\n' "$o" | wc -l | tr -d ' '; fi; }
# The recorder floor: a posting scenario must have recorded at least one read and one comment.
floor_ok() { grep -q '^issue view ' "$1/calls" && grep -q '^issue comment ' "$1/calls"; }

# The ONE static census (R5), written as an ALLOWLIST over comment-stripped text: every
# `gh issue` subcommand is `view` or `comment`; every `gh api` call is GET-shaped (no -X or
# --method other than GET, no -f/-F/--field/--raw-field/--input, except the single
# `-f query=` of a GraphQL read, and no `mutation` anywhere in the call); any other `gh` noun
# is rejected. The census ALSO flags every other way to reach the network or write to a remote
# (curl, wget, nc, git push, HTTP::Tiny / LWP in perl) and every way to reach `gh` through a
# variable (`"$GH" issue ...`, `${GH:-gh}`, `GH=gh`), because a name-based gh scan cannot see them.
CENSUS_EGRESS_RE='(^|[^[:alnum:]_.-])(curl|wget)([^[:alnum:]_]|$)|(^|[^[:alnum:]_.-])nc[[:space:]]|git[[:space:]]+push|HTTP::Tiny|LWP|\$\{?GH([^[:alnum:]_]|$)|(^|[^[:alnum:]_])GH='
census_check_call() {
  local c="$1" t
  local -a W
  read -r -a W <<<"$c"
  case "${W[1]:-}" in
    issue) [[ "${W[2]:-}" == view || "${W[2]:-}" == comment ]] || return 1 ;;
    api)
      [[ "$c" =~ [Mm][Uu][Tt][Aa][Tt][Ii][Oo][Nn] ]] && return 1
      t="$(sed -E 's/(-X|--method)[ =]GET//g' <<<"$c")"
      if [[ "${W[2]:-}" == graphql ]]; then t="$(sed -E 's/-f query=//g' <<<"$t")"; fi
      [[ " $t " =~ [[:space:]](-X[A-Za-z]*|--method|-f|-F|--field|--raw-field|--input)([[:space:]=]|$) ]] && return 1 ;;
    *) return 1 ;;
  esac
  return 0
}
CENSUS_OUT=""
census_scan() {
  local f calls call egress
  CENSUS_OUT=""
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    calls="$(grep -vE '^[[:space:]]*#' "$f" | sed -E 's/for [A-Za-z_]+ in [^;]*;//g' | grep -oE '(^|[^[:alnum:]_./-])gh[[:space:]]+[^;|&)]*' | sed -E 's/^[^g]*//' || true)"
    while IFS= read -r call; do
      [[ -n "$call" ]] || continue
      census_check_call "$call" || CENSUS_OUT+="$f: $call"$'\n'
    done <<<"$calls"
    egress="$(grep -vE '^[[:space:]]*#' "$f" | sed -E 's/for [A-Za-z_]+ in [^;]*;//g' | grep -E "$CENSUS_EGRESS_RE" || true)"
    while IFS= read -r call; do
      [[ -n "$call" ]] || continue
      CENSUS_OUT+="$f: [egress] $call"$'\n'
    done <<<"$egress"
  done
}
census_count() { census_scan "$@"; if [[ -z "$CENSUS_OUT" ]]; then echo 0; else printf '%s' "$CENSUS_OUT" | wc -l | tr -d ' '; fi; }
probe_census() { assert_fixture_dir "$ROOT"; printf '%s\n' "$1" > "$ROOT/probe.txt"; census_count "$ROOT/probe.txt"; }

# ------------------------------------------------------------ mutation machinery ----
# mutcopy NAME: a pristine copy and a to-be-mutated copy of the script and the lib in a
# scratch dir (the script finds its lib relative to itself). mutsubst TARGET FROM TO applies a
# literal one-shot substitution; MUT_LANDED is then 1 only if the mutated copy really differs
# from the pristine one (a mutation that did not land would read as a green "caught" row).
MUT_DIR=""; MUT_SUT=""; CTL_SUT=""; MUT_LANDED=0
mutcopy() {
  MUT_DIR="$ROOT/mut-$1"
  assert_fixture_dir "$MUT_DIR"
  mkdir -p "$MUT_DIR/pristine/lib" "$MUT_DIR/mut/lib" || fatal "mutcopy mkdir failed"
  cp "$SUT" "$MUT_DIR/pristine/" && cp "$LIB" "$MUT_DIR/pristine/lib/" || fatal "mutcopy cp failed"
  cp "$SUT" "$MUT_DIR/mut/" && cp "$LIB" "$MUT_DIR/mut/lib/" || fatal "mutcopy cp failed"
  CTL_SUT="$MUT_DIR/pristine/$(basename "$SUT")"; MUT_SUT="$MUT_DIR/mut/$(basename "$SUT")"; MUT_LANDED=0
}
mutsubst() {
  local f
  case "$1" in script) f="$MUT_SUT" ;; lib) f="$MUT_DIR/mut/lib/watch-notify-once.sh" ;; *) fatal "bad mutation target" ;; esac
  MUT_FROM="$2" MUT_TO="$3" perl -0pi -e 's/\Q$ENV{MUT_FROM}\E/$ENV{MUT_TO}/' "$f" || fatal "mutation perl failed"
  if ! diff -q "$MUT_DIR/pristine/lib/watch-notify-once.sh" "$MUT_DIR/mut/lib/watch-notify-once.sh" >/dev/null 2>&1 \
     || ! diff -q "$CTL_SUT" "$MUT_SUT" >/dev/null 2>&1; then MUT_LANDED=1; fi
}
obs_rcposted() { printf '%s:%s' "$RC" "$(posted)"; }
obs_viol() { if [[ "$(oracle_count "$MOCKD")" -gt 0 ]]; then printf 'VIOL'; else printf 'CLEAN'; fi; }

scen_fresh() { mkmock; NOW="$NOW_AFTER"; }
scen_bot() { mkmock; issue OPEN "$(bot_comment)"; }
scen_human() { mkmock; issue OPEN "$(human_comment)"; }
scen_junk() { mkmock; issue OPEN '["junk"]'; }
scen_before() { mkmock; NOW="$NOW_BEFORE"; }

# mut_row LABEL SCENARIO OBSERVABLE CTL_EXPECT MUT_EXPECT: control first (must be green), then
# the mutated copy must land and flip the observable.
mut_row() {
  local label="$1" scen="$2" obs="$3" want_ctl="$4" want_mut="$5" got_ctl got_mut
  "$scen"; run_with "$CTL_SUT"; got_ctl="$($obs)"
  "$scen"; run_with "$MUT_SUT"; got_mut="$($obs)"
  if [[ "$got_ctl" == "$want_ctl" ]]; then pass "$label: unmutated control is green ($got_ctl)"; else fail "$label: control expected $want_ctl got $got_ctl"; fi
  if [[ "$MUT_LANDED" -eq 1 && "$got_mut" == "$want_mut" ]]; then pass "$label: mutation landed and turns the suite RED ($got_mut)"; else fail "$label: landed=$MUT_LANDED expected $want_mut got $got_mut"; fi
}

# ======================================================================== scenarios ====
# ---- S1: the earliest gate precedes everything ----
mkmock; NOW="$NOW_BEFORE"; run
[[ "$RC" -eq 0 && "$OUT" == *"::notice::"* && ! -s "$MOCKD/calls" ]] \
  && pass "S1a before 2026-11-14: exit 0, ::notice::, ZERO gh calls (the date gate precedes the issue read)" || fail "S1a (rc=$RC out=$OUT calls=$(tr '\n' '|' < "$MOCKD/calls"))"
mkmock; NOW='2026-11-13T23:59:59Z'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && ! -s "$MOCKD/calls" ]] && pass "S1b one second before the boundary: nothing" || fail "S1b (rc=$RC)"
mkmock; NOW='2026-11-14T00:00:00Z'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S1c exactly 2026-11-14T00:00:00Z: the gate is open" || fail "S1c (rc=$RC posted=$(posted))"

# ---- S1d: the first real run posts once; every part of the body; sentinel LAST ----
mkmock; run
B="$(body)"; ok=1
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] || ok=0
[[ "$(tail -n 1 "$MOCKD/bodies")" == "$SENTINEL" ]] || ok=0
[[ "$(grep -cF -- "$SENTINEL" "$MOCKD/bodies" || true)" -eq 1 ]] || ok=0
[[ "$(grep -c -- '-->' "$MOCKD/bodies" || true)" -eq 1 && "$(grep -c -- '<!--' "$MOCKD/bodies" || true)" -eq 1 ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S1d first run after the date: exit 0, exactly one comment, the sentinel is the exact last line and the only HTML comment" || fail "S1d (rc=$RC posted=$(posted))"
floor_ok "$MOCKD" && pass "S1e the recorder floor holds on a posting scenario (a read and a comment were recorded)" || fail "S1e recorder floor"
ok=1
for needle in 'As recorded in the ADR-276 amendment of 2026-10-19' 'switched OFF on 2026-10-19' 'does not read the setting live' \
  'Code Quality half only' 'predates the ADR-276 amendment of 2026-10-19' "ADR-276's re-evaluation step (1)" 'NOT gathered here' 'ruling session runs it' \
  'cost driver' 're-enable only if (i) a consumer for the findings exists' 'a billing budget on the `code_quality` product' \
  'ADR-276' 'No ruling is made here' 'next `soleur:go` session' 'CTO agent' 'successor' 'Nothing was changed' '<details>' '</details>'; do
  [[ "$B" == *"$needle"* ]] || { ok=0; echo "  missing body text: $needle"; }
done
[[ "$ok" -eq 1 ]] && pass "S1f body carries the ADR-276 criteria, the recorded (not live) OFF state, the Code-Quality-half and step-(1)-not-gathered scoping, the PR-volume cost-driver reason, the no-ruling and successor sentences and the nothing-changed line" || fail "S1f body text"
ok=1
[[ "$B" == *"1853 opened, 1097 merged"* ]] || ok=0
[[ "$B" == *"| 2026-08-31 | 75 | 21 | 6 |"* && "$B" == *"| 2026-09-14 | 182 | 119 | 7 |"* && "$B" == *"| 2026-11-16 | 27 | 16 | 1 |"* ]] || ok=0
[[ "$B" == *"- 2026-09-01: opened 10, merged 1"* && "$B" == *"- 2026-11-16: opened 27, merged 16"* ]] || ok=0
[[ "$(ncalls '^api graphql ')" -eq 4 && "$(ncalls '^api orgs/jikig-ai/settings/billing/usage?year=')" -eq 3 ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S1g PR volume: 77 days in 4 chunks of <=20, every day present, totals 1853/1097, weekly rows and per-day lines right, 3 billing months" || fail "S1g PR volume (calls: $(tr '\n' '|' < "$MOCKD/calls" | cut -c1-300))"
# Safety of the posted text: no @ mention, no closing keyword followed by #N, no bare URL.
if [[ "$B" != *"@"* ]] && ! grep -qiE '\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\b[[:space:]:]*#[0-9]+' <<<"$B" && ! grep -qE 'https?://' <<<"$B"; then
  pass "S1h posted text: no @ mention, no closing keyword + #N, no bare URL"
else fail "S1h unsafe text in the body"; fi
# Second run with the bot's own comment present: nothing posted.
ONE_BODY="$B"
assert_fixture_dir "$MOCKD"
issue OPEN "$(jq -cn --arg b "$ONE_BODY" '[{author:{login:"github-actions"},body:$b}]')"; : > "$MOCKD/calls"; run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"already notified"* && "$(ncalls '^api ')" -eq 0 ]] \
  && pass "S1i rerun with the posted comment present: exit 0, no post, and no PR-volume/billing work done" || fail "S1i (rc=$RC posted=$(posted))"

# ---- S2: billing unreadable (401/403/404): degrade, still post, exit 0 ----
for st in 401 403 404; do
  mkmock; flag billing_mode "$st"; run
  B="$(body)"; ok=1
  [[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$ERR" == *"::warning::"* && "$OUT" != *"::warning::"* ]] || ok=0
  for mo in 09 10 11; do [[ "$ERR" == *"2026-$mo HTTP $st"* ]] || ok=0; done
  [[ "$ERR" != *"gh: "* && "$ERR" != *"Resource not accessible"* ]] || ok=0
  [[ "$B" == *"1853 opened, 1097 merged"* && "$B" == *"not readable from CI"* && "$B" == *"HTTP $st"* ]] || ok=0
  [[ "$B" == *"is not determinable (at least one month was unreadable)"* && "$B" != *"is present: "* ]] || ok=0
  for mo in 9 10 11; do [[ "$B" == *"gh api 'orgs/jikig-ai/settings/billing/usage?year=2026&month=$mo'"* ]] || ok=0; done
  [[ "$(grep -c "gh api 'orgs/jikig-ai/settings/billing/usage?year=" <<<"$B" || true)" -eq 3 ]] || ok=0
  [[ "$(tail -n 1 "$MOCKD/bodies")" == "$SENTINEL" ]] || ok=0
  [[ "$ok" -eq 1 ]] && pass "S2 billing HTTP $st: PR volume posted, 'not readable from CI' + the three commands, 'not determinable', a stderr ::warning:: carrying each month's status (no body text), exit 0" || fail "S2 HTTP $st (rc=$RC posted=$(posted))"
done
# Mixed: September readable, October not, November readable.
mkmock; flag billing_10 403; run
B="$(body)"
[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$B" == *"94.31"* && "$B" == *"month=10'"* && "$B" != *"month=9'"* && "$B" != *"month=11'"* && "$ERR" == *"::warning::"*"2026-10 HTTP 403"* && "$ERR" != *"2026-09 HTTP"* ]] \
  && pass "S2b one unreadable month: the readable months render, only the unreadable month's command is listed" || fail "S2b (rc=$RC)"
# Transient failures are NOT a degraded one-shot: retry next Monday.
for st in 502 429 ratelimit garbage noitems; do
  mkmock; flag billing_mode "$st"; run
  [[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && pass "S2c billing '$st': exit 3, nothing posted (retried next run, the one-shot is not spent)" || fail "S2c billing $st (rc=$RC posted=$(posted))"
done

# ---- S3: billing readable: code_quality aggregates only ----
mkmock; run
B="$(body)"; ok=1
[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$OUT" != *"::warning::"* && "$ERR" != *"::warning::"* ]] || ok=0
[[ "$B" == *"| 2026-09 | 2 | 94.31 | 94.31 | 2026-09-22 | 2026-09-30 |"* ]] || ok=0
[[ "$B" == *"| 2026-10 | 2 | 160.65 | 160.65 | 2026-10-01 | 2026-10-19 |"* ]] || ok=0
[[ "$B" == *'no `code_quality` line'* ]] || ok=0
[[ "$B" != *"7777.77"* && "$B" != *"copilot"* && "$B" != *"Agent Premium"* && "$B" != *"AI Credits"* && "$B" != *"not readable from CI"* ]] || ok=0
[[ "$B" == *"dated 2026-10-21 or later is present: no"* ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S3 billing 200: first/last dated lines and monthly aggregates for code_quality only, no other product, no SKU, empty month says so" || fail "S3 (rc=$RC)"

# ---- S4: a GraphQL failure or partial response posts nothing ----
mkmock; flag gql_mode fail2; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$(ncalls '^api orgs/')" -eq 0 && "$(ncalls '^api graphql ')" -eq 2 && "$ERR" != *"$SENTINEL"* ]] \
  && pass "S4a GraphQL fails on chunk 2: exit 3, no post, no sentinel, no billing work" || fail "S4a (rc=$RC posted=$(posted))"
for gm in partial errors nullcount floatcount; do
  mkmock; flag gql_mode "$gm"; run
  [[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && pass "S4b GraphQL '$gm' response: exit 3, nothing posted (never a partial result)" || fail "S4b $gm (rc=$RC posted=$(posted))"
done

# ---- S5: tracker state / comments ----
mkmock; issue CLOSED '[]'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"::notice::"* && "$OUT" == *"RETIREMENT"* && "$(ncalls '^api ')" -eq 0 ]] \
  && pass "S5a CLOSED tracker: exit 0, notice, no post, no gather work" || fail "S5a (rc=$RC)"
mkmock; flag view_fail 502; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S5b unreadable issue: exit 3, ::error::, nothing posted" || fail "S5b (rc=$RC)"
mkmock; rawissue '{"state":"OPEN","createdAt":"2026-10-19T10:00:00Z","comments":null}'; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && pass "S5c comments null: exit 3, nothing posted" || fail "S5c (rc=$RC posted=$(posted))"
mkmock; rawissue '{"createdAt":"2026-10-19T10:00:00Z","comments":[]}'; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && pass "S5d an issue view without .state: exit 3" || fail "S5d (rc=$RC)"
scen_junk; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S5e malformed comment entries (jq failure in the sentinel reader): exit 3, never read as 'absent'" || fail "S5e (rc=$RC posted=$(posted))"
mkmock; flag view_fail gone; run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"tracker gone"* ]] && pass "S5f a tracker that no longer resolves: terminal notice, exit 0" || fail "S5f (rc=$RC out=$OUT)"
mkmock; flag comment_fail; run
[[ "$RC" -eq 1 && "$(posted)" -eq 1 && "$ERR" == *"::error::"* ]] && pass "S5g failed post: exit 1 with ::error:: (no sentinel exists without the comment)" || fail "S5g (rc=$RC posted=$(posted))"

# ---- S14: every exit-3 scenario prints an ::error:: line that names a cause (never a silent red run) ----
exit3_row() {
  local label="$1" re="$2"
  if [[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && grep -qE "^::error::.*($re)" <<<"$ERR"; then pass "S14 $label: exit 3 with an ::error:: naming the cause ($re)"
  else fail "S14 $label: rc=$RC posted=$(posted) err=$(printf '%s' "$ERR" | head -c 300)"; fi
}
for spec in '502|HTTP 502' '429|HTTP 429' 'ratelimit|rate limited' 'secondary|rate limited' 'garbage|unexpected shape' 'noitems|unexpected shape'; do
  mkmock; flag billing_mode "${spec%%|*}"; run; exit3_row "billing ${spec%%|*}" "${spec#*|}"
done
mkmock; flag gql_mode fail2; run; exit3_row "graphql HTTP 403 on chunk 2" 'PR-volume.*HTTP 403'
for gm in partial errors nullcount floatcount; do
  mkmock; flag gql_mode "$gm"; run; exit3_row "graphql $gm" 'PR-volume.*unexpected response shape'
done
mkmock; flag view_fail 502; run; exit3_row "tracker read 502" 'could not read #9730.*HTTP 502'
mkmock; rawissue '{"state":"OPEN","createdAt":"2026-10-19T10:00:00Z","comments":null}'; run; exit3_row "comments null" 'could not read #9730'
scen_junk; run; exit3_row "malformed comments" 'could not evaluate the comments'

# ---- S15: year rollover (Jan 2027 still reads Sep-Dec 2026 and the new year) ----
mkmock; NOW='2027-01-18T09:17:00Z'; run
B="$(body)"; ok=1
[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(ncalls '^api orgs/jikig-ai/settings/billing/usage?year=')" -eq 5 && "$(ncalls '^api graphql ')" -eq 7 ]] || ok=0
for ym in 'year=2026&month=9' 'year=2026&month=10' 'year=2026&month=11' 'year=2026&month=12' 'year=2027&month=1'; do grep -qF -- "usage?$ym" "$MOCKD/calls" || { ok=0; echo "  missing request: $ym"; }; done
for t in 2026-09 2026-10 2026-11 2026-12 2027-01; do [[ "$B" == *"| $t |"* ]] || { ok=0; echo "  missing month row: $t"; }; done
[[ "$B" == *"(140 days)"* && "$B" == *"- 2027-01-18: opened"* && "$B" == *"- 2026-12-31: opened"* ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S15 year rollover: 5 billing months (2026-09..2027-01, year=2027&month=1 requested), 140 days in 7 chunks, December and January rows present" || fail "S15 year rollover (rc=$RC posted=$(posted) calls=$(grep -c . "$MOCKD/calls"))"

# ---- S16: tracker gone via HTTP 404 and HTTP 410 ----
for st in 404 410; do
  mkmock; flag view_fail "$st"; run
  [[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"::notice::tracker #9730 no longer resolves"* && "$(ncalls '^api ')" -eq 0 ]] \
    && pass "S16 'gh issue view' HTTP $st: terminal notice, exit 0, no post, no gather work" || fail "S16 HTTP $st (rc=$RC out=$OUT)"
done

# ---- S17: a comment whose body is null must not abort the sentinel reader ----
mkmock; issue OPEN '[{"author":{"login":"github-actions"},"body":null},{"author":null,"body":"x"}]'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S17 a null comment body and a null author: no abort, no false suppression, the notice posts" || fail "S17 (rc=$RC posted=$(posted))"

# ---- S18: billing aggregation pins ----
mkmock; flag billing_9 gn; run
B="$(body)"
[[ "$RC" -eq 0 && "$B" == *"| 2026-09 | 1 | 10 | 4 | 2026-09-05 | 2026-09-05 |"* && "$B" != *"7777.77"* && "$B" != *"copilot"* ]] \
  && pass "S18a a product spelled 'Code Quality' (space) is aggregated; gross (10) and net (4) are distinct columns; the other product stays out" || fail "S18a (rc=$RC)"
mkmock; flag billing_mode secondary; run
[[ "$RC" -eq 3 && "$(posted)" -eq 0 ]] && pass "S18b a 403 whose stderr says only 'secondary' is a rate limit: exit 3, nothing posted" || fail "S18b (rc=$RC posted=$(posted))"

# ---- S19: the switch-off verdict ----
verdict_of() { local b; b="$(body)"; case "$b" in *"is not determinable"*) printf nd ;; *"is present: yes"*) printf yes ;; *"is present: no"*) printf no ;; *) printf none ;; esac; }
mkmock; flag billing_10 late; run
B="$(body)"
[[ "$RC" -eq 0 && "$(verdict_of)" == yes && "$B" == *"is present: yes (latest 2026-10-22)"* && "$B" != *"is present: no"* ]] \
  && pass "S19a a code_quality line dated 2026-10-22: verdict yes with the latest date" || fail "S19a (verdict=$(verdict_of))"
mkmock; flag billing_10 dated-2026-10-20; run
[[ "$RC" -eq 0 && "$(verdict_of)" == no ]] && pass "S19b a line dated 2026-10-20 (covers usage up to the switch-off) is NOT after the stop: verdict no" || fail "S19b (verdict=$(verdict_of))"
mkmock; flag billing_10 dated-2026-10-21; run
[[ "$RC" -eq 0 && "$(verdict_of)" == yes && "$(body)" == *"is present: yes (latest 2026-10-21)"* ]] && pass "S19c a line dated exactly 2026-10-21 IS on the stop day: verdict yes (boundary)" || fail "S19c (verdict=$(verdict_of))"
mkmock; flag billing_10 404; flag billing_11 404; run
B="$(body)"
[[ "$RC" -eq 0 && "$(posted)" -eq 1 && "$(verdict_of)" == nd && "$B" != *"is present: "* && "$B" == *"| 2026-09 | 2 | 94.31 |"* ]] \
  && pass "S19d September readable, October and November 404: 'not determinable', never 'no'" || fail "S19d (verdict=$(verdict_of))"
mkmock; run
[[ "$(verdict_of)" == no ]] && pass "S19e all months readable and clean: verdict no" || fail "S19e (verdict=$(verdict_of))"

# ---- S11: xtrace refusal precedes the lib and any gh call ----
mkmock
TOKEN="gh""p_""0123456789abcdefghijklmnopqrstuvwxyzAB"
assert_fixture_dir "$MOCKD"
( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "TMPDIR=$ROOT/tmp" "GH_TOKEN=$TOKEN" "WATCH_NOW=$NOW_AFTER" bash -x "$SUT" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
RC=$?; ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"refusing to run under xtrace"* && ! -s "$MOCKD/calls" && "$ERR" != *"$TOKEN"* && "$ERR" != *"watch-notify-once"* ]] \
  && pass "S11 bash -x with a token set: exit 78, no gh call, token not echoed, the lib was never sourced" || fail "S11 (rc=$RC err=$ERR)"
# Structural pin: the refusal sits above the `source` of the lib.
l_x="$(grep -n 'case "\$-" in' "$SUT" | head -n 1 | cut -d: -f1)"; l_src="$(grep -nE '^\. .*watch-notify-once\.sh' "$SUT" | head -n 1 | cut -d: -f1)"
[[ -n "$l_x" && -n "$l_src" && "$l_x" -lt "$l_src" ]] && pass "S11b the xtrace refusal is above the library source line" || fail "S11b (xtrace line '$l_x', source line '$l_src')"

# ---- S12: --dry-run ----
mkmock; NOW="$NOW_BEFORE"; issue CLOSED "$(bot_comment)"; run --dry-run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$(ncalls '^issue comment ')" -eq 0 && "$(ncalls '^issue view ')" -eq 1 && "$OUT" == *"dry-run: nothing posted, no sentinel spent"* && "$OUT" == *"1775 opened, 1052 merged"* \
   && "$OUT" == *"dry-run: tracker #9730 state=CLOSED; sentinel already present"* && "$OUT" == *"Nothing was changed"* && "$OUT" != *"::notice::"* ]] \
  && pass "S12a --dry-run before the date on a CLOSED tracker: the would-be body is printed, the read-only tracker read + sentinel info line appear, ZERO issue comment calls (the gate is skipped), no sentinel spent" || fail "S12a (rc=$RC out=$(printf '%s' "$OUT" | tail -n 3))"
[[ "$(tail -n 2 "$MOCKD/stdout" | head -n 1)" == "$SENTINEL" ]] && pass "S12b the printed would-be body ends with the sentinel line" || fail "S12b"
assert_fixture_dir "$MOCKD"
mkmock; NOW="$NOW_BEFORE"; ( cd "$ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" "TMPDIR=$ROOT/tmp" WN_DRY_RUN=1 "WATCH_NOW=$NOW_BEFORE" bash "$SUT" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
RC=$?; OUT="$(cat "$MOCKD/stdout")"
[[ "$RC" -eq 0 && "$OUT" == *"::notice::"* && "$OUT" != *"dry-run:"* && ! -s "$MOCKD/calls" ]] \
  && pass "S12c an inherited WN_DRY_RUN=1 without the flag does not enable dry-run (the date gate still applies)" || fail "S12c (rc=$RC out=$OUT)"
# Dry-run on an OPEN tracker with no sentinel: info line says absent; a failing tracker read is non-fatal.
mkmock; run --dry-run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"dry-run: tracker #9730 state=OPEN; sentinel absent"* && "$(tail -n 2 "$MOCKD/stdout" | head -n 1)" == "$SENTINEL" && "$OUT" == *"### GitHub Code Quality re-evaluation data"* ]] \
  && pass "S12f --dry-run on an OPEN tracker: sentinel-absent info line, the full would-be body, the sentinel last, zero comment calls" || fail "S12f (rc=$RC posted=$(posted))"
mkmock; flag view_fail 502; run --dry-run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 && "$OUT" == *"::warning::dry-run: could not read #9730 (HTTP 502)"* && "$OUT" == *"dry-run: nothing posted, no sentinel spent"* ]] \
  && pass "S12g --dry-run with an unreadable tracker: non-fatal ::warning:: naming the status, body still printed, nothing posted" || fail "S12g (rc=$RC out=$(printf '%s' "$OUT" | head -c 300))"
mkmock; run --bogus
[[ "$RC" -eq 2 && ! -s "$MOCKD/calls" && "$ERR" == *"usage:"* ]] && pass "S12d an unknown flag: exit 2 with usage, no gh call" || fail "S12d (rc=$RC err=$ERR)"
mkmock; run --dry-run extra
[[ "$RC" -eq 2 && ! -s "$MOCKD/calls" ]] && pass "S12e extra arguments: exit 2" || fail "S12e (rc=$RC)"

# ---- S13: sentinel hygiene (Guard 2 harness rows) ----
scen_human; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S13a a human-authored full sentinel never suppresses" || fail "S13a (rc=$RC posted=$(posted))"
scen_bot; run
a="$(posted)"; rc1="$RC"
mkmock; issue OPEN "$(bot_comment2)"; run
[[ "$a" -eq 0 && "$rc1" -eq 0 && "$(posted)" -eq 0 && "$RC" -eq 0 ]] && pass "S13b github-actions and github-actions[bot] (REST spelling) both suppress" || fail "S13b (first=$a second=$(posted))"
mkmock; issue OPEN "$(bot_with '<!-- code-quality-followups-watch:reeval-9730:v10 -->')"; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S13c a prefix-colliding key (v10) does not suppress v1" || fail "S13c (posted=$(posted))"
mkmock; issue OPEN "$(bot_with '<!-- code-quality-followups-watch:reeval-10515:v1 -->')"; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S13d another tracker's bot sentinel does not suppress" || fail "S13d (posted=$(posted))"
mkmock; issue OPEN "$(bot_with '<!-- other-watch:reeval-9730:v1 -->')"; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S13e a foreign namespace does not suppress" || fail "S13e (posted=$(posted))"
mkmock; issue OPEN '[{"author":{"login":"someone"},"body":"hello"},{"author":{"login":"github-actions"},"body":"x\n'"$SENTINEL"'"}]'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 0 ]] && pass "S13f the bot sentinel in a non-first comment still suppresses (every comment is read)" || fail "S13f (posted=$(posted))"
mkmock; issue OPEN '[{"author":{"login":"github-actions-fan"},"body":"'"$SENTINEL"'"}]'; run
[[ "$RC" -eq 0 && "$(posted)" -eq 1 ]] && pass "S13g a login that merely starts with the bot's does not suppress" || fail "S13g (posted=$(posted))"

# ===================================================== Guard 1: oracle and census ====
bad_total=0; calls_total=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  calls_total=$((calls_total + $(wc -l < "$d/calls")))
  bad_total=$((bad_total + $(oracle_count "$d")))
done
[[ "$bad_total" -eq 0 && "$calls_total" -gt 100 ]] \
  && pass "G1a every recorded gh call in every scenario ($calls_total calls) is issue view / issue comment / GET api / GraphQL read" || fail "G1a ($bad_total offending of $calls_total)"

# Oracle self-test: it must reject each write shape and accept the read shapes.
assert_fixture_dir "$ROOT"
printf '%s\n' 'issue close 9730' 'issue edit 9730 --add-label x' 'api -X POST repos/x' 'api orgs/x -f a=b' 'api graphql -f query=mutation { x }' 'label create x' 'pr merge 1' \
  'issue comment 9730 --edit-last' 'issue comment 9730 --delete-last' 'issue comment 9730 --body-file - -R other/repo' 'issue comment 9730 --body-file - extra' \
  'issue comment 9730 --body x' 'issue comment abc --body-file -' 'issue comment 9730 --body-file - --edit-last' 'issue view 9730 --json state --web' > "$ROOT/orc.bad"
assert_fixture_dir "$ROOT"
printf '%s\n' 'issue view 9730 --json state,createdAt,comments' 'issue comment 9730 --body-file -' 'api orgs/jikig-ai/settings/billing/usage?year=2026&month=9' 'api graphql -f query=query { viewer { login } }' > "$ROOT/orc.ok"
[[ "$(oracle_bad_lines "$ROOT/orc.bad" | wc -l | tr -d ' ')" -eq 15 && -z "$(oracle_bad_lines "$ROOT/orc.ok")" ]] \
  && pass "G1b oracle self-test: all 15 write/variant shapes rejected (the comment argv is pinned exactly: --edit-last, --delete-last, -R, extras, a non-numeric N), all 4 read shapes accepted" || fail "G1b oracle self-test"

# Static census: real sources. Files that do not exist yet (sibling watchers, workflow) are skipped.
CENSUS_FILES=("$LIB" "$SUT")
for f in "$SCRIPT_DIR"/watch-*-reeval-*.sh "$SCRIPT_DIR"/watch-*-triggers-*.sh; do
  [[ -f "$f" && "$f" != *.test.sh && "$f" != "$SUT" ]] && CENSUS_FILES+=("$f")
done
[[ -f "$WF" ]] && CENSUS_FILES+=("$WF")
c="$(census_count "${CENSUS_FILES[@]}")"
[[ "$c" -eq 0 ]] && pass "G1c static allowlist census over the lib, the script, ${#CENSUS_FILES[@]} files in all: no forbidden gh verb, flag or mutation" || fail "G1c census found: $(printf '%s' "$CENSUS_OUT" | tr '\n' '|')"

# Census self-test row: it MUST be able to fail.
cbad=0; cprobe=0
for probe in 'gh issue close 1' 'gh issue edit 1 --add-label x' 'gh issue reopen 1' 'gh issue delete 1' 'gh issue lock 1' 'gh issue pin 1' 'gh label create x' \
  'gh pr merge 1' 'gh repo edit --visibility public' 'gh api -X POST repos/x' 'gh api --method PATCH repos/x' 'gh api repos/x -f a=b' 'gh api repos/x --field a=b' \
  'gh api repos/x --raw-field a=b' 'gh api repos/x --input f' "gh api graphql -f query='mutation { x }'" 'gh api -XDELETE repos/x' 'gh workflow run x' 'x=$(gh issue close 1)' \
  'curl -X POST https://api.github.com/repos/x/issues/1/comments' 'x=$(curl -s https://example.invalid)' 'wget -qO- http://example.invalid' '/usr/bin/curl http://example.invalid' \
  'nc example.invalid 80' 'git push origin HEAD' 'perl -MHTTP::Tiny -e 1' 'perl -MLWP::UserAgent -e 1' \
  '"$GH" issue close 1' '${GH:-gh} issue close 1' 'GH=gh' '$GH api -X POST repos/x' 'echo hi && GH=gh'; do
  cprobe=$((cprobe + 1))
  [[ "$(probe_census "$probe")" -ge 1 ]] || { cbad=$((cbad + 1)); echo "  census let through: $probe"; }
done
[[ "$cbad" -eq 0 ]] && pass "G1d census self-test: all $cprobe forbidden shapes (gh writes, curl, wget, nc, git push, HTTP::Tiny, LWP, gh through a variable) are flagged (the census can fail)" || fail "G1d census missed $cbad of $cprobe forbidden shapes"
cok=0; cprobe=0
for probe in 'gh issue view 1 --json state' 'gh issue comment 1 --body-file -' "gh api 'orgs/o/settings/billing/usage?year=2026&month=9'" \
  "gh api graphql -f query='query { viewer { login } }'" 'gh api -X GET repos/x' '# gh issue close 1' '  for t in gh jq perl git; do' \
  '# curl http://example.invalid' 'git log --oneline -n 3' 'git -C "$d" rev-parse HEAD' 'echo "GH_TOKEN is injected"' 'GH_TOKEN=x' 'sync --all' 'func_nc() { :; }' 'perl -e "print 1"' 'echo "$GH_REPO"'; do
  cprobe=$((cprobe + 1))
  [[ "$(probe_census "$probe")" -eq 0 ]] || { cok=$((cok + 1)); echo "  census false positive: $probe"; }
done
[[ "$cok" -eq 0 ]] && pass "G1e census must-PASS non-canonical inputs: a read-only graphql query, an explicit GET, comments, the preflight for-loop, plain git reads, GH_TOKEN/GH_REPO names stay clean" || fail "G1e census false positives: $cok of $cprobe"

# Guard 1 mutation rows: #1 (close after the post), #5 (graphql mutation), #6 (-f on a plain api call).
mutcopy g1m1; mutsubst script 'exit "$rc"' 'gh issue close "$TRACKER" >/dev/null 2>&1
exit "$rc"'
mut_row "G1#1 gh issue close after the post" scen_fresh obs_viol CLEAN VIOL
[[ "$(census_count "$CTL_SUT")" -eq 0 && "$(census_count "$MUT_SUT")" -ge 1 ]] && pass "G1#1 the census also flags the mutated script (control clean)" || fail "G1#1 census"
mutcopy g1m5; mutsubst script 'exit "$rc"' "gh api graphql -f query='mutation { addComment(input: {}) { clientMutationId } }' >/dev/null 2>&1
exit \"\$rc\""
mut_row "G1#5 graphql mutation call" scen_fresh obs_viol CLEAN VIOL
[[ "$(census_count "$CTL_SUT")" -eq 0 && "$(census_count "$MUT_SUT")" -ge 1 ]] && pass "G1#5 the census also flags the mutated script (control clean)" || fail "G1#5 census"
mutcopy g1m6; mutsubst script 'exit "$rc"' 'gh api orgs/jikig-ai/settings/billing/usage -f year=2026 >/dev/null 2>&1
exit "$rc"'
mut_row "G1#6 non-graphql gh api with -f" scen_fresh obs_viol CLEAN VIOL
[[ "$(census_count "$CTL_SUT")" -eq 0 && "$(census_count "$MUT_SUT")" -ge 1 ]] && pass "G1#6 the census also flags the mutated script (control clean)" || fail "G1#6 census"
# A read-only variant that adds a gh api graphql QUERY call must stay GREEN (oracle and census).
mutcopy g1ok; mutsubst script 'exit "$rc"' "gh api graphql -f query='query { viewer { login } }' >/dev/null 2>&1
exit \"\$rc\""
scen_fresh; run_with "$MUT_SUT"
[[ "$MUT_LANDED" -eq 1 && "$(obs_viol)" == CLEAN && "$(census_count "$MUT_SUT")" -eq 0 ]] \
  && pass "G1 must-PASS non-canonical: a variant adding a read-only graphql query stays GREEN" || fail "G1 read-only variant (landed=$MUT_LANDED oracle=$(obs_viol))"
# #2: the recording dispatch is dead -> the recorder floor must go RED.
scen_fresh; run
floor_ok "$MOCKD" && ctl_floor=ok || ctl_floor=dead
mkmock; assert_fixture_dir "$MOCKD"; sed '/# LOGLINE/d' "$ROOT/gh.template" > "$MOCKD/gh"; chmod +x "$MOCKD/gh"
if cmp -s "$ROOT/gh.template" "$MOCKD/gh"; then dead_landed=0; else dead_landed=1; fi
run
[[ "$ctl_floor" == ok && "$dead_landed" -eq 1 && "$(posted)" -eq 0 ]] && ! floor_ok "$MOCKD" \
  && pass "G1#2 a mock that logs nothing: the recorder floor (one read, one comment per posting scenario) goes RED while the control is green" || fail "G1#2 (ctl=$ctl_floor landed=$dead_landed)"

# The workflow facets of Guard 1 (per-job permissions, the `if:` guard, the run step). They PARSE the
# workflow with PyYAML; an absent workflow file or an unavailable PyYAML FAILS (never skips).
assert_fixture_dir "$ROOT"
cat > "$ROOT/wfcheck.py" <<'PY'
import sys
try:
    import yaml
except ImportError:
    print("PyYAML is not importable")
    sys.exit(3)
facet, path = sys.argv[1], sys.argv[2]
doc = yaml.safe_load(open(path)) or {}
jobs = doc.get("jobs") or {}
want = {"contents": "read", "issues": "write"}
guard = "github.repository == 'jikig-ai/soleur' && (github.event_name == 'schedule' || github.ref == format('refs/heads/{0}', github.event.repository.default_branch))"
bad = []
if "reeval-9730" not in jobs:
    bad.append("job reeval-9730 is missing")
if facet == "perms":
    if doc.get("permissions") != {}:
        bad.append("workflow-level permissions is %r, want {}" % (doc.get("permissions"),))
    for name, job in jobs.items():
        if not isinstance(job, dict) or job.get("permissions") != want:
            bad.append("job %s permissions is %r, want %r" % (name, (job or {}).get("permissions") if isinstance(job, dict) else job, want))
elif facet == "if":
    for name, job in jobs.items():
        cond = " ".join(str(job.get("if", "")).split()) if isinstance(job, dict) else ""
        if cond != guard:
            bad.append("job %s if: is %r" % (name, cond))
elif facet == "runs":
    steps = (jobs.get("reeval-9730") or {}).get("steps") or []
    if not any("watch-code-quality-reeval-9730.sh" in str(st.get("run", "")) for st in steps if isinstance(st, dict)):
        bad.append("no step of reeval-9730 runs watch-code-quality-reeval-9730.sh")
else:
    bad.append("unknown facet")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
WF_OUT=""; WF_RC=0
wf_run() { # FACET FILE [python flags]
  if [[ ! -f "$2" ]]; then WF_RC=4; WF_OUT="workflow file absent: $2"; return; fi
  WF_OUT="$(python3 "${3:--I}" "$ROOT/wfcheck.py" "$1" "$2" 2>&1)"; WF_RC=$?
}
wf_expect() { # LABEL FACET FILE: the facet must pass on the real workflow
  wf_run "$2" "$3"
  [[ "$WF_RC" -eq 0 ]] && pass "$1" || fail "$1 (rc=$WF_RC: $WF_OUT)"
}
wf_expect "G1f every workflow permissions block is exact: workflow-level {} and each job contents: read + issues: write" perms "$WF"
wf_expect "G1g every job's if: is the repository + schedule/default-branch-ref guard, verbatim" if "$WF"
wf_expect "W1 the workflow's reeval-9730 job runs this script" runs "$WF"
# Self-tests: the facets can fail. Mutated COPIES of the workflow (mutation must land: diff -q).
wf_mut() { # NAME PERL_SUBST (applied once) -> $ROOT/wfmut-NAME.yml
  assert_fixture_dir "$ROOT"
  cp "$WF" "$ROOT/wfmut-$1.yml" || fatal "wf copy failed"
  perl -0pi -e "$2" "$ROOT/wfmut-$1.yml" || fatal "wf mutation perl failed"
  ! diff -q "$WF" "$ROOT/wfmut-$1.yml" >/dev/null 2>&1
}
wf_mut toplevel 's/^permissions: \{\}/permissions: write-all/m' && wf_row_landed=1 || wf_row_landed=0
wf_run perms "$ROOT/wfmut-toplevel.yml"
[[ "$wf_row_landed" -eq 1 && "$WF_RC" -eq 1 && "$WF_OUT" == *"workflow-level"* ]] && pass "G1h mutated copy with top-level 'permissions: write-all': the permissions facet goes RED" || fail "G1h (landed=$wf_row_landed rc=$WF_RC $WF_OUT)"
wf_mut extraperm 's/^(      issues: write\n)/$1      actions: write\n/m' && wf_row_landed=1 || wf_row_landed=0
wf_run perms "$ROOT/wfmut-extraperm.yml"
[[ "$wf_row_landed" -eq 1 && "$WF_RC" -eq 1 ]] && pass "G1i mutated copy with an extra job-level permission: the permissions facet goes RED" || fail "G1i (landed=$wf_row_landed rc=$WF_RC)"
wf_mut addjob 's/\z/\n  extra-job:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n/' && wf_row_landed=1 || wf_row_landed=0
wf_run perms "$ROOT/wfmut-addjob.yml"
[[ "$wf_row_landed" -eq 1 && "$WF_RC" -eq 1 && "$WF_OUT" == *"extra-job"* ]] && pass "G1j mutated copy with an added job that has no permissions block: the permissions facet goes RED" || fail "G1j (landed=$wf_row_landed rc=$WF_RC $WF_OUT)"
wf_mut noguard "s/github\\.repository == 'jikig-ai\\/soleur' && //" && wf_row_landed=1 || wf_row_landed=0
wf_run if "$ROOT/wfmut-noguard.yml"
[[ "$wf_row_landed" -eq 1 && "$WF_RC" -eq 1 ]] && pass "G1k mutated copy with the repository condition removed from one job: the if: facet goes RED" || fail "G1k (landed=$wf_row_landed rc=$WF_RC)"
wf_run perms "$ROOT/no-such-workflow.yml"; r1=$WF_RC; wf_run if "$ROOT/no-such-workflow.yml"; r2=$WF_RC; wf_run runs "$ROOT/no-such-workflow.yml"; r3=$WF_RC
[[ "$r1" -ne 0 && "$r2" -ne 0 && "$r3" -ne 0 ]] && pass "G1l an absent workflow file FAILS every workflow facet (never skips)" || fail "G1l (rc $r1 $r2 $r3)"
wf_run perms "$WF" -IS
[[ "$WF_RC" -eq 3 && "$WF_OUT" == *"PyYAML"* ]] && pass "G1m with PyYAML unavailable the facet exits 3 (a loud FAIL in the real rows, never a skip)" || fail "G1m (rc=$WF_RC $WF_OUT)"

# ===================================================== Guard 2: notify-once rows ====
FROM_SENT='wn_sentinel_present "$key"; rc=$?'
mutcopy g2m1; mutsubst lib "$FROM_SENT" 'rc=1'
mut_row "G2#1 sentinel check deleted" scen_bot obs_rcposted "0:0" "0:1"
FROM_AUTH='((.author.login // "") == "github-actions" or (.author.login // "") == "github-actions[bot]")'
mutcopy g2m2; mutsubst lib "$FROM_AUTH" 'true'
mut_row "G2#2 any author accepted" scen_human obs_rcposted "0:1" "0:0"
mutcopy g2m4
mutsubst lib "| length' 2>/dev/null)\" || return 3" "| length' 2>/dev/null)\" || count=0"
mutsubst lib '[[ "$count" =~ ^[0-9]+$ ]] || return 3' '[[ "$count" =~ ^[0-9]+$ ]] || count=0'
mut_row "G2#4 jq failure read as absent" scen_junk obs_rcposted "3:0" "0:1"
mutcopy g2m5; mutsubst lib 'wn_reached "$earliest"; rc=$?' 'rc=0'
mut_row "G2#5 date gate removed" scen_before obs_rcposted "0:0" "0:1"
# Harness row: remove the wn_post call -> the positive posting scenario must go RED.
mutcopy g2post; mutsubst lib '| wn_post "$tracker"; then' '| cat >/dev/null; then'
mut_row "G2 harness: wn_post removed" scen_fresh obs_rcposted "0:1" "0:0"

# ---- mutation rows for the review-fix guards (each: control green, mutated copy lands and flips the observable) ----
scen_partial_bill() { mkmock; flag billing_10 404; flag billing_11 404; }
scen_late() { mkmock; flag billing_10 late; }
scen_d21() { mkmock; flag billing_10 dated-2026-10-21; }
scen_410() { mkmock; flag view_fail 410; }
scen_nullbody() { mkmock; issue OPEN '[{"author":{"login":"github-actions"},"body":null}]'; }
scen_secondary() { mkmock; flag billing_mode secondary; }
scen_gn() { mkmock; flag billing_9 gn; }
scen_gqlfail() { mkmock; flag gql_mode fail2; }
scen_b10_403() { mkmock; flag billing_10 403; }
obs_gn() { if [[ "$(body)" == *"| 2026-09 | 1 | 10 | 4 | 2026-09-05 | 2026-09-05 |"* ]]; then printf ok; else printf bad; fi; }
obs_pvcause() { if grep -qE '^::error::PR-volume search failed \(HTTP 403\)' <<<"$ERR"; then printf cause; else printf nocause; fi; }
obs_warnstatus() { if [[ "$ERR" == *"::warning::"*"2026-10 HTTP 403"* ]]; then printf status; else printf nostatus; fi; }

mutcopy v1; mutsubst script 'if [[ "$BILL_UNREADABLE" -eq 0 ]]; then' 'if true; then'
mut_row "V1 verdict emitted although a month was unreadable" scen_partial_bill verdict_of nd no
mutcopy v2; mutsubst script '! "$BILL_LATEST" < "$stop"' '"$BILL_LATEST" == never'
mut_row "V2 the yes branch forced to no" scen_late verdict_of yes no
mutcopy v3; mutsubst script '! "$BILL_LATEST" < "$stop"' '"$stop" < "$BILL_LATEST"'
mut_row "V3 stop-day comparison '>=' weakened to '>'" scen_d21 verdict_of yes no
mutcopy v4; mutsubst lib 'WN_BILLING_STOP_EXPECTED_BY=2026-10-21' 'WN_BILLING_STOP_EXPECTED_BY=2026-10-22'
mut_row "V4 the script consults the library's stop constant, not a literal" scen_d21 verdict_of yes no
mutcopy e1; mutsubst script '${http:-network or client error}' 'network or client error'
mut_row "E1 pv_chunk ::error:: drops the HTTP status" scen_gqlfail obs_pvcause cause nocause
mutcopy e2; mutsubst script 'BILL_STATUSES+="${BILL_STATUSES:+, }${tag} HTTP ${WN_BILL_STATUS#unreadable:}"' 'BILL_STATUSES+=""'
mut_row "E2 the billing ::warning:: drops the per-month status" scen_b10_403 obs_warnstatus status nostatus
mutcopy c1; mutsubst script 'CHUNK_DAYS=20' 'CHUNK_DAYS=21'
mut_row "C1 chunk size beyond 40 search aliases (mock exits 64)" scen_fresh obs_rcposted "0:1" "3:0"
mutcopy a1; mutsubst script '((.net * 100 | round) / 100), (.first' '((.gross * 100 | round) / 100), (.first'
mut_row "A1 the net column reads gross" scen_gn obs_gn ok bad
mutcopy a2; mutsubst lib 'test("code[ _-]?quality"; "i")' 'test("code_quality"; "i")'
mut_row "A2 'Code Quality' (space) no longer aggregated" scen_gn obs_gn ok bad
mutcopy l1; mutsubst lib '|*"HTTP 410"*' ''
mut_row "L1 HTTP 410 no longer means tracker gone" scen_410 obs_rcposted "0:0" "3:0"
mutcopy l2; mutsubst lib '(.body // "")' '.body'
mut_row "L2 a null comment body aborts the sentinel reader" scen_nullbody obs_rcposted "0:1" "3:0"
mutcopy l3; mutsubst lib '|*secondary*)' ')'
mut_row "L3 a 403 saying only 'secondary' read as unreadable" scen_secondary obs_rcposted "3:0" "0:1"
mutcopy o1; mutsubst lib 'gh issue comment "$n" --body-file -' 'gh issue comment "$n" --edit-last --body-file -'
mut_row "O1 the comment argv gains --edit-last (oracle pins the exact argv)" scen_fresh obs_viol CLEAN VIOL
# Census mutations: only STATIC (the mutated script is never run: it would reach the network).
mutcopy x1; mutsubst script 'exit "$rc"' 'curl -s http://example.invalid >/dev/null 2>&1
exit "$rc"'
[[ "$MUT_LANDED" -eq 1 && "$(census_count "$CTL_SUT")" -eq 0 && "$(census_count "$MUT_SUT")" -ge 1 ]] && pass "X1 a curl call added to the script: the census flags it (control clean)" || fail "X1 census curl"
mutcopy x2; mutsubst script 'exit "$rc"' 'GH=gh
"$GH" issue close "$TRACKER" >/dev/null 2>&1
exit "$rc"'
[[ "$MUT_LANDED" -eq 1 && "$(census_count "$CTL_SUT")" -eq 0 && "$(census_count "$MUT_SUT")" -ge 2 ]] && pass "X2 a gh call through a variable added to the script: the census flags the assignment and the call (control clean)" || fail "X2 census gh variable"
mutcopy x3; mutsubst lib 'wn_preflight() {' 'wn_exfil() { git push origin HEAD; }
wn_preflight() {'
[[ "$MUT_LANDED" -eq 1 && "$(census_count "$CTL_SUT" "$MUT_DIR/pristine/lib/watch-notify-once.sh")" -eq 0 && "$(census_count "$MUT_SUT" "$MUT_DIR/mut/lib/watch-notify-once.sh")" -ge 1 ]] && pass "X3 a git push added to the library: the census flags it (control clean)" || fail "X3 census git push"

# Exit-gate check (behavioural): this same suite, re-run with ONE injected failure, must
# exit EXACTLY 1. An `exit 0` placed before the gate, a reset FAIL counter, or a neutered
# exit path would all give 0 here; the FATAL below runs before any of them can.
if [[ -z "${WCQ_INJECT_FAIL:-}" ]]; then
  WCQ_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: the exit gate returned %s (expected 1) with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
# Anti-vacuity floor (ADR-193). The threshold is declared on the line IMMEDIATELY
# above the `if`, not with the other constants: guard-vacuity-floor builds its mutant
# by slicing the floor block plus the CONTIGUOUS simple assignments above it.
MIN_ASSERTIONS=125
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
finish || exit 1
