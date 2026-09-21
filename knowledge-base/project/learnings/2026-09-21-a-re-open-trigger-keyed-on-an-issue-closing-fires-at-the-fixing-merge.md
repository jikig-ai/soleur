---
title: "A re-open trigger keyed on an issue closing fires at the fixing PR's merge, with zero post-fix data"
date: 2026-09-21
category: workflow-issues
module: knowledge-base/engineering/architecture
issues: [8399, 8470]
pr: 8459
tags: [adr, triggers, measurement, review, fsm]
---

# Learning: a re-open trigger keyed on an issue's closure can never fire

Work session for #8399 (PR #8459): `plan`, `postmerge` and `ship` gained `compound` as
designed sub-steps, the 51 `review → ship` rows were triaged, ADR-229 ruled "no gate",
and the operator adopted the `post >= 5` floor on dissent 1. The feature was sound; eight
of the nine review seats' findings were in its prose, its triggers and its guards.

## Problem

Three claims the PR added were each true-looking and unable to do their job:

- ADR-229's re-open trigger read "when #8470 closes, re-run the triage on rows logged
  after the fix merged". The PR that fixes #8470 closes it AT merge, when zero post-fix
  rows exist — so the trigger fires on an empty sample and reports all-clear.
- A review rule keyed on "zero required contexts" could never fire: CodeQL and the two CLA
  checks are 3 of the 26 required contexts and always report.
- A SKILL.md anchor test proved a MENTION of `skill: soleur:compound`, not a call; and a
  loop-key pin compared a string the loop never read.

## Solution

- Trigger: the #8470 fix PR carries `Ref #8470`; the issue closes only after a re-run at
  ≥5 post-fix rows or six weeks, whichever first — the same `n ≥ 5` floor the operator
  adopted for the extraction reading.
- Rule: keyed on "required contexts present are only CodeQL/CLA (`test` absent)".
- Tests: the loop iterates the pinned list; the anchor test's textual limits are written
  into the test and the ADR rather than hardened past what a text anchor can prove.

## Key Insight

**A trigger is a predicate over a future state — name the event that satisfies it and ask
what data exists at that instant.** "When X closes" is satisfied by the very merge that
should start the measurement, so it measures nothing. Bind triggers to a sample floor or a
date, never to the lifecycle event the fix itself performs.

## Session Errors

1. **The planner's C-triage sub-counts (19 preflight, 18 flag-C) came from an ad-hoc,
   non-executable procedure, and 19 reached the ADR, #8470, the plan and session-state.**
   Making #8470's procedure executable gave 18 and 20; data-integrity review independently
   measured 18. **Prevention:** a count written into an ADR or issue is produced by the
   procedure that artifact publishes, run once before the first write — routed to
   plan-sharp-edges.
2. **The per-user `/tmp` quota, exhausted by other sessions, made the classifier suite red
   ("Disk quota exceeded") and failed a lefthook commit (126 plugin tests, a
   `generate-kb-index` sort).** **Prevention:** on any `Disk quota exceeded`, re-run with
   `TMPDIR=/var/tmp` before diagnosing; never delete other sessions' `/tmp` artifacts.
3. **A Python multi-edit aborted on one mismatched anchor.** Nothing was written because
   every `assert` ran before the single write. **Prevention:** keep the assert-all-then-write
   shape for scripted multi-edits.
4. **The postmerge brief expected "no deploy job"; the deploy arm ran `deploy` = success.**
   **Prevention:** already covered — postmerge Phase 3.7 identifies the arm by its
   `resolve-target` log; report what the arm did.
5. **The anchor test was textual, and the loop-key pin guarded an unread string.**
   **Prevention:** existing review catalogue (guard satisfied by a mention; a pin must
   constrain the thing that runs) — fixed inline, limits documented.
6. **The ADR re-open trigger could never fire** (see Key Insight). **Prevention:** routed
   to the architecture skill's Sharp Edges.
7. **The learning inherited "none of the 26 required contexts" without measuring it,**
   and the rule built on it could never fire. **Prevention:** existing compound bullet on
   inherited framings — one `gh api …/rules/branches/main` would have falsified it.
8. **A failed commit reported an opaque exit code** because output went to a log and the
   rc was read after a pipeline. **Prevention:** `cmd > log 2>&1; rc=$?` on its own line,
   then read the log.

## Tags

category: workflow-issues
module: architecture, plan
