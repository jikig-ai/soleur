---
category: best-practices
module: flag-set-role
tags: [flagsmith, segment-rules, precondition-verification]
date: 2026-05-27
issue: 4515
pr: 4517
---

# Learning: Verify Flagsmith segment rule structure via live API before implementing

## Problem

Issue #4515 and ADR-043 described the `org-targeted` segment as using an `IN` operator with comma-separated UUID values (`orgId IN [uuid1,uuid2,uuid3]`). The plan was built on this assumption. During implementation, the first dry-run test failed with `unexpected condition: operator=EQUAL property=orgId` — the actual segment uses multiple `EQUAL` conditions (one per org) inside an `ANY` rule.

## Solution

Ran the Phase 0 precondition check (GET the segment and inspect its rule structure) before writing implementation code. The live API response showed:

```
rules[0].type = ALL
rules[0].rules[0].type = ANY
rules[0].rules[0].conditions[0]: operator=EQUAL property=orgId value=<uuid1>
rules[0].rules[0].conditions[1]: operator=EQUAL property=orgId value=<uuid2>
```

Adapted the implementation to add/remove individual `EQUAL` conditions rather than modifying a single comma-separated `IN` value.

## Key Insight

Issue bodies, ADRs, and plan-time research describe what the author *believed* the API structure to be. The live API is the source of truth. For novel API operations (no codebase precedent), the plan's Phase 0 precondition checks are load-bearing — they catch structural assumptions before 100+ lines of code are written against a wrong model. The 30-second API probe at Phase 0 saved a full rewrite.

## Session Errors

1. **Plan assumed IN operator; actual segment uses EQUAL conditions.** Recovery: caught at Phase 0 precondition verification (dry-run returned unexpected operator). Adapted implementation in-place. **Prevention:** Phase 0 precondition checks for novel API operations should always include a structural-shape verification (not just existence), and the plan should note which assumptions are unverified.

## Tags
category: best-practices
module: flag-set-role
