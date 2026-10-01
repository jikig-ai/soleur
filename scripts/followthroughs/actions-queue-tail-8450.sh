#!/usr/bin/env bash
# actions-queue-tail-8450.sh — post-Team-upgrade soak probe for #8450.
#
# Measures the thing the issue actually reports: how long DEPLOY-ARM jobs wait
# for a hosted runner. Metric is per-JOB `started_at - created_at` on the
# `resolve-target`/`migrate`/`deploy`/`live-verify` jobs of
# web-platform-release.yml runs whose event is `workflow_run` (every merge
# produces TWO runs — a `push`-arm run carrying only `release`, which would
# contaminate the sample). Run-level `created_at → run_started_at` is vacuous
# (equal on every sampled run). For a `needs:`-gated job, `created_at` is
# stamped at job instantiation — post-`needs:` — so the delta measures
# runner-acquisition wait PLUS any concurrency-lock wait the job sat in
# between instantiation and start (e.g. the web-1-swap lock). That
# contamination is fail-safe (it can delay a PASS, never fabricate one) but
# means a PASS reads as "post-upgrade deploy latency", not strictly "runner
# pool wait". Pinned empirically in
# knowledge-base/project/specs/feat-8450-ci-concurrency/measurements.md.
#
# Caveat recorded for the sweeper's auto-close comment: the GitHub API cannot
# report how deep the org queue was at each sampled run's `created_at`, so a
# PASS asserts "the deploy tail measured in the sampled window", not "the tail
# is gone under load". The probe logs the CURRENT queued-run depth alongside
# the verdict for context; the manual D.4 re-evaluation on #8450 remains the
# load-conditioned check.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              (>=5 in-window runs each with >=1 core deploy job
#                          (migrate/deploy/live-verify) measured, AND pooled
#                          p95 wait < 15 min; sweeper closes #8450)
#   1 = FAIL              (p95 >= 15 min; sweeper comments, leaves open)
#   2 = NOT YET           (explicit non-team plan visible; clock
#                          unset/unparseable; <5 usable in-window runs;
#                          GH_TOKEN/gh/jq missing. NOT exit 0: the plan's
#                          original SKIP-DECLARED-exit-0 would auto-close
#                          #8450 on an unmet precondition — a false
#                          resolution)
#   3 = CANNOT ESTABLISH  (gh API failures; sweeper comments, retries)
#   78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# `plan.name` precondition note: repo-scoped tokens (the sweeper forwards
# `secrets.GITHUB_TOKEN` as GH_TOKEN) cannot read `orgs/{org}.plan` — that
# field is restricted to org-owner tokens or a GitHub App holding the
# Organization plan permission. An unreadable plan is therefore NOT a
# precondition failure: the `earliest=`/`UPGRADE_NOT_BEFORE` cutoff is only
# stamped after the operator bootstrap independently verifies plan==team, and
# a still-free pool would fail the p95 budget on its own evidence. An
# explicitly readable non-team value still gates (SKIP-DECLARED -> NOT YET).
#
# Required env: GH_TOKEN (needs actions:read — the sweeper job gained that
# scope under #8450; an explicit permissions block defaults unlisted scopes
# to none). Clock: UPGRADE_NOT_BEFORE (ISO-8601) overrides the forwarded
# SOLEUR_FT_EARLIEST; one of them must be set — `plan.name` reports the
# CURRENT tier, not when it changed, so a pre-upgrade sample is stale data.
#
# RETIREMENT: one-shot soak probe. When #8450 closes, delete this file, its
# .test.sh, the `run_suite` line in scripts/test-all.sh, and the
# actions-queue-tail-8450 references in bootstrap.sh, measurements.md, and the
# preflight-discoverability baseline comment. Revert the sweeper's
# `actions: read` permission only if no other followthrough probe needs it.
set -uo pipefail

# XTRACE REFUSAL (#7797). This probe binds GH_TOKEN, and shell tracing echoes a
# command AFTER expansion -- so under `bash -x` the credential reaches the
# transcript at the moment it is bound, before it is used for anything. Refuse
# to run traced while a credential is present, rather than trusting the caller
# not to trace.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
WORKFLOW="web-platform-release.yml"
# Deploy ARM, not the push arm: each merge produces both, and the push-arm run
# carries only `release` — sampling it would read the wrong half (~50% of runs).
EVENT_ARM="workflow_run"
# Sampled deploy-arm jobs (workflow_run arm). resolve-target is the FIRST job
# of the arm — its created_at ~= run creation, so its delta also captures
# head-of-pipeline queue wait, which dominates under a saturated pool. The
# other arm jobs (verify-migrations, verify-doppler-secrets, notify-gated,
# release-outcome) are excluded: verify-* waits are subsumed by the deploy
# job's own post-needs instantiation wait, and the tail jobs add no signal.
# Fragility, recorded: the jobs API returns display names — adding a `name:`
# display override to a sampled job drops it from the sample (safe direction:
# INSUFFICIENT forever, never a fabricated PASS). Guard 2 pins this literal
# against the workflow's job keys.
DEPLOY_ARM_JOBS="resolve-target migrate deploy live-verify"
# A run counts toward MIN_RUNS only when at least one CORE deploy job
# produced a wait — on docs-only pushes the deploy chain is if:-skipped and
# only resolve-target ran, so resolve-target-only samples would otherwise
# satisfy MIN_RUNS without a single deploy job starting (review, #8472).
CORE_DEPLOY_JOBS="migrate deploy live-verify"
MIN_RUNS=5
P95_BUDGET_S=900

[ -n "${GH_TOKEN:-}" ] || { echo "NOT YET: GH_TOKEN not set (secrets= clause)" >&2; exit 2; }
command -v gh  >/dev/null || { echo "NOT YET: gh not on PATH" >&2; exit 2; }
command -v jq  >/dev/null || { echo "NOT YET: jq not on PATH" >&2; exit 2; }

# ISO-8601 -> epoch. GNU `date -d` first, BSD/macOS `date -j -f` fallback.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

CUTOFF="${UPGRADE_NOT_BEFORE:-${SOLEUR_FT_EARLIEST:-}}"
if [ -z "$CUTOFF" ]; then
  echo "NOT YET: no cutoff clock — UPGRADE_NOT_BEFORE/SOLEUR_FT_EARLIEST unset." >&2
  exit 2
fi
# `earliest=` is issue-body data — any member can edit it, and GNU `date -d`
# accepts natural-language single tokens (`now`, `today`, `@epoch`) that would
# silently widen the soak window toward a PASS. bootstrap.sh enforces exactly
# this regex at write time; the probe must not trust it at read (review #8472).
if [[ ! "$CUTOFF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
  echo "NOT YET: cutoff '$CUTOFF' is not canonical ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)." >&2
  exit 2
fi
CUTOFF_EPOCH="$(iso_epoch "$CUTOFF" || true)"
if [ -z "${CUTOFF_EPOCH:-}" ]; then
  echo "NOT YET: cutoff '$CUTOFF' is not a parseable ISO timestamp." >&2
  exit 2
fi
# Normalize to canonical ISO before the lexicographic compare below — a
# date-parseable but non-canonical cutoff ("yesterday", "+02:00" offsets)
# would silently misfilter against GitHub's Z-suffixed timestamps.
CUTOFF="$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -r "$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

# Precondition: the probe only means something on the 60-job pool. See the
# header note — an UNREADABLE plan (repo-scoped token) proceeds; only an
# explicitly readable non-team value gates. Acceptable asymmetry for a
# one-shot probe: a future non-team tier (e.g. enterprise) would loop NOT YET
# forever — fail-safe, surfaced to the operator on every sweep.
PLAN="$(gh api orgs/jikig-ai --jq '.plan.name // "unreadable"' 2>/dev/null)" || {
  echo "CANNOT ESTABLISH: gh api orgs/jikig-ai failed" >&2; exit 3; }
case "$PLAN" in
  team) ;;
  unreadable)
    echo "NOTE: org plan not visible to this credential (repo-scoped tokens cannot read .plan) — proceeding on the post-upgrade cutoff + measured wait." ;;
  *)
    echo "SKIP-DECLARED: org plan is '$PLAN', not 'team' — AC-TEAM unmet; soaking is meaningless on the 20-job pool." >&2
    exit 2 ;;
esac

RUNS_JSON="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?event=$EVENT_ARM&per_page=50" 2>/dev/null)" || {
  echo "CANNOT ESTABLISH: gh api workflow runs failed" >&2; exit 3; }

# Usable in-window runs: event=workflow_run (already server-filtered, but the
# filter is re-asserted client-side so a fixture/stubbed page can't smuggle a
# push-arm row), created_at strictly after the cutoff, and COMPLETED — an
# in_progress run whose early jobs finished while its deploy job still queues
# would contribute only its short waits (downward-biased partial sample).
IDS="$(printf '%s' "$RUNS_JSON" | jq -r --arg cut "$CUTOFF" '
  .workflow_runs // []
  | map(select(.event == "workflow_run"
        and .created_at > $cut
        and .status == "completed"))
  | .[].id' 2>/dev/null)" || { echo "CANNOT ESTABLISH: could not parse runs payload" >&2; exit 3; }

N_RUNS=0
WAITS=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  JOBS="$(gh api --paginate "repos/$REPO/actions/runs/$id/jobs" 2>/dev/null)" || {
    echo "CANNOT ESTABLISH: gh api jobs for run $id failed" >&2; exit 3; }
  # Sample only jobs that genuinely ran: queued jobs pre-populate
  # started_at == created_at (wait=0 fake sample), never-started jobs have
  # null started_at, and skipped/cancelled jobs also report
  # started_at == created_at — each contributing a fake 0s wait that dilutes
  # the pooled p95 toward 0 (review, #8472). Negative deltas (clock skew
  # between created_at and started_at stamps) are dropped, not averaged in.
  W="$(printf '%s' "$JOBS" | jq -r --arg names "$DEPLOY_ARM_JOBS" '
    [.jobs[] | select(.name as $n | ($names | split(" ") | index($n)) != null)
     | select(.status != "queued")
     | select(.status == "in_progress" or .conclusion == "success")
     | select(.started_at != null and .created_at != null)
     | ((.started_at | fromdateiso8601) - (.created_at | fromdateiso8601)) as $w
     | select($w >= 0) | "\(.name)\t\($w)"]
    | .[]' 2>/dev/null)" || {
    echo "CANNOT ESTABLISH: could not parse jobs payload for run $id" >&2; exit 3; }
  if [ -n "$W" ]; then
    core_hit=0
    while IFS=$'\t' read -r jname jwait; do
      [ -n "$jwait" ] || continue
      WAITS="${WAITS}${jwait}"$'\n'
      case " $CORE_DEPLOY_JOBS " in *" $jname "*) core_hit=1 ;; esac
    done <<< "$W"
    [ "$core_hit" -eq 1 ] && N_RUNS=$((N_RUNS + 1))
  fi
done <<EOF
$IDS
EOF

# Live queue depth for context — the API cannot report historical depth at
# each sample, so the current depth is the only load signal available.
QUEUED_NOW="$(gh api "repos/$REPO/actions/runs?status=queued&per_page=1" --jq '.total_count // 0' 2>/dev/null || echo "unknown")"

if [ "$N_RUNS" -lt "$MIN_RUNS" ]; then
  echo "INSUFFICIENT: $N_RUNS post-$CUTOFF runs carried a core deploy-arm job wait (need >=$MIN_RUNS). Soak continues next sweep. (queued now: $QUEUED_NOW)" >&2
  exit 2
fi

# p95 via the lower-quantile convention i=floor((N-1)*0.95)+1: at the ~15-sample
# soak floor this picks the SECOND-largest wait — one outlier is tolerated.
P95="$(printf '%s' "$WAITS" | sort -n | awk -v p=0.95 '{a[NR]=$1} END {i=int((NR-1)*p)+1; print a[i]}')"
if [ -z "${P95:-}" ]; then
  echo "FAIL: $N_RUNS in-window runs but no measurable deploy-arm job waits." >&2
  exit 1
fi

CAVEAT="(queued now: $QUEUED_NOW; sample-window load not measurable via API — PASS asserts the measured window, D.4 re-eval is the load-conditioned check)"
if [ "$P95" -lt "$P95_BUDGET_S" ]; then
  echo "PASS: deploy-arm queue wait p95=${P95}s < ${P95_BUDGET_S}s across $N_RUNS post-upgrade workflow_run runs (cutoff $CUTOFF). $CAVEAT"
  exit 0
fi
echo "FAIL: deploy-arm queue wait p95=${P95}s >= ${P95_BUDGET_S}s across $N_RUNS post-upgrade runs — the 60-job ceiling did not dissolve the tail. $CAVEAT" >&2
exit 1
