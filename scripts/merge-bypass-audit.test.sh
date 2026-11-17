#!/usr/bin/env bash
# merge-bypass-audit.test.sh — fixture-driven Guard-1 suite for scripts/merge-bypass-audit.sh
# (#12666; plan Guard-1 mutation matrix).
#
# WHAT THIS PROVES. The suite drives a COPY of the probe (never the live file — siblings may
# edit it) with a stubbed `gh` on a PRIVATE PATH prefix: no network, no credential, no real
# repo object is touched. Every Guard-1 matrix row is a behavior arm; the unread-answer rule
# (exit 2, never exit 0, never the kinder verdict) is exercised on every API read the probe
# makes, not just the check-runs read the matrix names.
#
# Guard-1 mutation matrix → arms:
#   1 merge_group success run present              → A1 (verdict=ok via=merge_group; only a
#                                                    ci.yml run counts — A5 arms the
#                                                    other-workflow rejection)
#   2 PR head required `test` conclusion failure   → A2 (verdict=bypass + issue + ::error)
#   3 PR head all-required success                 → A3 (verdict=ok via=pr_head; A3b adds the
#                                                    skipped/neutral==green attack-surface row;
#                                                    A4 arms the {name,app.id} match against a
#                                                    foreign check-app's colliding context)
#   4 empty/invalid/unreadable API bodies          → B1..B12 (exit 2 + verdict=unread each);
#                                                    B13/B14 are required-set FILE failures
#                                                    (same unread signature, upstream of any
#                                                    API read); B15..B17 the ancestry gate
#   5 open issue already names the SHA             → C5 (deduped; no second issue)
#   6 no source PR resolvable                      → C6 (verdict=bypass class=no_source_pr)
#   7 green-at-merge → red-later                   → C7 (verdict=check_flipped_after_merge,
#                                                    never bypass; C7b proves the ordering read
#                                                    is started_at-relative, not existence)
#   8 verdict function mutated to return OK always → D (the same fixture yields no bypass —
#                                                    the bypass arms discriminate)
#
# Review-fix arms on top of the matrix: B10 rework (issue-create failure -> verdict=bypass
# filed=FAILED, rc 2, never degrades to unread), C8/C8b (the deduped fixed-title unread
# notice), C9 (at_merge_state completed_after_merge), G1/G2 (extra-operand rejection).
#
# H1 (harness sabotage): a child run with pass()/fail() neutered must refuse — section F.
# SEAMS: MBA_TEST_SABOTAGE={pass|fail} for H1; STUB_STATE feeds the stub's response files.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"   # a direct run inherits /tmp (shared tmpfs); the runner defaults here

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT_SRC="$REPO_ROOT/scripts/merge-bypass-audit.sh"
ORIG_PATH="$PATH"
START_S=$SECONDS

TMP="$(mktemp -d "$TMPDIR/merge-bypass-audit.XXXXXXXX")" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0; fails=0; asserted=0
FAILS_LOG="$TMP/fails.log"; : > "$FAILS_LOG"   # append-only: the final verdict reads THIS, not only the counters
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf '  FAIL: %s\n' "$1" >&2; printf '%s\n' "$1" >> "$FAILS_LOG"; }
harness_die() { printf '[FATAL] %s\n' "$1" >&2; exit 2; }
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
assert_fixture_dir "$TMP"

# H1 (negative control for the harness itself): MBA_TEST_SABOTAGE={pass,fail} makes the named
# helper a no-op; the instrument self-test below must then refuse, so a suite whose verdict
# helpers do nothing cannot exit 0 having asserted nothing.
if [[ "${MBA_TEST_SABOTAGE:-}" == "pass" ]]; then pass() { :; }; fi
if [[ "${MBA_TEST_SABOTAGE:-}" == "fail" ]]; then fail() { :; }; fi

# INSTRUMENT SELF-TEST — drives both helpers once and requires every observable to move.
_st_p=$passes; _st_f=$fails
pass "instrument self-test (pass)" >/dev/null
fail "instrument self-test (fail)" >/dev/null
if (( passes != _st_p + 1 || fails != _st_f + 1 )); then
  printf '[FATAL] instrument self-test: pass()/fail() did not move their counters (passes %d->%d, fails %d->%d)\n' \
    "$_st_p" "$passes" "$_st_f" "$fails" >&2
  exit 1
fi
passes=$_st_p; fails=$_st_f; asserted=0; : > "$FAILS_LOG"

[[ -f "$SUT_SRC" ]] || harness_die "SUT not found: $SUT_SRC"
command -v jq >/dev/null 2>&1 || harness_die "jq is required"
command -v python3 >/dev/null 2>&1 || harness_die "python3 is required (mutation patcher)"
bash -n "$SUT_SRC" || harness_die "SUT does not parse: $SUT_SRC"

# --- the SUT copy under test --------------------------------------------------------------------
SUT_DIR="$TMP/sut"
assert_fixture_dir "$SUT_DIR"
mkdir -p "$SUT_DIR" || harness_die "cannot create $SUT_DIR"
cp "$SUT_SRC" "$SUT_DIR/merge-bypass-audit.sh" || harness_die "cannot copy SUT"
SUT="$SUT_DIR/merge-bypass-audit.sh"

# --- a small required-set fixture (3 contexts; the real canonical has 11) -----------------------
REQ_JSON="$TMP/required.json"
cat > "$REQ_JSON" <<'JSON'
[
  {"context": "test", "integration_id": 15368},
  {"context": "guards-ruleset", "integration_id": 15368},
  {"context": "quality-guards", "integration_id": 15368}
]
JSON

# --- the stubbed gh (private PATH prefix; response files are {rc}\n{stderr}\n{body}) ------------
STUB="$TMP/stub"; STUB_STATE="$TMP/state"
assert_fixture_dir "$STUB"; assert_fixture_dir "$STUB_STATE"
mkdir -p "$STUB" "$STUB_STATE" || harness_die "cannot create stub dirs"
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Fixture gh: routes on argv, serves $STUB_STATE/resp.<key> ({rc}\n{stderr}\n{body}),
# logs every argv to calls.log, refuses anything unexpected (exit 64 + refused.log), and
# records `gh issue create` argv into created.log. A MISSING response file exits 99 — an
# unmocked call is a loud stub failure, never an answer the probe can read as green.
: "${STUB_STATE:?}"
printf '%s\n' "$*" >>"$STUB_STATE/calls.log"
key=""
# Route on the VERB argv only ($1/$2) — never $*. A `--body` payload contains
# free text ("/commits/{sha}/pulls" appears in the alert body); a whole-argv
# substring match lets body text hijack routing and serve the wrong fixture.
case "${1-}" in
  api)
    case "${2-}" in
      *"/check-runs"*)    key=checkruns ;;
      *"/actions/runs?"*) key=runs ;;
      *"/compare/"*)      key=compare ;;
      *"/pulls/"*)        key=pr ;;
      *"/pulls")          key=pulls ;;
      *"/commits/"*)      key=commit ;;
      "search/issues")    key=search ;;
      repos/*)            key=repo ;;
    esac ;;
  issue) [[ "${2-}" == "create" ]] && key=create ;;
esac
if [[ -z "$key" ]]; then
  printf 'refused argv: %s\n' "$*" >>"$STUB_STATE/refused.log"
  echo "stub gh: unexpected argv: $*" >&2; exit 64
fi
f="$STUB_STATE/resp.$key"
[[ -f "$f" ]] || { echo "stub gh: no response configured for $key" >&2; exit 99; }
rc="$(sed -n '1p' "$f")"
sed -n '2p' "$f" >&2
sed -n '3,$p' "$f"
# created.log records only a SUCCESSFUL creation — a logged-but-403'd create is an
# attempt (see calls.log), not a filed issue.
[[ "$key" == "create" && "$rc" == "0" ]] && printf '%s\n' "$*" >>"$STUB_STATE/created.log"
exit "$rc"
STUBEOF
chmod +x "$STUB/gh" || harness_die "cannot chmod stub gh"

# resp <key> <rc> <stderr> <body> — one canned response.
resp() { assert_fixture_dir "$STUB_STATE"; printf '%s\n%s\n%s\n' "$2" "$3" "$4" > "$STUB_STATE/resp.$1"; }
reset_stub() {
  assert_fixture_dir "$STUB_STATE"
  rm -f "$STUB_STATE"/resp.* "$STUB_STATE/calls.log" "$STUB_STATE/created.log" "$STUB_STATE/refused.log"
}

# --- fixture shapes -----------------------------------------------------------------------------
SHA="aae21955e6f000000000000000000000000000aa"   # 40-hex; echoes the incident merge aae21955e6
HEAD="d46da3095c0000000000000000000000000000dd" # the incident PR head
MERGE_T="2026-11-11T17:33:39Z"                  # incident merge instant
T_RED="2026-11-10T20:43:00Z"                    # `test` aggregate FAILURE ~21h before merge
T_GREEN="2026-11-11T16:00:00Z"                  # a green completion before merge
T_LATE="2026-11-11T18:00:00Z"                   # a re-run started after merge
T_LATE_DONE="2026-11-11T18:30:00Z"

# cr <id> <name> <conclusion|null> <status> <started_at|null> <completed_at|null> [app_id]
# app_id defaults to 15368 (GitHub Actions) — the required-integration id every canonical
# context carries; pass another id to arm a FOREIGN check-app posting a colliding name.
cr() {
  jq -nc --argjson id "$1" --arg n "$2" --arg c "$3" --arg st "$4" --arg s "$5" --arg e "$6" \
    --argjson app "${7:-15368}" \
    '{id: $id, name: $n, status: $st, app: {id: $app},
      conclusion: (if $c == "null" then null else $c end),
      started_at: (if $s == "null" then null else $s end),
      completed_at: (if $e == "null" then null else $e end)}'
}
# checkruns_body <cr-objects...> — a {total_count, check_runs} page.
checkruns_body() { printf '%s\n' "$@" | jq -sc '{total_count: length, check_runs: .}'; }
# pull_assoc <n> <merge_sha> <head_sha> <merged_at>
pull_assoc() {
  jq -nc --argjson n "$1" --arg ms "$2" --arg h "$3" --arg ma "$4" \
    '[{number: $n, merge_commit_sha: $ms, merged_at: $ma, head: {sha: $h}}]'
}
# commit_body <subject-line> <committer-date>
commit_body() { jq -nc --arg m "$1" --arg d "$2" '{commit: {message: ($m + "\n"), committer: {date: $d}}}'; }
# pr_detail <n> <merged:true|false> <merge_commit_sha|null> <head_sha> <merged_at|null>
pr_detail() {
  jq -nc --argjson n "$1" --argjson m "$2" --arg mcs "$3" --arg h "$4" --arg ma "$5" \
    '{number: $n, merged: $m,
      merge_commit_sha: (if $mcs == "null" then null else $mcs end),
      merged_at: (if $ma == "null" then null else $ma end),
      head: {sha: $h}}'
}
# search_open_with_sha <sha> — one open issue whose title names the SHA (dedupe hit).
search_open_with_sha() {
  jq -nc --arg s "$1" '{total_count: 1, items: [{number: 42, title: ("[merge-bypass-audit] merge " + $s + " landed over a non-green required set"), body: "filed by an earlier probe run"}]}'
}
# search_open_with_title <title> — one open issue carrying the given fixed title
# (the unread-notice dedupe hit — dedupe is by the title, not a SHA).
search_open_with_title() {
  jq -nc --arg t "$1" '{total_count: 1, items: [{number: 43, title: $t, body: "filed by an earlier probe run"}]}'
}
# compare_body <status> — a compare/<sha>...main payload (`ahead` = the sha is on main).
compare_body() { jq -nc --arg st "$1" '{status: $st, ahead_by: 1, behind_by: 0, total_commits: 1}'; }

# The unread-notice title is the SUT's fixed dedupe key — the suite pins the same constant
# so a drift between script and suite cannot turn a dedupe arm into a false pass.
UNREAD_TITLE='[merge-bypass-audit] unread verdict — investigation needed'

fx_runs_empty() { resp runs 0 "" '{"total_count":0,"workflow_runs":[]}'; }
# The ancestry gate sits between the queue arm and the source-PR arm: every fixture chain
# that reaches PR resolution needs main to contain the SHA (a diverged arm overrides this
# with its own `resp compare` — last write wins).
fx_compare_ahead() { resp compare 0 "" "$(compare_body ahead)"; }
fx_pulls_incident() { resp pulls 0 "" "$(pull_assoc 12565 "$SHA" "$HEAD" "$MERGE_T")"; }
fx_checkruns_green() {
  resp checkruns 0 "" "$(checkruns_body \
    "$(cr 1 test success completed "$T_GREEN" "$T_GREEN")" \
    "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
    "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")")"
}
fx_checkruns_bypass() {
  resp checkruns 0 "" "$(checkruns_body \
    "$(cr 1 test failure completed "$T_RED" "$T_RED")" \
    "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
    "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")")"
}
fx_search_none() { resp search 0 "" '{"total_count":0,"items":[]}'; }
fx_create_ok() { resp create 0 "" "https://github.com/jikig-ai/soleur/issues/900"; }
fx_bypass() { fx_runs_empty; fx_compare_ahead; fx_pulls_incident; fx_checkruns_bypass; fx_search_none; fx_create_ok; }
fx_okdirect() { fx_runs_empty; fx_compare_ahead; fx_pulls_incident; fx_checkruns_green; }

# --- run + assert -------------------------------------------------------------------------------
OUT=""; RC=0
run_sut() {  # <sut> <arg> [ENV=VAL ...] — scrubs the env, puts the stub first on PATH
  local sut="$1" arg="$2"; shift 2
  OUT="$(env -i HOME="$TMP" PATH="$STUB:$ORIG_PATH" STUB_STATE="$STUB_STATE" \
        MBA_REPO=jikig-ai/soleur MBA_REQUIRED_JSON="$REQ_JSON" "$@" \
        timeout 120 bash "$sut" "$arg" 2>&1)"
  RC=$?
}
run_sut_argv() {  # <sut> <arg...> — same scrub as run_sut but every arg reaches the SUT
  local sut="$1"; shift
  OUT="$(env -i HOME="$TMP" PATH="$STUB:$ORIG_PATH" STUB_STATE="$STUB_STATE" \
        MBA_REPO=jikig-ai/soleur MBA_REQUIRED_JSON="$REQ_JSON" \
        timeout 120 bash "$sut" "$@" 2>&1)"
  RC=$?
}
expect_rc()    { if [[ "$RC" == "$2" ]]; then pass "$1"; else fail "$1 (rc=$RC, want $2): ${OUT:0:300}"; fi; }
expect_out()   { case "$OUT" in *"$2"*) pass "$1" ;; *) fail "$1 (output lacks '$2'): ${OUT:0:300}" ;; esac; }
expect_noout() { case "$OUT" in *"$2"*) fail "$1 (output must not contain '$2')" ;; *) pass "$1" ;; esac; }
expect_filed()   { if [[ -s "$STUB_STATE/created.log" ]]; then pass "$1"; else fail "$1 (no issue was created)"; fi; }
expect_nofiled() { if [[ ! -f "$STUB_STATE/created.log" ]]; then pass "$1"; else fail "$1 (an issue was filed: $(cat "$STUB_STATE/created.log"))"; fi; }
# No LABELED bypass alert filed — an unread verdict may legitimately file the unlabeled
# unread-notice issue, so the unread signature asserts the ALERT never happened, not the
# weaker "nothing was created".
expect_noalert() { if [[ ! -f "$STUB_STATE/created.log" ]] || ! grep -qF 'compliance/critical' "$STUB_STATE/created.log"; then pass "$1"; else fail "$1 (a compliance/critical alert was filed: $(cat "$STUB_STATE/created.log"))"; fi; }
expect_clean()   { if [[ ! -s "$STUB_STATE/refused.log" ]]; then pass "$1"; else fail "$1 (stub refused an argv: $(head -n 1 "$STUB_STATE/refused.log"))"; fi; }
expect_called()  { if grep -qF "$2" "$STUB_STATE/calls.log" 2>/dev/null; then pass "$1"; else fail "$1 (no call matching '$2')"; fi; }

# unread_case <label> — the shared row-4 signature: exit 2, the ::error annotation, the
# verdict=unread line, and NO labeled bypass alert (never the kinder verdict).
unread_case() {
  run_sut "$SUT" "$SHA"
  expect_rc "$1 -> exit 2" 2
  expect_out "$1 -> ::error::merge-bypass-audit annotation" "::error::merge-bypass-audit"
  expect_out "$1 -> verdict=unread" "verdict=unread"
  expect_noalert "$1 -> no compliance/critical alert filed on an unread answer"
}

# =================================================================================================
# A — verdict classes on the pristine copy (rows 1-3)
# =================================================================================================
printf '\nA. verdict classes\n'

reset_stub
resp runs 0 "" '{"total_count":1,"workflow_runs":[{"conclusion":"success","event":"merge_group","path":".github/workflows/ci.yml"}]}'
run_sut "$SUT" "$SHA"
expect_rc "A1: merge_group success -> rc 0" 0
expect_out "A1: verdict ok" "verdict=ok"
expect_out "A1: queue authority named" "via=merge_group"
expect_nofiled "A1: no issue filed"
expect_clean "A1: no refused argv"

# A failed merge_group run confers NO queue authority — the probe falls through to the PR path.
reset_stub
resp runs 0 "" '{"total_count":1,"workflow_runs":[{"conclusion":"failure","event":"merge_group","path":".github/workflows/ci.yml"}]}'
fx_compare_ahead; fx_pulls_incident; fx_checkruns_green
run_sut "$SUT" "$SHA"
expect_rc "A1b: failed merge_group run falls through -> rc 0" 0
expect_out "A1b: verdict comes from the PR head" "via=pr_head"
expect_clean "A1b: no refused argv"

reset_stub; fx_bypass
run_sut "$SUT" "$SHA"
expect_rc "A2: red required test at merge -> rc 1" 1
expect_out "A2: verdict bypass" "verdict=bypass"
expect_out "A2: ::error annotation" "::error::merge-bypass-audit"
expect_filed "A2: an issue was filed"
if grep -qF 'compliance/critical' "$STUB_STATE/created.log"; then pass "A2: issue carries the compliance/critical label"; else fail "A2: issue carries the compliance/critical label"; fi
if grep -qF "$SHA" "$STUB_STATE/created.log"; then pass "A2: issue names the merge SHA (dedupe key)"; else fail "A2: issue names the merge SHA (dedupe key)"; fi
if grep -qF '"context":"test"' "$STUB_STATE/created.log"; then pass "A2: issue names the offending context"; else fail "A2: issue names the offending context"; fi
expect_called "A2: the ancestry gate read compare/<sha>...main" "/compare/"
expect_called "A2: the source PR head check-runs were read" "/check-runs?"
expect_clean "A2: no refused argv"

reset_stub; fx_okdirect
run_sut "$SUT" "$SHA"
expect_rc "A3: compliant direct merge -> rc 0" 0
expect_out "A3: verdict ok" "verdict=ok"
expect_out "A3: via PR head" "via=pr_head"
expect_nofiled "A3: no issue filed"
expect_clean "A3: no refused argv"

# skipped/neutral are green by GitHub's own semantics (attack surface row e).
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test skipped completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 2 guards-ruleset neutral completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")")"
run_sut "$SUT" "$SHA"
expect_rc "A3b: skipped+neutral count as green -> rc 0" 0
expect_out "A3b: verdict ok" "verdict=ok"
expect_nofiled "A3b: no issue filed"

# A FOREIGN check-app (app.id != 15368) posting a colliding required context name must not
# enter the ordering read. Run 9 would be selected as latest-at-merge (higher id at the
# same started_at) and reads FAILURE — if the foreign run were counted, this arms a false
# bypass; the {name, app.id} match keeps the verdict `ok via=pr_head`.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 9 test failure completed "$T_GREEN" "$T_GREEN" 777777)")"
run_sut "$SUT" "$SHA"
expect_rc "A4: foreign check-app's colliding context ignored -> rc 0" 0
expect_out "A4: verdict ok" "verdict=ok"
expect_out "A4: via PR head" "via=pr_head"
expect_noout "A4: the foreign run must not flip the verdict" "verdict=bypass"
expect_nofiled "A4: no issue filed"

# A merge_group SUCCESS from a non-battery workflow is not queue authority: with no ci.yml
# group success on the sha and no source PR, it must fall through to the source-PR arm —
# here it resolves the incident PR and reads the green head as `ok via=pr_head`.
reset_stub
resp runs 0 "" '{"total_count":1,"workflow_runs":[{"conclusion":"success","event":"merge_group","path":".github/workflows/other.yml"}]}'
fx_compare_ahead; fx_pulls_incident; fx_checkruns_green
run_sut "$SUT" "$SHA"
expect_rc "A5: other-workflow merge_group success is not queue authority -> rc 0" 0
expect_out "A5: verdict ok" "verdict=ok"
expect_noout "A5: must NOT classify via the queue arm" "via=merge_group"
expect_out "A5: falls through to the source-PR arm" "via=pr_head"
expect_clean "A5: no refused argv"

# =================================================================================================
# B — the unread-answer rule (row 4): every API read that cannot establish the answer exits 2
# =================================================================================================
printf '\nB. unread answers\n'

reset_stub
resp runs 1 "gh: Server Error (HTTP 500)" ""
unread_case "B1: actions/runs API error"

reset_stub
resp runs 0 "" "<html>not json</html>"
unread_case "B2: actions/runs invalid body"

reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" "definitely not json"
unread_case "B3: commits/pulls invalid body"

reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" '[]'
resp commit 0 "" "junk"
unread_case "B4: commit body invalid on the no-association path"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "not-json"
unread_case "B5: check-runs invalid body"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" '{}'
unread_case "B6: check-runs body missing the array"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" ""
unread_case "B7: check-runs empty body"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
# total_count says 200, every page serves one run: after MAX_PAGES the answer is still
# truncated — unread, never a verdict off a partial check-run set.
resp checkruns 0 "" "$(jq -nc --argjson r "$(cr 1 test success completed "$T_GREEN" "$T_GREEN")" '{total_count: 200, check_runs: [$r]}')"
unread_case "B8: check-runs truncated pagination"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident; fx_checkruns_bypass
resp search 0 "" "not-json"
unread_case "B9: dedupe search invalid body on the bypass path"

# A failed issue-create does NOT degrade the verdict to unread: the BYPASS classification
# survives as filed=FAILED on exit 2 (the alert attempt precedes the failure).
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident; fx_checkruns_bypass; fx_search_none
resp create 1 "gh: Forbidden (HTTP 403)" ""
run_sut "$SUT" "$SHA"
expect_rc "B10: issue create failure -> exit 2" 2
expect_out "B10: verdict stays bypass" "verdict=bypass"
expect_out "B10: filed=FAILED keeps the classification" "filed=FAILED"
expect_out "B10: ::error annotation" "::error::merge-bypass-audit"
expect_noout "B10: never degrades to unread" "verdict=unread"
expect_called "B10: the probe DID attempt the alert before the verdict" "issue create"
expect_noalert "B10: no issue was actually filed"

reset_stub
unread_case "B11: no stub response at all (unmocked read)"

reset_stub; fx_okdirect
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed null "$T_GREEN")")"
unread_case "B12: a required context with null started_at is unorderable"

reset_stub; fx_runs_empty
run_sut "$SUT" "$SHA" MBA_REQUIRED_JSON="$TMP/nope.json"
expect_rc "B13: missing required-set JSON -> exit 2" 2
expect_out "B13: unread annotation" "::error::merge-bypass-audit"
expect_nofiled "B13: no issue filed"
run_sut "$SUT" "$SHA" MBA_REQUIRED_JSON="$STUB/gh"   # a non-JSON file
expect_rc "B14: invalid required-set JSON -> exit 2" 2
expect_out "B14: unread annotation" "::error::merge-bypass-audit"

# The ancestry gate (a'): compare/<sha>...main unreadable or non-ancestor is unread.
reset_stub; fx_runs_empty
resp compare 1 "gh: Server Error (HTTP 500)" ""
unread_case "B15: compare read failed on the ancestry gate"

reset_stub; fx_runs_empty
resp compare 0 "" "not-json"
unread_case "B16: compare body invalid on the ancestry gate"

# `diverged` — the sha is NOT on main's history: unread, and the source-PR arm must never
# run (a non-landed sha's green PR head would otherwise read as a false `ok`).
reset_stub; fx_runs_empty
resp compare 0 "" "$(compare_body diverged)"
fx_pulls_incident; fx_checkruns_green
run_sut "$SUT" "$SHA"
expect_rc "B17: diverged sha -> exit 2" 2
expect_out "B17: verdict=unread" "verdict=unread"
expect_out "B17: not-an-ancestor detail" "not an ancestor of main"
expect_noalert "B17: no compliance/critical alert filed"
if grep -qF '/check-runs?' "$STUB_STATE/calls.log" 2>/dev/null; then
  fail "B17: the source-PR arm ran despite the diverged sha"
else
  pass "B17: the source-PR arm never ran for a non-ancestor sha"
fi

# =================================================================================================
# C — dedupe, no_source_pr, flipped (rows 5-7)
# =================================================================================================
printf '\nC. dedupe / no_source_pr / flipped\n'

reset_stub; fx_bypass
resp search 0 "" "$(search_open_with_sha "$SHA")"
run_sut "$SUT" "$SHA"
expect_rc "C5: deduped alert -> rc 1" 1
expect_out "C5: verdict still bypass" "verdict=bypass"
expect_out "C5: dedupe marker" "deduped=open-issue"
expect_nofiled "C5: no second issue filed"
expect_out "C5: ::error still emitted" "::error::merge-bypass-audit"

# A fuzzy search hit that does NOT name the SHA must not suppress filing.
reset_stub; fx_bypass
resp search 0 "" '{"total_count":1,"items":[{"number":7,"title":"unrelated open issue","body":"no sha here"}]}'
run_sut "$SUT" "$SHA"
expect_rc "C5b: unrelated open issue does not dedupe -> rc 1" 1
expect_filed "C5b: issue still filed"

reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" '[]'
resp commit 0 "" "$(commit_body "drive-by fix" "$MERGE_T")"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C6: no source PR -> rc 1" 1
expect_out "C6: verdict bypass" "verdict=bypass"
expect_out "C6: no_source_pr class" "class=no_source_pr"
expect_filed "C6: an issue was filed"
if grep -qF "$SHA" "$STUB_STATE/created.log"; then pass "C6: issue names the merge SHA"; else fail "C6: issue names the merge SHA"; fi
if grep -qF 'post-merge-monitor' "$STUB_STATE/created.log"; then pass "C6: issue body names the sanctioned-revert class"; else fail "C6: issue body names the sanctioned-revert class"; fi

# A commit-message (#N) pointing at a PR whose merge_commit_sha is NOT this sha does not resolve.
reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" '[]'
resp commit 0 "" "$(commit_body "feat: thing (#777)" "$MERGE_T")"
resp pr 0 "" "$(pr_detail 777 true "ffffffffffffffffffffffffffffffffffffffff" "$HEAD" "$MERGE_T")"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C6b: (#N) naming a different merge commit -> rc 1" 1
expect_out "C6b: still no_source_pr" "class=no_source_pr"

# A commit-message (#N) verified against pulls/N DOES resolve the source PR.
reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" '[]'
resp commit 0 "" "$(commit_body "feat: thing (#777)" "$MERGE_T")"
resp pr 0 "" "$(pr_detail 777 true "$SHA" "$HEAD" "$MERGE_T")"
fx_checkruns_green
run_sut "$SUT" "$SHA"
expect_rc "C6c: verified (#N) resolves the source PR -> rc 0" 0
expect_out "C6c: compliant merge via pr_head" "via=pr_head"
expect_out "C6c: PR number carried" "pr=777"

# The merge-queue spelling `Merge pull request #N` resolves through the same path.
reset_stub; fx_runs_empty; fx_compare_ahead
resp pulls 0 "" '[]'
resp commit 0 "" "$(commit_body "Merge pull request #778 from branch" "$MERGE_T")"
resp pr 0 "" "$(pr_detail 778 true "$SHA" "$HEAD" "$MERGE_T")"
fx_checkruns_green
run_sut "$SUT" "$SHA"
expect_rc "C6d: 'Merge pull request #N' resolves -> rc 0" 0
expect_out "C6d: compliant merge via pr_head" "via=pr_head"

reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 4 test failure completed "$T_LATE" "$T_LATE_DONE")")"
run_sut "$SUT" "$SHA"
expect_rc "C7: green at merge, red later -> rc 0" 0
expect_out "C7: verdict check_flipped_after_merge" "verdict=check_flipped_after_merge"
expect_noout "C7: never reads as bypass" "verdict=bypass"
expect_nofiled "C7: no issue filed (CI regression, not bypass)"
expect_out "C7: ::warning report" "::warning::merge-bypass-audit"

# Contrast: the same two runs but the FAILURE predates the merge — red at merge -> bypass.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test success completed "$T_RED" "$T_RED")" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 4 test failure completed "$T_GREEN" "$T_GREEN")")"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C7b: a red latest-at-merge -> rc 1" 1
expect_out "C7b: verdict bypass (ordering is started_at-relative, not existence)" "verdict=bypass"
expect_filed "C7b: an issue was filed"

# A required check still in flight at merge is a pending required check -> bypass.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test null in_progress "$T_GREEN" null)" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")")"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C7c: in-flight required check at merge -> rc 1" 1
expect_out "C7c: pending is not green" "verdict=bypass"

# An unread verdict files the deduped, UNLABELED unread-notice issue (a red run alone is
# not a durable artifact). The notice dedupes on its FIXED title, not the merge SHA.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "not-json"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C8: unread verdict -> exit 2" 2
expect_out "C8: verdict=unread line survives" "verdict=unread"
expect_filed "C8: the unread-notice issue was filed"
if grep -qF "$UNREAD_TITLE" "$STUB_STATE/created.log"; then pass "C8: filed issue carries the fixed unread-notice title"; else fail "C8: filed issue carries the fixed unread-notice title"; fi
expect_noalert "C8: the notice is UNLABELED (no compliance/critical)"
expect_called "C8: the dedupe search used the fixed title" "unread verdict"

# A second unread while the notice is still open dedupes on the title — no refiling, and
# the exit stays 2.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "not-json"
resp search 0 "" "$(search_open_with_title "$UNREAD_TITLE")"
fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C8b: second unread with the notice open -> still exit 2" 2
expect_out "C8b: verdict=unread" "verdict=unread"
expect_nofiled "C8b: deduped on the fixed title — no second notice"

# A run in flight AT the merge that has since completed reports completed_after_merge, not
# its bare conclusion — the state is embedded in the filed alert's bad-context detail.
reset_stub; fx_runs_empty; fx_compare_ahead; fx_pulls_incident
resp checkruns 0 "" "$(checkruns_body \
  "$(cr 1 test success completed "$T_GREEN" "$T_LATE_DONE")" \
  "$(cr 2 guards-ruleset success completed "$T_GREEN" "$T_GREEN")" \
  "$(cr 3 quality-guards success completed "$T_GREEN" "$T_GREEN")")"
fx_search_none; fx_create_ok
run_sut "$SUT" "$SHA"
expect_rc "C9: in-flight-at-merge run since completed -> rc 1" 1
expect_out "C9: verdict bypass (in-flight at merge is not green)" "verdict=bypass"
if grep -qF 'completed_after_merge' "$STUB_STATE/created.log"; then pass "C9: at_merge_state reports completed_after_merge"; else fail "C9: at_merge_state reports completed_after_merge"; fi

# =================================================================================================
# D — instrument control (row 8): the same bypass fixture must NOT produce a bypass verdict on a
#     SUT copy whose verdict routing always reports OK — proving the bypass arms discriminate.
# =================================================================================================
printf '\nD. instrument control\n'

MUT_DIR="$TMP/mut"
assert_fixture_dir "$MUT_DIR"
mkdir -p "$MUT_DIR" || harness_die "cannot create $MUT_DIR"
cp "$SUT" "$MUT_DIR/merge-bypass-audit.sh" || harness_die "cannot copy SUT for mutation"
python3 - "$MUT_DIR/merge-bypass-audit.sh" <<'PY' || harness_die "the always-ok mutation did not land"
import re, sys
p = sys.argv[1]
s = open(p).read()
assert s.count("# >>> VERDICT >>>") == 1, "VERDICT marker not exactly once"
assert s.count("# <<< VERDICT <<<") == 1, "VERDICT end marker not exactly once"
s = re.sub(r"(?s)# >>> VERDICT >>>.*?# <<< VERDICT <<<",
           "printf 'verdict=ok via=mutant sha=%s\\n' \"$sha\"; exit 0", s)
open(p, "w").write(s)
PY
if cmp -s "$MUT_DIR/merge-bypass-audit.sh" "$SUT"; then
  harness_die "the mutated copy is byte-identical to the pristine one"
fi
bash -n "$MUT_DIR/merge-bypass-audit.sh" || harness_die "mutant does not parse"

reset_stub; fx_bypass
run_sut "$MUT_DIR/merge-bypass-audit.sh" "$SHA"
if [[ "$RC" == "1" && "$OUT" == *"verdict=bypass"* ]]; then
  fail "mutant always-ok SURVIVED: an always-OK verdict still reported bypass"
else
  pass "mutant always-ok: the same bypass fixture yields no bypass verdict — the arms discriminate"
fi
expect_out "mutant ran the substituted routing" "via=mutant"
expect_nofiled "mutant filed no issue"

# =================================================================================================
# E — --self-check (the observability discoverability_test depends on this mode)
# =================================================================================================
printf '\nE. self-check\n'

reset_stub
resp repo 0 "" '{"id":1}'
run_sut "$SUT" --self-check
expect_rc "E1: self-check -> rc 0" 0
expect_out "E1: self-check ok line" "merge-bypass-audit self-check ok"

reset_stub
resp repo 1 "gh: Unauthorized (HTTP 401)" ""
run_sut "$SUT" --self-check
expect_rc "E2: self-check auth failure -> rc 2" 2
expect_out "E2: unread annotation" "::error::merge-bypass-audit"

reset_stub
resp repo 0 "" '{"id":1}'
run_sut "$SUT" --self-check MBA_REQUIRED_JSON="$TMP/nope.json"
expect_rc "E3: self-check missing required-set -> rc 2" 2

# =================================================================================================
# G — operand hygiene: anything past the single positional arg is a usage error, not a
#     silently-ignored tail (rc 2, usage line, no API touched).
# =================================================================================================
printf '\nG. operand hygiene\n'

reset_stub
run_sut_argv "$SUT" "$SHA" garbage
expect_rc "G1: <sha> garbage -> exit 2" 2
expect_out "G1: usage printed" "usage:"
expect_nofiled "G1: no issue filed"

reset_stub
run_sut_argv "$SUT" "$SHA" --self-check
expect_rc "G2: <sha> --self-check -> exit 2" 2
expect_out "G2: usage printed" "usage:"

reset_stub
run_sut_argv "$SUT" --self-check extra
expect_rc "G3: --self-check extra -> exit 2" 2
expect_out "G3: usage printed" "usage:"

# =================================================================================================
# F — H1: a child run with pass()/fail() neutered must refuse (rc != 0).
# =================================================================================================
printf '\nF. harness sabotage\n'
for _sab in pass fail; do
  SAB_OUT="$TMP/sabotage-$_sab.out"
  MBA_TEST_SABOTAGE=$_sab timeout 600 bash "${BASH_SOURCE[0]}" > "$SAB_OUT" 2>&1; sab_rc=$?
  if (( sab_rc != 0 )) && grep -q 'instrument self-test' "$SAB_OUT"; then
    pass "H1: a suite whose $_sab() is a no-op exits non-zero (rc=$sab_rc) via the instrument self-test"
  else
    fail "H1: the child with $_sab() sabotaged exited $sab_rc without refusing"
  fi
done

# =================================================================================================
# verdict. Floors are reported with printf + exit, never through the helpers they back-stop.
# =================================================================================================
printf '\nmerge-bypass-audit.test.sh: %d passed, %d failed, %d assertion(s) executed (%ds)\n' \
  "$passes" "$fails" "$asserted" "$((SECONDS - START_S))"

# The floor sits flush against its `if` with its threshold on the line above, for the reason
# scripts/guard-vacuity-floor.test.sh states (it slices the floor block and widens backward over
# CONTIGUOUS simple assignments).
MBA_MIN_ASSERTIONS=164
if (( asserted < MBA_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < MBA_MIN_ASSERTIONS=%d\n' "$asserted" "$MBA_MIN_ASSERTIONS" >&2
  exit 1
fi
# The verdict reads the append-only log AND the counter: neutering either alone cannot turn a
# failing assertion into exit 0.
[[ ! -s "$FAILS_LOG" ]] || exit 1
(( fails == 0 )) || exit 1
exit 0
