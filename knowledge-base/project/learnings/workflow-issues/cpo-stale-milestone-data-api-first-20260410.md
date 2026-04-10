---
module: System
date: 2026-04-10
problem_type: workflow_issue
component: tooling
symptoms:
  - "CPO domain leader asserted Phase 1 had 7 unfinished P1 items when Phase 1 was already closed"
  - "CPO operated on frozen roadmap.md Current State snapshot instead of live milestone data"
  - "Roadmap Current State section was 2+ weeks out of date after milestones closed"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [cpo, domain-leader, stale-data, milestones, roadmap, api-first]
synced_to: []
---

# Troubleshooting: CPO Domain Leader Operates on Stale Milestone Data

## Problem

During brainstorm for #1871, the CPO agent assessed Phase 1 as having 7 unfinished P1 items and 0 beta users. Phase 1 and Phase 2 were both closed. The CPO read the stale `## Current State (2026-03-23)` section in roadmap.md, which had not been updated since milestones closed.

## Environment

- Module: System (agent prompt infrastructure)
- Affected Component: CPO domain leader agent (`plugins/soleur/agents/product/cpo.md`)
- Date: 2026-04-10

## Symptoms

- CPO domain leader asserted Phase 1 had 7 unfinished P1 items when the milestone was closed with 0 open issues
- CPO reported 0 beta users based on stale snapshot
- roadmap.md Current State section showed Phase 1.5 as open, Phase 3 with 11 open/2 closed (actual: 12 open/27 closed)

## What Didn't Work

**Previous downstream fix (2026-03-25):** Plan reviewers were updated to catch stale claims after the assessment. This mitigated the symptom but didn't prevent the CPO from reading stale data in the first place. The CPO's "Roadmap consistency check" bullet was advisory and positioned last in the Assess section, so the stale file content anchored the assessment before any API check ran.

## Session Errors

**Wrong path for setup-ralph-loop.sh**
- **Recovery:** Corrected path from `./plugins/soleur/skills/one-shot/scripts/` to `./plugins/soleur/scripts/`
- **Prevention:** The one-shot skill should reference the correct script path in its instructions

## Solution

Three coordinated changes:

**1. CPO agent Assess section restructured** (`plugins/soleur/agents/product/cpo.md`):

```markdown
# Before (advisory, runs last):
- **Roadmap consistency check:** If roadmap.md exists, cross-reference
  it against GitHub milestones. Flag any inconsistency.

# After (authoritative, runs first + reconciliation later):
- Query GitHub milestones FIRST before reading any file -- these are
  the authoritative source of phase status. Run gh api milestones
  (open) and milestones?state=closed. Store the results.
  ...
- If roadmap.md exists, read its Current State section and compare
  against the milestone API results from above. Trust API over file
  when they conflict; flag staleness.
```

**2. AGENTS.md workflow gate added:**

```markdown
- When closing a phase milestone, update the ## Current State section
  of roadmap.md in the same commit.
```

**3. roadmap.md Current State updated** with live API data (2026-04-10).

## Why This Works

1. **Root cause:** The CPO agent's instruction ordering allowed stale file content to anchor the assessment before any API verification ran. The "Roadmap consistency check" was advisory and positioned last.
2. **Fix:** Moving the API query to the first bullet ensures the agent has authoritative data before reading any file. The reconciliation step then catches staleness explicitly.
3. **Prevention:** The AGENTS.md workflow gate ensures the file stays current when milestones close, reducing the window where file and API can diverge.

## Prevention

- Domain leader agents that depend on file-based status should query the authoritative API source FIRST, then reconcile with the file
- Workflow gates should cover milestone closure (not just milestone reassignment) since closure is the highest-impact state change
- The weekly CPO review cadence provides a backstop for incremental drift between milestone closures

## Related Issues

- See also: [domain-assessments-contain-stale-codebase-claims](../2026-03-25-domain-assessments-contain-stale-codebase-claims.md) -- downstream fix (plan reviewers catch stale claims); this learning is the upstream complement
- See also: [milestone-roadmap-integrity-audit](../2026-04-03-milestone-roadmap-integrity-audit.md) -- established bidirectional enforcement (issues<->milestones); this adds a third direction (milestones->roadmap Current State)
