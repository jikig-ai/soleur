---
title: PR-G — Cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow)
date: 2026-05-18
status: brainstormed
issue: 3947
umbrella_issue: 3244
predecessor_prs: [3240, 3395, 3854, 3883, 3922, 3940]
spec: knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md
brand_survival_threshold: single-user incident
lane: cross-domain
user_brand_critical: true
---

# PR-G — Cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow)

## Scope of this brainstorm

PR-G is the seventh slice of the agent-runtime umbrella ([#3244](https://github.com/jikig-ai/soleur/issues/3244)) and the prerequisite for exposing the runtime to any founder beyond operator + 1 dogfood. PR-A→F shipped substrate (tenant isolation, BYOK lease, sibling-query migration, attachments RLS, audit_byok_use writer sweep, Inngest trigger layer + CFO autonomous-draft). PR-G ships the cohort-exposure surface: per-action-class scope grants, audit-log viewer, runtime onboarding explainer, the four legal-doc amendments that become load-bearing the moment a second founder's data is processed under automated triggers, and the `SOLEUR_FR5_ENABLED` flip-to-true.

## User-Brand Impact

**Artifacts at risk:** `audit_byok_use` rows (PR-E), Inngest function executions (PR-F, `finance.payment_failed` → CFO draft), `scope_grants` rows (introduced in this PR), founder PII embedded in `messages.draft_preview` and Stripe event payloads.

**Vectors (operator endorsed all four at Phase 0.1, CPO surfaced a fifth):**
1. **Cross-tenant read** via audit viewer (NEW — PR-F framing was write-path-only; PR-G adds a read-path tenancy boundary).
2. **Credential leak / auth bypass** if scope-grant flow stores tokens insecurely or webhook predicate honors flag without per-grant check.
3. **Unauthorized agent action** if scope-grant UX silently fails or defaults open.
4. **PII exposure** if audit viewer renders raw `authorizing_event` payloads (Stripe `customer_email`, draft text).
5. **Trust breach** if Art. 22(3) right-to-human-review is not surfaced when a tier permits auto-send.

**Threshold:** `single-user incident`. One mis-tenanted scope grant, one cross-founder audit row, one PII leak, or one unauthorized agent action ends the brand for cohort exposure.

## What We're Building

A single bundled PR (Approach A) containing:

1. **Migration 047** — `public.scope_grants` (append-only ledger), RLS self-select, SECURITY DEFINER RPCs `grant_action_class()` / `revoke_action_class()` pinning `search_path = public, pg_temp`. Revocation = column flip (`revoked_at`), not delete (WORM mirror of `audit_byok_use`).
2. **Webhook predicate change** — `apps/web-platform/app/api/webhooks/stripe/route.ts` `inngest.send` now requires BOTH `SOLEUR_FR5_ENABLED=true` AND a non-revoked `scope_grants` row for the firing tenant/action-class. Per-grant deny-by-default is the load-bearing safety primitive given the operator's "flip in PR-G" decision.
3. **Scope-grant UX** — `/dashboard/settings/scope-grants` (or sibling). Three radio states per action-class matching `messages.trust_tier` (`auto | draft_one_click | approve_every_time`), deny-by-default. First (and only) action-class in PR-G: `finance.payment_failed`. Framework extensible by row.
4. **Audit-log viewer** — `/dashboard/audit` single route, two sections: (a) BYOK invocations from `audit_byok_use` via cookie-scoped RLS client + belt-and-suspenders `.eq("founder_id", user.id)`; (b) Inngest function executions via server-only proxy route `/api/dashboard/runs` calling Inngest HTTP API with `INNGEST_SIGNING_KEY`. Redacted `authorizing_event` rendering (`"Stripe invoice.payment_failed for cus_***"` — no raw payload).
5. **Onboarding explainer** — new `users.runtime_explainer_dismissed_at timestamptz` column. Dismissable banner at top of Today section first render after PR-G ships, gated through existing `useOnboarding.updateUserField` helper. Three beats: what runs while you sleep / per-action-class explicit grant link / budget disclosure.
6. **Legal doc amendments** (4) — ToS §3a "Agent Command Authority" (new), AUP "Automated agent actions taken on your behalf" (new section), Privacy Policy Art. 22 disclosure (new), DPD §2.3(o) extension (enumerate grant ledger + audit viewer surfaces).
7. **Precondition test** — `SOLEUR_FR5_ENABLED=true && no scope_grants row → does NOT call inngest.send`. Must pass on main before the Doppler flip commit lands.
8. **Flag flip** — Doppler `prd` `SOLEUR_FR5_ENABLED=true` as part of PR-G merge. Cohort exposure goes live at merge.

## Why This Approach

**Approach A (single bundled PR) chosen** over substrate-then-surface split and five-slice carpaccio:

- The scope_grants table, webhook predicate, scope-grant UI, audit viewer, and flag flip are a single conceptual unit — the flag-flip merge IS cohort exposure. Splitting creates intermediate states on `main` that don't enforce the single-user-incident threshold until the last slice lands.
- Reuses the `feat-pr-f-inngest-iac` bundle pattern (#3940) which shipped substrate + IaC + smoke in one merge with one QA pass.
- Single legal review pass for the four doc amendments alongside the UX they enforce.
- Diff size is offset by single-review-pass economy and elimination of inter-PR coordination tax.

**Trust-tier shape: 3-tier MVP** chosen over 5-tier per FR6 and binary deny/allow:

- Matches the already-shipped `messages.trust_tier` enum (`auto | draft_one_click | approve_every_time`). No enum widening, no cross-consumer grep tax (`hr-type-widening-cross-consumer-grep`).
- Preserves the "drafts everywhere, sends nowhere" Art. 22(3) granularity that CLO needs (binary loses this).
- Future tier widening can append rows when a class genuinely needs `read_only` or `per_command_ack`.

**Onboarding: extend `useOnboarding`** chosen over new 4-state dashboard model and no-onboarding:

- Reuses existing primitives (`users.onboarding_completed_at`, `updateUserField`, `today-banner.tsx`).
- New 4-state model would block dashboard access until grant decision — worse first-run UX, blocks founders from seeing the audit viewer they need to make an informed grant decision.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| K1 | Single bundled PR-G | Approach A; tight coupling between substrate, predicate, UI, viewer, flag. |
| K2 | 3-tier MVP matching `messages.trust_tier` | No enum widening; matches shipped state; preserves Art. 22(3) granularity. |
| K3 | Deny-by-default per-action-class | Most restrictive default (`approve_every_time`); explicit grant required for any non-draft tier. |
| K4 | Webhook predicate: `flag && grant_exists` | Per-grant deny-by-default is load-bearing safety primitive; flag alone is insufficient. |
| K5 | Audit viewer reads both BYOK + Inngest | Both data sources surfaced in one `/dashboard/audit` route; redacted `authorizing_event`. |
| K6 | BYOK read via cookie-scoped RLS client | No service-role; mirrors `today/route.ts` pattern; belt-and-suspenders `.eq("founder_id", user.id)`. |
| K7 | Inngest runs via server-only proxy route | `/api/dashboard/runs` calls Inngest HTTP API server-side; `INNGEST_SIGNING_KEY` never crosses to client. |
| K8 | Append-only `scope_grants` ledger | Mirror `tc_acceptances` pattern (#3205); revocation = column flip; service-role INSERT only via SECURITY DEFINER RPC. |
| K9 | SECURITY DEFINER `search_path = public, pg_temp` | Per `cq-pg-security-definer-search-path-pin-pg-temp`. |
| K10 | Onboarding extends `useOnboarding` | New `users.runtime_explainer_dismissed_at` column; dismissable banner at top of Today section. |
| K11 | Trust-tier copy in `lib/messages/trust-tier-copy.ts` | Mirror `lib/messages/tiers.ts` single-source pattern (typo-divergence learning explicitly cited at `tiers.ts:5-8`). |
| K12 | Bundle 4 legal doc amendments in PR-G | ToS §3a + AUP + Privacy Policy Art. 22 + DPD §2.3(o); single legal review pass alongside enforcement UX. |
| K13 | Precondition test on main before flag flip | `flag=true && no scope_grants row → no inngest.send`; safety guard for the bundled flip. |
| K14 | Flip `SOLEUR_FR5_ENABLED` in PR-G merge | **Operator override** of CPO/CTO recommendation (test-now/flip-later). Risk mitigated by K4's per-grant deny-by-default; the flag becomes a global kill-switch, not the load-bearing per-tenant gate. |
| K15 | Action-class denylist as code-constant | Mirror `CC_ROUTER_TIER3_DENYLIST` pattern; hard-coded list of action-classes that can NEVER be granted (e.g., cross-tenant operations). Allowlist via Doppler-promotable rows; denylist via code. |
| K16 | No backfill of historical grants | Per #898/#927 learning ("never fabricate consent metadata"); alpha-internal pre-PR-G activity is pre-ledger. |
| K17 | T&C version bump alongside legal doc amendments | Four legal-doc changes require a tc-version bump per `feat-oauth-tc-consent-3205` bump-policy rubric; CLO sign-off required at PR-G merge. |
| K18 | `hr-autonomous-loop-skill-api-budget-disclosure` carry-forward | Onboarding explainer's third beat is the runtime cost disclosure (existing `RUNTIME_COST_DISCLOSURE` constant). |

## Open Questions (for plan-time)

1. **Action-class denylist contents.** What goes in the code-constant denylist on day one? Candidates: cross-tenant ops, mass-send actions, any action with > $X cost ceiling. Decide at plan-time; deliberately not in this brainstorm.
2. **`/dashboard/audit` filter UI scope.** v1 = simple paginated list (no filters). Open: time-range picker now or follow-up? Search-by-action-class now or follow-up? Lean toward no filters in v1; revisit after first dogfood founder feedback.
3. **Inngest run history pagination depth.** Inngest HTTP API has its own paging; how deep should `/api/dashboard/runs` proxy go? Cap at last 50 runs in v1?
4. **`users.runtime_explainer_dismissed_at` vs. `runtime_onboarded_at`.** Naming question. `dismissed_at` matches the dismissable-banner pattern; `onboarded_at` matches the existing `onboarding_completed_at`. Decide at plan-time.
5. **Grant revocation UX during in-flight `step.run`.** If founder revokes scope mid-flight while an Inngest function is executing, what happens? Options: (a) function completes (revocation effective for next trigger only), (b) function aborts at next `step.run` boundary, (c) function aborts immediately. CTO carry-forward; consult PR-F's `step.run` semantics; flag-deferred to plan.
6. **Synthetic-event smoke test on prd before merge.** PR-F's flip checklist included a synthetic Stripe event smoke. Is this a PR-G merge precondition (block merge until smoke passes) or a follow-up runbook step? Lean toward merge precondition given K14's flip-in-PR-G decision.
7. **First dogfood founder identity.** Who is it? Same as PR-F's dogfood founder? Their onboarding becomes the PR-G canary. Out of scope for this brainstorm but blocks the post-merge verify cycle.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

### Engineering (CTO)

**Summary:** No existing `scope_grants` substrate; new migration 047 with append-only WORM-style ledger + SECURITY DEFINER RPCs is the right shape. Audit viewer reads via cookie-scoped RLS client (NOT service-role); Inngest runs via server-only proxy route. Onboarding extends existing `useOnboarding` hook + new column. Precondition test (`flag && no_grant → no_send`) must pass on main before flip. Substrate delta: webhook predicate must require BOTH flag AND grant existence; flag alone is unsafe.

### Product (CPO)

**Summary:** User-Brand threshold holds; PR-G introduces a new read-path tenancy vector (audit viewer) not anticipated by PR-F's write-path framing. No drift in cohort-exposure posture since 2026-05-17 — operator + 1 dogfood remains the alpha bound. One delta: PR-F shipped trust-tier defaults as code-resident; PR-G must turn that into per-founder per-action-class grant records with explicit consent timestamp (Art. 22(3) attaches the moment a second founder's data is processed under a tier they did not personally authorize). Recommends spawning `spec-flow-analyzer` at plan-time for scope-grant flow + `ux-design-lead` for audit viewer redaction patterns.

### Legal (CLO)

**Summary:** Four legal doc amendments become load-bearing for PR-G that were dormant in PR-F: ToS §3a "Agent Command Authority" (NEW section binding grant scope, revocation effect, BYOK cost cap), AUP "Automated agent actions taken on your behalf" (founder remains responsible for sends derived from drafts), Privacy Policy Art. 22 disclosure (currently absent), DPD §2.3(o) extension. Audit viewer minimum content satisfies Art. 15 right of access; MUST NOT show other tenants' rows, BYOK key material, or raw `customer_email`. "Drafts everywhere, sends nowhere" is the binding invariant for tier defaults; any auto-send tier requires Art. 22(3) human-review affordance.

## Capability Gaps

None. `feature-dev`, `plan`, `work`, `review`, `qa`, `gdpr-gate`, `preflight`, `legal-audit` cover the slice. CTO confirms no new agents needed.

**Evidence:**
- `git grep -l "scope_grants\|scope_grant\|grant_scope" apps/web-platform/` → zero matches (verifies substrate is genuinely new, not duplicate).
- `apps/web-platform/supabase/migrations/037_audit_byok_use.sql` exists with `owner_select` RLS policy (audit viewer's load-bearing read primitive).
- `apps/web-platform/hooks/use-onboarding.ts` exists with `updateUserField()` helper (onboarding extension primitive).
- `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` is the only Inngest function registered today (PR-G surfaces its run history only).

## Deferred to follow-up issues

- **Tier expansion to 5-tier per FR6** — defer until empirical demand from cohort. Re-evaluation criterion: a founder requests `read_only` or `per_command_ack` granularity that the 3-tier MVP cannot express.
- **Additional action classes beyond `finance.payment_failed`** — defer until second domain leader (CTO, COO, CMO, etc.) is wired through Inngest. Framework is extensible by row insertion.
- **Audit viewer filters / search / digest cadence** — defer until first dogfood founder feedback. Open Question 2.
- **Multi-account E2E Playwright coverage for cohort scope-grants** — defer until cohort > 2. Reuse `2026-04-07-buttondown-onboarding-multi-account-playwright.md` pattern when needed.
- **`runtime_explainer_dismissed_at` naming consolidation with `onboarding_completed_at`** — defer to a future onboarding-naming sweep.

## Sharp edges

- **K14 "flip in PR-G" is a deliberate operator override** of CPO and CTO's recommendation to ship the flag still false and flip later. Mitigation: K4's per-grant deny-by-default webhook predicate makes the flag a global kill-switch rather than the load-bearing per-tenant gate. The plan MUST include a post-merge verify cycle (`wg-after-a-pr-merges-to-main-verify-all`) that exercises the flag-flip on a synthetic event before the first dogfood founder is invited.
- **Migration 047 deploy ordering.** Supabase migration must apply BEFORE the new webhook code runs in prd. Standard supabase deploy ordering (migration → deploy → flag) but with an extra constraint: the predicate change MUST go live with the migration (no intermediate state where flag is true and grant table doesn't exist).
- **Inngest HTTP API surface.** CTO flagged that Inngest function executions live only in Inngest's backend. The `/api/dashboard/runs` proxy depends on Inngest's HTTP API contract; if Inngest's API shape changes or rate-limits the per-founder query, the audit viewer's Inngest section breaks silently. Plan-time decision: cache strategy + Sentry alert on Inngest API errors.
- **Read-path cross-tenant leak is a NEW vector** not exercised by PR-F. The viewer MUST use `getFreshTenantClient` (tenant.ts:341), NOT service-role. Belt-and-suspenders `.eq("founder_id", user.id)` per the `today/route.ts` precedent. Add a tenant-integration test that asserts cross-tenant read returns zero rows.
- **No backfill** — per K16 and the #898/#927 fabricated-consent learning, alpha-internal pre-PR-G activity is pre-ledger. Do NOT INSERT historical grant rows for operator/dogfood founders; they grant fresh through the UX after PR-G ships.

## References

- Umbrella spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- Predecessor PR-F brainstorm (archived): `knowledge-base/project/brainstorms/archive/20260517-203729-2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
- Predecessor PR-F plan: `knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md`
- T&C consent ledger precedent: `knowledge-base/project/specs/feat-oauth-tc-consent-3205/spec.md`
- Onboarding state pattern: `apps/web-platform/supabase/migrations/012_onboarding_state.sql`
- Audit table: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- Webhook gate site: `apps/web-platform/app/api/webhooks/stripe/route.ts:428-466`
- Inngest function: `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`
- Tenant client primitive: `apps/web-platform/lib/supabase/tenant.ts:341`
- Trust-tier copy precedent: `apps/web-platform/lib/messages/tiers.ts:5-8`
- Issue: [#3947](https://github.com/jikig-ai/soleur/issues/3947)
- Draft PR: [#3984](https://github.com/jikig-ai/soleur/pull/3984)
