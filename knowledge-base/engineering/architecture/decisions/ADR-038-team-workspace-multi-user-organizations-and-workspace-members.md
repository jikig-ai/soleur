---
title: Introduce organizations + workspace_members; decouple workspace from userId
status: accepted
date: 2026-05-21
related: [4229, 4225, 2972]
related_adrs: [ADR-029, ADR-023]
amended_by: [ADR-044]
related_plans:
  - knowledge-base/project/plans/2026-05-21-feat-team-workspace-multi-user-plan.md
brand_survival_threshold: single-user incident
---

# ADR-038: Introduce organizations + workspace_members; decouple workspace from userId

## Status

**Accepted** (2026-05-21, PR #4225).

Lands BEFORE migration 053 in the same PR per `requires_adr: true` in the plan frontmatter.

> **Amended by [ADR-044](./ADR-044-workspace-repo-ownership.md) (2026-05-28, #4558).** This ADR deliberately left GitHub repo-connection state on `users` (the migration-059 9-table sweep excludes the repo columns). ADR-044 reverses that boundary — relocating repo state to `workspaces` so joined-workspace members can sync the workspace's repo (#4543) — and moves the installation-id uniqueness guarantee from the migration-052 DB UNIQUE to the `normalizeRepoUrl` TS↔SQL parity contract.

## Context

Soleur shipped its first ~14 months as a solo-founder web app: every Postgres row and every `/workspaces/<userId>/` filesystem tree was keyed on `auth.uid()` = `users.id`. RLS predicates across 17 policy sites in 10 migrations all evaluate `auth.uid() = user_id` (or `founder_id` for audit/cost tables). The bwrap sandbox in `apps/web-platform/server/agent-runner-sandbox-config.ts` mounts `/workspaces/<userId>/` directly into the container.

Two converging pressures invalidate the userId-keyed model:

1. **External signal (#2972 → #4229).** A prospect on the closed-beta waitlist articulated that the soleur value proposition compounds when two co-founders, or a founder + their fractional ops contractor, can share a single workspace (KB, conversations, BYOK cost ledger, daily-priorities feed) under one organization. The original product positioning carried the implicit assumption that "team" was post-PMF; the prospect's framing made it pre-PMF for the dogfood ICP.
2. **Internal dogfood (jikigai).** The founder + a second operator collaborating on Soleur development hit the workspace-isolation wall: each operator has their own user_id, their own filesystem tree, their own BYOK key, their own audit_byok_use rows. No primitive in the schema lets "Jean and second operator both see the same `messages` row." The dogfood workspace itself is the first multi-member organization.

The reflexive shape — "add `organization_id` to every table; rewrite every `auth.uid() = user_id` predicate to `auth.uid() IN (SELECT user_id FROM organization_members WHERE organization_id = …)`" — is naive on three axes:

1. **BYOK cost attribution.** PR-F (#3244) load-bears on `public.users.runtime_cost_cap_cents` + `SELECT … FOR UPDATE` serialization in `record_byok_use_and_check_cap()`. The TOCTOU window is the user_id PK lock. Moving cap enforcement off `users.id` would re-architect the entire cap-enforcement substrate for a feature whose primary need is reporting-grain (which user spent what within an org), not enforcement-grain.
2. **BYOK keys are per-user, not per-workspace.** HKDF in `byok.ts:34` derives the data-encryption key from the user_id (salt empty, userId in `info` per `2026-03-20-hkdf-salt-info-parameter-semantics`). Sharing a key across an org would require re-key-on-add and re-key-on-remove, plus a key-escrow story this PR is not buying.
3. **Filesystem isolation is bwrap-enforced.** The `/workspaces/<userId>/` mount is the agent's only writable surface; the bwrap profile is the load-bearing CWE-59 defense. Renaming the mount point is correct, but the old paths are referenced from `dsar-export.ts`, `sandbox.ts`, `tool-labels.ts`, `agent-runner.ts` — symlink-aware compat is required to avoid an in-flight DSAR job opening a stale path post-rename.

A third tension: **legal scaffolding precedes the flag flip.** ToS 2.2.0 §Workspace Members, AUP §5.5, DPD §2.3 (co-member disclosure), and a Side Letter template are all CLO-required to flip `FLAG_TEAM_WORKSPACE_INVITE=1` in production. They ship on a parallel PR (Phase 10) — this ADR + this PR must therefore land the technical substrate in a state where the flag is OFF by default and the route 404s when OFF.

Brand-survival threshold: **single-user incident.** If `is_workspace_member()` over-returns TRUE, ONE row of Jean's `messages` is visible to another `auth.uid()`. The user-impact-reviewer agent at PR review is the load-bearing gate.

## Decision

**Introduce four new Postgres primitives keyed by stable UUIDs, and a single `SECURITY DEFINER plpgsql` membership helper as the substrate for all rewritten RLS predicates. `workspaces.id` is permanently equal to `owner_user_id` for backfilled solo workspaces; new workspaces created post-flag-flip use `gen_random_uuid()`. BYOK keys stay per-user (HKDF unchanged); cost attribution shifts to workspace_id grain via an additive column on `audit_byok_use` plus a workspace-aggregate view. The bwrap mount becomes `/workspaces/<workspace_id>/` with backward-compat symlinks. The feature flag is a two-key gate (env var AND org allowlist) OFF by default in production until the legal-PR merges. [Updated 2026-05-26: env-allowlist removed; Flagsmith segment is now the sole per-org gate. See ADR-043.]**

### Schema (migrations 053+058-060)

```text
organizations
  id uuid PK default gen_random_uuid()
  name text NULL                    -- NULL sentinel = solo backfill (UI suppresses display when count=1)
  domain text NULL
  owner_user_id uuid NOT NULL FK → auth.users(id) ON DELETE RESTRICT
  created_at timestamptz NOT NULL default now()

workspaces
  id uuid PK                        -- = owner_user_id for backfilled solo workspaces (permanent invariant)
                                    -- = gen_random_uuid() for workspaces created post-backfill
  organization_id uuid NOT NULL FK → organizations(id) ON DELETE RESTRICT
  name text NULL
  created_at timestamptz NOT NULL default now()

workspace_members
  workspace_id uuid FK → workspaces(id) ON DELETE RESTRICT
  user_id uuid FK → auth.users(id) ON DELETE RESTRICT
  role text NOT NULL CHECK (role IN ('owner', 'member'))
  attestation_id uuid NULL FK → workspace_member_attestations(id)
  created_at timestamptz NOT NULL default now()
  PRIMARY KEY (workspace_id, user_id)

workspace_member_attestations   -- WORM (BEFORE UPDATE/DELETE trigger rejects all)
  id uuid PK default gen_random_uuid()
  workspace_id uuid NOT NULL FK → workspaces(id) ON DELETE RESTRICT
  inviter_user_id uuid NOT NULL FK → auth.users(id) ON DELETE RESTRICT
  invitee_user_id uuid NOT NULL FK → auth.users(id) ON DELETE RESTRICT
  attestation_text text NOT NULL   -- frozen at insertion; rotates via versioned text not row-mutation
  accepted_at timestamptz NOT NULL default now()
  ip_hash text NOT NULL
  user_agent text NOT NULL

user_session_state               -- current_organization_id JWT claim source (migration 060)
  user_id uuid PK FK → auth.users(id)
  current_organization_id uuid NULL FK → organizations(id) ON DELETE SET NULL
```

### Helper (migration 053)

```sql
CREATE FUNCTION public.is_workspace_member(p_workspace_id uuid, p_user_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql                 -- NOT sql STABLE: planner-inlining dissolves SECURITY DEFINER boundary
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$ ... $$;

REVOKE ALL ON FUNCTION public.is_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(uuid, uuid) TO authenticated;
```

Shape matches `is_message_owner` on `main` (migration 045) and `cq-pg-security-definer-search-path-pin-pg-temp`. Phase 0 probe (2026-05-21) confirmed PR-D #3883 merged with the same plpgsql + `public, pg_temp` shape.

### RLS rewrite (migration 059)

Add `workspace_id uuid REFERENCES workspaces(id)` to **9 user-keyed tables** (full enumeration: `conversations`, `messages`, `kb_share_links`, `push_subscriptions`, `concurrency_slots`, `audit_byok_use`, `dsar_export_jobs`, `scope_grants`, `multi_source_dedup`). Backfill `workspace_id = workspace_members.workspace_id WHERE user_id = <table>.user_id` (one membership per user post-053). Drop old `auth.uid() = user_id` policies, replace with `is_workspace_member(workspace_id, auth.uid())`. Set `workspace_id NOT NULL` after backfill.

`team_names` (migration 018) STAYS per-user — conversation labels are not workspace-shared (plan NG10). `runtime_cost_state` (migration 046) STAYS per-user — `record_byok_use_and_check_cap()` TOCTOU contract is load-bearing on user_id PK lock; aggregate via `workspace_cost_aggregate VIEW security_invoker = true` for dashboards.

`is_message_owner`-routed tables (message_attachments, messages external drafts, action_sends) extend the helper to accept workspace context.

### BYOK split (Phase 3)

`byok-lease.ts:154-179` accepts two parameters:

```ts
issueLease({
  workspaceContextUserId: string,   // whose workspace mounts at /workspaces/<workspace_id>/
  keyOwnerUserId: string,           // whose Anthropic key derives the data-encryption key
})
```

`audit_byok_use` tags BOTH `user_id` (= keyOwnerUserId) AND `workspace_id` (from session JWT current_organization_id → resolved workspace). HKDF in `byok.ts:34` UNCHANGED. **No fallback to owner's key for members without BYOK.** Members without BYOK fail closed with a UI banner pointing to `/dashboard/settings/byok`; Sentry breadcrumb (info-level) records workspace_id + user_id hash (no key prefix, no raw user_id) per Kieran N4.

### Filesystem (Phase 2)

bwrap mount in `apps/web-platform/server/agent-runner-sandbox-config.ts` changes from `/workspaces/<userId>` to `/workspaces/<workspace_id>`. Read-only call sites in `dsar-export.ts`, `sandbox.ts`, `tool-labels.ts`, `agent-runner.ts` keep their existing paths; a `realpathSync`-validated symlink `/workspaces/<userId> → /workspaces/<workspace_id>` covers the in-flight transition for one release cycle (CWE-59 defense per `2026-03-20-symlink-escape-cwe59-workspace-sandbox.md`). Filesystem migration is idempotent (`realpathSync` two-sided + `lstatSync` dangling check) and runs inline at deploy time, NOT as a Post-merge operator step.

### Current organization JWT claim (Phase 5.4, migration 060)

`user_session_state.current_organization_id` is the source-of-truth for the active org context. A Supabase custom access-token hook injects it as `app_metadata.current_organization_id` into the JWT. The org-switcher UI calls a `SECURITY DEFINER` RPC `set_current_organization_id(p_org_id)` (membership-checked) then forces a `supabase.auth.refreshSession()`. Reasons for JWT-resident over middleware-resolved:

- **Middleware-free.** No `getCurrentOrganizationId(req)` round-trip on every request.
- **WebSocket-resident.** `ws-handler.ts` reads the claim from the connection JWT; no per-message lookup.
- **Multi-tab race resolution (AC-FLOW3).** Per-session semantics: switching org in tab A invalidates tab B's session via the standard JWT-refresh path; tab B sees the WebSocket close with code `MEMBERSHIP_REVOKED` and re-resolves.

### Feature-flag gate (Phase 4)

`isTeamWorkspaceInviteEnabled(orgId, identity)` delegates to Flagsmith's `org-targeted` segment via `getRuntimeFlag`. The `orgId` is passed as a trait for per-org segment evaluation. [Updated 2026-05-26: `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` env var and the dual-control (AND) architecture were removed; Flagsmith segment is the sole per-org gate. `FLAG_TEAM_WORKSPACE_INVITE` env var remains as the Flagsmith outage fallback.]

Boot-time Sentry breadcrumb fires when the flag evaluates true in `NODE_ENV=production`.

### Permanent invariant: `workspaces.id = owner_user_id` for backfilled solo workspaces (Kieran N2)

Backfill (Phase 1.1.7) inserts ONE workspace per existing user with `workspaces.id = users.id`. This is **permanent** — there is no migration that re-IDs these workspaces to `gen_random_uuid()`. New workspaces created post-flag-flip use `gen_random_uuid()`. Rationale:

1. **Idempotency.** Re-running migration 053 against a populated DB produces zero rows (the `WHERE NOT EXISTS` discriminator on `workspaces.id = users.id` is stable). Switching to `gen_random_uuid()` would generate new IDs on every re-run and the discriminator would never trigger.
2. **DSAR + audit traceability.** A DSAR query that knows a user_id can resolve their original solo workspace_id without joining through `workspace_members` (which may have grown to multiple rows post-invite).
3. **Filesystem transition is cheaper.** The symlink `/workspaces/<userId> → /workspaces/<workspace_id>` is a self-link for backfilled solo workspaces (`/workspaces/<user_id> → /workspaces/<user_id>`); no actual file copy, no symlink target divergence. Post-invite, the second user's mount resolves to the workspace's canonical path.

The cost: a small amount of "is this a backfilled solo workspace or a real one?" cognitive load when inspecting raw IDs. Mitigated by the `organizations.name IS NULL` sentinel — backfilled organizations have NULL name; new ones MUST have a name.

## Rejected alternatives

- **Organization-keyed RLS (skip workspaces table).** Conflates billing-grain (org) with isolation-grain (workspace). A future "one org, multiple workspaces" shape (per-project, per-client) requires re-introducing the workspaces concept. Cheaper to introduce both now.
- **Per-org BYOK key (shared across members).** Requires re-key-on-add, re-key-on-remove, plus a key-escrow story for the org-owner-leaves case. Rejected: per-user keys preserve the HKDF invariant, BYOK delegation (#4232) is the future story.
- **`workspaces.id = gen_random_uuid()` for ALL workspaces (no special case for backfill).** Rejected per N2 above (re-runnability, DSAR ergonomics, filesystem symlink ergonomics).
- **Resolve current_organization_id from a middleware DB read on every request.** Adds a Postgres round-trip to every request. Rejected: JWT custom-claim hook has zero per-request cost and Supabase already supports the hook surface (precedent in migration 047).
- **Single-key feature flag (`FLAG_TEAM_WORKSPACE_INVITE` only).** Originally rejected per CPO conditions (AC-F): no defense-in-depth against accidental env-var flip exposing all orgs. [Updated 2026-05-26: superseded by ADR-043's Flagsmith segment-rule architecture which provides per-org control via the `org-targeted` segment without the env-var surface. The env-allowlist was removed.]
- **Drop legacy `/workspaces/<userId>/` path immediately (no symlink).** Breaks in-flight DSAR export jobs, in-progress agent runs, any cron walker holding a stale path. Symlink-with-compat for one release cycle is the rolling-deploy-safe shape.
- **Pre-create the second workspace per organization at backfill.** Rejected — solo users have one workspace; multi-workspace organizations are not in scope for this PR. The workspaces table allows future expansion without re-architecting.

## Consequences

- **Sentinel sweep is exhaustive, not aspirational.** Plan §G13 / AC4 enumerates the FULL output of `git grep -nE "auth\.uid\(\)\s*=\s*(user_id|founder_id)" apps/web-platform/supabase/migrations/` plus every `is_message_owner(` call site. AC4 fails if any literal `auth.uid() = user_id` predicate survives outside the documented `team_names` + `runtime_cost_state` exemptions per `hr-write-boundary-sentinel-sweep-all-write-sites`.
- **Backfill is idempotent and reasoned.** `IS DISTINCT FROM` discriminator + `DO $$ ... GET DIAGNOSTICS rc; RAISE NOTICE` audit per `2026-03-20-gdpr-remediation-migration-discriminator-strategy.md`. Re-running 053 against a populated DB logs `0 rows`.
- **DSAR endpoints extend to workspace_member_id JOIN.** `dsar-reauth.ts` + `dsar-export.ts` add a sibling query path. Existing `founder_id` paths remain. AC-LEGAL-FLIP gates the flag flip on this DSAR completion.
- **Member-removal kills in-flight agent sessions.** `agent-session-registry.ts` adds a `workspaceId` field + `abortAllWorkspaceMemberSessions(workspaceId, userId)` API. `workspace-membership.ts` invokes this after the `remove_workspace_member` RPC returns. WebSocket closes with `WS_CLOSE_CODES.MEMBERSHIP_REVOKED` (new code); UI shows a terminal "You were removed from <org name>" screen (AC-FLOW2).
- **Rolling-deploy-safe.** RPC signature changes (Phase 1 SECURITY DEFINER additions) use overloading per `2026-05-12-stub-handlers-as-silent-undercount-vectors`. Old pods continue resolving v1 signatures during the rolling deploy window.
- **Rollback runbook exists and lands BEFORE migration 053 commit.** `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md` documents the 6-step incident response: disable flag, down-migrate 056→053, restore old policies, drop symlinks, notify members, post-mortem via `/soleur:compound`. AC-G.
- **Legal scaffolding (Phase 10) is a parallel PR with a hard dependency.** AC-LEGAL-FLIP blocks `FLAG_TEAM_WORKSPACE_INVITE=1` in any environment until ToS 2.2.0 + AUP §5.5 + DPD §2.3 + Side Letter template land. Encoded as a Doppler audit step in `/soleur:ship`.
- **Future-revision-friendly invariants left in place.** `attestation_text` is frozen-at-insertion (WORM table); when the attestation copy changes ("I confirm this member is my employee or contractor under written agreement" → softer revision for external-team v2), the OLD text remains queryable for every existing member while NEW invitations use the NEW text. No row mutation, no schema change.
