---
title: "Fixture cannot distinguish the cases it claims"
summary: "A test row passes for the wrong reason when its fixture collapses two cases or fails a later clause; discriminating needs inputs that differ only on the clause under test."
status: open
opened_on: "2026-10-24"
tags: [fixtures, mutation-testing, vacuity, guards]
evidence:
  - knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md
  - knowledge-base/project/learnings/2026-08-13-my-guard-passed-through-the-whole-regression-because-its-fixture-predated-the-widening.md
  - knowledge-base/project/learnings/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md
  - knowledge-base/project/learnings/2026-10-12-a-red-row-backstopped-by-a-later-clause-proves-nothing.md
  - knowledge-base/project/learnings/2026-10-13-a-guard-that-parses-a-fragment-passes-the-negation-and-my-first-arm-did-not-discriminate.md
  - knowledge-base/project/learnings/2026-09-10-i-graded-lines-when-the-unit-was-the-command.md
required_reading: false
---
## Root cause

A fixture instantiates one point in the space of inputs the code accepts. When that point makes
two behaviours produce the same output, every assertion built on it inherits the blindness: sibling
directories hide a swapped prefix order, a stacked mount of one device hides head versus tail, and a
fixture written before a matcher was widened never occupies the newly admitted region. A row can also
turn red through a later clause of a conjunct chain, so deleting the clause it names changes nothing.
Predicates graded per line instead of per command, or over a fragment of a declaration, pass the
negation of the property they guard.

## Fix

Each discriminating row feeds an input that satisfies every clause except the named one, then proves
the row by deleting or reverting that clause and watching it go red. Fixtures get a topology in which
the two candidate behaviours disagree (nested instead of sibling, distinct devices instead of one).
A change that widens a matcher, allowlist or regex adds a fixture inside the newly admitted region in
the same commit. Predicates are pinned to the whole declaration, graded per command, and a crashed
predicate is scored as unresolved rather than as a kill.

## Evidence

- knowledge-base/project/learnings/2026-08-13-the-fixture-shape-decided-what-the-assertion-could-possibly-catch.md
- knowledge-base/project/learnings/2026-08-13-my-guard-passed-through-the-whole-regression-because-its-fixture-predated-the-widening.md
- knowledge-base/project/learnings/2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill-and-the-fixture-stacked-x-on-x.md
- knowledge-base/project/learnings/2026-10-12-a-red-row-backstopped-by-a-later-clause-proves-nothing.md
- knowledge-base/project/learnings/2026-10-13-a-guard-that-parses-a-fragment-passes-the-negation-and-my-first-arm-did-not-discriminate.md
- knowledge-base/project/learnings/2026-09-10-i-graded-lines-when-the-unit-was-the-command.md
