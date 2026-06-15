# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-15-fix-warm-reprovision-ensure-workspace-dir-presandbox-plan.md
- Status: complete

### Errors
None. (One self-corrected step: the initial Write targeted the main checkout while worktrees exist; rewritten to the worktree path immediately.)

### Decisions
- Root cause re-diagnosed during deepen-plan. Original premise (fire-and-forget ordering race on the warm path; fix with an awaited mkdir in dispatchSoleurGo before runner.dispatch) was structurally wrong. The bwrap sandbox binds the factory's own resolved workspacePath (cc-dispatcher.ts:1315→1799), not args.workspacePath — so a dispatch-level mkdir guards the wrong variable.
- The genuine RED-on-main defect is the CONDITIONAL mkdir. ensureWorkspaceRepoCloned early-returns at :85 (not-connected) and :89 (.git-present) before its mkdir at :163. Fix: unconditional awaited mkdir(workspacePath,{recursive:true}) at each query()-construction site (realSdkQueryFactory + agent-runner.ts), using the factory's own resolved value — zero added RTT.
- AC1 re-spec'd from proxy to invariant: real-tmpdir existsSync(boundPath)-at-sandbox-construction assertion against a not-connected reclaimed fixture (genuinely RED on main).
- AC6 fail-soft made safe: silent-proceed after mkdir failure reconstructed the symptom for not-connected workspaces; now surfaces the retryable/honest envelope.
- Leader path (agent-runner.ts) folded in (shares the same conditional-mkdir gap). Reused-in-process-sandbox case scoped out to session-checkpoint work. Threshold: single-user incident → requires_cpo_signoff: true.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Agent: soleur:engineering:review:architecture-strategist
- Agent: soleur:product:spec-flow-analyzer
- Agent: general-purpose (verify-the-negative grep pass)
- Deepen-plan enforcement gates 4.4, 4.6, 4.7, 4.8, 4.9
