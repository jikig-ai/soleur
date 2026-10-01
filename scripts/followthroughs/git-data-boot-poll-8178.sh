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
#   - that job's POLL STEP ran (its own conclusion, from the jobs API, is success or
#     failure), and that step's OWN output carries the poll library's summary
#     (`answered=N/M last_class=…`), a matching number of `poll k/M: answered` lines, and
#     `VERDICT=…`. "Its own output" is bounded by the runner, not by the clock: the lines
#     between the poll step's `##[group]Run` header and the next step's. The next step's env
#     block, which echoes the operator's `reason` input, starts after that header, so free
#     text it echoes cannot supply or add a verdict, even in the same second.
# The NEWEST job whose poll step ran decides. A job whose poll step did not run (apply
# failed first, or the run was cancelled) proves nothing either way, and the probe looks at
# the next-older one.
#
# Exit semantics (sweep-followthroughs.sh contract; followthrough-convention.md):
#   0 = PASS              the newest evaluated post-merge poll had at least one read
#                         ANSWER (answered >= 1), whatever its verdict. That is the
#                         property #8178 lacked: the post-fix read path can read. A
#                         `silent` or a late `unreadable` is then a separate fault the job
#                         already reported.
#   1 = FAIL              the newest evaluated post-merge poll never answered
#                         (answered=0, or refused-no-anchor = a wiring fault).
#   2 = NOT YET           measured: PR not merged, or no post-merge dispatch has reached a
#                         poll step yet. The normal state for weeks — births are once-ever
#                         and replaces are operator-initiated.
#   3 = CANNOT ESTABLISH  could not look: no token, an API/log read failed, a poll step
#                         ran but left no VERDICT in its window (it failed before polling,
#                         or gh's log format changed), or a log's shape did not match the
#                         library's contract. Kept distinct from 2
#                         on purpose — the sweeper renders 2 as "NOT YET", and "could not
#                         look" reported as "nothing yet" is the inversion #8178 itself was.
#   78 = refused to run under xtrace with GH_TOKEN set (#7797).
#
# CREDENTIAL POSTURE. The workflow token only, declared as `secrets=GH_TOKEN` (the sweeper
# runs probes under `env -i` and forwards only declared names). Deliberately NOT the
# Doppler service token (it would hand every probe in the sweeper a prd_terraform read token) and
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
# KNOWN RESIDUAL: `head_branch == "main"` is also satisfied by a TAG named `main`. Pushing
# one needs repository write access, which already exceeds what this probe defends against.
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

# gh's stderr is KEPT (its first line goes into each CANNOT ESTABLISH message), so "the log
# has expired" and "rate limited" are distinguishable in the sweeper's comment. Discarding
# a reader's stderr is the defect #8178 fixes.
ERRF="$(mktemp -t gdbp8178.XXXXXXXX)" || _cannot "could not create a temp file"
trap 'rm -f "$ERRF"' EXIT
gh_err() { local l; l="$(head -1 "$ERRF" 2>/dev/null | tr -d '\r' | cut -c1-200)"; printf '%s' "${l:-<no stderr>}"; }

# --- The anchor: PR #8262's merge time -----------------------------------------------
pr_json=$(gh api "repos/${REPO}/pulls/${PR}" 2>"$ERRF") || _cannot "could not read PR #${PR}: $(gh_err)"
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
  2>"$ERRF") || _cannot "could not list ${WF} runs: $(gh_err)"
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

# --- Walk newest-first; the first job whose poll step ran decides --------------------
ts_re='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z'
pending=0
unevaluable=0
for run_id in "${run_ids[@]}"; do
  [[ "$run_id" =~ ^[0-9]+$ ]] || _cannot "run id is not numeric: ${run_id}"
  jobs_json=$(gh api --paginate "repos/${REPO}/actions/runs/${run_id}/jobs?per_page=100" 2>"$ERRF") \
    || _cannot "could not list the jobs of run ${run_id}: $(gh_err)"
  jq -en 'inputs' <<<"$jobs_json" >/dev/null 2>&1 || _cannot "jobs of run ${run_id} are not JSON"
  # One line per git-data job: id, name, status, and its POLL STEP's conclusion and window.
  # Names are the job ids (the git-data jobs carry no `name:` key), so exact match is right.
  mapfile -t jobs < <(jq -rn '
    [inputs | .jobs[]?
     | select((.name == "git_data_host_create" or .name == "git_data_host_replace")
              and .conclusion != "skipped")]
    | sort_by(.started_at // "") | reverse | .[]
    | ([.steps[]? | select((.name // "") | startswith("Poll for the git-data boot-completion signal"))] | first) as $p
    | "\(.id) \(.name) \(.status) \($p.conclusion // "none") \($p.started_at // "-") \($p.completed_at // "-")"' <<<"$jobs_json" 2>/dev/null)
  for j in "${jobs[@]}"; do
    read -r job_id job_name job_status poll_concl poll_start _ <<<"$j"
    [[ "$job_id" =~ ^[0-9]+$ ]] || _cannot "job id is not numeric in run ${run_id}: ${job_id}"
    if [[ "$job_status" != "completed" ]]; then
      pending=$((pending + 1))
      echo "run ${run_id} ${job_name} (job ${job_id}) is ${job_status} — not yet evaluable"
      continue
    fi
    if [[ "$poll_concl" != "success" && "$poll_concl" != "failure" ]]; then
      unevaluable=$((unevaluable + 1))
      echo "run ${run_id} ${job_name} (job ${job_id}): its poll step did not run (conclusion ${poll_concl}) — not evidence either way"
      continue
    fi
    [[ "$poll_start" =~ ^${ts_re}$ ]] \
      || _cannot "${job_name} (job ${job_id}): the poll step's start time is unreadable (${poll_start})"
    log=$(gh run view --job "$job_id" --repo "$REPO" --log 2>"$ERRF") \
      || _cannot "could not read the log of ${job_name} (job ${job_id}, run ${run_id}): $(gh_err)"
    [[ -n "$log" ]] || _cannot "the log of ${job_name} (job ${job_id}, run ${run_id}) is empty"
    # THE POLL STEP'S OWN OUTPUT. gh prints `<job>\t<step>\t<ts> <text>`; the step column is
    # `UNKNOWN STEP`, so steps are told apart by the runner's `##[group]Run` headers. The
    # region is everything after the first header stamped at or after the poll step's start
    # second, up to the next header. Each line is reduced to its third field, so a tab inside
    # echoed text cannot place a line of its own choosing at the start.
    # STRIP THE BOM ALONGSIDE THE CR, AND IN BASH RATHER THAN IN awk. `gh run view --log` writes
    # a UTF-8 byte-order mark at the start of EVERY step's log section, and the mark lands AFTER
    # the two tab fields — i.e. immediately before the timestamp the awk block below anchors on.
    # Measured on job 106093730126 (run 35516692240): 15 `##[group]Run` headers, 14 of them
    # BOM-prefixed; only the job's first section ("Set up job") is bare, because gh strips the
    # mark from the head of the concatenated stream and not from each section it appends.
    #
    # Without this, `^[0-9]` matched ONLY that first bare header, whose ts is the job start and
    # therefore always < the poll step's start, so `started` never flipped, `region` came back
    # empty, and the probe took the `_cannot` arm on every real log it has ever read — reporting
    # CANNOT ESTABLISH against the exact evidence it exists to read. The mark also shifted
    # `substr(line, 1, 19)` by three bytes, corrupting the ts compare even had a header matched.
    #
    # WHY HERE AND NOT IN THE awk PROGRAM. `sub(/^\357\273\277/, "", line)` beside the tab-field
    # strip also works, and it is NOT a portability problem — that was this change's first
    # rationale and it was wrong. Measured during review on gawk 5.4.1, mawk 1.3.4 and busybox
    # 1.35.0 awk, under both LC_ALL=C and a UTF-8 locale: all three match the three bytes and
    # emit a byte-identical region. POSIX XCU requires `\ddd` in ERE tokens, and two awk programs
    # in this repo already depend on exactly that (scripts/tenant-dpa-register-guard.sh gsub
    # /\002/, plugins/soleur/hooks/browser-snapshot-credential-guard.sh gsub /\001/). Do not
    # cite this comment to "fix" either of those.
    #
    # The bash form is kept on its own merits, which are real but ordinary: it sits beside the
    # \r strip that already establishes this exact pattern one line up, it is one mechanism
    # rather than two for the same normalization, and it clears the mark for EVERY consumer of
    # "$log" rather than only the block that happens to normalize. Pinned by the suite: turning
    # the `//` into a single `/` drives 18 failures, because a real log carries one mark per
    # step section and clearing only the first leaves the poll step's header BOM-prefixed.
    log=${log//$'\r'/}
    log=${log//$'\357\273\277'/}
    region=$(awk -v ps="${poll_start:0:19}" '
      { line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line); ts = substr(line, 1, 19) }
      line ~ /^[0-9][0-9TZ:.-]* ##\[group\]Run / { if (started) exit; if (ts >= ps) { started = 1; next } }
      started { print line }' <<<"$log")
    [[ -n "$region" ]] \
      || _cannot "${job_name} (job ${job_id}, run ${run_id}): could not locate the poll step's output in its log (no ##[group]Run header at or after ${poll_start})"
    mapfile -t verdicts < <(grep -E "^${ts_re} VERDICT=[a-z-]+$" <<<"$region" | sed -E 's/.* VERDICT=//' || true)
    mapfile -t summaries < <(grep -E "^${ts_re} answered=[0-9]+/[0-9]+ last_class=[a-z0-9_-]+$" <<<"$region" \
                             | sed -E 's/.* answered=([0-9]+)\/([0-9]+) .*/\1 \2/' || true)
    polls_answered=$(grep -cE "^${ts_re} poll [0-9]+/[0-9]+: answered" <<<"$region" || true)
    if [[ "${#verdicts[@]}" -eq 0 ]]; then
      _cannot "${job_name} (job ${job_id}, run ${run_id}): the poll step ran (conclusion ${poll_concl}) but its output carries no VERDICT line — it failed before polling (read its log: a missing-token or anchor refusal) or gh's log format changed"
    fi
    [[ "${#verdicts[@]}" -eq 1 ]] || _cannot "${job_name} (job ${job_id}) logged ${#verdicts[@]} VERDICT lines in its poll step's output; the library emits exactly one"
    verdict="${verdicts[0]}"
    case "$verdict" in
      received|silent|unreadable|refused-no-anchor) : ;;
      *) _cannot "${job_name} (job ${job_id}) logged a VERDICT outside the library's vocabulary: ${verdict}" ;;
    esac
    where="${job_name} (job ${job_id}, run ${run_id}, https://github.com/${REPO}/actions/runs/${run_id})"
    if [[ "$verdict" == "refused-no-anchor" ]]; then
      echo "FAIL: ${where} — the boot poll REFUSED to run (no usable run anchor), so it never read. That is a workflow wiring fault in the post-fix code." >&2
      exit 1
    fi
    # Every other verdict carries exactly one summary line.
    [[ "${#summaries[@]}" -eq 1 ]] || _cannot "${job_name} (job ${job_id}) logged ${#summaries[@]} answered= summaries alongside VERDICT=${verdict}"
    read -r answered max_polls <<<"${summaries[0]}"
    # The summary must agree with the per-poll lines it summarises. A forged summary cannot
    # also forge the right number of `poll k/M: answered` lines from the real loop.
    [[ "$answered" == "$polls_answered" ]] \
      || _cannot "${where}: the summary says answered=${answered} but the step's output has ${polls_answered} answered poll line(s)"
    if [[ "$verdict" == "received" ]] && (( answered < 1 )); then
      _cannot "${where}: VERDICT=received with answered=0 — the log contradicts the library's contract"
    fi
    if (( answered >= 1 )); then
      echo "PASS: ${where} — the boot poll's read path ANSWERED (${answered}/${max_polls} reads answered, VERDICT=${verdict})."
      [[ "$verdict" != "received" ]] && echo "      Note: VERDICT=${verdict} is a separate fault (host or a late read) that the job already reported; it is not #8178."
      exit 0
    fi
    echo "FAIL: ${where} — the boot poll never got an answer (answered=0/${max_polls}, VERDICT=${verdict})." >&2
    echo "      The post-fix read path still cannot read the git-data boot signal. Read that job's per-poll lines: each names rc and class (credentials-rejected / source-not-in-connection / transport / reader-refusal / credentials-absent / reader-exit-1)." >&2
    exit 1
  done
done

if (( pending > 0 )); then
  _not_yet "${pending} post-merge git-data job(s) still running; ${unevaluable} completed without their poll step running"
fi
_not_yet "${#run_ids[@]} post-merge dispatch(es) since ${merged_at}, none with a git-data job whose poll step ran (${unevaluable} git-data job(s) without one)"
