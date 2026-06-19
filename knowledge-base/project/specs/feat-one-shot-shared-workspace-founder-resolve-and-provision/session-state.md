# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-18-fix-shared-workspace-founder-resolve-and-provision-plan.md
- Status: complete

### Errors
None. (One recoverable harness block: an initial Write targeted the bare-repo path and was redirected to the worktree per hr-when-in-a-worktree-never-read-from-bare. CWD verified on first call.)

### Decisions
- Bug 1 premise corrected: the PUSH path already scopes by (installation_id, repo_url) and fans out (founderId dropped, schema v=3). The abort is the NON-PUSH path — `resolveSoloFounderForInstallation` lacks a repo_url filter, so a multi-repo org install resolves >1 solo → ambiguous. Prod Sentry event header was `check_suite` (unmapped event reaching the resolver before the actionClass guard). Fix: scope non-push resolver by (installation_id, normalizeRepoUrl(repo_url)), completing ADR-044 Decision.1; keep >1 fail-closed for genuine same-repo two-users-same-fork.
- Bug 2 hypothesis refuted and re-rooted: RLS-denies-member theory wrong (resolve_workspace_installation_id mig 079 + workspaces_select_for_members mig 053 are membership-checked; active-workspace path threads unified id per #4767). Real gap: a repo_status='ready' workspace whose physical .git is absent is never deterministically re-cloned — self-heal gates on code==='error' and evaluateRepoReadiness returns {ok:true} for 'ready' without checking disk; fire-and-forget ensureWorkspaceRepoCloned at cc-dispatcher:1866 discards its 'failed' outcome.
- ADR-044 amendment is a deliverable (Architecture Decision gate fired): non-push repo-scope completes Decision.1 (amendment, not reversal).
- #5274/multi-host ruled out: /workspaces is a single-instance persistent Hetzner volume → single-host in-session self-heal suffices.
- Deepen-plan folded 3 critical fixes: AC6 rewritten to assert .git materialized (was a proxy); AC6b + RED test for concurrency loser terminal state; migration-108 member split-write firm fix (member-triggered heal failure must surface correct reason → requires a migration).

### Components Invoked
- CWD verification; scripts/sentry-issue.sh --latest-event WEB-PLATFORM-3M; gh issue view (#5470/#5274/#4755); soleur:plan; soleur:deepen-plan; Explore ×3; architecture-strategist; spec-flow-analyzer; deepen-plan halt gates 4.6-4.9 (pass)
