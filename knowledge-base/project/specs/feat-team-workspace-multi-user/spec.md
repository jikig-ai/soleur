---
title: Team-Workspace Multi-User Support (first-class organizations + flagged invite UI)
status: specified
issue: 4229
supersedes_issue: 2972
brainstorm: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
branch: feat-team-workspace-multi-user
pr: 4225
date: 2026-05-21
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
budget_override:
  ceiling_days: 10
  estimate_days: "10-13"
  approved_by: operator
  rationale: prospect signal from #2972 firmed product-shape clause; internal dogfood need is operationally real
---

# Spec: Team-Workspace Multi-User Support

## Problem Statement

Soleur's webapp is single-tenant per user: every workspace, RLS predicate, BYOK key, and `/workspaces/<id>` filesystem path is keyed on `user_id`. Two events require this to change:

1. **Internal dogfood (today, 2026-05-21).** Founder Jean (jikigai.com) onboarded Harry as an intern. They need to collaborate on the same Soleur workspace (shared KB, shared agent runs, shared cost ledger).
2. **External prospect signal (2026-05-21).** The 10-person prospect from #2972 communicated that they "most likely need it for a team of 10 users." This partially fires #2972's commit gate (product-shape clause; LOI clause not strictly met — operator override).

The 2026-04-27 small-team brainstorm deferred all team-tier engineering to "after validation gate fires." Since then:

- Tenant-isolation infrastructure shipped: migrations 028, 035, 038 (RLS), 043 (tenant_deploy_audit), 045 (attachments RLS), `lib/supabase/tenant.ts`, MU3 sandbox isolation (#1450).
- Workspace identity is still keyed on `userId` (`apps/web-platform/server/workspace.ts:67`).
- No `organization_id` / `workspace_id` primitive exists; "tenant" in the codebase = founder.

A naive multi-user retrofit (adding Harry as a second principal under Jean's `user_id`) destroys audit trail and conflicts with GDPR Art. 5(2). A workspace-keyed RLS migration is foundational and not feature-flag-able. The operator chose to introduce first-class `organizations` and `workspaces` primitives now, behind a feature-flagged invite UI, to avoid rebuilding the same primitive twice.

## Goals

- **G1.** Introduce `public.organizations(id, name, domain, owner_user_id, created_at, ...)` and `public.workspaces(id, organization_id, name, created_at, ...)` and `public.workspace_members(workspace_id, user_id, role, attestation_id, created_at)` tables.
- **G2.** Ship a `SECURITY DEFINER` function `public.is_workspace_member(p_workspace_id uuid, p_user_id uuid) RETURNS boolean` with `SET search_path = pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- **G3.** Rewrite RLS predicates on all user-keyed tables to use `is_workspace_member()`: `conversations`, `messages`, `kb_files` / `kb_chunks`, `byok_keys` (per-user read-only, NOT shared), `runtime_cost_state` (now workspace-keyed), `scope_grants`, `attachments` (extend migration 045's `is_message_owner`).
- **G4.** Add `workspace_id` column to `runtime_cost_state` so cost rows aggregate at workspace grain for dashboards while BYOK keys remain per-user (HKDF in `server/byok.ts:34` keyed on userId, unchanged).
- **G5.** Convert `/workspaces/<userId>` filesystem layout to `/workspaces/<workspace_id>`. Symlink legacy `/workspaces/<userId>` → `/workspaces/<workspace_id>` for backward compat with active sandboxes.
- **G6.** Update `apps/web-platform/server/agent-runner.ts:~941` bwrap mount to mount `/workspaces/<workspace_id>` read-write; sandbox sees workspace_id, not user_id.
- **G7.** Add `public.workspace_member_attestations(id, workspace_id, inviter_user_id, invitee_user_id, attestation_text, accepted_at, ip_hash)` WORM table following the `scope_grants` pattern (PR-G #3984). Invite endpoint requires inviter to check "I confirm this member is my employee or contractor under written agreement" — captures attestation row.
- **G8.** Ship invite UI in `/dashboard/settings/team` (or equivalent) gated by env `TEAM_WORKSPACE_INVITE_ENABLED=false` in prd, true for jikigai org only on day one. Roles: Owner + Member (2 roles).
- **G9.** Add an org-switcher UI element (header dropdown) for users who belong to >1 organization. Initially only visible to users with >1 active `workspace_members` row.
- **G10.** Update `apps/web-platform/server/workspace.ts:63-92,117-215,227` to read `workspace_id` from session context or org context, not from `userId`.
- **G11.** Migrate existing single-user workspaces: for each user, create one organization (`name = ${user.email_domain}` or `${user.email}`), one workspace, one `workspace_members(workspace_id, user_id, role='owner')` row. Idempotent backfill. `workspace_id = user_id` for backward-compat with cost/audit references.
- **G12.** Add new `sandbox-isolation.test.ts` case: two users in same workspace see same files; two users in different workspaces see nothing of each other's.
- **G13.** Run a write-boundary sentinel sweep per `hr-write-boundary-sentinel-sweep-all-write-sites`: grep all `owner_id`, `user_id` filter sites in `apps/web-platform/server/**`, document conversion to `is_workspace_member()` or explicit non-conversion in the PR body.
- **G14.** Update DSAR endpoint `apps/web-platform/server/dsar-reauth.ts` to query by `workspace_member_id` so departed members can serve Art. 15/17/20 over their identifiable rows. (Capability Gap #1 from brainstorm — confirm before merge whether this is in-PR or follow-up.)
- **G15.** Create ADR via `/soleur:architecture create "Introduce organizations and workspace_members; decouple workspace from userId"` before migration merges. Required per CTO assessment.
- **G16.** Ship legal scaffolding in parallel (separate PRs or same PR with explicit flag-OFF gate): ToS 2.2.0 §"Workspace Members" + AUP §5.5 attestation clause + Side Letter template + DPD §2.3 co-member disclosure. Flag MUST NOT flip ON until these are merged.
- **G17.** Close #2972 with a comment linking this spec and the brainstorm; reference the new kill criterion (revisit when first paying solo + ≥1 external team prospect requests multi-user during invite-UI beta).

## Non-Goals

- **NG1.** Customer-facing DPA template. Parallel CLO track; not gated by this PR's flag-OFF state.
- **NG2.** Audit-log table (`workspace_member_actions`). Deferred to first external workspace per CLO + CTO.
- **NG3.** Admin / Viewer roles. Defer until external team or revenue.
- **NG4.** `byok_delegations` table. Design must not preclude; not in this PR.
- **NG5.** SSO/SAML/SCIM. Enterprise tier.
- **NG6.** Per-domain RBAC ACLs. Enterprise tier.
- **NG7.** `/teams` landing page. Until 5+ paying team logos.
- **NG8.** Pricing-page tier toggle. Until validation evidence justifies.
- **NG9.** Public homepage change. Solo positioning unchanged.
- **NG10.** Email-domain auto-membership. CLO rejected (couples auth to email-string trust; Art. 17 conflict). Explicit invite only.
- **NG11.** Email-based invite-by-email flow. Initial scope: invite by user_id (Jean inserts Harry's existing user row). Email-based flow is a follow-up if external invites land.
- **NG12.** Backfill of cost data into workspace-aggregated rows. Migration creates the column; backfill is a separate idempotent script.
- **NG13.** Container-per-workspace isolation (#673, Phase 4.6). Orthogonal.
- **NG14.** Plan-based agent concurrency enforcement (#1162). Orthogonal.

## Functional Requirements

### FR1: `organizations` table
Columns: `id uuid PK`, `name text NOT NULL`, `domain text`, `owner_user_id uuid NOT NULL REFERENCES auth.users(id)`, `created_at timestamptz DEFAULT now()`. RLS: owner can read own org; members can read orgs they belong to (via `workspace_members` join).

### FR2: `workspaces` table
Columns: `id uuid PK`, `organization_id uuid NOT NULL REFERENCES organizations(id)`, `name text NOT NULL`, `created_at timestamptz`. RLS: visible to all members of any of its workspaces (via `workspace_members`).

### FR3: `workspace_members` table
Columns: `workspace_id uuid NOT NULL REFERENCES workspaces(id)`, `user_id uuid NOT NULL REFERENCES auth.users(id)`, `role text NOT NULL CHECK (role IN ('owner','member'))`, `attestation_id uuid REFERENCES workspace_member_attestations(id)`, `created_at timestamptz`, PRIMARY KEY (workspace_id, user_id). RLS: members can SELECT rows for workspaces they belong to.

### FR4: `is_workspace_member()` helper
`SECURITY DEFINER`, `SET search_path = pg_temp`. Returns `EXISTS(SELECT 1 FROM workspace_members WHERE workspace_id = p_workspace_id AND user_id = p_user_id)`.

### FR5: `workspace_member_attestations` WORM
Columns: `id uuid PK`, `workspace_id uuid NOT NULL`, `inviter_user_id uuid NOT NULL`, `invitee_user_id uuid NOT NULL`, `attestation_text text NOT NULL`, `accepted_at timestamptz NOT NULL DEFAULT now()`, `ip_hash text`. INSERT-only RLS; no UPDATE, no DELETE. Service-role write boundary checked via existing `service-role-allowlist-gate.sh` pattern.

### FR6: Invite UI
Path `/dashboard/settings/team` (or per UX). Gated by env `TEAM_WORKSPACE_INVITE_ENABLED`. Owner sees: member list (with role), invite form (user_id or email-lookup of existing user), attestation checkbox required. Member sees member list only.

### FR7: Org-switcher
Header dropdown shows when `auth.uid()` has rows in >1 organization. Selecting an org sets session `current_organization_id` cookie / context.

### FR8: BYOK ledger
`runtime_cost_state` gains `workspace_id uuid` column. Migration backfills `workspace_id = user_id` for existing rows. New rows write `workspace_id` from session context. BYOK key encryption stays per-user (HKDF on userId in `byok.ts:34`).

### FR9: Filesystem indirection
`getWorkspacesRoot()`-keyed paths become `/workspaces/<workspace_id>`. Migration script creates symlinks `/workspaces/<userId>` → `/workspaces/<workspace_id>` for each existing user during deploy. bwrap mounts read workspace_id from session context.

### FR10: Sandbox MU3 extension
`apps/web-platform/test/sandbox-isolation.test.ts` adds two cases: (a) two `workspace_members` of the same workspace can read each other's files inside `/workspaces/<workspace_id>`; (b) two users in different workspaces cannot read each other's files.

## Technical Requirements

### TR1: ADR before migration merges
Create `knowledge-base/architecture/adr/NNNN-organizations-and-workspace-members.md` via `/soleur:architecture create`. Reference issues #2778, #3815, #3723 as downstream beneficiaries.

### TR2: Migration numbering
Likely `053_organizations_and_workspace_members.sql`, `054_workspace_member_attestations.sql`, `055_runtime_cost_state_workspace_id.sql`. Verify highest current migration before final naming.

### TR3: Coordinate with active branches
- `feat-workspace-reconciliation-4224` — sequence after, or coordinate `workspace.ts` edits.
- `feat-pr-d-attachments-storage-tenant-rls` — migration 045's `is_message_owner` predicate must be extended (read from `workspace_members` instead of direct `user_id` check), not replaced.
- `feat-tenant-isolation-globalsetup-4041` — benefits from this work; test infrastructure picks up the new MU3 cases.

### TR4: Feature flag handling
`TEAM_WORKSPACE_INVITE_ENABLED` env var read at server boot and per-request. Flag values: per-org allowlist (`{"jikigai": true}`) for granularity. Default OFF in prd. Tested under both states.

### TR5: Legal scaffolding precedes flag flip
The `TEAM_WORKSPACE_INVITE_ENABLED=true` Doppler config change requires prior merge of: ToS 2.2.0, AUP §5.5, DPD §2.3 edit, Side Letter template. PR checklist enforces.

### TR6: Sentinel sweep documentation
PR body MUST include the output of `git grep -nE "(owner_id|user_id)\s*=\s*(auth\.uid|session\.user_id)" apps/web-platform/server/` with annotation per match: converted / kept-with-rationale.

### TR7: BYOK cost-attribution test
Add an integration test that exercises Harry's agent run inside Jean's workspace and asserts: (a) the row inserted into `runtime_cost_state` has `user_id = Harry`, `workspace_id = jikigai`; (b) the encryption key used for BYOK decryption was derived from Harry's userId, not Jean's.

### TR8: Sandbox path symlink atomicity
Filesystem migration script (G5) MUST be idempotent and atomic per directory (mv-then-symlink) — partial failure must not leave a workspace half-migrated. Smoke test on dev before prd.

## Open Questions (for plan-skill)

1. **`feat-workspace-reconciliation-4224` exact scope.** Read that branch's diff before planning to confirm collision shape.
2. **DSAR-routing fix (G14): in-PR or follow-up?** Brainstorm flagged as Capability Gap — CLO requires before first external workspace, not strictly before flag flips ON for jikigai-only.
3. **Org-switcher UI design.** Header dropdown vs. settings switch — ux-design-lead pass needed.
4. **Migration ordering.** Whether to do `workspaces` → backfill → RLS rewrite as one PR or split across 3 (lower-risk rollback path).
5. **Service-role allowlist update.** New tables need explicit allowlist entries; verify `apps/web-platform/.service-role-allowlist` includes them.

## User-Brand Impact (carry-forward from brainstorm)

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident`. Vectors (operator selected all three):

1. **Cross-user KB/chat leak** via mis-written RLS predicate — load-bearing per CLO + CTO.
2. **BYOK key exposure / silent cost shift** — load-bearing per CTO; mitigated by per-user keys + workspace cost ledger.
3. **Multi-tenant boundary bleed** — every `owner_id === session.user_id` site becomes an authz bug; sentinel sweep is the gate.

The plan skill MUST inherit `Brand-survival threshold: single-user incident` and the `## Domain Review (carry-forward)` block. The `user-impact-reviewer` agent at PR review is the load-bearing gate.

## Domain Review (carry-forward)

- **CPO:** Approved scope with override caveat (operator chose flagged-UI over no-UI; flag must stay OFF until legal scaffolding lands).
- **CTO:** Approved architecture (organizations + workspaces + workspace_members + is_workspace_member helper). ADR required.
- **CLO:** Approved with sequenced gate: Side Letter + ToS 2.2.0 + AUP §5.5 + DPD §2.3 + attestation table BEFORE flag flips ON.
- **CFO:** GO with budget caveat (10-13 days exceeds ≤10 ceiling by 0-3 days).
