#!/usr/bin/env bash
# Tests for scripts/prod-version-drift-check.sh (#7091) — the production version-drift alerter.
#
# THREE PARTS, ALL LOAD-BEARING:
#
#   PART A -- the pure classifier, driven directly. Every fixture asserts an EXIT CODE, not a
#   message, because the exit code is what the workflow branches on. The fixture set includes
#   rows where `build_sha` and `version` DISAGREE (A16/A17): whenever a comment argues "we key
#   on X, not Y", the fixtures must contain a case where X and Y differ, or the claim is
#   untested. A6 additionally drives the oldest-commit EXTRACTION, because the choice of
#   oldest-vs-newest lives in main(), not in the classifier, and a classifier fixture alone
#   could never see it.
#
#   PART B -- wiring pins extracted from the SHIPPED workflow via PyYAML. A hermetic unit test
#   stays green after the workflow's call site is deleted or relocated, so the properties that
#   live only in the YAML (the alert `if:` conditions, fetch-depth, the label bootstrap
#   ordering, the heartbeat allowlist) are asserted against the real file. Every step selector
#   carries an exactly-one cardinality assertion so a rename breaks LOUDLY rather than
#   silently extracting nothing.
#
#   PART C -- mutation battery. Part A and Part B can both be green against a checker that is
#   wired wrong, so each axis sabotages one property, asserts the sabotage LANDED (diff -q),
#   and requires the suite to go RED. The unmutated control runs FIRST and must be green: a
#   battery scored against a red baseline is void.
#
# Exit contract: 0 clean; 1 findings OR assertion-count regression below MIN_ASSERTIONS.
#
# NOTE ON `set -e`: deliberately absent (`set -uo pipefail` only), matching
# scripts/lint-workflow-step-env-refs.test.sh. Assertions must accumulate, not abort.

set -uo pipefail

# `/tmp` is a machine-global 4 GiB tmpfs shared by parallel worktrees; a direct invocation of
# this suite (the inner loop while editing the checker) inherits the bare `/tmp` where
# test-all.sh would have defaulted it. A sandbox harness whose `cp` fails silently reports
# verdicts about the SUT that are really verdicts about another session's disk usage.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Overridable so Part C can point the whole suite at a mutated sandbox copy.
SUT="${DRIFT_TEST_SCRIPT:-$SCRIPT_DIR/prod-version-drift-check.sh}"
WORKFLOW="${DRIFT_TEST_WORKFLOW:-$REPO_ROOT/.github/workflows/scheduled-prod-version-drift.yml}"
RELEASE_WORKFLOW="${DRIFT_TEST_RELEASE_WORKFLOW:-$REPO_ROOT/.github/workflows/web-platform-release.yml}"
MONITORS_TF="${DRIFT_TEST_MONITORS_TF:-$REPO_ROOT/apps/web-platform/infra/sentry/cron-monitors.tf}"

# Part C re-invokes this file against a sandbox; the guard stops infinite recursion.
MUTATION_CHILD="${DRIFT_MUTATION_CHILD:-0}"
# Which parts to run. Part C children run "AB" so they exercise the assertions without
# recursing into the battery.
PARTS="${DRIFT_TEST_PARTS:-ABC}"

PASS=0
FAIL=0
# Anti-vacuity floors: if a future edit deletes an assertion block, the suite must fail even
# though nothing "failed". Raise these deliberately when adding coverage.
#
# PER-PART, not just global. A single global floor set well below the real total is slack that
# hides a whole part: at 58 against 79 actual, `if false; then` on the Part C dispatch deleted
# the entire mutation battery -- the suite's own anti-vacuity mechanism -- and still exited 0.
# A part-level floor makes that a loud "Part C shrank" instead of a silent pass, and gives a
# better failure message than a total ever could.
# FLOORS CATCH DELETION, NOT COLLAPSE. The `FAIL > 0` early exit precedes every floor check
# below, so a block that degrades into a single failing assertion can never trip one. They are
# a tripwire against a block being REMOVED, and nothing more -- do not read a green floor as
# evidence that the assertions still mean what they meant.
MIN_ASSERTIONS="${DRIFT_MIN_ASSERTIONS:-151}"
MIN_A="${DRIFT_MIN_A:-57}"
# 49 -> 81 (#7304): B14 both-direction execution x3 arms + self-check, B14b,
# B15/B15b/B15c, B16/B16b/B16c, B17/B17b/B17c.
MIN_B="${DRIFT_MIN_B:-81}"
# 11 -> 13 (#7304): axis11 (errexit clear) + axis12 (outcome conjunct).
MIN_C="${DRIFT_MIN_C:-13}"
COUNT_A=0
COUNT_B=0
COUNT_C=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() {
  echo "  FAIL: $1"
  [[ $# -ge 2 ]] && echo "    expected: $2"
  [[ $# -ge 3 ]] && echo "    actual:   $3"
  FAIL=$((FAIL + 1))
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  # assert_contains <desc> <needle-ERE> <haystack>
  if printf '%s' "$3" | grep -Eq -- "$2"; then pass "$1"; else fail "$1" "matches /$2/" "$3"; fi
}
assert_not_contains() {
  if printf '%s' "$3" | grep -Eq -- "$2"; then fail "$1" "does NOT match /$2/" "$3"; else pass "$1"; fi
}

TMP="$(mktemp -d "${TMPDIR%/}/prod-version-drift-test.XXXXXXXX")" || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# PART A -- the pure classifier
# ---------------------------------------------------------------------------

# Threshold in seconds, re-derived from the SUT rather than hardcoded here, so the two cannot
# drift apart silently. (B9 separately asserts the SUT's value is >= the pipeline's own
# declared serial ceiling — this only keeps the fixtures honest.)
THRESH_MIN=""
THRESH_S=""

run_part_a() {
  echo "=== PART A: classifier fixtures ==="

  if [[ ! -f "$SUT" ]]; then
    fail "A0 the checker exists at $SUT" "a readable file" "absent"
    return 0
  fi
  # shellcheck source=/dev/null
  if ! source "$SUT"; then
    fail "A0 the checker is sourceable without executing main()" "source rc=0" "source failed"
    return 0
  fi
  pass "A0 the checker exists and is sourceable"

  if ! declare -F classify_drift >/dev/null; then
    fail "A0b classify_drift() is defined" "a function" "undefined"
    return 0
  fi
  if ! declare -F oldest_epoch_from_log >/dev/null; then
    fail "A0c oldest_epoch_from_log() is defined" "a function" "undefined"
    return 0
  fi
  pass "A0b classify_drift() and oldest_epoch_from_log() are defined"

  THRESH_MIN="${DRIFT_SUSTAINED_THRESHOLD_MIN:-}"
  if ! [[ "$THRESH_MIN" =~ ^[0-9]+$ ]]; then
    fail "A0d DRIFT_SUSTAINED_THRESHOLD_MIN is a bare integer" "^[0-9]+$" "${THRESH_MIN:-<unset>}"
    return 0
  fi
  THRESH_S=$((THRESH_MIN * 60))
  pass "A0d DRIFT_SUSTAINED_THRESHOLD_MIN is an integer (${THRESH_MIN})"

  local NOW=1900000000
  local SHA_A="b35736dedacd0fb4339952af800ac23996dddd28"
  local OK_JSON
  OK_JSON="$(printf '{"status":"ok","version":"0.247.6","build_sha":"%s","uptime":123}' "$SHA_A")"

  # classify_drift must be called DIRECTLY (never in `$( )`): it sets caller-visible globals,
  # and a subshell would discard every one of them while still yielding a plausible exit code.
  local rc
  _classify() {
    DRIFT_VERDICT=""; DRIFT_REASON=""
    classify_drift "$@"
    rc=$?
  }

  # --- the three core verdicts -------------------------------------------------
  _classify "$OK_JSON" 0 0 "" 0 "$NOW"
  assert_eq "A1 count==0 -> exit 0" "0" "$rc"
  assert_eq "A1b count==0 -> CLEAN" "CLEAN" "$DRIFT_VERDICT"

  _classify "$OK_JSON" 0 2 "$((NOW - THRESH_S + 60))" 0 "$NOW"
  assert_eq "A2 count>0, age just UNDER threshold -> exit 0" "0" "$rc"
  assert_eq "A2b -> DRIFT_PENDING (a release is legitimately in flight)" "DRIFT_PENDING" "$DRIFT_VERDICT"

  _classify "$OK_JSON" 0 2 "$((NOW - THRESH_S - 60))" 0 "$NOW"
  assert_eq "A3 count>0, age just OVER threshold -> exit 1" "1" "$rc"
  assert_eq "A3b -> DRIFT_SUSTAINED" "DRIFT_SUSTAINED" "$DRIFT_VERDICT"

  # --- prod ahead / operator-caused ---------------------------------------------
  # The workflow_dispatch/force_run case: prod deployed a commit that does not match the path
  # filter, so it is AHEAD of the newest qualifying commit. The range is empty -> no special
  # case needed. This is the false-positive class a plain equality test would have shipped.
  _classify "$OK_JSON" 0 0 "" 0 "$NOW"
  assert_eq "A4 prod AHEAD (force_run dispatch) -> CLEAN, not a false alarm" "CLEAN" "$DRIFT_VERDICT"

  # skip_deploy: prod is DELIBERATELY behind. This is a TRUE positive -- the operator caused
  # it, and it auto-closes on the next deploy. Documented rather than special-cased, because
  # suppressing it would need state the checker deliberately does not keep.
  _classify "$OK_JSON" 0 5 "$((NOW - THRESH_S - 3600))" 0 "$NOW"
  assert_eq "A5 skip_deploy dispatch -> DRIFT_SUSTAINED (a true positive, documented)" "1" "$rc"

  # --- A6: the clock does not reset -------------------------------------------
  # The hole this pins: if qualifying commits keep landing while deploy is broken, a
  # NEWEST-commit clock resets on every one and never escalates while prod rots. The choice
  # lives in main()'s extraction, so a classifier fixture alone cannot see it -- drive the
  # extraction function directly with a log whose oldest and newest differ.
  local OLDEST=$((NOW - THRESH_S - 7200))
  local NEWEST=$((NOW - 60))
  local LOGFIX
  LOGFIX="$(printf '%s %s\n%s %s\n%s %s\n' \
    "aaaaaaa" "$NEWEST" "bbbbbbb" "$((NOW - 1800))" "ccccccc" "$OLDEST")"
  local got
  got="$(printf '%s\n' "$LOGFIX" | oldest_epoch_from_log)"
  assert_eq "A6 oldest_epoch_from_log picks the OLDEST, not the newest" "$OLDEST" "$got"

  # ...and reversed input, because reverse-chronological row order is git's DEFAULT, not a
  # documented contract: a positional read (head -1 / tail -1) must not be what makes this pass.
  local LOGFIX_REV
  LOGFIX_REV="$(printf '%s %s\n%s %s\n%s %s\n' \
    "ccccccc" "$OLDEST" "bbbbbbb" "$((NOW - 1800))" "aaaaaaa" "$NEWEST")"
  got="$(printf '%s\n' "$LOGFIX_REV" | oldest_epoch_from_log)"
  assert_eq "A6b oldest_epoch_from_log is order-independent (numeric min, not positional)" "$OLDEST" "$got"

  _classify "$OK_JSON" 0 3 "$OLDEST" 0 "$NOW"
  assert_eq "A6c new commits land but the OLDEST stays stale -> still DRIFT_SUSTAINED" "1" "$rc"

  # A7: multi-commit push where an earlier commit matched the path filter but the push TIP did
  # not, so check_changed said false and deploy silently no-opped. The range query sees the
  # earlier commit; a tip-only comparison would not.
  _classify "$OK_JSON" 0 1 "$((NOW - THRESH_S - 600))" 0 "$NOW"
  assert_eq "A7 silent no-op from a multi-commit push -> DRIFT_SUSTAINED" "1" "$rc"

  # --- CHECK_ERROR: every way of not knowing --------------------------------
  # The whole point of a third verdict: "we could not evaluate" must never be encoded as
  # "no drift". Each of these would read as CLEAN under a two-state design.
  _classify "$OK_JSON" 0 0 "" 128 "$NOW"
  assert_eq "A8 git range query failed (unknown prod SHA) -> exit 2" "2" "$rc"
  assert_eq "A8b -> CHECK_ERROR" "CHECK_ERROR" "$DRIFT_VERDICT"

  _classify "" 28 "" "" 0 "$NOW"
  assert_eq "A9 curl exhausted retries (rc 28 timeout) -> exit 2" "2" "$rc"
  assert_contains "A9b reason names the curl rc" "28" "$DRIFT_REASON"

  _classify "" 6 "" "" 0 "$NOW"
  assert_eq "A10 curl rc 6 (DNS failure) -> exit 2" "2" "$rc"

  # jq -r .build_sha prints the literal string "null" for BOTH {} and {"build_sha":null}.
  # Measured -- both exit 0, so an unguarded consumer treats "null" as a SHA.
  #
  # These rows pass a VALID count (0) deliberately. Passing an empty count would let the
  # count validation produce CHECK_ERROR on its own, so the fixture would stay green with the
  # SHA validation deleted -- it would be asserting the wrong guard. With count=0, removing
  # the 40-hex check makes these return CLEAN, which is exactly what axis 10 must catch.
  _classify '{}' 0 0 "" 0 "$NOW"
  assert_eq "A11 body {} -> jq yields literal 'null' -> exit 2" "2" "$rc"

  _classify '{"build_sha":null}' 0 0 "" 0 "$NOW"
  assert_eq "A11b explicit JSON null -> exit 2" "2" "$rc"

  _classify '{"build_sha":""}' 0 0 "" 0 "$NOW"
  assert_eq "A12 empty build_sha -> exit 2" "2" "$rc"

  _classify '{"build_sha":"not-a-sha"}' 0 0 "" 0 "$NOW"
  assert_eq "A13 non-hex build_sha -> exit 2" "2" "$rc"

  _classify '{"build_sha":"abc123"}' 0 0 "" 0 "$NOW"
  assert_eq "A13b short (non-40) build_sha -> exit 2" "2" "$rc"

  _classify '{"build_sha":"ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"}' 0 0 "" 0 "$NOW"
  assert_eq "A13c 40 chars but non-hex -> exit 2" "2" "$rc"

  _classify '<html><body>502 Bad Gateway</body></html>' 0 0 "" 0 "$NOW"
  assert_eq "A14 HTTP 200 with an HTML body -> exit 2" "2" "$rc"

  _classify "$OK_JSON" 0 2 "not-an-epoch" 0 "$NOW"
  assert_eq "A15 unparseable oldest_epoch -> exit 2 (never 'no drift')" "2" "$rc"

  _classify "$OK_JSON" 0 "not-a-number" "" 0 "$NOW"
  assert_eq "A15b unparseable missing_count -> exit 2" "2" "$rc"

  # --- A15c/A15d: the ONE path that echoes unvalidated input back at a human -------------
  # DRIFT_DETAIL is interpolated into a GitHub issue body AND into an HTML email body inside
  # <code>...</code>. The workflow's strip_log_injection removes CONTROL characters only and
  # does NOT escape markup, so without a charset restriction at the source a hostile or MITM'd
  # /health could inject markup into the alert that exists to say /health is untrustworthy.
  _classify '{"build_sha":"<img src=x onerror=alert(1)>"}' 0 0 "" 0 "$NOW"
  assert_eq "A15c markup build_sha -> still exit 2" "2" "$rc"
  assert_not_contains "A15c-b DRIFT_DETAIL never echoes raw markup back into issue/email bodies" \
    "[<>]" "$DRIFT_DETAIL"

  # Unbounded echo is the same class: a megabyte of junk in build_sha must not become a
  # megabyte of issue body. 64 chars is comfortably above the 40 a real SHA needs.
  local LONG_SHA
  LONG_SHA="$(printf 'a%.0s' $(seq 1 500))"
  _classify "{\"build_sha\":\"${LONG_SHA}\"}" 0 0 "" 0 "$NOW"
  assert_eq "A15d overlong build_sha -> exit 2" "2" "$rc"
  if [[ "${#DRIFT_DETAIL}" -le 200 ]]; then
    pass "A15d-b DRIFT_DETAIL stays bounded (${#DRIFT_DETAIL} chars) on an overlong build_sha"
  else
    fail "A15d-b DRIFT_DETAIL stays bounded" "<= 200 chars" "${#DRIFT_DETAIL}"
  fi

  # --- A16/A17: build_sha vs version DISAGREE ---------------------------------
  # The plan argues "compare build_sha, not version", because version only advances when the
  # release job tags -- on a skipped deploy it can look plausible while the image is stale.
  # These two rows are what make that claim testable rather than decorative.
  local DISAGREE_JSON
  DISAGREE_JSON='{"status":"ok","version":"0.247.6","build_sha":"1111111111111111111111111111111111111111"}'
  _classify "$DISAGREE_JSON" 0 4 "$((NOW - THRESH_S - 60))" 0 "$NOW"
  assert_eq "A16 version matches but build_sha differs + stale -> DRIFT_SUSTAINED" "1" "$rc"

  _classify '{"version":"0.0.0-old","build_sha":"'"$SHA_A"'"}' 0 0 "" 0 "$NOW"
  assert_eq "A17 converse: version differs but build_sha current -> CLEAN" "0" "$rc"
  assert_eq "A17b -> CLEAN (we do not key on version)" "CLEAN" "$DRIFT_VERDICT"

  # --- boundary discipline -----------------------------------------------------
  # Exactly AT the threshold must not alert: the comparison is strictly-greater, so a
  # legitimate release finishing at its declared ceiling is not paged.
  _classify "$OK_JSON" 0 1 "$((NOW - THRESH_S))" 0 "$NOW"
  assert_eq "A18 age EXACTLY at threshold -> DRIFT_PENDING (strict >, no boundary page)" "0" "$rc"

  # --- A19/A19b: an implausible clock is a FAILURE TO MEASURE, both directions ----------
  # A previous revision asserted `rc=0` here ("a future-dated commit must not underflow into a
  # huge age and page") and so pinned the alarm's own silence as intended behaviour. The
  # underflow concern was real, the remedy was backwards: %ct is committer-settable, the clock
  # takes the numeric MINIMUM, so one bad timestamp decides the verdict. Future-dated meant a
  # negative age that can never exceed the threshold -- silent for as long as the skew lasted,
  # with the heartbeat checking in `ok`. Both directions must reach CHECK_ERROR, which alerts on
  # its own channel and names the clock rather than production.
  _classify "$OK_JSON" 0 1 "$((NOW + 600))" 0 "$NOW"
  assert_eq "A19 future-dated commit -> CHECK_ERROR, never a silent pass" "2" "$rc"
  assert_eq "A19b -> reason names the future date" "future_dated_commit" "$DRIFT_REASON"

  # The converse: the minimum-taking clock means one absurdly-old commit (epoch 0, an import, a
  # mis-rebase) would otherwise page instantly regardless of real staleness.
  _classify "$OK_JSON" 0 1 "$((NOW - 200 * 24 * 3600))" 0 "$NOW"
  assert_eq "A19c absurdly-old commit date -> CHECK_ERROR, not an instant page" "2" "$rc"
  assert_eq "A19d -> reason names the implausible date" "implausible_commit_date" "$DRIFT_REASON"

  # ...and the guard must not swallow a REAL sustained drift just inside the bound. Without this
  # row the two fixtures above are satisfied by a guard that rejects everything.
  _classify "$OK_JSON" 0 1 "$((NOW - 3 * 24 * 3600))" 0 "$NOW"
  assert_eq "A19e a genuinely 3-day-old undeployed commit still pages (guard is not a blanket)" "1" "$rc"
  assert_eq "A19f -> DRIFT_SUSTAINED" "DRIFT_SUSTAINED" "$DRIFT_VERDICT"

  # Ordering: an evaluation failure outranks a drift signal. If we could not read prod, we do
  # not get to claim we know prod is stale.
  _classify "" 28 5 "$((NOW - THRESH_S - 60))" 0 "$NOW"
  assert_eq "A20 curl failure outranks a stale-looking count -> CHECK_ERROR" "2" "$rc"

  # A20b -- prod serving a sha that is NOT an ancestor of main. main() signals this with the
  # sentinel rc 64, distinct from a plain range failure, so the operator learns WHICH thing is
  # odd. Without the ancestry guard the range resolves rc=0 against the merge-base and pages a
  # confident, wildly wrong age.
  _classify "$OK_JSON" 0 0 "" 64 "$NOW"
  assert_eq "A20b prod sha off main's first-parent chain -> CHECK_ERROR" "2" "$rc"
  assert_eq "A20c -> reason names the ancestry problem, not a generic query failure" \
    "prod_sha_not_on_main" "$DRIFT_REASON"

  run_main_smoke
}

# --- A21+: main() ------------------------------------------------------------------------
# Until this existed, ZERO assertions executed main(): Part A drove classify_drift and
# oldest_epoch_from_log directly, and A0 asserted only that sourcing does NOT run main. So the
# entire I/O half was unpinned, and each of these mutations left the suite fully green:
#   * repoint the default PROD_HEALTH_URL at staging  -> the alarm monitors the wrong host,
#     forever, while looking perfectly healthy
#   * `for attempt in 1 2 3` -> `1`                   -> the retry the check-error step cites as
#     "what keeps this from being noisy" is gone; one blip files an issue AND emails ops
#   * rename any DRIFT_*= output key                  -> the workflow greps nothing; issues and
#     emails ship with empty detail while every alert still fires
# Driven with curl/git/date stubbed on PATH, so it is hermetic and clock-free.
run_main_smoke() {
  local sdir="$TMP/stubs" work="$TMP/mainsmoke"
  mkdir -p "$sdir" "$work" || { fail "A21 smoke setup" "mkdir rc=0" "failed"; return 0; }

  cat > "$sdir/date" <<'STUB'
#!/usr/bin/env bash
echo 1900000000
STUB
  cat > "$sdir/git" <<'STUB'
#!/usr/bin/env bash
# `merge-base --is-ancestor` answers by exit code; GIT_STUB_NOT_ANCESTOR makes it say no.
if [[ "${1:-}" == "merge-base" ]]; then
  [[ -n "${GIT_STUB_NOT_ANCESTOR:-}" ]] && exit 1
  exit 0
fi
# Emit N `<sha> <ct>` rows per GIT_STUB_ROWS; default none (prod is current).
[[ -n "${GIT_STUB_FAIL:-}" ]] && exit 128
for i in $(seq 1 "${GIT_STUB_ROWS:-0}"); do
  echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa$i 1899000000"
done
exit 0
STUB
  # Fails for the first CURL_STUB_FAILS invocations, then succeeds. The counter file makes the
  # retry COUNT observable: a single-attempt loop can never reach the success arm.
  cat > "$sdir/curl" <<'STUB'
#!/usr/bin/env bash
n=$(cat "$CURL_COUNT_FILE" 2>/dev/null || echo 0)
n=$((n + 1)); echo "$n" > "$CURL_COUNT_FILE"
if [[ "$n" -le "${CURL_STUB_FAILS:-0}" ]]; then exit 7; fi
printf '{"status":"ok","version":"9.9.9","build_sha":"b35736dedacd0fb4339952af800ac23996dddd28"}'
STUB
  chmod +x "$sdir/date" "$sdir/git" "$sdir/curl" || true

  local out rc cnt
  export CURL_COUNT_FILE="$work/curl.count"
  # Zero the backoff: these cases drive the REAL retry loop (the count assertions below prove
  # it), they just must not spend 15s of wall clock each doing it -- 11 battery children pay
  # this cost too, which took the suite from ~10s to over six minutes.
  export DRIFT_RETRY_BACKOFF_S=0

  # A21 -- happy path: every documented output key is present, exactly once, and CLEAN.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=0 GIT_STUB_ROWS=0 bash "$SUT" 2>&1)"; rc=$?
  assert_eq "A21 main() on a current prod -> exit 0" "0" "$rc"
  assert_contains "A21b main() emits DRIFT_VERDICT=CLEAN" "^DRIFT_VERDICT=CLEAN$" "$out"
  local k missing_keys=""
  for k in DRIFT_VERDICT DRIFT_REASON DRIFT_DETAIL DRIFT_MISSING_COUNT DRIFT_PATHSPEC DRIFT_HEALTH_URL DRIFT_MISSING_SHAS; do
    printf '%s\n' "$out" | grep -q "^${k}=" || missing_keys="${missing_keys}${k} "
  done
  assert_eq "A21c main() emits every documented output key" "" "$missing_keys"

  # A22 -- the retry budget, observed rather than asserted from the source. Two failures then a
  # success must still reach CLEAN; a loop of one cannot.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=2 GIT_STUB_ROWS=0 bash "$SUT" 2>&1)"; rc=$?
  cnt="$(cat "$CURL_COUNT_FILE" 2>/dev/null || echo 0)"
  assert_eq "A22 main() survives 2 transient curl failures -> exit 0" "0" "$rc"
  assert_eq "A22b ...having actually retried 3 times" "3" "$cnt"

  # A23 -- exhausted retries fail CLOSED, and the count proves the budget is bounded.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=99 GIT_STUB_ROWS=0 bash "$SUT" 2>&1)"; rc=$?
  cnt="$(cat "$CURL_COUNT_FILE" 2>/dev/null || echo 0)"
  assert_eq "A23 main() with prod unreachable -> CHECK_ERROR (2), never CLEAN" "2" "$rc"
  assert_eq "A23b ...after exactly 3 attempts, not an unbounded loop" "3" "$cnt"

  # A24 -- a failed range query must reach CHECK_ERROR through main(), not read as CLEAN.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=0 GIT_STUB_FAIL=1 bash "$SUT" 2>&1)"; rc=$?
  assert_eq "A24 main() with a failing git range query -> CHECK_ERROR" "2" "$rc"

  # A24b -- the ancestry guard, reached through main() rather than asserted from the source.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=0 GIT_STUB_NOT_ANCESTOR=1 bash "$SUT" 2>&1)"; rc=$?
  assert_eq "A24b main() with prod off main's chain -> CHECK_ERROR" "2" "$rc"
  assert_contains "A24c ...naming the ancestry problem" "^DRIFT_REASON=prod_sha_not_on_main$" "$out"

  # A25 -- the default endpoint. A silent repoint at staging is invisible to every other
  # assertion here and to the workflow, and the alarm would look healthy forever.
  : > "$CURL_COUNT_FILE"
  out="$(PATH="$sdir:$PATH" CURL_STUB_FAILS=0 GIT_STUB_ROWS=0 bash "$SUT" 2>&1)"
  assert_contains "A25 main() defaults to the PRODUCTION health endpoint" \
    "^DRIFT_HEALTH_URL=https://app\\.soleur\\.ai/health$" "$out"

  unset CURL_COUNT_FILE DRIFT_RETRY_BACKOFF_S
}

# ---------------------------------------------------------------------------
# PART B -- wiring pins against the SHIPPED workflow
# ---------------------------------------------------------------------------

# Emits key=value lines the shell can read. Every step selector asserts exactly-one
# cardinality, so a rename fails loudly instead of extracting nothing.
PYEXTRACT='
import sys, os, yaml, json, re

wf_path, rel_path = sys.argv[1], sys.argv[2]
try:
    wf = yaml.safe_load(open(wf_path))
except Exception as e:
    print("EXTRACT_ERROR=%s" % str(e).replace("\n", " ")); sys.exit(0)
if not isinstance(wf, dict):
    print("EXTRACT_ERROR=workflow did not parse to a mapping"); sys.exit(0)

def emit(k, v):
    print("%s=%s" % (k, str(v).replace("\n", "\\n")))

def code(st):
    # A step run: body with COMMENT LINES REMOVED.
    #
    # Every body matcher below reads this, never st["run"] directly. A grep over a raw body
    # cannot tell code from prose, and that cuts both ways: the ordering pin (B5) false-FAILED
    # on a comment that named the commands in explanatory order, and any must-not-contain
    # assertion is satisfiable by prose. The earlier workaround -- rewording the workflow to
    # avoid tripping the tests -- pointed the coupling the wrong way, making a matcher here a
    # constraint on how the production artifact may be documented. Strip here instead.
    #
    # Deliberately line-based: a hash inside a string literal is not a comment, so only lines
    # whose first non-space character starts a comment are dropped.
    #
    # NOTE: this whole program is a SINGLE-QUOTED bash string, so it must contain no
    # apostrophes at all -- one would terminate the string and the shell would try to execute
    # the prose. That is exactly what happened when this docstring was first written.
    body = st.get("run") or ""
    return "\n".join(l for l in body.split("\n") if not l.lstrip().startswith("#"))

jobs = wf.get("jobs") or {}
steps = []
for jname, job in jobs.items():
    for st in (job.get("steps") or []):
        steps.append((jname, st))
emit("STEP_COUNT", len(steps))

def by_id(sid):
    return [s for (_, s) in steps if s.get("id") == sid]

# --- B1: the call site exists, in a job, not buried in a retry loop -----------
runs = [(j, s) for (j, s) in steps if isinstance(s.get("run"), str)
        and re.search(r"(^|[;&|(]|\s)bash\s+scripts/prod-version-drift-check\.sh", code(s), re.M)]
emit("CALLSITE_COUNT", len(runs))
if runs:
    emit("CALLSITE_JOB", runs[0][0])
    body = code(runs[0][1])
    # A call nested in a poll/retry loop would re-run the checker and mask a transient.
    emit("CALLSITE_IN_LOOP", int(bool(re.search(r"^\s*(while|until|for)\b", body, re.M))))
    emit("CALLSITE_STEP_ID", runs[0][1].get("id", ""))

# --- B2: checkout depth ------------------------------------------------------
co = [s for (_, s) in steps if isinstance(s.get("uses"), str) and "actions/checkout" in s["uses"]]
emit("CHECKOUT_COUNT", len(co))
if co:
    emit("CHECKOUT_FETCH_DEPTH", (co[0].get("with") or {}).get("fetch-depth", "<unset>"))

# --- B3/B4/B6: alert-step conditions -----------------------------------------
# Normalise whitespace so the comparison is about structure, not formatting.
def norm(x):
    return re.sub(r"\s+", " ", str(x)).strip()

alerting = []   # steps that can notify a human (issue / email), i.e. must never fire when clean
for (_, s) in steps:
    body = code(s)
    uses = s.get("uses") or ""
    if ("gh issue create" in body or "gh issue comment" in body
            or "api.resend.com" in body or "notify-ops-email" in uses):
        # the close-on-recovery step touches gh issue close, not create/comment
        alerting.append(s)
emit("ALERT_STEP_COUNT", len(alerting))

# A verdict conjunct is any form that BINDS the step to a non-clean verdict class:
#   drift        -> exit_code == \x271\x27
#   cannot-eval  -> exit_code == \x272\x27, or the wider "not 0 and not 1" form that also
#                   catches 127/126/124/139 (a checker that never reached its reporting path)
def _drift_gated(cond):
    return "exit_code == \x271\x27" in cond
def _err_gated(cond):
    if "exit_code == \x272\x27" in cond:
        return True
    return ("exit_code != \x270\x27" in cond) and ("exit_code != \x271\x27" in cond)

bad = [norm(s.get("if", "")) for s in alerting
       if not _drift_gated(norm(s.get("if", ""))) and not _err_gated(norm(s.get("if", "")))]
emit("ALERT_STEPS_WITHOUT_VERDICT_CONJUNCT", len(bad))
if bad:
    emit("ALERT_BAD_IF", bad[0])
emit("ALERT_STEPS_GATED_ON_DRIFT", len([s for s in alerting if _drift_gated(norm(s.get("if", "")))]))
emit("ALERT_STEPS_GATED_ON_CHECK_ERROR", len([s for s in alerting if _err_gated(norm(s.get("if", "")))]))
# B4: no alerting step may be reachable on a clean tick.
emit("ALERT_STEPS_REACHABLE_WHEN_CLEAN",
     len([s for s in alerting if "exit_code == \x270\x27" in norm(s.get("if", ""))]))

closers = [s for (_, s) in steps if "gh issue close" in code(s)]
emit("CLOSE_STEP_COUNT", len(closers))
close_ifs = [norm(s.get("if", "")) for s in closers]
# The drift issue closes ONLY on a genuinely clean verdict. exit_code == 0 is CLEAN UNION
# DRIFT_PENDING, so gating on it closed the issue while commits were still undeployed and
# posted a recovery message contradicted by its own interpolated verdict.
emit("CLOSE_STEPS_GATED_ON_CLEAN_VERDICT", len([c for c in close_ifs if "verdict == \x27CLEAN\x27" in c]))
# The check-error issue closes as soon as the checker reaches ANY verdict (exit 0 or 1) --
# otherwise a fixed misconfiguration could not close while a real drift was sustained.
emit("CLOSE_STEPS_GATED_ON_EVALUATED", len([c for c in close_ifs
     if "exit_code == \x270\x27" in c and "exit_code == \x271\x27" in c]))
# No closer may key on the bare exit-0 form alone (the defect above).
emit("CLOSE_STEPS_ON_BARE_EXIT0", len([c for c in close_ifs
     if "exit_code == \x270\x27" in c and "exit_code == \x271\x27" not in c]))

# --- B5: label bootstrap precedes every issue create, in the same body --------
viol = 0
for (_, s) in steps:
    body = code(s)
    if "gh issue create" not in body:
        continue
    ci = body.find("gh issue create")
    li = body.find("gh label create")
    if li == -1 or li > ci:
        viol += 1
emit("ISSUE_CREATE_WITHOUT_PRIOR_LABEL_BOOTSTRAP", viol)

# --- B7: heartbeat status allowlist ------------------------------------------
hb = [s for (_, s) in steps if "sentry-heartbeat" in (s.get("uses") or "")]
emit("HEARTBEAT_COUNT", len(hb))
if hb:
    w = hb[0].get("with") or {}
    emit("HEARTBEAT_SLUG", w.get("monitor-slug", ""))
    emit("HEARTBEAT_STATUS", norm(w.get("status", "")))
    emit("HEARTBEAT_IF", norm(hb[0].get("if", "")))

# --- B8: pathspec parity vs the release workflow -----------------------------
#
# The critical path is NOT a serial sum (#7160). `release` and `await-ci` declare no `needs:`,
# so they run in PARALLEL and the declared bound is:
#     max(release, await-ci) + migrate + verify-migrations + deploy
#
# Two properties this computation must preserve, both previously violated in the UNSAFE
# direction:
#
#  1. A MISSING `timeout-minutes` means the GitHub 360-minute default, never 0. The old
#     `int(x or 0)` read a DELETED ceiling as zero, so removing the 90 on `deploy` silently
#     LOWERED the computed bound and B9 stayed green. The 360 default is applied uniformly to
#     all five jobs -- simpler than a special case, and it closes four more silent-green holes.
#  2. The ceiling for `release` lives in the CALLEE (a `uses:` job cannot declare
#     timeout-minutes -- the GitHub schema rejects it), so it is read from whatever workflow
#     jobs.release `uses:`. Resolved from `uses:` rather than hardcoded: repointing that key at
#     another workflow must not leave this reading a stale value and passing green.
DEFAULT_JOB_TIMEOUT_MIN = 360
try:
    rel = yaml.safe_load(open(rel_path))
    rjobs = rel.get("jobs") or {}
    rel_release = rjobs.get("release") or {}
    pf = rel_release.get("with", {}).get("path_filter", "")
    emit("RELEASE_PATH_FILTER", pf)

    ceiling_err = ""

    def job_timeout(name):
        # Returns (value, error). Absent -> the GitHub default. Non-integer (an expression such
        # as ${{ inputs.x }}) -> a NAMED error, never an uncaught traceback.
        global ceiling_err
        j = rjobs.get(name) or {}
        if "timeout-minutes" not in j:
            return DEFAULT_JOB_TIMEOUT_MIN
        raw = j.get("timeout-minutes")
        try:
            return int(raw)
        except (TypeError, ValueError):
            if not ceiling_err:
                ceiling_err = "job %s has a non-integer timeout-minutes (%r)" % (name, raw)
            return DEFAULT_JOB_TIMEOUT_MIN

    # --- resolve the release ceiling out of the callee ---
    release_ceiling = DEFAULT_JOB_TIMEOUT_MIN
    uses = rel_release.get("uses") or ""
    if not uses:
        ceiling_err = "jobs.release declares no `uses:` -- release ceiling unverifiable"
    elif not uses.startswith("./"):
        # owner/repo/.github/workflows/x.yml@ref -- genuinely not verifiable from this repo.
        # Fail CLOSED with a message that says so, rather than a raw FileNotFoundError.
        ceiling_err = "remote reusable workflow (%s) -- release ceiling unverifiable" % uses
    else:
        # Root at the SANDBOX root -- the directory containing .github/workflows/ -- not CWD and
        # not the real repo. Under the Part-C mutation harness those differ.
        # removeprefix, never lstrip("./"): lstrip is a CHARACTER-class strip that would mangle
        # any "."-prefixed path segment.
        callee_rel = uses.removeprefix("./")
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(rel_path))))
        callee_path = os.path.join(root, callee_rel)
        try:
            callee = yaml.safe_load(open(callee_path))
            cjob = ((callee.get("jobs") or {}).get("release") or {})
            if "timeout-minutes" not in cjob:
                release_ceiling = DEFAULT_JOB_TIMEOUT_MIN
            else:
                raw = cjob.get("timeout-minutes")
                try:
                    release_ceiling = int(raw)
                except (TypeError, ValueError):
                    ceiling_err = ("callee %s jobs.release has a non-integer timeout-minutes (%r)"
                                   % (callee_rel, raw))
        except Exception as e:
            ceiling_err = ("could not read reusable workflow %s: %s"
                           % (callee_rel, str(e).replace("\n", " ")))

    crit = max(release_ceiling, job_timeout("await-ci"))
    for j in ("migrate", "verify-migrations", "deploy"):
        crit += job_timeout(j)

    # Emitted AFTER every job_timeout call, not before. job_timeout also writes ceiling_err (an
    # expression-valued timeout-minutes on any of the four caller-side jobs), so emitting above
    # would publish a stale empty string and B8d would report "resolved fine" while a timeout was
    # in fact unreadable. B9 still reds in that case -- the unreadable value defaults to 360, which
    # inflates the path -- so this is a diagnosability gap, not a silent-green hole; but naming the
    # unreadable input is the entire reason B8d exists. Verified by mutation.
    emit("RELEASE_CEILING_MIN", release_ceiling)
    emit("RELEASE_CEILING_ERROR", ceiling_err)
    emit("RELEASE_CRITICAL_PATH_MIN", crit)

    # --- topology guard (#7160) ---
    # Uniform-360 closes the delete-a-VALUE hole but not the change-the-GRAPH hole: inserting a
    # job before `deploy`, or raising the currently-dominated `verify-doppler-secrets` (10m) to
    # 200, leaves the formula returning 195 while the real bound is larger. Pin the set of jobs
    # with a needs-path to `deploy` so a topology change reds instead of being absorbed.
    def needs_of(name):
        n = (rjobs.get(name) or {}).get("needs") or []
        return [n] if isinstance(n, str) else list(n)

    seen, stack = set(), list(needs_of("deploy"))
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        stack.extend(needs_of(cur))
    emit("DEPLOY_NEEDS_CLOSURE", ",".join(sorted(seen)))
except Exception as e:
    emit("RELEASE_PARSE_ERROR", str(e).replace("\n", " "))

# --- B11: step-id and env CLOSURE --------------------------------------------
# Part B previously inspected only `if:` and `uses.with`, so an entire class was unmutated and
# invisible: renaming `id: notify` (heartbeat then reads a permanently-empty output and reports
# error on every real drift), pointing the heartbeat at the wrong step id, or deleting an `env:`
# DECLARATION (the body dies on an unbound var under set -u, so the drift email never sends).
declared_ids = set(s.get("id") for (_, s) in steps if s.get("id"))
emit("DECLARED_ID_COUNT", len(declared_ids))

ref_re = re.compile(r"steps\.([A-Za-z0-9_-]+)\.")
referenced = set()
for (_, st) in steps:
    surfaces = [str(st.get("if", ""))]
    w = st.get("with") or {}
    if isinstance(w, dict):
        surfaces.extend(str(v) for v in w.values())
    e = st.get("env") or {}
    if isinstance(e, dict):
        surfaces.extend(str(v) for v in e.values())
    surfaces.append(st.get("run") or "")
    for surf in surfaces:
        referenced.update(ref_re.findall(surf))
dangling = sorted(referenced - declared_ids)
emit("DANGLING_STEP_REFS", len(dangling))
if dangling:
    emit("DANGLING_STEP_REF_NAMES", ",".join(dangling))

# Every ${VAR} a run body expands must be declared in that step env, or be a runner-provided
# name. Under `set -uo pipefail` an undeclared one kills the step mid-body.
RUNNER_PROVIDED = set(["GITHUB_OUTPUT", "RUNNER_TEMP", "GITHUB_ENV", "GITHUB_STEP_SUMMARY",
                       "GITHUB_WORKSPACE", "HOME", "PATH", "BODY", "TITLE", "EXISTING",
                       "HTTP_CODE", "PAYLOAD", "list_rc"])
undeclared = []
for (_, st) in steps:
    body = code(st)
    if not body:
        continue
    env_keys = set((st.get("env") or {}).keys())
    for var in set(re.findall(r"\$\{([A-Z][A-Z0-9_]*)(?::-[^}]*)?\}", body)):
        if var in env_keys or var in RUNNER_PROVIDED:
            continue
        # The capture stays WIDE (guarded expansions included). A narrowing was tried and
        # measured unnecessary: it silently dropped two real detections, because a deleted
        # MISSING_SHAS or EXIT_CODE declaration degrades a diagnostic to a permanent
        # placeholder without ever failing a step -- the QUIET half of the class this exists
        # to catch, and exactly the half a guarded read creates.
        if re.search(r"^\s*(local\s+)?%s=" % var, body, re.M):
            continue
        undeclared.append("%s:%s" % (st.get("id") or st.get("name") or "?", var))
emit("UNDECLARED_ENV_REFS", len(undeclared))
if undeclared:
    emit("UNDECLARED_ENV_REF_NAMES", ",".join(sorted(undeclared)[:6]))

# --- B12: the SUT<->workflow output-key contract -------------------------------
# Owned by NEITHER side before: Part A pinned the globals classify_drift sets, Part B pinned the
# workflow if: conditions, and nothing pinned that the keys the workflow greps out are the keys
# the checker prints. Renaming one character on either side ships empty issue and email bodies
# while every alert still fires, so nothing looks broken.
if runs:
    emit("EXTRACTED_KEYS", ",".join(sorted(set(
        re.findall(r"sed -n .s/\^([A-Z_]+)=//p", code(runs[0][1]))))))

# --- the check step body, for EXECUTION rather than grepping --------------------
# Every other Part B pin is a regex over source, which is right for declarative YAML (if:
# conditions, fetch-depth, permissions) and wrong for imperative shell. A grep cannot see
# ordering, cannot see a redirect to /dev/null, and cannot see which variable a `case`
# actually tests -- all three shipped as survivable mutations. Emit the body so a Part A
# assertion can run it.
if runs:
    with open(os.environ.get("DRIFT_STEP_BODY_OUT", "/dev/null"), "w") as fh:
        fh.write(runs[0][1].get("run") or "")

# --- B16: the issue step body, likewise for EXECUTION ---------------------------
# The plan justifies widening the errexit fix beyond the capture on the grounds that four
# list_rc handlers are dead code. Nothing executed them, so that claim was unpinned.
for _s in by_id("issue"):
    with open(os.environ.get("DRIFT_ISSUE_BODY_OUT", "/dev/null"), "w") as fh:
        fh.write(_s.get("run") or "")
    break

# --- B14b: the simulation premise behind executing bodies under `bash -e` --------
# Executing an extracted body under `bash -e` is faithful ONLY while this workflow declares no
# shell: key. If one is added, the real invocation becomes
# `bash --noprofile --norc -eo pipefail {0}` and the execution tests keep passing while
# simulating a runner that no longer exists. Note `shell: bash` does NOT clear -e either -- this
# counter exists to force a re-read of the harness, not to bless any particular value.
_shell_steps = len([s for (_, s) in steps if s.get("shell")])
_defaults = (wf.get("defaults") or {}).get("run") or {}
if _defaults.get("shell"):
    _shell_steps += 1
for _j in jobs.values():
    _jd = (_j.get("defaults") or {}).get("run") or {}
    if _jd.get("shell"):
        _shell_steps += 1
emit("STEPS_WITH_SHELL_KEY", _shell_steps)

# --- B15: every run: body in this workflow clears inherited errexit -------------
def _set_verdict(args):
    # True = clears -e, False = re-arms it, None = says nothing. `-o NAME` / `+o NAME` are
    # consumed as PAIRS so `set -o errexit` is seen as the re-arm it is.
    verdict = None
    toks = args.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in ("-o", "+o") and i + 1 < len(toks):
            if toks[i + 1] == "errexit":
                verdict = t.startswith("+")
            i += 2
            continue
        if t.startswith(("-", "+")) and not t.startswith("--") and "e" in t[1:]:
            verdict = t.startswith("+")
        i += 1
    return verdict

def errexit_clear_position(body):
    # Returns (clear_index, first_statement_index) over the COMMENT-STRIPPED body, or
    # (None, ...) when nothing clears errexit.
    #
    # POSITION, not presence. Asserting only presence was measured vacuous: moving the
    # `set +e` in the notify step from the top of the body to AFTER the `fi` kept the count
    # at 0 and left the whole suite green, while errexit was armed for the entire
    # jq/curl sequence the clear exists to protect. The plan flagged exactly this residual
    # ("B15 asserts presence, not position") and assumed the Phase 4 linter covered it --
    # it cannot, because that gate anchors on a `$?` read and these bodies have none.
    clear_i = None
    first_stmt = None
    for i, ln in enumerate(body.split("\n")):
        if not ln.strip():
            continue
        m = re.match(r"^\s*set\s+(.*)$", ln)
        if m:
            if clear_i is None and _set_verdict(m.group(1)) is True:
                clear_i = i
            continue
        if first_stmt is None:
            first_stmt = i
    return clear_i, first_stmt

_bodies = [s for (_, s) in steps if isinstance(s.get("run"), str)]
emit("RUN_BODY_COUNT", len(_bodies))

_no_clear = 0
_late_clear = 0
for _s in _bodies:
    _c, _f = errexit_clear_position(code(_s))
    if _c is None:
        _no_clear += 1
    elif _f is not None and _c > _f:
        _late_clear += 1
emit("BODIES_WITHOUT_ERREXIT_CLEAR", _no_clear)
emit("BODIES_WITH_LATE_ERREXIT_CLEAR", _late_clear)

# --- B17: the empty-string coercion fail-open ----------------------------------
# Actions == is LOOSE: differing operand types are cast to Number, an unset output is the empty
# string, and the empty string casts to 0 -- so \x27\x27 == \x270\x27 is TRUE. A step that died
# before writing $GITHUB_OUTPUT therefore satisfies every == \x270\x27 gate. Measured on run
# 31054501973: the check-error FILING step (!= 0 && != 1) was skipped while its exact complement,
# the CLOSER (== 0 || == 1), RAN. Leading with steps.check.outcome is what discriminates
# "the step ran and measured 0" from "the step never ran".
# Selector is `steps.check.outputs.` -- the WHOLE consumer set, not just the exit_code ones.
# Keying on exit_code excluded the `verdict == \x27CLEAN\x27` gate, leaving that one consumer
# unpinned while the prose above it claimed EVERY consumer leads with the conjunct. The guard
# was narrower than its own name. (No apostrophes in this block -- see the code() docstring.)
_gates = [norm(s.get("if", "")) for (_, s) in steps
          if "steps.check.outputs." in norm(s.get("if", ""))]
emit("EXITCODE_GATE_COUNT", len(_gates))
emit("EXITCODE_GATES_WITHOUT_OUTCOME_CONJUNCT",
     len([g for g in _gates if "steps.check.outcome == \x27success\x27" not in g]))
# A substring test cannot see a NEUTERED conjunct: `(steps.check.outcome == \x27success\x27
# || true) && …` keeps the substring and is vacuous. Count gates whose conjunct sits inside a
# disjunction, which is the cheap shape that defeats the check above.
emit("EXITCODE_GATES_WITH_VACUOUS_CONJUNCT",
     len([g for g in _gates
          if re.search(r"\(\s*steps\.check\.outcome == \x27success\x27\s*\|\|", g)]))

# --- B10: schedule + job timeout ---------------------------------------------
on = wf.get("on", wf.get(True, {})) or {}
sched = on.get("schedule") or []
emit("CRON", sched[0].get("cron", "") if sched else "")
emit("HAS_DISPATCH", int("workflow_dispatch" in on))
emit("CONCURRENCY_CANCEL", (wf.get("concurrency") or {}).get("cancel-in-progress", "<unset>"))
perms = wf.get("permissions") or {}
emit("PERM_ISSUES", perms.get("issues", "<unset>"))
emit("PERM_CONTENTS", perms.get("contents", "<unset>"))
for jname, job in jobs.items():
    emit("JOB_TIMEOUT", job.get("timeout-minutes", "<unset>"))
    break
'

run_part_b() {
  echo "=== PART B: wiring pins (shipped workflow) ==="

  if [[ ! -f "$WORKFLOW" ]]; then
    fail "B0 the workflow exists at $WORKFLOW" "a readable file" "absent"
    return 0
  fi
  pass "B0 the workflow file exists"

  local EX="$TMP/extract.env"
  export DRIFT_STEP_BODY_OUT="$TMP/check-body.sh"
  export DRIFT_ISSUE_BODY_OUT="$TMP/issue-body.sh"
  if ! python3 -c "$PYEXTRACT" "$WORKFLOW" "$RELEASE_WORKFLOW" > "$EX" 2>"$TMP/extract.err"; then
    fail "B0b PyYAML extraction succeeded" "rc=0" "$(cat "$TMP/extract.err")"
    return 0
  fi
  if grep -q '^EXTRACT_ERROR=' "$EX"; then
    fail "B0b workflow parses as YAML" "a mapping" "$(grep '^EXTRACT_ERROR=' "$EX")"
    return 0
  fi
  pass "B0b the workflow parses and extraction succeeded"

  # Read key=value pairs into shell vars prefixed X_.
  local k v
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    printf -v "X_$k" '%s' "$v"
  done < "$EX"

  # B1 -- the production call site.
  assert_eq "B1 exactly one call to prod-version-drift-check.sh" "1" "${X_CALLSITE_COUNT:-0}"
  assert_eq "B1b the call is NOT nested in a retry/poll loop" "0" "${X_CALLSITE_IN_LOOP:-1}"
  assert_eq "B1c the checker step carries id: check" "check" "${X_CALLSITE_STEP_ID:-}"

  # B2 -- fetch-depth. Not cosmetic: origin/main HEAD is frequently NOT a path-matching
  # commit, so the range query needs full history on the COMMON path. A shallow checkout
  # puts the checker in permanent CHECK_ERROR.
  assert_eq "B2 exactly one actions/checkout" "1" "${X_CHECKOUT_COUNT:-0}"
  assert_eq "B2b checkout declares fetch-depth: 0" "0" "${X_CHECKOUT_FETCH_DEPTH:-<unset>}"

  # B3 -- every alerting step names a verdict. A bare !cancelled() is TRUE on success too,
  # so on its own it would email on every healthy tick, forever.
  assert_contains "B3 at least one alerting step exists" "^[1-9]" "${X_ALERT_STEP_COUNT:-0}"
  assert_eq "B3b every alerting step carries a verdict conjunct (never a bare !cancelled())" \
    "0" "${X_ALERT_STEPS_WITHOUT_VERDICT_CONJUNCT:-1}"
  # Per-CLASS cardinality. B3 was existence-only (^[1-9]), which meant the whole cannot-evaluate
  # family -- the third verdict this design exists to make non-silent -- could be DELETED with
  # the suite green, because the two drift steps still satisfied the existence check.
  assert_eq "B3c exactly two alerting steps on the drift class (issue + email)" \
    "2" "${X_ALERT_STEPS_GATED_ON_DRIFT:-0}"
  assert_eq "B3d exactly two alerting steps on the cannot-evaluate class (issue + email)" \
    "2" "${X_ALERT_STEPS_GATED_ON_CHECK_ERROR:-0}"

  # B4 -- the anti-spam pin, stated as its own property rather than inferred from B3.
  assert_eq "B4 NO alerting step is reachable when exit_code == '0'" \
    "0" "${X_ALERT_STEPS_REACHABLE_WHEN_CLEAN:-1}"

  # B5 -- gh issue create --label hard-fails on an undefined label, and ci/prod-version-drift
  # does not exist yet. This repo has already shipped that exact failure twice.
  assert_eq "B5 every 'gh issue create' is preceded by a label bootstrap in the same body" \
    "0" "${X_ISSUE_CREATE_WITHOUT_PRIOR_LABEL_BOOTSTRAP:-1}"

  # B6 -- TWO close steps, one per issue class, each on its own recovery condition. A single
  # label-wide closer gated on exit_code == '0' produced two distinct falsehoods: it closed the
  # DRIFT issue on DRIFT_PENDING (missing_count > 0) while posting "no longer missing any
  # commit", and it could never close a RESOLVED check-error issue during a sustained drift,
  # because exit is 1 throughout -- so that issue sat open, lying, for the whole incident.
  assert_eq "B6 exactly two close steps (one per issue class)" "2" "${X_CLOSE_STEP_COUNT:-0}"
  assert_eq "B6b the drift issue closes only on a genuinely CLEAN verdict" \
    "1" "${X_CLOSE_STEPS_GATED_ON_CLEAN_VERDICT:-0}"
  assert_eq "B6c the check-error issue closes as soon as the checker reaches ANY verdict" \
    "1" "${X_CLOSE_STEPS_GATED_ON_EVALUATED:-0}"
  assert_eq "B6d no closer keys on the bare exit_code == '0' form (CLEAN UNION DRIFT_PENDING)" \
    "0" "${X_CLOSE_STEPS_ON_BARE_EXIT0:-1}"

  # B7 -- heartbeat semantics. The first conjunct must be the step OUTCOME (#7138's lesson:
  # a step that dies before writing its output leaves the output empty, and an output-only
  # test reads that as a value rather than as a death).
  assert_eq "B7 exactly one sentry-heartbeat step" "1" "${X_HEARTBEAT_COUNT:-0}"
  assert_eq "B7b heartbeat runs unconditionally (if: always())" "always()" "${X_HEARTBEAT_IF:-}"
  assert_contains "B7c heartbeat status' FIRST conjunct is steps.check.outcome == 'success'" \
    "^\\\$\\{\\{ steps\.check\.outcome == 'success'" "${X_HEARTBEAT_STATUS:-}"
  # B7d -- the drift arm must still require delivery, AND must accept the dedupe tick. Gating
  # only on `delivered == '1'` made the monitor report ITSELF broken on every tick after the
  # first of a real incident: the email step is correctly skipped by the anti-spam gate, and a
  # skipped step's outputs are EMPTY. That pinned the liveness channel at `error` for exactly
  # the window in which a genuine checker failure would need to page.
  assert_contains "B7d heartbeat drift arm requires the email actually delivered" \
    "delivered == '1'" "${X_HEARTBEAT_STATUS:-}"
  assert_contains "B7d2 ...or a positively-identified dedupe tick (no alert was required)" \
    "first_detection == 'false'" "${X_HEARTBEAT_STATUS:-}"
  # B7f -- pin the terminal MAPPING, not just the tokens. Swapping the arms
  # (&& 'error' || 'ok') leaves every token present and makes Sentry report error when healthy
  # and ok when broken -- a monitor permanently green over a dead alarm, by a different route
  # than the slug mismatch B10g guards.
  assert_contains "B7f the ok arm is the allowlist's TRUE branch, error its false branch" \
    "&& 'ok' \|\| 'error' \}\}$" "${X_HEARTBEAT_STATUS:-}"
  assert_contains "B7e heartbeat is an allowlist ending in 'error'" \
    "'error'" "${X_HEARTBEAT_STATUS:-}"

  # B8 -- pathspec parity. The release path filter is the DEFINITION of "a commit that should
  # have deployed"; if it changes and the checker does not, the checker silently redefines
  # correctness. Assert at CI time, at the moment of divergence.
  if [[ -f "$SUT" ]]; then
    local sut_pathspec
    # shellcheck source=/dev/null
    sut_pathspec="$(source "$SUT" >/dev/null 2>&1; printf '%s' "${PATHSPEC[*]:-}")"
    assert_eq "B8 checker PATHSPEC equals the release job's path_filter verbatim" \
      "${X_RELEASE_PATH_FILTER:-<missing>}" "$sut_pathspec"
    # --first-parent is a no-op on today's linear history and load-bearing the moment a merge
    # commit lands -- 35 already have, and allow_merge_commit is on.
    #
    # ANCHOR ON THE INVOCATION, NOT A BARE TOKEN. A plain `grep -c -- --first-parent` counts
    # COMMENT mentions too, and this checker documents the flag at length in its header -- so
    # the bare-token form stayed green with the flag deleted from the git call, which is the
    # assertion passing for a reason unrelated to what it claims. Anchoring to the command
    # shape is something a comment cannot satisfy (a comment line starts with `#`, which
    # `^[^#]*` cannot cross).
    local fp
    fp="$(grep -cE '^[^#]*git (log|rev-list)[^|]*--first-parent' "$SUT" || true)"
    assert_contains "B8b the checker's git invocation itself carries --first-parent" "^[1-9]" "$fp"
    # ...and never through a pipe: measured, `git log <bad>..main | tail -1` returns rc=0
    # while git itself returns 128, which is exactly how a broken check reads as CLEAN.
    local piped
    piped="$(grep -cE '^[^#]*git (log|rev-list)[^|]*\|' "$SUT" || true)"
    assert_eq "B8c no git invocation pipes its output before rc is captured" "0" "$piped"
  else
    fail "B8 checker present for pathspec parity" "a readable file" "absent"
  fi

  # B8d -- the release ceiling was actually RESOLVED (#7160). Without this, an unreadable or
  # remote `uses:` surfaced as an opaque `unbound variable` abort under set -u: caught, but
  # undiagnosable. It also covers a case that did not exist before, because nothing resolved
  # `uses:` before -- an unresolvable callee.
  # `-` not `:-`: the SUCCESS value here is the empty string, and `:-` would substitute on it,
  # turning every clean run into a <unset> mismatch. Only a genuinely absent key -- extraction
  # never reached the emit -- should read as <unset>.
  assert_eq "B8d the release ceiling resolves out of jobs.release.uses" "" "${X_RELEASE_CEILING_ERROR-<unset>}"

  # B8e -- the critical-path TOPOLOGY is pinned. Uniform-360 catches a deleted ceiling but not
  # a changed graph: insert a job before `deploy`, or raise the dominated verify-doppler-secrets
  # (10m) to 200, and the formula still returns 195 while the real bound is larger.
  assert_eq "B8e the set of jobs with a needs-path to deploy is unchanged" \
    "await-ci,migrate,release,verify-doppler-secrets,verify-migrations" \
    "${X_DEPLOY_NEEDS_CLOSURE:-<unset>}"

  # B9 -- threshold safety, in the SAFE direction: a pipeline timeout INCREASE fails the
  # suite, so the threshold can never silently become smaller than legitimate latency.
  #
  # The compared value is a CRITICAL PATH with a max() term, not a serial sum: `release` and
  # `await-ci` start in parallel, so it is max(release, await-ci) + migrate + verify-migrations
  # + deploy. With `release` undeclared that is 495, not the 555 a serial reading gives.
  #
  # SCOPE (#7160): this bounds DECLARED EXECUTION only. The checker's own clock starts at the
  # oldest undeployed commit's committer epoch, and runner queue wait, concurrency
  # serialization between back-to-back merges, and push-to-start latency all sit outside any
  # job timeout. The threshold's tolerance for those remains empirical, not provable.
  if [[ -n "${THRESH_MIN:-}" && "${X_RELEASE_CRITICAL_PATH_MIN:-x}" =~ ^[0-9]+$ ]]; then
    if [[ "$THRESH_MIN" -ge "${X_RELEASE_CRITICAL_PATH_MIN}" ]]; then
      pass "B9 threshold (${THRESH_MIN}m) >= release declared critical path (${X_RELEASE_CRITICAL_PATH_MIN}m)"
    else
      fail "B9 threshold >= release declared critical path" \
        ">= ${X_RELEASE_CRITICAL_PATH_MIN}" "$THRESH_MIN"
    fi
  else
    fail "B9 threshold and release critical path both readable" "integers" \
      "thresh=${THRESH_MIN:-<unset>} path=${X_RELEASE_CRITICAL_PATH_MIN:-<unset>}"
  fi

  # B10 -- schedule/monitor coherence. A job timeout above the tick interval, combined with
  # cancel-in-progress: false, would queue every subsequent tick behind a wedged run.
  assert_eq "B10 schedule is every 30 minutes" "*/30 * * * *" "${X_CRON:-}"
  assert_eq "B10b workflow_dispatch is available (needed to exercise the alert path)" "1" "${X_HAS_DISPATCH:-0}"
  assert_eq "B10c overlapping ticks serialize rather than cancel" "False" "${X_CONCURRENCY_CANCEL:-<unset>}"
  assert_eq "B10d permissions: issues: write" "write" "${X_PERM_ISSUES:-<unset>}"
  assert_eq "B10e permissions: contents: read" "read" "${X_PERM_CONTENTS:-<unset>}"
  if [[ "${X_JOB_TIMEOUT:-999}" =~ ^[0-9]+$ ]] && [[ "${X_JOB_TIMEOUT}" -le 30 ]]; then
    pass "B10f job timeout (${X_JOB_TIMEOUT}m) <= the 30m tick interval"
  else
    fail "B10f job timeout <= tick interval" "<= 30" "${X_JOB_TIMEOUT:-<unset>}"
  fi

  # B11 -- closure. Both were entirely unpinned: Part B read only `if:` and `uses.with`.
  assert_eq "B11 every steps.<id>. reference resolves to a declared step id" \
    "0" "${X_DANGLING_STEP_REFS:-1}"
  assert_eq "B11b every \${VAR} a run body expands is declared in that step's env" \
    "0" "${X_UNDECLARED_ENV_REFS:-1}"

  # B12 -- the output-key contract, owned by neither side until now.
  assert_eq "B12 the keys the workflow extracts are exactly the keys the checker emits" \
    "$(grep -oE '^\s*echo "([A-Z_]+)=' "$SUT" | grep -oE '[A-Z_]+' | sort -u | paste -sd, -)" \
    "${X_EXTRACTED_KEYS:-<none>}"

  # B13 -- the run-log echo, EXECUTED rather than grepped.
  #
  # The three assertions this replaces pinned spelling, and review demonstrated three
  # rewrites that satisfied all of them while breaking the property: redirecting the loop to
  # /dev/null and re-adding the whole-blob form under a different quoting of the same
  # variable; testing the `case` on the RAW line instead of the sanitised one (so a leading
  # control byte escapes the marker); and duplicating the printf. All three left the suite
  # green. A grep over shell cannot see a redirect, an ordering, or which variable is tested.
  #
  # So: run the shipped step's own sanitiser and loop against a hostile fixture and assert
  # the OUTPUT. The fixture carries, on purpose, a control byte before a workflow command --
  # the exact input that distinguishes sanitise-then-classify from classify-then-sanitise.
  if [[ -s "$TMP/check-body.sh" ]]; then
    local fnsrc loopsrc probe out13
    fnsrc="$(awk "/strip_log_injection\(\) \{/,/^\}/" "$TMP/check-body.sh")"
    loopsrc="$(awk '/^printf .*while IFS= read/,/^done/' "$TMP/check-body.sh")"
    if [[ -n "$fnsrc" && -n "$loopsrc" ]]; then
      probe="$TMP/echo-probe.sh"
      {
        printf '%s\n' "$fnsrc"
        printf '%s\n' 'out="$(printf "A=1\n\001::stop-commands::PWNED\nfoo ##[stop-commands]y\nsafe\r::stop-commands::CRSPOOF\n##[#[stop-commands]DOUBLE\nkeep\tTAB\nbell\007gone")"'
        printf '%s\n' "$loopsrc"
      } > "$probe"
      out13="$(bash "$probe" 2>&1)"

      assert_eq "B13 the echo preserves every line (no whole-blob collapse)" \
        "7" "$(printf '%s\n' "$out13" | grep -c .)"
      assert_eq "B13b no line reaches column 0, so ::-form workflow commands cannot parse" \
        "0" "$(printf '%s\n' "$out13" | grep -c '^::' || true)"
      assert_eq "B13c the legacy ##[ form is broken even mid-line (IndexOf has no position test)" \
        "0" "$(printf '%s\n' "$out13" | grep -cF '##[' || true)"
      assert_contains "B13d a control byte BEFORE a command does not smuggle it past the marker" \
        "^drift\| ::stop-commands::PWNED$" "$out13"
      assert_contains "B13e TAB survives (it is \\011, inside the old strip range)" \
        "keep	TAB" "$out13"
      assert_not_contains "B13f other control bytes still die" "$(printf 'bell\007gone')" "$out13"
      # CR is not cosmetic: .NET ReadLine treats a bare \r as a line terminator, so a surviving
      # one makes the RUNNER re-split the line and everything after it lands at column 0 with no
      # marker. An earlier draft preserved CR by accident while intending to preserve only TAB,
      # defeating the marker on precisely the input it exists to stop.
      assert_not_contains "B13h CR does not survive (it would let the runner re-split past the marker)" \
        "$(printf '\r')" "$out13"
      # A replacement that begins and ends with the character it escapes can re-form the token:
      # `#[#` turned `##[#[` into `#[##[`, leaving an intact `##[` for IndexOf to find.
      assert_not_contains "B13i the ##[ rewrite cannot re-form its own token" "##\\[" "$out13"
      assert_eq "B13g each input line is emitted exactly once" \
        "1" "$(printf '%s\n' "$out13" | grep -c 'A=1' || true)"
    else
      fail "B13 the check step exposes a sanitiser and a per-line loop" "both extractable" \
        "fn=$([[ -n "$fnsrc" ]] && echo yes || echo no) loop=$([[ -n "$loopsrc" ]] && echo yes || echo no)"
    fi
  else
    fail "B13 the check step body was extracted for execution" "a non-empty file" "absent"
  fi

  # B14 -- THE CAPTURE REACHES ITS CONSUMERS, on every verdict class. Executed, not grepped.
  #
  # This is the assertion #7304 was missing. GitHub runs a run: block with no shell: key under
  # `bash -e {0}`, so errexit is ALREADY ON, and `set -uo pipefail` only ADDS flags. The capture
  # `out="$(...)"; rc=$?` therefore aborted the shell AT that line whenever the checker exited
  # non-zero -- which is exactly the two verdicts that alert. Measured: 8/8 scheduled runs failed
  # emitting zero output, while the CLEAN path passed through unaffected the entire time.
  #
  # That asymmetry is why this runs all three arms. A fix verified only on exit 0 is
  # indistinguishable from no fix at all, because exit 0 already worked.
  #
  # Running under `bash -e` is load-bearing: a bare `bash` would make this test pass against the
  # BROKEN body. B14b pins the premise that `bash -e` is still what the runner uses.
  if [[ -s "$TMP/check-body.sh" ]]; then
    # ONE invocation, shared by the self-check probe and every arm, so they cannot diverge.
    local BASH_E=(bash -e)

    # Self-check: prove THIS bash actually aborts an assignment-from-failing-substitution under
    # errexit. If it did not, every arm below would pass for the wrong reason and B14 would be
    # silently vacuous rather than depending on axis11 to notice.
    local probe14
    probe14="$("${BASH_E[@]}" -c 'set -uo pipefail; x="$(exit 1)"; echo REACHED' 2>&1 || true)"
    assert_not_contains "B14 self-check: inherited errexit aborts the capture in this bash" \
      "REACHED" "$probe14"

    local keys14 stub_arm code14 sbx14 gho14 out14 rc14 want_verdict
    IFS=',' read -ra keys14 <<< "${X_EXTRACTED_KEYS:-}"
    if [[ "${#keys14[@]}" -lt 2 ]]; then
      fail "B14 the extracted output-key set is usable for stub generation" \
        "at least 2 keys from B12" "${X_EXTRACTED_KEYS:-<none>}"
    else
      for code14 in 0 1 2; do
        case "$code14" in
          0) want_verdict="CLEAN" ;;
          1) want_verdict="DRIFT_SUSTAINED" ;;
          2) want_verdict="CHECK_ERROR" ;;
        esac

        # A FRESH sandbox and a FRESH $GITHUB_OUTPUT per arm. The body APPENDS (>>), so a shared
        # file would let the exit-1 arm's grep find exit_code=0 left behind by the exit-0 arm and
        # pass for the wrong reason. The exact-line-count assertion catches both that
        # contamination and a partially-written output.
        sbx14="$TMP/b14-$code14"
        gho14="$TMP/b14-gho-$code14"
        rm -rf "$sbx14"; mkdir -p "$sbx14/scripts" || { fail "B14 sandbox setup (exit $code14)" "mkdir rc=0" "failed"; break; }
        : > "$gho14"

        # The stub's key set is GENERATED from the keys the workflow actually greps out (B12's
        # X_EXTRACTED_KEYS) rather than hand-copied. A hand-written list would be a THIRD
        # independent copy of the key contract -- checker, workflow, stub -- so a rename would
        # turn B12 red while this stub silently rotted into testing nothing.
        {
          printf '%s\n' '#!/usr/bin/env bash'
          for stub_arm in "${keys14[@]}"; do
            [[ -z "$stub_arm" ]] && continue
            case "$stub_arm" in
              *VERDICT) printf 'echo "%s=%s"\n' "$stub_arm" "$want_verdict" ;;
              # The stub marker proves the STUB produced this result -- not a stale real checker,
              # not an empty run, not a leftover file.
              *REASON)  printf 'echo "%s=%s"\n' "$stub_arm" "STUB_MARKER_7304" ;;
              *)        printf 'echo "%s=stub_value"\n' "$stub_arm" ;;
            esac
          done
          printf 'exit %s\n' "$code14"
        } > "$sbx14/scripts/prod-version-drift-check.sh"

        cp "$TMP/check-body.sh" "$sbx14/body.sh"
        out14="$(cd "$sbx14" && GITHUB_OUTPUT="$gho14" "${BASH_E[@]}" ./body.sh 2>&1)"; rc14=$?

        assert_eq "B14 (exit $code14) the step body itself exits 0 -- the verdict travels as DATA" \
          "0" "$rc14"
        assert_eq "B14 (exit $code14) \$GITHUB_OUTPUT records the checker's exit code" \
          "exit_code=$code14" "$(grep '^exit_code=' "$gho14" || echo '<ABSENT -- the step died at the capture>')"
        assert_eq "B14 (exit $code14) \$GITHUB_OUTPUT records the verdict" \
          "verdict=$want_verdict" "$(grep '^verdict=' "$gho14" || echo '<ABSENT>')"
        assert_eq "B14 (exit $code14) the stub marker reached \$GITHUB_OUTPUT" \
          "reason=STUB_MARKER_7304" "$(grep '^reason=' "$gho14" || echo '<ABSENT>')"
        # Exact, not >=: contamination and truncation are both caught, and the count is
        # stub-deterministic so pinning it costs no flake.
        assert_eq "B14 (exit $code14) \$GITHUB_OUTPUT has exactly one line per contract key plus exit_code" \
          "$(( ${#keys14[@]} + 1 ))" "$(grep -c . "$gho14" || true)"
        # This count's only real power is 0-vs-N: did the run-log echo loop execute AT ALL. Do
        # not "strengthen" it into a content assertion -- B13 already owns the sanitiser's
        # behaviour, and duplicating it here would couple two tests to one fixture.
        assert_eq "B14 (exit $code14) every checker line reached the run log" \
          "${#keys14[@]}" "$(printf '%s\n' "$out14" | grep -c '^drift| ' || true)"

        case "$code14" in
          1) assert_eq "B14 (exit 1) exactly one ::error:: names the stale build" \
               "1" "$(printf '%s\n' "$out14" | grep -c '^::error::Production is serving a stale build' || true)" ;;
          2) assert_eq "B14 (exit 2) exactly one ::error:: names the cannot-evaluate case" \
               "1" "$(printf '%s\n' "$out14" | grep -c '^::error::Version-drift check could NOT be evaluated' || true)" ;;
          0) assert_eq "B14 (exit 0) the quiet verdict emits NO ::error::" \
               "0" "$(printf '%s\n' "$out14" | grep -c '^::error::' || true)" ;;
        esac
      done
    fi
  else
    fail "B14 the check step body was extracted for execution" "a non-empty file" "absent"
  fi

  # B14b -- pin B14's OWN simulation premise.
  #
  # B14's fidelity claim ("bash -e is what the runner uses") holds only because this workflow
  # declares no shell: key anywhere. Add one and the real invocation becomes
  # `bash --noprofile --norc -eo pipefail {0}` -- at which point B14 keeps passing while
  # simulating a runner that no longer exists. Three lines, and it is what stops this whole
  # execution battery from rotting silently.
  assert_eq "B14b no step declares a shell: key (so \`bash -e\` remains the faithful simulation)" \
    "0" "${X_STEPS_WITH_SHELL_KEY:-<unextracted>}"

  # B15 -- EVERY run: body in this workflow clears inherited errexit, not just the capture.
  #
  # Deliberately NOT subsumed by the repo-wide lint gate, and this comment is the reason: the
  # gate anchors on a `$?` / ${PIPESTATUS[n]} read, because that read is what proves the author
  # meant to handle failure. The notify and notify_error bodies are `jq -n` steps with no such
  # read, so the gate can NEVER fire on them. If a future edit drops set +e from notify, B15 is
  # the only thing in the repo that catches it. Do not delete this as "covered by the linter".
  #
  # Asserts the NUMERATOR, never the ratio: pinning "0 of 7" would make adding a legitimate
  # eighth step fail for a completely misleading reason.
  assert_eq "B15 every run: body clears inherited errexit (count lacking it)" \
    "0" "${X_BODIES_WITHOUT_ERREXIT_CLEAR:-<unextracted>}"
  assert_contains "B15b the body count is non-zero (a workflow with no bodies passes B15 vacuously)" \
    "^[1-9]" "${X_RUN_BODY_COUNT:-0}"
  # B15c -- POSITION, which B15 alone cannot see. Measured: moving the notify step's `set +e`
  # below its `fi` kept B15's count at 0 and the whole suite green, while errexit stayed armed
  # across the jq/curl sequence the clear exists to protect. A clear that lands after the first
  # statement protects nothing above it.
  assert_eq "B15c no body clears errexit AFTER its first statement (presence is not position)" \
    "0" "${X_BODIES_WITH_LATE_ERREXIT_CLEAR:-<unextracted>}"

  # B16 -- the list_rc safety branch is actually REACHABLE.
  #
  # The stated justification for widening this fix beyond the capture is that four documented
  # "A FAILED LOOKUP IS NOT 'NOTHING FOUND'" handlers were dead code under inherited errexit.
  # Nothing executed them, so that claim was asserted rather than measured. This runs the issue
  # body with `gh` stubbed to fail and requires the branch to be reached.
  if [[ -s "$TMP/issue-body.sh" ]]; then
    local sbx16 gho16 out16
    sbx16="$TMP/b16"; gho16="$TMP/b16-gho"
    rm -rf "$sbx16"; mkdir -p "$sbx16/bin"
    : > "$gho16"
    # Fails on `issue list` (the lookup under test) and succeeds on `label create`, so the branch
    # is reached via the rc path rather than by breaking the step outright.
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf '%s\n' 'case "$1 $2" in'
      printf '%s\n' '  "label create") exit 0 ;;'
      printf '%s\n' '  "issue list")   echo "gh: API rate limit exceeded" >&2; exit 1 ;;'
      printf '%s\n' '  *)              echo "UNEXPECTED gh invocation: $*" >&2; exit 64 ;;'
      printf '%s\n' 'esac'
    } > "$sbx16/bin/gh"
    chmod +x "$sbx16/bin/gh"
    cp "$TMP/issue-body.sh" "$sbx16/body.sh"
    out16="$(cd "$sbx16" && PATH="$sbx16/bin:$PATH" GITHUB_OUTPUT="$gho16" \
      GH_REPO="owner/repo" DETAIL="d" MISSING_COUNT="1" PATHSPEC_DOC="p" \
      PROD_HEALTH_URL="https://example.invalid/health" MISSING_SHAS="abc" RUN_URL="https://example.invalid/run" \
      bash -e ./body.sh 2>&1 || true)"

    assert_contains "B16 a FAILED lookup is reported, not collapsed into 'nothing found'" \
      "^::error::Could not query existing drift issues" "$out16"
    assert_eq "B16b the failed-lookup branch records itself rather than filing a duplicate" \
      "first_detection=lookup_failed" "$(grep '^first_detection=' "$gho16" || echo '<ABSENT -- branch unreachable>')"
    assert_not_contains "B16c a failed lookup must NEVER route to the create branch" \
      "UNEXPECTED gh invocation" "$out16"
  else
    fail "B16 the issue step body was extracted for execution" "a non-empty file" "absent"
  fi

  # B17 -- the empty-string coercion fail-open, which set +e does NOT fix.
  #
  # Actions == is LOOSE: operands of differing types are both cast to Number, an unset step
  # output is '', and '' casts to 0 -- so '' == '0' is TRUE. A step that dies before writing
  # $GITHUB_OUTPUT therefore satisfies every == '0' gate downstream. Measured on run
  # 31054501973: `File or update the check-error issue` (gated != '0' && != '1') was SKIPPED
  # while its exact logical complement `Close the check-error issue ...` (gated == '0' || == '1')
  # RAN -- i.e. on a dead tick this workflow would auto-close the issue reporting its own
  # breakage, posting an empty verdict.
  #
  # This also means B4 was never testing the empty case: it asks which steps are reachable when
  # exit_code is '0', not when the step never ran. B17 is what covers that.
  assert_eq "B17 every steps.check.outputs consumer leads with the outcome conjunct (count lacking it)" \
    "0" "${X_EXITCODE_GATES_WITHOUT_OUTCOME_CONJUNCT:-<unextracted>}"
  # The population is SIX -- the five exit_code gates plus the verdict==CLEAN gate. Pinning the
  # exact number is what stops the selector silently narrowing again: an earlier revision keyed
  # on `exit_code` and reported a clean 5, excluding the consumer whose conjunct was therefore
  # unasserted while the prose claimed full coverage.
  assert_eq "B17b all six steps.check.outputs consumers are in B17's population" \
    "6" "${X_EXITCODE_GATE_COUNT:-0}"
  # B17c -- a substring test cannot see a neutered conjunct. `(outcome == 'success' || true) &&`
  # keeps the substring B17 looks for and is vacuous.
  assert_eq "B17c no consumer's outcome conjunct is neutered inside a disjunction" \
    "0" "${X_EXITCODE_GATES_WITH_VACUOUS_CONJUNCT:-<unextracted>}"

  # B10g -- monitor slug parity. A mismatched slug leaves the Sentry monitor permanently
  # green over a dead alarm: the worst shape available, since it looks like coverage.
  if [[ -f "$MONITORS_TF" ]]; then
    local slug="${X_HEARTBEAT_SLUG:-}"
    if [[ -n "$slug" ]] && grep -qF -- "\"$slug\"" "$MONITORS_TF"; then
      pass "B10g heartbeat slug '$slug' has a matching sentry_cron_monitor in cron-monitors.tf"
    else
      fail "B10g heartbeat slug has a matching sentry_cron_monitor" "\"$slug\" present" "absent"
    fi
  else
    fail "B10g cron-monitors.tf readable" "a readable file" "absent"
  fi
}

# ---------------------------------------------------------------------------
# PART C -- mutation battery
# ---------------------------------------------------------------------------
# Parts A and B can both be green against a checker that is wired wrong. Each axis sabotages
# ONE property, asserts the sabotage LANDED, and requires the suite to go red. Without the
# landed-assertion a no-op `sed` scores as "the guard caught it" -- the failure mode that makes
# a mutation battery itself the source of false confidence.

# Runs the A+B assertions against a sandbox. Echoes the child's exit code.
run_child() {
  local sbx="$1"
  (
    cd "$sbx" || exit 3
    DRIFT_MUTATION_CHILD=1 \
    DRIFT_TEST_PARTS=AB \
    DRIFT_MIN_ASSERTIONS=0 \
    DRIFT_MIN_A=0 DRIFT_MIN_B=0 DRIFT_MIN_C=0 \
    DRIFT_TEST_SCRIPT="$sbx/scripts/prod-version-drift-check.sh" \
    DRIFT_TEST_WORKFLOW="$sbx/.github/workflows/scheduled-prod-version-drift.yml" \
    DRIFT_TEST_RELEASE_WORKFLOW="$sbx/.github/workflows/web-platform-release.yml" \
    DRIFT_TEST_MONITORS_TF="$sbx/apps/web-platform/infra/sentry/cron-monitors.tf" \
    bash "$sbx/scripts/prod-version-drift-check.test.sh" 2>&1
  )
}

make_sandbox() {
  local dst="$1"
  # Every setup command is checked. A harness that fails to SET UP and continues does not
  # degrade into a missing result -- it degrades into a confident wrong one, because the next
  # case runs against the previous case's tree.
  mkdir -p "$dst/scripts" "$dst/.github/workflows" "$dst/apps/web-platform/infra/sentry" || return 1
  cp "$SCRIPT_DIR/prod-version-drift-check.sh"      "$dst/scripts/" || return 1
  cp "$SCRIPT_DIR/prod-version-drift-check.test.sh" "$dst/scripts/" || return 1
  cp "$REPO_ROOT/.github/workflows/scheduled-prod-version-drift.yml" "$dst/.github/workflows/" || return 1
  cp "$RELEASE_WORKFLOW" "$dst/.github/workflows/web-platform-release.yml" || return 1
  cp "$MONITORS_TF" "$dst/apps/web-platform/infra/sentry/cron-monitors.tf" || return 1

  # B8 resolves jobs.release.uses and reads the CALLEE's timeout-minutes, so the sandbox must
  # carry the reusable workflow too. Without it every mutation child hits an unresolvable
  # `uses:` -- and because each axis carries an expected-FAIL label, the whole battery would
  # report green while testing nothing, which is exactly the false confidence Part C exists to
  # remove (#7160 P10).
  #
  # Resolved FROM `uses:` rather than hardcoded, so repointing jobs.release.uses at a
  # different callee cannot silently leave the sandbox carrying a stale file.
  local reusable_rel
  reusable_rel="$(python3 - "$RELEASE_WORKFLOW" <<'PY' 2>/dev/null
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
u = ((d.get("jobs") or {}).get("release") or {}).get("uses") or ""
print(u.removeprefix("./") if u.startswith("./") else "")
PY
  )" || return 1
  if [[ -n "$reusable_rel" ]]; then
    mkdir -p "$dst/$(dirname "$reusable_rel")" || return 1
    cp "$REPO_ROOT/$reusable_rel" "$dst/$reusable_rel" || return 1
  fi
  return 0
}

# mutate_and_assert_red <axis-name> <target-relative-path> <python-mutator> [expected-FAIL-label]
#
# The 4th argument is what makes an axis evidence about the PROPERTY rather than about the file
# merely being broken. Scoring on "the child exited non-zero" accepts any failure, including a
# mutant that is simply a bash SYNTAX ERROR -- the weakest possible mutant, caught by A0 (is the
# checker sourceable) rather than by the assertion the axis is named for. Axis 2 was exactly
# that for its whole life: its regex stopped at the `)` inside `:(exclude)...`, emitting
# unparseable bash, so it never tested pathspec parity at all. With a label, an axis that stops
# reaching its own property fails LOUDLY instead of passing for the wrong reason.
mutate_and_assert_red() {
  local axis="$1" rel="$2" mutator="$3" expect_label="${4:-}"
  local sbx="$TMP/mut-$axis"
  rm -rf "$sbx"
  if ! make_sandbox "$sbx"; then
    fail "C-$axis sandbox setup" "cp/mkdir rc=0" "setup failed (disk full?)"
    return 0
  fi
  local target="$sbx/$rel"
  local pristine="$TMP/pristine-$axis"
  cp "$target" "$pristine" || { fail "C-$axis pristine copy" "rc=0" "cp failed"; return 0; }

  if ! python3 -c "$mutator" "$target" 2>"$TMP/mut-err-$axis"; then
    fail "C-$axis mutator ran" "rc=0" "$(cat "$TMP/mut-err-$axis")"
    return 0
  fi
  # THE MUTATION MUST HAVE LANDED. A no-op sed that scores as "caught" is how a battery
  # becomes the false confidence it exists to remove.
  if diff -q "$pristine" "$target" >/dev/null 2>&1; then
    fail "C-$axis mutation LANDED (file actually changed)" "a differing file" "byte-identical"
    return 0
  fi

  local child_out
  child_out="$(run_child "$sbx")"
  local rc=$?

  if [[ "$rc" == "0" ]]; then
    fail "C-$axis $rel sabotage is caught" "child exit != 0" "child exit 0 (SURVIVED)"
    return 0
  fi

  # A syntax-error mutant trips A0 and nothing else. If the axis names a property, require the
  # assertion for THAT property to be among the failures.
  if [[ -n "$expect_label" ]]; then
    if printf '%s' "$child_out" | grep -q "FAIL: ${expect_label}"; then
      pass "C-$axis caught by ${expect_label}, the assertion it targets"
    else
      fail "C-$axis caught by ${expect_label}" "a FAIL line naming ${expect_label}" \
        "child failed on something else: $(printf '%s' "$child_out" | grep -m3 '^  FAIL' | tr '\n' ';')"
    fi
  else
    pass "C-$axis $rel sabotage is caught (child exit $rc)"
  fi
}

run_part_c() {
  echo "=== PART C: mutation battery ==="

  if [[ ! -f "$SUT" || ! -f "$WORKFLOW" ]]; then
    fail "C0 control preconditions (checker + workflow present)" "both present" "missing"
    return 0
  fi

  # CONTROL FIRST. A battery scored against a red baseline is void -- every axis would
  # "pass" for the wrong reason.
  local sbx="$TMP/control"
  if ! make_sandbox "$sbx"; then
    fail "C0 control sandbox setup" "rc=0" "setup failed"
    return 0
  fi
  local cout crc
  cout="$(run_child "$sbx")"; crc=$?
  if [[ "$crc" == "0" ]]; then
    pass "C0 unmutated control is GREEN (the battery's results are meaningful)"
  else
    fail "C0 unmutated control is GREEN" "exit 0" \
      "exit $crc — battery VOID, fix the baseline first: $(printf '%s' "$cout" | grep -m3 '^  FAIL' | tr '\n' ';')"
    return 0
  fi

  local WF=".github/workflows/scheduled-prod-version-drift.yml"
  local SH="scripts/prod-version-drift-check.sh"

  # Axis 1 -- delete the production call site. A hermetic unit test would stay green.
  mutate_and_assert_red "axis1-delete-callsite" "$WF" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=s.replace("prod-version-drift-check.sh","prod-version-drift-check-RENAMED.sh")
open(p,"w").write(s)' "B1 exactly one call to prod-version-drift-check.sh"

  # Axis 2 -- replace the pathspec with a bare main-HEAD comparison (the issue body sketch).
  # This is the change that reads as an obvious simplification and false-alarms continuously.
  mutate_and_assert_red "axis2-pathspec-to-head" "$SH" '
import sys,re
p=sys.argv[1]; s=open(p).read()
# DOTALL across the multi-line array, and anchored at line start so the match cannot end early
# on the ")" inside ":(exclude)...". The previous form produced a bash SYNTAX ERROR, so the
# axis was scored by A0 (sourceable) and never exercised pathspec parity at all.
s2,n = re.subn(r"(?m)^PATHSPEC=\(.*?\)\n", "PATHSPEC=()\n", s, count=1, flags=re.S)
assert n == 1, "axis2 mutator did not match the PATHSPEC array"
open(p,"w").write(s2)' "B8 checker PATHSPEC equals the release job"

  # Axis 3 -- drop --first-parent. A no-op today, load-bearing the moment a merge lands.
  #
  # MUTATES CODE ONLY, NEVER PROSE. A naive `s.replace(tok, "", 1)` rewrites the FIRST
  # occurrence in the file, and both of these tokens are DOCUMENTED in the checker header
  # above the code that uses them -- so the sabotage landed in a comment, the real invocation
  # was untouched, and the axis reported SURVIVED while the artifact was in fact correct. A
  # mutation that cannot reach the property is not evidence about the property.
  mutate_and_assert_red "axis3-drop-first-parent" "$SH" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n")
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if "--first-parent " in l:
        ls[i]=l.replace("--first-parent ","",1); break
open(p,"w").write("\n".join(ls))' "B8b the checker"

  # Axis 4 -- anchor the staleness clock to the NEWEST missing commit. Under a steady commit
  # stream this resets forever and never escalates while prod rots. Code-only, per axis 3.
  mutate_and_assert_red "axis4-newest-not-oldest" "$SH" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n")
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if "sort -n | head -1" in l:
        ls[i]=l.replace("sort -n | head -1","sort -n | tail -1",1); break
open(p,"w").write("\n".join(ls))' "A6 oldest_epoch_from_log picks the OLDEST"

  # Axis 5 -- replace an alert condition with a bare !cancelled(). True on success too, so
  # this emails on every healthy tick.
  # The pattern is deliberately tolerant of ADDITIONAL leading conjuncts. It was originally
  # anchored on the exact string `!cancelled() && steps.check.outputs.exit_code == '1'`, and
  # #7304 then inserted `steps.check.outcome == 'success' &&` between the two -- at which point
  # the regex matched nothing, the mutation silently did not land, and this axis stopped being
  # evidence about B3b. A mutator keyed on an exact expression shape is coupled to every future
  # edit of that expression; key it on the two ENDS instead.
  mutate_and_assert_red "axis5-bare-not-cancelled" "$WF" '
import sys,re
p=sys.argv[1]; ls=open(p).read().split("\n"); n=0
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if not l.lstrip().startswith("if:"): continue
    l2,k=re.subn(r"\$\{\{ !cancelled\(\)[^}]*exit_code == .1. \}\}",
                 "${{ !cancelled() }}", l, count=1)
    if k:
        ls[i]=l2; n+=1; break
assert n == 1, "axis5 mutator did not match a drift-gated if: CONDITION (comment-only match?)"
open(p,"w").write("\n".join(ls))' "B3b every alerting step carries a verdict conjunct"

  # Axis 6 -- delete the label bootstrap. gh issue create --label hard-fails on an undefined
  # label, so the verdict would reach the email channel only.
  mutate_and_assert_red "axis6-drop-label-bootstrap" "$WF" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^.*gh label create.*\n(^.*--description.*\n)?", "", s, count=1, flags=re.M)
open(p,"w").write(s)' "B5 every"

  # Axis 7 -- delete close-on-recovery. The issue then never closes and the standing signal
  # becomes permanent noise the operator learns to ignore.
  mutate_and_assert_red "axis7-drop-close-on-recovery" "$WF" '
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("gh issue close","gh issue view",1)
open(p,"w").write(s)' "B6 exactly two close steps"

  # Axis 8 -- flip the heartbeat first conjunct from the step OUTCOME to the output value.
  # A step that dies before writing its output leaves it empty; an output-only test reads
  # that as a value rather than as a death (#7138, one layer up).
  # CODE-ONLY AND HEARTBEAT-ANCHORED, per axis 3. This mutator used to replace the first
  # occurrence of the conjunct anywhere in the file, which worked only while the heartbeat was
  # its ONLY occurrence. #7304 added the same conjunct to six if: gates AND documented it in
  # prose above them, so a first-occurrence replace would now rewrite a COMMENT -- the mutation
  # "lands" (the file differs), B7c stays green, and the axis reports SURVIVED against a
  # perfectly correct artifact. The status expression is the one whose `${{` opens directly on
  # the conjunct; every if: gate opens on `!cancelled()`.
  mutate_and_assert_red "axis8-heartbeat-first-conjunct" "$WF" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n"); n=0
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if "${{ steps.check.outcome == \x27success\x27" in l:
        ls[i]=l.replace("steps.check.outcome == \x27success\x27",
                        "steps.check.outputs.exit_code != \x27\x27",1); n+=1; break
assert n == 1, "axis8 mutator did not match the heartbeat status expression"
open(p,"w").write("\n".join(ls))' "B7c heartbeat status"

  # Axis 9 -- shallow checkout. Puts the checker in permanent CHECK_ERROR on the COMMON path,
  # because origin/main HEAD is frequently not a path-matching commit. Code-only, per axis 3:
  # the workflow header explains WHY fetch-depth is 0, so a first-occurrence replace mutated
  # the justification comment and left the actual `with:` block intact.
  mutate_and_assert_red "axis9-fetch-depth-1" "$WF" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n")
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if "fetch-depth: 0" in l:
        ls[i]=l.replace("fetch-depth: 0","fetch-depth: 1",1); break
open(p,"w").write("\n".join(ls))' "B2b checkout declares fetch-depth: 0"

  # Axis 10 -- neuter the 40-hex validation so the literal string "null" flows through as a
  # SHA. jq -r prints "null" for both {} and {"build_sha":null}, exit 0 either way.
  mutate_and_assert_red "axis10-drop-sha-validation" "$SH" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"\[\[ \"\$sha\" =~ \^\[0-9a-f\]\{40\}\$ \]\]", "true", s, count=1)
open(p,"w").write(s)' "A11 body {}" "B2b checkout declares fetch-depth: 0"

  # Axis 11 -- delete the errexit clear from the check body: the #7304 outage itself, restored.
  #
  # This is the control that makes B14 evidence rather than decoration. Without it, B14 could
  # degrade into asserting that a working body works, and nothing would notice -- which is the
  # precise shape of the original bug, where the CLEAN path passed unchanged for eight
  # consecutive runs while the two alerting verdicts were dark.
  #
  # MUTATES CODE ONLY, NEVER PROSE, per axis 3 and axis 9. The rationale comment above this very
  # statement contains the literal `set +e` (it has to -- it explains why the statement is
  # required), so a naive s.replace("set +e", "", 1) rewrites the COMMENT: the file differs, so
  # diff -q reports the mutation landed, the child stays GREEN, and the axis reports SURVIVED
  # while the artifact is in fact correct. Match a whole line that IS the statement.
  mutate_and_assert_red "axis11-drop-errexit-clear" "$WF" '
import sys,re
p=sys.argv[1]; ls=open(p).read().split("\n"); out=[]; n=0
for l in ls:
    if n==0 and not l.lstrip().startswith("#") and re.match(r"^\s*set \+e\s*$", l):
        n+=1; continue
    out.append(l)
assert n == 1, "axis11 mutator did not remove a set +e STATEMENT (comment-only match?)"
open(p,"w").write("\n".join(out))' "B14 (exit 1)"

  # Axis 12 -- strip the outcome conjunct from an exit_code gate: the empty-string coercion
  # fail-open, re-armed. `\x27\x27 == \x270\x27` is TRUE in an Actions expression, so without
  # this conjunct a check step that died before writing its output satisfies every == 0 gate --
  # and the workflow auto-closes the issue reporting its own breakage. Observed on run
  # 31054501973. Code-only for the same reason as axis 11: the conjunct is documented in prose
  # directly above the gates it guards.
  mutate_and_assert_red "axis12-drop-outcome-conjunct" "$WF" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n"); n=0
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if l.lstrip().startswith("if:") and "steps.check.outputs.exit_code" in l \
       and "steps.check.outcome == \x27success\x27 && " in l:
        ls[i]=l.replace("steps.check.outcome == \x27success\x27 && ","",1); n+=1; break
assert n == 1, "axis12 mutator did not strip a conjunct from an exit_code gate"
open(p,"w").write("\n".join(ls))' "B17"
}

# ---------------------------------------------------------------------------

echo "=== prod-version-drift-check.sh tests ==="
_before=0
[[ "$PARTS" == *A* ]] && { _before=$((PASS + FAIL)); run_part_a; COUNT_A=$(( PASS + FAIL - _before )); }
[[ "$PARTS" == *B* ]] && { _before=$((PASS + FAIL)); run_part_b; COUNT_B=$(( PASS + FAIL - _before )); }
# Part C is skipped inside mutation children (recursion guard) and when PARTS excludes it.
if [[ "$PARTS" == *C* && "$MUTATION_CHILD" == "0" ]]; then
  _before=$((PASS + FAIL))
  run_part_c
  COUNT_C=$(( PASS + FAIL - _before ))
fi

TOTAL=$((PASS + FAIL))
echo ""
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED: $FAIL assertion(s)"
  exit 1
fi
# The global floor is only non-slack while it EQUALS the sum of the per-part floors. That held
# by coincidence before #7304 (117 = 57+49+11) and nothing asserted it, so raising one part's
# floor without the global would have left the global slack by exactly the amount added -- the
# hole this whole block exists to close. Checked only on a full run, since a subset invocation
# legitimately overrides the parts it is not running.
if [[ "$PARTS" == "ABC" && "$MUTATION_CHILD" == "0" ]]; then
  _floor_sum=$(( MIN_A + MIN_B + MIN_C ))
  if [[ "$MIN_ASSERTIONS" -ne "$_floor_sum" ]]; then
    echo "FAILED: MIN_ASSERTIONS=$MIN_ASSERTIONS != MIN_A+MIN_B+MIN_C=$_floor_sum — the global floor is slack by the difference"
    exit 1
  fi
fi
# An assertion-count regression means a block was deleted -- "nothing failed" is not the same
# as "everything was checked".
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAILED: assertion count $TOTAL regressed below MIN_ASSERTIONS=$MIN_ASSERTIONS"
  exit 1
fi
# Per-part floors, checked only for the parts this invocation actually ran. Children run
# DRIFT_MIN_*=0 so the battery can drive A+B subsets without tripping them.
_floor_fail=0
[[ "$PARTS" == *A* && "$COUNT_A" -lt "$MIN_A" ]] && { echo "FAILED: Part A shrank to $COUNT_A (floor $MIN_A)"; _floor_fail=1; }
[[ "$PARTS" == *B* && "$COUNT_B" -lt "$MIN_B" ]] && { echo "FAILED: Part B shrank to $COUNT_B (floor $MIN_B)"; _floor_fail=1; }
if [[ "$PARTS" == *C* && "$MUTATION_CHILD" == "0" && "$COUNT_C" -lt "$MIN_C" ]]; then
  echo "FAILED: Part C shrank to $COUNT_C (floor $MIN_C) — the mutation battery is the suite's own anti-vacuity mechanism; deleting it must not be free"
  _floor_fail=1
fi
[[ "$_floor_fail" -ne 0 ]] && exit 1
echo "All tests passed"
