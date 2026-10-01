#!/usr/bin/env bash
# Guard 2 — actions-queue-tail-8450.sh cannot pass on stale, empty, or
# contaminated samples (#8450 soak probe).
#
# PROPERTY. The probe exits 0 only when ALL of:
#   - the org plan precondition is met: plan.name == team, OR the plan field is
#     UNREADABLE to the credential (repo-scoped tokens cannot see .plan — the
#     post-upgrade cutoff + measured wait carry the verification in that arm);
#     an explicitly readable non-team value still gates (SKIP-DECLARED);
#   - >=5 COMPLETED deploy-arm runs of web-platform-release.yml
#     (event=workflow_run) postdate the UPGRADE_NOT_BEFORE / SOLEUR_FT_EARLIEST
#     cutoff;
#   - p95 of the per-JOB (started_at - created_at) waits on the deploy-arm
#     jobs (resolve-target, migrate, deploy, live-verify) is < 900 s.
# Every other shape exits non-zero: empty window, stale-only samples,
# push-arm contamination, breached p95, unparseable/missing clock, gh failure,
# queued-only jobs (pre-populated started_at==created_at is a fake wait=0),
# in_progress runs (partial samples are downward-biased).
#
# SEMANTICS NOTE (vs the plan's written matrix): the plan said SKIP-DECLARED
# exits 0. Under sweep-followthroughs.sh, exit 0 AUTO-CLOSES the tracked
# issue — a false resolution of #8450 if the org plan silently stayed
# `free`. The correct sweeper verdict for a precondition-not-yet-met is
# exit 2 ("NOT YET": leaves open, retries next sweep). The probe still prints
# the SKIP-DECLARED marker in its output so the vocabulary survives; only the
# code changed. Recorded in measurements.md.
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH that answers ONLY
# the argv the probe may legitimately issue:
#   gh api orgs/jikig-ai                                  -> $FIXTURE_DIR/plan.json
#   gh api repos/.../workflows/web-platform-release.yml/runs?event=workflow_run... -> runs.json
#   gh api [--paginate] repos/.../actions/runs/<id>/jobs  -> jobs-<id>.json
#   gh api repos/.../actions/runs?status=queued...        -> queued.json
# Flags anywhere in argv are ignored except --jq, which the stub honors by
# piping the fixture through real jq. Every invocation is appended to
# $FIXTURE_DIR/calls.log (truncated per run_probe), and any other argv exits
# 64 after logging STUB-UNEXPECTED there — the probe's own `2>/dev/null`
# would swallow stub stderr, so the call log is what keeps a wandering probe
# loud, not silently vacuous. The log is also how flags are policed: the
# `--paginate` assertion below greps it, because a dropped --paginate leaves
# the endpoint string (and therefore the fixture routing) unchanged.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every timestamp
# and run id is fabricated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/actions-queue-tail-8450.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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
assert_fixture_dir "$WORK"

command -v jq >/dev/null || { echo "FATAL: jq required for the fixture stub" >&2; exit 1; }

CUTOFF="2026-09-22T00:00:00Z"   # fabricated upgrade-verification timestamp

# ── fixture builders ────────────────────────────────────────────────────────
# A runs.json page: id + created_at + event + status per run.
run_row() { # <id> <created_at> <event> <status>
  printf '{"id":%s,"created_at":"%s","event":"%s","status":"%s","conclusion":"success"}' "$1" "$2" "$3" "$4"
}

# One job row. wait=- means started_at null (never started); wait=0 with a
# queued status models the API's started_at==created_at pre-population.
# conclusion defaults to "success"; pass "skipped"/"cancelled"/null to model
# jobs that report started_at==created_at without having run.
job_row() { # <name> <status> <wait_seconds|-> [conclusion]
  local name="$1" status="$2" w="$3" concl="${4:-success}"
  local ca="2026-09-22T01:00:00Z"
  local cj; cj="$(jq -nc --arg c "$concl" 'if $c == "null" then null else $c end')"
  if [ "$w" = "-" ]; then
    jq -nc --arg n "$name" --arg st "$status" --arg ca "$ca" --argjson c "$cj" \
      '{name:$n,status:$st,conclusion:$c,created_at:$ca,started_at:null}'
  else
    local start
    start="$(jq -nr --argjson w "$w" '(1790038800 + $w) | strftime("%Y-%m-%dT%H:%M:%SZ")')"
    jq -nc --arg n "$name" --arg st "$status" --arg ca "$ca" --arg s "$start" --argjson c "$cj" \
      '{name:$n,status:$st,conclusion:$c,created_at:$ca,started_at:$s,completed_at:$s}'
  fi
}

write_jobs() { # <file> <job_row>...
  local file="$1"; shift
  assert_fixture_dir "$file"
  local rows="" first=1
  for r in "$@"; do
    if [ "$first" -eq 1 ]; then rows="$r"; first=0; else rows="$rows,$r"; fi
  done
  printf '{"total_count":%d,"jobs":[%s]}\n' "$#" "$rows" > "$file"
}

# A jobs-<id>.json of "migrate" jobs with controlled waits (seconds).
jobs_fixture() { # <file> <wait_seconds>...
  local file="$1"; shift
  local jrows=()
  local w
  for w in "$@"; do jrows+=("$(job_row migrate completed "$w")"); done
  write_jobs "$file" "${jrows[@]}"
}

# write_runs <file> <run_row>...
write_runs() {
  local file="$1"; shift
  assert_fixture_dir "$file"
  local rows="" first=1
  for r in "$@"; do
    if [ "$first" -eq 1 ]; then rows="$r"; first=0; else rows="$rows,$r"; fi
  done
  printf '{"total_count":%d,"workflow_runs":[%s]}\n' "$#" "$rows" > "$file"
}

mkplan() { printf '{"plan":{"name":"%s"}}\n' "$1" > "$WORK/fix/plan.json"; }

# run_probe — probe env: GH_TOKEN dummy, cutoff set via UPGRADE_NOT_BEFORE.
run_probe() {
  local out rc
  : > "$WORK/fix/calls.log"
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake \
        FIXTURE_DIR="$WORK/fix" UPGRADE_NOT_BEFORE="$CUTOFF" bash "$PROBE" 2>&1)"
  rc=$?
  printf '%s' "$out" > "$WORK/out"
  return $rc
}

expect() { # <desc> <want_rc> <needle-in-output-or-"">
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
    fail "$desc (rc ok but output missing '$needle')"
    return
  fi
  pass "$desc"
}

mkdir -p "$WORK/bin" "$WORK/fix"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
FIX="${FIXTURE_DIR:?}"
# Log every invocation: the probe pipes our stderr to /dev/null, so this file
# is the only place STUB-UNEXPECTED can be observed — and it records the full
# argv so callers can police flags the router ignores (e.g. --paginate).
printf 'gh %s\n' "$*" >> "$FIX/calls.log"
[[ "${1:-}" == "api" ]] || { printf 'STUB-UNEXPECTED: gh %s\n' "$*" >> "$FIX/calls.log"; exit 64; }
shift
# First non-flag arg is the endpoint; flags are ignored except --jq, which the
# stub honors by piping the fixture through real jq.
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
  orgs/jikig-ai) out < "$FIX/plan.json" ;;
  repos/jikig-ai/soleur/actions/workflows/web-platform-release.yml/runs?event=workflow_run*)
    out < "$FIX/runs.json" ;;
  repos/jikig-ai/soleur/actions/runs?status=queued*)
    out < "$FIX/queued.json" ;;
  repos/jikig-ai/soleur/actions/runs/*/jobs)
    id="$(printf '%s' "$ep" | sed -n 's|.*/runs/\([0-9]*\)/jobs|\1|p')"
    f="$FIX/jobs-$id.json"
    [[ -f "$f" ]] || { printf 'STUB-UNEXPECTED: no jobs fixture for run %s\n' "$id" >> "$FIX/calls.log"; exit 64; }
    out < "$f" ;;
  *) printf 'STUB-UNEXPECTED: gh api %s\n' "$ep" >> "$FIX/calls.log"; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export FIXTURE_DIR="$WORK/fix"
printf '{"total_count":7,"workflow_runs":[]}\n' > "$WORK/fix/queued.json"

echo "── Guard 2: precondition + sampling matrix"

# 0. Artifact hygiene: the sweeper refuses non-executable probes with a
#    stderr-only log and return 0 (sweep-followthroughs.sh:507-510) — a 644
#    probe is silently quiet forever.
if [ -x "$PROBE" ]; then pass "probe is executable"; else fail "probe is not executable ($PROBE)"; fi

# 1. Non-team plan -> SKIP-DECLARED, exit 2 (NOT YET — never close #8450 on it).
mkplan free
write_runs "$WORK/fix/runs.json"
expect "plan=free is SKIP-DECLARED (exit 2, not a close)" 2 "SKIP-DECLARED"

# 2. Plan field UNREADABLE (repo-scoped token cannot see .plan) -> proceed to
#    sampling; NOT a precondition refusal. Empty window still INSUFFICIENT.
printf '{}\n' > "$WORK/fix/plan.json"
write_runs "$WORK/fix/runs.json"
expect "unreadable plan proceeds (no SKIP-DECLARED)" 2 "plan not visible"
mkplan team
expect "team plan + empty run window cannot pass" 2 "INSUFFICIENT"

# 3. gh api failure -> exit 3 (CANNOT ESTABLISH — sweeper retries; never a
#    close, never a false FAIL).
rm -f "$WORK/fix/plan.json"
expect "gh api failure is CANNOT ESTABLISH (exit 3)" 3 ""
mkplan team

# 4. Team + runs ALL predating the cutoff -> non-zero (stale window rejected).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 1001 2026-09-20T10:00:00Z workflow_run completed)" \
  "$(run_row 1002 2026-09-20T11:00:00Z workflow_run completed)" \
  "$(run_row 1003 2026-09-20T12:00:00Z workflow_run completed)" \
  "$(run_row 1004 2026-09-20T13:00:00Z workflow_run completed)" \
  "$(run_row 1005 2026-09-20T14:00:00Z workflow_run completed)"
expect "pre-upgrade samples are stale, not evidence" 2 ""

# 5. Team + 5 fresh workflow_run runs, p95 wait < 15 min -> PASS exit 0.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 60; done
expect "passing dataset (fresh, p95<15min) exits 0" 0 "PASS:"

# 5b. The jobs call MUST be --paginate'd: an unpaginated endpoint returns the
#     same fixture either way (invisible to the router) but in production
#     silently under-samples >30-job runs — a downward-biased p95 that can
#     fabricate a PASS. Assert against the stub's argv log.
if grep -qE 'runs/[0-9]+/jobs' "$WORK/fix/calls.log" \
   && ! grep -E 'runs/[0-9]+/jobs' "$WORK/fix/calls.log" | grep -qv -- '--paginate'; then
  pass "every jobs call carries --paginate"
else
  fail "a jobs call was issued without --paginate: $(grep -E 'runs/[0-9]+/jobs' "$WORK/fix/calls.log" | grep -v -- '--paginate' | head -1)"
fi
# Same shape for the runs call: the deploy-arm filter is part of the endpoint
# and must not silently regress to all-events sampling.
if grep -q 'workflows/web-platform-release.yml/runs?event=workflow_run' "$WORK/fix/calls.log"; then
  pass "runs call carries the event=workflow_run filter"
else
  fail "runs call lost the event=workflow_run filter: $(head -3 "$WORK/fix/calls.log")"
fi

# 6. Named-job coverage: the sampled set is resolve-target/migrate/deploy/
#    live-verify — fixtures naming the non-migrate members must count.
for id in 2001 2002 2003 2004 2005; do
  write_jobs "$WORK/fix/jobs-$id.json" \
    "$(job_row resolve-target completed 45)" \
    "$(job_row deploy completed 90)" \
    "$(job_row live-verify completed 20)" \
    "$(job_row some-other-job completed 5000)"
done
expect "resolve-target/deploy/live-verify jobs are sampled" 0 "PASS:"

# 6b. Each sampled name individually: a fixture where ONE named job is the
#     sole row kills a dropped entry in DEPLOY_ARM_JOBS for every core name.
#     (resolve-target alone is NOT a counter — see case 7b.)
for solo in migrate deploy live-verify; do
  for id in 2001 2002 2003 2004 2005; do
    write_jobs "$WORK/fix/jobs-$id.json" "$(job_row "$solo" completed 40)"
  done
  expect "a lone $solo row still counts the run" 0 "PASS:"
done

# 7. Queued jobs carry started_at==created_at (wait=0 pre-population) — they
#    must not count. Rows cover both shapes: the realistic conclusion=null AND
#    an impossible queued+success pair, so the status guard itself is pinned.
for id in 2001 2002 2003 2004 2005; do
  write_jobs "$WORK/fix/jobs-$id.json" \
    "$(job_row migrate queued 0 null)" "$(job_row deploy queued 0)"
done
expect "queued jobs are not measurable samples" 2 "INSUFFICIENT"

# 7b. Skipped/cancelled jobs report the same started_at==created_at shape with
#     status=completed — conclusion is the discriminator. And a run whose ONLY
#     measured job is resolve-target (deploy chain if:-skipped, the docs-push
#     shape) must not count toward MIN_RUNS at all.
for id in 2001 2002 2003 2004 2005; do
  write_jobs "$WORK/fix/jobs-$id.json" \
    "$(job_row resolve-target completed 0)" \
    "$(job_row migrate completed 0 skipped)" \
    "$(job_row deploy completed 0 skipped)" \
    "$(job_row live-verify completed 0 cancelled)"
done
expect "skipped/cancelled jobs are not measurable samples" 2 "INSUFFICIENT"
for id in 2001 2002 2003 2004 2005; do
  write_jobs "$WORK/fix/jobs-$id.json" "$(job_row resolve-target completed 30)"
done
expect "resolve-target-only runs do not count (deploy arm never ran)" 2 "INSUFFICIENT"

# 8. in_progress runs are excluded (partial samples are downward-biased).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run in_progress)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run in_progress)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run in_progress)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run in_progress)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run in_progress)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 60; done
expect "in_progress runs are not sampled" 2 "INSUFFICIENT"

# 9. Team + 5 fresh completed runs but p95 wait >= 15 min -> FAIL exit 1.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 1200; done
expect "p95>=15min breaches -> FAIL" 1 "FAIL:"

# 9b. Boundary fixtures on the three numbers that carry the verdict:
#     MIN_RUNS-1 = 4 runs -> INSUFFICIENT (pins the >=5 edge).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 4001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 4002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 4003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 4004 2026-09-22T04:00:00Z workflow_run completed)"
for id in 4001 4002 4003 4004; do jobs_fixture "$WORK/fix/jobs-$id.json" 30; done
expect "exactly 4 usable runs is INSUFFICIENT (MIN_RUNS boundary)" 2 "INSUFFICIENT"
#     created_at == cutoff is stale (strict-greater compare, not >=).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 5001 2026-09-22T00:00:00Z workflow_run completed)" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)"
jobs_fixture "$WORK/fix/jobs-5001.json" 10
for id in 2001 2002 2003 2004; do jobs_fixture "$WORK/fix/jobs-$id.json" 30; done
expect "a run stamped exactly at the cutoff is stale" 2 "INSUFFICIENT"
#     p95 == 900 exactly breaches (the predicate is strict <).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 900 900; done
expect "p95 exactly at the 900s budget is FAIL (strict <)" 1 "FAIL:"

# 10. Push-arm contamination: 'push'-event rows must be excluded by the probe's
#     own event=workflow_run filter (simulates the unfiltered reality: the
#     stubbed page is what the API would return WITHOUT the server filter).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 3001 2026-09-22T01:00:00Z push completed)" \
  "$(run_row 3002 2026-09-22T02:00:00Z push completed)" \
  "$(run_row 3003 2026-09-22T03:00:00Z push completed)" \
  "$(run_row 3004 2026-09-22T04:00:00Z push completed)" \
  "$(run_row 3005 2026-09-22T05:00:00Z push completed)"
expect "push-arm runs are not deploy-arm evidence" 2 "INSUFFICIENT"

# 11. Fewer than 5 usable runs -> INSUFFICIENT, non-zero.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 4001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 4002 2026-09-22T02:00:00Z workflow_run completed)"
jobs_fixture "$WORK/fix/jobs-4001.json" 10
jobs_fixture "$WORK/fix/jobs-4002.json" 10
expect "<5 usable runs is INSUFFICIENT" 2 "INSUFFICIENT"

# 11b. in_progress JOBS with a real wait count (conclusion is null mid-flight);
#      an all-in_progress-job sample is legitimate evidence of a live queue.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do
  write_jobs "$WORK/fix/jobs-$id.json" "$(job_row deploy in_progress 45 null)"
done
expect "in_progress jobs with a real wait are measurable" 0 "PASS:"

# 12. SOLEUR_FT_EARLIEST is the clock the sweeper actually forwards — it must
#     reach the cutoff path exactly like UPGRADE_NOT_BEFORE.
mkplan team
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 60; done
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake \
      FIXTURE_DIR="$WORK/fix" SOLEUR_FT_EARLIEST="$CUTOFF" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'PASS'; then
  pass "SOLEUR_FT_EARLIEST clock feeds the cutoff"
else
  fail "SOLEUR_FT_EARLIEST clock (rc=$rc; out: $(printf '%s' "$out" | tail -3))"
fi

# 13. Missing clock: no UPGRADE_NOT_BEFORE / SOLEUR_FT_EARLIEST -> NOT YET
#     (exit 2 + marker — a crash must not satisfy "non-zero").
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'NOT YET'; then
  pass "missing clock is NOT YET (exit 2)"
else
  fail "missing clock (want rc=2+NOT YET; got rc=$rc; out: $(printf '%s' "$out" | tail -3))"
fi

# 14. Unparseable clock -> NOT YET (exit 2), never a crash into sampling.
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" UPGRADE_NOT_BEFORE='not a date' bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'NOT YET'; then
  pass "unparseable clock is NOT YET (exit 2)"
else
  fail "unparseable clock (rc=$rc; out: $(printf '%s' "$out" | tail -3))"
fi

# 14b. Non-canonical clock: GNU `date -d` accepts natural-language tokens
#      (`now`, `today`, `@epoch`) — `earliest=` is issue-body data and must be
#      canonical ISO-8601 Z at read time, not merely date-parseable.
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" UPGRADE_NOT_BEFORE='now' bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'NOT YET'; then
  pass "natural-language clock is NOT YET (exit 2)"
else
  fail "natural-language clock (want rc=2+NOT YET; got rc=$rc)"
fi

# 15. Xtrace refusal: GH_TOKEN bound under `bash -x` -> exit 78 (#7797).
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" bash -x "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 78 ]; then
  pass "xtrace with live credential refused (exit 78)"
else
  fail "xtrace refusal (want rc=78 got rc=$rc)"
fi

echo "── Guard 2: wiring + parity pins"

# The sampled job set is a replicated literal — a rename or typo in 3 of the
# 4 names ships green while silently shrinking the sample (review #8472).
grep -qF 'DEPLOY_ARM_JOBS="resolve-target migrate deploy live-verify"' "$PROBE" \
  && pass "DEPLOY_ARM_JOBS literal is the pinned set" \
  || fail "DEPLOY_ARM_JOBS literal drifted from the pinned set"

# Parity against the workflow's own job keys: every sampled name must exist
# as a `  <name>:` job key in web-platform-release.yml, or the probe samples
# a job that cannot exist and quietly under-counts forever.
RELEASE_YML="$(cd "$HERE/../.." && pwd)/.github/workflows/web-platform-release.yml"
parity_missing=""
for jn in resolve-target migrate deploy live-verify; do
  grep -qE "^  ${jn}:\s*$" "$RELEASE_YML" || parity_missing="$parity_missing $jn"
done
if [ -z "$parity_missing" ]; then
  pass "DEPLOY_ARM_JOBS all exist as job keys in web-platform-release.yml"
else
  fail "sampled job(s) missing from web-platform-release.yml:$parity_missing"
fi

# Anti-vacuity floor: deleting every assertion must not exit 0. Reports
# directly and exits (ADR-193): a floor routed through fail() is disarmed
# by the same neutered machinery it exists to catch.
total=$((passes + fails))
if [ "$total" -lt 25 ]; then
  echo "[FATAL] assertion floor: only $total assertions ran, want >=25" >&2
  exit 1
fi

echo
echo "Guard 2: $passes passed, $fails failed"
[ "$fails" -eq 0 ]
