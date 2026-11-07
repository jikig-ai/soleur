# Learning: a counts-only census and the checks around it were each narrower than the claim they carried

## Problem

PR #11712 built a passive, secret-gated route that counts (never reads) the shared HOME, plus a trigger script that governs the one authorized production run. A 14-seat review panel and a 3-seat verification round found that almost every control certified something narrower than its name:

- **Bound-path binding:** C8 compared the discharged commit with the served build using `git diff --quiet -- <pathspecs>`. Pathspecs are relative to the current directory, so from `apps/web-platform` the diff returned 0 ("no difference") whatever had changed. The check passed vacuously on an ordinary invocation.
- **Verdict fields:** the headline `trigger_class_nonzero` read `"false"` when all four trigger classes were `inconclusive`; a symlinked class directory and an unlistable `sessions` directory read as zero; `sessions_key` was marked unknown for a directory that was never listed; `other_under_claude` was marked visited by the `sessions` step and read `none_counted` when the scan stopped before the real listing; an unlistable `/root` (the image runs as a non-root user) turned every class into an error, so a mature zero was unreachable.
- **Sinks:** a failed control emitted the synthetic control's counts labelled as the real HOME; a synthetic dry_run looked like a counted trigger class in Sentry.
- **Output validation:** `jq -e` returns the status of the last output, so a body of two JSON documents validated and the raw file was then printed.
- **A reorder regression:** moving a `5*)` arm ahead of the `503` arm turned a definitive pre-scan refusal into "the scan may have run, do not retry".
- **Plan vs ruling:** the plan added a `merge-base --is-ancestor` check that a recorded CTO row explicitly forbade, and it proved nothing (true for every commit of main).

## Solution

- Run every pathspec-based git check from the repository root, assert the pathspecs match files of the served tree, require the script that is running to be the checkout's copy, and make the test fake record the working directory of each git call.
- Give the headline a fourth value and define each verdict by what the scan established: a link, an unlistable directory, a stop in progress and an unvisited class are `unknown`, never zero; mark `visited` only for the classes a step enumerates; skip (and report) a root that exists but cannot be listed.
- Emit a failed control as a refusal record with no class counts; tag every event with `data_source` and keep a synthetic dry_run at info level.
- Validate with `jq -es`, require exactly one document, and print the re-serialised validated value.
- Delete the ancestry check; read the CLO record from the served commit as an exact line; bind the sink and gate files; batch the four findings that touched recorded rulings into one CLO spawn.
- Reviewer-run mutation battery of 23 mutants, with a kill judge that needs vitest's own "Tests N failed" line so a copy that fails to load is not credited as caught.

## Key Insight

A check is only as strong as the weakest dimension it silently inherits from its environment: the current directory, the number of JSON documents, the step that last touched a flag, the label on a synthetic record. When a gate says "these paths are unchanged", ask what makes the path list resolve; when a verdict says "none counted", ask what the scan did NOT look at. Also: a plan deviation from a recorded ruling must be checked against the rulings file before it is built, not after review finds it.

## Session Errors

1. **Bound-path diff run from a subdirectory passed vacuously.** Recovery: cd to the toplevel, non-vacuity `ls-tree` check, cwd-logging test fake. **Prevention:** for any git check that uses pathspecs, the test fake must record the working directory and a row must run the script from a subdirectory.
2. **Headline read `false` over all-`inconclusive` classes.** Recovery: four-state enum, mirrored in both validators and the tests. **Prevention:** derive a run-level verdict from the same enum the per-item verdicts use and add a row where every item is the third state.
3. **Failed control labelled synthetic counts as the real HOME.** Recovery: refusal record without class counts. **Prevention:** an error path must not reuse the success builder with substitute data.
4. **Multi-document body passed `jq -e` and was printed.** Recovery: `jq -es`, `length == 1`, print `jq -c .`. **Prevention:** "printed only if it validates" requires printing the validated value, never the raw file.
5. **A class marked visited by a step that does not enumerate it; unlistable `/root` made every class an error.** Recovery: `own` classes per step; skip unlistable roots. **Prevention:** test each verdict under a truncated scan and under an environment where one candidate root is unreadable (the image user is not root).
6. **Reorder put `5*)` before `503` and regressed an exit code.** Recovery: explicit 503 arm plus tests for 503 with and without the closed shape. **Prevention:** after reordering `case` arms, run a test per status class that the header documents.
7. **Added an ancestry check that a recorded CTO row forbade.** Recovery: deleted it and recorded the conformance in the dissent-round rows. **Prevention:** before adding a check to a governed script, grep the rulings file for "no <that check>".
8. **Sentry re-init after `close()` captured nothing, making "no event leaked" assertions vacuous.** Recovery: init once per file, flush instead of close, positive control. **Prevention:** every "emits nothing" assertion needs a sibling that proves the harness can see an event.
9. **Fake timers also faked `setImmediate`, hanging a test that awaited it.** Recovery: switch to real timers before the real-event-loop turn. **Prevention:** when a test mixes fake timers with an unhandled-rejection probe, restore real timers first.
10. **Closing sentences that promised an action were rejected by the stop hook (twice).** Recovery: end with a `Paused:` sentence that names the single wait. **Prevention:** when waiting on background seats, say so in one `Paused:` line instead of describing the next step.

## Tags
category: logic-errors
module: apps/web-platform/server/home-census.ts, apps/web-platform/scripts/home-census-trigger.sh
