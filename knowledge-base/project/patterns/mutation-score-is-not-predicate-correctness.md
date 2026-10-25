---
title: "Mutation score is not predicate correctness"
summary: "A fully killed mutation battery only measures the mutations imagined; escape inputs fed to the unmodified guard and mutations on new axes expose predicates narrower than their name."
status: open
opened_on: "2026-10-24"
tags: [mutation-testing, guards, escape-rows, vacuity]
evidence:
  - knowledge-base/project/learnings/2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md
  - knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md
  - knowledge-base/project/learnings/2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md
  - knowledge-base/project/learnings/2026-08-11-my-battery-reported-all-caught-and-eight-axes-were-untouched.md
  - knowledge-base/project/learnings/2026-09-30-an-absence-pin-over-hcl-must-compare-the-whole-shape-not-the-kinds-i-was-guarding.md
  - knowledge-base/project/learnings/2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md
required_reading: false
---
## Root cause

Mutation rows damage the guard and ask whether it can fail at all. They do not ask whether the
predicate is the property its name claims, because on an escape the guard works exactly as written.
Authors mutate the implementation toward obviously broken spellings along one axis, so batteries
score fully killed while environment inheritance, fixture population, loop cardinality, comment
forms and sibling declarations go unexercised. Absence checks written against the kinds the author
was thinking of miss every other kind.

## Fix

Run escape rows first: feed the pristine guard inputs it should refuse and read the result. Audit
the axes a battery edits rather than the count it reports, add a legal sibling declaration instead
of only editing the subject, and compare the whole shape of a block instead of counting selected
kinds. Count assertions per check rather than per row, keep a floor on the unit that actually
measures discrimination, and re-run the suite in the environment the repository mandates.

## Evidence

- knowledge-base/project/learnings/2026-09-04-a-10-of-10-mutation-score-and-ten-escapes-it-could-not-see.md
- knowledge-base/project/learnings/2026-09-10-every-escape-my-mutations-could-not-reach.md
- knowledge-base/project/learnings/2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md
- knowledge-base/project/learnings/2026-08-11-my-battery-reported-all-caught-and-eight-axes-were-untouched.md
- knowledge-base/project/learnings/2026-09-30-an-absence-pin-over-hcl-must-compare-the-whole-shape-not-the-kinds-i-was-guarding.md
- knowledge-base/project/learnings/2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md
