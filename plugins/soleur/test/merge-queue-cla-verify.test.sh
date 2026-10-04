#!/usr/bin/env bash
# Suite for scripts/merge-queue-cla-verify.sh (#9454): the verification half of
# .github/workflows/merge-queue-cla-synthetics.yml. The workflow may post a synthetic
# cla-check/cla-evidence on a merge_group candidate ONLY if this script has proven the PR
# head's REAL cla-check/cla-evidence are green. The script must fail closed on every other
# outcome.
#
# HOW THE SEAM IS BUILT: `gh` is a PATH stub that serves synthesized JSON for the endpoints the
# script is allowed to read (pulls/N, commits/PR_HEAD/check-runs; the candidate commit is NOT
# read), records every call, refuses any request it was not told to expect (exit 64), and can be
# told to fail one endpoint. It models the real shapes the script depends on: the check-runs path
# is parsed for its ref (the PR head gets the PR's pages, `main` or the candidate get different
# data), --paginate emits every page as concatenated top-level objects with no outer array while
# a call WITHOUT --paginate returns page 1 only, and a query without filter=all or per_page is
# refused (gh's defaults hide older runs and cap a page at 30).
#
# Cases are plain functions, so the same battery runs against the real script (all must
# pass) and against mutants of it (each mutant must turn the specific row that guards the
# mutated line RED, proven by diffing the mutant against the pristine copy first).
# shellcheck disable=SC2016,SC2329  # sed programs and workflow expressions are literal text; mutate() callees run indirectly
export TMPDIR="${TMPDIR:-/var/tmp}"

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUT_REAL="$REPO_ROOT/scripts/merge-queue-cla-verify.sh"
SANDBOX_PATH="/usr/local/bin:/usr/bin:/bin"

passes=0; fails=0; FAILED=()
QUIET=0; MUT_FAILED=()
pass() { if [[ "$QUIET" -eq 1 ]]; then return 0; fi; passes=$((passes + 1)); echo "  PASS: $1"; }
fail() {
  if [[ "$QUIET" -eq 1 ]]; then MUT_FAILED+=("$1"); return 0; fi
  fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2
}

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=()

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

command -v jq >/dev/null 2>&1 || { echo "[FATAL] jq not found" >&2; exit 2; }

WORK="$(mktemp -d)"; assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

BIN="$WORK/bin"; assert_fixture_dir "$BIN"
mkdir -p "$BIN" || exit 2

# ---- the gh stub ---------------------------------------------------------------------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
# Synthesized gh modelling the real shapes the script depends on. Reads GH_FIX_DIR (pr.json,
# commit.json, cr.<n> = one check-runs page each, main.json = the check-runs of any ref that is
# NOT the PR head) and appends every call (argv) to GH_CALLS. GH_FIX_FAIL=<pr|commit|checks>
# makes that endpoint exit 1. commit.json is only served if a (mutated) script asks for the
# candidate commit.
#   * the check-runs path is parsed for its ref: the PR head gets the cr.* pages, any other ref
#     (main, the candidate) gets main.json, so a script that reads the wrong ref gets different data
#   * with --paginate every page is emitted back to back (top-level objects, no outer array, as
#     the real gh does); WITHOUT it only the first page comes back, so a dropped --paginate is a
#     real behavioural change, not a no-op
#   * the query must carry filter=all and per_page=<n>: gh's default is filter=latest, which
#     hides the older runs, and a missing per_page falls back to 30 per page
set -u
printf '%s\n' "$*" >> "${GH_CALLS:?GH_CALLS unset}"
[[ "${1-}" == "api" ]] || { echo "stub gh: only 'gh api' is expected, got: $*" >&2; exit 64; }
shift
path=""; paginate=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate) paginate=1; shift ;;
    --silent) shift ;;
    -H|--header|--jq|-q) shift 2 ;;
    -*) echo "stub gh: unexpected flag $1 (a read-only verifier sends no write flags)" >&2; exit 64 ;;
    *) path="$1"; shift ;;
  esac
done
fix="${GH_FIX_DIR:?GH_FIX_DIR unset}"
# flaky <endpoint>: true for the first GH_FIX_FLAKY_N (default 1) calls to the endpoint named by GH_FIX_FLAKY, then
# false: a transient 5xx blip that a single retry rides out (the counter lives in the fixture dir).
flaky() {
  local ep="$1" n="${GH_FIX_FLAKY_N:-1}" c=0
  [[ "${GH_FIX_FLAKY-}" == "$ep" ]] || return 1
  [[ -f "$fix/flaky.$ep" ]] && c="$(cat "$fix/flaky.$ep")"
  c=$((c + 1)); printf '%s' "$c" > "$fix/flaky.$ep"
  [[ "$c" -le "$n" ]]
}
case "$path" in
  repos/*/pulls/[0-9]*)
    flaky pr && { echo "gh: HTTP 502 (pulls, transient)" >&2; exit 1; }
    [[ "${GH_FIX_FAIL-}" == "pr" ]] && { echo "gh: HTTP 500 (pulls)" >&2; exit 1; }
    cat "$fix/pr.json" ;;
  repos/*/commits/*/check-runs\?*)
    flaky checks && { echo "gh: HTTP 503 (check-runs, transient)" >&2; exit 1; }
    [[ "${GH_FIX_FAIL-}" == "checks" ]] && { echo "gh: HTTP 500 (check-runs)" >&2; exit 1; }
    [[ "$path" == *"filter=all"* ]] || { echo "stub gh: check-runs query lacks filter=all" >&2; exit 64; }
    [[ "$path" =~ per_page=[0-9]+ ]] || { echo "stub gh: check-runs query lacks per_page" >&2; exit 64; }
    ref="${path#repos/*/commits/}"; ref="${ref%%/check-runs*}"
    head="$(jq -r '.head.sha' "$fix/pr.json")"
    if [[ "$ref" != "$head" ]]; then
      cat "$fix/main.json"
    elif [[ "$paginate" -eq 1 ]]; then
      for page in "$fix"/cr.*; do cat "$page"; done
    else
      cat "$fix/cr.1"
    fi ;;
  repos/*/commits/*)
    [[ "${GH_FIX_FAIL-}" == "commit" ]] && { echo "gh: HTTP 500 (commits)" >&2; exit 1; }
    cat "$fix/commit.json" ;;
  *) echo "stub gh: unexpected path $path" >&2; exit 64 ;;
esac
STUB
chmod +x "$BIN/gh" || exit 2

# ---- fixture builders (synthesized only) ---------------------------------------------------
S40_A="1111111111111111111111111111111111111111"   # PR head
S40_B="2222222222222222222222222222222222222222"   # previous queue candidate (the squash candidate's only parent)
S40_C="3333333333333333333333333333333333333333"   # merge_group head (the candidate)
PR=4242

# cr <name> <app_id> <status> <conclusion|null> <started_at|null> <id>  (started_at "null" = a
# queued run that has not started: the real API sends null, never an empty string)
cr() {
  jq -n --arg n "$1" --argjson a "$2" --arg s "$3" --argjson c "$4" --arg t "$5" --argjson i "$6" \
    '{id:$i,name:$n,status:$s,conclusion:$c,started_at:(if $t == "null" then null else $t end),app:{id:$a,slug:"github-actions"}}'
}

# mkfix <dir> : default = both contexts green on the PR head; the candidate is the real SQUASH
# shape (ONE parent, the previous candidate; the PR head is NOT a parent).
mkfix() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d" || exit 2
  jq -n --arg h "$S40_A" '{number:4242,state:"open",base:{ref:"main"},head:{sha:$h}}' > "$d/pr.json"
  jq -n --arg b "$S40_B" '{sha:"3333333333333333333333333333333333333333",parents:[{sha:$b}]}' > "$d/commit.json"
  # the check-runs of any ref other than the PR head (main, the candidate): nothing useful
  printf '{"total_count":0,"check_runs":[]}\n' > "$d/main.json"
  # one page, as gh prints it
  jq -n --argjson x "$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)" \
        --argjson y "$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)" \
        --argjson z "$(cr test 15368 completed '"success"' 2026-10-03T10:00:02Z 103)" \
        '{total_count:3,check_runs:[$x,$y,$z]}' > "$d/cr.1"
}

# pages <dir> <json-array-of-check_runs>...  : replace the PR head's check-runs reply by N pages
# (cr.1, cr.2, ...). The stub emits them concatenated only for a --paginate call.
pages() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  rm -f "$d"/cr.* || exit 2
  local arr n=0
  for arr in "$@"; do
    n=$((n + 1))
    jq -n --argjson c "$arr" '{total_count:($c|length),check_runs:$c}' > "$d/cr.$n"
  done
}

GOOD_REF="refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"
OUT=""; RC=0; CALLS=""

# run_sut <fixture-dir> [VAR=value ...]: defaults are a valid event; overrides win.
run_sut() {
  local d="$1"; shift
  assert_fixture_dir "$d"
  CALLS="$d/calls.log"; : > "$d/calls.log"
  OUT="$(env -i PATH="$BIN:$SANDBOX_PATH" HOME="$WORK" GH_TOKEN=synthetic-token \
    REPO=example-org/example-repo HEAD_REF="$GOOD_REF" HEAD_SHA="$S40_C" BASE_REF=refs/heads/main \
    MQ_VERIFY_RETRY_DELAY=0 GH_FIX_DIR="$d" GH_CALLS="$CALLS" "$@" bash "$SUT" 2>&1)"
  RC=$?
}

ncalls() { if [[ -s "$CALLS" ]]; then wc -l < "$CALLS" | tr -d ' '; else echo 0; fi; }

# expect_green <label> : rc 0, OK line, and the stub really was consulted (a verifier that
# answers without reading anything is a vacuous pass): the PR read plus the check-runs read.
expect_green() {
  local label="$1"
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK pr=${PR} "* && "$(ncalls)" -ge 2 ]]; then
    pass "$label"
  else
    fail "$label (rc=$RC calls=$(ncalls))"
    [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

# expect_red <label> <anchor> : non-zero, never the OK line, and the output names the failure.
expect_red() {
  local label="$1" anchor="$2"
  if [[ "$RC" -ne 0 && "$OUT" != *"merge-queue-cla-verify=OK"* && "$OUT" == *"$anchor"* ]]; then
    pass "$label"
  else
    fail "$label (rc=$RC, wanted anchor: $anchor)"
    [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$OUT" | head -n 8 >&2
  fi
}

# no_api_calls <label>: validation rejects must happen BEFORE any API call.
expect_no_calls() {
  if [[ "$(ncalls)" -eq 0 ]]; then pass "$1"; else fail "$1 (made $(ncalls) gh call(s))"; fi
}

CASE_N=0
newfix() { CASE_N=$((CASE_N + 1)); FX="$WORK/fx.$CASE_N"; mkfix "$FX"; }

run_cases() {
  # ---- must PASS --------------------------------------------------------------------------
  newfix; run_sut "$FX"
  expect_green "P1 both real contexts green on the PR head"

  # Read-only: the verifier must not post anything (the workflow's later step does).
  if grep -Eq -- ' (-f|-F|-X|--method|--field|--raw-field|--input)( |$)' "$CALLS"; then
    fail "P1b verifier sent a write-shaped gh call"
  else
    pass "P1b every gh call is a read (no -f/-F/-X/--method)"
  fi

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"failure"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"failure"' 2026-10-03T09:00:01Z 91),$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_green "P2 old red then newer green passes (latest run per name)"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"failure"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]" \
              "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_green "P3 newer green on page 2 beats older red on page 1"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  # bot PR: the composite action's synthetic runs (app 15368) are the PR head's only CLA runs
  run_sut "$FX"
  expect_green "P4 bot-PR synthetic cla-check/cla-evidence (app 15368) on the head passes"

  # The real SQUASH shape: single-parent candidate whose parent is not the PR head. Passing here
  # and never asking for the candidate commit is what keeps the queue from deadlocking.
  newfix; run_sut "$FX"
  if [[ "$(jq -r '.parents | length' "$FX/commit.json")" == "1" \
     && "$(jq -r '.parents[0].sha' "$FX/commit.json")" != "$S40_A" ]] \
     && ! grep -Fq -- "commits/${S40_C}" "$CALLS"; then
    expect_green "P5 single-parent squash candidate (parent is not the PR head) passes, candidate never read"
  else
    fail "P5 fixture is not the squash shape or the candidate commit was read"
  fi

  # P6: the PR head has MORE than one page of runs and cla-check exists only on page 2. The stub
  # serves every page only for a --paginate call, so this row is a real pagination test.
  newfix
  filler="$(jq -nc '[range(0;100) | {id:(1000+.),name:("filler-"+tostring),status:"completed",conclusion:"success",started_at:"2026-10-03T08:00:00Z",app:{id:15368,slug:"github-actions"}}]')"
  pages "$FX" "$filler" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_green "P6 cla-check and cla-evidence only on page 2 of 2 are found (--paginate)"

  # P7: the request carries the shapes the API needs and reads the PR head, never main.
  newfix; run_sut "$FX"
  if grep -Fq -- '--paginate' "$CALLS" && grep -Fq -- 'filter=all' "$CALLS" && grep -Fq -- 'per_page=100' "$CALLS" \
     && grep -Fq -- "commits/${S40_A}/check-runs" "$CALLS" && ! grep -Fq -- 'commits/main/' "$CALLS"; then
    pass "P7 check-runs call carries --paginate, filter=all, per_page=100 and reads the PR head ref"
  else
    fail "P7 check-runs call argv is missing --paginate/filter=all/per_page=100 or the PR head ref"
    sed -n 1,5p "$CALLS" >&2
  fi

  # ---- must FAIL --------------------------------------------------------------------------
  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T09:00:01Z 91),$(cr cla-check 15368 completed '"failure"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F1 old green then newer red fails" "cla-check"

  newfix
  pages "$FX" "[$(cr cla-evidence 15368 completed '"success"' 2026-10-03T09:00:00Z 90),$(cr cla-check 15368 completed '"success"' 2026-10-03T09:00:01Z 91)]" \
              "[$(cr cla-evidence 15368 completed '"failure"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F1b newer red on page 2 beats older green on page 1" "cla-evidence"

  # F11: a queued re-run has started_at null. Ordering by started_at sorts it OLDEST, so the stale
  # success of the earlier run would win and the verifier would pass over a re-run still pending.
  # The newest run is the highest id (admin-merge-ready.sh documents the same choice).
  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-check 15368 queued null null 205),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F11 older success then a newer queued re-run (started_at null) fails" "cla-check"

  # F12: id order, not timestamp order: the higher id carries the OLDER started_at.
  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 90),$(cr cla-check 15368 completed '"failure"' 2026-10-03T09:00:00Z 200),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F12 the highest-id cla-check run decides even with an older started_at" "cla-check"

  # F13: a newer re-run that is only queued (not yet completed) after an older RED: not green.
  newfix
  pages "$FX" "[$(cr cla-evidence 15368 completed '"failure"' 2026-10-03T09:00:00Z 90),$(cr cla-evidence 15368 queued null null 200),$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F13 older red then a newer queued re-run is not green" "cla-evidence"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F2 cla-evidence missing fails" "cla-evidence"

  newfix
  pages "$FX" "[$(cr test 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX"
  expect_red "F2b both contexts missing fails" "cla-check"

  newfix
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 in_progress null 2026-10-03T10:00:05Z 102)]"
  run_sut "$FX"
  expect_red "F7 newest cla-evidence run still in progress fails" "cla-evidence"

  newfix
  pages "$FX" "[$(cr cla-check 99999 completed '"success"' 2026-10-03T10:00:00Z 101),$(cr cla-evidence 15368 completed '"success"' 2026-10-03T10:00:01Z 102)]"
  run_sut "$FX"
  expect_red "F6 a success from a different app id (spoof) does not count" "cla-check"

  newfix
  jq -n --arg h "$S40_A" '{number:4242,state:"open",base:{ref:"release"},head:{sha:$h}}' > "$FX/pr.json"
  run_sut "$FX"
  expect_red "F8 PR base is not main fails" "base"

  newfix
  printf '{"number":4242,"base":{"ref":"main"},"head":{"sha":"not-a-sha"}}\n' > "$FX/pr.json"
  run_sut "$FX"
  expect_red "F9 wrong-shape PR head sha fails" "head"

  local ep
  for ep in pr checks; do
    newfix; run_sut "$FX" GH_FIX_FAIL="$ep"
    expect_red "F5-$ep gh error on the $ep endpoint fails" "::error::"
  done

  # T1-T4: one transient gh failure per read is retried once (a healthy PR is not ejected by a blip); a second
  # failure is fatal (bounded: never a third attempt), so a real outage still fails closed.
  ncalls_of() { grep -c -- "$1" "$CALLS" || true; }
  newfix; run_sut "$FX" GH_FIX_FLAKY=pr
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK pr=${PR} "* && "$(ncalls_of 'pulls/')" == "2" ]]; then
    pass "T1 one transient failure reading the PR is retried once and the verify passes (2 PR reads)"
  else
    fail "T1 a single transient PR read failure was not retried (rc=$RC, PR reads=$(ncalls_of 'pulls/'))"
  fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=checks
  if [[ "$RC" -eq 0 && "$OUT" == *"merge-queue-cla-verify=OK pr=${PR} "* && "$(ncalls_of '/check-runs')" == "2" ]]; then
    pass "T2 one transient failure reading the check-runs is retried once and the verify passes (2 check-run reads)"
  else
    fail "T2 a single transient check-runs read failure was not retried (rc=$RC, reads=$(ncalls_of '/check-runs'))"
  fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=pr GH_FIX_FLAKY_N=2
  if [[ "$RC" -ne 0 && "$OUT" == *"gh api failed reading the PR"* && "$(ncalls_of 'pulls/')" == "2" ]]; then
    pass "T3 two consecutive PR read failures fail closed after exactly one retry (2 PR reads, no third)"
  else
    fail "T3 the PR read retry is not bounded to one retry or does not fail closed (rc=$RC, PR reads=$(ncalls_of 'pulls/'))"
  fi
  newfix; run_sut "$FX" GH_FIX_FLAKY=checks GH_FIX_FLAKY_N=2
  if [[ "$RC" -ne 0 && "$OUT" == *"gh api failed reading the PR head check-runs"* && "$OUT" != *"merge-queue-cla-verify=OK"* && "$(ncalls_of '/check-runs')" == "2" ]]; then
    pass "T4 two consecutive check-runs read failures fail closed after exactly one retry (2 reads, no third)"
  else
    fail "T4 the check-runs read retry is not bounded to one retry or does not fail closed (rc=$RC, reads=$(ncalls_of '/check-runs'))"
  fi

  # head_ref shapes: each must be rejected BEFORE any API call.
  local bad idx=0
  local -a bads=(
    ""
    "refs/heads/main"
    "refs/heads/gh-readonly-queue/main/pr-abc-${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-abc123"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}x"
    "refs/heads/gh-readonly-queue/dev/pr-${PR}-${S40_C}"
    "gh-readonly-queue/main/pr-${PR}-${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr--${S40_C}"
    "refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"$'\n'"::error::forged"
  )
  for bad in "${bads[@]}"; do
    idx=$((idx + 1))
    newfix; run_sut "$FX" HEAD_REF="$bad"
    expect_red "F3.$idx unparseable or wrong-shape head_ref is rejected" "head_ref"
    expect_no_calls "F3.$idx ... before any API call"
  done

  newfix; run_sut "$FX" BASE_REF=refs/heads/other
  expect_red "F3b merge_group base_ref other than refs/heads/main is rejected" "base_ref"
  expect_no_calls "F3b ... before any API call"

  newfix; run_sut "$FX" HEAD_SHA="not-40-hex"
  expect_red "F3c head_sha that is not 40 hex is rejected" "head_sha"
  expect_no_calls "F3c ... before any API call"

  newfix; run_sut "$FX" REPO=""
  expect_red "F10 an empty REPO is rejected" "REPO"
  expect_no_calls "F10 ... before any API call"

  # R1/R2: a failing verify leaves a one-line, fixed-vocabulary `reason=` for the workflow's
  # failure-post step (GITHUB_OUTPUT); a passing verify leaves none. Event text never reaches it.
  newfix; : > "$FX/out"
  pages "$FX" "[$(cr cla-check 15368 completed '"success"' 2026-10-03T10:00:00Z 101)]"
  run_sut "$FX" GITHUB_OUTPUT="$FX/out"
  if [[ "$RC" -ne 0 && "$(grep -c '^reason=' "$FX/out")" == "1" && "$(wc -l < "$FX/out" | tr -d ' ')" == "1" \
        && "$(cat "$FX/out")" == *"cla-evidence"* ]]; then
    pass "R1 a verify failure writes exactly one reason= line naming the failed context"
  else
    fail "R1 a verify failure did not write exactly one reason= line (rc=$RC)"
  fi
  newfix; : > "$FX/out"
  run_sut "$FX" GITHUB_OUTPUT="$FX/out" HEAD_REF="refs/heads/gh-readonly-queue/main/pr-${PR}-${S40_C}"$'\n'"forged=1"
  if [[ "$RC" -ne 0 && "$(wc -l < "$FX/out" | tr -d ' ')" == "1" && "$(cat "$FX/out")" != *"forged"* ]]; then
    pass "R2 a forged head_ref never reaches the reason= output"
  else
    fail "R2 the reason= output is not one fixed line, or carries event text (rc=$RC)"
  fi
  newfix; : > "$FX/out"; run_sut "$FX" GITHUB_OUTPUT="$FX/out"
  if [[ "$RC" -eq 0 && ! -s "$FX/out" ]]; then
    pass "R3 a passing verify writes no reason="
  else
    fail "R3 a passing verify wrote output or failed (rc=$RC)"
  fi
}

echo "== merge-queue-cla-verify =="
if [[ ! -f "$SUT_REAL" ]]; then
  fail "scripts/merge-queue-cla-verify.sh is missing"
  echo; echo "=== merge-queue-cla-verify: $passes passed, $fails failed ==="; exit 1
fi

SUT="$SUT_REAL"
run_cases

# ---- mutation battery over the script itself ----------------------------------------------
echo "-- mutants of the script (each must turn its guarding row RED)"
MUTDIR="$WORK/mut"; assert_fixture_dir "$MUTDIR"; mkdir -p "$MUTDIR" || exit 2

# mutant <id> <row-label-that-must-fail> <sed-expression>
mutant() {
  local id="$1" row="$2" expr="$3" m="$MUTDIR/$1.sh" hit=0 f
  cp "$SUT_REAL" "$m" || exit 2
  sed -i "$expr" "$m"
  if cmp -s "$SUT_REAL" "$m"; then fail "mutant $id: mutation did not land"; return; fi
  SUT="$m"; QUIET=1; MUT_FAILED=()
  run_cases
  QUIET=0; SUT="$SUT_REAL"
  for f in "${MUT_FAILED[@]}"; do
    case "$f" in "$row"*) hit=1 ;; esac
  done
  if [[ "$hit" -eq 1 ]]; then
    pass "mutant $id turns row $row RED"
  else
    fail "mutant $id did not turn row $row RED (rows that went red: ${MUT_FAILED[*]:-none})"
  fi
}

# The mutation re-adds the candidate parent check; the squash-shaped row P5 must catch it.
# shellcheck disable=SC2016  # sed expression: $pr_base, ${REPO}, $a are literal text for the mutant
mutant parent  "P5"   '/^\[\[ "\$pr_base" == "main" \]\]/a gh_read "c" "repos/${REPO}/commits/${HEAD_SHA}"; jq -e --arg a "$pr_head" '"'"'[.parents[].sha] | index($a) != null'"'"' <<<"$REPLY_JSON" >/dev/null || die "not a parent"'
# shellcheck disable=SC2016  # sed expressions: $a and ${BASE_REF} are literal text to match
mutant app     "F6"   's/ and \.app\.id == 15368//'
mutant latest  "F1 "  's/^  | last$/  | first/'
# shellcheck disable=SC2016  # sed expression: ${BASE_REF} is literal text
mutant base    "F3b"  's/"\${BASE_REF:-}" == "refs\/heads\/main"/-n "${BASE_REF:-}"/'

mutant paginate "P6" 's/ --paginate / /'
mutant filterall "P1 " 's/filter=all&//'
mutant perpage "P1 " 's/&per_page=100//'
mutant wrongref "P1 " 's/commits\/\${pr_head}\/check-runs/commits\/main\/check-runs/'
# The old ordering ([started_at // "", id]) hides a queued re-run behind the older success.
mutant startedat "F11" 's/sort_by(\.id)/sort_by([(.started_at \/\/ ""), .id])/'
mutant reasonout "R1" '/GITHUB_OUTPUT/d'
# the retry: removing it turns the single-blip rows red; making it unbounded turns the fail-closed rows red
mutant noretry  "T1" 's/for attempt in 1 2; do/for attempt in 1; do/'
mutant unbounded "T3" 's/for attempt in 1 2; do/for attempt in 1 2 3; do/'

# ---- positive controls for the verdict-owning helpers ---------------------------------------
# A helper that stops failing (expect_green, expect_red, expect_no_calls, mutant) turns every row
# that leans on it into a vacuous pass, and the pass count would not move. Each control drives the
# helper ONCE with an input that must fail, requires the failure counter to move (and the pass
# counter not to), then unwinds the counters and the ledger so the suite's own totals are clean.
echo "-- controls: each verdict helper must fail on an input that must fail"
control_fails() {
  local label="$1" want_msg="$2"; shift 2
  local p0="$passes" f0="$fails" n0="${#FAILED[@]}" moved=0 msg_ok=1
  "$@" >/dev/null 2>&1
  [[ "$fails" -eq $((f0 + 1)) && "$passes" -eq "$p0" ]] && moved=1
  if [[ -n "$want_msg" ]]; then
    [[ "${FAILED[$((${#FAILED[@]} - 1))]:-}" == *"$want_msg"* ]] || msg_ok=0
  fi
  passes="$p0"; fails="$f0"; FAILED=("${FAILED[@]:0:$n0}")
  if [[ "$moved" -eq 1 && "$msg_ok" -eq 1 ]]; then
    pass "control: $label fails on an input that must fail"
  else
    fail "control: $label did not record a failure on an input that must fail"
  fi
}
ctl_calls="$WORK/ctl.calls"; assert_fixture_dir "$ctl_calls"
printf 'api a\napi b\n' > "$ctl_calls"
CALLS="$ctl_calls"
RC=1; OUT="boom"
control_fails "expect_green (rc != 0)" "ctl-green-rc" expect_green "ctl-green-rc"
RC=0; OUT="merge-queue-cla-verify=OK pr=${PR} head=x"; : > "$ctl_calls"
control_fails "expect_green (OK line but zero gh calls: vacuous)" "ctl-green-vacuous" expect_green "ctl-green-vacuous"
RC=0; OUT="merge-queue-cla-verify=OK pr=${PR} head=x"
control_fails "expect_red (rc 0)" "ctl-red-rc" expect_red "ctl-red-rc" "OK"
RC=1; OUT="::error::merge-queue-cla-verify: something else"
control_fails "expect_red (anchor absent)" "ctl-red-anchor" expect_red "ctl-red-anchor" "cla-evidence"
printf 'api a\n' > "$ctl_calls"
control_fails "expect_no_calls (a call was made)" "ctl-nocalls" expect_no_calls "ctl-nocalls"
# mutant(): a mutation that lands but is guarded by no failing row must be reported, never passed.
control_fails "mutant() (landed mutation that turns no row red)" "did not turn row" mutant ctl-harmless "P1 " '$a # harmless'
control_fails "mutant() (mutation that does not land)" "did not land" mutant ctl-noland "P1 " 's/^NO_SUCH_LINE_ANYWHERE$/x/'

echo
echo "=== merge-queue-cla-verify: $passes passed, $fails failed ==="
# Exact assertion floor: a deleted row or neutered helper changes the count, which a
# "no failures" verdict alone would not notice.
EXPECTED_PASSES=73
if [[ "$fails" -eq 0 && "$passes" -ne "$EXPECTED_PASSES" ]]; then
  printf 'FAIL: %s assertions passed, the floor is exactly %s\n' "$passes" "$EXPECTED_PASSES" >&2
  exit 1
fi
if [[ "$fails" -ne 0 ]]; then
  printf 'FAILED: %s\n' "${FAILED[@]}" >&2
  exit 1
fi
exit 0
