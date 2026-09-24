#!/usr/bin/env bash
# ci-leg-durations-8006.sh — post-carve-out soak probe for #8006.
#
# Measures the thing the issue actually reports: the wall-clock duration of
# the `test-scripts*` legs on main-branch CI runs after the heavy-suite
# carve-out (scripts/test-all.sh TEST_GROUP=scripts-heavy + the
# test-scripts-heavy matrix job). Metric is per-JOB
# `completed_at - started_at` on every leg whose display name matches
# `test-scripts (<k>/<K>)` or `test-scripts-heavy (<k>/<K>)` in completed
# `push`-arm runs of ci.yml on main. The run-level duration is the wrong
# quantity (the aggregator serializes behind all legs); leg-level is what
# the #8006 tail is made of.
#
# A run is QUALIFYING only when all 9 expected legs are present, each with
# conclusion=success and non-null started/completed timestamps:
#   test-scripts (1/6..6/6) + test-scripts-heavy (1/3..3/3)
# (light K went 5 -> 6 in phase 2; the qualifying shape moved with it.)
# A pre-carve-out run (no heavy legs), a run with a skipped leg (job exists
# but never started — under fail-closed the aggregator would already be red,
# but a skipped leg is unmeasurable either way), or a run with a failed leg
# contributes nothing to the sample. That asymmetry is fail-safe: it delays
# a PASS, never fabricates one.
#
# Caveat recorded for the sweeper's auto-close comment: the 15-minute budget
# is the #8006 acceptance bound on a QUIET pool — leg duration includes
# runner-acquisition wait (started_at is job start, not container boot; the
# queue term lands between job created_at and started_at, which this probe
# does NOT measure). A PASS reads as "post-carve-out green-path leg tail",
# not "the tail is bounded under contention" — the contention ceiling stays
# tracked by #8163.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              (>=3 qualifying post-cutoff runs, AND every leg in
#                          every qualifying run < 900 s; sweeper closes #8006)
#   1 = FAIL              (a qualifying leg breached the budget; sweeper
#                          comments, leaves open)
#   2 = NOT YET           (<3 qualifying runs; cutoff unset/unparseable;
#                          GH_TOKEN/gh/jq missing. NOT exit 0: an unmet
#                          precondition must not auto-close #8006)
#   3 = CANNOT ESTABLISH  (gh API failures; sweeper comments, retries)
#   78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# Required env: GH_TOKEN (needs actions:read — the sweeper forwards the
# repo's GITHUB_TOKEN under `secrets=GH_TOKEN`; the sweeper job already has
# actions:read for #8450's probe). Clock: SOLEUR_FT_EARLIEST (forwarded from
# the directive's `earliest=`) — required; runs must postdate it because
# pre-merge runs predate the carve-out and are stale data, not a small sample.
#
# RETIREMENT: one-shot soak probe. When #8006 closes, delete this file, its
# .test.sh, and the `run_suite` line in scripts/test-all.sh.
set -uo pipefail

# XTRACE REFUSAL (#7797). This probe binds GH_TOKEN, and shell tracing echoes
# a command AFTER expansion -- under `bash -x` the credential reaches the
# transcript at the moment it is bound. Refuse to run traced while a
# credential is present.
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
WORKFLOW="ci.yml"
MIN_RUNS=3
LEG_BUDGET_S=900   # #8006's <15-minute acceptance bound, per-leg

[ -n "${GH_TOKEN:-}" ] || { echo "NOT YET: GH_TOKEN not set (secrets= clause)" >&2; exit 2; }
command -v gh  >/dev/null || { echo "NOT YET: gh not on PATH" >&2; exit 2; }
command -v jq  >/dev/null || { echo "NOT YET: jq not on PATH" >&2; exit 2; }

# ISO-8601 -> epoch. GNU `date -d` first, BSD/macOS `date -j -f` fallback.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}

CUTOFF="${SOLEUR_FT_EARLIEST:-}"
if [ -z "$CUTOFF" ]; then
  echo "NOT YET: no cutoff clock — SOLEUR_FT_EARLIEST unset." >&2
  exit 2
fi
# `earliest=` is issue-body data — any member can edit it, and GNU `date -d`
# accepts natural-language single tokens (`now`, `today`, `@epoch`) that
# would silently widen the sample window toward stale pre-merge runs. The
# probe must not trust it at read.
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

RUNS_JSON="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?event=push&branch=main&status=completed&per_page=50" 2>/dev/null)" || {
  echo "CANNOT ESTABLISH: gh api workflow runs failed" >&2; exit 3; }

# Candidate in-window runs: event=push (re-asserted client-side so a
# fixture/stubbed page can't smuggle a non-push row), branch=main, completed,
# created_at strictly after the cutoff. Newest first, capped at 20 — each run
# costs a jobs call, and a long-red stretch must not hang the sweeper.
IDS="$(printf '%s' "$RUNS_JSON" | jq -r --arg cut "$CUTOFF" '
  .workflow_runs // []
  | map(select(.event == "push"
               and .head_branch == "main"
               and .status == "completed"
               and .created_at > $cut))
  | sort_by(.created_at) | reverse | .[0:20] | .[].id')" || {
  echo "CANNOT ESTABLISH: runs list unparseable" >&2; exit 3; }

qualifying=0
breached=0
examined=0

for id in $IDS; do
  examined=$((examined + 1))
  JOBS="$(gh api --paginate "repos/$REPO/actions/runs/$id/jobs?per_page=100&filter=latest" 2>/dev/null)" || {
    echo "CANNOT ESTABLISH: gh api jobs for run $id failed" >&2; exit 3; }

  # Per-run leg table: name<TAB>duration_s<TAB>ok. A leg counts `ok` only when
  # conclusion==success AND both timestamps parse to epochs. --paginate on the
  # jobs endpoint yields concatenated {jobs:[...]} pages; slurp merges them.
  TABLE="$(printf '%s' "$JOBS" | jq -rs '
    [ .[] | .jobs // [] | .[]
      | select(.name | test("^test-scripts(|-heavy) \\([0-9]+/[0-9]+\\)$"))
      | { name,
          dur: (if .started_at != null and .completed_at != null
                then ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
                else null end),
          ok: (.conclusion == "success" and .started_at != null and .completed_at != null) }
    ]')" || { echo "CANNOT ESTABLISH: jobs list for run $id unparseable" >&2; exit 3; }

  nlight="$(jq '[.[] | select(.name | startswith("test-scripts ("))] | length' <<<"$TABLE")"
  nheavy="$(jq '[.[] | select(.name | startswith("test-scripts-heavy ("))] | length' <<<"$TABLE")"
  nok="$(jq '[.[] | select(.ok)] | length' <<<"$TABLE")"

  # All 9 legs present AND all green-and-measured. Anything else is
  # non-qualifying, not a sample point (pre-carve-out shape, skipped leg,
  # failed leg — each explained in the header).
  if [[ "$nlight" -ne 6 || "$nheavy" -ne 3 || "$nok" -ne 9 ]]; then
    echo "run $id: non-qualifying (light=$nlight/6 heavy=$nheavy/3 green=$nok/9) — skipped"
    continue
  fi

  qualifying=$((qualifying + 1))
  worst="$(jq '[.[].dur] | max' <<<"$TABLE")"
  worstname="$(jq -r 'max_by(.dur) | .name' <<<"$TABLE")"
  echo "run $id: qualifying — worst leg $worstname ${worst}s"
  if [[ "$worst" -ge "$LEG_BUDGET_S" ]]; then
    breached=$((breached + 1))
    echo "run $id: BREACH — $worstname at ${worst}s >= ${LEG_BUDGET_S}s budget" >&2
  fi
done

echo "summary: examined=$examined qualifying=$qualifying breached=$breached cutoff=$CUTOFF"

if [[ "$qualifying" -lt "$MIN_RUNS" ]]; then
  echo "NOT YET: $qualifying qualifying post-carve-out runs (< $MIN_RUNS)." >&2
  exit 2
fi
if [[ "$breached" -gt 0 ]]; then
  echo "FAIL: $breached/$qualifying qualifying runs had a leg >= ${LEG_BUDGET_S}s." >&2
  exit 1
fi
echo "PASS: $qualifying qualifying runs; every test-scripts* leg < ${LEG_BUDGET_S}s."
exit 0
