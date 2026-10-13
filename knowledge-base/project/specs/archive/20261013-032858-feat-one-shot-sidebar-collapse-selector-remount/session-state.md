# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-22-fix-sidebar-collapse-workspace-selector-remount-plan.md
- Status: complete

### Errors
None. CWD verified, branch safety passed, all deepen-plan halt gates passed. Push reported informational Dependabot advisories (non-blocking).

### Decisions
- Root cause: WorkspaceContextBand (workspace-context-band.tsx:83) early-returns a structurally different subtree when collapsed, omitting OrgSwitcherContainer entirely. React remounts the container on every collapse/expand, re-running its /api/workspace/list-memberships fetch and resetting state. Regression against active ADR-047 (band must never be gated on collapsed).
- Fix (Pattern 2a): keep ONE OrgSwitcherContainer instance mounted across the toggle; render icon-only collapsed presentation internally (thread collapsed prop OrgSwitcherContainer -> OrgSwitcher).
- Remove redundant useActiveWorkspace hook + prop-threading (single runtime consumer, no test imports).
- Test strategy: fetch-count/mount-counter across a collapse toggle (net-new); nav-single-mount.test.ts import guard stays green.
- Scope: second mobile CSS-hidden OrgSwitcherContainer fetch acknowledged but left out of scope. ADR-047 amendment ships in same PR.

### Components Invoked
- Skill soleur:plan
- Skill soleur:deepen-plan
- 4 research/verification sub-agents (general-purpose)
