---
title: Workspace Repo Ownership (user → workspace)
date: 2026-05-28
issue: 4558
branch: feat-workspace-repo-ownership
pr: 4559
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm — Move Repo Ownership from User to Workspace (#4558)

## What We're Building

GitHub repo connection state (`repo_url`, `github_installation_id`, sync status) currently lives on the `users` table. This brainstorm moves ownership to the **workspace** so multi-workspace collaboration works: a user has their own workspace + repo, AND can join another user's workspace to sync **that workspace's** repo. This is the durable root-cause fix for the KB-sync-broken-for-ops symptom (#4543, which was closed by the inert band-aids #4546/#4557).

## Why This Approach

Staged, additive migration with a soak window — chosen over a hard cutover because the surface is credential-bearing and cross-tenant (brand-survival threshold = single-user incident). The work is a continuation of the ADR-038 team-workspace line, not net-new architecture; it reuses ADR-038's idempotent-backfill and rollback patterns and the existing membership-checked switcher RPC (already write-capable at org-grain). The injectable sibling-fallback flagged by both the CTO and an automated security review is *deleted/workspace-scoped* by the resolver rework, so this feature removes a pre-existing HIGH rather than introducing risk.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| Fork 1 | **Auto-adopt**: owner connects repo once at workspace setup; joiners inherit it read-only, cannot reconnect/change | Least confusing for non-technical users; eliminates wrong-repo errors (CPO) |
| Fork 2 | **Preserve & restore** personal repo per-workspace ("rooms" model) | Lowest surprise; matches per-workspace DB shape; avoids trust-eroding "my project broke while I was away" (CPO) |
| Sub-fork | **`github_installation_id` on `workspaces`, NOT unique** (1:N) | One GitHub App install is org-level and legitimately covers many repos/workspaces; UNIQUE would break shared-org repos (CTO + #4546/#4557 learning) |
| Fork 3 | **Staged column lifecycle**: 079 add cols → 080 idempotent backfill (keep users cols) → 081 read-cutover (read workspaces ONLY) → drop users cols after prod soak | Clean rollback; reading workspaces-only during soak avoids the dual-ownership divergence trap |
| Fork 4 | **No UNIQUE on `workspaces.github_installation_id`**; webhook resolves founder by `(installation_id, repo_full_name)` not installation_id alone | Preserves cross-tenant attribution guard without breaking shared-org installs (CTO) |
| Switcher | **Confirm-then-switch** + persistent "Working on: `repo`" badge + loud failure/retry; never silent | Directly kills the "sync silently breaks" failure mode (CPO) |
| Security | New resolver keys off active workspace's own `installation_id` via `.eq()` on a normalized owner — the injectable `.ilike("repo_url", ...)` fallback is deleted/workspace-scoped | Subsumes pre-existing HIGH (LIKE wildcard injection) flagged by automated security review |
| Scope | Promote to **P4** (root cause of live bug; prerequisite that makes shipped invite/Members UI functional) | CPO; roadmap Current State block is stale |

## Open Questions

1. **GitHub App install scope (carried forward, unresolved).** Does installation `122213433` (jean's) actually grant access to `jikig-ai/soleur`? Could not be verified from this session — needs an App-authenticated JWT, not the user token (got 401/404 via `gh api`). If the App was scoped to only `chatte`, ops's sync fails at the GitHub API layer even after this lands; ops would need the App installed on `soleur`. **Must verify before declaring ops fixed.**
2. **Do `repo_last_synced_at` / `kb_sync_history` move to `workspaces` too?** They're on `users` today; a multi-workspace user's sync history would conflate two repos if they stay. Lean: move them with the repo columns.
3. **Removed-member local clone purge.** Revocation (067 `check_my_revocation`) closes the *session*, not the data plane — a departed member's local `workspace_path` clone may retain repo/KB data. Specify a purge/expiry obligation + T&C expectation-setting (server clones controller-side; member-local copies out of technical control).
4. **`workspace_path` re-keying.** `agent-runner.ts` reads `users.workspace_path`; how does this become active-workspace-relative? (`/workspaces/{active_workspace_id}` is the emergent target, not a literal today.)

## Domain Assessments

**Assessed:** Engineering, Product, Legal (Marketing, Operations, Sales, Finance, Support — not relevant to this internal data-model + collaboration change)

### Engineering (CTO)
Stage as 079 (additive schema) → 080 (idempotent backfill, keep users cols) → 081 (read-cutover + switcher) → later decommission. `075` does NOT already do repo ownership (role transfer only). Don't make `installation_id` UNIQUE on workspaces; resolve webhook by `(installation_id, repo_full_name)`. The `resolveInstallationId(userId)` sibling-fallback is the most dangerous code in the diff and must become `(userId, workspaceId)` workspace-scoped. Migration ceiling is 078. Complexity: LARGE (week+).

### Product (CPO)
Auto-adopt + preserve/restore + confirm-with-badge switcher. Right-sized now — completes the half-shipped invite/Members UI and fixes a live bug; promote to P4. Existing design assets: `knowledge-base/product/design/command-center/team-workspace-collaboration.pen`, `workspace-invite-acceptance.pen`. Roadmap Current State (dated 2026-03-23) is stale and should be refreshed.

### Legal (CLO)
No statutory clock triggered (no breach, no DSAR). Design-time obligations: amend PA-17 lawful basis (currently "founder's own repo → founder's own dashboard, App on founder's own account only") across Privacy Policy (~:512), Data Protection Disclosure §2.3 (~:112), and GDPR Article-30 register/balancing (~:399) for co-member repo/KB access. Backfill must assert **solo-only** workspaces (can't land a repo onto a workspace that already has co-members → pre-vetting access). Existing attestation (058) is the right surface but copy must cover repo/KB data-access consent. `installation_id` is a credential (no data-subject clock) but members must be told at join that joining grants repo access.

## Capability Gaps

None. Evidence: `soleur:atdd-developer`, `soleur:review`, the `supabase` skill, `legal-document-generator`, and `legal-compliance-auditor` cover the implementation, migration, and legal-doc work. No new skill/agent required.

## Plan-Time Gates (from learnings)

- **Idempotent backfill** — key on `WHERE NOT EXISTS` so re-runs produce 0 rows; preserve ADR-038 `workspaces.id == users.id` invariant (`knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md`).
- **TS/SQL normalizer parity** — `normalizeRepoUrl` exists in `lib/repo-url.ts` AND migration 031; run TS fixtures through the SQL expr before committing the repo_url backfill (`.../best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`).
- **RLS-widening + same-PR client `.eq` sweep** — audit all ~20 `users.repo_url`/`github_installation_id` call sites, not just the helper (`2026-05-27-client-server-rls-mismatch-post-workspace-sweep.md`, `2026-04-22-scope-by-new-column-audit-every-query-not-just-the-helper.md`).
- **Switcher reads claim from session JWT, not `getUser()`** — `raw_app_meta_data` doesn't carry mint-hook claims (`2026-05-27-supabase-getuser-app-metadata-does-not-include-jwt-hook-claims.md`); flip via membership-checked SECURITY DEFINER RPC → `refreshSession()`.
- **Don't apply migration to shared dev-Supabase pre-merge** (`hr-dev-prd-distinct-supabase-projects`, `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`).
- **`account-delete` / `anonymise_organization_membership` (078)** must handle the new `workspaces.github_installation_id`.
- **`SECURITY DEFINER search_path` pinned to `pg_temp`** for any new RPC (`cq-pg-security-definer-search-path-pin-pg-temp`).
