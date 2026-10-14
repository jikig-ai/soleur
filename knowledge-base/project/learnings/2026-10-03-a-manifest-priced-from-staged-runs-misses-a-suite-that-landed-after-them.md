# Learning: a shard manifest priced from staged runs misses a suite that landed after them

## Problem

Bumping the light `test-scripts` matrix from K=7 to K=8 (#9307) needed a wholesale manifest
regeneration from five green main runs. Two things went wrong with the INPUTS, not the code:

1. Main moved while the first pricing PR was open (#9416 added `scripts/infra-drift-autoclose`), so the
   TSV pair conflicted and the merge hook refused to auto-sync it. The branch had to be reset to
   `origin/main` and regenerated, never hand-merged.
2. The K=8 regeneration used the five runs staged earlier. A newer main run already carried a timing for
   the new suite (11.7 s), so the committed pair priced it at the floor and put one leg near 607 s while
   the runbook, `ci.yml` and the plan all said "every leg under 600 s". The architecture review seat
   found it; a dry-run on the five newest runs gave legs 566.1-578.2 s (spread 12.1 s) with 0 suites at
   the floor.

## Solution

Regenerate from the five NEWEST green main runs at write time, and require `0 at floor` in the
dry-run summary (`545 tabled (545 measured, 0 at floor …)`). Single-source the figures: the runbook
topology row owns the range, `ci.yml` points at it instead of restating it.

## Key Insight

A figure written into several files before the final inputs are chosen is a figure that will be
rewritten in every one of them. Choose the inputs first, then write the number once.

## Session Errors

1. **`git merge --ff-only` ran on the checked-out branch, not `main`** — Recovery: harmless refusal; switched via detach. **Prevention:** name the target ref (`git fetch origin main:main` or `git -C <worktree-holding-main>`) rather than relying on the current branch.
2. **`gh run download -p 'name-[0-9]'` matched nothing and an empty `grep` read like "label absent"** — Recovery: download by exact name (`-n`). **Prevention:** assert the downloaded file count before grepping (`find … | wc -l` must equal the expected legs).
3. **Chained `gh pr create && gh pr merge` was blocked by the review-evidence hook, and an `ps | awk` poll was blocked as self-matching** — Recovery: split the commands; used a file/marker poll. **Prevention:** run the trailer script and the push as separate commands before any merge call (the hook text already says so).
4. **Main moved mid-flight and the manifest was priced from stale inputs, twice** — Recovery: reset own branch to `origin/main`, regenerate wholesale. **Prevention:** runbook regeneration note (re-list the newest runs right before `--write`; require `0 at floor`).
5. **The same K=8 range was hand-written in `ci.yml` and the runbook before re-pricing** — Recovery: rewrote both; `ci.yml` now points at the runbook. **Prevention:** single-source rationale at the owning artifact (work skill, "single-source the rationale").
6. **A "report-only" review seat ran `git checkout --detach` in the shared worktree** — Recovery: noticed the empty `git branch --show-current`, `git switch` back. **Prevention:** review Sharp Edges bullet (check the branch after the panel returns).
7. **`battery-owed.sh` ran before the branch was pushed (UNDECIDABLE)** — Recovery: pushed, re-ran. **Prevention:** push before asking CI-state questions.
8. **The go-skill route decision (`emit-decision.sh`) was skipped** — Recovery: emitted late. **Prevention:** none beyond the skill text; one-off.
9. **A K-derived literal in a suite that reads K from `ci.yml` broke on the bump, and my targeted set never ran that suite** — `regenerate-shard-manifest.test.sh` fixture Q asserted a floor of 350 ms, the median of `{50, 100..700}`, which is only true at 7 incumbent legs. Plan, 7-seat review and the guard suites I chose all missed it; CI's `test-scripts (4/8)` caught it (62/63). Recovery: derive the expected floor from N in the fixture. **Prevention:** when a change alters a value a suite derives from (`ci.yml` leg count), `git grep -lE 'regenerate-shard-manifest|suite-shard-legs|suite-durations'` across `plugins/soleur/test scripts tests` and run every hit before pushing — the literal grep for `7`/`K=7` cannot find a value computed from 7.

## Tags
category: workflow-patterns
module: ci-test-scripts-sharding
