#!/usr/bin/env bash
# Follow-through: #7432 — soak probe for removing the JOBS pin from the main health monitor's INFRA step.
#
# DIRECTIVE (set on #7432 after the Item I PR merges; `earliest` is the merge time and is the soak window start):
#   <!-- soleur:followthrough script=scripts/followthroughs/jobs1-stopgap-7432.sh earliest=<merge time, ISO Z> secrets=GH_TOKEN -->
# The sweeper hands the directive's `earliest` to the probe as SOLEUR_FT_EARLIEST. The window start is that value and
# nothing else: not a constant here, and not the workflow file's last commit (the file changes about every four days,
# so a commit-time anchor would let an unrelated edit restart the soak or reopen a closed #7432).
#
# What it decides: the infra step now runs at the runner's default width (Item I of #9217 removed its pin; the tests
# step keeps one, because that step nests the runner on a branch diff touching apps/web-platform/infra/). The soak
# is the 12 OLDEST completed, non-cancelled monitor runs on `main` created at or after the window start. Once 12
# such runs exist a later bad run cannot change the verdict (PASS is monotone), so the sweeper's re-check of a
# closed issue cannot reopen #7432.
#
# REVERT TRIGGER (recorded here and on #7432): within those 12 runs, an infra step killed at its ceiling, or two or
# more REDs that do NOT reproduce, restores the pin in a PR that also flips guard (12b) in
# plugins/soleur/test/main-health-monitor-workflow.test.sh. A RED reproduces only if the same suite is RED at the
# same sha in an infra-validation run, or a rerun of that suite at -P 1 also fails. Read the numbers with the caveat
# that the measured upper bound on isolated suite-events (13.6% of push runs, which includes one-commit regressions)
# would, taken literally, fire the two-RED arm about half the time; M3 cannot show every isolated event was
# contention-shaped, so a revert is not a failure of the analysis. Cancelled runs are skipped. A manual
# `dry_run=true` dispatch on `main` is counted (a valid infra sample). The realistic soak is 3.5 days or more
# because about 10% of runs have no verdict. Closing #7432 closes #7376 through suite-runner-flake-7376.sh, which
# means #7376 closes on 12 clean infra runs while the tests-step pin remains (an accepted claim, repeated in the
# closing comment).
#
# CLEAN RUN: annotation `main-health-outcomes` reads infra=success, or infra=failure with a RED set (the `RED  <path>`
# lines printed after the infra step's env dump) that is a subset of KNOWN_DETERMINISTIC_REDS below. That suite is the
# tag-drift guard, RED on main by design and reproducing in infra-validation, so it is not parallel-only evidence.
#
# Exit codes (sweep-followthroughs.sh vocabulary): 0 PASS (closes) | 1 FAIL (a counted run was killed at the infra
# ceiling; precedence over 5) | 2 NOT YET (the infra pin is still on main, fewer than 12 runs, or a counted run is
# still running) | 3 CANNOT ESTABLISH (any read failed, SOLEUR_FT_EARLIEST unset or not an ISO timestamp, the run list
# filled its limit, or a counted non-cancelled run has no annotation) | 5 ACTION REQUIRED (a counted run has a RED
# outside the allowlist, or an infra failure with no RED line; whether it reproduces needs a person) | 78 refused to
# run under xtrace with GH_TOKEN set (#7797).
#
# RETIREMENT: when #7432 closes, delete this file, its .test.sh, the run_suite line in scripts/test-all.sh, and the
# comment in suite-runner-flake-7376.sh that depends on #7432 closing.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}${GITHUB_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
WF="main-health-monitor.yml"
N=12
KNOWN_DETERMINISTIC_REDS="cloud-init-inngest-bootstrap.test.sh"

for need in gh jq base64 awk grep sed sort tr head date; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the directive must declare secrets=GH_TOKEN)"; exit 3; }
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
case "$EARLIEST" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset or not an ISO timestamp (got '${EARLIEST}')"; exit 3 ;;
esac

# --- 1. the pin on main: count JOBS assignments in the comment-stripped workflow ---------------------------------------
content="$(gh api "repos/$REPO/contents/.github/workflows/$WF?ref=main" --jq .content 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not read $WF from main"; exit 3; }
body="$(base64 -d <<<"$content" 2>/dev/null)" || body=""
[ -n "$body" ] || { echo "CANNOT ESTABLISH: $WF on main decoded to nothing"; exit 3; }
case "$body" in *main-health-monitor*) : ;; *) echo "CANNOT ESTABLISH: fetched content does not look like the monitor workflow"; exit 3 ;; esac
pins="$(grep -vE '^[[:space:]]*#' <<<"$body" | grep -cE '(^|[^A-Za-z0-9_])JOBS[[:space:]]*[:=]')" || pins=0
if [ "$pins" -ge 2 ]; then
  echo "NOT YET: $pins JOBS assignments on main (the tests-step pin plus another); the infra-step pin has not been removed."
  exit 2
fi

# --- 2. the run list: the oldest N completed non-cancelled runs at or after the window start --------------------------------
runs="$(gh run list -R "$REPO" --workflow "$WF" --branch main --limit 200 --created ">=$EARLIEST" --json databaseId,status,conclusion,createdAt,event 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not list $WF runs on main"; exit 3; }
count="$(jq 'length' <<<"$runs" 2>/dev/null)" || count=""
case "$count" in ''|*[!0-9]*) echo "CANNOT ESTABLISH: the run list was not a JSON array"; exit 3 ;; esac
if [ "$count" -ge 200 ]; then
  echo "CANNOT ESTABLISH: the run list filled its 200-run limit, so the oldest $N runs may be missing"
  exit 3
fi
oldest="$(jq -r --argjson n "$N" '[.[] | select(.conclusion != "cancelled")] | sort_by(.createdAt) | .[0:$n] | .[] | "\(.databaseId) \(.status)"' <<<"$runs" 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not project the run list"; exit 3; }

# --- 3. classify each counted run --------------------------------------------------------------------------------------------
killed=""; reds=""; unread=""; pending=0; seen=0; allowlisted=""
while read -r rid status; do
  [ -n "$rid" ] || continue
  seen=$((seen + 1))
  if [ "$status" != "completed" ]; then pending=$((pending + 1)); continue; fi
  jobs_json="$(gh api "repos/$REPO/actions/runs/$rid/jobs?per_page=100" 2>/dev/null)" || { unread="$unread $rid(jobs)"; continue; }
  jid="$(jq -r '[.jobs[] | select(.name == "health-check")][0].id // empty' <<<"$jobs_json" 2>/dev/null)" || jid=""
  [ -n "$jid" ] || { unread="$unread $rid(job)"; continue; }
  ann="$(gh api "repos/$REPO/check-runs/$jid/annotations?per_page=100" 2>/dev/null)" || { unread="$unread $rid(annotations)"; continue; }
  msg="$(jq -r '[.[] | select(.title == "main-health-outcomes")][0].message // ""' <<<"$ann" 2>/dev/null)" || { unread="$unread $rid(annotations)"; continue; }
  if [ -z "$msg" ]; then unread="$unread $rid(no-outcome-annotation)"; continue; fi
  tmo="$(jq -r '[.[] | select(.message | test("action .Run infra suites. has timed out"))] | length' <<<"$ann" 2>/dev/null)" || tmo=""
  case "$tmo" in ''|*[!0-9]*) unread="$unread $rid(annotations)"; continue ;; esac
  if [ "$tmo" -gt 0 ]; then killed="$killed $rid"; continue; fi
  infra="$(sed -n 's/.* infra=\([a-z_]*\).*/\1/p' <<<"$msg")"
  if [ "$infra" = "success" ]; then continue; fi
  if [ "$infra" != "failure" ]; then reds="$reds $rid(infra=${infra:-unknown})"; continue; fi
  log="$(gh api "repos/$REPO/actions/jobs/$jid/logs" 2>/dev/null)" || { unread="$unread $rid(log)"; continue; }
  # only the infra step's part of the job log: everything from its env dump onward
  red_set="$(awk '/TEST_GROUP: infra$/ {on=1} on' <<<"$log" | grep -oE '^[0-9TZ:.-]+ +RED  apps/web-platform/infra/[^ ]+' | sed -E 's|.*RED  apps/web-platform/infra/||' | sort -u)" || red_set=""
  if [ -z "$red_set" ]; then reds="$reds $rid(infra=failure,no-RED-line)"; continue; fi
  other=""
  for s in $red_set; do
    case " $KNOWN_DETERMINISTIC_REDS " in *" $s "*) : ;; *) other="$other $s" ;; esac
  done
  if [ -n "$other" ]; then reds="$reds $rid(${other# })"; else allowlisted="$allowlisted $rid"; fi
done <<<"$oldest"

# --- 4. verdict, in precedence order -----------------------------------------------------------------------------------------
if [ -n "$killed" ]; then
  echo "FAIL: infra step killed at its ceiling in run(s):$killed (revert trigger 2: restore the pin together with guard 12b)."
  [ -n "$reds" ] && echo "  also RED outside the allowlist:$reds"
  exit 1
fi
if [ -n "$reds" ]; then
  echo "ACTION REQUIRED: RED outside the allowlist in run(s):$reds. Check whether it reproduces at the same sha in infra-validation or at -P 1 (revert trigger 1)."
  exit 5
fi
if [ -n "$unread" ]; then
  echo "CANNOT ESTABLISH: could not read run(s):$unread"
  exit 3
fi
if [ "$pending" -gt 0 ]; then
  echo "NOT YET: $pending counted run(s) still running ($seen of $N seen)."
  exit 2
fi
if [ "$seen" -lt "$N" ]; then
  echo "NOT YET: $seen of $N clean runs since $EARLIEST."
  exit 2
fi
echo "PASS: the oldest $N non-cancelled monitor runs since $EARLIEST all read clean at the default infra width (${pins} JOBS assignment on main).${allowlisted:+ Allowlisted tag-drift RED in run(s):$allowlisted.}"
exit 0
