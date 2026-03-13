---
title: Overdue Document Skip Bug in Review Reminder Workflow
date: 2026-03-02
category: logic-errors
module: ci-cd
tags: [github-actions, bash, conditional-logic, review-reminder]
last_reviewed: 2026-03-02
review_cadence: annual
---

# Learning: Overdue Document Skip Bug in Review Reminder Workflow

## Problem

The `review-reminder.yml` GitHub Actions workflow had a bash conditional that silently skipped all overdue documents. The intent was to flag documents due within 7 days, but the condition also excluded anything already past due:

```bash
if [[ $days_until -lt 0 || $days_until -gt 7 ]]; then
  continue
fi
```

A document due Feb 15 with a March 1 run gets `days_until = -14`, which matches `$days_until -lt 0`, so it's skipped. The document is permanently ignored until `next_review` is manually updated — which never happens because no reminder was ever created.

## Solution

Remove the `$days_until -lt 0` condition. Only skip documents that are more than 7 days away:

```bash
if [[ $days_until -gt 7 ]]; then
  continue
fi
```

This flags everything due within 7 days **or already past due**. The fix is a single condition removal.

## Key Insight

When writing "not yet due" skip conditions in bash, test the boundary with negative values, not just positive ones. The original author likely reasoned "skip if not in the 0-7 window" but the OR condition created an unintended exclusion zone for all negative values. The bug is subtle because it only manifests for documents that miss their review window — which is exactly when reminders are most needed.

SpecFlow analysis (spec-flow-analyzer agent) caught this by systematically walking through the flow permutation matrix — specifically the "past due (overdue)" staleness variation. Manual code review had missed it because the conditional *looks* correct at a glance.

## Tags

category: logic-errors
module: ci-cd
