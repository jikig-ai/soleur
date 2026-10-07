#!/usr/bin/env bash
# Regression suite for github-community.sh -- Ref #6695.
#
# Covers the three reported collector defects:
#   RC1  activity/contributors died with "Argument list too long" because the
#        whole payload was passed as ONE execve argument. The binding limit is
#        MAX_ARG_STRLEN (131,072 B PER ARGUMENT), not ARG_MAX (2 MB) -- which is
#        why it fired on only 10 commits and recurred every run.
#   RC2  repo-stats merged the stargazer fetch's stderr into the JSON stream, so
#        any stderr byte poisoned the parse.
#   RC3  an exit-0 error body (404/403/410) rendered a plausible "0 new
#        stargazers", indistinguishable from a quiet day.
#
# Fixtures are SYNTHESIZED, never captured (cq-test-fixtures-synthesized-only).
# TMPDIR is private per case so the cleanup assertions cannot false-pass on a
# shared /tmp.

set -uo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SUITE_DIR/../../../../.." && pwd)"
COLLECTOR="$REPO_ROOT/plugins/soleur/skills/community/scripts/github-community.sh"
HELPERS="$REPO_ROOT/plugins/soleur/test/test-helpers.sh"

# Path arithmetic is a claim: verify both resolved paths before trusting them
# (hr-when-a-plan-specifies-relative-paths-e-g).
for required in "$COLLECTOR" "$HELPERS"; do
  if [[ ! -f "$required" ]]; then
    echo "FATAL: expected file not found: $required" >&2
    echo "       (REPO_ROOT resolved to '$REPO_ROOT')" >&2
    exit 1
  fi
done

# shellcheck source=/dev/null
source "$HELPERS"
# test-helpers.sh sets -e; this suite accumulates failures and exits at the end,
# so errexit must be off or a deliberate non-zero probe aborts before fail().
set +e

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- local assertions -------------------------------------------------------

assert_rc() {
  local expected="$1" actual="$2" msg="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected exit $expected, got $actual)"; FAIL=$((FAIL + 1))
  fi
}

assert_nonzero_rc() {
  local actual="$1" msg="$2"
  if [[ "$actual" != "0" ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (expected non-zero exit, got 0)"; FAIL=$((FAIL + 1))
  fi
}

# Asserts a jq predicate over a file. Anchors on the parsed structure rather
# than a bare token, so it cannot false-pass on prose (cq-assert-anchor-not-bare-token).
assert_jq() {
  local file="$1" filter="$2" msg="$3"
  if jq -e "$filter" <"$file" >/dev/null 2>&1; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    filter: $filter"
    echo "    actual: $(head -c 300 "$file")"
    FAIL=$((FAIL + 1))
  fi
}

# grep against a FILE, never `producer | grep -q` -- an early match under
# pipefail takes SIGPIPE (141) and the assertion silently inverts.
assert_file_matches() {
  local file="$1" pattern="$2" msg="$3"
  local n
  n=$(grep -cE -- "$pattern" "$file" 2>/dev/null)
  if [[ "${n:-0}" -gt 0 ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (no match for /$pattern/)"
    echo "    actual: $(head -c 300 "$file")"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_matches() {
  local file="$1" pattern="$2" msg="$3"
  local n
  n=$(grep -cE -- "$pattern" "$file" 2>/dev/null)
  if [[ "${n:-0}" -eq 0 ]]; then
    echo "  PASS: $msg"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (unexpected match for /$pattern/)"
    echo "    actual: $(head -c 300 "$file")"
    FAIL=$((FAIL + 1))
  fi
}

# --- fixture synthesis ------------------------------------------------------

# A payload is "large" when a single serialized argument exceeds MAX_ARG_STRLEN
# (131,072 B). 10 items x 15,000 B of padding clears it with margin, and mirrors
# the production shape: few items, large bodies.
PAD=15000
BIG_N=10

gen_issues()     { jq -nc --argjson n "$1" --argjson pad "$2" --arg ts "$NOW" \
  '[range($n) | {number: (.+1), title: ("issue " + (.|tostring)), state: "open",
                 user: {login: ("user" + ((. % 3)|tostring))}, created_at: $ts,
                 updated_at: $ts, pull_request: null, body: ("x" * $pad)}]'; }

gen_pulls()      { jq -nc --argjson n "$1" --argjson pad "$2" --arg ts "$NOW" \
  '[range($n) | {number: (.+1), title: ("pr " + (.|tostring)), state: "open",
                 user: {login: ("user" + ((. % 3)|tostring))}, created_at: $ts,
                 updated_at: $ts, merged_at: null, body: ("x" * $pad)}]'; }

gen_commits()    { jq -nc --argjson n "$1" --argjson pad "$2" \
  '[range($n) | {sha: ("sha" + (.|tostring)),
                 author: {login: ("dev" + ((. % 2)|tostring))},
                 commit: {author: {name: "Dev"}, message: ("x" * $pad)}}]'; }

gen_stargazers() { jq -nc --argjson n "$1" --argjson pad "$2" --arg ts "$NOW" \
  '[range($n) | {starred_at: $ts, user: {login: ("gazer" + (.|tostring))},
                 pad: ("x" * $pad)}]'; }

gen_comments()   { jq -nc --argjson n "$1" --arg ts "$NOW" \
  '[range($n) | {author_association: "NONE",
                 user: {login: ("outsider" + (.|tostring)), type: "User"},
                 issue_url: "https://api.github.com/repos/o/r/issues/42",
                 body: "a comment", html_url: "https://github.com/o/r/issues/42",
                 created_at: $ts}]'; }

gen_repo()       { jq -nc '{stargazers_count: 11, forks_count: 2,
                            watchers_count: 11, subscribers_count: 1}'; }

# Builds a fresh stub + fixture dir, returns the case root on stdout.
new_case() {
  local name="$1"
  local root="$WORK/$name"
  mkdir -p "$root/stub" "$root/fixtures" "$root/tmp" "$root/out"
  make_gh_api_stub "$root/stub" "$root/fixtures"
  echo "$root"
}

# Runs the collector for a case. Sets RC; stdout/stderr land in $root/out.
run_collector() {
  local root="$1" cmd="$2" days="${3:-1}"
  (
    export PATH="$root/stub:$PATH"
    export GITHUB_REPOSITORY="test-owner/test-repo"
    export TMPDIR="$root/tmp"
    bash "$COLLECTOR" "$cmd" "$days"
  ) >"$root/out/stdout" 2>"$root/out/stderr"
  RC=$?
}

count_tmp_residue() {
  find "$1" -mindepth 1 2>/dev/null | wc -l | tr -d ' '
}

echo "=== github-community.sh regression suite (#6695) ==="
echo ""

# --- Test 1: RC1 large payload, parametric over 3 commands / 5 bindings -----
#
# One-binding coverage is not enough: `prs` mis-unwrapped while `issues` is
# correct yields a partially-correct digest that looks exactly like a quiet day.
# The `count == (items|length)` invariant catches the PARTIAL unwrap, which is
# the silent shape -- a full non-unwrap hard-errors and is comparatively safe.

echo "Test 1: large payloads (>131,072 B/arg) across all five bindings"

CASE1="$(new_case rc1)"
gen_issues     "$BIG_N" "$PAD" > "$CASE1/fixtures/issues.json"
gen_pulls      "$BIG_N" "$PAD" > "$CASE1/fixtures/pulls.json"
gen_commits    "$BIG_N" "$PAD" > "$CASE1/fixtures/commits.json"
gen_stargazers "$BIG_N" "$PAD" > "$CASE1/fixtures/stargazers.json"
gen_repo                       > "$CASE1/fixtures/repo.json"

# Precondition: the fixtures must actually breach the per-argument ceiling, or
# every assertion below is vacuous.
CARDINALITY=0
for f in issues pulls commits stargazers; do
  sz=$(wc -c < "$CASE1/fixtures/$f.json")
  CARDINALITY=$((CARDINALITY + 1))
  if [[ "$sz" -le 131072 ]]; then
    echo "  FAIL: fixture $f.json is $sz B, below the 131,072 B ceiling under test"
    FAIL=$((FAIL + 1))
  fi
done
if [[ "$CARDINALITY" -ne 4 ]]; then
  echo "  FAIL: fixture size guard covered $CARDINALITY/4 payloads"
  FAIL=$((FAIL + 1))
fi

run_collector "$CASE1" activity 1
assert_rc 0 "$RC" "activity exits 0 on a large payload"
assert_jq "$CASE1/out/stdout" \
  '.issues.count == (.issues.items | length)' \
  "activity: issues.count == issues.items|length (partial-unwrap guard)"
assert_jq "$CASE1/out/stdout" \
  ".pull_requests.count == (.pull_requests.items | length)" \
  "activity: pull_requests.count == pull_requests.items|length (partial-unwrap guard)"
assert_jq "$CASE1/out/stdout" \
  ".issues.count == $BIG_N and .pull_requests.count == $BIG_N" \
  "activity: both counts equal the $BIG_N synthesized items"

run_collector "$CASE1" contributors 1
assert_rc 0 "$RC" "contributors exits 0 on a large payload"
assert_jq "$CASE1/out/stdout" \
  "([.commit_authors[].commits] | add) == $BIG_N" \
  "contributors: commit totals sum to the $BIG_N synthesized commits"
assert_jq "$CASE1/out/stdout" \
  "([.issue_authors[].activity] | add) == $BIG_N" \
  "contributors: issue totals sum to the $BIG_N synthesized issues"

run_collector "$CASE1" repo-stats 1
assert_rc 0 "$RC" "repo-stats exits 0 on a large stargazer payload"
assert_jq "$CASE1/out/stdout" \
  '.new_stargazers_count == (.new_stargazers | length)' \
  "repo-stats: new_stargazers_count == new_stargazers|length (partial-unwrap guard)"
assert_jq "$CASE1/out/stdout" \
  ".new_stargazers_count == $BIG_N" \
  "repo-stats: new stargazer count equals the $BIG_N synthesized entries"

echo ""

# --- Test 2: RC2 stderr noise on the stargazer path -------------------------

echo "Test 2: stderr noise must not poison the stargazer JSON stream"

CASE2="$(new_case rc2)"
gen_stargazers 3 16 > "$CASE2/fixtures/stargazers.json"
gen_repo            > "$CASE2/fixtures/repo.json"
printf 'gh: warning: some pages were rate-limited\n' > "$CASE2/fixtures/stargazers.stderr"

run_collector "$CASE2" repo-stats 1
assert_rc 0 "$RC" "repo-stats parses despite stderr noise on the stargazer fetch"
assert_jq "$CASE2/out/stdout" '.stargazers_count == 11' \
  "repo-stats: stargazers_count survives stderr noise"
assert_jq "$CASE2/out/stdout" '.new_stargazers_count == 3' \
  "repo-stats: new_stargazers_count survives stderr noise"

echo ""

# --- Test 2b: paginated (multi-array) body ----------------------------------
#
# `gh --paginate` emits ONE JSON ARRAY PER PAGE, concatenated. Slurping wraps
# them as [[...],[...]], so the dereference must FLATTEN, not take the first
# page. Every other fixture in this suite is a single array, under which
# `add // []` and `.[0] // []` are indistinguishable -- so without this case the
# flattening is unverified and a first-page-only regression reads as green while
# silently undercounting. That is the same plausible-wrong-number class as RC3,
# in the fix for RC3.

echo "Test 2b: a paginated multi-array body is flattened, not truncated to page 1"

CASE2B="$(new_case paginated)"
gen_repo > "$CASE2B/fixtures/repo.json"
# Two pages: 100 + 50. Concatenated exactly as --paginate emits them.
{ gen_stargazers 100 16; gen_stargazers 50 16; } > "$CASE2B/fixtures/stargazers.json"

# Precondition: the fixture really does hold more than one JSON value.
PAGES=$(jq -s 'length' < "$CASE2B/fixtures/stargazers.json")
assert_eq "2" "$PAGES" "fixture holds two concatenated page arrays"

run_collector "$CASE2B" repo-stats 1
assert_rc 0 "$RC" "repo-stats exits 0 on a paginated body"
assert_jq "$CASE2B/out/stdout" '.new_stargazers_count == 150'   "repo-stats sums BOTH pages (150), not just the first (100)"
assert_jq "$CASE2B/out/stdout" \
  '.new_stargazers_count == (.new_stargazers | length)' \
  "repo-stats: count still matches items on a paginated body"

echo ""

# --- Test 3: RC3/D6/H3 exit-0 error body ------------------------------------
#
# A 404/403/410 body arrives at exit 0. Unguarded, it renders a plausible
# new_stargazers_count: 0 -- the fabrication path the digest actually shipped.

echo "Test 3: an exit-0 error body must fail loudly, never render a plausible 0"

CASE3="$(new_case rc3)"
gen_repo > "$CASE3/fixtures/repo.json"
jq -nc '{message: "Not Found", documentation_url: "https://docs.github.com/rest"}' \
  > "$CASE3/fixtures/stargazers.json"

run_collector "$CASE3" repo-stats 1
assert_nonzero_rc "$RC" "repo-stats exits non-zero on an exit-0 error body"
assert_file_not_matches "$CASE3/out/stdout" '"new_stargazers_count"' \
  "repo-stats emits no new_stargazers_count on an error body"
assert_file_not_matches "$CASE3/out/stdout" '"stargazers_count"' \
  "repo-stats emits no stargazers_count on an error body"
assert_file_matches "$CASE3/out/stderr" 'GITHUB_COLLECTOR_CAUSE=' \
  "repo-stats reports a machine-readable cause on an error body"

echo ""

# --- Test 3b: exit-0 with an EMPTY body -------------------------------------
#
# The API renders "no results" as [], so zero bytes means the response was lost.
# Slurping an empty file yields [], which would render a plausible 0 -- the last
# path by which a missing fetch could still look like a quiet day.

echo "Test 3b: an exit-0 empty body must fail loudly, not read as a quiet day"

CASE3B="$(new_case rc3_empty)"
gen_repo > "$CASE3B/fixtures/repo.json"
: > "$CASE3B/fixtures/stargazers.json"

run_collector "$CASE3B" repo-stats 1
assert_nonzero_rc "$RC" "repo-stats exits non-zero on an empty stargazer body"
assert_file_not_matches "$CASE3B/out/stdout" '"new_stargazers_count"' \
  "repo-stats emits no new_stargazers_count on an empty body"
assert_file_matches "$CASE3B/out/stderr" 'GITHUB_COLLECTOR_CAUSE=stargazers returned an empty body' \
  "repo-stats names the empty body as the cause"

echo ""

# --- Test 4: D7 multi-tempfile cleanup on a FAILURE path ---------------------
#
# Forward guard: it cannot be RED before the fix, because the pre-fix script
# creates no tempfiles in these commands. Its value is mutation-testing --
# splitting the single trap into one-trap-per-file must turn it red, since bash
# EXIT traps are global and singular (the second REPLACES the first).
# A single-tempfile command could not detect that class at all.

echo "Test 4: multi-tempfile command leaks nothing on a failure path"

CASE4="$(new_case d7)"
gen_issues 3 16 > "$CASE4/fixtures/issues.json"
printf '1\n'    > "$CASE4/fixtures/pulls.exit"
printf 'gh: server error fetching pulls\n' > "$CASE4/fixtures/pulls.stderr"

run_collector "$CASE4" activity 1
assert_nonzero_rc "$RC" "activity exits non-zero when the PR fetch fails"
assert_eq "0" "$(count_tmp_residue "$CASE4/tmp")" \
  "activity leaves zero tempfile residue in a private TMPDIR after failing"

echo ""

# --- Test 5: D5 collector-status sidecar ------------------------------------
#
# The deterministic signal. Every other failure channel the collector has
# terminates in the spawned agent's context window -- this one is read by the
# handler directly from spawnCwd, with no LLM in the path.

echo "Test 5: collector-status sidecar records real exit codes"

CASE5="$(new_case d5ok)"
gen_issues 2 16 > "$CASE5/fixtures/issues.json"
gen_pulls  2 16 > "$CASE5/fixtures/pulls.json"
STATUS_DIR="$CASE5/status"
(
  export PATH="$CASE5/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE5/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS_DIR"
  bash "$COLLECTOR" activity 1
) >"$CASE5/out/stdout" 2>"$CASE5/out/stderr"
RC=$?
assert_rc 0 "$RC" "activity succeeds with the status dir set"
assert_file_exists "$STATUS_DIR/collector-status.jsonl" \
  "sidecar file is created when SOLEUR_COLLECTOR_STATUS_DIR is set"
if [[ -f "$STATUS_DIR/collector-status.jsonl" ]]; then
  assert_jq "$STATUS_DIR/collector-status.jsonl" \
    '.collector == "github" and .command == "activity" and .exit == 0' \
    "sidecar records exit 0 for a successful activity run"
fi

CASE5F="$(new_case d5fail)"
printf '1\n' > "$CASE5F/fixtures/issues.exit"
printf 'gh: boom\n' > "$CASE5F/fixtures/issues.stderr"
STATUS_DIR_F="$CASE5F/status"
(
  export PATH="$CASE5F/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE5F/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS_DIR_F"
  bash "$COLLECTOR" activity 1
) >"$CASE5F/out/stdout" 2>"$CASE5F/out/stderr"
RC=$?
assert_nonzero_rc "$RC" "activity fails when the issues fetch fails"
if [[ -f "$STATUS_DIR_F/collector-status.jsonl" ]]; then
  assert_jq "$STATUS_DIR_F/collector-status.jsonl" \
    '.command == "activity" and .exit != 0' \
    "sidecar records a non-zero exit for a failed activity run"
else
  echo "  FAIL: sidecar file missing after a failed run"
  FAIL=$((FAIL + 1))
fi

CASE5U="$(new_case d5unset)"
gen_issues 2 16 > "$CASE5U/fixtures/issues.json"
gen_pulls  2 16 > "$CASE5U/fixtures/pulls.json"
run_collector "$CASE5U" activity 1
assert_rc 0 "$RC" "activity succeeds with the status dir unset"
assert_eq "0" "$(find "$CASE5U" -name 'collector-status.jsonl' 2>/dev/null | wc -l | tr -d ' ')" \
  "no sidecar is written when SOLEUR_COLLECTOR_STATUS_DIR is unset"

echo ""

# --- Test 6: AC4 counter-assertion -- cmd_discussions graceful path ---------
#
# cmd_discussions' stderr capture is load-bearing: it classifies the
# "Discussions not enabled" case into a graceful exit 0. A blanket stderr sweep
# would convert that into a hard failure. This asserts the sweep did not happen.

echo "Test 6: cmd_discussions still degrades gracefully (counter-assertion)"

CASE6="$(new_case discussions)"
printf '1\n' > "$CASE6/fixtures/graphql.exit"
printf 'Could not resolve to a Repository: discussions are not enabled\n' \
  > "$CASE6/fixtures/graphql.stderr"

run_collector "$CASE6" discussions 1
assert_rc 0 "$RC" "discussions exits 0 when Discussions are not enabled"
assert_jq "$CASE6/out/stdout" '.discussions == []' \
  "discussions returns the graceful empty payload"

echo ""

# --- Test 7: AC7/D2 cap detection -------------------------------------------

echo "Test 7: a fetch capped at per_page emits a truncation warning"

CASE7="$(new_case cap)"
gen_issues 100 16 > "$CASE7/fixtures/issues.json"
gen_pulls    2 16 > "$CASE7/fixtures/pulls.json"

run_collector "$CASE7" activity 1
assert_rc 0 "$RC" "activity still succeeds at the per_page cap"
assert_file_matches "$CASE7/out/stderr" 'truncat' \
  "activity warns when a fetch returns exactly per_page items"

# Both arms are required. The pulls endpoint over-fetches a fixed page and
# filters by date afterwards, so a full RAW page is its steady state -- against
# the live repo it returns 100 on every run. Warning on that would fire daily
# and train the reader to ignore the signal, so the cap is measured after the
# date filter for this endpoint. A detector that cries wolf is worse than none.
CASE7B="$(new_case cap_negative)"
gen_issues 3 16   > "$CASE7B/fixtures/issues.json"
gen_pulls  100 16 > "$CASE7B/fixtures/pulls.json"
# Age every PR out of the window so the post-filter count is 0, not 100.
jq -c '[.[] | .updated_at = "2000-01-01T00:00:00Z"]' \
  "$CASE7B/fixtures/pulls.json" > "$CASE7B/fixtures/pulls.tmp" \
  && mv "$CASE7B/fixtures/pulls.tmp" "$CASE7B/fixtures/pulls.json"

run_collector "$CASE7B" activity 1
assert_rc 0 "$RC" "activity succeeds when pulls returns a full raw page"
assert_jq "$CASE7B/out/stdout" '.pull_requests.count == 0' \
  "activity: the date filter still excludes out-of-window PRs"
assert_file_not_matches "$CASE7B/out/stderr" 'truncat' \
  "activity does NOT warn on a full raw pulls page that filters down to 0"

# The contributors/issues call site passed a FILE PATH to a helper that takes a
# COUNT, so `[[ /tmp/tmp.X -eq 100 ]]` raised a bash arithmetic error, returned
# non-zero inside an `if`, and the detector was permanently dead there. Test 7
# covered `activity` only, which is why the suite stayed green.
echo "Test 7c: cap detection is live on the contributors endpoint too"

CASE7C="$(new_case cap_contributors)"
gen_commits 3 16   > "$CASE7C/fixtures/commits.json"
gen_issues 100 16  > "$CASE7C/fixtures/issues.json"

run_collector "$CASE7C" contributors 1
assert_rc 0 "$RC" "contributors succeeds at the per_page cap"
assert_file_matches "$CASE7C/out/stderr" 'issues returned exactly 100 items' \
  "contributors warns when its issues fetch returns exactly per_page items"
assert_file_not_matches "$CASE7C/out/stderr" 'arithmetic syntax error' \
  "contributors emits no bash arithmetic error (helper receives a count)"

echo ""

# --- Test 8: the sidecar carries the diagnostic payload, not just an exit code -
#
# `cause` and `warn` are what the handler renders into the operator page. Both
# were previously unasserted: blanking every _CAUSE assignment, or dropping the
# warn field, left the suite fully green.

echo "Test 8: sidecar records carry cause and warn"

CASE8="$(new_case sidecar_fields)"
gen_repo > "$CASE8/fixtures/repo.json"
jq -nc '{message: "Not Found"}' > "$CASE8/fixtures/stargazers.json"
STATUS8="$CASE8/status"
(
  export PATH="$CASE8/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE8/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS8"
  bash "$COLLECTOR" repo-stats 1
) >"$CASE8/out/stdout" 2>"$CASE8/out/stderr"
RC=$?
assert_nonzero_rc "$RC" "repo-stats fails on an error body"
if [[ -f "$STATUS8/collector-status.jsonl" ]]; then
  assert_jq "$STATUS8/collector-status.jsonl" \
    '.cause == "stargazers-non-array"' \
    "sidecar records the specific cause, not an empty string"
else
  echo "  FAIL: sidecar missing after error-body run"; FAIL=$((FAIL + 1))
fi

CASE8W="$(new_case sidecar_warn)"
gen_commits 3 16  > "$CASE8W/fixtures/commits.json"
gen_issues 100 16 > "$CASE8W/fixtures/issues.json"
STATUS8W="$CASE8W/status"
(
  export PATH="$CASE8W/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE8W/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS8W"
  export SOLEUR_COLLECTOR_COMPACT=1
  bash "$COLLECTOR" contributors 1
) >"$CASE8W/out/stdout" 2>"$CASE8W/out/stderr"
RC=$?
assert_rc 0 "$RC" "contributors succeeds with a status dir set"
# 100 issues are NOT read in compact mode (the line carries only the commit total), so the
# truncation signal comes from the commits cap.
gen_commits 100 16 > "$CASE8W/fixtures/commits.json"
rm -f "$STATUS8W/collector-status.jsonl"
(
  export PATH="$CASE8W/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE8W/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS8W"
  export SOLEUR_COLLECTOR_COMPACT=1
  bash "$COLLECTOR" contributors 1
) >"$CASE8W/out/stdout" 2>"$CASE8W/out/stderr"
RC=$?
assert_rc 0 "$RC" "contributors succeeds at the commits cap"
if [[ -f "$STATUS8W/collector-status.jsonl" ]]; then
  assert_jq "$STATUS8W/collector-status.jsonl" \
    '.warn == "truncated_at_per_page"' \
    "sidecar carries the truncation warn field the handler reports on"
else
  echo "  FAIL: sidecar missing after capped run"; FAIL=$((FAIL + 1))
fi
# The same capped run WITHOUT the flag (a cron whose flag did not arrive): compact_off outranks the
# truncation warn, so the flag regression is not hidden behind the per_page cap.
rm -f "$STATUS8W/collector-status.jsonl"
(
  export PATH="$CASE8W/stub:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
  export TMPDIR="$CASE8W/tmp"
  export SOLEUR_COLLECTOR_STATUS_DIR="$STATUS8W"
  bash "$COLLECTOR" contributors 1
) >"$CASE8W/out/stdout" 2>"$CASE8W/out/stderr"
assert_jq "$STATUS8W/collector-status.jsonl" '.warn == "compact_off"' \
  "compact_off outranks truncated_at_per_page"

# --- Test 9: fetch-interactions -------------------------------------------
#
# This command runs in production on every digest but had zero coverage. Its old
# form piped through `add // []` BEFORE any validation and discarded stderr, so a
# lost or error response collapsed into an empty interaction list at exit 0 --
# a quiet day, indistinguishable from a real one.

echo "Test 9: fetch-interactions parses, and fails loudly on an error body"

CASE9="$(new_case interactions)"
gen_comments 3 > "$CASE9/fixtures/issue_comments.json"

run_collector "$CASE9" fetch-interactions 1
assert_rc 0 "$RC" "fetch-interactions exits 0 on a valid body"
assert_jq "$CASE9/out/stdout" '(.interactions | length) == 3' \
  "fetch-interactions returns all three external comments"

# Paginated shape: the same flattening requirement as the stargazer path.
CASE9P="$(new_case interactions_paged)"
{ gen_comments 2; gen_comments 2; } > "$CASE9P/fixtures/issue_comments.json"
run_collector "$CASE9P" fetch-interactions 1
assert_rc 0 "$RC" "fetch-interactions exits 0 on a paginated body"
assert_jq "$CASE9P/out/stdout" '(.interactions | length) == 4' \
  "fetch-interactions flattens both pages (4), not just the first (2)"

# Exit-0 error body must not read as "no interactions today".
CASE9E="$(new_case interactions_error)"
jq -nc '{message: "Not Found"}' > "$CASE9E/fixtures/issue_comments.json"
run_collector "$CASE9E" fetch-interactions 1
assert_nonzero_rc "$RC" "fetch-interactions exits non-zero on an exit-0 error body"
assert_file_not_matches "$CASE9E/out/stdout" '"interactions"' \
  "fetch-interactions emits no empty interactions list on an error body"
assert_file_matches "$CASE9E/out/stderr" 'GITHUB_COLLECTOR_CAUSE=issue-comments' \
  "fetch-interactions names issue-comments as the cause"

# --- Test 10: compact mode (#9678) ------------------------------------------
#
# The spawned agent has no file tools, so collector output past the Bash tool's inline
# limit (30,000 characters) is unreadable and the digest row goes `partial`. With
# SOLEUR_COLLECTOR_COMPACT=1 each command prints ONE line holding only the fields the
# prompt reads; unset (or any other value) the output is the unchanged interactive shape.

echo "Test 10: compact mode projects to the prompt's fields within the inline budget"

INLINE_LIMIT=30000
LONG=256

# Runs the collector with extra environment ("NAME=value ..." in $2). Sets RC.
run_collector_env() {
  local root="$1" envs="$2" cmd="$3" days="${4:-1}"
  local -a pairs=()
  # shellcheck disable=SC2206
  [[ -n "$envs" ]] && pairs=($envs)
  (
    export PATH="$root/stub:$PATH"
    export GITHUB_REPOSITORY="test-owner/test-repo"
    export TMPDIR="$root/tmp"
    env "${pairs[@]}" bash "$COLLECTOR" "$cmd" "$days"
  ) >"$root/out/stdout" 2>"$root/out/stderr"
  RC=$?
}

# Issues/PRs with long titles and distinct, strictly increasing updated_at (item 100
# is the newest), so "newest first" is observable and the title cap has work to do.
gen_long_issues() { jq -nc --argjson n "$1" --argjson len "$2" \
  '[range($n) | {number: (.+1), title: ("T" + (.|tostring) + "-" + ("x" * $len)), state: "open",
                 user: {login: ("user" + ((. % 3)|tostring))},
                 created_at: "2099-01-01T00:00:00Z",
                 updated_at: ("2099-01-01T00:" + ((. / 60 | floor) | tostring | if length < 2 then "0" + . else . end) + ":" + ((. % 60) | tostring | if length < 2 then "0" + . else . end) + "Z"),
                 pull_request: null, body: ("x" * 100)}]'; }
gen_long_pulls() { jq -nc --argjson n "$1" --argjson len "$2" \
  '[range($n) | {number: (.+1), title: ("P" + (.|tostring) + "-" + ("x" * $len)), state: "open",
                 user: {login: ("user" + ((. % 3)|tostring))},
                 created_at: "2099-01-01T00:00:00Z",
                 updated_at: ("2099-01-01T00:" + ((. / 60 | floor) | tostring | if length < 2 then "0" + . else . end) + ":" + ((. % 60) | tostring | if length < 2 then "0" + . else . end) + "Z"),
                 merged_at: null, body: ("x" * 100)}]'; }
gen_graphql_discussions() { jq -nc --argjson n "$1" --argjson len "$2" \
  '{data: {repository: {discussions: {nodes:
     [range($n) | {number: (.+1), title: ("D" + (.|tostring) + "-" + ("x" * $len)),
                   author: {login: "someone"}, createdAt: "2099-01-01T00:00:00Z",
                   updatedAt: ("2099-01-01T00:00:" + ((. % 60) | tostring | if length < 2 then "0" + . else . end) + "Z"),
                   answerChosenAt: null, comments: {totalCount: 1}, category: {name: "General"}}]}}}}'; }

CASE10="$(new_case compact)"
gen_long_issues 100 "$LONG" > "$CASE10/fixtures/issues.json"
gen_long_pulls  100 "$LONG" > "$CASE10/fixtures/pulls.json"
gen_commits 100 16          > "$CASE10/fixtures/commits.json"
gen_stargazers 5 16         > "$CASE10/fixtures/stargazers.json"
gen_repo                    > "$CASE10/fixtures/repo.json"
gen_graphql_discussions 60 "$LONG" > "$CASE10/fixtures/graphql.json"
{ gen_comments 3; gen_comments 2; } > "$CASE10/fixtures/issue_comments.json"

# Precondition: the default output really does breach the inline limit, so the
# budget assertions below are not vacuous.
run_collector "$CASE10" activity 1
DEFAULT_ACTIVITY_BYTES=$(wc -c < "$CASE10/out/stdout")
if [[ "$DEFAULT_ACTIVITY_BYTES" -le "$INLINE_LIMIT" ]]; then
  echo "  FAIL: default activity output is $DEFAULT_ACTIVITY_BYTES B, not over the $INLINE_LIMIT B limit under test"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: default activity output ($DEFAULT_ACTIVITY_BYTES B) breaches the $INLINE_LIMIT B inline limit"
  PASS=$((PASS + 1))
fi
# Default shape is unchanged (flag unset).
assert_jq "$CASE10/out/stdout" \
  '(keys | sort) == ["issues","pull_requests","repo","since"] and (.issues.items[0] | has("user"))' \
  "default activity shape is unchanged when the flag is unset"

CHAIN_BYTES=0
for cmd in activity contributors repo-stats discussions fetch-interactions; do
  run_collector_env "$CASE10" "SOLEUR_COLLECTOR_COMPACT=1" "$cmd" 1
  assert_rc 0 "$RC" "compact $cmd exits 0"
  bytes=$(wc -c < "$CASE10/out/stdout")
  CHAIN_BYTES=$((CHAIN_BYTES + bytes))
  lines=$(wc -l < "$CASE10/out/stdout" | tr -d ' ')
  assert_eq "1" "$lines" "compact $cmd prints exactly one line"
  if [[ "$bytes" -lt "$INLINE_LIMIT" ]]; then
    echo "  PASS: compact $cmd ($bytes B) is under the $INLINE_LIMIT B inline limit"; PASS=$((PASS + 1))
  else
    echo "  FAIL: compact $cmd is $bytes B, not under the $INLINE_LIMIT B inline limit"; FAIL=$((FAIL + 1))
  fi
  cp "$CASE10/out/stdout" "$CASE10/out.$cmd.json"
done
# The agent's reads concatenate: the whole GitHub chain must fit one inline window with margin.
if [[ "$CHAIN_BYTES" -lt 9800 ]]; then
  echo "  PASS: worst-case compact chain ($CHAIN_BYTES B) fits well inside the inline limit"; PASS=$((PASS + 1))
else
  echo "  FAIL: worst-case compact chain is $CHAIN_BYTES B (budget 9800 B, measured 7840 B)"; FAIL=$((FAIL + 1))
fi

assert_jq "$CASE10/out.activity.json" \
  '(keys | sort) == ["issues","pull_requests"]
   and .issues.count == 100 and .pull_requests.count == 100
   and (.issues.titles | length) == 40 and (.pull_requests.titles | length) == 40
   and ([.issues.titles[], .pull_requests.titles[]] | all(length <= 60))' \
  "compact activity: exact counts, newest 40 titles per list, each title capped at 60"
assert_jq "$CASE10/out.activity.json" \
  '(.issues.titles[0] | startswith("T99-")) and (.pull_requests.titles[0] | startswith("P99-"))' \
  "compact activity: titles are newest-first (sorted by updated_at before the slice)"
assert_file_not_matches "$CASE10/out.activity.json" 'user[0-9]|"login"|body' \
  "compact activity carries no login or body text"
assert_jq "$CASE10/out.contributors.json" '. == {commit_total: 100}' \
  "compact contributors: commit_total equals the 100 synthesized commits, no logins"
assert_jq "$CASE10/out.repo-stats.json" \
  '(keys | sort) == ["forks_count","new_stargazers_count","stargazers_count","stargazers_unavailable","subscribers_count"]
   and .stargazers_count == 11 and .forks_count == 2 and .new_stargazers_count == 5
   and .stargazers_unavailable == false' \
  "compact repo-stats: exactly the prompt's fields, no login list, no watchers_count"
assert_jq "$CASE10/out.discussions.json" \
  '(keys == ["titles"]) and (.titles | length) == 40 and (.titles | all(length <= 60)) and (.titles[0] | startswith("D59-"))' \
  "compact discussions: newest 40 titles, each capped at 60"
assert_jq "$CASE10/out.fetch-interactions.json" \
  '. == {external_contributors: 3, interactions_count: 5}' \
  "compact fetch-interactions: 5 interactions from 3 distinct people, computed in the collector"

# A flag value other than 1 leaves output unchanged and never echoes the raw value.
run_collector_env "$CASE10" "SOLEUR_COLLECTOR_COMPACT=sekret-value" activity 1
assert_rc 0 "$RC" "activity exits 0 with a bad flag value"
assert_jq "$CASE10/out/stdout" '(.issues | has("items"))' "a flag value other than 1 leaves the default shape"
assert_file_matches "$CASE10/out/stderr" '^SOLEUR_COLLECTOR_COMPACT ignored \(expected 1\)$' \
  "a bad flag value prints one fixed stderr line"
assert_file_not_matches "$CASE10/out/stderr" 'sekret-value' "the raw flag value is never echoed"

# Discussions not enabled.
CASE10N="$(new_case compact_nodiscussions)"
printf 'Discussions are not enabled for this repository (Not Found)\n' > "$CASE10N/fixtures/graphql.json"
echo 1 > "$CASE10N/fixtures/graphql.exit"
run_collector_env "$CASE10N" "SOLEUR_COLLECTOR_COMPACT=1" discussions 1
assert_rc 0 "$RC" "compact discussions exits 0 when discussions are not enabled"
assert_jq "$CASE10N/out/stdout" '. == {titles: []}' "compact discussions (not enabled): empty titles"

# The stargazers_unavailable sidecar warn survives compact mode (it is set in the same
# function scope as the projection; a pipe would have lost it).
CASE10S="$(new_case compact_sidecar)"
gen_repo > "$CASE10S/fixtures/repo.json"
echo '[]' > "$CASE10S/fixtures/stargazers.json"
printf 'gh: Resource not accessible by integration (HTTP 403)\n' > "$CASE10S/fixtures/stargazers.stderr"
echo 1 > "$CASE10S/fixtures/stargazers.exit"
run_collector_env "$CASE10S" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$CASE10S/status" repo-stats 1
assert_rc 0 "$RC" "compact repo-stats exits 0 with unreadable stargazers"
assert_jq "$CASE10S/out/stdout" '.stargazers_unavailable == true and .new_stargazers_count == null' \
  "compact repo-stats reports stargazers as unavailable, not zero"
assert_jq "$CASE10S/status/collector-status.jsonl" '.warn == "stargazers_unavailable" and .exit == 0 and .cause == ""' \
  "compact mode keeps the stargazers_unavailable sidecar warn (and no cause on success)"

# compact_off: inside the cron (status dir set) but the flag did not arrive.
CASE10O="$(new_case compact_off)"
gen_repo > "$CASE10O/fixtures/repo.json"
gen_stargazers 2 16 > "$CASE10O/fixtures/stargazers.json"
run_collector_env "$CASE10O" "SOLEUR_COLLECTOR_STATUS_DIR=$CASE10O/status" repo-stats 1
assert_rc 0 "$RC" "default repo-stats still exits 0 inside the cron"
assert_jq "$CASE10O/status/collector-status.jsonl" '.warn == "compact_off"' \
  "a cron run without the flag records warn=compact_off in the sidecar"
# ...and a status-dir run that DOES carry the flag does not.
run_collector_env "$CASE10O" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$CASE10O/status2" repo-stats 1
assert_jq "$CASE10O/status2/collector-status.jsonl" 'has("warn") | not' \
  "a cron run with the flag records no compact warn"

# compact_over_budget: titles that JSON-escape to two bytes per character push one
# output past the 6,000 B signal threshold.
CASE10B="$(new_case compact_over_budget)"
jq -nc '[range(99) | {number: (.+1), title: ("\"" * 60), state: "open", user: {login: "u"},
         created_at: "2099-01-01T00:00:00Z", updated_at: "2099-01-01T00:00:00Z", pull_request: null}]' \
  > "$CASE10B/fixtures/issues.json"
jq -nc '[range(99) | {number: (.+1), title: ("\"" * 60), state: "open", user: {login: "u"},
         created_at: "2099-01-01T00:00:00Z", updated_at: "2099-01-01T00:00:00Z", merged_at: null}]' \
  > "$CASE10B/fixtures/pulls.json"
run_collector_env "$CASE10B" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$CASE10B/status" activity 1
assert_rc 0 "$RC" "compact activity exits 0 on escape-heavy titles"
assert_jq "$CASE10B/status/collector-status.jsonl" '.warn == "compact_over_budget"' \
  "an over-budget compact output records warn=compact_over_budget"

# Fail closed: a drifted required field must not print null for the model to read as 0.
CASE10F="$(new_case compact_failclosed)"
jq -nc '{stargazers_count: 11, watchers_count: 11, subscribers_count: 1}' > "$CASE10F/fixtures/repo.json"
gen_stargazers 1 16 > "$CASE10F/fixtures/stargazers.json"
run_collector_env "$CASE10F" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$CASE10F/status" repo-stats 1
assert_nonzero_rc "$RC" "compact repo-stats exits non-zero when forks_count is missing"
assert_file_not_matches "$CASE10F/out/stdout" 'forks_count' "no partial compact record is printed on a projection failure"
assert_jq "$CASE10F/status/collector-status.jsonl" '.cause == "compact-projection-failed" and .exit != 0' \
  "a projection failure is recorded with cause=compact-projection-failed"

# --- Test 11: compact filters keep their predicates (#9678 review) ----------
#
# Every fixture in Test 10 sits on the KEEP side of every filter, so a compact projection that
# dropped its date, pull-request, bot-association or null-author predicate would still pass. This
# case puts items on BOTH sides of each predicate and asserts the exact counts.

echo "Test 11: compact projections apply the same filters as the default output"

OLD="2000-01-01T00:00:00Z"
CASE11="$(new_case compact_filters)"
# issues: 3 real, 2 pull requests listed by the issues endpoint (must not count as issues)
jq -nc --arg ts "$NOW" '[range(5) | {number: (.+1), title: ("i" + (.|tostring)), state: "open",
   user: {login: "u"}, created_at: $ts, updated_at: $ts,
   pull_request: (if . >= 3 then {url: "x"} else null end)}]' > "$CASE11/fixtures/issues.json"
# pulls: 4 recent, 2 updated long before `since` (the endpoint over-fetches a fixed page)
jq -nc --arg ts "$NOW" --arg old "$OLD" '[range(6) | {number: (.+1), title: ("p" + (.|tostring)), state: "open",
   user: {login: "u"}, created_at: $ts, merged_at: null, updated_at: (if . >= 4 then $old else $ts end)}]' \
   > "$CASE11/fixtures/pulls.json"
# commits: 3 attributable, 1 with neither a login nor an author name (must not count)
jq -nc '[{author: {login: "a"}, commit: {author: {name: "A"}}},
         {author: {login: "b"}, commit: {author: {name: "B"}}},
         {author: null, commit: {author: {name: "Anon"}}},
         {author: null, commit: {author: {name: null}}}]' > "$CASE11/fixtures/commits.json"
# stargazers: 2 inside the window, 3 long before it
jq -nc --arg ts "$NOW" --arg old "$OLD" '[range(5) | {starred_at: (if . < 2 then $ts else $old end), user: {login: ("g" + (.|tostring))}}]' \
   > "$CASE11/fixtures/stargazers.json"
gen_repo > "$CASE11/fixtures/repo.json"
# discussions: 5 recent, 3 updated long before `since`
jq -nc --arg ts "$NOW" --arg old "$OLD" '{data: {repository: {discussions: {nodes:
   [range(8) | {number: (.+1), title: ("d" + (.|tostring)), author: {login: "x"}, createdAt: $ts,
                updatedAt: (if . < 5 then $ts else $old end), answerChosenAt: null,
                comments: {totalCount: 0}, category: {name: "G"}}]}}}}' > "$CASE11/fixtures/graphql.json"
# comments: 2 external people; a bot account, a [bot] login, an OWNER and a MEMBER are excluded
jq -nc --arg ts "$NOW" '[
  {author_association: "NONE",        user: {login: "ext1", type: "User"}},
  {author_association: "CONTRIBUTOR", user: {login: "ext2", type: "User"}},
  {author_association: "NONE",        user: {login: "robot", type: "Bot"}},
  {author_association: "NONE",        user: {login: "dependabot[bot]", type: "User"}},
  {author_association: "OWNER",       user: {login: "maint", type: "User"}},
  {author_association: "MEMBER",      user: {login: "maint2", type: "User"}}
 ] | map(. + {issue_url: "https://api.github.com/repos/o/r/issues/1", body: "b",
              html_url: "https://github.com/o/r/issues/1", created_at: $ts})' > "$CASE11/fixtures/issue_comments.json"

for cmd in activity contributors repo-stats discussions fetch-interactions; do
  run_collector_env "$CASE11" "SOLEUR_COLLECTOR_COMPACT=1" "$cmd" 1
  assert_rc 0 "$RC" "filters case: compact $cmd exits 0"
  cp "$CASE11/out/stdout" "$CASE11/out.$cmd.json"
done
assert_jq "$CASE11/out.activity.json" '.issues.count == 3 and .pull_requests.count == 4' \
  "compact activity: pull requests are not issues, and PRs older than since are not counted"
assert_jq "$CASE11/out.contributors.json" '. == {commit_total: 3}' \
  "compact contributors: a commit with no login and no author name is not counted"
assert_jq "$CASE11/out.repo-stats.json" '.new_stargazers_count == 2' \
  "compact repo-stats: only stargazers inside the window count"
assert_jq "$CASE11/out.discussions.json" '(.titles | length) == 5' \
  "compact discussions: discussions older than since are not listed"
assert_jq "$CASE11/out.fetch-interactions.json" '. == {external_contributors: 2, interactions_count: 2}' \
  "compact fetch-interactions: bots, [bot] logins, OWNER and MEMBER comments are excluded"

# A numeric-looking but wrong field must fail the projection closed, for EVERY compact command:
# an item that is not an object makes the jq projection error, and the sidecar must carry the cause.
echo "Test 11b: every compact command fails closed with a recorded cause"
for cmd in activity contributors discussions fetch-interactions; do
  C="$(new_case "failclosed_$cmd")"
  gen_repo > "$C/fixtures/repo.json"
  case "$cmd" in
    activity)           jq -nc '[1]' > "$C/fixtures/issues.json"; jq -nc '[1]' > "$C/fixtures/pulls.json" ;;
    contributors)       jq -nc '[1]' > "$C/fixtures/commits.json"; jq -nc '[]|.+[{}]' > "$C/fixtures/issues.json" ;;
    discussions)        jq -nc '{data: null}' > "$C/fixtures/graphql.json" ;;
    fetch-interactions) jq -nc '[1]' > "$C/fixtures/issue_comments.json" ;;
  esac
  run_collector_env "$C" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$C/status" "$cmd" 1
  assert_nonzero_rc "$RC" "compact $cmd exits non-zero on a drifted payload"
  assert_jq "$C/status/collector-status.jsonl" '.cause == "compact-projection-failed"' \
    "compact $cmd records cause=compact-projection-failed"
done

# subscribers_count is a published metric too: a payload without it must fail closed, not print null.
C="$(new_case failclosed_subscribers)"
jq -nc '{stargazers_count: 11, forks_count: 2, watchers_count: 11}' > "$C/fixtures/repo.json"
gen_stargazers 1 16 > "$C/fixtures/stargazers.json"
run_collector_env "$C" "SOLEUR_COLLECTOR_COMPACT=1 SOLEUR_COLLECTOR_STATUS_DIR=$C/status" repo-stats 1
assert_nonzero_rc "$RC" "compact repo-stats exits non-zero when subscribers_count is missing"
assert_file_not_matches "$C/out/stdout" 'subscribers_count' "no compact record is printed without subscribers_count"

# Control characters in a title are neutralised before the slice, so JSON escaping cannot inflate
# a compact line past the inline limit.
echo "Test 11c: control characters in titles cannot inflate the compact line"
C="$(new_case ctrl_titles)"
jq -nc --arg ts "$NOW" '[range(99) | {number: (.+1), title: ("\u0001" * 60), state: "open", user: {login: "u"},
   created_at: $ts, updated_at: $ts, pull_request: null}]' > "$C/fixtures/issues.json"
jq -nc --arg ts "$NOW" '[range(99) | {number: (.+1), title: ("\u0001" * 60), state: "open", user: {login: "u"},
   created_at: $ts, updated_at: $ts, merged_at: null}]' > "$C/fixtures/pulls.json"
run_collector_env "$C" "SOLEUR_COLLECTOR_COMPACT=1" activity 1
assert_rc 0 "$RC" "activity exits 0 on control-character titles"
CTRL_BYTES=$(wc -c < "$C/out/stdout")
if [[ "$CTRL_BYTES" -lt 6000 ]]; then
  echo "  PASS: control-character titles stay under the compact budget ($CTRL_BYTES B)"; PASS=$((PASS + 1))
else
  echo "  FAIL: control-character titles produced $CTRL_BYTES B (budget 6000 B)"; FAIL=$((FAIL + 1))
fi
assert_file_not_matches "$C/out/stdout" '\\u00' "no JSON control-character escapes survive in titles"

echo ""
print_results
