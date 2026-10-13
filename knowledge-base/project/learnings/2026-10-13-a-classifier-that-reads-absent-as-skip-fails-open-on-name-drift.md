---
title: "A classifier that reads ABSENT as SKIP fails open on name drift, and regex pins cannot see a gate's wiring"
date: 2026-10-13
category: workflow-patterns
tags: [github-actions, gate-design, fail-closed, mutation-testing, executed-tests, git-data, review-panel]
issue: 10166
pr: 10184
synced_to: [review]
---

# Learning: a classifier that reads ABSENT as SKIP fails open on name drift, and regex pins cannot see a gate's wiring

## Problem

The git-data cutover flip gate `d6_replace_stale` matched a step NAME (`rotate confirm token`) that is
unconditional and concludes success on every non-rotate target, so a plain replace or a plan-only rotate
discharged it (#10166). The fix is a last-step marker (`Rotate completed (d6 marker)`), a lib that classifies
`gh run view --json jobs` and scans the 100 newest dispatch runs newest-first, a gate rewrite and parity pins.
It was planned with a CTO ruling and a 5-seat plan review, built TDD, and still took a 12-seat panel, a 5-seat
fix round and a verification pass to close 16 unique defects, none of them in the happy path.

## Solution

- **Absent is not skipped.** The first classifier read an apply step that was ABSENT (a rename: run
  38140050880, the real failed rotate the plan cites, carries the pre-#10155 name) or LISTED WITH NO CONCLUSION
  (cancelled mid-apply) as "nothing happened", so the guarantee "a failed newest rotate blocks" was false for
  that very run, and the plan called the shape "harmless". Now only an explicit `skipped` apply is a skip;
  absent, `unknown` (listed, no conclusion), `failure` or `cancelled` on a job that did not succeed read
  `rotate_failed`. A `sc()` helper returns `absent` / `unknown` / the conclusion so the three states stay apart.
- **Execute the gate's own block, don't regex it.** Five regex pins plus a six-mutant battery could not see a
  case-arm body replaced by `:`, a `--event` selector changed, the `--jq` field order swapped, or `d6=` reassigned
  after the scan: every mutant stayed green. The fix extracts the real `run:` block from the parsed workflow and
  runs it under bash against a modelled `gh` that REFUSES any other full argv (exit 64) and passes the list through
  the real `--jq` filter, with ten cases (each verdict, a non-numeric id, a failed list) and a CONTROL case that
  changes one selector in the block and asserts the refusal flips the verdict. Every deletion (arm bodies,
  `--event`, `--limit`, field order, the id sanitiser, the remedies, the bare-stamp guard) was then shown to red on
  a backed-up mutated copy.
- **A not-completed run that does not list the job is in flight**, not skipped in favour of an older stamp; a
  non-numeric id never reaches `gh` and is never echoed; the gate prints only a validated numeric `d6_run`.
- **`3<&0` does not protect an id stream.** The comment claimed reading ids on fd 3 stops children consuming
  them; `3<&0` duplicates the descriptor and both share one file offset (measured: a child `cat` drains it). What
  protects the stream is `</dev/null` on the `gh` call, which now has its own mutation row (M5).
- **A re-run does not hide the failure from the record it replaces.** `gh run view` defaults to the LATEST attempt,
  so a re-run that completes stamps (and re-executes the destructive apply), and one refused at the plan gate reads
  `skip` and unmasks an older stamp. The remedy, runbook and plan said three different things until the history
  seat ran `gh run view 38280522229 --json attempt` and read it off a real run.

## Key Insight

A fail-closed gate is only as closed as its treatment of the states it did not enumerate: `absent` and `unknown`
are not `skipped`, and the one a rename or a cancellation produces is the one that must read as "in doubt". And
a gate's WIRING (which arm runs what, which selector it sends, what it does after the scan) is a different
artifact from its logic: regex pins over the workflow text pin spellings, so the pin that bites is running the
real block against a stub that refuses anything but the exact calls and having a control case prove the refusal
changes the verdict. Two process corollaries from the same session: a commit message that says "pinned by executed
cases" is a claim the verification pass will measure (it marked the commit NOT CLOSED until each remedy had its
own assertion), and an unmeasured sentence about a platform's behaviour (re-run semantics, what an in-progress run
lists) must be either measured or marked inferred where it is written.

## Session Errors

1. **The plan-prescribed marker `run:` text carried a colon-space in an unquoted YAML scalar and broke the workflow parse.**
   — Recovery: reworded the echo; actionlint found it. — **Prevention:** run `actionlint` (or a `yaml` parse) on a
   workflow edit before the first commit, and never copy a plan's shell/YAML line without parsing it.
2. **Four `decision-challenges.md` rows failed the technical-ruling gate** (a parenthetical between the date and the
   colon; a CPO ruling classed `technical`). — Recovery: moved the parenthetical after the colon, reclassed the
   brand row `taste`. — **Prevention:** run `technical-ruling-gate.sh --branch` right after the plan subagent returns.
3. **The plan called a failed rotate recorded under a legacy step name "harmless" and the classifier read it `skip`.**
   — Recovery: explicit-`skipped`-only skip, `absent`/`unknown` fail toward `rotate_failed`. — **Prevention:** replay
   the classifier over the real runs the plan cites (`gh run view <id> --json jobs`) before writing "harmless".
4. **A comment claimed `3<&0` isolates the id stream; it shares the offset.** — Recovery: reworded, added M5. —
   **Prevention:** a comment that names a mechanism's guarantee gets its falsifying one-liner run before commit.
5. **Gate pins could not see case-arm bodies, selectors or post-scan edits; the first escaper/census regex pins were
   ad hoc.** — Recovery: executed-block test with a refusing stub and a control, `escapeRe`, census regex mirrored. —
   **Prevention:** for a workflow gate, execute the extracted run-block against a stub that refuses unknown argv, and
   mutation-check each wiring edit on a backed-up copy.
6. **The remedy said a re-run "does not clear" the block; a successful re-run reads stamped.** — Recovery: measured
   with `gh`, reworded in gate, runbook, plan. — **Prevention:** measure platform-semantics sentences (`gh run view
   --attempt`) before writing them, or mark them inferred.
7. **My second fix commit's message over-claimed pinning.** — Recovery: added a `has:` assertion per remedy and a case
   for the bare-stamp guard, each shown to red. — **Prevention:** write the commit message after running the
   deletion for each thing it says is pinned.
8. **A first stub-argv comparison carried a junk line, and a Python patch batch aborted on an assertion with the
   second patch unapplied until a test failed.** — Recovery: replaced with a positional-slice equality; reran the
   skipped patch. — **Prevention:** a scripted multi-edit prints the changed anchors; treat a green rerun identical to
   the previous one as un-run.
9. **semgrep segfaults on any `.ts` file here (void), a foreground verification passed the 120 s tool limit, and a
   Monitor expired with no events.** — Recovery: shellcheck/actionlint/manual substitutes, background run with a
   result file. — **Prevention:** record a void SAST as void, run slow batteries in the background from the start,
   and wait on a result file rather than a pattern match.
10. **The parity-test floor comment said "exact" while main already carried 2 rows of slack (278 vs 276).** —
    Recovery: kept the delta arithmetic and said so in the comment. — **Prevention:** `grep -cE '^\s*test\('` before
    trusting a floor comment.
11. **The planning subagent spawned the CTO three times for three design forks, over the pipeline's two-spawn cap
    (recorded as `cto_spawns=3`).** — Recovery: none needed, the forks were genuine; the cap then blocked further
    CTO consults in review. — **Prevention:** brief the planning subagent to batch design forks into ONE CTO spawn.
12. **Report-only seats can detach HEAD; I checked `git branch --show-current` for empty after every panel.** —
    Recovery: none needed (stayed attached). — **Prevention:** keep the empty-branch guard before every commit that
    follows a panel.

## Related

- `knowledge-base/project/learnings/2026-10-12-a-mode-decided-in-one-step-and-re-derived-in-the-next-is-two-sources-of-truth.md`
  (the #10155 backstop whose item 13 is this defect).
- `knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md` (skip-vs-fail
  defaults, the class re-committed in the first classifier).
- `knowledge-base/project/learnings/2026-10-11-a-fake-that-ignores-its-selectors-lets-every-selector-mutation-pass.md`
  (why the modelled `gh` must refuse any other argv).

## Tags

category: workflow-patterns
module: infra/ci (git-data cutover flip gate)
