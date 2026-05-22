---
title: BYOK Delegations — Owner-Funded BYOK with Per-Grantee Opt-In
status: specified
issue: 4232
parent_issue: 4229
brainstorm: knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md
branch: feat-byok-delegations-4232
pr: 4290
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: true
requires_adr: true
packaging: two-pr-split
prs:
  - role: schema+resolver+enforcement+CLI
    estimate_days: "3-4"
  - role: ui+legal-docs
    estimate_days: "2-3"
---

# Spec: BYOK Delegations

## Problem Statement

PR #4225 (team-workspace) shipped multi-user organizations and split `byok-lease.ts` so it accepts `keyOwnerUserId ≠ workspaceContextUserId`. The lease's `MissingByokKeyError` ADR comment (`apps/web-platform/server/byok-lease.ts:101-112`) explicitly cites #4232 as "the future opt-in remediation. NEVER falls back to another user's key." Today (2026-05-22) Harry started as intern at jikigai and Jean wants to fund Harry's agentic runs from Jean's BYOK Anthropic key. The "never falls back" invariant must flip to "only with an active, unexpired, unrevoked, under-cap, same-workspace delegation row." Without this primitive, the only workarounds are (a) Harry brings own key + Jean reimburses out-of-band (Harry lacks upfront capital), or (b) Harry uses Jean's session (destroys audit + violates AUP §5.5).

## Goals

- **G1.** Add migration `apps/web-platform/supabase/migrations/062_byok_delegations.sql` with table `public.byok_delegations` per CTO schema sketch (key decision #9 + #11): `id, grantor_user_id, grantee_user_id, workspace_id, daily_usd_cap_cents, created_by_user_id, created_at, expires_at, revoked_at, revoked_by_user_id, revocation_reason`. FKs `ON DELETE RESTRICT`. CHECK `grantor_user_id <> grantee_user_id`. Partial unique index `WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > now())` on `(grantor_user_id, grantee_user_id, workspace_id)`.
- **G2.** Add WORM trigger on `byok_delegations` following the `scope_grants` (mig 048) **structural-diff bypass pattern**, NOT the GUC+role-gate pattern (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing`). Allowed UPDATE shapes: (a) revoke flip — `revoked_at`/`revoked_by_user_id`/`revocation_reason` set, all else unchanged; (b) Art. 17 anonymise — `grantor_user_id`/`grantee_user_id`/`created_by_user_id`/`revoked_by_user_id` nullified, all else unchanged. Every other UPDATE rejected.
- **G3.** Add DB-level CHECK constraint enforcing `same_workspace`: both `grantor_user_id` and `grantee_user_id` belong to `workspace_id` via `is_workspace_member()` (implemented as trigger or `CHECK` calling a stable function). Violation = Sentry error event with severity `error` (NOT silent rescue) — per CLO Art. 33 risk note (cross-tenant grant = 72h breach clock).
- **G4.** Ship RLS predicates per Decisions #11: INSERT `grantor_user_id = auth.uid() AND created_by_user_id = auth.uid() AND is_workspace_member(workspace_id, grantee_user_id)`; SELECT `grantor_user_id = auth.uid() OR grantee_user_id = auth.uid()`. UPDATE forbidden via tenant client; revoke routed through SECURITY DEFINER RPC `revoke_byok_delegation(p_id uuid, p_reason text)`. Pin `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- **G5.** Add SQL function `public.resolve_byok_key_owner(p_caller_user_id uuid, p_workspace_context_user_id uuid) RETURNS uuid` (plpgsql, SECURITY DEFINER, pinned search_path). Resolution order: caller's own `api_keys` row if present → grantor on first active+unexpired+unrevoked delegation row matching `(grantee_user_id = p_caller_user_id, workspace_id resolves to p_workspace_context_user_id's primary workspace)` → raise `no_active_delegation` SQLSTATE. **SQL not TS** for atomic MVCC read vs revoke write (no TOCTOU).
- **G6.** Add `audit_byok_use.delegation_id uuid NULL REFERENCES byok_delegations(id)` column. NULL = self-funded; NOT NULL = delegated. Backfilled NULL on existing rows. Indexed for the Jean's-dashboard "Funded for others" query.
- **G7.** Extend `record_byok_use_and_check_cap()` RPC (mig 061) to: (a) accept `p_delegation_id`; (b) on every call, re-resolve the delegation row by id and verify `revoked_at IS NULL OR turn_started_at <= revoked_at + interval '60 seconds'` AND `expires_at IS NULL OR expires_at > now()` AND `daily_spent_cents + p_cost_cents <= daily_usd_cap_cents`; (c) on grace-window violation OR cap-exceeded OR revoked-past-grace, write the audit row to the **grantee's** `founder_id` (not grantor) AND raise `delegation_revoked_mid_flight` / `delegation_cap_exceeded` SQLSTATE. The grantor never pays for tokens after explicit revoke + 60s grace.
- **G8.** Add wrapper module `apps/web-platform/server/byok-resolver.ts` exporting `resolveKeyOwnerThenLease(callerUserId, workspaceContextUserId, fn)`. Calls SQL `resolve_byok_key_owner` then `runWithByokLease`. Maps SQL errors → existing `ByokLeaseError` cause enum (widened with `delegation_expired`, `delegation_revoked`, `delegation_cap_exceeded`, `no_active_delegation`).
- **G9.** **Sentinel sweep — load-bearing pre-merge gate.** Update all 5 prod `runWithByokLease` call sites to call `resolveKeyOwnerThenLease` instead: `apps/web-platform/server/cc-dispatcher.ts:890`, `apps/web-platform/server/agent-runner.ts:882`, `apps/web-platform/server/agent-runner.ts:2401`, `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:199`, `apps/web-platform/server/inngest/functions/github-on-event.ts:208`. PR-A body MUST enumerate every site + explicit "still passes `userId` for both" non-conversion sites with rationale.
- **G10.** Widen `ByokLeaseArgs`, `ByokLease`, and `ByokLeaseError.cause` types in `byok-lease.ts`. Per `hr-type-widening-cross-consumer-grep` + `cq-union-widening-grep-three-patterns`: grep all consumers of `ByokLease`, `ByokLeaseArgs`, `ByokLeaseError`; update the `mapByokLeaseCauseToErrorCode` exhaustive switch at `byok-lease.ts:182-196`; sweep every catch site mapping causes to UI error codes.
- **G11.** Add CLI command `pnpm soleur:byok grant --to <user> --workspace <id> --cap-cents <n> [--expires-in <duration>]` and `pnpm soleur:byok revoke --id <delegation-id> --reason <reason>`. Calls SECURITY DEFINER RPCs `grant_byok_delegation` / `revoke_byok_delegation`. This is the v1 grant surface (UI lands in PR-B).
- **G12.** Add member-departure transactional auto-revoke (CLO requirement). Extend the `workspace_members DELETE` path (or trigger) to mark all `byok_delegations` rows where the departing user is grantor or grantee with `revoked_at = now()`, `revoked_by_user_id = NULL`, `revocation_reason = 'member_departed'` in the same statement. WORM history retained 7 years.
- **G13.** Add Art. 17 cascade RPC `anonymise_byok_delegations(p_user_id uuid)` called from existing `anonymise_user` pipeline before `auth.admin.deleteUser`. Nullifies both user_id columns + `created_by_user_id` + `revoked_by_user_id` while preserving `id, workspace_id, created_at, expires_at, revoked_at, revocation_reason` for audit chain.
- **G14.** Migration 062 carries `LAWFUL_BASIS:` header (Art. 6(1)(b) contract — the delegation is a contract between grantor and grantee) + `RETENTION:` block (7y) per `hr-gdpr-gate-on-regulated-data-surfaces` precedent (mig 058 §6-19).
- **G15.** Add `BYOK_DELEGATIONS_ENABLED` feature flag (Doppler-config keyed). OFF in prd until both PR-A + PR-B + signed Delegation Consent Side Letter land. ON for jikigai org only on day one.
- **G16.** Test plan (PR-A): (a) RLS deny-test pair distinguishing 42501 (grant) vs 42P17 (policy) per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape`; (b) `pg_default_acl` audit at migration smoke-test per learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`; (c) cross-tenant insert test (must reject + emit Sentry); (d) revoke-grace-window timing test (token at +30s debits grantor, token at +90s debits grantee); (e) cap-exceeded test; (f) duplicate-active grant rejection test; (g) member-departure auto-revoke test.

## PR-B Goals (UI + Legal)

- **G17.** Member-row grant affordance in workspace members panel: "Fund this member's runs with my key" toggle + USD/day cap input (default $20) + expiry datetime (default NULL). Edit via the same row; revoke is an inline kill switch.
- **G18.** Jean's "Funded for others" pane in his billing/usage view: per-grantee spend today + MTD + cap remaining + last invocation timestamp. Per-row revoke button.
- **G19.** Harry's persistent banner: "Running on Jean's key — $Y of $CAP today." Display the grantor's display name, never key prefix/last-4/residue. Banner shows during chat session and links to the cap details.
- **G20.** Failure-mode UX per CPO decision #6: (a) no delegation + no own key → blocking error "Request access from [owner]" + deep link; (b) delegation expired mid-conversation → current message completes, next blocks with renewal CTA; (c) revoked mid-run → same; (d) cap hit → blocking, "Ask Jean to raise cap" CTA, no soft warning, no queue.
- **G21.** Ship Delegation Consent Side Letter via legal-document-generator (parallel-tracked with G17-G20 in PR-B window). Distinct artifact from #4225's workspace-member Side Letter — different consent surface, different revocation semantics. Storage table: `byok_delegation_acceptances` mirroring `tc_acceptances_ledger` shape (open question #1 from brainstorm; plan-skill confirms).
- **G22.** DPD §2.3 addendum: "delegated-credential prompt routing — joint controllership (Art. 26) with workspace owner; Anthropic remains processor under owner's existing DPA."
- **G23.** AUP §5.6 clause: "Workspace owners granting delegations must hold a current Delegation Consent Side Letter from grantee, and may not use delegation to circumvent grantee's usage limits or surveil grantee's prompt content (cost telemetry only)."
- **G24.** DSAR runbook update (`apps/web-platform/server/dsar-reauth.ts`): include delegation history in Art. 15 extraction; respect Art. 17 cascade via G13.

## Non-Goals

- **NG1.** Per-action ACLs (e.g., "Harry can use my key for research, not deploys") — defer until second grantee with conflicting needs exists.
- **NG2.** Time-window auto-expiry (expires_at column ships but no auto-cleanup scheduler) — manual revoke + daily cap is sufficient.
- **NG3.** Multi-grantor delegations on same grantee — defer; if it happens, pick first-active by `created_at`.
- **NG4.** `prefer_delegation` boolean column — defer until a real user asks for grantor-key-wins precedence (CPO default: grantee's own key wins).
- **NG5.** Out-of-band reimbursement workflow — explicitly rejected at brainstorm; doesn't unblock Harry's first run.
- **NG6.** Mid-token stream abort via AbortController — CTO: 60s grace + reject-at-write covers the billing risk; mid-token abort breaks Harry's turn for no billing-safety gain.
- **NG7.** Per-grantee dashboard for grantee ("here's all my funders across workspaces") — defer; v1 per-workspace banner is enough.
- **NG8.** Cap aggregation across multiple delegations from the same grantor — defer; cap = per-delegation only.
- **NG9.** Materialized view for `byok_delegations_active` — defer; query-time SELECT with partial unique index is sufficient at expected scale.
- **NG10.** UI grant-from-global-settings — CPO chose per-workspace-member-row exclusively; global view defers until ≥3 grantees.

## Functional Requirements

- **FR1.** A grantor can grant a delegation to a grantee in a workspace where both are members, via CLI (G11) or UI (G17), specifying USD/day cap and optional expiry.
- **FR2.** A grantor can revoke any delegation they created, instantly. Grantee can decline an active delegation. Either action writes `revoked_at` and routes the actual API caller subsequently to their own key (or fails closed).
- **FR3.** When a grantee submits a prompt and the resolver finds an active delegation (and the grantee has no own key, per FR4 precedence), the prompt is processed on the grantor's Anthropic key; cost debits the grantor's ledger; `audit_byok_use.delegation_id` is set.
- **FR4.** Grantee's own BYOK key wins over delegation by default (no opt-out in v1).
- **FR5.** Cap exceeded = blocking error with "ask grantor to raise cap" CTA. No soft warning, no queue, no auto-fallback to grantee key.
- **FR6.** Revoked mid-run, within 60s grace: in-flight tokens debit grantor. Past 60s: in-flight tokens debit grantee.
- **FR7.** Cross-tenant grant attempt (RLS WITH CHECK rejection OR DB-level CHECK violation) emits Sentry `error` event for Art. 33 review.
- **FR8.** Member-departure (DELETE on `workspace_members`) transactionally auto-revokes all delegations involving the departing user as grantor or grantee.
- **FR9.** Jean sees per-grantee spend today/MTD + cap remaining in his billing pane; Harry sees a persistent "running on Jean's key — $Y of $CAP" banner.
- **FR10.** DSAR Art. 15 extraction includes delegation history for the requesting subject; Art. 17 anonymise nulls user_id columns while preserving audit-chain columns.

## Technical Requirements

- **TR1.** Migration 062 is the next free slot (verified by `find apps/web-platform/supabase/migrations/06[0-9]_*.sql` returning 060/061 only).
- **TR2.** `is_workspace_member(p_workspace_id, p_user_id)` exists as 2-arg signature at `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`; RLS predicates reference it directly.
- **TR3.** All new SECURITY DEFINER functions pin `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- **TR4.** `pg_default_acl` audit at migration smoke-test rejects `EXECUTE TO PUBLIC` on new functions (per learning `2026-05-06-supabase-default-privileges-defeat-revoke-from-public`).
- **TR5.** WORM trigger uses structural-diff bypass (mig 048 precedent), NOT current_user role check (per learning `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing`).
- **TR6.** RLS deny-tests distinguish 42501 (grant) vs 42P17 (policy) per learning `2026-05-16-followthrough-verification-loop-catches-grant-vs-rls-deny-shape`.
- **TR7.** All 5 `runWithByokLease` prod call sites updated (G9 enumeration); PR-A body lists each site with conversion or explicit non-conversion rationale per `hr-write-boundary-sentinel-sweep-all-write-sites`.
- **TR8.** `ByokLeaseArgs`, `ByokLease`, `ByokLeaseError.cause` widened; consumers swept per `hr-type-widening-cross-consumer-grep` + `cq-union-widening-grep-three-patterns`; exhaustive switch at `byok-lease.ts:182-196` updated.
- **TR9.** Feature flag `BYOK_DELEGATIONS_ENABLED` Doppler-keyed; OFF in prd until PR-A + PR-B + signed Side Letter land.
- **TR10.** `record_byok_use_and_check_cap` revoke-grace check re-resolves the delegation row by `delegation_id` on every call (not cached); per-write RTT cost accepted for closer grace window.
- **TR11.** ADR drafted via `/soleur:architecture create "BYOK delegations: per-workspace grantor-funded runs"` before PR-A merges, capturing (a) resolver-in-SQL-not-TS rationale, (b) 60s grace + caller-absorbs billing decision, (c) workspace-scope-not-org-scope rationale.
- **TR12.** GDPR gate runs on migration 062 review (regulated-data-surface; joint controllership).

## Acceptance Criteria

- [ ] Migration 062 applied in dev; manual smoke shows `INSERT` from grantor succeeds; from a third party fails with 42P17; cross-workspace INSERT fails with CHECK violation + Sentry event.
- [ ] All 5 `runWithByokLease` call sites updated; PR-A body enumerates sites + rationale.
- [ ] Type-widening sweep complete; exhaustive switch updated; consumer grep recorded in PR-A body.
- [ ] CLI grant/revoke works end-to-end against dev Supabase.
- [ ] Revoke-grace timing test: token at +30s debits grantor; token at +90s debits grantee.
- [ ] Cap-exceeded test: write past cap fails with `delegation_cap_exceeded`; grantor's spend unchanged.
- [ ] Member-departure test: DELETE on `workspace_members` auto-revokes delegations transactionally.
- [ ] DSAR extraction (G24) returns delegation history for the subject.
- [ ] PR-B UI: member-row toggle creates delegation; banner displays for grantee; funded pane shows per-grantee spend.
- [ ] Delegation Consent Side Letter drafted by legal-document-generator + signed by Harry before flag-flip.
- [ ] DPD §2.3 addendum + AUP §5.6 merged.
- [ ] ADR committed.
- [ ] `BYOK_DELEGATIONS_ENABLED` flipped ON for jikigai org only.

## Risks

- **R1 (High).** Cross-tenant grant via RLS predicate bug → Art. 33 72h breach clock. Mitigation: DB-level CHECK + Sentry error event + structural test.
- **R2 (High).** Revoke-grace window mis-implemented → grantor billed for hours after revoke (theatre kill-switch per learning `2026-04-18-cf-cache-purge-on-share-revoke`). Mitigation: per-write resolver re-check; integration test with timing assertion.
- **R3 (Medium).** Type-widening miss leaves a catch site silently mapping new error cause to old UI code. Mitigation: exhaustive switch + consumer grep in PR body.
- **R4 (Medium).** Default privileges audit miss leaves new RPC EXECUTE-able by `authenticated` role. Mitigation: TR4 in migration smoke-test.
- **R5 (Low).** UI banner exposes key prefix/last-4 by accident. Mitigation: UI shows grantor display name only (G19); review-time grep for `api_key`/`anthropic_key` string interpolation in JSX.
- **R6 (Low).** Cap aggregation confusion if grantor later grants multiple delegations to same grantee across workspaces. Mitigation: NG8 explicit; revisit if pattern emerges.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`
- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md`
- Parent issue: #4229 (closed via #4225)
- Lease ADR comment citing #4232: `apps/web-platform/server/byok-lease.ts:101-112`
- WORM precedent: `apps/web-platform/supabase/migrations/048_scope_grants.sql`
- RLS helper: `apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql:115-140`
- Audit table: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` + `061_byok_audit_workspace_id_rpcs.sql`
