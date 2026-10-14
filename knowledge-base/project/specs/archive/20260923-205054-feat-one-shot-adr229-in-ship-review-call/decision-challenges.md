# Decision challenges: feat-one-shot-adr229-in-ship-review-call

Recorded headless at plan review (2026-09-23). `ship` renders this file into the PR body.

## 1. #8470 confounder: add an actionable check, or cut it (Taste)

- **Finding (CTO, devex lens):** a third confounder, "review directly after a ship record", gives
  the #8470 re-measure operator nothing to act on. The triage prints no `$before[-1]` column,
  and the plan forbids editing the triage. The CTO proposed a separate read-only one-liner plus
  a disposition rule.
- **Applied instead:** the confounder was cut (simplicity seat). It records no delta of this PR,
  and a class-D row stays an honest compound skip whether or not ship ran the review. The ADR
  keeps one sentence stating that the classifier and the triage now differ on
  `ship … review ship` shapes.
- **Default kept:** the #8470 triage procedure is untouched. That is the brief's
  out-of-scope line.

## 2. Phase 4 substitute-suite list: pointer or explicit list (Taste)

- **Finding (DHH):** replace the hand-listed path-less ratchets with a pointer to work/SKILL.md
  §REFUSED gate.
- **Not applied.** The brief requires the path-less ratchets to run UNFILTERED if the gate is
  refused, because a keyword filter let two of them reach CI on the prior PR. The explicit
  "at least" list is how that requirement is checked.
