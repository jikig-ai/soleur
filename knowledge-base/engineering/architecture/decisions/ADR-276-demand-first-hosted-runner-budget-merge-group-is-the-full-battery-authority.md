---
title: "Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority"
status: proposed
date: 2026-10-07
issue: 9721
related_adrs: [ADR-032, ADR-181, ADR-183, ADR-216, ADR-217, ADR-242, ADR-262, ADR-270]
tags: [ci, github-actions, runners, merge-queue, cost]
brand_survival_threshold: aggregate pattern
---

# ADR-276: Hosted-runner demand is cut before supply is raised; merge_group (and the push-main deploy arm) stay the full-battery authority

## Status

**Proposed, 2026-10-07 (#9721).** The file `status:` moves `proposed` to `adopting` when the CTO
approves this ADR in a review comment on a PR that edits the line, and no stage PR that changes CI
behaviour (S2, S3, S4; S1 exempt below) may merge while it reads `proposed`. On that edit the guardrail decisions (1, 2,
3, 6, 7 and 8) become `adopting`; Decisions 4 and 5 stay the proposed shape of stages 3 and 4. It moves
`adopting` to `accepted` when S5 closes with a post-merge census for S2 and S3, or with each closed by
its entry gate or stop rule. Every stage that changes CI behaviour (S2, S3, S4) takes effect only when
its own PR appends a dated `## Amendment` to this ADR (Decision 3(g)), so finishing one stage cannot
activate an unrun one. S1 is exempt from 3(c), (d) and (g): its smoke gate is a PR-only, non-required
job that runs unconditionally off `pull_request` and fails open, it moves no required context or merge
authority, and its rollback is a revert (a variable would add a switch to guard 1.8% of minutes); S1's
census script changes no CI behaviour and S5 is decision-only, so neither appends an amendment. Nothing
in this ADR provisions infrastructure.

> **Superseded 2026-10-08 (S1, #9727):** two clauses above no longer describe S1. The smoke gate does not run
> "unconditionally off `pull_request`": `smoke-relevance` runs on every pull request and `smoke-tests` is now
> path-conditional (it skips only when the gate succeeded and answered `false`). The exemption from 3(c), (d)
> and (g) rests instead on: a non-required context, a fail-open gate, rollback by revert, and a saving bounded
> at about 134 job-minutes per 6 h (1.8%). And "neither appends an amendment" was a floor, not a ban: S1 appends
> the amendment at the end of this file. The original sentences are kept above unedited.

### Stage status

Append-only: a change is a dated line added under the table (`- 2026-MM-DD S3 amended`, `- ... S3
live`), never an edit of an earlier row, so the current state of a stage is the last dated line that
names it (the column below is the initial state only). `live` means the stage's dark-launch exit
criterion passed (ADR file statuses use `active`, so the stage word differs on purpose).

| Stage | Lever | Tracking issue | Initial state |
|---|---|---|---|
| S1 | Census script and secret-scan smoke path gate | #9727 | not started |
| S2 | Push-run dedupe | #9512 | not started |
| S3 | Draft PRs run the light set | #9728 | not started |
| S4 | PR runs select the affected suites | #9729 | not started |
| S5 | Re-measure, then CodeQL, Code Quality and supply decision | #9730 | not started |

- 2026-10-08 S1 amended (#9727; see `## Amendment 2026-10-08 (S1, #9727)

Status stays `proposed`. This amendment is non-activating: it records what stage 1 delivered, corrects two Status clauses (see the dated note under Status) and activates no other stage.

- **Delivered.** S1 added `scripts/ci-demand-census.sh` (the measurement authority Decision 7 names) and a path gate for the secret-scan `smoke-tests` matrix: a new fail-open `smoke-relevance` job lists the pull request's files through the API, and the ten smoke cases run only when the PR touches a file they exercise, or when the changed-file list cannot be fully determined. Both are additive. No required context, merge authority or non-`pull_request` behaviour moved.
- **Dropped, with the residual named.** The weekly smoke arm the issue allowed for was dropped, because no document claims weekly smoke coverage: every "weekly" in the secret-scanning runbook means the gitleaks scan, which the smoke job never fed. No schedule arm and no kill-switch variable were added; the rollback is a revert. The accepted residual: the smoke matrix was also, in effect, a canary for runner-image and tool drift (it ran on every PR); it now runs on PRs that touch a subject path, so that drift surfaces at the next such PR rather than within hours. S5 (#9730) re-measures and decides whether a `schedule` arm is worth its cost.
- **Decision 3(e).** The numeric target: the secret-scan smoke-related minutes per pull-request run (the `smoke` stem plus the `smoke-relevance` stem) fall by at least 80% against the baseline window (`smoke` = 134.4 job-minutes over 33 runs that ran it, 2.92 per completed secret-scan PR run). Measure over at least 48 hours or 100 pull-request runs, and report the run-weighted hit share next to the skip share: the criterion holds while the share of runs touching a subject path stays at or under about 17%. An escape rate is not directly observable (a skipped case has no verdict), so none is reported; the skip share and the hit share stand in for it, and nothing in the required set depends on either.
- **How to measure.** From a developer shell with `gh auth` (the script refuses to run in CI): `end=$(date -u -d '-1 hour' +%Y-%m-%dT%H:00:00Z); start=$(date -u -d '-7 hours' +%Y-%m-%dT%H:00:00Z); bash scripts/ci-demand-census.sh --start "$start" --end "$end" --summary > /var/tmp/ci-census.txt`. `--end` is exclusive, the window is fetched in one-hour sub-windows (the runs listing is capped at 1,000 results), a 6 h window takes about 15 minutes, and a self-check failure exits 3 with no total. Add `--workflow secret-scan.yml` to cost one workflow only (the call stage evidence uses).
- **How to roll back.** Restore the original condition on `smoke-tests` (`if: github.event_name == 'pull_request'`), delete its `needs: smoke-relevance`, delete the `smoke-relevance` job and restore the secret-scan row of `scripts/pr-fanout-ledger.txt` to 6 jobs; or revert the pull request, which does all of that. Deleting only the `if:` line would run the matrix on push, `merge_group` and `schedule` as well.
- **Evidence ownership.** The baseline census is attached to #9727 before merge. The post-merge census (`--workflow secret-scan.yml`, a closed window after merge) and the first no-subject-path pull request that shows `smoke-relevance` green and the `smoke (...)` row skipped are collected by S2 (#9512) as its first step, and the `S1 live` line is appended by the S2 amendment (or by a docs commit if S2 does not follow). `Closes #9727` closes the issue at merge, before that evidence exists; the evidence is therefore owned by S2, not by the S1 session.
- **Required rollup.** A job-level skipped matrix job posts one check named `smoke (${{ matrix.case }})`, not ten, so promoting any `smoke (*)` context to required (the deferred rollup recorded under ADR-032) needs an always-run aggregator that treats that skipped row as success by name (Decision 3(a)); until then `skipped` is never read as green by anything in the required set.
- **Corrections.** Decision 5 cites `--print-selection` as #9307; the merged pull request is #9306 (#9307 is the open issue). The census `STEM` rows carry `runs_ran`, `runs_skipped` and `runs_runnerless`; a queue-cancelled or superseded run is counted in `runs_runnerless`, not `runs_skipped`.
