---
title: "Fix: workspaces display as \"Untitled\" because organizations.name is always NULL"
type: fix
date: 2026-06-01
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new infrastructure (no server, secret, vendor, cron, DNS, TLS, firewall). It is a pure code change against the already-provisioned web-platform — one Supabase migration (applied by the existing web-platform-release.yml#migrate pipeline on merge), one RPC, one Next.js route, two component edits. The only "operator runs" phrasing is a read-only psql discoverability probe (SELECT count), not provisioning. No Terraform changes required. -->

## Enhancement Summary

**Deepened on:** 2026-06-01
**Sections enhanced:** Technical Considerations (precedent-diff), Dependencies & Risks, Sharp Edges
**Gates passed:** 4.6 User-Brand Impact (present, threshold `single-user incident`), 4.7 Observability (5/5 fields, no SSH), 4.8 PAT-shaped (none), 4.4 Precedent-Diff (SECURITY DEFINER RPC + owner-gate diffed against mig 075). 4.5 Network-Outage: skipped (no SSH/network triggers). 4.4 Scheduled-work: skipped (no new cron).

### Key Improvements
1. **Precedent-diff (Phase 4.4):** the rename RPC is confirmed *simpler* than the cited transfer-ownership precedent — no audit GUC, no attestation, no multi-row transaction (see Research Insights below). The `organizations` table has **no** audit trigger (audit triggers target `workspace_members` only), so the rename RPC must NOT set `workspace_audit.actor_user_id`.
2. **Verify-the-negative (Phase 4.45):** confirmed both load-bearing negative claims hold against `origin`-state code — (a) no `NOT NULL` to be added on `organizations.name`; (b) no RLS UPDATE policy exists on `organizations` for `authenticated` (grep of mig 053 shows only SELECT policies), so the RPC is genuinely the sole authenticated write path.
3. **No external infra / scheduled work** — pure code change; IaC + cron gates correctly skip.

### New Considerations Discovered
- The rename RPC's owner-check should use `auth.uid()` + `FOR UPDATE` row lock + `ERRCODE = '42501'` (insufficient_privilege) exactly as mig 075:55-62, but WITHOUT the attestation/self-transfer/target-member guards (irrelevant to a name change).
- Because `organizations` carries no audit trigger, a future audit requirement on org renames would need a NEW trigger — out of scope here, but note it so a reviewer doesn't expect actor-GUC plumbing.

# Fix: workspaces display as "Untitled" in the org switcher (organizations.name is always NULL)

## Overview

Every organization row carries `name = NULL`. The backfill (migration `053_organizations_and_workspace_members.sql:229`), the signup trigger `handle_new_user()` (`053:314`), and every other write path insert `name = NULL`. The dashboard org switcher renders `organizationName ?? "Untitled"` (`server/org-memberships-resolver.ts:146`), so multi-workspace users see a list of indistinguishable "Untitled" rows. The switcher hides itself for solo users (`components/dashboard/org-switcher.tsx:63`, `memberships.length <= 1`), which is why the defect only surfaces once a user belongs to 2+ workspaces.

Migration 053 documented the intended contract verbatim (`053:44-48`): *"New organizations created post-flag-flip MUST set name (enforced at application layer via the invite flow; no NOT NULL constraint here so the backfill stays single-statement)."* That enforcement was deferred to "Phase 5.4" and never built — there is no onboarding name prompt, no name capture in the invite flow, and no rename UI (`/dashboard/settings/team` only lists members + invites).

This plan closes the contract three ways: (a) **name capture at the only moment that matters** — when an owner first invites a teammate (the org/workspace already exists by then; see Research Reconciliation), plus a generic non-NULL default so no org is ever displayed as the literal sentinel "Untitled"; (b) a **rename UI** in `/dashboard/settings/team` so owners can name/rename their workspace; (c) a **one-time backfill** of existing NULL-name orgs to a non-PII default so current multi-workspace users stop seeing "Untitled".

## Problem Statement / Motivation

The org switcher is the operator's primary signal of *which workspace am I acting in*. When every row reads "Untitled", a user with a personal workspace + a team workspace cannot tell them apart — they can switch into the wrong billing/data context blind. For Soleur's non-technical target user this is a trust-eroding, potentially data-exposing defect (acting in the wrong workspace), which is why the brand-survival threshold is `single-user incident`.

## Research Reconciliation — Spec vs. Codebase

The one-shot context framed three fix levers. Direct file verification (2026-06-01) confirmed the bug mechanism exactly but **corrected the framing of lever (a)**:

| Premise (from one-shot context) | Reality (verified) | Plan response |
|---|---|---|
| `organizations.name` nullable; backfill + `handle_new_user()` insert NULL | CONFIRMED — `053:49` (`name text NULL`), `053:229` (backfill `SELECT gen_random_uuid(), NULL, …`), `053:314-319` (trigger inserts NULL org + NULL workspace) | Address at all three write surfaces |
| `org-memberships-resolver.ts:146` falls back to "Untitled" | CONFIRMED — `const orgName = orgNameById.get(ws.organization_id) ?? "Untitled"` (stored value is `null` → `?? "Untitled"`) | Keep the `?? "Untitled"` as a last-resort guard; the real fix is making `name` non-NULL upstream so the guard never fires |
| `org-switcher.tsx:63` hides for `<= 1` memberships | CONFIRMED — `if (memberships.length <= 1) return null` | No change needed; explains why the bug only shows for 2+ workspaces |
| "capture a name … in the invite flow" | **CORRECTED**: the invite flow (`server/workspace-invitations.ts:153`, `app/api/workspace/invite-member/route.ts`) adds a member to the **inviter's existing** workspace via `p_workspace_id`. It does **not** create an org. The inviter's org already exists (as a backfilled NULL-name row) before they ever invite. | Name-capture for lever (a) = prompt the owner to name their workspace **at first-invite time** (the invite modal), writing to the existing org — not "create org with name". |
| "capture a name at signup/onboarding" | **MOOT for the NULL problem**: there is no onboarding flow and no `server/auth/` TS signup fallback (the "TS fallback" referenced at `053:198,277` was never built). Every signup org is NULL by the trigger. | The non-NULL default belongs in the **trigger + backfill** (a generic label), not a signup UI we'd have to build from scratch. A signup name-prompt is explicitly a Non-Goal. |
| No rename UI exists | CONFIRMED — `app/(dashboard)/dashboard/settings/team/page.tsx` lists members + pending invites only; it already resolves `data.organizationName` and passes it to `TeamMembershipList` (`page.tsx:77`), so the display surface exists but no edit control | Add rename control to the team page (owner-only) |
| No rename RPC exists | CONFIRMED — `grep` for `set_organization_name`/`update … organizations` returns nothing in `server/` or `supabase/migrations/` | Add migration `091` rename RPC (mirror `075_transfer_workspace_ownership.sql` owner-gate + SECURITY DEFINER shape) |

**Premise Validation note:** All cited artifacts exist and behave as described; the only correction is the invite-flow framing (invite != org creation). Latest migration on disk is `090` → new migration is `091`. No external premises (issue/PR references) were cited. The team page + rename route are gated behind the Flagsmith flag `isTeamWorkspaceInviteEnabled` (`lib/feature-flags/server.ts`), so the rename UI is naturally scoped to the same multi-user population that sees the switcher.

## Proposed Solution

Make `organizations.name` effectively non-NULL at every write surface, give owners a way to set/change it, and backfill the existing NULL rows:

1. **Trigger default (DB):** `handle_new_user()` inserts a generic non-PII default name (e.g. `'My Workspace'`) for the new org and workspace instead of `NULL`. Solo users still never see the switcher, but the value is meaningful the moment they go multi-workspace or open team settings.
2. **First-invite name capture (UI + route):** the invite modal (`components/settings/invite-member-action.tsx`) gains an optional "Name your workspace" field shown when the current org still carries the default/NULL name. Submitting the invite also calls the rename RPC. This is the "enforced at application layer via the invite flow" contract from `053:46`, implemented at the correct grain (rename existing org, not create).
3. **Rename UI + RPC (UI + route + DB):** owner-only rename control on `/dashboard/settings/team`, posting to `POST /api/workspace/rename` → `rename_organization` RPC (migration `091`), mirroring the `transfer-ownership` owner-gate + CSRF + flag-gate precedent.
4. **Backfill (DB):** migration `091` updates existing `organizations.name IS NULL` rows to a generic default. **Default to a generic label, NOT the owner's email/name** (privacy: the org name is visible to all workspace peers via `orgs_select_for_members`; leaking the owner's email into a peer-visible field is an avoidable disclosure — see Technical Considerations).
5. **Resolver guard retained:** keep `?? "Untitled"` in `org-memberships-resolver.ts:146` as defense-in-depth; after this change it should be unreachable, and a test asserts no production row is NULL post-backfill.

## Technical Considerations

- **Architecture impacts:** One new migration (`091`), one new RPC, one new route, one resolver/UI touch. No schema-type change to `organizations.name` (stays `text NULL` — adding `NOT NULL` would break the single-statement backfill invariant `053:47-48` and any in-flight insert ordering; we enforce non-NULL at the application + trigger + backfill layers instead, exactly as the 053 contract intended). State this explicitly so a reviewer does not push for a `NOT NULL` constraint.
- **Security / RLS:** `rename_organization` must be `SECURITY DEFINER LANGUAGE plpgsql SET search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`), with an `auth.uid()` owner-check (caller must be `role='owner'` on a workspace in the target org) — mirror `075:35-55`. `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE … TO authenticated` per the 053/075 grant convention. Do NOT add an RLS UPDATE policy to `organizations` for `authenticated` — route the write through the RPC only (same pattern as 053:154-157 "INSERT/UPDATE/DELETE routed through SECURITY DEFINER RPCs").
- **Privacy (GDPR, advisory):** the `name` column is user-supplied free-text rendered to all workspace peers (`orgs_select_for_members`, `053:159`). Backfilling NULL → owner email would surface the owner's email to every peer who can read the org. Default to a generic `'My Workspace'` (or owner-display-name only if a non-email display name is already peer-visible elsewhere). No new Article 30 Processing Activity is required: this is value-population within the already-registered `organizations` table under the existing Art. 6(1)(b) lawful basis (`053:6-11`); no new collection, disclosure, or third-party transfer. (Confirm with `/soleur:gdpr-gate` at /work.)
- **Input validation:** rename RPC + route must bound name length (e.g. 1–60 chars after trim), reject empty/whitespace-only, and trim. Mirror the `attestationText.length` validation pattern in `transfer-ownership/route.ts:54`.
- **NFR impacts:** negligible — single-row UPDATE on rename; one-time UPDATE on backfill (bounded by user count). No hot-path latency change.

### Research Insights — Precedent-Diff (Phase 4.4)

**Pattern-bound behavior:** SECURITY DEFINER plpgsql RPC + `auth.uid()` owner-gate + REVOKE/GRANT. Canonical precedent: `supabase/migrations/075_transfer_workspace_ownership.sql`. Side-by-side:

| Aspect | `transfer_workspace_ownership` (precedent, mig 075) | `rename_organization` (this plan, mig 091) |
|---|---|---|
| Language / security | `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp` (075:33-35) | **Same** (required by `cq-pg-security-definer-search-path-pin-pg-temp`) |
| Caller auth | `v_caller := auth.uid(); IF NULL RAISE 28000` (075:40-44) | **Same** |
| Owner-gate | `SELECT EXISTS(... role='owner') FOR UPDATE; IF NOT RAISE 42501` (075:50-62) | **Same shape** — resolve the org's owning workspace and require caller `role='owner'`; `FOR UPDATE` lock; `ERRCODE='42501'` |
| Attestation guard | `length(p_attestation_text) >= 16` (075:88-92) | **DROP** — a rename is not an attested act; validate name length 1–60 + non-empty instead |
| Self-transfer / target-member guards | present (075:64-86) | **DROP** — N/A to a name change |
| Audit GUC | `PERFORM set_config('workspace_audit.actor_user_id', …)` (075:94) | **DROP** — verified: `organizations` has NO audit trigger (audit triggers target `workspace_members` only; `grep "CREATE TRIGGER … ON public.organizations"` returns nothing). Setting the GUC would be dead. |
| Grant | `REVOKE ALL … FROM PUBLIC, anon, authenticated, service_role; GRANT EXECUTE … TO authenticated` (075:156-158) | **Same** |
| Transaction scope | multi-row (promote/demote/org-owner/attestation/removal) | **single-row UPDATE** on `organizations.name` |

**Net:** the rename RPC is a strict simplification of the precedent — same auth/owner/grant spine, none of the multi-row/attestation/audit machinery. No novel pattern; reviewers can apply the 075 lens directly.

**Verify-the-negative (Phase 4.45):** both negative claims hold against current code — (a) the plan adds no `NOT NULL` (mig 053:49 keeps `name text NULL`, contract-mandated at 053:47-48); (b) `grep "CREATE POLICY.*organizations"` in mig 053 returns only `orgs_select_for_members` (SELECT) — no UPDATE policy for `authenticated`, so the RPC is the sole authenticated write path as claimed.

### Attack Surface Enumeration (rename write surface)

- Ways to mutate `organizations.name`: (1) `handle_new_user()` trigger (system, signup-time, owner identity); (2) backfill DO block in `091` (one-time, migration-time); (3) new `rename_organization` RPC (the only runtime user-reachable path). No RLS UPDATE policy is granted to `authenticated`, so the RPC is the sole authenticated write path.
- Owner-gate on the RPC (`auth.uid()` must be `role='owner'` in the target org) closes member-escalation. The route additionally enforces CSRF (`validateOrigin`), auth (`getUser`), flag-gate (`isTeamWorkspaceInviteEnabled`), and `workspaceId`/`orgId` match against `resolveTeamMembershipPageData` — identical defense stack to `transfer-ownership/route.ts:14-58`.
- Gap check: the first-invite name field posts through the same authenticated owner-gated path; no new surface beyond the rename RPC.

## User-Brand Impact

- **If this lands broken, the user experiences:** the org switcher (`components/dashboard/org-switcher.tsx`) still showing "Untitled" for one or more workspaces, OR a rename that silently no-ops / writes to the wrong org, leaving the user unable to distinguish their personal vs. team workspace and at risk of acting in the wrong billing/data context.
- **If this leaks, the user's workflow/identity is exposed via:** the org `name` is rendered to all workspace peers via `orgs_select_for_members` — a backfill that defaults NULL → owner email would disclose the owner's email address to every member of every shared workspace.
- **Brand-survival threshold:** `single-user incident`

Because the threshold is `single-user incident`, **CPO sign-off is required at plan time** before `/work` begins, and `user-impact-reviewer` will be invoked at review time (handled by the review skill's conditional-agent block). Invoke CPO domain leader if not already covered by the Domain Review below.

## Observability

```yaml
liveness_signal:
  what: "Vitest assertion (post-backfill no-NULL guard) + Sentry on rename RPC failure"
  cadence: "per-CI-run (test); per-rename (runtime error path)"
  alert_target: "CI red on test failure; Sentry issue (web-platform) on rename failure"
  configured_in: "apps/web-platform/test/server/rename-organization.test.ts (new); apps/web-platform/app/api/workspace/rename/route.ts (new, reportSilentFallback)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "POST /api/workspace/rename returns non-2xx with {error:...}; rename RPC failure mirrored via reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry), matching workspace-invitations.ts:232"

failure_modes:
  - mode: "rename_organization RPC fails (caller_not_owner, rpc_failed, invalid name)"
    detection: "route returns mapped status; reportSilentFallback then Sentry on rpc_failed"
    alert_route: "Sentry issue to operator"
  - mode: "backfill leaves residual NULL org names after migration 091 applies"
    detection: "post-deploy read-only probe (see discoverability_test) returns count > 0; CI test asserts default substitution"
    alert_route: "operator runs probe post-deploy; non-zero = investigate"
  - mode: "trigger regression — new signup org still NULL"
    detection: "migration 091 trigger test (BEGIN; INSERT auth.users; assert org.name NOT NULL; ROLLBACK) red in CI"
    alert_route: "CI red"

logs:
  where: "Vercel/Docker app logs (pino childLogger 'workspace' / route); Sentry breadcrumbs"
  retention: "per existing app log retention"

discoverability_test:
  command: "doppler run -c dev -- psql \"$DATABASE_URL\" -c \"SELECT count(*) FROM public.organizations WHERE name IS NULL;\""
  expected_output: "count = 0 (no org rows carry NULL name after backfill)"
```

## Acceptance Criteria

### Functional Requirements

- [x] **AC1 (trigger default):** After migration `091`, `handle_new_user()` inserts a non-NULL default for `organizations.name` (and `workspaces.name`) on new signups. Verify: `BEGIN; INSERT INTO auth.users(...) VALUES (...); SELECT name FROM public.organizations WHERE owner_user_id = <new id>; ROLLBACK;` returns a non-NULL default. *(handle_new_user re-derived from 053:289-329; both name literals → 'My Workspace'. SQL-shape test asserts non-NULL + every 053 arm preserved.)*
- [x] **AC2 (backfill):** After migration `091` applies, `SELECT count(*) FROM public.organizations WHERE name IS NULL` returns `0`. Backfill default is a **generic non-PII label** (not owner email). *(UPDATE … WHERE name IS NULL for organizations + workspaces; idempotent.)*
- [x] **AC3 (rename RPC):** `rename_organization(p_organization_id, p_name, p_caller_user_id)` is `SECURITY DEFINER plpgsql SET search_path = public, pg_temp`, owner-gated via `COALESCE(p_caller_user_id, auth.uid())` (deviation from plan's auth.uid()-only — see note), with `REVOKE … FROM PUBLIC, anon, authenticated` + `GRANT EXECUTE … TO authenticated`. A member (non-owner) calling it gets `42501`/`caller_not_owner`. Name is trimmed; empty/whitespace-only rejected; length bounded (1–60).
- [x] **AC4 (rename route):** `POST /api/workspace/rename` enforces CSRF (`validateOrigin`), auth, flag-gate (`isTeamWorkspaceInviteEnabled`), and org match (mirror `transfer-ownership/route.ts`). Returns mapped statuses for `unauthorized`/`not_found`/`invalid_body`/`caller_not_owner`. *(15 route tests.)*
- [x] **AC5 (rename UI):** `/dashboard/settings/team` shows an owner-only rename control prefilled with the current org name; non-owners do not see it. Successful rename updates the displayed name in place (no full reload). *(new `RenameWorkspaceAction`; 5 component tests.)*
- [x] **AC6 (first-invite capture):** when the current org name is still the default, the invite modal (`invite-member-modal.tsx`) shows an optional "Name your workspace" field; submitting renames the org via the same rename path. *(path corrected from invite-member-action.tsx; the form lives in the modal.)*
- [x] **AC7 (resolver guard retained, unreachable):** `org-memberships-resolver.ts:146` keeps `?? "Untitled"` (now commented as defense-in-depth); a test asserts the switcher renders the real name (not "Untitled") for a two-org fixture with non-NULL names.

> **Deviation note (AC3):** the plan specified an `auth.uid()`-only owner-gate mirroring mig 075. Implemented as `COALESCE(p_caller_user_id, auth.uid())` mirroring `accept_workspace_invitation` (mig 076/085) because the TS wrapper invokes the RPC via the **service-role** client, under which `auth.uid()` is NULL — the 075 shape would raise `28000` on every call. The route forwards the verified `getUser()` id; when `auth.uid()` is populated COALESCE returns the same value, so the gate is correct under both invocation modes. REVOKE list follows the 075 3-role form (`PUBLIC, anon, authenticated`), which the `migration-rpc-grants` lint requires.

### Non-Functional Requirements

- [x] Rename RPC is a single-row UPDATE; backfill is a single bounded UPDATE statement (idempotent — re-running migration `091` updates 0 rows on a populated DB; use `WHERE name IS NULL` discriminator).
- [x] No `NOT NULL` constraint added to `organizations.name` (preserves `053:47-48` single-statement backfill invariant; non-NULL enforced at app+trigger+backfill layers).
- [x] `/soleur:gdpr-gate` run at /work confirms no new Processing Activity required (advisory).

### Quality Gates

- [x] RED tests written before implementation (`cq-write-failing-tests-before`): rename RPC owner-gate, route status mapping, trigger non-NULL, backfill no-NULL, resolver/switcher non-"Untitled".
- [x] Test files land where vitest collects them: `apps/web-platform/test/**/*.test.ts(x)` per `vitest.config.ts` `include:` globs (NOT co-located under `components/` or `server/` — those are silently skipped; see Sharp Edges).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **AC1:** Given a fresh signup, when `handle_new_user()` fires, then `organizations.name` and `workspaces.name` are the non-NULL default. (Test: `test/supabase-migrations/091-rename-organization.test.ts` — `BEGIN; … ROLLBACK;` against a seeded auth.users insert, mirroring `063-workspace-member-actions.test.ts` harness.)
- **AC2:** Given a pre-091 DB with NULL-name orgs, when migration `091` applies, then `count(name IS NULL) = 0` and re-applying updates 0 rows.
- **AC3:** Given a non-owner member, when they call `rename_organization`, then it raises/returns `caller_not_owner`. Given an owner with a valid trimmed name, then `organizations.name` is updated. Given empty/whitespace name, then rejected.
- **AC4:** Given a cross-origin request, when `POST /api/workspace/rename`, then CSRF reject. Given flag OFF, then 404. Given owner + valid body, then 200 + updated name. (Test: `test/server/rename-organization.test.ts` mirroring an existing route test.)
- **AC5:** Given an owner on the team page, when they rename, then the new name renders; given a member, no control is shown. (Test: extend/`test/` component test for `team-membership-list`.)
- **AC6:** Given an org with the default name, when the owner opens the invite modal, the name field appears; submitting renames. (Test: `invite-member-action` component test.)
- **AC7:** Given a two-org fixture with non-NULL names, when the switcher renders, then both real names show and neither is "Untitled". (Extend `test/org-switcher.test.tsx` / `test/org-switcher-container.test.tsx`.)

### Regression Tests

- Given the original bug (two orgs, both NULL name), when the resolver + switcher run after backfill, then no row reads "Untitled".

### Integration Verification (for /soleur:qa)

- **Browser:** Navigate to `/dashboard/settings/team` (multi-user flag ON, as owner) → rename workspace → verify org switcher shows the new name.
- **DB verify:** `doppler run -c dev -- psql "$DATABASE_URL" -c "SELECT count(*) FROM public.organizations WHERE name IS NULL;"` expects `0`.

## Files to Edit

- `apps/web-platform/supabase/migrations/091_rename_organization_and_default_names.sql` (NEW) — `rename_organization` RPC + `handle_new_user()` default-name update (`CREATE OR REPLACE`, re-derive full body from `053:289-329` to avoid dropping existing behavior — see Sharp Edges) + NULL-name backfill DO block.
- `apps/web-platform/supabase/migrations/091_rename_organization_and_default_names.down.sql` (NEW) — revert RPC + restore prior `handle_new_user()` body. (Backfill is not reverted — names are user data.)
- `apps/web-platform/server/workspace-membership.ts` (EDIT) — add `renameOrganization(...)` wrapper calling the RPC, mirroring `transferWorkspaceOwnership` shape; map `caller_not_owner`/`rpc_failed` reasons.
- `apps/web-platform/app/api/workspace/rename/route.ts` (NEW) — owner-gated POST, mirror `app/api/workspace/transfer-ownership/route.ts`.
- `apps/web-platform/components/settings/team-membership-list.tsx` (EDIT) — owner-only rename control prefilled with `organizationName`.
- `apps/web-platform/components/settings/invite-member-action.tsx` (EDIT) — optional "Name your workspace" field when org name is still default; call rename on submit.
- `apps/web-platform/server/org-memberships-resolver.ts` (EDIT — minimal) — keep `?? "Untitled"` guard; no behavioral change (add a code comment that it is now defense-in-depth, unreachable post-backfill).
- `apps/web-platform/lib/feature-flags/server.ts` — read-only (reuse `isTeamWorkspaceInviteEnabled`; confirm no new flag needed).

## Files to Create

- `apps/web-platform/test/supabase-migrations/091-rename-organization.test.ts` — RPC owner-gate, trigger non-NULL, backfill no-NULL (mirror `063-workspace-member-actions.test.ts`).
- `apps/web-platform/test/server/rename-organization.test.ts` — route status mapping + flag/CSRF gates.
- (Extend existing) `apps/web-platform/test/org-switcher.test.tsx` — AC7 non-"Untitled" assertion.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (74 open) was queried; none reference `org-memberships-resolver.ts`, `org-switcher.tsx`, `team-membership-resolver.ts`, `team-membership-list.tsx`, or `workspace-invitations.ts`.

## Dependencies & Risks

- **Migration ordering / numbering:** latest on disk is `090`; new is `091`. Note: migration `053` exists with THREE files at the same number (`053_organizations_and_workspace_members`, `053_append_kb_sync_row_rpc`, `053_template_authorizations`) — a pre-existing collision. Do NOT reuse `053`; `091` is unambiguous.
- **Trigger `CREATE OR REPLACE` risk:** `091` must re-issue the FULL `handle_new_user()` body (the version at `053:289-329`), changing only the two `NULL` name literals to the default. Dropping any of the existing 001+053 behavior (public.users insert, org/workspace/member creation, idempotency canary) would break signup. Diff against the current definition before shipping (see Sharp Edges).
- **Flag gating:** rename UI + route live behind `isTeamWorkspaceInviteEnabled`. The trigger default + backfill are unconditional (DB-level), so even flag-OFF solo users get a non-NULL name — correct, since they may go multi-workspace later.
- **GDPR (advisory):** backfill default must be non-PII (generic label), not owner email. Confirmed no new PA.

## Alternative Approaches Considered

| Approach | Rejected because |
|---|---|
| Add `NOT NULL` + default to `organizations.name` | Breaks `053:47-48` single-statement backfill invariant; the 053 contract explicitly chose app-layer enforcement. A DB default would still be a generic string (no better than the trigger default) and complicates the backfill ordering. |
| Capture name by *creating* an org in the invite flow | Misreads the architecture — invite adds a member to the existing org (`workspace-invitations.ts:153`, `p_workspace_id`); there is no org-creation-at-invite. |
| Build a signup/onboarding name prompt | No onboarding flow or TS signup fallback exists; building one is out of scope. The trigger default + rename UI cover the need. Deferred — see Non-Goals. |
| Backfill NULL → owner email/name | Privacy: org name is peer-visible (`orgs_select_for_members`); leaks owner email to all workspace members. |
| Remove the `?? "Untitled"` guard | Keep as defense-in-depth; removing a guard requires the defense-relaxation analysis and offers no user benefit. |

## Non-Goals

- A dedicated signup/onboarding workspace-naming wizard (deferred; covered by trigger default + rename UI). **Deferral tracking:** file a GitHub issue at /work — "onboarding workspace-name prompt" with re-evaluation criteria (revisit if multi-workspace adoption shows users never rename the default).
- Multi-workspace-per-org naming (`workspaces.name` UX beyond the default) — `#2778` post-MVP projects scope per `team-membership-resolver.ts:118`.
- Adding a `NOT NULL` DB constraint (intentional per 053 contract).

## Domain Review

**Domains relevant:** Product, Engineering, Legal

This plan creates a new user-facing rename control + modifies the invite modal (new interactive UI surface) → **Product/UX Gate tier: BLOCKING** (mechanical: edits create/modify `components/settings/*.tsx` interactive controls). Engineering relevant (migration + RPC + RLS-adjacent write path). Legal relevant (peer-visible user free-text + email-leak risk in backfill default).

> NOTE (pipeline/subagent context): this plan skill is running inside the one-shot pipeline as a Task subagent, so domain-leader sub-agents (CPO, CTO, CLO, spec-flow-analyzer, ux-design-lead) could not be spawned from here. The BLOCKING Product/UX gate and the `requires_cpo_signoff: true` obligation are therefore **carried forward to deepen-plan / review**, where domain agents run. The frontmatter flag `requires_cpo_signoff: true` enforces the plan-time CPO ack before `/work`.

### Engineering
**Status:** reviewed (inline)
**Assessment:** Change rides established precedents — SECURITY DEFINER plpgsql owner-gated RPC (`075`), owner-gated CSRF+flag route (`transfer-ownership`), team-page UI host. Lowest-risk shape is RPC-only write (no new RLS UPDATE policy). Primary engineering risk is the `CREATE OR REPLACE handle_new_user()` body-drop hazard (mitigated by full-body re-derivation + diff).

### Legal
**Status:** reviewed (inline, advisory)
**Assessment:** No new Article 30 Processing Activity (value-population in already-registered `organizations` table, existing Art. 6(1)(b) basis). Backfill default MUST be non-PII to avoid disclosing owner email to workspace peers. Confirm via `/soleur:gdpr-gate` at /work.

### Product/UX Gate
**Tier:** blocking
**Decision:** deferred to deepen-plan/review (pipeline subagent cannot spawn domain agents)
**Agents invoked:** none (carried forward)
**Skipped specialists:** spec-flow-analyzer, cpo, ux-design-lead (deferred to deepen-plan/review — Pencil availability unknown in this context)
**Pencil available:** N/A (not invokable here)

#### Findings
The rename control is a small, well-scoped owner-only surface on an existing settings page; the first-invite name field is an optional addition to an existing modal. spec-flow-analyzer should validate: rename error states (caller_not_owner, invalid name), the "default name still set" detection that triggers the first-invite field, and that a member (non-owner) sees no rename affordance.

## References & Research

### Internal References
- Migration contract + NULL inserts: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:44-49,229,289-329`
- Resolver "Untitled" fallback: `apps/web-platform/server/org-memberships-resolver.ts:146`
- Switcher hide-on-solo: `apps/web-platform/components/dashboard/org-switcher.tsx:63`
- Owner-gated RPC precedent: `apps/web-platform/supabase/migrations/075_transfer_workspace_ownership.sql:30-55`
- Owner-gated route precedent: `apps/web-platform/app/api/workspace/transfer-ownership/route.ts:12-58`
- Team page (UI host, resolves org name): `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx:77`
- Org-name source in resolver: `apps/web-platform/server/team-membership-resolver.ts:89-96`
- RPC wrapper pattern: `apps/web-platform/server/workspace-invitations.ts:213-264`, `apps/web-platform/server/workspace-membership.ts`
- Migration RPC test harness: `apps/web-platform/test/supabase-migrations/063-workspace-member-actions.test.ts`
- Existing switcher tests: `apps/web-platform/test/org-switcher.test.tsx`, `test/org-switcher-container.test.tsx`

### Related Work
- ADR-038 (workspaces.id = users.id solo invariant) referenced throughout migration 053.
- `#2778` — post-MVP multi-workspace-per-org projects (Non-Goal boundary).

## Sharp Edges

- **`CREATE OR REPLACE handle_new_user()` must re-derive the FULL body.** The current definition lives at `053:289-329` and does public.users insert + org/workspace/member creation + idempotency canary. Migration `091` changes only the two `NULL` name literals → default. Diff the new body against `053:289-329` before shipping; dropping any arm breaks signup (per AGENTS.md Sharp Edge on `CREATE OR REPLACE` body re-derivation, e.g. mig 085 silently dropping mig 076's identity check).
- **vitest discovery globs.** `apps/web-platform/vitest.config.ts` collects only `test/**/*.test.ts` (node) and `test/**/*.test.tsx` (jsdom). Co-located tests under `components/**` or `server/**` are silently NEVER run. Place all new tests under `apps/web-platform/test/...`.
- **A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is filled (threshold `single-user incident`).
- **Backfill default must be non-PII.** `name` is peer-visible via `orgs_select_for_members`; an email-derived default leaks the owner's email to all workspace members. Use a generic label.
- **Migration number collision precedent.** `053` is triple-numbered on disk; this is pre-existing and unrelated, but confirm `091` is unused before writing (`ls supabase/migrations/091*`).
