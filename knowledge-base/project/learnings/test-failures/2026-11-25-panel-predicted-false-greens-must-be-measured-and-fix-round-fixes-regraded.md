---
title: Measure every panel-predicted false green, then grade the fixes as a new change
date: 2026-11-25
category: test-failures
module: apps/web-platform/e2e
tags: [playwright, e2e, mutation-testing, review, fix-round, review-evidence]
issue: 12605
pr: 13017
---

# Learning: measure every panel-predicted false green, then grade the fixes as a new change

## Problem

PR #13017 adds a phone-width (390x844) Playwright spec for the Scope Grants web-egress disclosures. The review
panel predicted that six ways of breaking the page would still pass. They were: the ON block removed, the switch
pushed off-card, a zero-height paragraph, a disclosure hidden in a `display:none` child, the unknown-org notice
removed, and the pointer branch disabled. Each prediction read as plausible. Some were not.

## Solution

- **Measure before ruling.** A probe script (`lead-probe.py`) applied each predicted mutation to the tree, ran
  the spec, then restored with `git restore --source=HEAD`. It refused to start on a dirty tree. All six
  measured GREEN. Five were real gaps (mutation rows 16-20); the sixth, the disabled pointer branch (row 22), is
  green by design because that branch is not load-bearing for the null-org fixtures (ruling R2-r). The CTO rulings
  R1-r to R5-r were made on those measured results, not on the reviewers' arguments.
- **Grade the fixes as a new change.** Fix round 1 seated test-design, security, code-quality and SAST against
  the fix range only. They found three new gaps inside the fixes, plus one finding that falls inside an earlier ruling:
  - A paragraph could hide part of its text in a `display:none` child. Fixed by comparing normalized `innerText`.
  - The switch could be covered by another element. Fixed with a `click({ trial: true })`.
  - A surface box could cross the card edge while its text stayed inside. Fixed with an element-box bound.
  - Vertical clipping was the fourth finding. It is the ruling-F8 Non-Goal, recorded before the panel ran, so it
    stays a stated residual rather than a gap in the fixes.

  Every new row was measured: rows 23 to 25 RED, row 26 GREEN by design. Across all 26 rows, 23 are RED, row 12
  is a control that must pass, and rows 22 and 26 are green by design. Rows that the earlier addendum had carried
  forward without running were re-run.
- **The verifier found the docblock claimed more than the check does.** `innerText` still includes text hidden
  by `sr-only`, opacity or a transparent colour. The docblock now lists that under "Not checked".

## Key Insight

A reviewer's "this would pass" is a hypothesis that costs about one Playwright run to settle, so settle it
before a ruling is made on it. And a fix for a false green is new test code with its own false greens. In this
PR, three of the four fix-round findings were gaps inside the panel fixes; the fourth was the known F8 residual.

## Session Errors

1. **`git rev-parse` with two revisions failed.** Recovery: separate calls. **Prevention:** one revision per call.
2. **The guardrails hook blocked `gh issue create --body-file "$VAR"`.** Recovery: a literal path. **Prevention:** already hook-enforced; pass literal paths.
3. **The probe's dev server rewrote `apps/web-platform/tsconfig.json`.** Recovery: restored after each run. **Prevention:** the probe restores every touched path in a `finally` and refuses to run on a dirty tree.
4. **The first draft said the `is_jti_denied` 404 fails safe; it fails open.** Recovery: a mock handler. **Prevention:** run the 404 path before describing it.
5. **The vertical-clip checks gave a reproduced false green.** Recovery: removed under ruling F8. **Prevention:** run each check's mutation before keeping the check.
6. **A disclosure hidden on phones passed every planned check, and the OFF test's steps could not run in the order written.** Recovery: plan fixed at review. **Prevention:** give every required check a mutation row that isolates it.
7. **The paragraph filter was unproven on the real page.** Recovery: mutation rows 13 and 14 ran on the real page. **Prevention:** never accept a static-markup trial as a real-page result.
8. **`git push` printed a Dependabot notice for the default branch.** Recovery: none needed; this branch did not cause it. **Prevention:** none (informational).
9. **An interrupted probe left `page.tsx` mutated.** Recovery: `git restore --source=HEAD --worktree`. **Prevention:** restore in `finally`, and check the tree is clean before and after each row.
10. **The scratchpad was wiped mid-session.** Recovery: rewrote `pw.sh` and `lead-probe.py`. **Prevention:** keep reused probe scripts under the git-dir, not under `/tmp`.
11. **`pw.sh` missed the totals line behind an ANSI `\x1B[1A` cursor-up code.** Recovery: strip regex widened to `[0-9;]*[A-Za-z]`. **Prevention:** strip every CSI sequence, not just colour codes.
12. **The fix-round brief was first written to the worktree root.** Recovery: deleted, then written under the git-dir. **Prevention:** write briefs to `$(git rev-parse --git-dir)`.
13. **The mock-edit script's anchor wrapped across a line.** Recovery: nothing was written because it asserts before writing; re-ran with the right anchor and a regex for the ruling ids. **Prevention:** keep the assert-before-write pattern for multi-replacement edits.
14. **tsc TS2339: `innerText` on `HTMLElement | SVGElement`.** Recovery: cast to `HTMLElement`. **Prevention:** run tsc on spec edits before running Playwright.
15. **The local dev server failed to start on 3 of 4 attempts.** Recovery: `pw.sh` retries on server-start failure only. **Prevention:** keep the retry limited to server start, and treat CI `e2e` as the gate.
16. **The Review-Evidence `seats=` list was written from memory.** It named performance, data-integrity and agent-native, which never ran, and left out git-history-analyzer and code-simplicity-reviewer. Recovery: counted the `subagent_type` values in the session transcript and edited the comment. **Prevention:** `review-evidence-comment.md` now says to derive `seats=` from the spawned agents' records, never from the roster.
17. **The verifier found the docblock claimed more than the check does.** Recovery: the docblock now lists the `innerText` residuals. **Prevention:** for every "fails when…" sentence in a test docblock, name the mutation that proves it.

## Tags
category: test-failures
module: apps/web-platform/e2e
