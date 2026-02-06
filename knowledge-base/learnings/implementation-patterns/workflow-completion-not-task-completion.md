---
module: Workflow
date: 2026-02-06
problem_type: process_improvement
component: soleur-workflow
tags:
  - workflow
  - shipping
  - pr-creation
  - compound
  - definition-of-done
severity: medium
---

# Workflow Completion is Not Task Completion

## Context

During the feat-project-overview implementation, all tasks were completed and marked off in tasks.md, but the PR was never created. The user had to prompt twice:

1. First to run `/compound` (should have been proactive)
2. Second to push and create the PR (should have been automatic)

The workflow stopped at "tasks checked off" instead of continuing to "PR submitted."

## Problem

Getting tunnel-visioned on task checkboxes treats "tasks complete" as the finish line. The actual finish line is "PR submitted for review."

The /work skill clearly defines Phase 4: Ship It with commit, push, and PR creation steps, but these were skipped.

## Pattern

The correct workflow sequence:

```
Tasks complete → /compound → /review → Commit → Push → PR → Done
```

Not:

```
Tasks complete → Done (WRONG)
```

## Key Insight

**Definition of Done is "PR submitted," not "code written" or "tasks checked off."**

A feature isn't done until:
- Code is committed with proper message
- Changes are pushed to origin
- PR is created with description
- Learning is documented (/compound)

Task checkboxes are progress indicators, not completion markers.

## Prevention

1. After marking the last task complete, immediately proceed to Phase 4: Ship It
2. Run `/compound` proactively before creating PR, not when prompted
3. Treat the PR URL as the deliverable, not the checked tasks

## Related Files

- `plugins/soleur/commands/soleur/work.md` - Phase 4: Ship It section
- `plugins/soleur/commands/soleur/compound.md` - Should run before PR
