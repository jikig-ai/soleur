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

echo ""
print_results
