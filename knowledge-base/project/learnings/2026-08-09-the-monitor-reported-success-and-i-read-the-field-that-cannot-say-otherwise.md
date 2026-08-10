---
title: "The monitor reported success, and I read the field that cannot say otherwise"
date: 2026-08-09
category: workflow-issues
tags: [github-actions, continue-on-error, outcome-vs-conclusion, pipefail, censored-data, flaky-harness, monitoring]
symptoms:
  - "A health monitor files no issue for months while its subject is broken"
  - "gh run view --json jobs reports every step success while the run log shows failures"
  - "A timeout produces conclusion=cancelled and every failure-gated step is skipped"
  - "A test runner reports different failing suites on an unchanged tree"
module: CI
component: main_health_monitor
problem_type: silent_failure
resolution_type: code_fix
root_cause: wrong_assumption
severity: high
issue: 7307
---

# The monitor reported success, and I read the field that cannot say otherwise

## Problem

`main-health-monitor.yml` is the repo's only main-branch backstop: run the suite
against `main` every 6h, file a P1 `ci/main-broken` issue when it goes red, close
it when it goes green. It had filed **zero** issues in the four months since it
was created. All three `ci/main-broken` issues that exist were opened by a human.

Three independent defects, two of them silent:

1. **A job timeout is recorded as `cancelled`, never `failure`.** The filer was
   gated on `outcome == 'failure'`, so a timeout filed nothing. 19 of the last
   30 runs ended `cancelled`.
2. **`| tee` discarded the suite's exit code.** A bare `run:` is `bash -e {0}` —
   errexit on, **pipefail off**. A pipeline's status is its last stage and `tee`
   always exits 0, so a RED suite reported `success` and the *closer* then
   auto-closed human-filed trackers. An active green light over a dead alarm.
3. **The infra suites were never covered.** `test-all.sh` gates its nested infra
   runner on a diff against `origin/main`, which on a clean checkout *of* `main`
   is empty — permanently, not incidentally.

## The mistake worth recording

The plan I was implementing contained this sharp edge, in its own words:

> `steps.<id>.outcome` is only readable inside `${{ }}`. `gh run view --json jobs`
> exposes `steps[].conclusion`, which `continue-on-error: true` pins to `success`.

I implemented the mitigation it prescribes (a step mirroring both outcomes to
`$GITHUB_STEP_SUMMARY`) — and then verified my own measurement run by reading
`conclusion` from the API anyway. Every step read `success`, so I reported to the
operator that the suite was green and that the top delivery risk was resolved.

It was not. The same run's log said `263/268 suites passed`, ten `[FAIL]` lines,
and `Process completed with exit code 1` on both steps. `continue-on-error: true`
had pinned `conclusion` to `success` exactly as documented. **The field I chose
to read is structurally incapable of reporting the failure I was checking for.**

That is the same shape as the bug under repair — a channel that cannot express
the state you are asking it about — reproduced by the person repairing it, one
step removed. It is the third instance in this repo of a fix reproducing its own
defect class (see the 2026-08-06 registry-budget learning).

**The check that would have caught it costs nothing:** for any assertion about a
step's success, ask *which field carries that fact, and can it say "no"?* If the
step is `continue-on-error`, `conclusion` cannot. Read the job summary, the
`##[error]Process completed with exit code N` line, or the runner's own terminal
marker (`=== N/M suites passed ===`) — three independent channels, all of which
were present and all of which I skipped.

## Why the existing errexit linter correctly does not cover defect 2

`scripts/lint-workflow-errexit-capture.py` (shipped by #7304 for this exact
family) scans 703 `run:` bodies and reports clean against the pre-fix file. That
is correct, not a gap. Its rule anchors on a `$?` / `${PIPESTATUS[n]}` **read**,
per its own docstring: *"it fires only where the code ITSELF proves the author
expected to handle a failure."* The pre-fix step reads neither — the **workflow
engine** reads the exit code. A linter keyed on the author's intent cannot see a
defect whose consumer is the platform.

Post-fix the code *does* read `${PIPESTATUS[0]}`, so the linter now covers the
regression direction: cases F14/F15b already fire on the "`set -e` above the
read" mutation, which would silently make `rc` always 0 — a false pass, worse
than the original bug. No new gate was built, deliberately: after this PR the
population of the un-linted class is zero, and a rule contradicting its host
gate's documented scope is worse than the prose record.

## Censored data: why the issue's own numbers could not size the fix

The issue reported a 14m49s–15m26s band and asked for a ceiling above it. That
band is **right-censored**: every run over 15m was killed at 15m, so it measures
the old ceiling, not the suite. As true duration rises, slow runs leave the
sample and the surviving max is dragged toward the limit — manufacturing a curve
indistinguishable from a real one. The plan withdrew its own v1 growth estimate
for exactly this reason.

The fix is not a better estimate but a different procedure: raise the ceiling to
something absurd, dispatch, and *measure*. Because the workflow already existed
on the default branch, `gh workflow run --ref <branch>` dispatches the **modified**
file, so every acceptance criterion was verifiable pre-merge.

**And the first measurement was still not a valid sample.** Run 1 measured
14m15s — but four suites were aborting or self-skipping for want of gitleaks and
likec4, so it understated the suite. Run 2, with the toolchain installed,
measured 20m48s. The ×1.5 rule crosses its own 30-minute floor between those two
numbers, so the second sample changed the answer. I had predicted in writing that
it could not.

## A monitor's environment must be the union of the shards it replaces

The deeper finding. This workflow runs `TEST_GROUP=all` — every CI shard's
suites — in a runner carrying **no** shard's toolchain. Three suites hard-ABORT
without gitleaks; `c4-model-freshness` self-skips without likec4, and a self-skip
is printed as PASS. So its coverage was already partly vacuous, independent of
the reporting defects. Fixing "the monitor cannot report" without fixing "the
monitor's environment cannot run what it claims to run" would have produced a
loud monitor reporting on a subset it never named.

Generalisation: **when a job aggregates other jobs' work, enumerate what those
jobs install, not just what they run.** A tool that is absent turns an assertion
into a silent pass, and the aggregate reports green over the gap.

## Different failure sets on an unchanged tree is a harness defect

Once the monitor could report, it filed a P1 (#7374) — correct in mechanism,
wrong in cause. `run-registered-suites.sh` runs 92 suites at `-P min(nproc,6)`,
i.e. `-P 4` on a 4-core runner. Across six executions of the same set on an
unchanged tree, two failed, naming **three different suites**; the same set
passed sequentially in CI and at `-P 6` on 16 cores. The sharpest evidence came
from a single job: the nested run reported `91 passed, 1 failed` and the infra
step `92 passed, 0 failed`, minutes apart.

At ~33% an armed monitor files a spurious P1 every third run, which is worse than
the silence being removed — so the monitor now runs the suites sequentially,
matching the only configuration proven stable. Tracked for a real fix in #7376.

**Scoping that override to the infra step was not enough**, and the reason
generalises: when the branch diff touches `infra/`, `TEST_GROUP=all` *also* runs
the runner nested inside the tests step. On `main` that nested path is inert —
because the diff is empty, which **is** defect C. Depending on a defect's
mechanism to suppress a flake is not a property worth having, so the override is
workflow-scoped.

## Key Insight

Three of this session's errors are the same error at different altitudes: I
trusted a channel that could not express the state I was asking about.

- `conclusion` under `continue-on-error` cannot report failure.
- A capture file shared by two steps cannot say *which* step failed — the filed
  issue's "Failure summary" was 30 lines of the passing step's `PASS` output.
- A verification harness whose expected string had drifted from the code reported
  its mutation control as passing, when both baseline and mutant were producing
  the same absence.

The last one is the most instructive: the mutation control existed *specifically*
to prove non-vacuity, and it went vacuous itself when the string it grepped for
changed. A control is only a control while the thing it discriminates on is still
the thing under test — re-prove discrimination whenever the subject moves, not
just when the control is written.

## Session Errors

1. **Read `conclusion` instead of `outcome`** and reported a red suite as green
   to the operator. Corrected by reading the run log's exit codes and terminal
   markers. The plan documented this exact trap; implementing its mitigation is
   not the same as using it.
   **Prevention:** for any assertion about a step's success, name the field that
   carries the fact and ask whether it CAN say "no". Under `continue-on-error`,
   `conclusion` cannot.
2. **`pkill -f 'run-registered-suites'` matched its own command line** and killed
   the invoking shell (exit 144), silently dropping the edit that was chained
   after it. The repo documents this trap verbatim. Use a bracket class
   (`'run-registered[-]suites'`) or match on PID.
   **Prevention:** never chain a destructive command and a file edit in one Bash
   call — the edit is lost if the command kills the shell.
3. **A double-quoted string inside a double-quoted C4 description** terminated it
   early; likec4 then reported `Could not resolve reference to ElementKind named
   'no'` at a line I had not edited. Regeneration is what caught it — the parity
   test alone would not have.
   **Prevention:** run `regenerate-c4-model.sh` after ANY `.c4` prose edit; the
   parity test checks counts, not that the source still parses.
4. **The verification harness went stale against its own subject** — I changed the
   fallback string and the harness still grepped the old one, so its mutation
   control "passed" by an absence that was already true of the baseline.
   **Prevention:** a control is only a control while the thing it discriminates
   on is still the thing under test; re-prove discrimination whenever the subject
   moves, not only when the control is written.
5. **Predicted that a second measurement could not change the derived ceiling**,
   on the grounds that the floors dominated. It did change it, because the
   toolchain fix altered which suites actually ran. The prediction was reasoning
   about the rule instead of measuring the input.
   **Prevention:** when a change alters WHICH work runs, the prior measurement is
   not a sample of the new configuration — re-measure rather than reasoning about
   whether the derivation rule would move.
6. **Two regressions introduced and caught only by the measurement dispatch**, not
   by review: four stale embedded counts in `model.c4`, and a new monitor name
   missing from `NON_INNGEST_MONITORS`. Both were counted-artifact drift of the
   kind the repo already warns about; neither was visible to `tsc`, actionlint,
   or the touched-file test loop.
   **Prevention:** after adding any resource/workflow that a parity gate counts,
   run that gate before pushing — `c4-count-parity`, `function-registry-count`.
7. **Removed the workflow-scoped `JOBS` while fixing a review finding and never
   re-added it to the steps**, so the infra runner reverted to `-P 4` and filed a
   spurious P1 (#7386). The monitor caught it; my brand-new guard suite did not.
   **Prevention:** when a review fix MOVES a setting rather than deleting it,
   assert the destination in the same commit — and if a guard exists for that
   file, the assertion belongs in the guard, not only in the diff.
8. **The bare repo reported every worktree as bare**, blocking `worktree-manager.sh
   draft-pr`. `ensure_bare_config`'s non-bare guard treats "`git_dir` is a `.git`
   directory" as proof of a normal clone, which this bare-in-`.git` layout
   satisfies, so its `core.bare` surgery never ran and the shared value bled into
   every linked worktree.
   **Prevention:** the guard should consult `core.bare` rather than the gitdir's
   shape. Not filed — it is a different subsystem and did not recur once the
   shared key was unset.
9. **Read an empty log as evidence.** `gh run view --log` hit a TLS handshake
   timeout and wrote a 155-byte error file; `grep -c` over it returned 0 and I
   reported "0 exit codes, both steps green".
   **Prevention:** assert the artifact is non-trivial (`wc -c`, or that the
   expected terminal marker is present) before drawing a conclusion from a
   grep count of zero — absence of evidence renders identically to evidence of
   absence.
10. **Counted my own guard's message as a failure.** `grep -c '\[FAIL\]'` over the
    suite log matched assertion (8)'s text, which necessarily contains the
    literal `[FAIL]`, and I reported a failure that did not exist.
    **Prevention:** anchor progress greps on the runner's line FORMAT
    (`^\[FAIL\] `), never a bare token — the same rule the diff applies to the
    workflow's own marker.

## Review phase: the reasoning was sound and pinned by nothing

Eleven agents produced eleven findings. The two P1s were both mine, and neither
was a reasoning error — each was a case of reading one file and not the file next
to it.

**The marker.** The failure classifier greped `[FAIL]`. `run-registered-suites.sh`'s
own header says, verbatim: *"a failing suite prints `RED <path>`, not `FAIL`. A
`grep FAIL` over this runner's log returns zero hits on a failing run and reads as
clean — measured 2026-08-04 (#7220)."* So an infra-only failure rendered "Run did
not complete … usually a timeout" over a real `RED` line — the phantom this PR
exists to remove, in the one path this PR adds. It could not surface in any branch
run, because `test-all.sh` *does* emit `[FAIL]` and the branch always ran both.

**The warm measurement.** Every branch run executes the 92 infra suites TWICE —
the branch diff touches `infra/`, so `TEST_GROUP=all` fires the nested runner
first and the standalone step then runs warm. I noticed the nested run INFLATES
the tests figure and called leaving it "the safe direction", and did not notice it
DEFLATES the infra figure, which is the unsafe direction. On `main` the standalone
step is the only run: cold. Generalisation: **when the same work runs twice in one
job, ask which of your measurements is the second one.**

### The finding that mattered most was not a bug

Three agents converged on it independently: a sandbox battery mutated the shipped
workflow 28 ways and **24 survived every existing gate** — including
`closer if: → always()`, which auto-closes the tracker while main is red, i.e.
defect B's consequence restored. The workflow's reasoning was fine. Nothing
executed it.

Two corollaries worth carrying:

- **A cited mitigation is a claim to test.** The plan asserted the `PIPESTATUS`
  idiom was "already guarded by `lint-workflow-errexit-capture.py` F14/F15b". It is
  not: that linter short-circuits on `if not state[cmd_pos]: continue` when errexit
  was already clear at the command, which is exactly this idiom's shape. Measured —
  moving `set -e` above the read (rc always 0, a silent false pass, strictly worse
  than the original bug) leaves it reporting `clean`.
- **A guard must pin the property, not the neighbourhood.** After the review I moved
  `JOBS` off workflow scope (node-gyp reads it as `make -j`) and did not re-add it to
  the steps. The monitor caught it and filed a spurious P1 — but my brand-new guard
  suite did not, because it asserted nothing about `JOBS`. The fix is an assertion
  that checks it *per-step*, mutation-proven. A guard that misses its own regression
  is measuring less than it appears to.

### And one claim I made twice and had to retract twice

I told the operator "every infra flake was `-P 4` on a 4-core runner; `-P 6` on 16
cores was clean", and wrote that into #7376. A later local run failed at `-P 6` on
16 cores — under load 8.42 with a sibling suite running. The variable is
**contention**, not the `-P` value. Both statements were made from a sample that
happened to be consistent with them; neither was tested against a case that could
falsify it. Tally at the end: 8 executions, 4 failed, 6 distinct suites, every
failure on a saturated machine.
