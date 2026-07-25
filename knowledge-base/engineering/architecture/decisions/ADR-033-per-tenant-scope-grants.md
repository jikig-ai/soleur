---
title: Per-tenant scope grants as Supabase WORM ledger
status: accepted
date: 2026-05-18
related: [3244, 3947, 3984]
related_adrs: [ADR-030]
related_plans:
  - knowledge-base/project/plans/2026-05-18-feat-pr-g-cohort-onboarding-plan.md
brand_survival_threshold: single-user incident
---

# ADR-033: Per-tenant scope grants as Supabase WORM ledger

> Note on numbering: the plan provisionally named this ADR-031 to follow ADR-030. Between plan-time and /work, two unrelated PRs each landed an `ADR-031-*.md` and an `ADR-032-*.md` on `main`. This ADR adopts the next free number (033) to avoid further collision; the related-ADRs link to ADR-030 (the substrate that this gates) and not to the two unrelated ADR-031 / ADR-032 records.

## Status

**Accepted** (2026-05-18, PR #3984).

Flipped from `proposed` at Phase 1 of `2026-05-18-feat-pr-g-cohort-onboarding-plan.md` after the substrate landed: migration 048 (`public.scope_grants` table + 3 SECURITY DEFINER RPCs + RLS self-select + WORM triggers); server modules at `apps/web-platform/server/scope-grants/` (`action-class-map.ts`, `is-granted.ts`); webhook predicate at `apps/web-platform/app/api/webhooks/stripe/route.ts:437` (per-grant deny-by-default); founder-facing UI at `/dashboard/settings/scope-grants` and `/dashboard/audit`.

## Context

PR-F (#3940, ADR-030) shipped the durable trigger substrate (self-hosted Inngest on Hetzner) and the CFO autonomous-draft pipeline gated by a single global env flag, `SOLEUR_FR5_ENABLED`. As long as the runtime was alpha-internal-only, a global kill-switch was sufficient: a single tenant (the operator) was the only data subject, and the flag at `prd=false` made the runtime inert.

PR-G (#3947) opens the runtime to a cohort of founders. The moment a second founder's data flows through `inngest.send`, GDPR Article 22(3) attaches (the right to obtain human intervention against automated decisions concerning the data subject). A single global flag is no longer adequate to model "this tenant authorized this action class at this tier; that tenant did not." Three concrete failure modes the global flag cannot prevent:

1. **Premature trigger on a non-consenting tenant.** Flag flips to `true`; a Stripe `invoice.payment_failed` event arrives for a tenant who has never seen the `/dashboard/settings/scope-grants` UI. The webhook produces a draft for that tenant. The tenant's first contact with the runtime is the audit row, after the fact.
2. **No forensic record of consent at the moment of action.** Each Inngest event needs to pin "what tier was the founder authorizing at this moment" so a later audit can prove the action ran under the consent that was in force when the trigger fired. Without a per-event recorded tier, a revoke-after-the-fact reshapes the audit ledger.
3. **No Art. 22(3) handle.** When the operator (or a future support ticket) needs to halt automated processing for a single tenant, the global flag is the wrong primitive (it halts everyone) and a code-level allowlist is the wrong primitive (it requires a deploy and is invisible to the data subject).

Brand-survival threshold for PR-G: `single-user incident`. The operator (2026-05-18) confirmed the per-grant deny-by-default predicate is load-bearing — flipping `SOLEUR_FR5_ENABLED=true` is operator-routable post-merge only because the per-grant predicate is the actual tenant-level gate.

## Decision

**Adopt `public.scope_grants` (Supabase, migration 048) as the per-tenant scope grants substrate. Append-only WORM ledger; RLS self-select; 3 SECURITY DEFINER RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`) with `SET search_path = public, pg_temp` and explicit `REVOKE EXECUTE FROM PUBLIC, anon` plus `GRANT EXECUTE TO authenticated` (or `service_role` for the Art. 17 anonymise RPC). Three tiers per grant: `auto`, `draft_one_click`, `approve_every_time`. The Stripe webhook predicate (`apps/web-platform/app/api/webhooks/stripe/route.ts:437`) calls `isGranted(supabase, founderId, actionClass)` — non-null grant required for `inngest.send`. The grant tier active at the moment of the event is recorded on the Inngest envelope so the audit ledger pins consent-at-time.**

## Rejected alternatives

### Doppler config map per tenant

**Rejected.** Doppler is the operator-facing secrets substrate; routing per-tenant authorization through Doppler couples (a) "what the founder authorized" (a data-subject right and a contract artifact) to (b) "what secrets the operator manages" (an ops surface). Founder-controlled state must live in the founder-controlled substrate (their own Supabase row, RLS-bounded, Art. 17 cascade-anonymised). Doppler doesn't reach `auth.uid()`, doesn't appear in DSAR exports, and doesn't get cascade-anonymised on account deletion.

### In-process registry (e.g., `Map<founderId, Grant>` at module load)

**Rejected.** No durability across deploys. No audit trail (a tier change at 9am is invisible after the 9:30am deploy). No way for `/dashboard/audit` to render the grant-at-time-of-event because the in-process record was overwritten on the next change.

### JWT custom claim (`scope_grants: ["finance.payment_failed:draft_one_click"]`)

**Rejected.** Two-clock problem: the JWT expires (1 hour) and is reminted with current grants; the Inngest event arrives at minute 73 with a stale claim. The "consent at the moment of the trigger" semantic requires reading the grants ledger at the moment the webhook fires, not the moment the founder's last page-load minted a fresh JWT. JWT claims also pollute every authenticated request with grant payload that 99% of those requests do not consult.

### Single global flag (`SOLEUR_FR5_ENABLED=true` and nothing else)

**Rejected.** This is the pre-PR-G state; the rejection rationale is the Context section. Acceptable for alpha-internal-only; unacceptable the moment a second tenant exists. The flag survives in PR-G as a global kill-switch (it can disable the substrate entirely in an emergency) but is no longer the tenant-level gate.

## Consequences

### Positive

- **Forensic audit trail.** Every grant, tier change, and revocation is preserved in `scope_grants` as a row (WORM trigger rejects UPDATE on non-revoke columns and DELETE on any row except via `anonymise_scope_grants`). The `/dashboard/audit` viewer renders the grant active at the moment each Inngest event fired (pinned on the event envelope).
- **Revoke-via-column-flip semantics.** `revoke_action_class` sets `revoked_at = now()` on the active row; the next webhook predicate read sees no active grant and `inngest.send` is skipped. No DELETE, no UPDATE to historical state — Article 5(2) accountability preserved.
- **Cascade on account erasure.** `anonymise_scope_grants(p_user_id)` sets `founder_id = NULL` on the user's rows under a GUC bypass + role check (`current_user OR session_user = 'service_role'`). The Art. 17 cascade runs BEFORE `anonymise_tc_acceptances` in `server/account-delete.ts`; both target `public.users(id)` with `ON DELETE RESTRICT`.
- **Forward-compat: denylist via code constant.** `apps/web-platform/server/scope-grants/is-granted.ts` inlines `ACTION_CLASS_DENYLIST` as a `ReadonlySet<string>`. PR-G ships with an empty denylist; future entries land as code patches (no migration). The webhook predicate checks `isDenied(actionClass)` inside `isGranted`; both gates must hold.

### Negative / cost

- **Cascade cost on user delete.** Each user-delete now runs one more RPC (`anonymise_scope_grants`) before the existing chain. Cost: one round-trip plus a row count update. Acceptable.
- **Migration 048's WORM trigger function is `INVOKER` (not `SECURITY DEFINER`).** This is required so `current_user` correctly reflects the calling role for the anonymise-bypass gate (mirrors migration 044's reasoning at `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql:105-108`). If migration 044's role-gate semantics are broken under Supabase's actual ownership pattern, so is 048's — both rely on the same assumption. The cascade-end-to-end test (Phase 9.3) exercises the path.
- **Webhook predicate is service-role context, not RLS-bounded.** `is-granted.ts` reads via the service-role client (the webhook handler has no founder JWT). The `.eq("founder_id", founderId)` is the load-bearing tenant filter, NOT belt-and-suspenders. A founderId typo would leak across tenants — the cross-tenant denial test (Phase 9.1) includes the founderId-typo regression case (AC3 / Kieran P1-3).

### Neutral

- **No backfill.** Per brainstorm K16 (fabricated-consent learning #898/#927), alpha-internal pre-PR-G activity is pre-ledger. The operator and the first dogfood founder grant fresh through the `/dashboard/settings/scope-grants` UI after PR-G ships.
- **In-flight revocation semantics.** Per spec NG8: revocation is effective for the next trigger; runs already in flight when the revoke commits may complete under the tier that was active when they fired. The audit row pins tier-at-time-of-event, so the user can see exactly which tier was honored.

## References

- Plan: `knowledge-base/project/plans/2026-05-18-feat-pr-g-cohort-onboarding-plan.md`
- Spec: `knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md`
- Migration: `apps/web-platform/supabase/migrations/048_scope_grants.sql`
- Server module: `apps/web-platform/server/scope-grants/is-granted.ts`
- Webhook predicate: `apps/web-platform/app/api/webhooks/stripe/route.ts:437`
- Cascade wiring: `apps/web-platform/server/account-delete.ts` (3.84 anonymise-scope-grants step)
- Trust-tier copy: `apps/web-platform/lib/messages/trust-tier-copy.ts`
- Founder UI: `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx`
- Audit viewer: `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx`
- Related ADR-030: `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`
- Migration precedent (WORM + SECURITY DEFINER + anonymise): `apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql`
- Default-privileges learning: `knowledge-base/project/learnings/2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`
