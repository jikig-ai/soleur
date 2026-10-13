# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-30-fix-durable-agent-surface-rev-parse-strand-heal-plan.md
- Status: complete

### Errors
None. Premise validation passed (#5733 OPEN, commit 190ab58a5 on main, PR #5783 open); all 6 plan premises CONFIRMED against code by the verify-the-negative pass; all deepen-plan HALT gates passed.

### Decisions
- Prior commit 190ab58a5 already shipped lstat scaffolding (probeGitWorktreeShape/isReadyGitWorkTree/isStrandingFilePointer) + reportAgentReadinessSelfStop mirror, all on main. The lstat verdict already heals escaping pointers (git-worktree-validity.ts:183). Net-new delta is narrow: a host `git rev-parse` confirm for `dir-valid` shapes (the slice lstat can't adjudicate) + an agent-context observability backstop (C2) for shapes the host confirm is blind to.
- Dropped the "union" framing (isStrandingFilePointer arm is dead behind the lstat pre-filter) and dropped bwrap-reproduction (host rev-parse can't reproduce the sandbox denyRead → C2, the agent's in-sandbox signal, is the load-bearing observability, robust to 754ee124's unconfirmed shape).
- Fail-OPEN on inconclusive probe (never honest-block a healthy repo on a transient timeout); one shared evaluateAgentReadiness helper across all 3 gates (cross-gate consistency structural — prior 26x-dark drift); dropped warm memoization (staleness re-darkens).
- Preserved never-destroy-populated invariant (data-integrity P0: no third .git rm; populated-corrupt dir-valid -> emit + honest-block, never destroy).
- ADR-044 amendment SUPERSEDES its 2026-06-19 zero-await trade-off for the connected cold path; C4 no impact. Threshold single-user incident -> requires_cpo_signoff. Security: execFile array form, hardened git env, no install token, no subprocess-stderr-in-extra (path = raw userId leak). Shape-confirmation moved to Phase 0 (gating). PR body Ref #5733; gh issue close is post-merge.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Plan: 2 Explore agents, soleur:engineering:cto, spec-flow-analyzer
- Deepen: architecture-strategist, data-integrity-guardian, security-sentinel, performance-oracle, code-simplicity-reviewer, verify-the-negative grep pass (6 parallel review agents)
