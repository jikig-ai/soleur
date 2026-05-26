---
date: 2026-05-22
module: brainstorm
problem_type: workflow_pattern
component: cto_agent_prompt
severity: medium
tags: [brainstorm, cto, sentinel-sweep, subagent-prompt, call-site-grep]
synced_to: [cto]
related:
  - knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md
  - knowledge-base/project/learnings/2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md
  - knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md
---

# Brainstorm: CTO Must Grep Call Sites, Not Estimate, When Sentinel-Sweep Rule Fires

## Problem

In the 2026-05-22 brainstorm of `byok_delegations` (#4232), the CTO subagent estimated **2 production call sites** of `runWithByokLease` that would need the resolver wrapper. The parallel repo-research-analyst grepped and found **5**. CTO's effort sizing ("M, 3-5d") was anchored on the undercount; if not reconciled at Phase 2, the spec would have shipped with a 60% understated scope.

Caught because:

- Phase 1.1 includes the explicit "Reconciling fast-returning leader recommendations with later-arriving research findings" rule.
- repo-research-analyst returned grep output naming each `file:line`.
- Reconciliation forced explicit grep evidence into the brainstorm's `## Session Errors` section + spec G9.

The cost would have been one of:

- Mid-PR scope explosion when the implementer discovers sites 3-5 (rework + estimate breach).
- Silent skip of sites 3-5 (sentinel sweep miss → write-boundary regression class).

## Root Cause

The CTO agent's `### 1. Assess` and `### 2. Recommend` phases do not require a *concrete grep listing* before sizing scope. The prompt produces a plausible architecture and a confident effort estimate; the model fills the call-site count from training-data plausibility rather than the actual codebase. When `hr-write-boundary-sentinel-sweep-all-write-sites` is implicated (any new principal axis: caller_user_id vs owner_user_id, tenant_id vs founder_id, workspace_id vs userId), the "estimate then ship" path is structurally unsafe — every miss is a silent authorization bug.

Two adjacent failure modes from the same session compounded the risk:

1. **CTO referenced `runtime_cost_state` as a table** — the actual schema has `runtime_cost_state` as two kill-switch columns on `public.users`; the cost ledger is `audit_byok_use`. CTO inferred the table name from the issue body (which itself was wrong, written at deferral time months earlier). No existence-grep was run before treating it as authoritative.
2. **Issue-body data-source mismatch** (#4232 body said "tagged on each `runtime_cost_state` row") — not workflow-fixable; the issue author made the error at deferral time.

Both reinforce the same class: the model's prompt budget is spent on synthesis, not verification, unless verification is required by name.

## Solution

Two CTO prompt rules, both targeted at brainstorm-time sizing:

1. **Sentinel-sweep grep required.** When the brainstorm topic introduces a new principal axis (caller vs owner, tenant vs founder, grantor vs grantee) OR proposes a schema change that adds a column to a table referenced by ≥2 write sites, the CTO assessment MUST include an explicit `git grep -n '<symbol>'` listing naming each call site. Effort sizing follows the listing, never precedes it.

2. **Table-existence grep required.** When the issue body cites a table name or migration name, the CTO assessment MUST verify the cited artifact exists at `main` before treating it as authoritative. One-liner: `git ls-files | grep -E '<table-name>|<migration-name>'` OR `git show main:supabase/migrations | grep <name>`. If the citation is wrong, name it in the assessment ("the issue body references `X` but the actual artifact is `Y`") — this is a load-bearing input for downstream agents.

Both rules are cheap (seconds), bounded (one grep per claim), and asymmetric in payoff: false negatives at brainstorm-time cost minutes of agent compute; false negatives at PR-time cost hours of rework or are caught by post-merge incidents.

## Prevention

CTO agent Sharp Edges gets one new bullet:

> When the brainstorm topic introduces a new principal axis OR proposes a schema change adding a column to a table with ≥2 known consumers, run an explicit `git grep -n '<symbol>'` listing each call site BEFORE sizing scope. Estimates without a grep listing are structurally unsafe for `hr-write-boundary-sentinel-sweep-all-write-sites` topics — every miss is a silent authorization bug.

Brainstorm skill Phase 1.1 already has a 'Verifying issue-body architectural constraints' guidance row — extend it to include `Verifying table-name and migration-name citations from issue bodies — issue authors writing at deferral time may name artifacts that never existed or were since renamed; one `git ls-files | grep` per cited name is cheap and prevents downstream agents inheriting the wrong premise.`

## Session Errors

This learning IS the session-errors capture. The three errors enumerated at Phase 0.5:

1. **CTO subagent undershot call-site count** (60% miss). **Recovery:** caught at research-vs-leader reconciliation; brainstorm + spec corrected to 5 sites. **Prevention:** CTO Sharp Edges bullet above.
2. **CTO referenced non-existent `runtime_cost_state` table.** **Recovery:** brainstorm narrative corrected; spec G4/G7 target the correct `audit_byok_use` table. **Prevention:** CTO table-existence-grep requirement (same Sharp Edges bullet).
3. **Issue-body data-source mismatch** in #4232 (written at deferral time months earlier). **Recovery:** brainstorm Session Errors entry. **Prevention:** brainstorm Phase 1.1 row addition; this is an issue-authoring problem the brainstorm verification step can catch.

## Cross-References

- `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md` — precedent for the sentinel-sweep miss class.
- `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md` — same lesson, scope-by-new-column angle.
- `2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md` — the reconciliation rule that caught this miss.
- Source artifacts: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md` (Session Errors §1-3) and `knowledge-base/project/specs/feat-byok-delegations-4232/spec.md` (G9 enumeration).
