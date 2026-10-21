#!/usr/bin/env bash
# Follow-through: #7432 — soak probe for removing the JOBS pin from the main health monitor's INFRA step.
#
# DIRECTIVE (on #7432; `earliest` is set BEFORE the Item I PR merges, to a time safely after the merge, and re-edited if
# the merge slips past it — the sweeper does not run this probe before `earliest`, which also keeps it off the old directive):
#   <!-- soleur:followthrough script=scripts/followthroughs/jobs1-stopgap-7432.sh earliest=<ISO Z> secrets=GH_TOKEN -->
# The sweeper hands `earliest` to the probe as SOLEUR_FT_EARLIEST. It is the window start and nothing else: not a constant
# here, and not the workflow file's last commit (a commit-time anchor would let an unrelated edit restart the soak).
#
# What it decides: the infra step runs at the runner's default width (Item I of #9217 removed its pin; the tests step keeps
# one, because it nests the runner on a branch diff touching apps/web-platform/infra/). The soak is the 12 OLDEST completed,
# non-cancelled monitor runs on `main` (any event; a manual dry_run=true dispatch is a valid infra sample) created at or
# after the window start. Once 12 exist a later bad run cannot change the verdict, so PASS is monotone and the sweeper's
# re-check of a closed issue cannot reopen #7432. 12 runs at 4 a day is about 3 days. WIDTH IS PROVEN PER RUN, not assumed
# from the clock: every counted run's job log must carry exactly one `with -P K` with K >= 2, else the run is unreadable.
#
# REVERT TRIGGER (stated here once; the workflow comment, guard (12b) and the ADR point here): within the 12 runs, an infra
# step killed or not completed (exit 1), or two or more suite REDs that do NOT reproduce (each non-allowlisted RED suite is
# one strike, so one run holding two of them is two), restores the pin in a PR that also flips guard (12b) in
# plugins/soleur/test/main-health-monitor-workflow.test.sh. A RED reproduces if the same suite is RED at the same sha in
# an infra-validation run, or a rerun of it at -P 1 also fails. HUMAN clause, not encoded here: revert
# early on a single non-deterministic RED in the first 3 runs, judged on the monitor's own filed P1 in the first ~18 hours.
# Evidence limit: of 15 same-sha pairs only 3 were informative and none showed a parallel-only failure, so the history
# cannot rule a parallel-only RED out; this soak is the instrument. #7376 later traced the original flake mostly to the
# `grep -q` early-exit pipe shape (contention only opened the scheduling gap), which #9554 removed on 2026-10-06 -- the
# start of this soak's observation window.
#
# CLASSIFICATION per counted run, in this order: width not provable (unread) | annotation missing, duplicated or malformed
# (unread) | killed (the `Run infra suites` timeout annotation, or infra=failure with no infra_elapsed_s) | infra=success
# (clean) | infra neither success nor failure (hard) | infra=failure: the runner's own tally line (`=== registered infra
# suites: P passed, F failed, U unaccounted ===`) absent, duplicated, with U > 0 or with F not equal to the RED lines, or an
# UNACCOUNTED line (all hard), no RED line (hard), a RED set inside KNOWN_DETERMINISTIC_REDS (clean, disclosed), otherwise
# one STRIKE per non-allowlisted RED suite unless the run id is in JUDGED_REPRODUCING_RUNS (run-granular — every
# non-allowlisted RED in a listed run is excused, so ids are added only for runs verified to carry no second defect). A
# human adds an id there, by PR, only after confirming the RED reproduces (which makes it not a strike under the
# trigger above) — or, exceptionally, judging it reproducing-in-intent: a self-attributing defect class with its fix
# in the same PR, the deviation disclosed at the data site and in the PR body; a run judged NON-reproducing stays a
# strike. A run whose only REDs are allowlisted reads clean and is named in the PASS line;
# there is no cap, because the deterministic tag-drift RED has its own P1 from the monitor.
#
# Exit codes (sweep-followthroughs.sh vocabulary), in precedence order: 1 FAIL (a counted run was killed) | 5 ACTION
# REQUIRED (any hard failure, or two or more strikes: whether they reproduce needs a person) | 3 CANNOT ESTABLISH (any read
# failed, SOLEUR_FT_EARLIEST unset or not a real ISO timestamp, the run list filled its limit, a counted run's width or
# outcome annotation could not be read) | 2 NOT YET (the infra pin is still on main, a counted run is still running, or
# fewer than 12 runs) | 0 PASS | 78 refused to run under xtrace with GH_TOKEN set (#7797). A single strike is tolerated and
# the PASS line names it, together with every allowlisted run, so whoever closes sees it.
#
# #7376 is NOT closed by this probe. 12 clean runs bound the failure rate at about 25% (rule of three) and #7376's own fix
# criteria are unmet, so the evidence supports "mitigated", not "fixed" (the runs are not independent, so the bound is
# generous). On a PASS, post the figures on #7376 and let a person decide closure.
#
# RETIREMENT: when #7432 closes, delete this file, its .test.sh and the run_suite line in scripts/test-all.sh, remove
# `checks: read` from scheduled-followthrough-sweeper.yml, and decide whether to re-derive the infra step's 60-minute ceiling
# (over-provisioned at the default width; it and its Sentry coupling were deliberately not re-derived in Item I).
set -uo pipefail
# no pathname expansion: a RED name is attacker-influenceable text and `for s in $reds` must not glob it
set -f

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
# Judged reproducing by PR (see header): runs 39378082716 + 39446197504 each carried one non-allowlisted
# RED, git-data-wipe-assert.test.sh bound-killed rc=124 at the 360 s default — the H4 class the runner's
# ATTRIBUTION block owns to _SUITE_BOUNDS, a deterministic capacity defect fixed by this same PR's =720
# entry (#10654), not the -P 4 flake the soak measures. Neither literal reproduction test held
# (same-sha infra-validation passed it; -P 1 would pass), so this judgment is disclosed deviation,
# bounded by: self-attributing rc class, the fix landing in this PR, disclosure in the PR body.
# Both runs verified single-RED (tallies 180/1/0, 182/1/0), so the run-granular excuse masks nothing.
JUDGED_REPRODUCING_RUNS="39378082716 39446197504"

for need in gh jq base64 awk grep sed sort tr head date wc; do
  command -v "$need" >/dev/null 2>&1 || { echo "CANNOT ESTABLISH: $need is not installed"; exit 3; }
done
[ -n "${GH_TOKEN:-}" ] || { echo "CANNOT ESTABLISH: GH_TOKEN is not set (the directive must declare secrets=GH_TOKEN)"; exit 3; }
EARLIEST="${SOLEUR_FT_EARLIEST:-}"
case "$EARLIEST" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
  *) echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST is unset or not an ISO timestamp (got '${EARLIEST}')"; exit 3 ;;
esac
# shape alone admits 2026-13-45T25:61:61Z, which `gh run list --created` quietly answers with zero runs: round-trip it
rt="$(date -u -d "$EARLIEST" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || rt=""
[ "$rt" = "$EARLIEST" ] || { echo "CANNOT ESTABLISH: SOLEUR_FT_EARLIEST '$EARLIEST' is not a real timestamp"; exit 3; }

# --- 1. the pin on main: count JOBS assignments in the comment-stripped workflow (bare or quoted key) -----------------------
# A cheap NOT YET gate and advisory only: it is location-blind. The authoritative width check is the per-run `-P K` below.
content="$(gh api "repos/$REPO/contents/.github/workflows/$WF?ref=main" --jq .content 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not read $WF from main"; exit 3; }
body="$(base64 -d <<<"$content" 2>/dev/null)" || body=""
[ -n "$body" ] || { echo "CANNOT ESTABLISH: $WF on main decoded to nothing"; exit 3; }
case "$body" in *main-health-monitor*) : ;; *) echo "CANNOT ESTABLISH: fetched content does not look like the monitor workflow"; exit 3 ;; esac
PIN_RE="(^|[^A-Za-z0-9_])[\"']?JOBS[\"']?[[:space:]]*[:=]"
WIDTH_RE='^[0-9TZ:.-]+ +Running [0-9]+ registered infra suite\(s\)[^|]* with -P [0-9]+'
SUMMARY_RE='^[0-9TZ:.-]+ +=== registered infra suites: [0-9]+ passed, [0-9]+ failed, [0-9]+ unaccounted \(of [0-9]+\) ===$'
pins="$(grep -vE '^[[:space:]]*#' <<<"$body" | grep -cE "$PIN_RE")" || pins=0
if [ "$pins" -ge 2 ]; then
  echo "NOT YET: $pins JOBS assignments on main (the tests-step pin plus another); the infra-step pin has not been removed."
  exit 2
fi

# --- 2. the run list: the oldest N completed non-cancelled runs at or after the window start --------------------------------
runs="$(gh run list -R "$REPO" --workflow "$WF" --branch main --limit 200 --created ">=$EARLIEST" --json databaseId,status,conclusion,createdAt,event 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not list $WF runs on main"; exit 3; }
count="$(jq 'if type == "array" then length else error("not an array") end' <<<"$runs" 2>/dev/null)" || count=""
case "$count" in ''|*[!0-9]*) echo "CANNOT ESTABLISH: the run list was not a JSON array"; exit 3 ;; esac
if [ "$count" -ge 200 ]; then
  echo "CANNOT ESTABLISH: the run list filled its 200-run limit, so the oldest $N runs may be missing"
  exit 3
fi
oldest="$(jq -r --argjson n "$N" '[.[] | select(.conclusion != "cancelled")] | unique_by(.databaseId) | sort_by(.createdAt) | .[0:$n] | .[] | "\(.databaseId) \(.status)"' <<<"$runs" 2>/dev/null)" \
  || { echo "CANNOT ESTABLISH: could not project the run list"; exit 3; }

# --- 3. classify each counted run --------------------------------------------------------------------------------------------
killed=""; hard=""; unread=""; allowlisted=""; judged=""; strikes=""; nstrikes=0; ks=""; pending=0; seen=0

classify() {  # classify <run id>: appends to the lists above and returns; it never exits
  local rid="$1" jobs_json jid log slice nw k ann msg tmo toks infra_vals ni infra reds nred sumn sumline sf su s other n_other name
  jobs_json="$(gh api "repos/$REPO/actions/runs/$rid/jobs?per_page=100" 2>/dev/null)" || { unread="$unread $rid(jobs)"; return; }
  jid="$(jq -r '[.jobs[] | select(.name == "health-check")][0].id // empty' <<<"$jobs_json" 2>/dev/null)" || jid=""
  [ -n "$jid" ] || { unread="$unread $rid(job)"; return; }
  # --allow-escape-sequences: gh refuses a log body carrying ESC bytes without it (every real monitor log does)
  log="$(gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$jid/logs" 2>/dev/null)" || { unread="$unread $rid(log)"; return; }
  # only the infra step's part of the job log: everything from its env dump onward
  slice="$(awk '/TEST_GROUP: infra$/ {on=1} on' <<<"$log")"
  # width proof, BEFORE any kill classification: a pre-removal -P 1 killed run must not raise a false FAIL
  # anchored on the runner's own timestamped line: a `SOLEUR| ` suite excerpt or a quoted decoy cannot match
  nw="$(grep -cE "$WIDTH_RE" <<<"$slice")" || nw=0
  k="$(grep -E "$WIDTH_RE" <<<"$slice" | head -1 | grep -oE ' with -P [0-9]+' | grep -oE '[0-9]+' | head -1)"
  case "$k" in ''|*[!0-9]*) unread="$unread $rid(width:none)"; return ;; esac
  if [ "$nw" != 1 ] || [ "${#k}" -gt 3 ] || [ "$k" -lt 2 ]; then unread="$unread $rid(width:$k)"; return; fi
  case " $ks " in *" $k "*) : ;; *) ks="$ks $k" ;; esac
  ann="$(gh api "repos/$REPO/check-runs/$jid/annotations?per_page=100" 2>/dev/null)" || { unread="$unread $rid(annotations)"; return; }
  msg="$(jq -r '[.[] | select(.title == "main-health-outcomes" and ((.message // "") | startswith("SOLEUR_MAIN_HEALTH ")))] | if length == 1 then .[0].message else "" end' <<<"$ann" 2>/dev/null)" || { unread="$unread $rid(annotations)"; return; }
  [ -n "$msg" ] || { unread="$unread $rid(outcome-annotation)"; return; }
  tmo="$(jq -r '[.[] | select((.message // "") | test("action .Run infra suites. has timed out"))] | length' <<<"$ann" 2>/dev/null)" || tmo=""
  case "$tmo" in ''|*[!0-9]*) unread="$unread $rid(annotations)"; return ;; esac
  toks="$(tr ' ' '\n' <<<"$msg")"
  infra_vals="$(sed -n 's/^infra=\(.*\)$/\1/p' <<<"$toks")"
  ni="$(grep -c . <<<"$infra_vals")" || ni=0
  infra="$infra_vals"
  case "$infra" in *[!a-z_]*|'') ni=0 ;; esac
  if [ "$ni" != 1 ]; then unread="$unread $rid(infra-token)"; return; fi
  if [ "$tmo" -gt 0 ] || { [ "$infra" = failure ] && ! grep -qE '^infra_elapsed_s=[0-9]+$' <<<"$toks"; }; then killed="$killed $rid"; return; fi
  if [ "$infra" = success ]; then return; fi
  if [ "$infra" != failure ]; then hard="$hard $rid(infra=$infra)"; return; fi
  reds="$(grep -oE '^[0-9TZ:.-]+ +RED  apps/web-platform/infra/[^ ]+' <<<"$slice" | sed -E 's|.*RED  apps/web-platform/infra/||' | sort -u)"
  nred="$(grep -c . <<<"$reds")" || nred=0
  # the runner's own tally is the accounting proof: exactly one line, no unaccounted suite, F equal to the RED lines. A line
  # of the shape of a RED line cannot forge a clean run past it, and a suite killed with no rc (the OOM class) shows in U.
  sumn="$(grep -cE "$SUMMARY_RE" <<<"$slice")" || sumn=0
  sumline="$(grep -E "$SUMMARY_RE" <<<"$slice" | head -1)"
  sf="$(sed -E 's/.*: [0-9]+ passed, ([0-9]+) failed, ([0-9]+) unaccounted.*/\1/' <<<"$sumline")"
  su="$(sed -E 's/.*: [0-9]+ passed, ([0-9]+) failed, ([0-9]+) unaccounted.*/\2/' <<<"$sumline")"
  if grep -qE '^[0-9TZ:.-]+ +UNACCOUNTED  ' <<<"$slice" || [ "$sumn" != 1 ] || [ "$su" != 0 ] || [ "$sf" != "$nred" ]; then hard="$hard $rid(accounting)"; return; fi
  if [ -z "$reds" ]; then hard="$hard $rid(infra=failure,no-RED-line)"; return; fi
  other=""; n_other=0
  for s in $reds; do
    # a RED name reaches a public comment: anything outside a plain path alphabet is replaced, never echoed
    name="$s"; case "$name" in *[!A-Za-z0-9._/-]*) name="<unsafe-name>" ;; esac
    case " $KNOWN_DETERMINISTIC_REDS " in *" $name "*) : ;; *) other="$other $name"; n_other=$((n_other + 1)) ;; esac
  done
  if [ "$n_other" -eq 0 ]; then allowlisted="$allowlisted $rid"; return; fi
  case " $JUDGED_REPRODUCING_RUNS " in *" $rid "*) judged="$judged $rid"; return ;; esac
  strikes="$strikes $rid(${other# })"; nstrikes=$((nstrikes + n_other))
}

while read -r rid status; do
  [ -n "$rid" ] || continue
  seen=$((seen + 1))
  if [ "$status" != "completed" ]; then pending=$((pending + 1)); continue; fi
  classify "$rid"
done <<<"$oldest"

# --- 4. verdict, in precedence order -----------------------------------------------------------------------------------------
if [ -n "$killed" ]; then
  echo "FAIL: infra step killed or did not complete in run(s):$killed (revert trigger: restore the pin together with guard 12b)."
  exit 1
fi
if [ -n "$hard" ]; then
  echo "ACTION REQUIRED: a measurement defect in run(s):$hard (an infra outcome the soak cannot read as clean). A person decides: revert, or hand-close."
  exit 5
fi
if [ "$nstrikes" -ge 2 ]; then
  echo "ACTION REQUIRED: $nstrikes REDs outside the allowlist:$strikes. If both reproduce (same suite RED at the same sha in infra-validation, or at -P 1) add the run ids to JUDGED_REPRODUCING_RUNS by PR; otherwise the revert trigger fires."
  exit 5
fi
if [ -n "$unread" ]; then
  echo "CANNOT ESTABLISH: could not read run(s):$unread"
  exit 3
fi
if [ "$pending" -gt 0 ]; then
  echo "NOT YET: $pending counted run(s) still running ($seen of $N seen; strikes so far: ${nstrikes})."
  exit 2
fi
if [ "$seen" -lt "$N" ]; then
  echo "NOT YET: $seen of $N clean runs since $EARLIEST (strikes so far: ${nstrikes})."
  exit 2
fi
echo "PASS: the oldest $N non-cancelled monitor runs since $EARLIEST read clean at the default infra width (-P${ks}; ${pins} JOBS assignment on main).${strikes:+ Tolerated strike(s):$strikes.}${allowlisted:+ Allowlisted tag-drift RED in run(s):$allowlisted.}${judged:+ Judged-reproducing run(s):$judged.} #7376 is mitigated, not fixed: post the figures there."
exit 0
