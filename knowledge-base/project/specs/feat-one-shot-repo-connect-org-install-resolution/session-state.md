# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-01-fix-repo-connect-org-install-resolution-plan.md
- Status: recovered from partial-artifact (planning subagent completed plan+deepen on disk; socket error killed only the Session Summary emission)

### Errors
- Planning subagent returned a socket-close API error after 53 tool uses, but the plan file (36KB, frontmatter + Overview + Root Cause + Files to Modify + Implementation Phases + Acceptance Criteria + Test Scenarios + Observability + Domain Review + Deepen-Pass Verification Log + Sharp Edges + Risks) is complete on disk. Recovered per one-shot partial-artifact protocol.

### Root cause (verified live, 2026-06-01)
- detect-installation/route.ts resolves install by matching user GitHub login to install ACCOUNT login → fails for org repos (org login ≠ user login).
- setup/route.ts reads users.github_installation_id directly → 400 when NULL even if workspace has a valid install.
- users.github_installation_id is UNIQUE; org install (122213433) owned by jean@; ops@ must reach it via workspace membership (ADR-044).

### Fix scope (code-only, no migration)
- detect-installation/repos: aggregate installs from (a) login-match + (b) workspace-membership; resolve owning install from selected repo, not login.
- setup: fall back to membership-resolved install (resolve_workspace_installation_id RPC / resolveInstallationId helper) when users.github_installation_id is NULL.
- Preserve CSRF/origin + membership/ownership checks; no service-role allowlist weakening.

### Prod data already repaired (manual, outside this PR)
- workspaces.754ee124.github_installation_id=122213433 + repo_url=jikig-ai/soleur (verified install has soleur access). users.754ee124 install stays NULL (unique constraint; resolved per-request via membership).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan (via subagent)
