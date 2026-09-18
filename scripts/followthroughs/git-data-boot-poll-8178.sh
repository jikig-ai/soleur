#!/usr/bin/env bash
# Follow-through verification for #8178: after PR #8262 merged, did a REAL git-data
# dispatch's boot poll actually ANSWER?
#
# #8178 was a poll that could not read. Its reader bound a credential set the query
# endpoint rejected, discarded the reader's stderr, and reported every failed read as
# "no boot_complete row yet" — so a birth failed on a read that never happened. PR #8262
# moves the read onto the doppler prd_terraform source, anchors it to the run, and makes
# its failure self-describing. No suite can prove the READ works against the live
# warehouse from a real runner; only a real dispatch can, and dispatches are rare and
# operator-initiated. Hence this probe, and hence `Ref #8178` rather than an auto-close.
#
# THE PREDICATE IS A RUN, NOT A ROW. "A boot_complete row for soleur-git-data exists" was
# already TRUE before this change (row dt 2026-09-16 15:39:36, from a replace that ran the
# old code), so a row-based predicate would close #8178 on pre-fix evidence after its
# `earliest` delay alone. This probe instead requires, all at once:
#   - PR #8262 is merged (its merged_at is the anchor; nothing is hardcoded);
#   - an apply-web-platform-infra.yml run, event=workflow_dispatch, on main, CREATED
#     STRICTLY AFTER that merge (re-checked client-side, not trusted to the API filter);
#   - a git_data_host_create or git_data_host_replace job in it that actually ran
#     (conclusion != skipped) and completed;
#   - that job's log carries the poll LIBRARY's own runtime summary lines
#     (`answered=N/M last_class=…` and `VERDICT=…`, emitted by
#     scripts/lib/git-data-boot-signal-poll.sh). The old inline poll printed neither, so a
#     job running pre-fix code cannot satisfy this even if the date filter were wrong.
# The NEWEST such job decides. A job whose log has no VERDICT line either never reached
# the poll (apply failed before it, the run was cancelled) or ran the pre-fix inline poll —
# it proves nothing either way, and the probe looks at the next-older one.
#
# Exit semantics (sweep-followthroughs.sh contract; followthrough-convention.md):
#   0 = PASS              the newest evaluated post-merge poll ANSWERED (verdict received
#                         or silent, answered >= 1). `silent` still passes: the read path
#                         worked and the verdict is then a true statement about the host,
#                         which is the property #8178 was missing.
#   1 = FAIL              the newest evaluated post-merge poll did NOT answer
#                         (verdict unreadable, or refused-no-anchor = a wiring fault).
#   2 = NOT YET           measured: PR not merged, or no post-merge dispatch has reached a
#                         poll step yet. The normal state for weeks — births are once-ever
#                         and replaces are operator-initiated.
#   3 = CANNOT ESTABLISH  could not look: no token, an API/log read failed, or a log's
#                         shape did not match the library's contract. Kept distinct from 2
#                         on purpose — the sweeper renders 2 as "NOT YET", and "could not
#                         look" reported as "nothing yet" is the inversion #8178 itself was.
#   78 = refused to run under xtrace with GH_TOKEN set (#7797).
#
# CREDENTIAL POSTURE. The workflow token only, declared as `secrets=GH_TOKEN` (the sweeper
# runs probes under `env -i` and forwards only declared names). Deliberately NOT
# DOPPLER_TOKEN (it would hand every probe in the sweeper a prd_terraform read token) and
# NOT the BETTERSTACK_QUERY_* secrets (the credential store #8178 moves the poll OFF — a
# close criterion bound to it would measure the old path). The run log is the evidence, so
# no warehouse credential is needed at all.
#
# WHY `gh run view --job <id> --log` AND NOT `gh api …/jobs/<id>/logs`: measured
# 2026-09-18 on gh 2.101.0 — `gh api` exits 1 on this log, refusing a response that
# carries terminal escape sequences (the runner echoes each step's script in ANSI colour).
# `gh run view` is also what scripts/followthroughs/monitor-streak-cache-roundtrip-7574.sh
# used to reach its PASS from inside the sweeper.
#
# RETIREMENT: delete this file and its companion git-data-boot-poll-8178.test.sh, and the
# `run_suite "scripts/git-data-boot-poll-8178"` line in scripts/test-all.sh, once #8178
# closes. Nothing else references it.

set -uo pipefail

# xtrace would print every expanded command, GH_TOKEN included (#7797).
case "$-" in
  *x*)
    if [ -n "${GH_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

REPO="jikig-ai/soleur"
PR=8262
WF="apply-web-platform-infra.yml"
readonly REPO PR WF

_not_yet()  { echo "NOT YET: $1"; exit 2; }
_cannot()   { echo "CANNOT ESTABLISH: $1" >&2; exit 3; }

if [[ -z "${GH_TOKEN:-}" ]]; then
  _cannot "GH_TOKEN is not set — the directive must declare secrets=GH_TOKEN"
fi
command -v jq >/dev/null 2>&1 || _cannot "jq is not installed"

# --- The anchor: PR #8262's merge time -----------------------------------------------
pr_json=$(gh api "repos/${REPO}/pulls/${PR}" 2>/dev/null) || _cannot "could not read PR #${PR}"
merged_at=$(jq -r '.merged_at // ""' <<<"$pr_json" 2>/dev/null) || _cannot "PR #${PR} response is not JSON"
if [[ -z "$merged_at" ]]; then
  pr_state=$(jq -r '.state // "?"' <<<"$pr_json" 2>/dev/null || echo '?')
  _not_yet "PR #${PR} is not merged (state=${pr_state}); there is no post-fix code on main to verify"
fi
# The anchor is compared as a string below, which is only an ORDER when both sides share
# this exact shape. Refuse anything else rather than compare apples to a malformed pear.
[[ "$merged_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || _cannot "PR #${PR} merged_at has an unexpected shape: ${merged_at}"

# --- Candidate runs: dispatches on main created strictly after the merge -------------
runs_json=$(gh api --paginate \
  "repos/${REPO}/actions/workflows/${WF}/runs?event=workflow_dispatch&branch=main&created=%3E%3D${merged_at}&per_page=100" \
  2>/dev/null) || _cannot "could not list ${WF} runs"
# Re-checked client-side: the API's `created` filter is inclusive and is trusted for
# nothing — a run created AT the merge second may still be on the pre-fix tree.
mapfile -t run_ids < <(jq -rn --arg m "$merged_at" '
  [inputs | .workflow_runs[]?
   | select(.event == "workflow_dispatch" and .head_branch == "main"
            and (.created_at | type) == "string" and .created_at > $m)]
  | sort_by(.created_at) | reverse | .[] | "\(.id)"' <<<"$runs_json" 2>/dev/null)
jq -en 'inputs' <<<"$runs_json" >/dev/null 2>&1 || _cannot "${WF} run list is not JSON"

if [[ "${#run_ids[@]}" -eq 0 ]]; then
  _not_yet "no ${WF} dispatch on main since PR #${PR} merged at ${merged_at}"
fi

# --- Walk newest-first; the first job that reached its poll decides ------------------
ts_re='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'
tab=$'\t'
pending=0
unevaluable=0
for run_id in "${run_ids[@]}"; do
  [[ "$run_id" =~ ^[0-9]+$ ]] || _cannot "run id is not numeric: ${run_id}"
  jobs_json=$(gh api --paginate "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" 2>/dev/null) \
    || _cannot "could not list the jobs of run ${run_id}"
  jq -en 'inputs' <<<"$jobs_json" >/dev/null 2>&1 || _cannot "jobs of run ${run_id} are not JSON"
  # "\(.id) \(.name) \(.status)" — names are the job ids here (the git-data jobs carry no
  # `name:` key), so an exact match is the right comparison.
  mapfile -t jobs < <(jq -rn '
    [inputs | .jobs[]?
     | select((.name == "git_data_host_create" or .name == "git_data_host_replace")
              and .conclusion != "skipped")]
    | sort_by(.started_at // "") | reverse | .[] | "\(.id) \(.name) \(.status)"' <<<"$jobs_json" 2>/dev/null)
  for j in "${jobs[@]}"; do
    read -r job_id job_name job_status <<<"$j"
    [[ "$job_id" =~ ^[0-9]+$ ]] || _cannot "job id is not numeric in run ${run_id}: ${job_id}"
    if [[ "$job_status" != "completed" ]]; then
      pending=$((pending + 1))
      echo "run ${run_id} ${job_name} (job ${job_id}) is ${job_status} — not yet evaluable"
      continue
    fi
    log=$(gh run view --job "$job_id" --repo "$REPO" --log 2>/dev/null) \
      || _cannot "could not read the log of ${job_name} (job ${job_id}, run ${run_id})"
    [[ -n "$log" ]] || _cannot "the log of ${job_name} (job ${job_id}, run ${run_id}) is empty"
    # Runtime lines only: `<job>\t<step>\t<ts> VERDICT=…`. The step's own script is echoed
    # into the log too, but each echoed line starts with an ANSI colour code after the
    # timestamp, so anchoring the marker directly after `<ts> ` excludes it.
    log=${log//$'\r'/}
    mapfile -t verdicts < <(grep -oE "(^|${tab})${ts_re} VERDICT=[a-z-]+$" <<<"$log" | sed -E 's/.*VERDICT=//')
    mapfile -t summaries < <(grep -oE "(^|${tab})${ts_re} answered=[0-9]+/[0-9]+ last_class=[a-z_-]*$" <<<"$log" \
                             | sed -E 's/.* answered=([0-9]+)\/([0-9]+) .*/\1 \2/')
    if [[ "${#verdicts[@]}" -eq 0 ]]; then
      unevaluable=$((unevaluable + 1))
      echo "run ${run_id} ${job_name} (job ${job_id}): no VERDICT from the poll library in its log — its poll step did not run (apply failed first, or the run was cancelled) or ran pre-#8262 code; not evidence either way"
      continue
    fi
    [[ "${#verdicts[@]}" -eq 1 ]] || _cannot "${job_name} (job ${job_id}) logged ${#verdicts[@]} VERDICT lines; the library emits exactly one per poll"
    verdict="${verdicts[0]}"
    case "$verdict" in
      received|silent|unreadable|refused-no-anchor) : ;;
      *) _cannot "${job_name} (job ${job_id}) logged a VERDICT outside the library's vocabulary: ${verdict}" ;;
    esac
    answered=""
    if [[ "$verdict" != "refused-no-anchor" ]]; then
      # refused-no-anchor returns before polling, so it prints no summary; every other
      # verdict must carry exactly one, and it must agree with the verdict.
      [[ "${#summaries[@]}" -eq 1 ]] || _cannot "${job_name} (job ${job_id}) logged ${#summaries[@]} answered= summaries alongside VERDICT=${verdict}"
      read -r answered max_polls <<<"${summaries[0]}"
    fi
    where="${job_name} (job ${job_id}, run ${run_id}, https://github.com/${REPO}/actions/runs/${run_id})"
    case "$verdict" in
      received|silent)
        (( answered >= 1 )) || _cannot "${where}: VERDICT=${verdict} with answered=0 — the log contradicts the library's contract"
        echo "PASS: ${where} — the boot poll ANSWERED (${answered}/${max_polls} reads answered, VERDICT=${verdict})."
        [[ "$verdict" == "silent" ]] && echo "      Note: the host itself did not report boot_complete in the budget; that is a separate host fault the job already failed on, not #8178."
        exit 0
        ;;
      *)
        echo "FAIL: ${where} — the boot poll did NOT answer (VERDICT=${verdict}${answered:+, answered=${answered}/${max_polls}})." >&2
        echo "      The post-fix read path still cannot read the git-data boot signal. Read that job's per-poll lines: each names rc and class (credentials-rejected / table-missing / transport / reader-refusal)." >&2
        exit 1
        ;;
    esac
  done
done

if (( pending > 0 )); then
  _not_yet "${pending} post-merge git-data job(s) still running; ${unevaluable} completed without reaching the poll"
fi
_not_yet "${#run_ids[@]} post-merge dispatch(es) since ${merged_at}, none with a git-data job whose log carries the poll library's VERDICT (${unevaluable} git-data job(s) without one)"
