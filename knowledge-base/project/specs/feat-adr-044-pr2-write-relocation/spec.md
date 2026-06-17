---
feature: ADR-044 PR-2a — workspace-owned repo connection (confused-deputy refusal guard)
refs: 5437
closed_by: 5437 is closed by PR-2b (the column drop), not PR-2a
depends_on: 4560
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

## PR-2a scope (this PR — application-layer only, NO migration)

The real ADR-044 gap is **team workspaces**: connect routes today write the
workspaces-side repo state keyed on `user.id` (the solo mirror) and gate on
`is_workspace_owner(user.id, user.id)` (always true post-mig-109), so a team's
repo connection can never land on the team workspace and any member can "connect."
Solo workspaces already work end-to-end (mirror keeps `workspaces` in sync; reads
come from `workspaces.repo_status`).

**No migration is required.** Recon of the live schema found mig 079 already:
- added the repo-connection columns to `workspaces`
  (`repo_url`/`repo_provider`/`github_installation_id`/`repo_status`/
  `repo_last_synced_at`);
- did the **credential protection** in full — `REVOKE SELECT ON workspaces FROM
  authenticated` + re-GRANT of only the non-credential columns (excludes
  `github_installation_id`), with `resolve_workspace_installation_id`
  (membership-checked SECURITY DEFINER) as the sole reader.
`repo_error` is deliberately NOT on `workspaces` and is NOT relocated here:
`current-repo-url.ts:82-104` documents the error-reason staying on
`users.repo_error` (read keyed on the dispatching user) as an accepted
forward-looking limitation, with the team-workspace relocation explicitly
assigned to **#4560**. So the "migration 110 + credential RPC" items from the
original PR-2 sketch are already done / out-of-scope; dropping them shrinks the
blast radius (no schema change) with the core fix intact.

1. **Owner-gate finalization (the confused-deputy fix #5437 centers on):**
   `app/api/repo/setup` + `app/api/repo/disconnect` resolve the active workspace
   and gate on `is_workspace_owner(activeWorkspaceId, user.id)` → 403 for a
   non-owner member. No-op for solo (`activeWorkspaceId === user.id`).
2. **Write relocation (additive dual-write):** the connect-time workspaces-side
   repo-connection writes (`setup`, `detect-installation`, `install`,
   `disconnect`) target the resolved **active** workspace id (team or solo) rather
   than always `user.id`; the existing `users.*` writes stay as the rollback net.
   No-op for solo.
3. **Consumer reads:** `dsar-export.ts` + `account-delete.ts` already carry no
   legacy-column reads (recon-confirmed); no change needed there.

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
