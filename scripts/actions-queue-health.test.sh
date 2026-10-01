#!/usr/bin/env bash
# Guard — actions-queue-health.sh verdict logic (#8450 queue-health monitor).
#
# PROPERTY. The probe exits 1 (UNDER_ASSIGNED) only when ALL of: live queue
# depth (queued minus zombie-tail) >= QUEUE_DEPTH_ALERT, the MEDIAN age of
# live (non-zombie) queued members on the newest page >= QUEUE_STALL_ALERT_S,
# AND jobs-in-flight < MIN_ASSIGN_PCT of the effective cap (plan-typed, or the
# Free floor of 20 when .plan is unreadable to the credential). A deep+stalled
# queue with delivered >= threshold is SATURATED (exit 0 — the entitlement is
# working; demand is the problem). Shallow or young-median queues are HEALTHY.
# Any prereq/API/parse failure exits 2 — never silently HEALTHY.
#
# ZOMBIE IMMUNITY is the load-bearing property (live data showed a 130-day-old
# schedule run and 34-day-old issues runs still status=queued): zombie members
# are excluded from the stall median and discounted from depth, so a permanent
# dead tail cannot pin the alert gate open — and cannot pin it shut either
# (newest-arrival age is never consulted for the verdict).
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH, byte-similar to
# followthroughs/actions-queue-tail-8450.test.sh's: it answers ONLY the exact
# endpoint strings the probe may issue, honors --jq by piping through real jq,
# and logs every invocation to calls.log (STUB-UNEXPECTED on anything else —
# the probe's own 2>/dev/null would swallow stub stderr). Endpoint matching is
# EXACT, so per_page=1 does not prefix-match per_page=100.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); timestamps are
# generated relative to NOW via iso_ago so age arithmetic stays meaningful.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/actions-queue-health.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v jq >/dev/null || { echo "FATAL: jq required for the fixture stub" >&2; exit 1; }

iso_ago() { # GNU date first, BSD fallback (the suite is CI-linux but must run locally on macOS)
  local target=$(( $(date -u +%s) - $1 ))
  date -u -d "@$target" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null     || date -u -j -f %s "$target" +%Y-%m-%dT%H:%M:%SZ
}

# ── fixture builders ────────────────────────────────────────────────────────
# run_row <id> <created_at>
run_row() { printf '{"id":%s,"created_at":"%s","status":"queued"}' "$1" "$2"; }
# job_row <name> <status> <created_at>  (jobs under IN-PROGRESS runs only —
# the probe never fetches jobs for queued runs; a queued-run jobs call is a
# STUB-UNEXPECTED, which is itself part of the contract this suite pins)
job_row() { printf '{"name":"%s","status":"%s","created_at":"%s","started_at":null}' "$1" "$2" "$3"; }

write_runs() { # <file> <status> <run_row>...
  local file="$1" status="$2" rows="" first=1 r; shift 2
  for r in "$@"; do
    if [ "$first" -eq 1 ]; then rows="$r"; first=0; else rows="$rows,$r"; fi
  done
  printf '{"total_count":%d,"workflow_runs":[%s]}\n' "$#" "$rows" > "$file"
}
write_jobs() { # <file> <job_row>...
  local file="$1" rows="" first=1 r; shift
  for r in "$@"; do
    if [ "$first" -eq 1 ]; then rows="$r"; first=0; else rows="$rows,$r"; fi
  done
  printf '{"total_count":%d,"jobs":[%s]}\n' "$#" "$rows" > "$file"
}

# queued_page <run_row>... — the rows the probe sees on page 1 (newest-first).
# queued_last <run_row>... — the last-page fixture, fetched only when
# queued_count > 100 (the stub STUB-UNEXPECTEDs a last-page fetch otherwise).
queued_page()  { write_runs "$WORK/fix/queued-page.json" queued "$@"; }
queued_last()  { write_runs "$WORK/fix/queued-page-last.json" queued "$@"; }
clear_last()   { rm -f "$WORK/fix/queued-page-last.json"; }
# live_rows <n> <age_s> — n queued-run rows at the same age (ids 90000+).
live_rows() {
  local n="$1" age="$2" i ts rows=()
  ts="$(iso_ago "$age")"
  for i in $(seq "$n"); do rows+=("$(run_row $((90000 + i)) "$ts")"); done
  printf '%s\n' "${rows[@]}"
}
# inprogress <n_runs> — n in-progress runs (ids 700,701,...); attach their job
# payloads with jobs_for afterwards.
inprogress()   { local rows=() id=700 i; for i in $(seq "${1:-0}"); do rows+=("$(run_row $id "$(iso_ago 300)")"); id=$((id+1)); done; write_runs "$WORK/fix/inprogress.json" in_progress "${rows[@]}"; }
jobs_for()     { write_jobs "$WORK/fix/jobs-$1.json" "${@:2}"; }
infl()         { job_row "j$2" in_progress "$(iso_ago 200)"; }  # shorthand

mkplan()      { rm -f "$WORK/fix/fail-plan"; printf '{"plan":{"name":"%s"}}\n' "$1" > "$WORK/fix/plan.json"; }
queued_count() { printf '{"total_count":%s,"workflow_runs":[]}\n' "$1" > "$WORK/fix/queued-count.json"; }
fail_endpoint() { : > "$WORK/fix/fail-$1"; }

# in_flight <n> — one in-progress run carrying exactly n in_progress jobs.
in_flight() {
  local n="$1" i rows=()
  inprogress 1
  for i in $(seq "$n"); do rows+=("$(infl x "$i")"); done
  jobs_for 700 "${rows[@]}"
}

# run_probe — env-isolated: only PATH/HOME/GH_TOKEN/FIXTURE_DIR + probe knobs.
run_probe() {
  local out rc
  : > "$WORK/fix/calls.log"
  # shellcheck disable=SC2086 # PROBE_ENV carries simple KEY=val pairs
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN="${GH_TOKEN_VAL-fake}" \
        FIXTURE_DIR="$WORK/fix" REPO=jikig-ai/soleur ${PROBE_ENV:-} bash "$PROBE" "$@" 2>&1)"
  rc=$?
  printf '%s' "$out" > "$WORK/out"
  return $rc
}

expect() { # <desc> <want_rc> <needle>
  local desc="$1" want="$2" needle="${3:-}" rc=0
  run_probe || rc=$?
  if grep -q 'STUB-UNEXPECTED' "$WORK/fix/calls.log"; then
    fail "$desc (probe hit an unstubbed endpoint: $(grep STUB-UNEXPECTED "$WORK/fix/calls.log" | head -1))"
    return
  fi
  if [ "$rc" -ne "$want" ]; then
    fail "$desc (want rc=$want got rc=$rc; out: $(tail -3 "$WORK/out"))"
    return
  fi
  if [ -n "$needle" ] && ! grep -qF "$needle" "$WORK/out"; then
    fail "$desc (rc ok but output missing '$needle'; out: $(tail -2 "$WORK/out"))"
    return
  fi
  pass "$desc"
}

# ── the stub ────────────────────────────────────────────────────────────────
mkdir -p "$WORK/bin" "$WORK/fix"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
FIX="${FIXTURE_DIR:?}"
printf 'gh %s\n' "$*" >> "$FIX/calls.log"
[[ "${1:-}" == "api" ]] || { printf 'STUB-UNEXPECTED: gh %s\n' "$*" >> "$FIX/calls.log"; exit 64; }
shift
ep=""
JQEXPR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) JQEXPR="${2:-}"; shift 2 ;;
    --*) shift ;;
    *) [ -z "$ep" ] && ep="$1"; shift ;;
  esac
done
out() { if [[ -n "$JQEXPR" ]]; then jq -r "$JQEXPR"; else cat; fi; }
case "$ep" in
  orgs/jikig-ai)
    [[ -f "$FIX/fail-plan" ]] && exit 1
    out < "$FIX/plan.json" ;;
  repos/*/actions/runs\?status=queued\&per_page=1)
    [[ -f "$FIX/fail-queued" ]] && exit 1
    out < "$FIX/queued-count.json" ;;
  repos/*/actions/runs\?status=queued\&per_page=100\&page=1)
    [[ -f "$FIX/fail-queuedpage" ]] && exit 1
    out < "$FIX/queued-page.json" ;;
  repos/*/actions/runs\?status=queued\&per_page=100\&page=*)
    # Last-page fetch: only legitimate when the count says >100 queued. No
    # fixture means the probe fetched a page it shouldn't have.
    [[ -f "$FIX/fail-queuedpage" ]] && exit 1
    if [[ -f "$FIX/queued-page-last.json" ]]; then out < "$FIX/queued-page-last.json"; else
      printf 'STUB-UNEXPECTED: last-page fetch without fixture: %s\n' "$ep" >> "$FIX/calls.log"; exit 64; fi ;;
  repos/*/actions/runs\?status=in_progress\&per_page=*)
    [[ -f "$FIX/fail-ip" ]] && exit 1
    out < "$FIX/inprogress.json" ;;
  repos/*/actions/runs/*/jobs)
    id="$(printf '%s' "$ep" | sed -E 's|.*/runs/([0-9]+)/jobs|\1|')"
    [[ -f "$FIX/fail-jobs-$id" ]] && exit 1
    if [[ -f "$FIX/jobs-$id.json" ]]; then out < "$FIX/jobs-$id.json"; else
      printf 'STUB-UNEXPECTED: no jobs fixture for run %s\n' "$id" >> "$FIX/calls.log"; exit 64; fi ;;
  *) printf 'STUB-UNEXPECTED: gh api %s\n' "$ep" >> "$FIX/calls.log"; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

# ── cases ───────────────────────────────────────────────────────────────────

# 1. Idle: no queue, a few jobs in flight -> HEALTHY
mkplan team
queued_count 0
inprogress 1
jobs_for 700 "$(infl x 1)" "$(infl x 2)"
expect "idle pool -> HEALTHY" 0 "HEALTHY:"

# 2. Saturated: deep stalled live queue but delivered 30 = 50% of team cap(60)
mkplan team
queued_count 40
in_flight 30
queued_page $(live_rows 30 1900)
expect "deep+stalled queue at 30/60 delivered -> SATURATED" 0 "SATURATED:"

# 3. THE INCIDENT SHAPE: deep+stalled queue, 10 delivered on a 60 cap.
#    >100 queued exercises the last-page fetch (queued_last fixture).
mkplan team
queued_count 200
in_flight 10
queued_page $(live_rows 30 1900)
queued_last "$(run_row 600 "$(iso_ago 3000)")"
expect "200-deep stalled queue, 10/60 delivered -> UNDER_ASSIGNED" 1 "UNDER_ASSIGNED:"
clear_last

# 4. Continuous-arrivals discrimination: the NEWEST member is seconds old (the
#    incident actually looked like this — sessions kept pushing) but the live
#    median is old. Newest-age gating would miss it; median does not.
mkplan team
queued_count 40
in_flight 10
queued_page "$(run_row 601 "$(iso_ago 10)")" $(live_rows 28 2000)
expect "young newest + old median -> UNDER_ASSIGNED (newest-age gate would miss)" 1 "UNDER_ASSIGNED:"

# 5. Unreadable plan (repo-scoped token), no override: cap falls back to free
#    floor 20, min_delivered=10 — 5 delivered with deep stalled queue ->
#    UNDER_ASSIGNED on ANY tier.
mkplan team
fail_endpoint plan
queued_count 60
in_flight 5
queued_page $(live_rows 30 1900)
expect "unreadable plan, 5 delivered, deep stalled queue -> UNDER_ASSIGNED" 1 "UNDER_ASSIGNED:"

# 6. Unreadable plan, no override, 15 delivered: inside the [10, real_cap*0.5)
#    dead-band — cannot prove under-assignment on an unknown entitlement ->
#    SATURATED (acknowledged tradeoff; CAP_OVERRIDE closes the band — case 22).
in_flight 15
expect "unreadable plan, 15 delivered -> SATURATED (floor dead-band)" 0 "SATURATED:"

# 7. Unreadable plan + CAP_OVERRIDE=60 (the deployed path — the workflow pins
#    the known Team entitlement): 15 delivered IS under-assignment now.
PROBE_ENV="CAP_OVERRIDE=60" expect "unreadable plan + CAP_OVERRIDE=60, 15 delivered -> UNDER_ASSIGNED" 1 "UNDER_ASSIGNED:"
unset PROBE_ENV 2>/dev/null || true
rm -f "$WORK/fix/fail-plan"

# 8. Free plan at capacity: 18 of 20 delivered with deep stalled queue -> SATURATED
mkplan free
queued_count 30
in_flight 18
queued_page $(live_rows 26 1900)
expect "free plan at 18/20, deep stalled queue -> SATURATED" 0 "SATURATED:"

# 9. Free plan UNDER-assigned: 3 of 20 (<10) with deep stalled queue -> alert
mkplan free
queued_count 30
in_flight 3
queued_page $(live_rows 26 1900)
expect "free plan at 3/20, deep stalled queue -> UNDER_ASSIGNED" 1 "UNDER_ASSIGNED:"

# 10. Deep but YOUNG median: 30 live queued, median live age ~100s -> HEALTHY
mkplan team
queued_count 40
in_flight 1
queued_page $(live_rows 30 100)
expect "deep but young-median queue -> HEALTHY" 0 "HEALTHY:"

# 11. Stalled but SHALLOW queue: median old but only 10 live (<25) -> HEALTHY
mkplan team
queued_count 10
in_flight 0
queued_page $(live_rows 10 5000)
expect "stalled but shallow queue -> HEALTHY" 0 "HEALTHY:"

# 12. ZOMBIE TAIL immunity: 3 zombie runs (>24h) + 1 young live member.
#     live members form a prefix of the newest-first list, so live=1 EXACT
#     (not 30-3) -> shallow -> HEALTHY, and zombies are still reported.
mkplan team
queued_count 30
in_flight 0
queued_page "$(run_row 610 "$(iso_ago 60)")" \
            "$(run_row 611 "$(iso_ago 90000)")" \
            "$(run_row 612 "$(iso_ago 100000)")" \
            "$(run_row 613 "$(iso_ago 11000000)")"
rc=0
run_probe --json || rc=$?
if [ "$rc" -eq 0 ] \
   && printf '%s' "$(cat "$WORK/out")" | jq -e '.verdict == "HEALTHY" and .zombie_runs == 3 and .live_queued_runs == 1' >/dev/null 2>&1; then
  pass "zombie tail cannot pin the stall gate open (HEALTHY, live=1 exact, zombies reported)"
else
  fail "zombie immunity (rc=$rc; out: $(tail -4 "$WORK/out"))"
fi

# 13. All-zombie queue: every queued member is >24h old -> HEALTHY (nothing live
#     is waiting; the zombies are a hygiene finding, not starvation)
mkplan team
queued_count 30
in_flight 0
queued_page "$(run_row 611 "$(iso_ago 90000)")" \
            "$(run_row 612 "$(iso_ago 100000)")" \
            "$(run_row 613 "$(iso_ago 11000000)")"
expect "all-zombie queue -> HEALTHY" 0 "HEALTHY:"

# 14. Missing GH_TOKEN -> UNKNOWN, exit 2
mkplan team; queued_count 0; in_flight 0
GH_TOKEN_VAL="" expect "no GH_TOKEN -> UNKNOWN rc2" 2 "UNKNOWN:"

# 15. gh api failure on the queued-count call -> UNKNOWN, exit 2 (not silent green)
mkplan team
fail_endpoint queued
in_flight 0
expect "queued-count API failure -> UNKNOWN rc2" 2 "UNKNOWN:"
rm -f "$WORK/fix/fail-queued"

# 16. Boundary: median live age exactly at the stall threshold -> alerts (>=)
mkplan team
queued_count 40
in_flight 0
queued_page $(live_rows 30 900)
expect "median == stall threshold -> UNDER_ASSIGNED" 1 "UNDER_ASSIGNED:"

# 17. Malformed created_at on a queued run -> parse failure -> UNKNOWN rc2,
#     never a silent 0-age HEALTHY.
mkplan team
queued_count 40
in_flight 0
queued_page '{"id":600,"created_at":"not-a-timestamp","status":"queued"}'
expect "malformed created_at -> UNKNOWN rc2" 2 "UNKNOWN:"

# 18. Multi-page jobs payload: gh --paginate concatenates page objects. The
#     probe slurps them (jq -s) — under the old --jq-per-page shape this same
#     payload yielded two lines and crashed the IN_FLIGHT arithmetic with
#     exit 1, reading as a FALSE UNDER_ASSIGNED.
mkplan team
queued_count 40
inprogress 1
{
  rows=()
  for i in $(seq 15); do rows+=("$(infl x "$i")"); done
  printf '{"total_count":30,"jobs":[%s]}' "$(IFS=,; echo "${rows[*]}")"
  rows=()
  for i in $(seq 16 30); do rows+=("$(infl x "$i")"); done
  printf '{"total_count":30,"jobs":[%s]}' "$(IFS=,; echo "${rows[*]}")"
} > "$WORK/fix/jobs-700.json"
queued_page $(live_rows 30 1900)
expect "two-page jobs payload sums to 30 delivered -> SATURATED" 0 "SATURATED:"

# 19. In-progress list truncation: total_count exceeds the page -> UNKNOWN,
#     never an undercounted delivered that false-pages UNDER_ASSIGNED.
mkplan team
queued_count 0
printf '{"total_count":150,"workflow_runs":[%s]}\n' "$(run_row 700 "$(iso_ago 300)")" > "$WORK/fix/inprogress.json"
jobs_for 700 "$(infl x 1)"
expect "in-progress truncation -> UNKNOWN rc2" 2 "UNKNOWN:"

# 20. Non-numeric knob must fail UNKNOWN, not degrade the gate to a false
#     HEALTHY (an unbound QUEUE_DEPTH_ALERT makes the stall test error-false).
mkplan team
queued_count 40
in_flight 0
queued_page $(live_rows 30 1900)
PROBE_ENV="QUEUE_DEPTH_ALERT=abc" expect "non-numeric QUEUE_DEPTH_ALERT -> UNKNOWN rc2" 2 "UNKNOWN:"
PROBE_ENV="MIN_ASSIGN_PCT=abc"   expect "non-numeric MIN_ASSIGN_PCT -> UNKNOWN rc2" 2 "UNKNOWN:"
unset PROBE_ENV 2>/dev/null || true

# 21. --json emits a parseable metrics object (verdict is a field)
mkplan team
queued_count 0
in_flight 0
rc=0
run_probe --json >/dev/null || rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$(cat "$WORK/out")" | jq -e '.verdict == "HEALTHY" and .queued_runs == 0 and .zombie_runs == 0' >/dev/null 2>&1; then
  pass "--json emits parseable verdict"
else
  fail "--json output not parseable/wrong (rc=$rc; $(tail -2 "$WORK/out"))"
fi

# 22. --paginate on EVERY jobs call — filter the call log to jobs endpoints and
#     assert each line carries the flag (a dropped flag truncates >30-job runs;
#     a presence-grep alone can't catch one call missing it).
mkplan team
queued_count 0
inprogress 2
jobs_for 700 "$(infl x 1)"
jobs_for 701 "$(infl x 1)"
run_probe >/dev/null 2>&1 || true
jobs_calls="$(grep -c '/jobs' "$WORK/fix/calls.log" || true)"
jobs_calls_paginated="$(grep '/jobs' "$WORK/fix/calls.log" | grep -c -- '--paginate' || true)"
if [ "$jobs_calls" -ge 2 ] && [ "$jobs_calls" -eq "$jobs_calls_paginated" ]; then
  pass "--paginate on every jobs call ($jobs_calls_paginated/$jobs_calls)"
else
  fail "--paginate missing on some jobs calls ($jobs_calls_paginated/$jobs_calls): $(cat "$WORK/fix/calls.log")"
fi

# 23. Missing gh binary -> UNKNOWN rc2
mkplan team; queued_count 0; in_flight 0
rc=0
out="$(env -i PATH="/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" REPO=jikig-ai/soleur bash "$PROBE" 2>&1)" || rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'UNKNOWN'; then
  pass "missing gh -> UNKNOWN rc2"
else
  fail "missing gh (rc=$rc; out: $out)"
fi

# 24. Queued+in_progress mixed jobs: only in_progress count toward delivered
mkplan team
queued_count 40
inprogress 1
jobs_for 700 "$(infl x 1)" \
             "$(job_row q1 queued "$(iso_ago 200)")" "$(job_row q2 queued "$(iso_ago 200)")"
queued_page $(live_rows 30 1900)
expect "queued jobs inside an in-progress run do not count as delivered" 1 "UNDER_ASSIGNED:"

# Anti-vacuity floor: deleting every assertion must not exit 0. Reports
# directly and exits (ADR-193): a floor routed through fail() is disarmed
# by the same neutered machinery it exists to catch.
total=$((passes + fails))
if [ "$total" -lt 24 ]; then
  echo "[FATAL] assertion floor: only $total assertions ran, want >=24" >&2
  exit 1
fi

echo
echo "actions-queue-health guard: $passes passed, $fails failed"
[ "$fails" -eq 0 ]
