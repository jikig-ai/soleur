# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-concierge-git-credentials/knowledge-base/project/plans/2026-06-03-fix-concierge-git-workspace-plumbing-per-user-repo-plan.md
- Status: complete

### Errors
None. Two write-hook blocks handled mid-plan (main-checkout write-guard redirected to worktree; IaC-routing false-positive resolved with iac-routing-ack). Plan introduces zero operator/manual steps.

### Decisions
- Sandbox network constraint: agent sandbox sets network.allowedDomains:[] + allowManagedDomainsOnly:true. A GIT_ASKPASS helper alone does NOT let raw git reach github.com if the sandbox blocks TCP. Plan adds Phase 0.1 sandbox-network spike gating item 1 into Outcome A (wire askpass env + allow github.com) vs Outcome B (route git via existing server-side tools, document in-sandbox push constraint).
- Discovery: github-tools.ts already exposes github_push_branch / create_pull_request / github_read_issue MCP tools running gitWithInstallationAuth OUTSIDE the sandbox; the cc path registers NO platform MCP tools (readCcMcpAllowlist() -> {}). Item 4 re-scoped to also wire these existing server-side tools into the cc path (write tools gated; cross-tenant risk).
- Item 3 corrected: clone at repo/setup/route.ts:165 is fire-and-forget only for the HTTP response; its .then/.catch already writes repo_status + mirrors to Sentry. Real gap = an observable completion signal item 2 can read (reuse repo_status === "ready" + on-disk .git check) -> NO migration.
- Item 2 (session-start ensure-repo self-heal) is highest-leverage, spike-independent, fully server-side, idempotent, fail-soft, generic per-user via resolveInstallationId (ADR-044). Sequenced as first commit.
- Brand-survival threshold = single-user incident (requires_cpo_signoff: true): cross-tenant clone/push + token-leak vectors. Verified: git-auth.ts embeds no URL creds (askpass only); no token-value-in-log sites.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan (gates 4.4/4.45/4.6/4.7/4.8/4.9 + live verification)

## Work Phase 0 — spike outcome (DECISIVE)
- Phase 0.1 = **Outcome A**: sandbox CAN reach github.com. Evidence: prod in-sandbox `gh auth status` returned "token invalid" (a 401-from-/user verdict), which requires reaching api.github.com — a blocked network yields a connection error, not an auth verdict. No managed-settings.json ships; github.com is in the SDK managed dev-domain allow-set. → in-sandbox GIT_ASKPASS (the user's chosen approach) is network-viable.
- Phase 0.2: askpass script will land under workspacePath (the verified allowWrite dir; /tmp,$HOME sandbox-visibility unverifiable) to eliminate the path-reachability uncertainty.
- Phase 0.3: per-user resolvers confirmed — resolveInstallationId(userId) + getCurrentRepoUrl(userId) (membership-checked, normalized, generic). NEVER hardcode jikig-ai/soleur.
- Phase 0.4: reuse users/workspaces.repo_status === "ready" + on-disk .git check → NO migration.
- Building blocks: gitWithInstallationAuth(args, installationId, {cwd}) [askpass, token-in-env never URL]; provisionWorkspaceWithRepo clones into a FRESH dir (scaffold-after-clone) so in-place repair needs git init+remote add+fetch, not a re-clone-into-nonempty.
