# Learning: a section-only fast runner is blind to cross-section state, and five review seats shared one wrong premise

## Problem

Fixing the S4 observation-window probe (tracker #10865): `jq --argjson` of a 700 KB files page failed at the 131,072-byte per-argument limit (`MAX_ARG_STRLEN`), the error was hidden by `2>/dev/null`, and the sweep could not finish inside the 15-minute sweeper job. The fix (stdin projection, bounded-parallel reads, a read budget, a `rate_limit` guard, progress lines) landed with 60 probe mutants. Three things went wrong on the way, each green at the point it happened.

## Solution and Key Insight

1. **A fast runner that cuts a suite down to one section cannot see what another section put on disk.** To iterate quickly I built a section-only runner for the `ratchet observation window` rows of `plugins/soleur/test/ci-pr-affected-replay.test.sh` (about 6 s with a row filter against about 20 min for the file). I added `"$GHFIX"/ERR4*RL_*` to `ow_write`'s cleanup `rm -f`. The earlier "read failures" section creates an `ERR403RL_` stub fixture that a *later* section (`row_rate_limit`) still relies on, so my glob deleted it. `row_rate_limit` stayed green on the real SUT for the wrong reason (a stub miss also retries three times) and its mutant `rate-limit-not-retried` survived: 469 of 470. Every row of my section was green, 107 of 107; only the full file showed it. The pattern was also redundant: the existing leading-`*` glob already matched my `actions_runs_6001` markers. Cleanup globs in a shared harness helper must be scoped to what that helper's own section creates.
2. **Five review seats converged on a premise none of them measured.** Architecture, history, code-quality, performance and security all reported the quota guard (`need = 2*runs + 5*PRs + 200`) as a permanent livelock "at 56+ distinct PRs". The history seat's proxy was the 123 PRs merged since the window opened. The probe reads the *oldest 250 runs*, which belong to **4** PRs (measured with one `gh api` loop), so `need` is about 740 against about 580 spent: tight on a shared 1,000/h token, not a livelock. Convergence of agents sharing a model is one reviewer. The same measurement also found that `pull_request` run listings with `created=`/`event=` filters are capped at exactly 1,000 results, so the oldest-first prefix moves forward over time (recorded on #11306).
3. **Real defects came from the same panel and the plan's own numbers.** The facts phase (about 35 serial reads at 1.6 to 2 s) shared the 300 s read budget with a read phase of about 258 s, so a cut sweep read zero PR facts and was NOT YET every night. It got its own allowance (`SOAK_FACTS_BUDGET_S`). An empty `head_branch` collapsed under `IFS=$'\t'` and shifted every later field (reproduced: exit 3).

## Session Errors

1. **Probe runs timed out with no output (two 14-minute and 115 s runs).** I ran the probe under `| tail` and a short `timeout`, which buffered everything. Recovery: stream to a file, run detached under a Monitor. Prevention: the PR itself adds stderr phase lines; for any long diagnostic run use a file and a Monitor from the first attempt.
2. **Two python patch scripts applied nothing** (a quoting typo; the second pass hit an assert on a `$'…'`-form anchor). The unchanged mutant count (41) was the tell. Recovery: re-read the exact file text, resend. Prevention: after a scripted multi-edit assert the artifact changed (already in `work/SKILL.md`).
3. **My cleanup glob deleted another section's fixture** (above). Recovery: removed the redundant pattern, re-ran the full file. Prevention: `references/work-test-harness-sharp-edges.md` bullet (routed below).
4. **A compound `git commit … && bash -c "…$PWD…" &` call was blocked by the commit-target hook.** Recovery: commit in its own call with a literal path, launch the detached run separately. Prevention: never put a detached launcher in the same Bash call as a `git commit`.
5. **Accepted a seat-shared premise as a P1 until measured.** Recovery: measured before acting. Prevention: the premise-measurement rule already in `review/SKILL.md` ("a converged panel finding built on a premise you supplied is not independent evidence").
6. **Stop-hook flags on closing sentences naming a future action.** Recovery: end a waiting turn with `Paused: …`.
7. **Forwarded from the plan phase:** a plan-review dispositions script died on an assertion after one commit had gone out (re-run applied the edits); a tracking-issue filing was first blocked for lacking a justification line.
8. **A `cd` into the archived spec directory left the session cwd there.** Recovery: absolute paths.

## Tags
category: test-failures
module: followthroughs, ci-pr-affected-replay suite
