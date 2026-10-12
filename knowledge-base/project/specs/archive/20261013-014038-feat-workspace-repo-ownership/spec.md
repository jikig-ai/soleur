---
title: Workspace Repo Ownership
issue: 4558
branch: feat-workspace-repo-ownership
pr: 4559
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-28-workspace-repo-ownership-brainstorm.md
status: spec
---

# Feature: Workspace Repo Ownership (user → workspace)

## Problem Statement

GitHub repo connection state (`repo_url`, `github_installation_id`, sync status) lives on the `users` table (migration 011). The `workspaces` table (migration 053) holds no repo columns. This blocks multi-workspace collaboration: a user can join another user's workspace (membership already supported) but cannot sync **that workspace's** repo — joining does nothing useful. It is the durable root cause of KB sync breaking for `ops@jikigai.com` (#4543, closed by inert band-aids #4546/#4557).

## Goals

- Repos owned by workspaces, not users; members sync the active workspace's repo.
- Session carries `current_workspace_id` (net-new; only `current_organization_id` exists today).
- Installation/sync resolution keyed on active workspace, not caller `userId`.
- Write-capable workspace switcher that triggers re-sync, with a permanent "which repo is live" indicator.
- Clean, staged, reversible migration of existing solo-user repo connections.

## Non-Goals

- Per-member installation grants (`installation_id` lives on `workspaces`, not `workspace_members`).
- Changing BYOK / cost ownership (stays per-user per ADR-038).
- Building the switcher from scratch (org-grain write path already exists via `set_current_organization_id`).
- Dropping `users` repo columns in the initial cutover (deferred to a post-soak decommission migration).
- Verifying/repairing the GitHub App install scope for any specific account (tracked as Open Question 1; ops fix is gated on it).

## Functional Requirements

### FR1: Auto-adopt repo on join
A workspace owner connects a repo once at workspace setup. Every member who joins inherits it read-only — members see "Working on `owner/repo`" as a fact, with no repo-connection control. Members cannot reconnect or change the workspace repo.

### FR2: Preserve & restore personal sync ("rooms")
Each workspace keeps its own repo + sync state. Switching into another workspace leaves the user's personal workspace sync untouched; switching back restores it instantly with no re-clone.

### FR3: Write-capable workspace switcher
Switching requires a confirmation ("Switch to [Workspace]? You'll start working on `repo-name`."), then shows explicit non-dismissible status (switching → syncing → ready / failed-with-retry). A persistent live-workspace badge ("Working on: `owner/repo`") is always visible so the user can never unknowingly run agents against the wrong repo. Re-sync failures surface loudly with retry — never a green UI over a broken sync.

### FR4: Active-workspace sync resolution
Installation and workspace-path resolution key off the active `current_workspace_id`. The sync target becomes `/workspaces/{active_workspace_id}`-relative rather than emergent from the solo `users.workspace_path`.

## Technical Requirements

### TR1: Schema (migration 079, additive)
Add nullable `repo_url`, `github_installation_id bigint`, `repo_provider`, `repo_status`, `repo_last_synced_at` to `workspaces`. **No UNIQUE on `github_installation_id`** (org-level installs cover many workspaces). Consider a partial unique index for "one active repo per workspace" only if needed. Reversible `.down.sql` drops the columns.

### TR2: Idempotent backfill (migration 080)
Copy `users.{repo_url, github_installation_id, repo_provider, repo_status, repo_last_synced_at}` → the user's solo workspace, joining on the ADR-038 `workspaces.id == users.id` invariant. Key on `WHERE NOT EXISTS` so re-runs produce 0 rows. **Assert solo-only**: must not land a repo onto a workspace that already has co-members (would grant pre-vetting access) — skip/flag multi-member workspaces for explicit owner re-consent. Run all TS `normalizeRepoUrl` fixtures through the SQL normalizer (migration 031) before committing. Keep `users` columns intact.

### TR3: Read cutover (migration 081 + TS)
`resolveInstallationId` becomes `(userId, workspaceId)` and reads `workspaces.github_installation_id` directly. During soak, reads come from `workspaces` **only** (users columns inert) to avoid the dual-ownership divergence trap — no read-time fallback to `users`. Sweep all ~20 call sites reading `users.repo_url`/`github_installation_id` in the same PR (RLS-widening client `.eq` sweep rule).

### TR4: Security — remove LIKE-injection fallback
The new resolver keys off the active workspace's own `installation_id` via exact `.eq()`. The injectable `.ilike("repo_url", "https://github.com/${owner}/%")` sibling-fallback (`resolve-installation-id.ts`, flagged HIGH by automated security review) is deleted/workspace-scoped. Any residual owner matching uses a constrained owner regex + escaped LIKE metacharacters or `.eq()` on a normalized owner. Subsumes a pre-existing HIGH.

### TR5: Webhook founder resolution
`webhooks/github/route.ts` resolves the workspace by `(installation_id, repo_full_name)`, not `installation_id` alone — preserves cross-tenant attribution under shared-org installs.

### TR6: Session `current_workspace_id`
Add `current_workspace_id` to `user_session_state` + the `runtime_jwt_mint_hook` (migration 060 pattern). Switcher flips it via a membership-checked `SECURITY DEFINER` RPC (search_path pinned to `pg_temp`) → `refreshSession()`. Read the claim from the **session JWT, not `getUser()`** (`raw_app_meta_data` omits mint-hook claims).

### TR7: Cascade + lifecycle
`anonymise_organization_membership` (078) and account-delete cascade must null/handle the new `workspaces.github_installation_id`. Specify a removed-member local-clone purge/expiry obligation (revocation closes session, not data plane).

### TR8: Legal docs (parallel, via legal-document-generator)
Amend PA-17 lawful basis for co-member repo/KB access across Privacy Policy, Data Protection Disclosure §2.3, and GDPR Article-30 register/balancing. Update attestation (058) copy to cover repo/KB data-access consent. Re-audit cross-document consistency (legal-compliance-auditor).

### TR9: Migration hygiene
Do not apply migrations to shared dev-Supabase before merge coordination (`hr-dev-prd-distinct-supabase-projects`). Backfill verified against a real DB, not mocked tests (NOT-NULL-after-backfill trap).

## Sequencing

1. **079** additive schema (ship + deploy)
2. **080** idempotent solo-only backfill (keep users cols)
3. **081** read-cutover (workspaces-only reads) + `current_workspace_id` session + write-capable switcher + call-site sweep + security fix + webhook resolution
4. **(later)** decommission migration: drop `users` repo columns after prod soak

Rollback = revert the read-cutover PR; backfilled workspace columns become inert, `users` columns still authoritative — which is why steps 2 and 4 are separated.

## Open Questions

See brainstorm doc. Blocking for the ops-specific fix: verify installation `122213433` grants access to `jikig-ai/soleur` via an App-authenticated check (unresolvable from a user token).
