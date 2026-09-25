# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-7761-flip-probe-post-cutover-answer-key/knowledge-base/project/plans/2026-09-24-fix-7761-flip-rollout-probe-post-cutover-answer-key-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- PreToolUse hook blocked `gh issue create` twice (missing body files; missing label); both follow-ups filed with meta/machinery as #8697, #8698.
- A Python splice aborted on a non-matching anchor before writing; re-run with corrected anchor.
- No spec.md on branch, so `lane:` defaulted to `cross-domain` (fail-closed).

### Decisions
- Answer key: `done` is safe only when preceded by a post-boundary guard=7761 `flushed-resume-no-reflush` row on the same `_MACHINE_ID`; liveness counts only `noop-done` rows after that resume. Resting `aborted`/`rolled-back` post-cutover is now FAIL. Key stays inline; `FLIP_ROLLOUT_EXPECTED_GUARD` env override dropped.
- Drift = any flip-FSM row since the boundary other than the resume row (fixed rare-event term set: 13 non-noop reasons, noop-aborted/rolled-back/unset, flag flipping/flushed), filtered to the flip FSM syslog tag.
- Boundary: committed `.after` file with 2026-09-23T19:36:32Z (symlink-refusing, non-echoing, must precede current machine's first row).
- Second defect: `mine()` dropped every object-shaped message row (probe never counted a real row); third: 500-row cap shrank the 24h drift window to ~1.9h. `betterstack-query.sh --since <ISO>` fixed at the source.
- PR body uses `Ref #7761`; post-merge live run + comment on #7761.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery, cto, spec-flow-analyzer, dhh/kieran/code-simplicity reviewers, test-design-reviewer, security-sentinel, observability-coverage-reviewer, architecture-strategist, git-history-analyzer.

## Work / Review / QA / Compound Phases
- Work: RED 7d8d2e1d50, GREEN 1244626655 (+ ef9a321979). Live PASS pre-review.
- Review: 9 seats report-only; 7 reproduced false-PASS paths rolled up to one gap; all fixed inline in da45d1b89d; 0 scope-outs; sibling-probe evidence commented on #8698. Trailer 83449394f4 (full 9/9).
- Battery (post-review head): 53/53 caught, 0 survivors, pristine control 307/0.
- QA: 12/12 ACs re-run by literal command; AC10/AC11b amended (91afb7ccab).
- Compound: learning 2026-09-24-my-probe-accepted-more-evidence-than-its-absence-queries-could-see.md; routed to followthrough-convention.md and plan-sharp-edges.md.
- Archival of this spec dir is deferred until after ship Phase 6 (it reads decision-challenges.md).
- Remaining: soleur:ship -> merge -> post-merge live run + comment on #7761.
