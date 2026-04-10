---
module: System
date: 2026-03-23
problem_type: workflow_issue
component: tooling
symptoms:
  - "CLO agent asserted '#670 not started' when issue was closed 5 days earlier"
  - "COO agent made identical false assertion about same issue"
  - "Both agents caused unnecessary urgency and wasted investigation time"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [domain-leaders, issue-verification, false-assertions, agent-accuracy]
---

# Troubleshooting: Domain Leader Agents Assert False Issue Status

## Problem

Both CLO and COO domain leader agents asserted that GitHub issue #670 (vendor DPA review) had "not been started" when it had actually been closed 5 days earlier with all 4 vendor DPAs signed and verified. This created false urgency and wasted investigation time.

## Environment

- Module: System (all domain leader agents)
- Affected Component: 8 domain leader agents (CLO, COO, CTO, CMO, CPO, CFO, CRO, CCO)
- Date: 2026-03-23

## Symptoms

- CLO assessment: "Issue #670 calls for DPA review but work has not started"
- COO assessment: "DPA review status: Not started — Issue #670 (P1, Phase 1 roadmap)"
- Both assertions were factually wrong — #670 was closed 2026-03-18 via PR #732

## What Didn't Work

**Direct solution:** The problem was identified by manually checking `gh issue view 670 --json state` and `gh pr view 732`, which immediately revealed the issue was closed. The root cause was clear: neither agent had instructions to verify issue state before asserting claims.

## Session Errors

**DPA verification memo path not found on first attempt**

- **Recovery:** Used glob search to find the correct path at `knowledge-base/project/specs/feat-vendor-ops-legal/dpa-verification-memo.md`
- **Prevention:** The `project/` segment in the knowledge-base path hierarchy should not be assumed — always glob when uncertain

**WebFetch failed to parse Supabase DPA PDF**

- **Recovery:** Used Read tool with PDF page support instead
- **Prevention:** For PDF analysis, prefer Read tool (native PDF support) over WebFetch (text extraction only)

## Solution

Three-layer fix applied:

**1. AGENTS.md hard rule** (loaded every turn):

```markdown
- Before asserting the status of a GitHub issue (open, closed, not started, in progress),
  verify via `gh issue view <N> --json state`. Before claiming work "has not been done"
  or "has not started," check `knowledge-base/` for existing artifacts and
  `gh pr list --search "<N>"` for related PRs.
```

**2. Domain leader Assess phase updates** (all 8 agents):
Added to each domain leader's Assess section:

```markdown
- If the task references a GitHub issue (`#N`), verify its state via
  `gh issue view <N> --json state` before asserting whether work is pending or complete.
```

CLO and COO received additional instructions to check `knowledge-base/project/specs/` for existing work artifacts.

**3. Legal compliance posture document** (`knowledge-base/legal/compliance-posture.md`):
Created a living status document tracking vendor DPAs, legal documents, and compliance items — analogous to `knowledge-base/operations/expenses.md` for ops. Domain leaders now read this during assessment instead of guessing.

## Why This Works

1. **Root cause:** Domain leader agents had no instruction to verify GitHub issue state before making claims. Their Assess phases were purely file-system based — they inventoried documents but never checked the issue tracker.
2. **The hard rule** ensures every agent (not just domain leaders) verifies issue state before asserting. It's loaded every turn via AGENTS.md.
3. **The Assess phase updates** add the verification step exactly where the assessment happens, making it a natural part of the workflow rather than an afterthought.
4. **The compliance posture document** provides a single source of truth for legal status, eliminating the need for agents to infer status from scattered artifacts.

## Prevention

- Domain leaders must verify GitHub issue state (`gh issue view <N> --json state`) before referencing issues in assessments
- Living status documents (like `expenses.md`, `compliance-posture.md`) should exist for every domain where agents make status assertions
- When an agent references an issue number, the system should treat the assertion as unverified until `gh` CLI confirms it

## Recurrence: 2026-04-10

[Updated 2026-04-10] The fix documented above was **incompletely applied**. During the #1062 CI/CD integration brainstorm:

- **CTO** cited #1060, #1044, and #1076 as open blockers — all three were closed 3-13 days prior
- **CPO** made the same stale assertions despite having the verification instruction since commit a558001a

**Root cause of recurrence:** The learning documented the fix as applied to "all 8 domain leaders" but only the CPO actually received it. The CTO, CFO, CRO, CCO, COO, and CMO assess phases still lack the `gh issue view` verification instruction.

**Tracking issue:** #1930 — add verification instruction to all 6 missing domain leaders

**Additional gap:** The roadmap (`knowledge-base/product/roadmap.md`) had stale status for #1076 ("Not started" when it was closed 2026-04-07). Fixed during this session.

**Lesson:** When a fix is documented as applied to N agents, verify each agent file actually received the edit. "Fix applied to all 8" was aspirational, not verified.

## Related Issues

- #1056: Supabase DPA update tracking (the task that exposed the original problem)
- #670: Original vendor DPA review (the issue both agents incorrectly claimed was not started)
- #1062: CI/CD integration brainstorm (exposed the recurrence)
- #1930: Tracking issue to apply the fix to 6 missing domain leaders
