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
# Anti-vacuity floor: if a future edit deletes an assertion block, the suite must fail even
# though nothing "failed". Raise this deliberately when adding coverage.
MIN_ASSERTIONS="${DRIFT_MIN_ASSERTIONS:-58}"

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

  # A future-dated commit (clock skew) must not underflow into a huge age and page.
  _classify "$OK_JSON" 0 1 "$((NOW + 600))" 0 "$NOW"
  assert_eq "A19 future-dated commit (clock skew) -> not a page" "0" "$rc"

  # Ordering: an evaluation failure outranks a drift signal. If we could not read prod, we do
  # not get to claim we know prod is stale.
  _classify "" 28 5 "$((NOW - THRESH_S - 60))" 0 "$NOW"
  assert_eq "A20 curl failure outranks a stale-looking count -> CHECK_ERROR" "2" "$rc"
}

# ---------------------------------------------------------------------------
# PART B -- wiring pins against the SHIPPED workflow
# ---------------------------------------------------------------------------

# Emits key=value lines the shell can read. Every step selector asserts exactly-one
# cardinality, so a rename fails loudly instead of extracting nothing.
PYEXTRACT='
import sys, yaml, json, re

wf_path, rel_path = sys.argv[1], sys.argv[2]
try:
    wf = yaml.safe_load(open(wf_path))
except Exception as e:
    print("EXTRACT_ERROR=%s" % str(e).replace("\n", " ")); sys.exit(0)
if not isinstance(wf, dict):
    print("EXTRACT_ERROR=workflow did not parse to a mapping"); sys.exit(0)

def emit(k, v):
    print("%s=%s" % (k, str(v).replace("\n", "\\n")))

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
        and "prod-version-drift-check.sh" in s["run"]]
emit("CALLSITE_COUNT", len(runs))
if runs:
    emit("CALLSITE_JOB", runs[0][0])
    body = runs[0][1]["run"]
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
    body = s.get("run") or ""
    uses = s.get("uses") or ""
    if ("gh issue create" in body or "gh issue comment" in body
            or "api.resend.com" in body or "notify-ops-email" in uses):
        # the close-on-recovery step touches gh issue close, not create/comment
        alerting.append(s)
emit("ALERT_STEP_COUNT", len(alerting))
bad = [norm(s.get("if", "")) for s in alerting
       if "exit_code == \x271\x27" not in norm(s.get("if", ""))
       and "exit_code == \x272\x27" not in norm(s.get("if", ""))]
emit("ALERT_STEPS_WITHOUT_VERDICT_CONJUNCT", len(bad))
if bad:
    emit("ALERT_BAD_IF", bad[0])
# B4: no alerting step may be reachable on a clean tick.
emit("ALERT_STEPS_REACHABLE_WHEN_CLEAN",
     len([s for s in alerting if "exit_code == \x270\x27" in norm(s.get("if", ""))]))

closers = [s for (_, s) in steps if "gh issue close" in (s.get("run") or "")]
emit("CLOSE_STEP_COUNT", len(closers))
if closers:
    emit("CLOSE_STEP_IF", norm(closers[0].get("if", "")))

# --- B5: label bootstrap precedes every issue create, in the same body --------
viol = 0
for (_, s) in steps:
    body = s.get("run") or ""
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
try:
    rel = yaml.safe_load(open(rel_path))
    pf = ((rel.get("jobs") or {}).get("release") or {}).get("with", {}).get("path_filter", "")
    emit("RELEASE_PATH_FILTER", pf)
    rjobs = rel.get("jobs") or {}
    tot = 0
    for j in ("await-ci", "migrate", "verify-migrations", "deploy"):
        tot += int((rjobs.get(j) or {}).get("timeout-minutes") or 0)
    emit("RELEASE_SERIAL_TIMEOUT_SUM", tot)
except Exception as e:
    emit("RELEASE_PARSE_ERROR", str(e).replace("\n", " "))

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
  assert_eq "B3b every alerting step carries an exit_code conjunct (never a bare !cancelled())" \
    "0" "${X_ALERT_STEPS_WITHOUT_VERDICT_CONJUNCT:-1}"

  # B4 -- the anti-spam pin, stated as its own property rather than inferred from B3.
  assert_eq "B4 NO alerting step is reachable when exit_code == '0'" \
    "0" "${X_ALERT_STEPS_REACHABLE_WHEN_CLEAN:-1}"

  # B5 -- gh issue create --label hard-fails on an undefined label, and ci/prod-version-drift
  # does not exist yet. This repo has already shipped that exact failure twice.
  assert_eq "B5 every 'gh issue create' is preceded by a label bootstrap in the same body" \
    "0" "${X_ISSUE_CREATE_WITHOUT_PRIOR_LABEL_BOOTSTRAP:-1}"

  # B6 -- close-on-recovery must EXIST and be gated on clean. Without it the issue never
  # closes and "one issue per episode" is fiction.
  assert_eq "B6 exactly one close-on-recovery step" "1" "${X_CLOSE_STEP_COUNT:-0}"
  assert_contains "B6b close-on-recovery is gated on exit_code == '0'" \
    "exit_code == '0'" "${X_CLOSE_STEP_IF:-}"

  # B7 -- heartbeat semantics. The first conjunct must be the step OUTCOME (#7138's lesson:
  # a step that dies before writing its output leaves the output empty, and an output-only
  # test reads that as a value rather than as a death).
  assert_eq "B7 exactly one sentry-heartbeat step" "1" "${X_HEARTBEAT_COUNT:-0}"
  assert_eq "B7b heartbeat runs unconditionally (if: always())" "always()" "${X_HEARTBEAT_IF:-}"
  assert_contains "B7c heartbeat status' FIRST conjunct is steps.check.outcome == 'success'" \
    "^\\\$\\{\\{ steps\.check\.outcome == 'success'" "${X_HEARTBEAT_STATUS:-}"
  assert_contains "B7d heartbeat drift arm requires the email actually delivered" \
    "delivered == '1'" "${X_HEARTBEAT_STATUS:-}"
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

  # B9 -- threshold safety, in the SAFE direction: a pipeline timeout INCREASE fails the
  # suite, so the threshold can never silently become smaller than legitimate latency.
  if [[ -n "${THRESH_MIN:-}" && "${X_RELEASE_SERIAL_TIMEOUT_SUM:-0}" =~ ^[0-9]+$ ]]; then
    if [[ "$THRESH_MIN" -ge "${X_RELEASE_SERIAL_TIMEOUT_SUM}" ]]; then
      pass "B9 threshold (${THRESH_MIN}m) >= release serial critical path (${X_RELEASE_SERIAL_TIMEOUT_SUM}m)"
    else
      fail "B9 threshold >= release serial critical path" \
        ">= ${X_RELEASE_SERIAL_TIMEOUT_SUM}" "$THRESH_MIN"
    fi
  else
    fail "B9 threshold and release timeouts both readable" "integers" \
      "thresh=${THRESH_MIN:-<unset>} sum=${X_RELEASE_SERIAL_TIMEOUT_SUM:-<unset>}"
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
    DRIFT_TEST_SCRIPT="$sbx/scripts/prod-version-drift-check.sh" \
    DRIFT_TEST_WORKFLOW="$sbx/.github/workflows/scheduled-prod-version-drift.yml" \
    DRIFT_TEST_RELEASE_WORKFLOW="$sbx/.github/workflows/web-platform-release.yml" \
    DRIFT_TEST_MONITORS_TF="$sbx/apps/web-platform/infra/sentry/cron-monitors.tf" \
    bash "$sbx/scripts/prod-version-drift-check.test.sh" >/dev/null 2>&1
  )
  echo $?
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
  return 0
}

# mutate <axis-name> <target-relative-path> <python-mutator>
# The mutator reads the file on stdin and writes the mutated text on stdout.
mutate_and_assert_red() {
  local axis="$1" rel="$2" mutator="$3"
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

  local rc
  rc="$(run_child "$sbx")"
  if [[ "$rc" != "0" ]]; then
    pass "C-$axis $rel sabotage is caught (child exit $rc)"
  else
    fail "C-$axis $rel sabotage is caught" "child exit != 0" "child exit 0 (SURVIVED)"
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
  local crc
  crc="$(run_child "$sbx")"
  if [[ "$crc" == "0" ]]; then
    pass "C0 unmutated control is GREEN (the battery's results are meaningful)"
  else
    fail "C0 unmutated control is GREEN" "exit 0" "exit $crc — battery VOID, fix the baseline first"
    return 0
  fi

  local WF=".github/workflows/scheduled-prod-version-drift.yml"
  local SH="scripts/prod-version-drift-check.sh"

  # Axis 1 -- delete the production call site. A hermetic unit test would stay green.
  mutate_and_assert_red "axis1-delete-callsite" "$WF" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=s.replace("prod-version-drift-check.sh","prod-version-drift-check-RENAMED.sh")
open(p,"w").write(s)'

  # Axis 2 -- replace the pathspec with a bare main-HEAD comparison (the issue body sketch).
  # This is the change that reads as an obvious simplification and false-alarms continuously.
  mutate_and_assert_red "axis2-pathspec-to-head" "$SH" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"PATHSPEC=\([^)]*\)", "PATHSPEC=()", s, count=1)
open(p,"w").write(s)'

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
open(p,"w").write("\n".join(ls))'

  # Axis 4 -- anchor the staleness clock to the NEWEST missing commit. Under a steady commit
  # stream this resets forever and never escalates while prod rots. Code-only, per axis 3.
  mutate_and_assert_red "axis4-newest-not-oldest" "$SH" '
import sys
p=sys.argv[1]; ls=open(p).read().split("\n")
for i,l in enumerate(ls):
    if l.lstrip().startswith("#"): continue
    if "sort -n | head -1" in l:
        ls[i]=l.replace("sort -n | head -1","sort -n | tail -1",1); break
open(p,"w").write("\n".join(ls))'

  # Axis 5 -- replace an alert condition with a bare !cancelled(). True on success too, so
  # this emails on every healthy tick.
  mutate_and_assert_red "axis5-bare-not-cancelled" "$WF" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"\$\{\{ !cancelled\(\) && steps\.check\.outputs\.exit_code == .1. \}\}",
         "${{ !cancelled() }}", s, count=1)
open(p,"w").write(s)'

  # Axis 6 -- delete the label bootstrap. gh issue create --label hard-fails on an undefined
  # label, so the verdict would reach the email channel only.
  mutate_and_assert_red "axis6-drop-label-bootstrap" "$WF" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^.*gh label create.*\n(^.*--description.*\n)?", "", s, count=1, flags=re.M)
open(p,"w").write(s)'

  # Axis 7 -- delete close-on-recovery. The issue then never closes and the standing signal
  # becomes permanent noise the operator learns to ignore.
  mutate_and_assert_red "axis7-drop-close-on-recovery" "$WF" '
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("gh issue close","gh issue view",1)
open(p,"w").write(s)'

  # Axis 8 -- flip the heartbeat first conjunct from the step OUTCOME to the output value.
  # A step that dies before writing its output leaves it empty; an output-only test reads
  # that as a value rather than as a death (#7138, one layer up).
  mutate_and_assert_red "axis8-heartbeat-first-conjunct" "$WF" '
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("steps.check.outcome == \x27success\x27","steps.check.outputs.exit_code != \x27\x27",1)
open(p,"w").write(s)'

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
open(p,"w").write("\n".join(ls))'

  # Axis 10 -- neuter the 40-hex validation so the literal string "null" flows through as a
  # SHA. jq -r prints "null" for both {} and {"build_sha":null}, exit 0 either way.
  mutate_and_assert_red "axis10-drop-sha-validation" "$SH" '
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"\[\[ \"\$sha\" =~ \^\[0-9a-f\]\{40\}\$ \]\]", "true", s, count=1)
open(p,"w").write(s)'
}

# ---------------------------------------------------------------------------

echo "=== prod-version-drift-check.sh tests ==="
[[ "$PARTS" == *A* ]] && run_part_a
[[ "$PARTS" == *B* ]] && run_part_b
# Part C is skipped inside mutation children (recursion guard) and when PARTS excludes it.
if [[ "$PARTS" == *C* && "$MUTATION_CHILD" == "0" ]]; then
  run_part_c
fi

TOTAL=$((PASS + FAIL))
echo ""
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED: $FAIL assertion(s)"
  exit 1
fi
# An assertion-count regression means a block was deleted -- "nothing failed" is not the same
# as "everything was checked".
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  echo "FAILED: assertion count $TOTAL regressed below MIN_ASSERTIONS=$MIN_ASSERTIONS"
  exit 1
fi
echo "All tests passed"
