#!/usr/bin/env bash
# deploy-script-tests-legs-8736.sh — post-shard soak probe for #8736.
#
# Measures the thing the issue actually demands: the wall-clock duration of
# the `deploy-script-tests` MATRIX LEGS on main-branch infra-validation.yml
# runs after the K=4 shard landed. Metric is per-JOB
# `completed_at - started_at` on every leg whose display name matches
# `deploy-script-tests (<k>/4)`, plus the `deploy-script-tests-fixed` and
# `deploy-script-tests-done` singletons. The run-level duration is the wrong
# quantity (the aggregator serializes behind all legs); leg-level is what
# the #8736 tail was made of.
#
# A run is QUALIFYING only when all six expected jobs are present, each with
# conclusion=success and non-null started/completed timestamps:
#   deploy-script-tests (1/4..4/4) + deploy-script-tests-fixed +
#   deploy-script-tests-done
# A pre-shard run (no matrix legs), a run with a skipped leg, or a run with a
# failed leg contributes nothing to the sample. That asymmetry is fail-safe:
# it delays a PASS, never fabricates one.
#
# Caveat recorded for the sweeper's auto-close comment: the 600-second leg
# budget is the #8736 acceptance bound ("under 10 min") on a QUIET pool —
# leg duration includes runner-acquisition wait (started_at is job start,
# not container boot; the queue term lands between job created_at and
# started_at, which this probe does NOT measure). A PASS reads as
# "post-shard green-path leg tail", not "the tail is bounded under
# contention".
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS              (>=5 qualifying post-cutoff runs, AND every leg in
#                          every qualifying run < 600 s; sweeper closes #8736)
#   1 = FAIL              (a qualifying leg breached the budget; sweeper
#                          comments, leaves open)
#   2 = NOT YET           (<5 qualifying runs; cutoff unset/unparseable;
#                          GH_TOKEN/gh/jq missing. NOT exit 0: an unmet
#                          precondition must not auto-close #8736)
#   3 = CANNOT ESTABLISH  (gh API failures; sweeper comments, retries)
#   78 = xtrace refusal while GH_TOKEN is set (#7797)
#
# Required env: GH_TOKEN (needs actions:read — the sweeper forwards the
# repo's GITHUB_TOKEN under `secrets=GH_TOKEN`). Clock: SOLEUR_FT_EARLIEST
# (forwarded from the directive's `earliest=`) — required; runs must
# postdate it because pre-merge runs predate the shard and are stale data,
# not a small sample.
#
# RETIREMENT: one-shot soak probe. When #8736 closes, delete this file, its
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
WORKFLOW="infra-validation.yml"
MIN_RUNS=5              # #8736's "measured over >=5 consecutive green runs"
LEG_BUDGET_S=600        # #8736's <10-minute acceptance bound, per-leg

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

# Completed push runs on main, newest first. `created_at` is what the issue
# timestamps describe; compare epochs, not strings.
RUNS="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?branch=main&event=push&status=completed&per_page=30" \
        --jq '.workflow_runs[] | select(.conclusion == "success") | [.id, .created_at] | @tsv')" \
  || { echo "CANNOT ESTABLISH: gh api runs list failed" >&2; exit 3; }

examined=0; qualifying=0; breached=0
while IFS=$'\t' read -r id created; do
  [ -n "$id" ] || continue
  created_epoch="$(iso_epoch "$created" || true)"
  [ -n "${created_epoch:-}" ] || continue
  [ "$created_epoch" -le "$CUTOFF_EPOCH" ] && continue
  examined=$((examined + 1))

  JOBS="$(gh api --paginate "repos/$REPO/actions/runs/$id/jobs?per_page=100" 2>/dev/null)" \
    || { echo "CANNOT ESTABLISH: jobs list for run $id unreadable" >&2; exit 3; }

  # Per-run leg table: name<TAB>duration_s<TAB>ok. A leg counts `ok` only when
  # conclusion==success AND both timestamps parse to epochs. --paginate on the
  # jobs endpoint yields concatenated {jobs:[...]} pages; slurp merges them.
  TABLE="$(printf '%s' "$JOBS" | jq -rs '
    [ .[] | .jobs // [] | .[]
      | select(.name | test("^deploy-script-tests( \\([0-9]+/4\\)|-fixed|-done)?$"))
      | { name,
          dur: (if .started_at != null and .completed_at != null
                then ((.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601))
                else null end),
          ok: (.conclusion == "success" and .started_at != null and .completed_at != null) }
    ]')" || { echo "CANNOT ESTABLISH: jobs list for run $id unparseable" >&2; exit 3; }

  nlegs="$(jq '[.[] | select(.name | startswith("deploy-script-tests ("))] | length' <<<"$TABLE")"
  nfixed="$(jq '[.[] | select(.name == "deploy-script-tests-fixed")] | length' <<<"$TABLE")"
  ndone="$(jq '[.[] | select(.name == "deploy-script-tests-done")] | length' <<<"$TABLE")"
  nok="$(jq '[.[] | select(.ok)] | length' <<<"$TABLE")"

  # All six jobs present AND all green-and-measured. Anything else is
  # non-qualifying, not a sample point (pre-shard shape, skipped leg,
  # failed leg — each explained in the header).
  if [[ "$nlegs" -ne 4 || "$nfixed" -ne 1 || "$ndone" -ne 1 || "$nok" -ne 6 ]]; then
    echo "run $id: non-qualifying (legs=$nlegs/4 fixed=$nfixed/1 done=$ndone/1 green=$nok/6) — skipped"
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
done <<<"$RUNS"

echo "summary: examined=$examined qualifying=$qualifying breached=$breached cutoff=$CUTOFF"

if [[ "$qualifying" -lt "$MIN_RUNS" ]]; then
  echo "NOT YET: $qualifying qualifying post-shard runs (< $MIN_RUNS)." >&2
  exit 2
fi
if [[ "$breached" -gt 0 ]]; then
  echo "FAIL: $breached/$qualifying qualifying runs had a leg >= ${LEG_BUDGET_S}s." >&2
  exit 1
fi
echo "PASS: $qualifying qualifying runs; every deploy-script-tests leg < ${LEG_BUDGET_S}s."
exit 0
