---
category: logic-errors
module: governance
tags: [rule-audit, context-budget, agents-md, constitution-md]
date: 2026-04-06
---

# Learning: Rule audit budget baselines drift between measurement and action

## Problem

Issue #1316 was filed on 2026-03-30 with a rule audit showing 63 AGENTS.md rules
and 314 total always-loaded rules. When executing the migration on 2026-04-06,
AGENTS.md had 69 rules (6 added in 7 days). The plan's expected post-migration
count of 56 was wrong -- the actual result was 62.

## Solution

Before executing a rule migration, re-measure the current baseline rather than
relying on the issue's snapshot. The plan's Budget Impact table should use
variables ("current - 7") not fixed values ("63 - 7 = 56").

## Key Insight

Governance document counts are volatile in active projects. Any plan that
references absolute counts from a prior audit should re-verify those counts at
execution time. The *delta* (removing 7 rules) was correct; the *absolute targets*
(56, 309) were stale within a week.

## Tags

category: logic-errors
module: governance
