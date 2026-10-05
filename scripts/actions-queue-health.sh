#!/usr/bin/env bash
# actions-queue-health.sh — reusable GitHub Actions queue-health probe.
#
# WHY THIS EXISTS (learned the hard way, #8450 post-upgrade incident): the org
# ran ~8–10 hosted jobs against a 200+ deep queue for ~90 minutes while
# plan.name already read `team` (60-job entitlement) — scheduler-side
# under-assignment, invisible to every monitor we had. Three numbers decide
# which failure you are looking at, and NO single one of them is sufficient:
#
#   queued runs        — demand backlog (depth)
#   jobs in flight     — DELIVERED concurrency (what the scheduler is actually
#                        assigning, vs the plan ENTITLEMENT — the two diverged)
#   median live queued — the stall clock. The MEDIAN age of the newest-100
#   run age              queued runs (zombie-aged entries excluded) measures
#                        whether the live backlog is draining: a fresh burst
#                        has a young median; a starved queue's median climbs
#                        past the threshold within ~one alert window (sustained
#                        arrivals above ~50 runs per stall-window can keep it
#                        young — a residual evasion noted in the alert body).
#
# Two traps this design avoids:
#   * run-level `created_at → run_started_at` is vacuous (equal on every
#     sampled run — it stamps at registration, not runner pickup), and
#     job-level `started_at - created_at` waits have SURVIVORSHIP bias: they
#     only count jobs that ever got a runner, so a wait-median reports healthy
#     through total starvation.
#   * Neither end of the queue is the starvation clock. OLDEST-queued age is
#     pinned open by zombies — queued runs are never reaped (live data showed
#     a 130-day-old `schedule` run and 34-day-old `issues` runs still
#     status=queued). NEWEST-queued age is pinned SHUT by continuous arrivals —
#     during the incident itself new pushes kept landing, so the freshest
#     member was always seconds old. The median of the newest-100 live (non-
#     zombie) members is immune to both: a handful of ancient tail entries
#     cannot move it, and it only climbs when arrivals genuinely stop being
#     admitted. Tail age is still reported as `zombie_runs` (queued >24h —
#     GitHub will never schedule those; cancel them).
#
# Verdicts:
#   HEALTHY        — live queue shallow, or its median age is young.
#   SATURATED      — deep+stalled queue AND delivered >= MIN_ASSIGN_PCT of the
#                    effective cap: the pool is working at entitlement; the
#                    fix is less demand or a bigger plan, not a support ticket.
#   UNDER_ASSIGNED — deep+stalled queue AND delivered < MIN_ASSIGN_PCT of cap:
#                    the incident signature (work waiting, entitlement idle).
#                    With an UNREADABLE plan (repo-scoped GITHUB_TOKEN cannot
#                    read orgs/{org}.plan) the cap falls back to the Free
#                    floor of 20 — which leaves a dead-band: delivered in
#                    [floor*PCT, real_cap*PCT) reads SATURATED, and the incident
#                    itself ran at ~10 jobs inside that band. Pin CAP_OVERRIDE
#                    to the known entitlement to close it (the scheduled
#                    monitor does); a live plan read always wins over the
#                    override.
#   UNKNOWN        — prereq/API failures; never silently HEALTHY.
#
# Exit: 0 HEALTHY|SATURATED, 1 UNDER_ASSIGNED, 2 UNKNOWN/prereq, 78 traced
# with a credential (#7797).
#
# Env: GH_TOKEN (required), REPO (default $GITHUB_REPOSITORY), ORG (default
# REPO owner), QUEUE_DEPTH_ALERT (25), QUEUE_STALL_ALERT_S (900),
# MIN_ASSIGN_PCT (50), MAX_IP_RUNS (100), ZOMBIE_S (86400), CAP_OVERRIDE (unset
# — a known plan entitlement, used ONLY when the plan endpoint is unreadable;
# a live plan read always wins so a post-downgrade stale override cannot
# false-page).
# Flags: --json emits ONLY a single metrics object on stdout (verdict is a field).

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

JSON_OUT=0
[ "${1:-}" = "--json" ] && JSON_OUT=1

[ -n "${GH_TOKEN:-}" ] || { echo "UNKNOWN: GH_TOKEN not set" >&2; exit 2; }
command -v gh >/dev/null || { echo "UNKNOWN: gh not on PATH" >&2; exit 2; }
command -v jq >/dev/null || { echo "UNKNOWN: jq not on PATH" >&2; exit 2; }

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
ORG="${ORG:-${REPO%%/*}}"
[ -n "$REPO" ] && [ -n "$ORG" ] || { echo "UNKNOWN: REPO/ORG unset (set REPO=owner/name)" >&2; exit 2; }

QUEUE_DEPTH_ALERT="${QUEUE_DEPTH_ALERT:-25}"
QUEUE_STALL_ALERT_S="${QUEUE_STALL_ALERT_S:-900}"
MIN_ASSIGN_PCT="${MIN_ASSIGN_PCT:-50}"
MAX_IP_RUNS="${MAX_IP_RUNS:-100}"
ZOMBIE_S="${ZOMBIE_S:-86400}"
CAP_OVERRIDE="${CAP_OVERRIDE:-}"
FREE_CAP=20
TEAM_CAP=60

# Non-numeric knob values must fail UNKNOWN, never degrade the gate to a
# silent false (a bad QUEUE_DEPTH_ALERT would make the stall test error out
# and read as HEALTHY through a real outage).
for kv in QUEUE_DEPTH_ALERT QUEUE_STALL_ALERT_S MIN_ASSIGN_PCT MAX_IP_RUNS ZOMBIE_S; do
  case "${!kv}" in ''|*[!0-9]*)
    echo "UNKNOWN: $kv='${!kv}' is not a non-negative integer" >&2; exit 2 ;;
  esac
done
if [ -n "$CAP_OVERRIDE" ]; then
  case "$CAP_OVERRIDE" in ''|*[!0-9]*)
    echo "UNKNOWN: CAP_OVERRIDE='$CAP_OVERRIDE' is not a non-negative integer" >&2; exit 2 ;;
  esac
fi

# --- plan -> entitlement cap ------------------------------------------------
# orgs/{org}.plan is restricted to org-owner/App tokens; a repo-scoped
# GITHUB_TOKEN gets 403 — that is UNREADABLE, not a failure (probe precedent).
PLAN="$(gh api "orgs/$ORG" --jq '.plan.name // "unreadable"' </dev/null 2>/dev/null)" \
  || PLAN="unreadable"
case "$PLAN" in
  free) CAP=$FREE_CAP ;;
  team) CAP=$TEAM_CAP ;;
  *)    # unreadable/enterprise/unknown: an explicit CAP_OVERRIDE (a known
        # org entitlement pinned by the caller) wins over the floor — without
        # it the repo-scoped GITHUB_TOKEN's 403 leaves a dead-band where
        # [floor*PCT, real_cap*PCT) delivered reads SATURATED, which is
        # exactly the band the incident ran in (10 jobs vs 60 entitlement).
        if [ -n "$CAP_OVERRIDE" ]; then CAP=$CAP_OVERRIDE; else CAP=$FREE_CAP; fi ;;
esac

# --- queue depth ------------------------------------------------------------
QUEUED_RUNS="$(gh api "repos/$REPO/actions/runs?status=queued&per_page=1" </dev/null \
  --jq '.total_count // 0' 2>/dev/null)" \
  || { echo "UNKNOWN: queued-runs list failed" >&2; exit 2; }
IP_RUNS_JSON="$(gh api "repos/$REPO/actions/runs?status=in_progress&per_page=$MAX_IP_RUNS" </dev/null 2>/dev/null)" \
  || { echo "UNKNOWN: in-progress list failed" >&2; exit 2; }
IP_RUN_COUNT="$(printf '%s' "$IP_RUNS_JSON" | jq -r '.workflow_runs | length' 2>/dev/null)" \
  || { echo "UNKNOWN: could not parse in-progress payload" >&2; exit 2; }
IP_TOTAL="$(printf '%s' "$IP_RUNS_JSON" | jq -r '.total_count // 0' 2>/dev/null)"
# A truncated in-progress page undercounts delivered concurrency — and a
# healthy pool delivering >MAX_IP_RUNS runs would read as UNDER_ASSIGNED.
# Fail UNKNOWN, not silent.
if [ "${IP_TOTAL:-0}" -gt "$IP_RUN_COUNT" ] 2>/dev/null; then
  echo "UNKNOWN: in-progress runs truncated ($IP_RUN_COUNT of $IP_TOTAL > MAX_IP_RUNS=$MAX_IP_RUNS)" >&2
  exit 2
fi

# --- delivered concurrency: jobs in flight across in-progress runs ----------
IN_FLIGHT=0
while IFS= read -r rid; do
  [ -n "$rid" ] || continue
  # NO --jq under --paginate: gh applies --jq PER PAGE and prints one line per
  # page, so a >per_page-job run yields a multi-line n and crashes the
  # arithmetic — with exit 1, the UNDER_ASSIGNED contract code. Concatenated
  # page objects slurp cleanly instead (jq -s on the response stream).
  n="$(gh api --paginate "repos/$REPO/actions/runs/$rid/jobs" </dev/null 2>/dev/null \
       | jq -s '[.[].jobs[] | select(.status == "in_progress")] | length' 2>/dev/null)" \
    || { echo "UNKNOWN: jobs list failed for run $rid" >&2; exit 2; }
  case "$n" in ''|*[!0-9]*)
    echo "UNKNOWN: bad jobs count for run $rid" >&2; exit 2 ;; esac
  IN_FLIGHT=$((IN_FLIGHT + n))
done <<EOF
$(printf '%s' "$IP_RUNS_JSON" | jq -r '.workflow_runs[].id' 2>/dev/null)
EOF

# --- queue ages -------------------------------------------------------------
# The runs list is newest-first and carries created_at in the payload, so the
# age model needs NO per-run jobs calls (a queued run's created_at is itself
# the wait lower bound — its jobs may not be instantiated yet).
#
#   page 1  -> live-member stats: median age over members younger than
#              ZOMBIE_S (the stall clock) + the live-depth approximation.
#   last pg -> tail stats: oldest age + zombie count (only fetched when the
#              queue exceeds one page; zombies live at the tail by definition).
#
# When the queue exceeds 100 members, page-1's live count is a lower bound on
# live depth — conservative direction (understates depth, never inflates it).
NOW_S="$(date -u +%s)"
MEDIAN_LIVE_S=0
LIVE_P1=0
NEWEST_QUEUED_S=0
OLDEST_QUEUED_S=0
ZOMBIE_RUNS=0
if [ "$QUEUED_RUNS" -gt 0 ]; then
  FIRST_PAGE="$(gh api "repos/$REPO/actions/runs?status=queued&per_page=100&page=1" </dev/null 2>/dev/null)" \
    || { echo "UNKNOWN: queued page 1 failed" >&2; exit 2; }
  AGE_STATS="$(printf '%s' "$FIRST_PAGE" | jq -r --argjson now "$NOW_S" --argjson zs "$ZOMBIE_S" '
    [.workflow_runs[].created_at | (sub("\\.[0-9]+Z$";"Z") | fromdateiso8601)] as $all
    | (if ($all|length) > 0 then $now - ($all|max) else 0 end) as $newest
    | ([$all[] | select(($now - .) < $zs)] | sort) as $live
    | "\($newest) \(if ($live|length) > 0 then $now - $live[($live|length)/2 | floor] else 0 end) \($live|length)"' 2>/dev/null)"
  # The stall clock must never silently read 0 on a parse failure — that would
  # report HEALTHY through a real outage. Empty stats on a non-empty queue is
  # UNKNOWN, not young.
  [ -n "$AGE_STATS" ] \
    || { echo "UNKNOWN: could not parse queued page 1 ages" >&2; exit 2; }
  read -r NEWEST_QUEUED_S MEDIAN_LIVE_S LIVE_P1 <<EOF2
$AGE_STATS
EOF2
  for v in NEWEST_QUEUED_S MEDIAN_LIVE_S LIVE_P1; do
    case "${!v}" in ''|*[!0-9]*) printf -v "$v" 0 ;; esac
  done

  if [ "$QUEUED_RUNS" -le 100 ]; then
    TAIL_SRC="$FIRST_PAGE"
  else
    last_page=$(( (QUEUED_RUNS + 99) / 100 ))
    TAIL_SRC="$(gh api "repos/$REPO/actions/runs?status=queued&per_page=100&page=$last_page" </dev/null 2>/dev/null)" \
      || { echo "UNKNOWN: oldest queued page failed" >&2; exit 2; }
  fi
  TAIL_STATS="$(printf '%s' "$TAIL_SRC" | jq -r --argjson now "$NOW_S" --argjson zs "$ZOMBIE_S" '
    [.workflow_runs[].created_at | (sub("\\.[0-9]+Z$";"Z") | fromdateiso8601)] as $ages
    | "\(if ($ages|length) > 0 then ($now - ($ages|min)) else 0 end) \([$ages[] | select(($now - .) > $zs)] | length)"' 2>/dev/null)"
  [ -n "$TAIL_STATS" ] \
    || { echo "UNKNOWN: could not parse queued tail-page ages" >&2; exit 2; }
  read -r OLDEST_QUEUED_S ZOMBIE_RUNS <<EOF3
$TAIL_STATS
EOF3
  for v in OLDEST_QUEUED_S ZOMBIE_RUNS; do
    case "${!v}" in ''|*[!0-9]*) printf -v "$v" 0 ;; esac
  done
fi

# Live depth discounts the zombie tail — a queue that is 90% dead backlog is
# not 90% demand. Live members are all younger than every zombie, so they form
# a PREFIX of the newest-first list: when page 1 contains a zombie (LIVE_P1 <
# 100) it also contains every live member and LIVE_P1 is exact. When page 1 is
# all-live, live members may continue past it — subtract the tail-page zombie
# count (a lower bound if zombies span multiple tail pages).
if [ "$LIVE_P1" -lt 100 ]; then LIVE_QUEUED=$LIVE_P1; else LIVE_QUEUED=$((QUEUED_RUNS - ZOMBIE_RUNS)); fi

# --- verdict ----------------------------------------------------------------
MIN_DELIVERED=$(( CAP * MIN_ASSIGN_PCT / 100 ))
VERDICT="HEALTHY"
if [ "$LIVE_QUEUED" -ge "$QUEUE_DEPTH_ALERT" ] \
   && [ "$MEDIAN_LIVE_S" -ge "$QUEUE_STALL_ALERT_S" ]; then
  if [ "$IN_FLIGHT" -lt "$MIN_DELIVERED" ]; then
    VERDICT="UNDER_ASSIGNED"
  else
    VERDICT="SATURATED"
  fi
fi

if [ "$JSON_OUT" -eq 1 ]; then
  jq -n --arg v "$VERDICT" --argjson qr "$QUEUED_RUNS" --argjson ipr "$IP_RUN_COUNT" \
     --argjson jif "$IN_FLIGHT" --argjson cap "$CAP" --arg plan "$PLAN" \
     --argjson lq "$LIVE_QUEUED" --argjson mq "$MEDIAN_LIVE_S" \
     --argjson nq "$NEWEST_QUEUED_S" --argjson oq "$OLDEST_QUEUED_S" \
     --argjson zr "$ZOMBIE_RUNS" \
     '{verdict:$v, queued_runs:$qr, live_queued_runs:$lq, in_progress_runs:$ipr, jobs_in_flight:$jif, plan:$plan, cap:$cap, median_live_queued_run_s:$mq, newest_queued_run_s:$nq, oldest_queued_run_s:$oq, zombie_runs:$zr}'
else
  echo "$VERDICT: queued_runs=$QUEUED_RUNS live_queued=$LIVE_QUEUED in_progress_runs=$IP_RUN_COUNT jobs_in_flight=$IN_FLIGHT cap=${CAP}($PLAN) min_delivered=$MIN_DELIVERED median_live_queued_run_s=$MEDIAN_LIVE_S newest_queued_run_s=$NEWEST_QUEUED_S oldest_queued_run_s=$OLDEST_QUEUED_S zombie_runs=$ZOMBIE_RUNS"
fi

case "$VERDICT" in
  UNDER_ASSIGNED) exit 1 ;;
  UNKNOWN)        exit 2 ;;
  *)              exit 0 ;;
esac
