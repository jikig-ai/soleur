# Dark-cost re-measurement (S4 PR C, Ref #9729)

Measured 2026-10-16 from the GitHub Actions API. Units: **billed minutes** = `max(1, ceil(seconds / 60))` per executed
`pr-selection` job (a skipped job bills 0); "per executed job" divides by executed jobs, never by runs.

## Window 1: the ADR-276 sample window (2026-10-14T23:24:00Z to 2026-10-15T09:20:12Z)

Command: `gh api --paginate "repos/jikig-ai/soleur/actions/workflows/ci.yml/runs?event=pull_request&created=<window>&per_page=100"`,
then `gh api --paginate "repos/jikig-ai/soleur/actions/runs/<id>/jobs?per_page=100&filter=latest"` for each run.

| Quantity | Value |
|---|---|
| `ci.yml` pull_request runs in the window | 44 |
| `pr-selection` conclusions | 34 success, 8 cancelled, 2 skipped |
| executed jobs (everything but skipped) | 42 |
| billed minutes (cancelled jobs counted by started to completed) | 54 |
| billed minutes per executed job | **1.29** |

Stage reached, read from the `SOLEUR_PR_SELECTION` notice on each of the 34 successful jobs
(`gh api repos/jikig-ai/soleur/check-runs/<job id>/annotations`): **10 reached stage 2, 24 stopped at stage 1**.
The 10 stage-2 notices: 6 `selector_timeout` at `sel_s=90` (censored at the 90 s budget) and 4 `affected` at `sel_s` 63, 63, 81 and 86;
none of them is a measurement of the cold wall time (a censored pass is a lower bound).

This reproduces the ADR amendment's figures (1.29 billed minutes per executed job, 10 of 34 annotated runs reaching stage 2).

## Pull request run counts per day (ci.yml, event=pull_request)

2026-10-09 354, 10-10 183, 10-11 383, 10-12 387, 10-13 251, 10-14 264: mean 303.7, so "about 300 PR runs per day" holds.
Command per day: `.../ci.yml/runs?event=pull_request&created=<day>T00:00:00Z..<day>T23:59:59Z&per_page=1` and read `total_count`.

## Window 2: after the Q1 follow-up merge (2026-10-15T17:50:38Z to 2026-10-16T09:40:00Z, queried 2026-10-16T16:00Z)

47 `ci.yml` pull_request runs listed by the API at the query time: `pr-selection` **44 skipped, 1 success**, and 2 runs that never created the
job (cancelled before any job; run ids 38871053197 and 38871069022). So **44 of the 45 runs that created the job were skipped**.
The one success is run 38781446320, created 2026-10-15T17:56:10Z (head branch `feat-one-shot-argv-bearer-pr-c-inngest-probes`), six minutes
after the merge: its merge ref predated the merge, so it ran the pre-Q1 workflow. With `CI_PR_AFFECTED` unset the dark job now costs 0 billed
minutes. (An earlier read of this same window listed 28 runs and 27 skipped. The window's end is fixed, so it was not an open window still
filling; the cause of the difference was not established, which is why the query time is part of the figure and the 47 run ids with their
`pr-selection` conclusions are committed beside this receipt as `window2-runs.tsv`. The 09:40:00Z end is the end of the original sample, kept for
comparability.)

## Oldest run record probed

Per-day counts of `ci.yml` runs (any event), read 2026-10-16T16:00Z: 2026-06-01 **160** runs, 2026-03-15 **1** run (the oldest date probed
that still lists a run). Earlier dates were not probed, so the retention is not inferred from a setting and not bounded here.

## Organization variables and AC9c (read 2026-10-16 with `scripts/ci-pr-affected-preactivation.sh`)

- `CI_PR_AFFECTED`: `gh api repos/jikig-ai/soleur/actions/variables/CI_PR_AFFECTED` is HTTP 404 and the variable list read is HTTP 200: **absent**.
- Organization variables shared with the repository: `gh api repos/jikig-ai/soleur/actions/organization-variables` is HTTP 200 with `total_count` **0**. No organization-admin credential was needed: this repo-scoped read lists exactly the organization variables that resolve through `vars`.
- AC9c (the first non-draft doc-only pull request after the Q1 follow-up merge, `pr-selection` skipped, battery green): **observed** on PR 10423
  (run 38867973491) and PR 10428 (run 38870968301), both created 2026-10-16 and both doc-only (every file under the documentation tree or a root
  `*.md`): `pr-selection` `skipped`, `test-bun`, every `test-scripts (n/8)` and `test-scripts-heavy (n/3)` shard and the aggregate `test` `success`
  (the matrix `test-webplat (n/2)` legs are skipped by `draft-light` only on drafts; both PRs were non-draft). This is an observation, not proof, and it is TRUE BY CONSTRUCTION while the variable is unset: the dark job is skipped exactly when the variable is empty, so a skipped `pr-selection` on a doc-only PR says nothing about the active state.
