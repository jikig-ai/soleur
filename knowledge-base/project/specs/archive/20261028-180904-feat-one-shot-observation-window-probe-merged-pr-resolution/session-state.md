# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-28-fix-observation-window-probe-merged-pr-resolution-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=2 (planning subagent: rulings F1-F5, re-ruling R1-R6)

### Errors
None.

### Decisions
- Resolver: commits/<head_sha>/pulls?per_page=2 in the read worker, identity-checked, ambiguous = unresolved (can only remove evidence).
- Quota guard re-weighted: ceil(1.5*to_read)+ceil(res_cands/2)+3*pr_est+100; facts allowance 120 -> 180 s.
- One bounded retry (fixed sleep 2) on 5xx/timeouts only; gh_get rc 44/45 for 404/422; baseline read through gh_get.
- Cosmetic PR_EXCLUDED abort fixed with plain integer facts_prs.
- Status-filtered listing deferred to a comment on the deferred-items tracker.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, cto x2, learnings-researcher, dhh/kieran/simplicity reviewers
