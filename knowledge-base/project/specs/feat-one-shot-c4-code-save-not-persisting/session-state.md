# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-12-fix-c4-code-save-not-persisting-plan.md
- Status: complete

### Errors
None. (CWD verified equal to the worktree on first tool call; branch confirmed feat-one-shot-c4-save-not-persisting.)

### Decisions
- Regression / residual failure mode, not a new build. Prior plan (2026-06-05-fix-likec4-code-editor-save-noop) and PRs #4963/#4965/#4967/#4979/#5007/#5027 already shipped; user's distinct symptom (model.c4 itself reverts) points at the workspace-sync/reconcile layer, not the render layer.
- Root cause: a diverged shared clone whose `git pull --ff-only` aborts, leaving the on-disk .c4 un-advanced so the editor's reload() re-reads stale text. Two competing hypotheses (write/read clone path-mismatch; render dirties tree) falsified by reading code.
- Committed fix: F-A1 (optimistic editor apply) + F-B (honest error). F-B already satisfied on the 500 path; real silent revert is the 200-but-stale-clone case. F-A2 demoted to contingency.
- Promoted concurrency finding H3: no mutex serializes working-tree git ops; self-heal rev-list→reset has a TOCTOU that can destroy un-pushed session-sync work. F-C deferred as a workspace-wide liveness gap with a required tracking issue.
- All deepen-plan halt gates passed (User-Brand Impact + scope-out, Observability 5-field no-SSH, no PAT vars, wireframe-gate Excluded carve-out); all 7 KB/pen citations resolve.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents (plan research): repo-research-analyst, learnings-researcher, Explore
- Agents (deepen-plan review): Explore, dhh-rails-reviewer, kieran-rails-reviewer, architecture-strategist
