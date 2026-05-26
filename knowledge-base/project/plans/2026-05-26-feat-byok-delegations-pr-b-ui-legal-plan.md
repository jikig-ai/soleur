---
title: "BYOK Delegations PR-B — UI Surfaces + Legal Docs + Flag Flip"
status: planned
issue: 4232
parent_issue: 4229
branch: feat-one-shot-4232-byok-delegations-pr-b
brainstorm: knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md
spec: knowledge-base/project/specs/feat-byok-delegations-4232/spec.md
pr_a: 4290
date: 2026-05-26
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feat
classification: ui-legal-flag-flip
estimate_days: "2-3"
---

# Plan: BYOK Delegations PR-B — UI Surfaces + Legal Docs + Flag Flip (#4232)

## Overview

PR-A (#4290, merged) shipped the schema-and-enforcement layer: migration 064 (`byok_delegations` table + WORM trigger + same-workspace constraint + RLS + RPCs), the SQL resolver, TS `byok-resolver.ts` with abstract error hierarchy, 5-site sentinel sweep, cost-writer integration, account-delete cascade, CLI grant/revoke, feature flag gate, and ADR.

PR-B delivers the remaining three pillars before the flag flips ON:

1. **UI surfaces (G17-G20):** member-row "Fund this member" toggle + cap input in the team settings page; Jean's "Funded for others" pane in the billing view; Harry's persistent "Running on Jean's key" chat banner; failure-mode error cards (no delegation, expired, revoked, cap-hit).
2. **Legal docs (G21-G24):** Delegation Consent Side Letter template, DPD section 2.3 addendum for `byok_delegations` data category, AUP section 5.6 clause for delegation responsibilities, Article 30 PA-23 entry, DSAR runbook update, `byok_delegation_acceptances` consent-storage table (migration 074).
3. **Flag flip:** `BYOK_DELEGATIONS_ENABLED` to ON for jikigai org after PR-B merges and the Delegation Consent Side Letter is signed by Harry.

## User-Brand Impact

- **If this lands broken, the user experiences:** Jean sees stale or incorrect per-grantee spend in the funded pane (billing surprise); Harry sees no banner and runs silently on Jean's key without knowing (consent gap); or the fund-toggle creates a delegation with wrong cap (financial exposure).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the UI surfaces Jean's Anthropic spend telemetry to Harry's screen (or vice versa) via a miscoped RLS predicate; or the Delegation Consent Side Letter template ships with incorrect joint-controllership framing, creating a legal gap exploitable by a regulator.
- **Brand-survival threshold:** `single-user incident` — one wrong-workspace delegation row that lets Harry see another user's spend or bill another user's key IS brand-survival territory.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| G17: member-row grant affordance in workspace members panel | `apps/web-platform/components/settings/team-membership-list.tsx` renders a `MemberRow` component with a 4-column grid (Member, Role, Added, actions). No delegation UI yet. Grid is `grid-cols-[1fr_auto_auto_auto]`. | Add a 5th column for "Funded by" indicator and inline toggle. Extend `TeamMembershipRow` type with delegation fields. |
| G18: Jean's funded pane in billing/usage view | `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` renders `BillingSection` + `ApiUsageSection`. No delegation pane. | Add new `DelegationFundedPane` component between billing and usage sections. Fetch via new API route. |
| G19: Harry's persistent banner | `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` is a simple flex layout with `ConversationsRail` + children. No delegation-aware banner. Chat page renders `ChatSurface` which uses `useWebSocket`. | Add `DelegationBanner` component in the chat layout. Fetch delegation status at page level (RSC), pass to client component. |
| G20: failure-mode UX | `apps/web-platform/lib/ws-client.ts` handles `error` message type with `errorCode` field. No delegation-specific error codes yet. `ws-handler.ts` maps `KeyInvalidError` to `key_invalid`. | Extend ws-handler to map `ByokDelegationError` subtypes to new error codes. Extend ws-client to display delegation-specific error cards. |
| G21: Delegation Consent Side Letter | `knowledge-base/legal/side-letter-template.md` exists (workspace co-member Side Letter). No delegation-specific Side Letter. | Create new `knowledge-base/legal/delegation-consent-side-letter-template.md`. Distinct template (different consent surface per CLO). |
| G22: DPD section 2.3 addendum | `docs/legal/data-protection-disclosure.md` section 2.3 has bullets (a) through (v). No delegation-specific bullet. | Add section 2.3(w) for `byok_delegations` data category. |
| G23: AUP section 5.6 | `docs/legal/acceptable-use-policy.md` has section 5.5 (workspace member responsibility) ending before section 6. No section 5.6. | Add section 5.6 for delegation responsibilities after existing 5.5. |
| G24: DSAR runbook update | `apps/web-platform/server/dsar-export-allowlist.ts:128` already has `byok_delegations` entry from PR-A. `dsar-export.ts` already handles the OR-semantics query. | PR-A already covered the DSAR export pipeline for `byok_delegations`. PR-B adds the acceptance table to DSAR. |
| Spec G21 open question #1: acceptance storage | CLO leans new table (`byok_delegation_acceptances`), NOT extending `workspace_member_attestations`. | Confirm: new table in migration 074 mirroring `tc_acceptances_ledger` shape (mig 044 precedent). |
| Article 30 register | Last PA is PA-22 (Anthropic SDK runtime). PR-A compliance-posture note says "PA-21 forthcoming in PR-B follow-up". | Numbering: next free PA is PA-23 (PA-21 is taken by autonomous-acknowledgment runtime, PA-22 by Anthropic SDK runtime). |
| Migration slot | Last migration is 073 (`rls_audit_kb_files_runtime_cost_state`). | PR-B uses slot 074 for `byok_delegation_acceptances`. |
| Roadmap listing | #4232 not in `knowledge-base/product/roadmap.md`. | Add as child of MU4 or as Phase 4 item. |

## Open Code-Review Overlap

7 open scope-outs touch files in PR-B's edit surface:

- **#2193** (refactor billing banners) — touches `billing-section.tsx`. **Acknowledge:** PR-B adds a sibling component (`DelegationFundedPane`), does not refactor billing-section internals. Different concern.
- **#2194** (decompose DashboardLayout) — touches dashboard layout. **Acknowledge:** PR-B adds a banner in chat layout, not dashboard layout. Different surface.
- **#2195** (test billing mocks) — touches billing test patterns. **Acknowledge:** PR-B's billing tests are delegation-specific, not refactoring existing billing tests.
- **#2197** (SubscriptionStatus type) — touches billing types. **Acknowledge:** PR-B adds delegation types, not refactoring subscription types.
- **#2246** (KB banner components polish) — touches banner components. **Acknowledge:** PR-B creates a new `DelegationBanner`, does not modify existing banner components.
- **#3184** (OTP hook extraction) — unrelated.
- **#3280** (useWebSocket reducer refactor) — touches `ws-client.ts`. **Acknowledge:** PR-B extends the error code handling, does not refactor the WebSocket reducer. Different concern.

**Disposition:** All 7 acknowledged; none folded in. Each is a different concern from the delegation UI surfaces.

## Implementation Phases

### Phase 0 — Preconditions + Research Verification

- [ ] 0.1 Worktree clean; `git rev-parse --abbrev-ref HEAD == feat-one-shot-4232-byok-delegations-pr-b`
- [ ] 0.2 PR-A (#4290) merged to main: `gh pr view 4290 --json state | jq -r .state` returns `MERGED`
- [ ] 0.3 Migration 064 applied in dev: `mcp__plugin_supabase_supabase__list_migrations` shows 064
- [ ] 0.4 Read existing components:
  - `apps/web-platform/components/settings/team-membership-list.tsx` (MemberRow shape)
  - `apps/web-platform/components/settings/billing-section.tsx` (billing pane pattern)
  - `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` (chat banner mount point)
  - `apps/web-platform/lib/ws-client.ts` error handling (error code dispatch)
  - `apps/web-platform/server/ws-handler.ts:1782` (ByokLeaseError catch site)
- [ ] 0.5 Read legal doc insertion points:
  - `docs/legal/acceptable-use-policy.md:281-285` (section 5.5 ends, section 6 begins)
  - `docs/legal/data-protection-disclosure.md:117` (section 2.3(v) ends)
  - `knowledge-base/legal/side-letter-template.md` (template pattern for Side Letter)
  - `knowledge-base/legal/article-30-register.md` (PA-22 is last)
- [ ] 0.6 Verify `BYOK_DELEGATIONS_ENABLED` flag is OFF in prd: `doppler secrets get FLAG_BYOK_DELEGATIONS -c prd --plain` returns `0`
- [ ] 0.7 Verify migration slot 074 is free: `ls apps/web-platform/supabase/migrations/074_*.sql` returns nothing
- [ ] 0.8 `bun run typecheck` exits 0; capture baseline test pass count
- [ ] 0.9 Read `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql` for acceptance table pattern (shape to mirror)
- [ ] 0.10 Read `apps/web-platform/server/byok-resolver.ts` for `ByokDelegationError` hierarchy (PR-A shipped)
- [ ] 0.11 Verify roadmap listing: `grep '4232' knowledge-base/product/roadmap.md` — if absent, add in Phase 7

### Phase 1 — Migration 074: `byok_delegation_acceptances` Consent Table

**Rationale:** The Delegation Consent Side Letter acceptance must be stored per-grantee before the flag can flip ON. This table mirrors `tc_acceptances_ledger` (mig 044) — append-only WORM, user-scoped RLS, anonymise RPC in the Art. 17 cascade.

- [ ] 1.1 RED: create `apps/web-platform/test/supabase-migrations/074-byok-delegation-acceptances.test.ts` with table-existence + RLS assertions
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.sql`:
  - `LAWFUL_BASIS:` header (Art. 6(1)(b) contract — grantee consents to delegation)
  - `RETENTION:` 7 years (same as `tc_acceptances`)
  - Table: `id uuid PK DEFAULT gen_random_uuid()`, `user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT`, `delegation_id uuid NOT NULL REFERENCES public.byok_delegations(id) ON DELETE RESTRICT`, `accepted_at timestamptz NOT NULL DEFAULT now()`, `side_letter_version text NOT NULL`, `ip_hash text`, `user_agent text`
  - WORM trigger: no UPDATE, no DELETE (pure append-only per tc_acceptances pattern)
  - RLS: ENABLE; SELECT `user_id = auth.uid()`; INSERT `user_id = auth.uid()`
  - Index on `(user_id, delegation_id)` UNIQUE
  - `REVOKE INSERT, UPDATE, DELETE FROM PUBLIC, anon`
  - GRANT INSERT, SELECT to authenticated
- [ ] 1.3 Define `anonymise_byok_delegation_acceptances(p_user_id uuid)` SECURITY DEFINER RPC:
  - Sets `user_id = NULL`, `ip_hash = NULL`, `user_agent = NULL` for matching rows
  - WORM bypass via `SET LOCAL session_replication_role = 'replica'` (matching tc_acceptances pattern, NOT the structural-diff pattern from mig 064 — this table has no legitimate mutation shapes)
  - Pin `SET search_path = public, pg_temp`
  - `REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role`
- [ ] 1.4 Write `074_byok_delegation_acceptances.down.sql` in reverse
- [ ] 1.5 GREEN: migration test apply + down + re-apply cycle passes
- [ ] 1.6 Update `apps/web-platform/server/account-delete.ts`: add phase 5.95 (BETWEEN phase 5.9 `anonymise_byok_delegations` and phase 6 `auth.admin.deleteUser`) calling `anonymise_byok_delegation_acceptances`
- [ ] 1.7 Update `apps/web-platform/server/dsar-export-allowlist.ts`: add `byok_delegation_acceptances: { ownerField: "user_id", article: "15+20" }`
- [ ] 1.8 `bun run typecheck` exits 0

### Phase 2 — API Routes + Server Resolvers

**Rationale:** UI components need server-side data. Add API routes that query `byok_delegations` with the flag gate.

- [ ] 2.1 RED: create `apps/web-platform/test/server/byok-delegation-ui.test.ts` with resolver test cases
- [ ] 2.2 Create `apps/web-platform/server/byok-delegation-ui-resolver.ts`:
  - `resolveGrantorDelegations(userId: string, workspaceId: string)` — returns active delegations where `grantor_user_id = userId` with per-grantee daily spend (join `audit_byok_use` where `delegation_id IS NOT NULL` and `ts > now() - interval '24 hours'`), MTD spend (ts in current calendar month), cap remaining, last invocation timestamp
  - `resolveGranteeDelegation(userId: string, workspaceId: string)` — returns the active delegation (if any) where `grantee_user_id = userId`, with grantor display name (NOT key data), today's spend, cap, last invocation
  - `resolveGranteeAcceptanceStatus(userId: string, delegationId: string)` — checks `byok_delegation_acceptances` for a matching row
  - All queries via service client (need cross-user read); flag-gated via `isByokDelegationsEnabled`
- [ ] 2.3 Create `apps/web-platform/app/api/workspace/delegations/route.ts`:
  - GET: returns grantor's delegations list (for the funded-pane)
  - POST: creates delegation via `grant_byok_delegation` RPC (for the member-row toggle)
  - DELETE: revokes delegation via `revoke_byok_delegation` RPC (for the member-row kill-switch)
  - All endpoints: auth guard + flag gate + workspace membership check
- [ ] 2.4 Create `apps/web-platform/app/api/workspace/delegations/accept/route.ts`:
  - POST: grantee accepts delegation (inserts `byok_delegation_acceptances` row)
  - Auth guard + flag gate + delegation exists + grantee is the authenticated user
- [ ] 2.5 GREEN: resolver + route tests pass
- [ ] 2.6 `bun run typecheck` exits 0

### Phase 3 — UI Components: Member Row + Funded Pane + Banner + Error Cards

**Rationale:** The user-facing surfaces. Flag-gated at render time so they're invisible when `BYOK_DELEGATIONS_ENABLED=OFF`.

#### 3.A — Team Settings: Member Row Delegation Toggle

- [ ] 3.1 RED: create `apps/web-platform/test/team-membership-delegation.test.tsx` testing toggle render + cap input + revoke
- [ ] 3.2 Extend `TeamMembershipRow` type in `team-membership-resolver.ts`: add `delegationFromMe?: { id: string; dailyCapCents: number; todaySpentCents: number; active: boolean }`, `delegationToMe?: { id: string; grantorDisplayName: string; dailyCapCents: number; todaySpentCents: number }`
- [ ] 3.3 Update `resolveTeamMembershipPageData` to join `byok_delegations` when flag is ON
- [ ] 3.4 Create `apps/web-platform/components/settings/delegation-toggle.tsx`:
  - For owner viewing a member: "Fund this member's runs" toggle switch + "$XX/day cap" number input (default 2000 cents = $20) + status pill ("Active $Y/$CAP today" or "Revoked")
  - Toggle ON: POST to `/api/workspace/delegations` with grantee userId, workspaceId, capCents
  - Toggle OFF: DELETE to `/api/workspace/delegations` with delegationId + reason `grantor_revoke`
  - Cap edit: PATCH (via the grant RPC's cap-update WORM shape)
  - For member viewing themselves: "Funded by [Owner Name]" read-only indicator if delegation exists
  - Flag gate: render nothing if `isByokDelegationsEnabled` returns false
- [ ] 3.5 Update `team-membership-list.tsx`: add "Funded" column header; render `DelegationToggle` in each `MemberRow`; adjust grid to `grid-cols-[1fr_auto_auto_auto_auto]`
- [ ] 3.6 GREEN: member-row delegation tests pass

#### 3.B — Billing Settings: Grantor "Funded for Others" Pane

- [ ] 3.7 RED: create `apps/web-platform/test/billing-delegation-pane.test.tsx`
- [ ] 3.8 Create `apps/web-platform/components/settings/delegation-funded-pane.tsx`:
  - Table: grantee name, today's spend, MTD spend, cap remaining, last invocation, revoke button
  - Fetch from `/api/workspace/delegations` (grantor view)
  - Empty state: "No active delegations"
  - Flag gate: render nothing if flag OFF
- [ ] 3.9 Update `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx`: render `DelegationFundedPane` after `BillingSection`, before `ApiUsageSection`; pass userId
- [ ] 3.10 GREEN: funded-pane tests pass

#### 3.C — Chat Layout: Grantee Delegation Banner

- [ ] 3.11 RED: create `apps/web-platform/test/delegation-banner.test.tsx`
- [ ] 3.12 Create `apps/web-platform/components/chat/delegation-banner.tsx`:
  - Persistent (non-dismissible) info banner at top of chat: "Running on [Grantor Name]'s key -- $Y of $CAP today"
  - Shows grantor display name ONLY (NEVER key prefix, last-4, or residue — per G19 + R5)
  - Links to cap details in billing settings
  - Visible only when an active delegation exists for the current user in the current workspace
  - Style: `bg-soleur-accent-gold-fill/10 text-soleur-accent-gold-fg` matching brand accent
- [ ] 3.13 Update `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx`: render `DelegationBanner` above the `<main>` content. Banner fetches its data via RSC (server component wrapper) or a lightweight client-side fetch on mount.
- [ ] 3.14 GREEN: banner tests pass

#### 3.D — Error Cards: Delegation Failure Modes

- [ ] 3.15 RED: create `apps/web-platform/test/delegation-error-cards.test.tsx`
- [ ] 3.16 Extend `apps/web-platform/server/ws-handler.ts`: in the catch site at `:1782` (and equivalent paths), add `instanceof ByokDelegationError` cases mapping to new error codes:
  - `delegation_revoked` -> "Your funded access has been revoked. Ask [owner] to re-enable."
  - `delegation_expired` -> "Your funded access has expired. Ask [owner] to renew."
  - `delegation_hourly_cap_exceeded` -> "Hourly cap reached ($X/$CAP). Ask [owner] to raise the cap."
  - `delegation_daily_cap_exceeded` -> "Daily cap reached ($X/$CAP). Ask [owner] to raise the cap."
  - `no_active_delegation` -> "No API key found. Request access from [owner]." (with deep link to workspace settings)
- [ ] 3.17 Extend `apps/web-platform/lib/ws-client.ts`: add delegation error codes to the `case "error"` handler; dispatch structured error with `errorCode` prefix `delegation_*`
- [ ] 3.18 Create `apps/web-platform/components/chat/delegation-error-card.tsx`: styled error card with CTA button ("Ask [owner] to raise cap" / "Request access") that links to the workspace team settings page
- [ ] 3.19 Update `apps/web-platform/components/chat/chat-surface.tsx`: render `DelegationErrorCard` when the structured error's `errorCode` starts with `delegation_`
- [ ] 3.20 GREEN: error card tests pass
- [ ] 3.21 `bun run typecheck` exits 0

### Phase 4 — Legal Documents

**Rationale:** CLO non-negotiable requirement (brainstorm decision #13). Legal docs must land before flag flip.

#### 4.A — Delegation Consent Side Letter Template

- [ ] 4.1 Create `knowledge-base/legal/delegation-consent-side-letter-template.md`:
  - Parties: Workspace Owner ("Grantor") + Co-Member ("Grantee")
  - Recitals: references `byok_delegations` feature, AUP section 5.6, DPD section 2.3(w)
  - Core terms: (a) Grantee attests consent to grantor receiving itemized cost telemetry (token count, cost, timestamp, agent role — NO prompt content); (b) Grantee acknowledges joint controllership (Art. 26) with Grantor for grantee's prompt content routed through grantor's key; (c) Anthropic remains processor under grantor's existing DPA; (d) Either party may terminate the delegation at any time; (e) Retention: delegation history retained 7 years per audit requirements
  - French governing law, RCS Paris jurisdiction (matching workspace Side Letter)
  - Template version: 1.0.0
  - `DRAFT` banner (requires professional legal review)

#### 4.B — DPD Section 2.3(w) — Delegated-Credential Prompt Routing

- [ ] 4.2 Edit `docs/legal/data-protection-disclosure.md`: add section 2.3(w) after existing section 2.3(v):
  - Data category: `byok_delegations` — delegated-credential prompt routing
  - Data processed: delegation rows (grantor_user_id, grantee_user_id, workspace_id, daily/hourly caps, created/revoked timestamps, cap update timestamps), acceptance rows (user_id, delegation_id, accepted_at, side_letter_version, ip_hash, user_agent), cost telemetry via `audit_byok_use.delegation_id` (token count, cost, agent role)
  - Joint controllership: Art. 26 between Grantor and Grantee for grantee's prompt content via delegation; Anthropic remains processor under grantor's existing DPA (no new sub-processor)
  - Legal basis: contract performance Art. 6(1)(b) — the delegation is the bilateral contract
  - Retention: 7 years (financial audit); anonymised on account erasure via Art. 17 cascade
  - Sub-processors: none new
  - Article 30 cross-reference: PA-23
  - Consent Side Letter cross-reference

#### 4.C — AUP Section 5.6 — Delegation Responsibilities

- [ ] 4.3 Edit `docs/legal/acceptable-use-policy.md`: add section 5.6 after existing section 5.5:
  - Title: "BYOK delegation responsibilities"
  - Content: Workspace owners who grant BYOK delegations must hold a current Delegation Consent Side Letter from each grantee. Owners may not use delegation to circumvent grantee's usage limits or surveil grantee's prompt content (cost telemetry only — token count, cost, timestamp, agent role). Grantees consent to the grantor receiving itemized cost telemetry. The Delegation Consent Side Letter is distinct from the workspace co-member Side Letter (section 5.5) and covers a different consent surface.
  - Cross-reference: DPD section 2.3(w), Terms section 3b

#### 4.D — Article 30 Register: PA-23

- [ ] 4.4 Edit `knowledge-base/legal/article-30-register.md`: add PA-23 for `byok_delegations` processing activity:
  - Purpose: owner-funded BYOK delegation within shared workspace
  - Categories of data subjects: workspace co-members (grantor + grantee)
  - Categories of personal data: delegation rows, acceptance rows, cost telemetry (delegation_id on audit_byok_use)
  - Recipients: Anthropic PBC (processor under grantor's DPA)
  - Transfers: existing Anthropic transfer mechanism (DPF + SCCs)
  - Retention: 7 years; Art. 17 cascade via `anonymise_byok_delegations` + `anonymise_byok_delegation_acceptances`
  - TOMs: (1) WORM trigger; (2) same-workspace CHECK constraint; (3) RLS predicates; (4) SECURITY DEFINER RPCs; (5) daily+hourly USD cap; (6) 60s grace window
  - Feature flag: `BYOK_DELEGATIONS_ENABLED` (default OFF)

#### 4.E — Compliance Posture Update

- [ ] 4.5 Edit `knowledge-base/legal/compliance-posture.md`: add PR-B changelog entry documenting delegation legal scaffolding

#### 4.F — Side Letter Register Preparation

- [ ] 4.6 Add a note to `knowledge-base/legal/side-letter-register.md` referencing the delegation-specific Side Letter template and noting that delegation acceptances are stored separately in `byok_delegation_acceptances` (not the workspace Side Letter register)

### Phase 5 — Acceptance Flow + Grantee Consent Gate

**Rationale:** Before a delegation is active, the grantee must accept the Delegation Consent Side Letter. This is the in-app consent capture.

- [ ] 5.1 RED: create `apps/web-platform/test/delegation-acceptance-flow.test.tsx`
- [ ] 5.2 Create `apps/web-platform/components/settings/delegation-acceptance-modal.tsx`:
  - Modal shown to grantee when they have a pending (unaccepted) delegation
  - Displays: Delegation Consent Side Letter summary, grantor name, cap details
  - "I accept" button: POST to `/api/workspace/delegations/accept` with delegationId
  - "Decline" button: DELETE to `/api/workspace/delegations` with reason `grantee_decline`
  - After accept: banner becomes active; delegation resolver starts resolving for this grantee
- [ ] 5.3 Update `DelegationBanner` to show "Pending acceptance" state when delegation exists but no acceptance row
- [ ] 5.4 GREEN: acceptance flow tests pass
- [ ] 5.5 `bun run typecheck` exits 0

### Phase 6 — Roadmap + Feature Flag Documentation

- [ ] 6.1 Edit `knowledge-base/product/roadmap.md`: add #4232 as a child of MU4 or as a new row in the relevant phase table
- [ ] 6.2 Verify feature flag documentation is accurate in `apps/web-platform/lib/feature-flags/server.ts`
- [ ] 6.3 Update `.env.example` if `FLAG_BYOK_DELEGATIONS` not already listed

### Phase 7 — Tests + Typecheck + Final Verification

- [ ] 7.1 Run full test suite: `bun run typecheck` + `bun test` — all pass
- [ ] 7.2 Verify all new components are flag-gated: `grep -rn "isByokDelegationsEnabled" apps/web-platform/components/settings/delegation-*.tsx apps/web-platform/components/chat/delegation-*.tsx` returns matches for every new component
- [ ] 7.3 Verify no key residue in UI: `grep -rn "api_key\|anthropic_key\|key_prefix\|last_four" apps/web-platform/components/settings/delegation-*.tsx apps/web-platform/components/chat/delegation-*.tsx` returns 0 matches
- [ ] 7.4 Verify grantor display name only: `grep -rn "grantorDisplayName\|grantor_display_name\|grantorName" apps/web-platform/components/` — every delegation UI reference uses display name, never key data
- [ ] 7.5 Verify DSAR coverage: `byok_delegation_acceptances` in `dsar-export-allowlist.ts`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. Migration 074 applied in dev; `byok_delegation_acceptances` table exists with WORM trigger
- [ ] AC2. Team settings: member row shows "Fund this member" toggle when flag ON; toggle creates delegation via RPC
- [ ] AC3. Team settings: member row shows cap input (default $20/day); cap editable in-place
- [ ] AC4. Team settings: revoke kill-switch sets `revoked_at` immediately
- [ ] AC5. Billing settings: "Funded for others" pane shows per-grantee today/MTD/cap-remaining/last-invocation
- [ ] AC6. Chat layout: persistent banner "Running on [Name]'s key -- $Y of $CAP today" when active delegation
- [ ] AC7. Chat banner never displays key prefix, last-4, or any key residue
- [ ] AC8. Error cards: all 5 failure modes (no delegation, expired, revoked, hourly cap, daily cap) display correct CTA
- [ ] AC9. Delegation Consent Side Letter template created at `knowledge-base/legal/delegation-consent-side-letter-template.md`
- [ ] AC10. DPD section 2.3(w) added: `grep -c '2\.3(w)' docs/legal/data-protection-disclosure.md` returns >= 1
- [ ] AC11. AUP section 5.6 added: `grep -c '5\.6' docs/legal/acceptable-use-policy.md` returns >= 1
- [ ] AC12. Article 30 PA-23 added: `grep -c 'Processing Activity 23' knowledge-base/legal/article-30-register.md` returns >= 1
- [ ] AC13. Account-delete cascade: phase 5.95 calls `anonymise_byok_delegation_acceptances`
- [ ] AC14. DSAR allowlist: `byok_delegation_acceptances` entry present
- [ ] AC15. All new UI components render nothing when `BYOK_DELEGATIONS_ENABLED=OFF`
- [ ] AC16. `bun run typecheck` exits 0; `bun test` exits 0
- [ ] AC17. Grantee acceptance modal shows before delegation becomes active; decline revokes
- [ ] AC18. PR body uses `Ref #4232` (NOT `Closes`) — issue stays open until flag flip confirmed
- [ ] AC19. Compliance-posture changelog entry added
- [ ] AC20. Roadmap listing for #4232 present

### Post-merge (operator)

- [ ] PM1. Migration 074 applied to prd via `web-platform-release.yml#migrate` (auto-triggered; verify `gh run watch`). Automation: `gh workflow view web-platform-release.yml --ref main`
- [ ] PM2. Harry signs Delegation Consent Side Letter (genuinely manual — legal consent act). Automation: not feasible because this is a human legal consent act requiring Harry's informed judgment.
- [ ] PM3. Operator grants delegation via CLI: `pnpm byok-grant --actor jean.deruelle@jikigai.com --to harry@jikigai.com --workspace <id> --cap-cents 2000 --hourly-cap-cents 500 --yes`. Automation: CLI script already exists from PR-A.
- [ ] PM4. Flip `BYOK_DELEGATIONS_ENABLED` to ON for jikigai org via Flagsmith segment rule. Automation: `mcp__plugin_soleur_cloudflare__authenticate` not applicable; Flagsmith dashboard is the standard path per `/soleur:flag-set-role`.
- [ ] PM5. Verify banner appears for Harry in chat. Automation: Playwright MCP (`mcp__playwright__browser_navigate` + `mcp__playwright__browser_snapshot`).
- [ ] PM6. Verify funded-pane appears for Jean in billing settings. Automation: Playwright MCP.
- [ ] PM7. Update side-letter-register.md: add Harry's acceptance row after Side Letter is signed. Automation: not feasible because it depends on the physical signature timestamp.
- [ ] PM8. Close #4232 after PM1-PM7 confirmed: `gh issue close 4232 --comment "PR-A + PR-B merged; flag ON for jikigai; Side Letter signed"`. Automation: `gh` CLI via Bash.

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.sql` | **Create** — acceptance consent table |
| `apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.down.sql` | **Create** — down migration |
| `apps/web-platform/server/account-delete.ts` | **Edit** — add phase 5.95 anonymise |
| `apps/web-platform/server/dsar-export-allowlist.ts` | **Edit** — add acceptance table entry |
| `apps/web-platform/server/byok-delegation-ui-resolver.ts` | **Create** — server resolver for UI data |
| `apps/web-platform/server/team-membership-resolver.ts` | **Edit** — extend TeamMembershipRow type + delegation join |
| `apps/web-platform/server/ws-handler.ts` | **Edit** — add ByokDelegationError mapping |
| `apps/web-platform/lib/ws-client.ts` | **Edit** — add delegation error code handling |
| `apps/web-platform/app/api/workspace/delegations/route.ts` | **Create** — delegations API route |
| `apps/web-platform/app/api/workspace/delegations/accept/route.ts` | **Create** — acceptance API route |
| `apps/web-platform/components/settings/delegation-toggle.tsx` | **Create** — member row toggle |
| `apps/web-platform/components/settings/delegation-funded-pane.tsx` | **Create** — grantor billing pane |
| `apps/web-platform/components/settings/delegation-acceptance-modal.tsx` | **Create** — grantee acceptance modal |
| `apps/web-platform/components/settings/team-membership-list.tsx` | **Edit** — add Funded column + DelegationToggle |
| `apps/web-platform/components/chat/delegation-banner.tsx` | **Create** — grantee persistent banner |
| `apps/web-platform/components/chat/delegation-error-card.tsx` | **Create** — delegation error UI |
| `apps/web-platform/components/chat/chat-surface.tsx` | **Edit** — render DelegationErrorCard on delegation errors |
| `apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx` | **Edit** — mount DelegationBanner |
| `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` | **Edit** — mount DelegationFundedPane |
| `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` | **Edit** — pass delegation data |
| `docs/legal/acceptable-use-policy.md` | **Edit** — add section 5.6 |
| `docs/legal/data-protection-disclosure.md` | **Edit** — add section 2.3(w) |
| `knowledge-base/legal/delegation-consent-side-letter-template.md` | **Create** — Side Letter template |
| `knowledge-base/legal/article-30-register.md` | **Edit** — add PA-23 |
| `knowledge-base/legal/compliance-posture.md` | **Edit** — add changelog entry |
| `knowledge-base/legal/side-letter-register.md` | **Edit** — add delegation reference note |
| `knowledge-base/product/roadmap.md` | **Edit** — add #4232 listing |
| `apps/web-platform/lib/feature-flags/server.ts` | **Edit** (if needed) — verify flag gate |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.sql` | Acceptance consent WORM table |
| `apps/web-platform/supabase/migrations/074_byok_delegation_acceptances.down.sql` | Down migration |
| `apps/web-platform/server/byok-delegation-ui-resolver.ts` | Server resolver for delegation UI data |
| `apps/web-platform/app/api/workspace/delegations/route.ts` | Delegations CRUD API |
| `apps/web-platform/app/api/workspace/delegations/accept/route.ts` | Acceptance API |
| `apps/web-platform/components/settings/delegation-toggle.tsx` | Member row fund toggle |
| `apps/web-platform/components/settings/delegation-funded-pane.tsx` | Grantor billing pane |
| `apps/web-platform/components/settings/delegation-acceptance-modal.tsx` | Grantee acceptance modal |
| `apps/web-platform/components/chat/delegation-banner.tsx` | Grantee persistent banner |
| `apps/web-platform/components/chat/delegation-error-card.tsx` | Delegation error cards |
| `knowledge-base/legal/delegation-consent-side-letter-template.md` | Side Letter template |
| `apps/web-platform/test/supabase-migrations/074-byok-delegation-acceptances.test.ts` | Migration tests |
| `apps/web-platform/test/server/byok-delegation-ui.test.ts` | Resolver tests |
| `apps/web-platform/test/team-membership-delegation.test.tsx` | Toggle tests |
| `apps/web-platform/test/billing-delegation-pane.test.tsx` | Funded pane tests |
| `apps/web-platform/test/delegation-banner.test.tsx` | Banner tests |
| `apps/web-platform/test/delegation-error-cards.test.tsx` | Error card tests |
| `apps/web-platform/test/delegation-acceptance-flow.test.tsx` | Acceptance flow tests |

## Observability

```yaml
liveness_signal:
  what: "Feature flag gate — all delegation UI invisible when FLAG_BYOK_DELEGATIONS=0. Active when flag ON for jikigai org."
  cadence: "Per-request (flag evaluated on every page load / API call)"
  alert_target: "Sentry web-platform via SENTRY_DSN — any ByokDelegationError that reaches UI without proper error card = unhandled"
  configured_in: "apps/web-platform/lib/feature-flags/server.ts:38,151"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "HTTP 500 on /api/workspace/delegations/* + Sentry capture; ws-handler delegation error codes visible in chat"

failure_modes:
  - mode: "Delegation created but acceptance table INSERT fails (mig 074 not applied)"
    detection: "Sentry error event with SQLSTATE 42P01 (relation does not exist)"
    alert_route: "Sentry → operator email"
  - mode: "Banner shows wrong grantor name (cross-workspace data leak)"
    detection: "Sentry breadcrumb on DelegationBanner mount + workspace-id mismatch check in resolver"
    alert_route: "Sentry → operator email (Art. 33 severity if confirmed cross-tenant)"
  - mode: "Flag flipped ON before Side Letter signed"
    detection: "Operator checklist PM2 → PM4 ordering; no automated detection (human consent act)"
    alert_route: "Operator self-check; CLO review at next quarterly audit"

logs:
  where: "Pino stdout → journalctl (Hetzner) + Better Stack eu-fsn-3 (via Vector VRL scrub)"
  retention: "Rolling Docker json-file buffer (Hetzner) + Better Stack paid-tier default"

discoverability_test:
  command: "doppler secrets get FLAG_BYOK_DELEGATIONS -c prd --plain && gh api repos/jikig-ai/soleur/pulls/4290 --jq '.state'"
  expected_output: "0 (flag OFF pre-flip) + MERGED (PR-A landed)"
```

## Domain Review

**Domains relevant:** Product (CPO), Engineering (CTO), Legal (CLO)

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** PR-B is pure UI + legal. No new SQL resolver logic (PR-A shipped that). Migration 074 is a simple consent table following the tc_acceptances pattern. Risk is in the UI wiring: wrong-workspace data in the banner or funded pane is cross-tenant. Mitigations: flag gate + workspace-scoped queries + RLS on the acceptance table.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm)
**Assessment:** Three legal deliverables (Side Letter, DPD, AUP) are CLO non-negotiable prerequisites for flag flip. PA-23 in Article 30 register completes the ROPA coverage. Acceptance table provides Art. 7 consent evidence. Flag flip requires signed Side Letter — operator action, not automated.

### Product/UX Gate

**Tier:** blocking (new user-facing pages: delegation toggle, funded pane, grantee banner, acceptance modal, error cards)
**Decision:** reviewed (carry-forward from brainstorm CPO assessment)
**Agents invoked:** spec-flow-analyzer (brainstorm phase), cpo (brainstorm phase), ux-design-lead (deferred to deepen-plan)
**Skipped specialists:** ux-design-lead (Pencil MCP availability unknown — deferred to deepen-plan)
**Pencil available:** N/A (deferred)

#### Findings

CPO brainstorm assessment: bidirectional cost visibility is mandatory v1. USD/day cap is load-bearing. Member-row toggle structurally prevents cross-tenant grant. Banner must show grantor display name only. Acceptance modal is the consent capture gate. All findings carried forward from brainstorm.

## Risks

- **R1 (High).** Banner shows wrong grantor name or spend for a different workspace's delegation → cross-tenant data leak. Mitigation: workspace-scoped queries; resolver takes explicit workspaceId param; RLS on acceptance table.
- **R2 (Medium).** Legal doc wording insufficient for Art. 26 joint controllership → regulator challenge. Mitigation: `DRAFT` banner on Side Letter template; professional legal review required before execution; DPD section explicitly declares Art. 26.
- **R3 (Medium).** Flag flipped ON before Side Letter signed → delegation active without consent. Mitigation: operator checklist ordering PM2 before PM4; acceptance modal gates delegation activation in-app.
- **R4 (Low).** Cap edit race: Jean edits cap while Harry is mid-conversation → momentary inconsistency. Mitigation: WORM Shape 3 cap-update in PR-A; UI refresh on cap change.
- **R5 (Low).** Acceptance table migration 074 fails to apply in prd. Mitigation: standard migration pipeline via `web-platform-release.yml#migrate`; down migration provided.

## Alternative Approaches Considered

| Approach | Disposition |
|---|---|
| Single PR (schema + UI + legal together) | Rejected — review surface too large; schema needs dogfood-testing before UI polish. |
| Legal docs in a separate PR-C | Rejected — CLO non-negotiable that legal scaffolding lands WITH the UI (brainstorm decision #13). |
| Modal-based delegation management (full settings page) | Deferred — per-workspace-member-row toggle is simpler for v1 (decision #6). Full delegation management page when >=3 grantees. |
| Global "Funded for others" settings tab | Rejected — CPO chose per-workspace member-row exclusively (NG10). |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The chat `DelegationBanner` is deliberately non-dismissible — Harry must always know he's using Jean's key. This is a consent requirement, not a UX oversight.
- Migration 074 uses `session_replication_role = 'replica'` for the anonymise RPC bypass (matching tc_acceptances 044 pattern), NOT the structural-diff pattern from mig 064. This is intentional — the acceptance table has no legitimate mutation shapes (pure append-only).
- The funded-pane spend query joins `audit_byok_use` filtered on `delegation_id IS NOT NULL` with a rolling 24h window — this matches the daily cap accounting (rolling 24h, not UTC midnight) per PR-A deepen-plan decision.
- When wiring the acceptance POST route, the endpoint must verify both: (a) the authenticated user IS the grantee_user_id on the delegation, and (b) the delegation is active (not revoked/expired). Missing either check is a security regression.
- Legal doc edits to `docs/legal/acceptable-use-policy.md` and `docs/legal/data-protection-disclosure.md` must update the "Last Updated" date in the frontmatter/header.

## Test Strategy

All tests use the project's existing test runner (`bun test` via vitest configuration). No new test framework introduced.

- **Migration tests:** apply + down + re-apply cycle against dev Supabase (pattern from `064-byok-delegations.test.ts`)
- **Resolver tests:** mock Supabase client; test flag-off bypass, grantor view, grantee view, empty states
- **Component tests:** React Testing Library; test render with/without flag, toggle interactions, banner content, error card CTA links
- **Integration tests:** acceptance flow end-to-end (create delegation -> accept -> banner active -> revoke -> banner gone)

All fixtures synthesized per `cq-test-fixtures-synthesized-only`. No production data in tests.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-byok-delegations-4232/spec.md`
- PR-A plan: `knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md`
- PR-A tasks: `knowledge-base/project/specs/feat-byok-delegations-4232/tasks.md`
- PR-A PR: #4290
- Issue: #4232
- Workspace Side Letter template: `knowledge-base/legal/side-letter-template.md`
- tc_acceptances precedent: `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql`
- WORM trigger learning: `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
