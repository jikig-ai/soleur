# Ready-run wait and recovery (ADR-276 S3, #9728)

Read this when a draft PR is readied (ship Phase 6 step 6, merge-pr 5.1, drain-prs), or when the Phase 7 poll, `monitor-pr-checks.sh` or `triage-prs.sh` reports a ready run that is `stalled`, `no-run` or `awaiting-approval`. The resolver is `plugins/soleur/scripts/ci-head-verdict.sh`; `--help` prints its contract.

## Why

With `CI_DRAFT_LIGHT` on, a draft PR's `test` check is red on purpose (`draft: full battery owed at ready`): the full battery runs on `ready_for_review`. Arming auto-merge before that ready run exists is the silent-forever case, so the order is fixed: read the ready-event count `K`, mark ready, wait for a ci.yml run created after the ready event, and only then arm. The block is one shell command so `K` is read before the ready call and a failed read readies nothing.

```bash
K=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" ready-count PR_NUMBER) && gh pr ready PR_NUMBER \
  && bash "${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" wait-ready-run PR_NUMBER --before-count "$K"
```

Run it as one Bash call with `timeout: 330000`: the wait budget is 300 s plus the API calls. A tool timeout kills it before it prints its marker and leaves the PR readied with the arm decision unrecorded; then run `ci-head-verdict.sh verdict PR_NUMBER`. `gh pr ready` needs a user token: `GITHUB_TOKEN` cannot ready a PR.

## Outcomes (last stdout line `SOLEUR_CI_WAIT_READY_RUN result=… reason=…`, plus the exit code)

| Outcome | Meaning | Do |
|---|---|---|
| exit 0, `run-created` | a ready run exists | arm: `gh pr merge --squash --auto` |
| exit 0, `not-applicable` | this repo has no `draft-light` job in its default-branch ci.yml | arm, exactly as before S3 |
| `ready-count` exits 3 (no number) | nothing was readied; the PR is still a draft | fix the read (rate limit?) and re-run the whole block; never `--undo` |
| exit 1, `no-ready-event` | the ready event was not visible within the budget | `gh pr view PR_NUMBER --json isDraft`: still a draft, re-run the whole block; readied, run `ci-head-verdict.sh verdict PR_NUMBER` |
| exit 1, `no-run` | readied, but no ci.yml run followed | `gh pr ready --undo PR_NUMBER`, then re-run the WHOLE block (it re-reads `K`; a stale `K` makes the wait pass on the first ready event) |
| exit 1, `awaiting-approval` | a fork's run needs a maintainer to click "Approve and run" in the Actions tab | approve it; `--undo` and ready again do not clear an approval gate |
| exit 3, `api-error` | a read failed on the last poll: the ready state is UNKNOWN | run `ci-head-verdict.sh verdict PR_NUMBER`; do not undo anything on a guess |

Never arm on any non-zero outcome: report "readied but unarmed" with the marker line.

## Reading a ready PR's red `test` (Phase 7 poll, monitor, triage, admin-merge)

`ci-head-verdict.sh verdict` answers one of six states: `n/a` (never readied, a draft now, or a repo without the mechanism), `full-decided`, `pending-full`, `no-run`, `stalled`, `awaiting-approval`. `pending-full` and `no-run` are PENDING, not a failure; `stalled` (120 minutes past the ready event with no deciding run) and `awaiting-approval` end the watch with no fix loop. On `full-decided` and `n/a` the red row is a real failure. Exit 3 prints `state=error`, which is none of the six: readers keep today's reading, so an outage never turns a real red `test` into a wait. `stalled` can also describe a slow healthy run: open the Actions tab before undoing, because `gh pr ready --undo` then ready cancels an in-flight ready run and starts the battery again.

When diagnosing a failed `test` on a ready PR, take the run id from the verdict marker's `run=` (the deciding run), not from `gh run list --commit`: a ready head carries the draft run too, and its only red text is the by-design line.
