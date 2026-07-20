---
title: "My fixture set had a direction, and both mutation batteries were blind to the other one"
date: 2026-07-21
category: test-failures
module: scripts/lint-infra-no-human-steps.py
issue: 6771
pr: 6779
tags: [mutation-testing, vacuous-tests, sentinel, false-negative, measurement]
---

# Learning: a fixture set has a DIRECTION, and a battery only measures the mutations you thought of

## Problem

#6771 reported a false positive in `scripts/lint-infra-no-human-steps.py`, the CI sentinel
enforcing `hr-no-ssh-fallback-in-runbooks`: the workflow FILENAME
`apply-web-platform-infra.yml` satisfied the `-target … appl(y|ies|ied)` imperative,
because the hyphen after `apply` is a word boundary. Prose correctly documenting a
CI-driven apply was being flagged as prescribing a human step.

Two fixes were available. The plan promoted **option 2** (anchor the imperative on
`terraform|tofu|opentofu` adjacency) to primary on a measured "~45 latent false positives
removed" vs option 1's ~8.

I shipped both. Then measured. Then had to revert one, re-derive the sweep, correct my own
evidence, and add six more fixtures — because **the same defect shape recurred three
times in one PR, in three different places, and my own mutation battery reported green
each time.**

## The recurring shape

> A test suite whose fixtures all point one direction is structurally incapable of seeing
> the other direction. Every mutation you invent lands in the direction you were already
> thinking about.

Three instances, same session:

**1. The anchor had no test at all.** Battery #1 reported all-caught. But reverting the
tool anchor left all 38 cases green — because both positive controls contained the literal
word `terraform`, so neither could distinguish "requires a tool token" from "doesn't".
Adding F9 (a positive control with NO tool token) made the mutation RED.

**2. The plan's "45 false positives" was a classification claim, not a count.** Reading all
41 lines the anchor removes: **12 are unambiguously genuine human-run steps (~29%)**,
including one in a *runbook* — the exact artifact class the rule polices. The anchor
silences them because the natural phrasing omits the tool name:
"a FULL operator apply", "must be applied LOCALLY by the operator", "type `yes`
interactively". The CTO ruled option 1 only.

**3. Then option 1 had the mirror defect, and battery #2 was green too.** Three review
agents converged: **every filename fixture asserted exit 0.** The suite could only see
neutralization being too WEAK. A genuine step whose only imperative lives inside the
filename went silent:

    you ssh into the web host and run the
    `cryptsetup-unlock-workspaces.yml` playbook by hand

`cryptsetup` was the only imperative; the filename ate it. Pre-PR `exit 1`, as-merged
`exit 0`. On a runbook.

And when I added F10/F11 to close it, **two over-reach mutations STILL survived** — because
F10/F11 carry strong-actor signals, so the suppression short-circuits before the char class
ever runs. Only F14/F15 (weak actor → neutralization actually executes) could pin it.

## Solution

- Keep filename neutralization (option 1). Revert the tool anchor. Record the ruling in
  ADR-132 with the asymmetry that decides it: **a false positive costs an author one
  auditable carve-out; a false negative costs a non-technical operator an un-automated
  infra step.** Resolve toward sensitivity. A carve-out is auditable; a silent miss is not,
  so the anchor would have *converted* visible carve-outs into invisible misses.
- Add `STRONG_ACTOR_RE`: a line with unambiguous human agency (`by hand`, `manually`,
  `yourself`, `your laptop`, `ssh into`, `<role> runs`) is scanned RAW so a filename can
  still supply its imperative. Bare `operator`/`you`/`founder` excluded — those weak
  mentions ARE the #6771 false positive. Measured cost: **zero** (identical flagged set;
  its one corpus hit is under `/archive/`, already excluded).
- Six fixtures, each mutation-verified on a sandbox copy: F10/F11 (strong-actor), F12
  (multiplicity — kills `count=1`), F13 (uppercase extension), F14 (weak actor,
  UNBACKTICKED — kills a widened char class), F15 (weak actor, imperative inside a span —
  kills span-eating).

## Key Insight

**Ask of every fixture set: what SET does this quantify over, and does any fixture sit on
the other side of the transform?** For a suppression/neutralization/redaction, that means
at minimum one fixture proving it suppresses AND one proving it does not over-suppress —
drawn from the *same* syntactic trigger, not a disjoint pool. Written as a standing rule
for this file: *every neutralization fixture must be paired with a positive control
containing the same trigger that still flags.*

Two corollaries that cost real time here:

- **A line-level probe is not a valid measurement for a file-scoped scanner.** I "confirmed"
  a genuine-silenced-step citation by extracting the single line to a temp file. That
  strips it from its `lint-infra-ignore` region and flips the verdict — the line was never
  a member of the 41. The CTO confirmed it the same flawed way. Verify in context, always.
- **Measure every arm on ONE tree.** I computed the neutralization-only arm on the
  post-sweep tree and the baseline on the pre-sweep tree, which made a pure-removal
  transform appear to ADD hits — impossible, and the tell I initially missed. The plan's
  own task 4.3 warned about exactly this.

And the meta-lesson: **N artifacts agreeing is ONE artifact when they share a premise.**
The plan, the commit message, the ADR draft and the CTO ruling all inherited my
line-extraction error. Convergence is evidence only when the errors are independent.

## Session Errors

- **Arms measured across inconsistent trees** — neutralization-only computed on the
  post-sweep tree, baseline/both on pre-sweep, making the attribution (8/46) wrong.
  **Prevention:** re-derive all comparison arms from one `git archive origin/main` tree in
  a single command; treat any "pure-removal transform added hits" result as proof of a
  broken measurement, not a finding.
- **Carve-out sweep validated under semantics that were later reverted** — 7 regions swept
  under the anchored script; 5 of 6 files re-flagged after the revert. **Prevention:** a
  sweep derived from a behavior change must be re-derived whenever that behavior changes;
  never carry a sweep across a revert.
- **Evidence verified by line extraction rather than in context** — see Key Insight.
  **Prevention:** for any file-scoped scanner, run the probe on the WHOLE file.
- **Mutation battery #1 green while the tool anchor had zero tests.** **Prevention:** for
  each behavior the diff adds, name the mutation that removes it and confirm RED; if you
  cannot construct one, the behavior is untested.
- **Mutation battery #2 green while the over-reach direction was untested.** **Prevention:**
  the direction rule in Key Insight.
- **First over-reach fixtures could not pin over-reach** — F10/F11 short-circuit on the
  strong-actor path before the char class runs. **Prevention:** when a fix adds a guard
  clause, check which fixtures actually REACH the code under test; a fixture that
  short-circuits earlier pins nothing about the later branch.
- **`comm` fed unsorted input** — `LC_ALL` unpinned, so the 4.3 subset check was
  untrustworthy despite printing `0`. **Prevention:** `export LC_ALL=C` before any
  `sort`/`comm` set-diff (already an AGENTS rule; it recurred anyway).
- **`grep "blunts nothing"` returned 0 because the phrase wrapped across a line break** —
  I nearly concluded the overclaim was already gone. **Prevention:** for prose assertions,
  match whitespace-tolerantly (`\s+`) or grep a single distinctive word; this is the
  `cq-assert-anchor-not-bare-token` class applied to line wrapping.
- **`… | grep … | sed … || echo "STILL GREEN"` never fired** because `sed` exits 0, so a
  mutation probe could not distinguish caught from uncaught. **Prevention:** report the
  runner's own summary line (`tail -1`) rather than relying on pipeline exit status.
- **Background task notification reported "exit code 0" while the suite was still running**
  — the wrapper's exit, not the suite's; rc file absent and 3 processes alive.
  **Prevention:** always write `echo $? > <rcfile>` and read THAT; documented in
  `work/SKILL.md` and it still recurred.
- **`test-all.sh` foreground timed out at the 10-minute harness ceiling** under load 45
  with three sibling worktrees running the same suite; required killing the surviving
  child before relaunch. **Prevention:** launch long suites detached with an explicit rc
  file from the start; check `pgrep` + `/proc/<pid>/cwd` for sibling contention before
  diagnosing a failure as real.
- **Timing measured at 1-second granularity under load 33** produced a spurious 1.68×
  ratio. **Prevention:** benchmark in-process with interleaved arms and min-of-N; never
  wall-clock a shared machine.
- **`git stash list` tripped the guardrail** (a vestigial probe in a compound command).
  **Prevention:** the hook denies the whole Bash call — keep probes out of commands that
  must succeed.
- **Push rejected post-rebase**; resolved with `--force-with-lease` after verifying the
  three remote commits were patch-id-identical to their rebased twins. **Prevention:**
  verify patch-ids before any force-push rather than assuming.
- **The ADR tripped its own sentinel twice** after adding evidence prose. **Prevention:**
  expected for this file; wrap quoted corpus evidence in a rationale-bearing ignore region
  and verify the region is load-bearing (strip it, confirm it flags).
- **Plan's `MIN_CASES=37` arithmetic predated task 1.8b** (8 cases enumerated, not 7).
  **Prevention:** derive counts from the as-written file, never from plan prose.
- *(Forwarded)* `iac-plan-write-guard` blocked the plan Write; the plan tripped its own
  linter 4×; background review-agent reports didn't surface on two attempts.
- *(Environmental, one-off)* scratchpad ENOSPC surfaced by a review agent.

## Related

- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the direct predecessor;
  this session is a second, independent instance of the same class, which argues the
  disposition should be a mechanical gate rather than another learning.
- [[2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable]]
  — fixture SHAPE as a coverage axis; here the missing axis was fixture DIRECTION.
- ADR-132 — the binding detection-semantics ruling.
- #6806 — residual false-positive classes (negation context, possessive actors, extension
  boundary, `mount`-as-noun).
