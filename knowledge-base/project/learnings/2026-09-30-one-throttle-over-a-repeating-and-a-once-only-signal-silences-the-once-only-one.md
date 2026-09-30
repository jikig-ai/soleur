---
title: One alert throttle over a repeating signal and a once-only signal silences the once-only one
date: 2026-09-30
category: integration-issues
module: apps/web-platform/infra/sentry
tags: [sentry, alerting, throttle, guard-test, absence, review]
issue: 9176
pr: 9292
---

# Learning: one throttle over a repeating and a once-only signal silences the once-only one

## Problem

#9176 added `sentry_alert.inngest_provision_failure`, paging on
`stage in {provision_attempt_failed, bootstrap_done_degraded}` AND `detail nc why=inngest_pull_fatal`,
with `frequency_minutes = 120`. The plan bundled both stages into one rule because they are the same
failure class ("the host did not reach durable shape"). Four review agents independently found that
the bundle breaks the second stage:

- Sentry's `frequency_minutes` throttles per **rule per issue group**, and every web and inngest
  host boot stage lands in one shared group (`WEB-PLATFORM-4S`).
- `provision_attempt_failed` repeats while the unit retries, so a throttled page comes back.
- `bootstrap_done_degraded` is emitted once per boot and never again (exit 0, no latch, nothing
  reboots the host).
- The most common real sequence, one attempt fails (pages) and the next ends degraded a few minutes
  later, therefore suppresses the degraded page until the next boot. That can be never. A forged event
  from the semi-public DSN can do the same.

Separately, the op-contract guard test as first written pinned only what must be PRESENT (the two
expected conditions, `logic_type = "all"`). A test-design reviewer ran 16 mutations and 14 survived,
including two P1s: one added AND-ed condition (`level eq fatal`, never true for a warning stage)
silences the page with the suite green. `enabled = false`, a dropped email action, a second
`logic_type = "any"` filter and five emit-call spellings (quoted stage, quoted or variable level,
hyphenated stage, line continuation) also survived.

## Solution

- **Throttle:** the clean fix is a second rule for the once-only stage, with its own throttle. The
  operator had authorized exactly one additive production write for this PR, so the PR keeps one rule.
  It corrects the docs, which had claimed "at most 2 h" and "pages once per boot". The runbook now
  tells the operator to confirm `bootstrap-done` (not `bootstrap-done-DEGRADED`) for the same `iid`
  after any page. The split is recorded as DC-2 in `decision-challenges.md`.
- **Guard test:** it now also pins ABSENCE:
  - exactly two field-order-insensitive `tagged_event` rows;
  - one `logic_type`, one email action, `enabled = true`, the monitor binding;
  - the full `alert-reference.json` entry with `toEqual` (the apply gate holds it equal to the plan);
  - every `soleur-boot-emit` call in the provision block matching a strict literal shape, otherwise
    it fails as unattributable;
  - a `.tf` file list derived from the directory;
  - a walk of every infra file for stray stage names.

  A 28-row battery (the original 12 plus the reviewer's 14 survivors plus two new rows) goes red on
  every mutation, and the controls stay green.

## Key Insight

When one alert rule covers several signals, compare each signal's **emission cadence** to the rule's
throttle. A signal that repeats survives a throttle, because it comes back. A signal emitted once, or
once per boot, does not: a sibling signal can consume the window it needed. "Same failure class" is
the wrong grouping test; "same cadence" is the right one.

For a guard over a declarative config block, asserting the rows you expect is half the contract.
Every AND-ed condition, filter, action and flag you did NOT expect is a way to silence or widen the
thing, so count them.

## Session Errors

1. **Plan-file write guard rejected a literal `systemctl start` phrase** (forwarded from planning).
   Recovery: rephrased. **Prevention:** none needed; the guard worked as designed.
2. **Infra human-step lint flagged one plan table row** (forwarded). Recovery: rephrased.
   **Prevention:** none needed; the lint worked as designed.
3. **`SENTRY_API_TOKEN` cannot resolve issue short ids** (forwarded). Recovery: used
   `SENTRY_ISSUE_RO_TOKEN`. **Prevention:** the plan records the RO token for post-merge verification.
4. **The lead's mutation-battery script crashed after writing a mutation**, leaving M1's rename in
   `issue-alerts.tf` on disk. The cause was `ok &= <list>`. Recovery: `git restore --source=HEAD`
   (the file had no uncommitted edits), then fixed the script and re-ran. **Prevention:** put each
   row's restore in a `try/finally`, so a harness bug cannot leave the SUT mutated.
5. **An ADR edit assertion failed** because a 3-space indented anchor was a substring of the 4-space
   one (count 2). Recovery: anchored the replacement on a leading newline. **Prevention:** anchor
   indentation-sensitive replacements on `\n<indent>`.
6. **markdownlint MD027 on blockquote continuation lines** in the ADR pointers (`>   text`).
   Recovery: single space after `>`. **Prevention:** lint every edited markdown file before commit
   (done).
7. **The lead's review spawn prompt stated a false premise.** It said the rule comment cites #8704,
   and a history agent returned it as a finding. Recovery: recognized it as the lead's own error and
   dismissed it. **Prevention:** verify every factual claim before putting it in a spawn prompt. The
   review skill's "converged panel finding built on a premise YOU supplied" rule already covers this.
8. **The guard test first pinned presence only** (2 P1 plus 12 lower survivors). Recovery: rewrote
   it to also pin absence (see above). **Prevention:** the review skill's closure and absence defect
   classes already cover this; the test-design seat caught it as designed.
9. **Design: one throttle over a repeating stage and a once-only stage** (4 agents converged).
   Recovery: corrected the docs, added the confirm step, recorded DC-2. **Prevention:** a new plan
   Sharp Edges bullet (routed in this PR).
10. **Inherited prose claims were not re-measured:** "ADR-257 measured ~26/h" (an estimate; the unit
    comment derives ~8 in the first hour), "EVERY non-zero exit" (not before the trap is armed), and
    "every boot stage of every host" (git-data uses its own group). Recovery: all corrected.
    **Prevention:** the work skill's "falsify every causal/universal claim the diff adds" rule
    already covers this. It was not applied to the rule comment because the comment was copied from
    the plan.

## Tags

category: integration-issues
module: apps/web-platform/infra/sentry
