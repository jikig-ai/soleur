---
title: "feat: team-workspace multi-user support (organizations + workspace_members + flagged invite UI)"
type: enhancement
status: planned
lane: cross-domain
branch: feat-team-workspace-multi-user
created: 2026-05-21
issue: 4229
brainstorm: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
spec: knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
pr: 4225
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
requires_clo_signoff: true
requires_cto_signoff: true
requires_adr: true
budget_override:
  ceiling_days: 10
  estimate_days: "10-13"
  approved_by: operator
  rationale: prospect signal from #2972 firmed product-shape clause; internal dogfood need is operationally real
---

# feat: Team-Workspace Multi-User Support

## Overview

Introduce first-class `organizations` + `workspaces` + `workspace_members` + `workspace_member_attestations` Postgres primitives to the Soleur webapp. Rewrite RLS predicates on ~14 user-keyed tables via a `SECURITY DEFINER` `is_workspace_member()` helper. Add `/dashboard/settings/team` membership UI with Owner + Member roles, an org-switcher in the dashboard layout (shown only when user belongs to >1 org), and a feature-flagged invite flow (`FLAG_TEAM_WORKSPACE_INVITE` + `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` two-key gate, OFF for prd until legal scaffolding lands). Restructure `/workspaces/<userId>` → `/workspaces/<workspace_id>` with backward-compat symlinks. BYOK keys stay per-user (HKDF on userId unchanged); cost attribution shifts to workspace_id grain via `audit_byok_use.workspace_id` + a workspace-aggregate view for dashboards. Backfill creates one organization + workspace + workspace_members row per existing user, atomically and idempotently. ADR via `/soleur:architecture create` lands before migrations. Legal scaffolding (ToS 2.2.0 §Workspace Members, AUP §5.5, DPD §2.3, Side Letter template) ships on a parallel PR track; flag flip blocked on its merge.

This is an **additive parallel ICP** (solo founders + small teams), not a pivot. Solo-founder positioning, pricing page, and homepage stay unchanged. Brand-survival threshold is `single-user incident` (cross-user KB/chat leak, BYOK credential exposure, or multi-tenant boundary bleed); the `user-impact-reviewer` agent at PR review is the load-bearing gate.

**Closes #4229** (issue tracker); **supersedes #2972** (already closed with explanatory comment, 2026-05-21).

## Research Reconciliation — Spec vs. Codebase

Repo-research surfaced multiple spec-vs-code mismatches that change scope and file targets. Captured here so /work runs against the corrected reality, not the spec's framing assumptions.

| # | Spec claim | Codebase reality | Plan response |
|---|---|---|---|
| 1 | `kb_files` / `kb_chunks` are user-keyed tables needing RLS rewrite (spec G3) | These tables do not exist. KB is filesystem-only under `/workspaces/<userId>/knowledge-base/` | Drop from G3. KB workspace-scoping is handled via filesystem path resolution (Phase 2), not RLS |
| 2 | `runtime_cost_state` is a table; add `workspace_id` column (spec G4, FR8) | Migration 046 added `runtime_paused_at` + `runtime_cost_cap_cents` as **columns on `public.users`**. The per-founder cost cap and TOCTOU-safe `record_byok_use_and_check_cap()` RPC depend on `users.id` keying for `SELECT ... FOR UPDATE` serialization. **Do not break this.** | Keep per-user cap enforcement on `public.users` unchanged. Add `audit_byok_use.workspace_id` (column on the audit table, migration 037 precedent) for workspace-grain cost reporting. Add `public.workspace_cost_aggregate` view (workspace-level rollup) for dashboards. PR-F (#3244) invariant preserved |
| 3 | Sentinel sweep covers ~8 user-keyed tables (spec G13, TR6) | **17 RLS policy sites across 10 tables** (Kieran C2 correction). Literal `auth.uid() = (user_id\|founder_id)` grep returns: `001` conversations + messages (2), `017` kb_share_links (1), `018` team_names (1), `020` push_subscriptions (5 — SELECT + INSERT WITH CHECK + UPDATE + DELETE pairs), `029` concurrency_slots (1), `037` audit_byok_use founder_id (1), `041` dsar_export_jobs (1), `048` scope_grants founder_id (1), `052` multi_source_dedup founder_id (1). Plus `036` release-slot is a comment-only reference (kept). Tables previously cited (`019` message_attachments, `046` messages external drafts, `051` action_sends) use the `is_message_owner` helper pattern — **separate enumeration via `git grep -nE "is_message_owner\\(" apps/web-platform/supabase/migrations/`**. Plus `byok_keys` proxy → `api_keys` resolution path. | Sentinel sweep target = **(a) the 17 literal policy sites enumerated by `git grep -nE "auth\\.uid\\(\\)\\s*=\\s*(user_id\\|founder_id)" apps/web-platform/supabase/migrations/`, (b) every `is_message_owner` helper call site, (c) every `byok-lease` resolution path**. AC4 enumerates the FULL output of both greps. `team_names` (018) stays per-user (NG10 — conversation labels are not workspace-shared). |
| 4 | bwrap mount in `apps/web-platform/server/agent-runner.ts:~941` (spec G6, FR9) | **Real bwrap mount lives in `apps/web-platform/server/agent-runner-sandbox-config.ts`** (Kieran C1 correction). `sandbox.ts:110-148` is `isPathInWorkspace(filePath, workspacePath)` — a path-containment check used by tool-path validators, NOT the bwrap `--bind`. `agent-runner.ts:886-894` reads `user.workspace_path` from DB. | Phase 2 edits split: workspace_path resolver lives in workspace.ts/byok-lease.ts; **`agent-runner-sandbox-config.ts` mounts bwrap (the file to edit for the workspace_id path change)**; `sandbox.ts:110-148` `isPathInWorkspace` regex accepts both layouts (symlink-aware); `agent-runner.ts:886-894` reads. |
| 5 | New `/dashboard/settings/team/page.tsx` invite UI (spec FR6) | `/dashboard/settings/team/page.tsx` ALREADY EXISTS — renders `TeamSettingsContent` from `components/settings/team-settings.tsx` with `TeamNamesProvider`. Function: `team_names` display labels for conversations (migration 018). NOT membership. | Rename existing route → `/dashboard/settings/conversation-names`. Update sidebar nav. New `/dashboard/settings/team` becomes the membership page. Single-file route move + one nav edit. |
| 6 | `is_message_owner` (migration 045) is plpgsql with `search_path = public, pg_temp` | True on `main`. PR-D branch `feat-pr-d-attachments-storage-tenant-rls` rewrites to `LANGUAGE sql STABLE` with `search_path = pg_catalog, pg_temp`. **Collision risk.** | New `is_workspace_member()` matches whichever shape ships first on `main`. Plan Phase 0 verifies PR-D state before migration 053 lands. If PR-D pre-merges, sequence-after; if not, lock to plpgsql `public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`. |
| 7 | `/workspaces/<userId>` cited at `server/workspace.ts:67` | Confirmed `workspace.ts:67` AND `121`, `227`, `247`. Plus 5 read-only references in `dsar-export.ts:26,910`, `sandbox.ts:105`, `tool-labels.ts:47`, `agent-runner.ts:950`. | Convert: workspace.ts ×4 (provisioning). Keep + compat-symlink: 5 read-only sites. Symlink atomic per directory (mv-then-symlink). |
| 8 | Feature flag `TEAM_WORKSPACE_INVITE_ENABLED` (spec TR4) | `apps/web-platform/lib/feature-flags/server.ts` has 2-entry registry with boolean `0\|1` semantic. CPO requires 2-key gate (env var AND org allowlist) — current registry shape doesn't fit. | Extend registry: add `FLAG_VARS` row `"team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE"` (boolean). Add new `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` env (comma-separated UUID list, parsed once at server boot, cached). New helper `isOrgFlagEnabled(orgId)` AND's both. Boot-time Sentry breadcrumb when flag evaluates true in prd. |
| 9 | BYOK key resolution site | `byok-lease.ts:154-179` is the single resolution point. HKDF in `byok.ts:34` is `'soleur:byok:' + userId` (per `2026-03-20-hkdf-salt-info-parameter-semantics`: salt empty, userId in `info`). | Keep HKDF unchanged. Split byok-lease parameters: `workspaceContextUserId` (whose workspace) vs `keyOwnerUserId` (whose Anthropic key). Cost rows tag both. |
| 10 | Existing two-user-same-workspace test fixture | `test/helpers/sandbox-isolation-fixtures.ts:60,69` provides `createWorkspacePair` and `createNamedWorkspacePair` (different workspaces). No same-workspace two-user fixture. | New helper `createSharedWorkspaceMembers(userIds: string[]): {workspaceId, members[]}`. Used by Phase 8 MU3 multi-user test. |
| 11 | `scope_grants` WORM precedent | Confirmed `048_scope_grants.sql`: `ENABLE ROW LEVEL SECURITY`, SELECT policy `auth.uid() = founder_id`, BEFORE UPDATE/DELETE trigger `scope_grants_no_mutate` rejecting all but NULL→non-NULL transitions, SECURITY DEFINER RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`) with `search_path = public, pg_temp`. | `workspace_member_attestations` follows this template exactly. Per `2026-03-20-supabase-column-level-grant-override`: `REVOKE UPDATE ON TABLE … FROM authenticated` first, then `GRANT UPDATE (safe_col) TO authenticated` — column-level REVOKE alone is silently ineffective. |
| 12 | DSAR endpoint shape (spec G14) | `apps/web-platform/server/dsar-reauth.ts` keys on `founder_id`. CLO Capability Gap #1: needs to query by `workspace_member_id` post-org introduction. | Include in-PR (Phase 7). Block flag-flip on completion. |

## Research Insights — Verified Facts

| Fact | Verification | Source |
|---|---|---|
| Migration 052 is current `main` head | `git ls-tree origin/main apps/web-platform/supabase/migrations/ \| tail -1` → `052_multi_source_dedup.sql` | Phase 1 repo research |
| 053/054/055 are next free slots | Confirmed worktree HEAD = main HEAD; no in-flight branch adds 053+ | Phase 1 repo research |
| HKDF salt MUST be empty; userId in `info` | `apps/web-platform/server/byok.ts:34-39` | `knowledge-base/project/learnings/2026-03-20-hkdf-salt-info-parameter-semantics.md` |
| Column-level REVOKE is silently no-op when table GRANT exists | Pattern: REVOKE table first, then GRANT(col) | `knowledge-base/project/learnings/2026-03-20-supabase-column-level-grant-override.md` |
| Trigger + TS fallback INSERT must mirror conditional logic; use `upsert(onConflict, ignoreDuplicates:true)` | Pattern for G11 backfill if `handle_new_user` trigger also runs | `knowledge-base/project/learnings/2026-03-20-supabase-trigger-fallback-parity.md` |
| Backfill: `IS DISTINCT FROM` discriminator, `DO $$ ... GET DIAGNOSTICS rc = ROW_COUNT; RAISE NOTICE` audit | Never timestamp proximity | `knowledge-base/project/learnings/2026-03-20-gdpr-remediation-migration-discriminator-strategy.md` |
| Never `::boolean` on `raw_user_meta_data->>'…'` in BEFORE INSERT — use text equality `= 'true'` | Applies to any new `handle_new_user` trigger logic | `knowledge-base/project/learnings/2026-03-20-supabase-trigger-boolean-cast-safety.md` |
| Encrypted columns stay `text` (base64), NEVER `bytea` (PostgREST corrupts round-trip) | `convert_from(col, 'UTF8')` not `encode(col, 'base64')` | `knowledge-base/project/learnings/2026-03-17-postgrest-bytea-base64-mismatch.md` |
| Do NOT migrate BYOK to pgsodium / Vault | App-layer AES-256-GCM + HKDF stays; workspace-context is application-layer split | `knowledge-base/project/learnings/2026-03-20-supabase-pgsodium-deprecation-vault-limitations.md` |
| `agent-env.ts:ALLOWED_KEYS` is allowlist-only; new env vars MUST NOT leak to subprocess | CWE-526 guard for env spread | `knowledge-base/project/learnings/2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` |
| Symlink reshape MUST use `realpathSync` on both sides + `lstatSync` dangling check | CWE-59 escape regression risk | `knowledge-base/project/learnings/2026-03-20-symlink-escape-cwe59-workspace-sandbox.md` |
| TC-version enforcement-surface gap rule: never declare ws-handler / route / webhook a "non-goal" for new RLS predicates | Predicate enforcement must be exhaustive | `knowledge-base/project/learnings/2026-03-20-tc-version-enforcement-surface-parity.md` |
| Server-side WORM attestation pattern: trigger inserts NULL → POST `/api/accept-*` writes via service-role with `AND col IS NULL` idempotency → middleware enforces non-NULL on protected paths | Pattern for `workspace_member_attestations` | `knowledge-base/project/learnings/2026-03-20-server-side-tc-acceptance-security-pattern.md` |
| `tasks.md` is ONE execution unit. NO `### Post-merge (operator)` rows for Supabase `apply_migration` / `execute_sql` / `gh pr ready` / Playwright — run inline | Supersedes any earlier "list it for the operator" reflex | `knowledge-base/project/learnings/2026-05-12-mid-plan-pause-gates-and-operator-step-pushback.md` |

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO), Finance (CFO). Marketing/Sales/Operations/Support not flagged at brainstorm-time; carry-forward.

**Brainstorm-recommended specialists:** `legal-document-generator` (parallel CLO track, separate PR — see Phase 10), `legal-compliance-auditor` (post-CLO-track audit; not gated by this PR), `ux-design-lead` (wireframes for invite UI + member list + org-switcher — invoked in Phase 2.5 below).

### Engineering (CTO)

**Status:** carried-forward from brainstorm assessment (2026-05-21). No new technical surprises; reconciliation table above captures the file-path corrections relative to spec wording. ADR required before migration 053 merges.

### Legal (CLO)

**Status:** carried-forward from brainstorm assessment. Five non-negotiable scaffolding items (ToS 2.2.0 §Workspace Members, AUP §5.5, DPD §2.3 co-member disclosure, Side Letter template, in-product attestation checkbox) gate the flag flip. Items 1-4 ship on a parallel PR (legal-document-generator), tracked separately. Item 5 (attestation checkbox + WORM table) ships in THIS PR (Phase 4 + 5).

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, cpo, ux-design-lead (status: see Phase 5)
**Skipped specialists:** copywriter (no leader recommendation; brand voice on member-list copy carried forward via existing Soleur brand-guide patterns); legal-document-generator (separate PR — Phase 10)
**Pencil available:** yes — 4 wireframes saved at `knowledge-base/product/design/team-workspace/` (Pen file + 4 PNGs at scale 3): `01-team-empty-solo.png`, `02-team-owner-plus-member.png`, `03-invite-member-modal.png`, `04-org-switcher-header.png`. Designer flagged for CPO follow-up: (a) hide workspace-identity chip from header entirely when user has only one org (currently designed as chip-is-dropdown-trigger, only renders when needed — confirms AC-C); (b) attestation copy "I confirm this member is my employee or contractor under written agreement" is acceptable for dogfood, plan a softer revision for external-team v2; (c) Frame 01 "Solo for now." hint uses gold accent — designer offers white alternative.

#### Findings

**SpecFlow CRITICAL (3) — folded into ACs:**
1. Default-org-on-login resolver undefined (Flow 2). User with exactly one membership has no current_organization_id set. **AC-FLOW1.**
2. In-flight agent runs on member removal (Flow 4). SIGTERM + cost-ledger semantics + UX undefined. **AC-FLOW2.**
3. Multi-tab org-switch race (Flow 3). Per-session vs per-tab semantics. **AC-FLOW3.**

**SpecFlow IMPORTANT (4) — folded:** Flag-OFF route behavior (AC-A), backfill empty-state (AC-B + AC-C), owner-removes-self block (AC-FLOW4), org-switcher cross-tab stale context (AC-FLOW3).

**CPO conditions (7) — folded as ACs:**
- AC-A: flag-OFF route returns 404 (not 403), no `<Link>` rendered, no `team` string in client bundle, no robots/sitemap entry
- AC-B: Backfill sets org `name = NULL` (sentinel); UI suppresses org name when `workspace_members.count = 1`
- AC-C: Org-switcher hidden when count = 1 (already spec FR7; make explicit + snapshot test)
- AC-D: Member-without-BYOK fails closed; error copy + docs explicit; `byok_delegations` shim deferred to #4232
- AC-E: No `organization_id` / `workspace_id` written to Stripe customer/subscription/invoice metadata
- AC-F: 2-key gate (env var AND org allowlist); boot-time Sentry breadcrumb when flag evaluates true in prd
- AC-G: Rollback runbook at `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md` committed before flag flips ON

## User-Brand Impact

**If this lands broken, the user experiences:** one row of Jean's `kb_chunks` (filesystem) or `messages` (Postgres) returned to any other authenticated `auth.uid()` via the new `is_workspace_member()` predicate. Concrete artifact: Jean's pricing-strategy.md notes; Jean's draft-LinkedIn-post Sentry-redacted-but-screenshotted contents; Jean's BYOK API key prefix visible in error toast.

**If this leaks, the user's data is exposed via:**
1. A mis-written RLS predicate widening `is_workspace_member()` to return TRUE for non-members (Vector 1).
2. A missed sentinel-sweep site that retains `owner_id === session.user_id` semantics after migration, granting cross-workspace reads (Vector 3).
3. BYOK-lease silently falling back to owner's key when member has none, debiting cost to wrong user_id and leaking key-derivation artifacts in error paths (Vector 2).

**Brand-survival threshold:** `single-user incident`. One leak = revert migrations 053 + 058 + 059, restore `auth.uid() = user_id` predicates, drop symlinks, take post-mortem to /soleur:compound. `user-impact-reviewer` agent at PR-review time is load-bearing per CLO and CPO.

## Implementation Phases

### Phase 0: Preconditions (in-worktree, no commits)

**Goal:** verify environmental assumptions before any DDL or code edits land.

0.1. **PR-D collision probe.** `gh pr view <PR-D-number> --json state,mergedAt,headRefName 2>/dev/null` AND `git log origin/feat-pr-d-attachments-storage-tenant-rls -1 --format="%H %s" -- apps/web-platform/supabase/migrations/045_*.sql` to read the latest `is_message_owner` rewrite (`LANGUAGE sql STABLE` with `search_path = pg_catalog, pg_temp`). Decide:
   - PR-D merged before this PR's migration 053 lands → match PR-D's shape (`LANGUAGE sql STABLE, search_path = pg_catalog, pg_temp`).
   - PR-D not merged → lock to `LANGUAGE plpgsql, search_path = public, pg_temp` per main + `cq-pg-security-definer-search-path-pin-pg-temp`. Coordinate PR-D rebase if PR-D is closer to merge.

0.2. **Highest migration number probe.** `git ls-tree origin/main apps/web-platform/supabase/migrations/ | awk -F'\t' '{print $2}' | sort -V | tail -1` → expect `052_multi_source_dedup.sql`. If any 053+ has landed on `main` since this plan was written, increment the migration numbers below accordingly and run `git diff origin/main..HEAD -- apps/web-platform/supabase/migrations/` to confirm no overlap.

0.3. **`feat-workspace-reconciliation-4224` scope probe.** `gh pr list --head feat-workspace-reconciliation-4224 --json state,title 2>/dev/null` (likely none; brainstorm-spec only branch). `git log origin/feat-workspace-reconciliation-4224 --oneline -- apps/web-platform/server/workspace.ts 2>/dev/null` to confirm zero code commits. If code is added before this PR lands, sequence-after.

0.4. **ADR draft.** Run `/soleur:architecture create "Introduce organizations and workspace_members; decouple workspace from userId"`. Reference downstream beneficiaries: #2778 (post-MVP projects-table refactor), #3815 (multi-tenant Sentry DPA), #3723 (multi-tenant deploy substrate). ADR text MUST describe: many-to-many membership rationale, per-user BYOK + workspace-aggregate cost ledger split, filesystem symlink approach with `realpathSync` two-sided containment, ToS 2.2.0 + AUP §5.5 + attestation WORM as legal preconditions for flag flip, **AND the permanent decision (Kieran N2) that `workspaces.id` for backfilled solo users equals `owner_user_id` (not `gen_random_uuid()`) — preserves backward-compat with all audit/cost/conversation rows whose `workspace_id` backfills derive from `user_id`. New workspaces created post-backfill get fresh UUIDs.**

0.5. **Service-role allowlist plan.** Read `apps/web-platform/.service-role-allowlist`. New service-role-importing files to add in Phase 4:
   - `apps/web-platform/server/workspace-membership.ts` (PERMANENT — invite/remove RPCs require service-role to write `workspace_member_attestations` WORM rows)
   - `apps/web-platform/server/workspace-resolver.ts` (PERMANENT — `current_organization_id` resolution + backfill-aware default-org)

0.6. **Spec amendment.** Update `knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md` to reflect reconciliation table corrections (drop `kb_files`/`kb_chunks` from G3, reframe G4 to keep per-user cap + add workspace-aggregate view, fix line numbers in G6/FR9, name the existing-route rename in FR6). Commit with `docs(spec): reconcile with codebase reality (kb tables, runtime_cost_state, file:line, /team route)`.

### Phase 1: Migrations 053-055 + helpers + RLS rewrites

Each migration ships in one commit. The full migration suite ships as one PR (no split-apply via Doppler — `tasks.md` is one execution unit per learning 2026-05-12).

#### Phase 1.1: Migration 053 — `organizations` + `workspaces` + `workspace_members` + helper

**File to create:** `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql`

```sql
-- ============================================================================
-- 1. organizations
-- ============================================================================
CREATE TABLE public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,                                    -- NULL for solo-backfilled (AC-B)
  domain text,
  owner_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. workspaces
-- ============================================================================
CREATE TABLE public.workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  name text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 3. workspace_members (many-to-many; one row per (workspace, user))
-- ============================================================================
CREATE TABLE public.workspace_members (
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  role text NOT NULL CHECK (role IN ('owner','member')),
  attestation_id uuid,                          -- FK populated in 054
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id, user_id)
);
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 4. is_workspace_member helper (SECURITY DEFINER)
-- ============================================================================
-- Posture mirrors 045's is_message_owner verbatim (Kieran C3 correction):
-- plpgsql (NO `STABLE` keyword — 045 comment block warns the volatility
-- marker risks planner inlining of the SECURITY DEFINER body), search_path
-- pinned, REVOKE PUBLIC+anon+authenticated+service_role then explicit GRANT.
-- If Phase 0.1 confirms PR-D pre-merged with sql STABLE / pg_catalog, pg_temp, mirror PR-D's shape instead.
CREATE OR REPLACE FUNCTION public.is_workspace_member(p_workspace_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id AND user_id = p_user_id
  );
END;
$$;
REVOKE ALL ON FUNCTION public.is_workspace_member FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_workspace_member TO authenticated;

-- ============================================================================
-- 5. RLS policies on the three new tables
-- ============================================================================
-- organizations: visible to any member of any workspace in the org
CREATE POLICY orgs_select_for_members ON public.organizations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.workspaces w
      JOIN public.workspace_members m ON m.workspace_id = w.id
      WHERE w.organization_id = organizations.id AND m.user_id = auth.uid()
    )
  );

-- workspaces: visible to its own members
CREATE POLICY workspaces_select_for_members ON public.workspaces FOR SELECT
  USING (public.is_workspace_member(workspaces.id, auth.uid()));

-- workspace_members: members can see other members of their workspace
CREATE POLICY members_select_peers ON public.workspace_members FOR SELECT
  USING (public.is_workspace_member(workspace_members.workspace_id, auth.uid()));

-- workspace_members: INSERT/DELETE only via service-role (invite/remove RPCs)
-- No INSERT/UPDATE/DELETE policies for authenticated → row-locked.
```

#### Phase 1.2: Migration 054 — `workspace_member_attestations` (WORM) + invite/remove/anonymise RPCs

**Header comment block** (load-bearing per AC-GDPR-5e + AC-GDPR-6):

```sql
-- 058_workspace_member_attestations.sql
-- LAWFUL_BASIS:
--   workspace_member_attestations.invitee_user_id, ip_hash, user_agent:
--     Art. 6(1)(b) contract performance (employment/contractor relationship)
--   workspace_member_attestations.inviter_user_id, attestation_text, accepted_at:
--     Art. 6(1)(f) legitimate interest (controller's audit trail; Art. 5(2)
--     accountability evidence under EDPB Opinion 2/2017 workplace context)
-- RETENTION:
--   Attestation rows retained for workspace lifetime + 7 years post-
--   membership-removal. After 7y, anonymise_workspace_member_attestations()
--   nulls all identifiable columns; preserves attestation_text→'<anonymised>'
--   + accepted_at as the immutable legal record of the act (Art. 7(1)).
```

**File to create:** `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql`

Mirrors `scope_grants` (048) WORM pattern. Key points:

```sql
CREATE TABLE public.workspace_member_attestations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  inviter_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  invitee_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  attestation_text text NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  ip_hash text,
  user_agent text
);
ALTER TABLE public.workspace_member_attestations ENABLE ROW LEVEL SECURITY;

-- WORM trigger (NO UPDATE, NO DELETE except admin anonymise RPC)
CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_attestations: row is WORM';
  END IF;
  RETURN NULL;
END;
$$;
CREATE TRIGGER worm_guard BEFORE UPDATE OR DELETE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

-- Column-level GRANT/REVOKE per learning 2026-03-20-supabase-column-level-grant-override:
REVOKE UPDATE ON TABLE public.workspace_member_attestations FROM authenticated, anon;
-- (no GRANT UPDATE — attestation rows are immutable to non-admin clients)

-- Service-role-only INSERT (invite RPC); SELECT scoped to workspace members
CREATE POLICY attestations_select_for_members ON public.workspace_member_attestations FOR SELECT
  USING (public.is_workspace_member(workspace_member_attestations.workspace_id, auth.uid()));

-- SECURITY DEFINER RPCs (search_path pinned per cq-pg-security-definer-search-path-pin-pg-temp)
CREATE OR REPLACE FUNCTION public.invite_workspace_member(
  p_workspace_id uuid, p_invitee_user_id uuid, p_attestation_text text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_attestation_id uuid; v_inviter uuid := auth.uid();
BEGIN
  -- Caller must be a workspace owner
  IF NOT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id AND user_id = v_inviter AND role = 'owner'
  ) THEN RAISE EXCEPTION 'caller is not workspace owner';
  END IF;
  -- Idempotency: skip if already a member
  IF EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id AND user_id = p_invitee_user_id
  ) THEN RAISE EXCEPTION 'already a member';
  END IF;
  -- Atomic: insert attestation, then membership row referencing it
  INSERT INTO public.workspace_member_attestations
    (workspace_id, inviter_user_id, invitee_user_id, attestation_text)
    VALUES (p_workspace_id, v_inviter, p_invitee_user_id, p_attestation_text)
    RETURNING id INTO v_attestation_id;
  INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id)
    VALUES (p_workspace_id, p_invitee_user_id, 'member', v_attestation_id);
  RETURN v_attestation_id;
END;
$$;
REVOKE ALL ON FUNCTION public.invite_workspace_member FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.invite_workspace_member TO authenticated;
-- Same pattern (SECURITY DEFINER, search_path = public, pg_temp, REVOKE/GRANT):
-- - remove_workspace_member(p_workspace_id, p_user_id): SIGTERM hook fires in TS side
-- - anonymise_workspace_member_attestations(p_attestation_id): Art. 17 cascade
-- - anonymise_workspace_members(p_workspace_id, p_user_id): nulls user_id
-- - anonymise_organization_membership(p_org_id, p_user_id): nulls owner_user_id
--   (mirrors migration 048 anonymise_scope_grants; service_role-only GRANT)
```

ALTER `workspace_members.attestation_id` to add FK reference now that 054's table exists.

#### Phase 1.3: Migration 055 — RLS sweep + `audit_byok_use.workspace_id` + aggregate view

**File to create:** `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql`

**Header (per Kieran N1):**
```sql
-- 059_workspace_keyed_rls_sweep.sql
-- DEPENDENCY: requires 053_organizations_and_workspace_members.sql to have
-- created public.workspaces, public.workspace_members, AND completed the
-- Phase 6 backfill in 053's body (one workspace + one workspace_members row
-- per existing user). 055 references those rows when backfilling per-table
-- workspace_id columns; without 053's backfill, the UPDATEs below silently
-- set workspace_id = NULL on existing rows.
```

Rewrites RLS predicates on the 17 policy sites (10 tables) enumerated in reconciliation row #3. For each table, the pattern is:

```sql
-- Example: conversations (was: auth.uid() = user_id)
DROP POLICY conversations_select_self ON public.conversations;
CREATE POLICY conversations_select_member ON public.conversations FOR SELECT
  USING (public.is_workspace_member(conversations.workspace_id, auth.uid()));
```

But conversations does NOT yet have a `workspace_id` column. So 055 ALSO adds `workspace_id uuid` columns to these tables with backfill:

```sql
ALTER TABLE public.conversations ADD COLUMN workspace_id uuid REFERENCES public.workspaces(id);
-- Backfill from user_id → workspaces (one per user post-Phase 6 backfill)
UPDATE public.conversations c SET workspace_id = m.workspace_id
  FROM public.workspace_members m WHERE c.user_id = m.user_id
    AND c.workspace_id IS DISTINCT FROM m.workspace_id;  -- IS DISTINCT FROM per learning
ALTER TABLE public.conversations ALTER COLUMN workspace_id SET NOT NULL;
```

Apply same pattern to: messages (001), kb_share_links (017), push_subscriptions (020 — all 4 policies), concurrency_slots (029), audit_byok_use (037 — `workspace_id` ON TOP OF founder_id, both retained for cap-enforcement TOCTOU semantics per migration 046's RV1 design), dsar_export_jobs (041), scope_grants (048 — workspace_id on top of founder_id), multi_source_dedup (052). For `message_attachments` (019), `messages` external-drafts policies (046), and `action_sends` (051) — these route via the `is_message_owner` helper; verify each via `git grep -nE "is_message_owner\(" apps/web-platform/supabase/migrations/` and either extend `is_message_owner` to accept a workspace_id arg OR add a sibling `is_message_owner_in_workspace`. `team_names` (018) stays per-user (NG10 — conversation labels are not workspace-shared). `runtime_cost_state` columns on `public.users` stay user-keyed (per reconciliation row #2 — PR-F invariant).

**Aggregate view:**
```sql
CREATE VIEW public.workspace_cost_aggregate AS
  SELECT w.id AS workspace_id, w.name,
    SUM(a.unit_cost_cents)::int AS cents_last_hour,
    MAX(a.ts) AS last_use_at
  FROM public.workspaces w
  LEFT JOIN public.workspace_members m ON m.workspace_id = w.id
  LEFT JOIN public.audit_byok_use a
    ON a.founder_id = m.user_id AND a.ts >= now() - interval '1 hour'
  GROUP BY w.id, w.name;
ALTER VIEW public.workspace_cost_aggregate SET (security_invoker = true);  -- RLS-aware
```

Backfill `audit_byok_use.workspace_id` with one statement guarded by `DO $$ ... GET DIAGNOSTICS rc = ROW_COUNT; RAISE NOTICE` per learning.

### Phase 2: Filesystem layout + sandbox

#### Phase 2.1: workspace.ts resolver split

**Files to edit:**
- `apps/web-platform/server/workspace.ts:35-37,67,121,227,247` — `getWorkspacesRoot()` keeps its env-var contract. `provisionWorkspace()` and siblings switch from `userId` to `workspaceId` parameter; new helper `resolveWorkspacePathForUser(userId)` reads `workspace_members` for the user's primary workspace and returns `join(root, workspaceId)`.
- New file: `apps/web-platform/server/workspace-resolver.ts` — `getCurrentOrganizationId(userId, requestCookies)`, `getDefaultWorkspaceForUser(userId)`. Implements **AC-FLOW1** (default-org resolver): user has exactly one membership → that workspace is default; user has >1 → cookie `current_organization_id` is authoritative, fallback to `MIN(created_at)` if cookie absent.

#### Phase 2.2: Filesystem migration script

**File to create:** `apps/web-platform/server/workspace-fs-migrate.ts` — idempotent, called once during deploy:

```ts
// For each user in workspace_members where workspace_id != user_id:
//   1. Read realpathSync(/workspaces/<userId>) — must match expected legacy
//   2. Atomically mv to /workspaces/<workspace_id>
//   3. Create symlink /workspaces/<userId> → /workspaces/<workspace_id>
//   4. Assert lstatSync(/workspaces/<userId>).isSymbolicLink() && realpathSync resolves
// Per learning 2026-03-20-symlink-escape-cwe59-workspace-sandbox: realpathSync BOTH sides
```

This script runs via a one-shot Supabase MCP call (`execute_sql` against deploy log table) + `bash apps/web-platform/server/workspace-fs-migrate.ts` SSH command. **NOT a Post-merge operator step** — wired into the deploy pipeline.

#### Phase 2.3: sandbox.ts containment

**Files to edit:**
- `apps/web-platform/server/sandbox.ts:105,112-141` — bwrap mount reads `workspace_path` from `user.workspace_path` (already DB-sourced per agent-runner.ts:886-894). Update path containment regex at line 105 to accept BOTH `/workspaces/<userId>` (symlinked) and `/workspaces/<workspace_id>` (canonical). Containment check MUST use `fs.realpathSync` on the resolved target — never `path.resolve` — per CWE-59 learning.

#### Phase 2.4: agent-env.ts allowlist audit

**File to edit:** `apps/web-platform/server/agent-env.ts` — confirm `ALLOWED_KEYS` does NOT include any new server-only env var introduced by this plan (`FLAG_TEAM_WORKSPACE_INVITE`, `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`). Per `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526`: server secrets must never reach agent subprocess.

#### Phase 2.5: tool-path-checker completeness

**File to edit:** `apps/web-platform/server/tool-path-checker.ts` — no new path-bearing tool is introduced by this plan, so coverage stays. Verify via existing completeness test.

### Phase 3: BYOK split (workspace context vs key owner)

#### Phase 3.1: byok-lease.ts parameter split

**File to edit:** `apps/web-platform/server/byok-lease.ts:154-179`

Current shape: `runWithByokLease(userId, fn)` derives KEK from `userId`, looks up `api_keys` for `userId`, runs `fn`.

New shape: `runWithByokLease({ workspaceContextUserId, keyOwnerUserId }, fn)` — `keyOwnerUserId` resolves to the actual `api_keys.user_id` (typically same as caller), `workspaceContextUserId` is the userId whose workspace is being acted upon. `record_byok_use_and_check_cap()` (PR-F invariant) keeps per-founder semantic; new code path threads `workspace_id` separately to `audit_byok_use.workspace_id`.

#### Phase 3.2: Fail-closed when member has no BYOK

**AC-D from CPO:** Member-without-BYOK triggers explicit error, NOT silent fallback to owner's key.

Error class `MissingByokKeyError` (extends existing error pattern). UI surface: dashboard banner "Configure your BYOK key to run agents in this workspace" + link to `/dashboard/settings/byok`. No fallback to owner's key. `byok_delegations` table (#4232) is the future remediation; documented in error help link.

### Phase 4: Two-key feature flag

**File to edit:** `apps/web-platform/lib/feature-flags/server.ts`

Extend FLAG_VARS pattern:

```ts
const FLAG_VARS = {
  "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
  "dev-signin": "FLAG_DEV_SIGNIN",
  "team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE",
} as const;

let cachedOrgAllowlist: Set<string> | null = null;
function getOrgAllowlist(): Set<string> {
  if (cachedOrgAllowlist) return cachedOrgAllowlist;
  const raw = process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS || "";
  cachedOrgAllowlist = new Set(raw.split(",").map(s => s.trim()).filter(Boolean));
  return cachedOrgAllowlist;
}

export function isTeamWorkspaceInviteEnabled(orgId: string): boolean {
  if (!getFlag("team-workspace-invite")) return false;
  if (!getOrgAllowlist().has(orgId)) return false;
  return true;
}
```

Boot-time Sentry breadcrumb when both keys evaluate true in prd (helps catch typo-flip of env on prd). Add to `apps/web-platform/server/boot.ts` (or equivalent server-init module).

### Phase 5: Settings UI + org-switcher

#### Phase 5.1: Resolve `/dashboard/settings/team` collision

**Files to edit:**
- Rename `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` → `apps/web-platform/app/(dashboard)/dashboard/settings/conversation-names/page.tsx`
- Rename `apps/web-platform/components/settings/team-settings.tsx` → `apps/web-platform/components/settings/conversation-names-settings.tsx` (inside still uses `team_names` table; rename is route-level only)
- Update sidebar nav (`apps/web-platform/components/settings/sidebar.tsx` or equivalent — verify exact path at /work-time via `git grep -nE '"team"|/settings/team' apps/web-platform/components/`)
- Add redirect from `/dashboard/settings/team` (old route) → `/dashboard/settings/conversation-names` for users with bookmarks — keep redirect for 1 release cycle then drop

#### Phase 5.2: New `/dashboard/settings/team` membership page

**File to create:** `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx`

```tsx
// Server-side: read user's current org's member list via supabase JS client
// Wrap with feature-flag gate: notFound() if !isTeamWorkspaceInviteEnabled(orgId)
// Render: member list (rows: avatar, name, email, role badge, kebab menu with Remove)
//          "Invite member" CTA (opens InviteMemberModal)
//          Empty state copy (1 member): "You're solo here. Invite someone to collaborate."
```

**File to create:** `apps/web-platform/components/settings/invite-member-modal.tsx` — form fields per ux-design-lead wireframe: user_id-or-email input, role selector (Owner / Member), attestation checkbox (required), Add CTA disabled until checked.

#### Phase 5.3: Org-switcher in dashboard layout

**File to edit:** `apps/web-platform/app/(dashboard)/layout.tsx`

Add `<OrgSwitcher />` component to header. Component reads workspace_members count for current user; renders dropdown ONLY when count > 1 (per spec FR7 + AC-C).

**File to create:** `apps/web-platform/components/dashboard/org-switcher.tsx`

#### Phase 5.4: Multi-tab org-switch race (AC-FLOW3)

**Decision (Kieran C4 picked):** `current_organization_id` is a **Supabase Auth JWT custom claim** added via a custom access-token hook (migration 047 precedent — verify exact migration number at /work-time). Per-session, propagates to all tabs on the next access-token refresh (~1 hour TTL; force-refresh on org-switch via `supabase.auth.refreshSession()` so tab B picks up the new value within seconds).

**Why JWT claim over server-side session table:**
- Server-side session table is new infra (storage + RLS + cleanup + cache invalidation) for a single value.
- JWT custom-claim hook already has migration precedent in this codebase.
- Refresh path on switch is one line; multi-tab propagation is automatic on next refresh.

**Why session-scoped (not per-tab cookie):** per-tab cookie creates "tab A is writing to org1 silently while user expects org2" failure mode — wrong-workspace-attribution at single-user-incident threshold.

**Files to create / edit:**
- New migration (likely `056_current_org_jwt_hook.sql` — number bumps if Phase 1 lands 053-055): custom access-token hook reads `current_organization_id` from a per-user `user_session_state(user_id uuid PK, current_organization_id uuid)` minimal table (1 row per user, set on org-switch RPC), injects into the JWT's `app_metadata.current_organization_id`. Migration includes a backfill that sets `current_organization_id = MIN(workspaces.id) FOR EACH user`.
- `apps/web-platform/server/workspace-resolver.ts` — `getCurrentOrganizationId(supabaseSession)` reads from JWT claim, falls back to user's default org if claim absent (covers single-membership AC-FLOW1 case).
- `apps/web-platform/components/dashboard/org-switcher.tsx` — on selection, calls `set_current_organization_id(p_org_id)` RPC (writes user_session_state row), then `supabase.auth.refreshSession()` to force JWT refresh.
- `apps/web-platform/middleware.ts` — no change needed (JWT is already validated by Supabase Auth middleware).

#### Phase 5.5: Member-removal in-flight agent SIGTERM (AC-FLOW2)

**Kieran C5 correction:** `agent-session-registry.ts` currently exposes `abortSession(userId, conversationId)`, `abortAllUserSessions(userId)`, `forEachSessionForConversation` — **no workspace-keyed kill API**. Sessions are keyed `userId:conversationId[:leaderId]` with no `workspace_id` field. Two corrections required:

1. **Extend session registration to carry workspace_id.** When a session is registered (via the start-session WS handler), include the `workspace_id` resolved from the JWT custom claim (Phase 5.4). The session record gains a `workspaceId: string` field.

2. **Add `abortAllWorkspaceMemberSessions(workspaceId: string, userId: string)` API** that scans the registry for sessions matching BOTH userId AND workspaceId, then SIGTERMs each. Using `abortAllUserSessions(userId)` would over-kill: removing Harry from jikigai workspace would also abort his sessions in his personal workspace.

**Files to edit:**
- `apps/web-platform/server/agent-session-registry.ts` — add `workspaceId` field to session record; add `abortAllWorkspaceMemberSessions(workspaceId, userId)` method
- `apps/web-platform/server/ws-handler.ts` — start-session handler reads JWT current_organization_id → resolves workspace_id → passes to registry registration. Handles `workspace_removed` event; closes socket with `WS_CLOSE_CODES.MEMBERSHIP_REVOKED` (new code).
- `apps/web-platform/server/workspace-membership.ts` — `remove_workspace_member` RPC's TS wrapper calls `abortAllWorkspaceMemberSessions(workspace_id, removed_user_id)` after the SQL RPC returns.

Cost row for the partial run writes with `status='interrupted'`. Removed member's next WS poll receives a `workspace_removed` event → frontend shows "You were removed from <org name>" terminal screen.

### Phase 6: Backfill (G11)

**File to create:** `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql` — backfill section (appended to migration 053 after table creation):

```sql
DO $$
DECLARE
  v_rc int;
BEGIN
  -- Create one org per existing user; name=NULL (AC-B; UI suppresses)
  INSERT INTO public.organizations (id, name, owner_user_id, created_at)
  SELECT gen_random_uuid(), NULL, u.id, u.created_at
  FROM auth.users u
  WHERE NOT EXISTS (
    SELECT 1 FROM public.organizations WHERE owner_user_id = u.id
  );  -- IS DISTINCT FROM via NOT EXISTS (idempotent)
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill-orgs] Inserted % organization rows', v_rc;

  -- Create one workspace per org
  INSERT INTO public.workspaces (id, organization_id, name, created_at)
  SELECT o.owner_user_id, o.id, NULL, o.created_at
  FROM public.organizations o
  WHERE NOT EXISTS (SELECT 1 FROM public.workspaces WHERE organization_id = o.id);
  -- workspace.id = owner_user_id (deliberate: preserves backward-compat with audit/cost rows
  -- that reference user_id; symlink layer makes /workspaces/<userId> = /workspaces/<workspaceId>)
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill-workspaces] Inserted % workspace rows', v_rc;

  -- Create owner membership row per workspace
  INSERT INTO public.workspace_members (workspace_id, user_id, role, attestation_id, created_at)
  SELECT w.id, w.id, 'owner', NULL, w.created_at
  FROM public.workspaces w
  WHERE NOT EXISTS (
    SELECT 1 FROM public.workspace_members WHERE workspace_id = w.id AND user_id = w.id
  );
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[053-backfill-members] Inserted % owner-membership rows', v_rc;
END $$;
```

**File to edit:** Existing `handle_new_user` trigger (if present; verify at /work-time via `git grep -nE 'CREATE.*handle_new_user'` in migrations dir). If trigger exists, extend to create org + workspace + workspace_members in same transaction. Per `2026-03-20-supabase-trigger-fallback-parity`: TS fallback path uses `upsert({onConflict:["workspace_id","user_id"], ignoreDuplicates:true})` to race the trigger safely.

Per `2026-03-20-supabase-trigger-boolean-cast-safety`: no `::boolean` casts on `raw_user_meta_data`.

### Phase 7: DSAR endpoint extension (G14)

**File to edit:** `apps/web-platform/server/dsar-reauth.ts`

Add query path keyed on `workspace_member_id` JOIN `workspace_members` so departed members can serve Art. 15/17/20 over their identifiable rows. Plan includes this **in-PR** (NOT deferred to #4230) because CLO required DSAR routing landed before flag flips ON for jikigai-only (even though jikigai is internal — Harry has Art. 15/17/20 rights regardless).

#4230 stays open as the broader "external-customer-ready DSAR enhancements" tracker.

### Phase 8: Sentinel sweep + observability + tests

#### Phase 8.1: Sentinel sweep (TR6)

PR body MUST include output of:

```bash
git grep -nE "(owner_id|user_id|founder_id)\s*=\s*(auth\.uid\(\)|session\.user_id|req\.user)" \
  apps/web-platform/server/ apps/web-platform/app/api/ \
  | grep -v -E "\.test\.|/test/"
```

Each match annotated as `converted` (now reads `is_workspace_member`) or `kept` (with one-line rationale — e.g., auth-callback writes that legitimately target the calling user's row).

#### Phase 8.2: Tests

**File to create:** `apps/web-platform/test/server/workspace-members.test.ts`
- Invite/remove RPC happy path
- `is_workspace_member()` predicate happy/sad
- WORM trigger rejects UPDATE/DELETE on `workspace_member_attestations`
- Backfill idempotency (run twice, second run inserts 0 rows)
- Default-org resolver (AC-FLOW1)

**File to edit:** `apps/web-platform/test/sandbox-isolation.test.ts`
- New case A: two users in same workspace see same files
- New case B: two users in different workspaces see nothing of each other's
- Uses new `createSharedWorkspaceMembers([userA, userB])` helper

**File to create:** `apps/web-platform/test/server/byok-cost-attribution.test.ts`
- TR7: Harry's agent run inside Jean's workspace inserts `audit_byok_use` row with `user_id = Harry, workspace_id = jikigai, founder_id = Harry`
- BYOK KEK derived from Harry's userId, not Jean's

**File to create:** `apps/web-platform/test/feature-flags/team-workspace-invite.test.ts`
- AC-F: Flag returns false when env unset
- Flag returns false when org NOT in allowlist
- Flag returns true ONLY when both true
- Boot-time Sentry breadcrumb fires once

**File to create:** `apps/web-platform/test/e2e/team-membership.e2e.ts` (Playwright)
- Owner invites Member via UI; member appears in list
- Flag OFF: `/dashboard/settings/team` returns 404, no nav entry, no `team` string in client bundle (AC-A)
- Org-switcher hidden for count=1 user (AC-C)
- Empty state for solo backfilled user shows correct copy (AC-B)
- Owner cannot remove self (AC-FLOW4)

#### Phase 8.3: Observability

See `## Observability` section below.

### Phase 9: Rollback runbook (AC-G)

**File to create:** `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md`

Documents the brand-survival-incident response:
1. Disable feature flag: `doppler secrets set FLAG_TEAM_WORKSPACE_INVITE=0 --config prd`
2. Migrate down migrations 053 + 058 + 059 (idempotent down-migrations included in each)
3. Restore `auth.uid() = user_id` predicates from migration backups
4. Drop `/workspaces/<userId>` symlinks (atomically — script in `apps/web-platform/server/workspace-fs-rollback.ts`)
5. Notify Harry (and any in-band members) of revert; preserve audit logs
6. Post-mortem: `/soleur:compound` → learning file

Commits BEFORE migration 053 lands (so the runbook is on `main` when the migration ships).

### Phase 10: Legal scaffolding (parallel PR)

**Not gated by this PR's merge.** Tracked separately. CLO recommended specialists:

- `legal-document-generator` drafts: ToS 2.2.0 §Workspace Members + AUP §5.5 attestation + DPD §2.3 co-member disclosure + Side Letter template (Jean → Harry)
- `legal-compliance-auditor` runs after generator merges; verifies cross-doc consistency, Article 30 register entry, PA-2/PA-8 co-member data category

These ship as a separate PR on branch `feat-team-workspace-legal-scaffolding`. Flag flip on this PR's branch BLOCKED until that PR merges. The PR body's "## Acceptance Criteria → ### Pre-flag-flip" subsection cross-references the legal PR number.

## Files to Edit

| Path | Edit |
|---|---|
| `apps/web-platform/server/workspace.ts` | Switch userId→workspaceId parameter; new `resolveWorkspacePathForUser`; lines 35-37, 67, 121, 227, 247 |
| `apps/web-platform/server/agent-runner.ts` | Line 886-894: workspace_path resolver uses new context-aware helper |
| `apps/web-platform/server/agent-runner-sandbox-config.ts` | **Real bwrap mount file** (Kieran C1). Update `--bind` / `--ro-bind` paths to reference `workspace_id` rather than legacy `userId` parameter. |
| `apps/web-platform/server/sandbox.ts` | Lines 110-148: `isPathInWorkspace` regex accepts both legacy `/workspaces/<userId>` (symlink-resolved) and canonical `/workspaces/<workspace_id>`; `realpathSync` both sides per CWE-59 learning |
| `apps/web-platform/server/dsar-export.ts` | **Kieran N5:** sibling DSAR endpoint queries `.eq("user_id", expectedUserId)` at lines 291, 311, 415, 434 — extend to JOIN `workspace_members` for departed-member coverage; identical to dsar-reauth.ts shape |
| `apps/web-platform/server/byok-lease.ts` | Lines 154-179: split `workspaceContextUserId` / `keyOwnerUserId` parameters |
| `apps/web-platform/server/agent-env.ts` | Confirm ALLOWED_KEYS does NOT include new env vars |
| `apps/web-platform/server/dsar-reauth.ts` | Extend to query via workspace_member_id join |
| `apps/web-platform/server/account-delete.ts` | Wire anonymise_workspace_member_attestations + anonymise_workspace_members + anonymise_organization_membership RPCs in FK-reverse order BEFORE auth.users.delete (Art. 17 caller-site wiring per GDPR-Art-17-caller) |
| `apps/web-platform/server/agent-session-registry.ts` | SIGTERM in-flight session on remove_workspace_member |
| `apps/web-platform/server/ws-handler.ts` | Handle `workspace_removed` event; new close code MEMBERSHIP_REVOKED |
| `apps/web-platform/lib/feature-flags/server.ts` | Add FLAG_VARS row; add `isTeamWorkspaceInviteEnabled(orgId)` 2-key helper; boot Sentry breadcrumb |
| `apps/web-platform/middleware.ts` | Read `current_organization_id` from session |
| `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` | Rename to `/conversation-names`; new file becomes membership page |
| `apps/web-platform/components/settings/team-settings.tsx` | Rename to `conversation-names-settings.tsx` |
| `apps/web-platform/components/settings/sidebar.tsx` | Update nav entries; new "Members" link (gated by flag); rename "Team" → "Conversation names" |
| `apps/web-platform/app/(dashboard)/layout.tsx` | Mount `<OrgSwitcher />` |
| `apps/web-platform/.service-role-allowlist` | Add `workspace-membership.ts` + `workspace-resolver.ts` (PERMANENT) |
| `knowledge-base/legal/compliance-posture.md` | Active Items row for Phase 10 legal-PR dependency |
| `knowledge-base/legal/article-30-register.md` | Co-member data category on PA-2 (jikigai org as test case) |
| `knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md` | Phase 0.6 reconciliation amendment |
| `knowledge-base/product/roadmap.md` | Move #4229 status to In-progress; reference rollback runbook |

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql` | Phase 1.1 |
| `apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql` | Phase 1.2 |
| `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql` | Phase 1.3 |
| `apps/web-platform/supabase/migrations/060_current_organization_jwt_hook.sql` | Phase 5.4: user_session_state table + custom access-token hook injecting `app_metadata.current_organization_id` (Kieran C4) |
| `apps/web-platform/server/workspace-membership.ts` | invite_workspace_member / remove_workspace_member RPC wrappers |
| `apps/web-platform/server/workspace-resolver.ts` | getCurrentOrganizationId, getDefaultWorkspaceForUser |
| `apps/web-platform/server/workspace-fs-migrate.ts` | Idempotent fs migration script (Phase 2.2) |
| `apps/web-platform/server/workspace-fs-rollback.ts` | Symlink rollback (Phase 9) |
| `apps/web-platform/components/dashboard/org-switcher.tsx` | Phase 5.3 |
| `apps/web-platform/components/settings/invite-member-modal.tsx` | Phase 5.2 |
| `apps/web-platform/components/settings/team-membership-list.tsx` | Phase 5.2 |
| `apps/web-platform/test/server/workspace-members.test.ts` | Phase 8.2 |
| `apps/web-platform/test/server/byok-cost-attribution.test.ts` | Phase 8.2 (TR7) |
| `apps/web-platform/test/feature-flags/team-workspace-invite.test.ts` | Phase 8.2 (AC-F) |
| `apps/web-platform/test/e2e/team-membership.e2e.ts` | Phase 8.2 (E2E) |
| `apps/web-platform/test/helpers/workspace-members-fixtures.ts` | createSharedWorkspaceMembers |
| `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md` | Phase 9 |
| `knowledge-base/architecture/adr/NNNN-organizations-and-workspace-members.md` | Phase 0.4 (via `/soleur:architecture create`) |

## Open Code-Review Overlap

Run check at /work-time per skill Phase 1.7.5. Likely overlap candidates (verify with the jq probe in skill body):

- #2778 (post-MVP projects-table refactor): compatible — orthogonal namespace
- #3637 (DSAR endpoint in-progress): cohabits `dsar-reauth.ts`; sequence after #3637 if still open
- `feat-pr-d-attachments-storage-tenant-rls`: extends 045's `is_message_owner` shape; Phase 0.1 verifies coordination

`None` of the open `code-review` labeled issues yet known to overlap; final overlap check runs at /work time.

## Observability

```yaml
liveness_signal:
  what: "workspace_member_attestations row count delta (24h)"
  cadence: "every 1 hour"
  alert_target: "Sentry → no rows for 72h while FLAG=true → warn (membership system unused)"
  configured_in: ".github/workflows/scheduled-membership-health.yml"

error_reporting:
  destination: "Sentry (PII-scrubbed; workspace_id only, no user_id raw)"
  fail_loud: "MissingByokKeyError + WorkspaceMembershipRevokedError + AttestationWriteError tagged event_class=brand-survival"
  breadcrumbs:
    - "MissingByokKeyError: Sentry breadcrumb (info-level) on every fail-closed encounter (Kieran N4). Captures workspace_id, user_id_hash; never raw user_id or key prefix."
    - "WorkspaceMembershipRevokedError: breadcrumb on session SIGTERM during member removal."
    - "Two-key flag evaluates true in prd boot: breadcrumb once at server boot (AC-F)."

failure_modes:
  - mode: "RLS predicate widened — cross-workspace read"
    detection: "scheduled probe: SELECT against jikigai workspace from secondary test-user session → row count > 0 fires P0"
    alert_route: "Sentry P0 → PagerDuty equivalent (operator)"
  - mode: "BYOK key silent fallback — cost mis-attribution"
    detection: "audit_byok_use row where user_id != founder_id AND workspace_id IS NULL fires post-commit"
    alert_route: "Sentry P1 → daily triage"
  - mode: "Feature flag mis-evaluated true in prd"
    detection: "boot-time breadcrumb: flag=true in NODE_ENV=production logs (expected pattern: org_allowlist non-empty, flag=true → log once)"
    alert_route: "Sentry breadcrumb → daily triage; alert if breadcrumb absent for >48h after flag enable"
  - mode: "Symlink dangling / containment escape"
    detection: "workspace-fs-migrate.ts asserts realpathSync + lstatSync each migration; failures captured in deploy log"
    alert_route: "Deploy log → fail-fast (block rollout)"
  - mode: "Member removal — in-flight agent leaked cost"
    detection: "audit_byok_use row where user_id NOT IN workspace_members AND ts > workspace_members.deleted_at fires"
    alert_route: "Sentry P1"

logs:
  where: "Better Stack (pino → BS) — structured workspace_id tag only, never user_id raw"
  retention: "30 days (standard)"

discoverability_test:
  command: "curl -s https://app.soleur.ai/api/health/team-membership | jq .status"
  expected_output: "\"ok\" when migrations 053 + 058 + 059 applied, flag wired, attestation table queryable. Returns \"degraded\" with reason field if helper missing."
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** Migrations 053-055 land in order; idempotent on re-run; backfill prints `RAISE NOTICE` audit lines
- [ ] **AC2.** `is_workspace_member()` helper pins `SET search_path = public, pg_temp`; `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated, service_role`
- [ ] **AC3.** `workspace_member_attestations` WORM trigger rejects UPDATE/DELETE; tested via `expect(...).rejects.toThrow(/WORM/)`
- [ ] **AC4.** Sentinel sweep PR body shows annotated grep output for 14 RLS sites + every byok-related read path; each `converted` or `kept` (with one-line rationale per kept site)
- [ ] **AC5.** ADR committed at `knowledge-base/architecture/adr/NNNN-organizations-and-workspace-members.md` BEFORE migration 053 commit
- [ ] **AC6.** Spec.md reconciliation amendment committed at Phase 0.6 (drop kb_files/kb_chunks; reframe G4; fix line numbers; name route rename)
- [ ] **AC-A.** Feature flag OFF: `/dashboard/settings/team` returns HTTP 404; sidebar nav does NOT render "Members" link; client bundle grep for "Members"/"team-workspace-invite" returns 0 matches; no robots/sitemap entry
- [ ] **AC-B.** Backfill creates `organizations.name = NULL` for existing users; UI suppresses org name in chrome when `workspace_members.count = 1`
- [ ] **AC-C.** Org-switcher component AND workspace-identity chip in header render ONLY when user belongs to >1 organization (header chrome for solo users = SOLEUR wordmark + avatar only; no chip, no dropdown trigger); verified via snapshot test (solo header) + Playwright (multi-org header)
- [x] **AC-D.** Member without BYOK key triggers `MissingByokKeyError` (no fallback to owner's key); error UI links to `/dashboard/settings/byok`; documented in error help page — Phase 3.2: `MissingByokKeyError` defined in `apps/web-platform/server/byok-lease.ts`; lease uses `.maybeSingle()` to distinguish missing-row (MissingByokKeyError) from DB-error (ByokLeaseError cause=fetch_failed); cc-dispatcher.ts surfaces WS `errorCode: "byok_key_missing"` with message "Configure your BYOK key to run agents in this workspace."; Sentry breadcrumb (info-level) via `reportMissingByokKey` captures workspace_id + sha256:16 user-id hash per Kieran N4. Migration 057 widens both `write_byok_audit` + `record_byok_use_and_check_cap` RPCs to thread `p_workspace_id` into `audit_byok_use`.
- [ ] **AC-E.** `git grep -nE 'stripe\\.(customers\\.update|customers\\.create|subscriptions\\.update|invoices\\.create)' apps/web-platform/server/ apps/web-platform/app/api/` shows no new `organization_id`/`workspace_id` in metadata payloads
- [ ] **AC-F.** Two-key flag gate: `isTeamWorkspaceInviteEnabled(orgId)` returns true ONLY when `FLAG_TEAM_WORKSPACE_INVITE=1` AND `orgId ∈ TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`; boot-time Sentry breadcrumb fires once when both true in prd
- [ ] **AC-G.** Rollback runbook committed at `knowledge-base/project/specs/feat-team-workspace-multi-user/rollback.md` BEFORE migration 053 commit
- [ ] **AC-FLOW1.** Default-org resolver: user with exactly one workspace_members row has `current_organization_id` set automatically on login; verified by E2E test
- [ ] **AC-FLOW2.** Member removal SIGTERMs in-flight agent session; `audit_byok_use` row for partial run writes with `status='interrupted'`; removed user's next WS event = `workspace_removed`; UI shows terminal screen
- [ ] **AC-FLOW3.** Multi-tab race: `current_organization_id` is session-scoped; tab A switch → tab B's next request also uses new org; verified via Playwright multi-context test
- [ ] **AC-FLOW4.** Owner cannot remove own membership: `remove_workspace_member()` raises exception when caller_id = invitee_id AND role = 'owner'
- [ ] **AC7.** Sandbox isolation: new `sandbox-isolation.test.ts` cases (same-workspace two-user see same files; cross-workspace two-user see nothing) pass
- [ ] **AC8.** BYOK cost-attribution: integration test confirms Harry's agent run in Jean's workspace writes `audit_byok_use` row with Harry's user_id + Jean's workspace_id; HKDF derived from Harry's userId
- [ ] **AC9.** Filesystem migration script idempotent: second run inserts 0 symlinks, no race-condition errors
- [ ] **AC10.** DSAR endpoint (Phase 7): query by workspace_member_id returns Harry's identifiable rows post-removal; existing founder_id queries unaffected
- [ ] **AC11.** `agent-env.ts` ALLOWED_KEYS audit: no new env var leaks to subprocess (test asserts absence)
- [ ] **AC12.** PR body references #4229 with `Closes #4229`; references Phase 10 legal PR number as a flag-flip prerequisite
- [ ] **AC-GDPR-6.** Each new table (organizations, workspaces, workspace_members, workspace_member_attestations) and each new `workspace_id` column on existing tables has a `-- LAWFUL_BASIS:` comment block in the migration. Org/workspace/member rows annotated Art. 6(1)(f) legitimate interest (controller operating workspace); attestation rows annotated Art. 6(1)(b) contract performance + Art. 6(1)(f) for audit trail
- [ ] **AC-GDPR-5e.** Migration 054 header comment block documents retention: attestation rows retained for workspace lifetime + 7 years post-membership-removal, then anonymised via `anonymise_workspace_member_attestations(p_attestation_id)` (nulls user_id-bearing columns; preserves attestation_text + accepted_at as the immutable legal record)
- [ ] **AC-GDPR-17.** Migration 054 ships three SECURITY DEFINER anonymise RPCs (`anonymise_workspace_member_attestations`, `anonymise_workspace_members`, `anonymise_organization_membership`), `search_path = public, pg_temp`, REVOKE ALL PUBLIC, GRANT EXECUTE to service_role only. Each nulls identifiable columns; preserves the act-of-the-record (timestamps, attestation_text→`'<anonymised>'`). Mirror migration 048's `anonymise_scope_grants` exactly
- [ ] **AC-GDPR-17-CALLER.** `apps/web-platform/server/account-delete.ts` invokes anonymise RPCs in FK-reverse order (attestations → workspace_members → workspaces → organizations) BEFORE `auth.admin.deleteUser`. Integration test exercises the full user-deletion path against migrations 053 + 058 + 059; test passes when the RESTRICT cascade completes successfully
- [ ] **AC-LEGAL-FLIP.** `TEAM_WORKSPACE_INVITE` flag MUST NOT evaluate to `1` in any environment until the legal-scaffolding PR (Phase 10) is merged on `main`. Encoded as a Doppler config audit step in `/soleur:ship`; PR body references the legal-PR number explicitly
- [ ] **AC-RATE-LIMIT.** `invite_workspace_member` RPC and `/api/workspace/invite` route apply a rate-limit (5 invites/min/owner). Existing rate-limit module reused if present; otherwise documented as `code-review` follow-up scope-out (with rationale: jikigai-only allowlist bounds exposure)
- [ ] **AC-ROLE-UNION.** Per `cq-union-widening-grep-three-patterns` (Kieran N6): when `workspace_members.role` enum is introduced (`'owner' | 'member'`), PR body includes output of three pattern greps over `apps/web-platform/` for: (1) `role ===` usage sites, (2) `_exhaustive: never` exhaustiveness rails, (3) `\.role\?` optional-chained access. New ladder/switch sites must enumerate both `'owner'` and `'member'` cases

### Post-merge (operator)

NONE. Per `2026-05-12-mid-plan-pause-gates-and-operator-step-pushback`: all Supabase MCP / gh / Playwright steps run inline at /work or /ship time. Migration apply is automated via the existing migration runner; flag-flip in Doppler is a separate workflow gated on the legal-scaffolding PR's merge (tracked in the legal PR's tasks.md, not here).

## Risks

- **R1. PR-D collision on `is_message_owner` shape.** Mitigation: Phase 0.1 probe; lock signature to whichever shape ships on `main` first. Owner: this PR's author.
- **R2. Backfill race with `handle_new_user` trigger.** Mitigation: TS fallback uses `upsert(onConflict, ignoreDuplicates:true)` per learning 2026-03-20-supabase-trigger-fallback-parity.
- **R3. Sentinel sweep miss — silent wrong-workspace write.** Mitigation: TR6 grep + AC4 PR-body enumeration; Sentry breadcrumb when `workspace_id IS NULL` on writes to user-keyed tables (Phase 8.3 failure_modes #2).
- **R4. 2-key flag gate bypass — Doppler typo flips prd.** Mitigation: AC-F two-key requirement; boot-time Sentry breadcrumb; alert if breadcrumb absent for >48h after flag enable (Phase 8.3 failure_modes #3).
- **R5. Filesystem symlink atomicity failure.** Mitigation: per-directory mv-then-symlink with `realpathSync` + `lstatSync` checks (Phase 2.2); failure fails-fast at deploy.
- **R6. BYOK lease parameter split — silent fallback regression.** Mitigation: AC8 integration test; remove all fallback-to-owner-key code paths in byok-lease.ts (fail-closed per AC-D).
- **R7. Multi-tab session-scoped org switch surprises user.** Mitigation: AC-FLOW3 Playwright multi-context test; UI badge during switch.
- **R8. Member-removal in-flight cost row attribution.** Mitigation: AC-FLOW2 SIGTERM + status='interrupted'; failure_modes #5 detects orphan rows.
- **R9. `ON DELETE RESTRICT` blocks Art. 17 user deletion without anonymise wiring.** Mitigation: AC-GDPR-17 + AC-GDPR-17-CALLER ship the three anonymise RPCs in migration 058 and wire them in `account-delete.ts` in FK-reverse order. Integration test exercises the full deletion path.
- **R10. Flag flip races legal scaffolding merge.** Mitigation: AC-LEGAL-FLIP enforces Doppler audit step in `/soleur:ship`; PR body cross-references legal-PR number.
- **R11. Invite endpoint enumeration oracle.** Mitigation: AC-RATE-LIMIT (5/min/owner). If existing rate-limit module is absent, ship as `code-review` follow-up with documented bounded exposure (jikigai-only allowlist).

## Sharp Edges

- **Plan budget override (10-13d vs 10d ceiling).** CFO acknowledged at brainstorm. At /work-time, if any single phase exceeds 4 days, raise to operator before continuing — sliding scope on the heavier end (FR9 invite UI, FR7 org-switcher polish) is acceptable; sliding migrations/RLS is not.
- **`requires_adr: true` MUST land BEFORE migration 053.** Plan Phase 0.4 establishes; /work agent should NOT start Phase 1.1 without ADR file on disk.
- **PR-D `is_message_owner` divergence:** sql STABLE + pg_catalog vs plpgsql + public. Whichever lands first sets the precedent for `is_workspace_member()`. Phase 0.1 is the disambiguation point.
- **`/dashboard/settings/team` route rename:** the existing `team_names` settings page (display labels for conversations, migration 018) collides with this PR's intended membership page. Rename to `/conversation-names`. Update sidebar, redirect old URL for 1 release.
- **NO `### Post-merge (operator)` steps in tasks.md.** Per learning `2026-05-12-mid-plan-pause-gates-and-operator-step-pushback`: Supabase MCP applies migrations inline; `gh pr ready` runs inline; Playwright runs inline. Flag flip in prd is the only "human decision" step and lives on the legal-PR side (because legal scaffolding gates it).
- **A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The above section is filled; preserve at deepen-plan time.**
- **HKDF salt MUST stay empty; workspace_id (if ever folded into key derivation) goes in `info` not salt** per `2026-03-20-hkdf-salt-info-parameter-semantics`. This plan does NOT change BYOK key derivation — kept here as a guard against future drift.
- **Column-level GRANT/REVOKE on attestation table:** REVOKE on TABLE first, THEN GRANT(safe_cols). Column-only REVOKE is silently ineffective per `2026-03-20-supabase-column-level-grant-override`.
- **Backfill discriminator MUST be `IS DISTINCT FROM` / `NOT EXISTS`, never timestamp proximity** per `2026-03-20-gdpr-remediation-migration-discriminator-strategy`.
- **NEVER `::boolean` on `raw_user_meta_data->>'...'` in `BEFORE INSERT` on auth.users** per `2026-03-20-supabase-trigger-boolean-cast-safety`.
- **Encrypted columns stay `text` (base64), NEVER `bytea`** per `2026-03-17-postgrest-bytea-base64-mismatch`. No new encrypted columns in this plan; guard against drift.
- **Pencil MCP unavailability fallback:** if ux-design-lead Phase 2.5 returns without wireframes, mark `**Skipped specialists:** ux-design-lead (Pencil MCP not available)` in Domain Review and proceed; document the affordance in `knowledge-base/product/design/team-workspace/notes.md` for future re-pass.
