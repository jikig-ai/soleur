---
feature: ADR-044 PR-2a — workspace-owned repo connection (additive write relocation)
closes: 5437
adr: ADR-044
lane: cross-domain
status: in-progress
---

# ADR-044 PR-2a — Additive repo-connection write relocation

## Soak-gate finding (decision record)

PR-2 (#5437) was scoped to relocate connect-time writes AND drop the legacy
`users.*` fallback columns. The column drop is hard-gated on a prod soak of the
PR-1 `repo-resolver-divergence` breadcrumb.

**Gate evaluated `2026-06-16 ~23:34 UTC` via the Sentry issues API** (project
`jikigai-eu/web-platform`, query `repo_resolver_divergence` and
`feature:repo-resolver-divergence`, 14d window): **0 issues**. But PR-1 (#5435,
`d83fca487`) merged `2026-06-16 23:06 UTC` — **~28 min earlier**. Zero
breadcrumbs after <1h (build likely still deploying) is *no soak / no data*, not
*proven clean*. The breadcrumb fires only on edge events
(`non-member-claim-reset`, `self-heal-failed`) that need days of real traffic.

**Decision (operator-confirmed):** the destructive drop is **DEFERRED** to a
soak-gated **PR-2b**. This PR (PR-2a) does the soak-independent, additive half.
Matches the plan's own Top-Risks mandate: *"additive-write-relocation must land +
soak BEFORE the column drop (two migrations, two deploys)."*

## PR-2a scope (this PR — additive only)

The real ADR-044 gap is **team workspaces**: connect routes today write to
`user.id` and gate on `is_workspace_owner(user.id, user.id)` (always true), so a
team's repo connection can never be set via the UI and any member can "connect."
Solo workspaces are already covered (the mirror keeps `workspaces` in sync; reads
already come from `workspaces.repo_status`).

1. **Migration 110 (additive):**
   - `ALTER TABLE workspaces ADD COLUMN repo_error text` (the only missing
     repo-connection column; `repo_url`/`github_installation_id`/`repo_status`/
     `repo_last_synced_at` already exist per mig 079).
   - Credential protection: `REVOKE SELECT (github_installation_id) ON
     public.workspaces FROM authenticated, anon` + a membership-checked SECURITY
     DEFINER reader RPC.
   - Membership/owner-gated SECURITY DEFINER write RPC(s) for the repo-connection
     columns keyed on `p_workspace_id` (precedent: mig 108 `set_repo_status`).
   - `verify/110_*.sql` sentinel.
2. **Owner-gate finalization:** `app/api/repo/setup` + `app/api/repo/disconnect`
   resolve the active workspace and gate on `is_workspace_owner(activeWorkspaceId,
   user.id)` → 403 for a non-owner member. (Confused-deputy fix.)
3. **Write relocation (additive dual-write):** connect-time repo-connection writes
   ALSO target the resolved active workspace (team or solo) via the RPC; the
   existing `users.*` writes stay as the rollback net.
4. **Consumer reads:** onboarding/connect-flow repo-state reads source the active
   workspace's `workspaces.*`. (`dsar-export.ts` + `account-delete.ts` already
   carry no legacy-column reads per recon.)

## Out of scope (deferred to PR-2b, soak-gated)

- DROP `users.repo_url`, `users.workspace_path`, `users.github_installation_id`
  (+ mig-052 partial-UNIQUE index) with `.down.sql` + `verify/NNN`.
- Removal of the `users`-side dual-write / the solo mirror's users-side write.
- Onboarding `github_installation_id IS NOT NULL` → on-demand
  `GET /user/installations`; connect-flow `GET /repos/{owner}/{repo}/installation`.
- `workspace_path` / `workspace_status` relocation (these are solo-provisioning
  columns, not the connection edge — they stay on `users`).
- ADR-044 `status: adopting → accepted`; C4 edge → wholly-Workspace (PR-2b lands
  the write-side fully).
- Sentry `sentry_issue_alert` routing for the divergence fingerprint (fast-follow).
