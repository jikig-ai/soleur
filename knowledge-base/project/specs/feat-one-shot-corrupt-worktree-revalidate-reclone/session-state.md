# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-19-fix-concierge-corrupt-worktree-revalidate-reclone-plan.md
- Status: complete

### Errors
None. CWD verified first call. Branch is feature branch (not main). All deepen-plan halt-gates (4.6/4.7/4.8/4.9) passed.

### Decisions
- Root cause confirmed by elimination + code reading: presence-only existsSync(.git) at three gates (cc-dispatcher:1783 needsSelfHeal, the :1823 gitDirExists seam, ensure-workspace-repo:142/:239 .git-present early-return) treats a corrupt .git as healthy → self-heal/graft skipped → silent repo-less spawn. Third distinct gap (not the 2026-06-18 null-install divergence, not the ready-but-gone graft).
- P0 (F2): the destructive rm is gated on a POSITIVE empty-.git fingerprint (dir present + HEAD ENOENT + objects ENOENT), NEVER the negation of the validity probe — avoids catastrophic rm-of-unpushed-commits on a transient EACCES; preserves gitdir-FILE worktrees + Start-Fresh repos. A populated-but-broken .git is honest-blocked, not destroyed.
- F1: the null-install divergence gates keep a distinct true-absence probe so corrupt+null-install does not mis-emit connected-null-install-at-dispatch. F3: rm serialized under existing withWorkspacePermissionLock. F4: corrupt-on-team failure avoids the member setRepoStatus hazard. F6/F7: structural check is the explicitly-weaker hot-path proxy, rev-parse reserved off the hot path; emit is warn-on-detect / page-on-unrecovered.
- New op: corrupt-worktree-at-dispatch (consistent across AC/Phases/Observability/Tests), wired into the feature-only repo_resolver_divergence alert (zero Terraform change). TS-only, no migration. ADR-044 amended (dispatch-readiness: credential-read divergence → on-disk worktree validity). Duplicate-workspace flagged not fixed. Issue 4826 explicitly not the target.

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, architecture-strategist, data-integrity-guardian, observability-coverage-reviewer
