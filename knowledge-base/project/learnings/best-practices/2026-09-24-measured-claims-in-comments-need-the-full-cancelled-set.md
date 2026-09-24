---
title: "Measured claims written into comments must be re-derived across the FULL cancelled-run set, not a one-vs-one pair"
date: 2026-09-24
issue: 8688
pr: 8731
tags: [measurement-parity, ci-observability, comment-accuracy, review-catch, best-practices]
category: best-practices
---

# A one-cancelled-vs-one-green comparison over-reads the data

## Problem

While fixing #8688 (infra-validation `deploy-script-tests` cancelling at its 27-min
ceiling), the first-pass step comments were written from a **single** cancelled run
(35976102327) compared against a **single** green run (35952634647). Written into
`.github/workflows/infra-validation.yml`, that produced four claims that did not
survive re-derivation across all five cancelled runs:

- "ownership … 80 s on the cancelled runs — the same whole-runner docker slowdown
  class" — actual cancelled-run values were **33–80 s**, every one inside the step's
  own 25–100 s green range. The step showed **no** slowdown; the comment invented
  one by reading the top of the range as the range.
- "cutover … 184–206 s on the cancelled runs" — actual **78–206 s**; one run was at
  its green max. Reported the top of the range as the range again.
- "the suite's apt fixture sits outside its internal `timeout -k 10 480` bound" —
  the apt line is inside `drive.sh`, which runs **inside** the bounded `docker run`.
  The real uncovered gap was the host-side legs (`docker info`, `docker rm -f`,
  fixture build) — a true claim existed, and the written one was a different, false
  claim that reached the same conclusion.
- "8 minutes keeps the inner bound firing first" — step ceiling 480 s from *step
  start* vs inner 480 s from *docker-run start*: the inner deadline is always later,
  so the step cap always fires first. Correct mechanism: a 10-min bound leaves the
  inner bound room to fire first on container stalls while still capping the
  unbounded host-side legs.

Three independent review seats (git-history, pattern-recognition, code-simplicity)
each caught the same defects by pulling per-step durations for **all five**
cancelled runs via `gh api repos/<o>/<r>/actions/runs/<id>/jobs`. Fixed inline.

## Solution

When a comment will carry a measured range or a mechanism claim:

1. **Measure the full set the claim names.** If the comment says "the cancelled
   runs", pull every cancelled run — not the first one that matches the narrative.
   A range written from n=1 of 5 is a point dressed as a range.
2. **Check the value against the step's OWN envelope before calling it a slowdown.**
   "80 s" read as degradation; against a 25–100 s green range it is the null result.
   A value inside the green range is evidence of no slowdown — say so or drop the
   clause.
3. **Verify mechanism claims against the code path, not the narrative.** "Fixture
   sits outside the bound" was true of a *different* gap (the host-side legs); the
   grep that settles it is one command (`grep -n "apt-get\|timeout\|docker run"
   <suite>` and check which side of the wrapper each lands on).
4. **For ordering claims ("X fires first"), write down both clocks.** Equal
   durations with different start times are never a tie — the earlier-starting
   clock wins. If inner-first ordering is the goal, size the outer bound > inner
   bound + preamble, and say that.

## Key Insight

The file's own convention is "durations stated as ranges on named run sets" — and
the convention is exactly what makes a wrong measured claim expensive: the next
re-derivation reads these comments as ground truth. A comment that over-reads the
data becomes a false premise the next sizing inherits. The review panel caught it
because it measured the same set the comment named; the defect was written because
the author measured a subset and generalized.

## Prevention

- Before writing a `N–M s` range into a comment, run the per-step API pull for the
  whole named run set (`gh api …/runs/<id>/jobs` per run id) and compute the range
  from every member, not from the run you already had open.
- For "same slowdown class as <step>" claims, compare each step's cancelled values
  against ITS OWN green range — a class claim needs the step outside its envelope,
  not merely elevated.
- For inner/outer timeout ordering, state both start points and both durations in
  the reasoning before picking the value.

## Session Errors

1. Planning subagent had no Skill/Task tool — plan/deepen ran inline; disclosed as
   `Reviewed-Coverage: sequential-fallback`. **Prevention:** inherent to this
   harness path; the disclosure convention already covers it.
2. *(forwarded)* One failed plan edit (replace target not found); resolved by
   re-reading the file. **Prevention:** re-read the current bytes before editing a
   file another phase wrote.
3. *(forwarded)* Early plan draft attributed some cancels to later steps; corrected
   after per-step API inspection showed the rehearsal step `cancelled` in flight on
   all four. **Prevention:** same root as this learning — pull per-step API data
   for every run the claim names before writing it.
4. *(forwarded)* markdownlint caught 2 issues pre-commit; fixed.
   **Prevention:** run the linter on the artifact before the commit that carries it.
5. Plan's flag-based awk for the job-block bound count had its exit pattern
   ungated on `flag` — fired at `push:` (line 29), returned 0 lines.
   **Prevention:** when a plan hands you a verbatim extraction command, run it on
   a small input first; a 0-row result from a "count the keys" command is a smell,
   not a count.
6. Four measured/mechanism claims in the first-pass comments over-read a
   one-vs-one comparison (the subject of this learning). **Prevention:** the
   checklist above.
7. `gh issue create` denied by the milestone hook. **Prevention:** include
   `--milestone` on first invocation for this repo.
8. session-state.md recorded pre-rebase commit SHAs that went stale on rebase.
   **Prevention:** record SHAs after the last history-rewriting step, or record
   branch-relative references.
