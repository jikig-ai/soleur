# Learning: a guard's vocabulary was widened without its census, and prose was scoped narrower than the claims it falsified

## Problem

PR #10341 (Ref #9729) gated the dark `pr-selection` job on `vars.CI_PR_AFFECTED != ''` and stage 2 of its driver on the switch being exactly `on`. The behaviour change was small; the review rounds found the same two structural defects three times each.

1. **A new read of an input was added to the guard vocabulary and the census of readers was not widened.** The existing `prcensus` counted only `needs.pr-selection` references. The new switch is read from `vars`, and a step-level `if: vars.CI_PR_AFFECTED == 'on'` on a gated job's test step (or `toJSON(needs)`, `needs.*.result`, `format('{0}', needs)`, a dynamic `vars[...]` index) changes which work runs while the job still concludes `success`. Round 1 added a second census; four fix-round-1 seats then showed it was case-sensitive, walked only `jobs`, and had three of four regex alternatives with no mutant. Round 2 made it case-insensitive over the whole document with one mutant per shape class. The verifier still found whitespace spellings (`needs . pr-selection`, `needs ['pr-selection']`) that Actions accepts and the first census missed, and one regex arm that was fully redundant (its three mutants were killed by a different arm).
2. **Prose was scoped narrower than the claims it falsified.** The ADR kept bullets that the PR made false ("merging it skips no job", "Re-run all jobs re-executes `pr-selection`", a measured-cost figure) without superseding them; `switch_off` was described as the off-switch reason when it appears only for doc-only diffs that pass the paths cap (a code diff keeps its stage-1 reason, so the off switch is read from `switch=`); and the cost figures cited at plan time (1.07 min per run, 1 of 11, 124 runs per day) did not survive a re-derivation (1.29 billed minutes per executed job, 10 of 34 annotated runs reach stage 2, about 300 runs per day).
3. **Probes and mutants were counted that killed nothing.** A masked-pair mutant (gate bypassed AND the conjunct removed) was killed by its bypass half; aggregator probes p24, p24b, p24c and p25 were not kills; `y-vars-job-env` edited a step env, not a job env.
4. **A pre-existing defect in the failure-diagnosis block of `ship` and `merge-pr`**: the `jq` read `detailsUrl`, a field `gh pr checks --json` does not have ("Unknown JSON field"), and `merge-pr` called `gh pr checks` without the PR number.

## Solution

- When a PR adds a read of an input, widen the census of readers in the same commit: case-insensitive (Actions context, property and function names are case-insensitive), whitespace-tolerant around `.` and `[`, over the whole parsed document (not just `jobs`), and with at least one mutant per shape class AND one per regex arm whose removal would otherwise be masked by another arm. Verify "no arm is redundant" by deleting each arm and running the suite.
- Run the sibling-spelling probe by hand once: write the read five ways (`toJson`, lowercase, whitespace, dynamic index, `format('{0}', ctx)`) as a step-level `if:` in a sandbox copy and confirm each tags.
- When a PR falsifies a sentence in a long-lived document, grep the claim's SUBJECT (not its phrasing) across the document and supersede every hit with a dated note; append, never overwrite, a dated record.
- Re-derive every measured figure with a command at the granularity you will claim it (per executed job vs per run, the sample's end time), and state the units in the sentence.
- Count a mutant or probe only if removing the guard it targets fails exactly that row; drop the rest, and record that an equivalent mutant is equivalent rather than inventing a kill.
- `gh pr checks <number> --json name,state,bucket,description,link`; Actions checks carry an empty `description`, so print `link`.

## Key Insight

A guard that is widened without its census is a guard whose coverage claim is only true of the vocabulary it was written with, and a note that is scoped to what the author edited is false of everything else it touches. The remedy for both is the same: enumerate the spellings and the consumers from the other side (what can the platform parse, which sentences assert the old fact), then pin each with a row that fails when the guard is removed.

## Session Errors

1. **Planner found the brief's cold/warm `sel_s` measurement via `workflow_dispatch` infeasible** (the job is skipped off `pull_request` and the driver exits `not_pr`). Recovery: recorded as decision row D3 and ruled to take the measurement in the PR C replay. **Prevention:** a plan that names a measurement mechanism checks the trigger can reach it before promising it.
2. **Stale or unmeasured figures restated in the ADR.** Recovery: re-derived from `gh run list` and job data. **Prevention:** run the measuring command before writing the figure, state units and the sample window.
3. **ADR bullets falsified but not superseded.** Recovery: dated supersession notes. **Prevention:** grep the claim's subject across the ADR before closing the edit.
4. **Census scope narrower than the guard vocabulary** (three review rounds). Recovery: second census, case-insensitive, whole document, per-shape mutants. **Prevention:** see Solution; widen the census in the commit that adds the read.
5. **Non-kill mutants and probes counted** (masked pair, p24*/p25, mislabeled `y-vars-job-env`). Recovery: dropped or relabelled, floors re-derived from the run. **Prevention:** run each mutant against the pristine tree minus the guard and require the named row to fail.
6. **`ship`/`merge-pr` failure-diagnosis `jq` used a non-existent field.** Recovery: fixed to `link`, `<number>` added. **Prevention:** run the diagnosis command once against a real PR before shipping it in a skill.
7. **A mutation rerun in a sandbox was void** (a sandbox is not a git repo, so the suite saw 178 cases below its 228 floor). Recovery: reran in the real tree. **Prevention:** `git init -q && git add -A` inside a sandbox before running a suite that reads git state.
8. **`test-all-affected.test.sh` timed out or lost a watchdog case under load 12-24** in three runs, a different case each time (`tg4`, `th4b`); never confirmed green in a quiet tree. Recovery: none yet; the branch does not touch that suite or `test-all.sh`. **Prevention:** run it when the host is idle, or in CI.
9. **Two `pipeline-tally.sh incr` calls ran from the primary checkout** (a parallel tool call started there) and polluted that checkout's per-branch ledger by one seat and one agent round. Recovery: redone in the worktree. **Prevention:** never place a tally call in a parallel batch with a `cd`; run it after `cd <worktree> &&` in the same command.
10. **A history seat claimed `repos/.../actions/organization-variables` was not the org endpoint.** It is GitHub's "List repository organization variables"; kept and documented (including that the org-wide list needs an org admin and returned 403). **Prevention:** falsify a reviewer's API claim with one `gh api` call before acting on it.
11. **The ADR said an organization variable "would shadow" the repository one.** GitHub precedence is environment, then repository, then organization. Recovery: reworded. **Prevention:** a precedence claim names its source.

## Tags

category: workflow-issues
module: ci, ci-pr-selection, adr-276
