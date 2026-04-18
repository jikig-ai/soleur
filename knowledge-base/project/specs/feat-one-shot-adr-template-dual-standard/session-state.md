# Session State

## Plan Phase

- Plan file: `knowledge-base/project/plans/2026-04-18-feat-adr-template-dual-standard-plan.md`
- Status: complete

### Errors

None.

### Decisions

- Adopted Option 3 from the issue: document dual standard in a single template file with a 5-trigger rubric, not backfill (Option 1) and not separate files (Option 2).
- Anchored terse shape in Nygard's 2011 ADR pattern and rich shape in MADR 3.0 — gives contributors a named tradition rather than a preference call.
- Restated each rubric trigger as an **observable** yes/no question checkable against existing repo files (NFR register, principles register, expenses.md) to remove subjectivity.
- Added a third file to the edit set: AP-011's row in `principles-register.md` gets a pointer to the rubric — keeps the principle register as a reachable entry point.
- Explicitly deferred lint/enforcement (YAGNI); the rubric is advisory and the risk section documents a concrete drift-detection grep procedure instead.
- Called out sequencing in `SKILL.md`: a new step 4.5 (ask the rubric) must slot between step 4 (read template) and step 5 (write body).
- Added retroactive rubric classification as a test: the rubric must classify ADR-001..020 as terse and ADR-021 as rich (21/21 match).

### Components Invoked

- soleur:plan (skill)
- soleur:deepen-plan (skill)
