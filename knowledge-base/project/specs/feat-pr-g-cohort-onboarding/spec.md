---
title: PR-G — Cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow) (#3244 §G)
date: 2026-05-18
status: planned
issue: 3947
umbrella_issue: 3244
predecessor_prs: [3240, 3395, 3854, 3883, 3922, 3940]
umbrella_spec: knowledge-base/project/specs/feat-agent-runtime-platform/spec.md
umbrella_tasks: knowledge-base/project/specs/feat-agent-runtime-platform/tasks.md
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md
draft_pr: 3984
---

# PR-G — Cohort onboarding (scope-grant UX, audit-log viewer, onboarding flow)

## Problem Statement

PR-A→F shipped the agent-runtime substrate ([#3244](https://github.com/jikig-ai/soleur/issues/3244) §1–§F): tenant isolation, BYOK lease, sibling-query migration, attachments RLS, `audit_byok_use` writer sweep, Inngest trigger layer + CFO autonomous-draft. The runtime is alpha-internal-only — `SOLEUR_FR5_ENABLED=false` in Doppler `prd`, no cohort founder onboarded. Three surfaces gate cohort exposure:

1. **No per-action-class scope grants.** PR-F shipped `messages.trust_tier` defaults as code-resident constants. The moment a second founder's data is processed under a tier they did not personally authorize, GDPR Art. 22(3) "right to obtain human intervention" attaches. There is no `scope_grants` substrate; the `inngest.send` gate is a single boolean env flag (`SOLEUR_FR5_ENABLED`, consumed at `apps/web-platform/app/api/webhooks/stripe/route.ts:428,437`) — global, not per-tenant, not auditable.
2. **No founder-facing audit viewer.** `audit_byok_use` (migration 037) has an `audit_byok_use_owner_select` RLS policy but no UI consumer beyond DSAR export (`server/dsar-export.ts:448-462`). Inngest function executions live only in Inngest's backend with no Supabase mirror. A founder cannot inspect "what ran while I slept."
3. **No runtime-surface onboarding.** The Today section (`app/(dashboard)/dashboard/page.tsx:591-606`) renders cards with Send/Edit/Discard buttons disabled with title `"Wires in PR-G (#3947)"`. Existing `useOnboarding` hook + `users.onboarding_completed_at` (migration 012) covers chat/foundation, not runtime trust-tier behavior.

PR-G ships all three surfaces plus four load-bearing legal-doc amendments and the `SOLEUR_FR5_ENABLED` flip-to-true in a single bundled PR.

## Goals

- **G1**: `scope_grants` substrate live with RLS self-select + SECURITY DEFINER `grant_action_class()` / `revoke_action_class()` RPCs (`search_path = public, pg_temp`).
- **G2**: Webhook predicate requires BOTH `SOLEUR_FR5_ENABLED=true` AND non-revoked `scope_grants` row for the firing `(founder_id, action_class)` tuple. Per-grant deny-by-default is the load-bearing safety primitive.
- **G3**: Founder can view their per-action-class grant state, change tier, and revoke grant at `/dashboard/settings/scope-grants` (or sibling path; plan-time decision). All writes go through SECURITY DEFINER RPCs.
- **G4**: Founder can inspect `audit_byok_use` rows + Inngest function executions at `/dashboard/audit`. BYOK section reads via cookie-scoped RLS client + belt-and-suspenders `.eq("founder_id", user.id)`. Inngest section reads via server-only proxy `/api/dashboard/runs`. `authorizing_event` rendered as redacted summary only.
- **G5**: First-run dismissable explainer renders at top of Today section after PR-G ships, gated by new `users.runtime_explainer_dismissed_at` column. Three beats: what runs while you sleep / per-action-class grant link / budget disclosure.
- **G6**: Four legal doc amendments live: ToS §3a "Agent Command Authority" (new), AUP "Automated agent actions taken on your behalf" (new section), Privacy Policy Art. 22 disclosure (new), DPD §2.3(o) extension (enumerate grant ledger + audit viewer).
- **G7**: T&C version bumped per `feat-oauth-tc-consent-3205` bump-policy rubric; CLO sign-off captured in the PR.
- **G8**: `SOLEUR_FR5_ENABLED=true` in Doppler `prd` as part of PR-G merge. Per-grant deny-by-default (G2) prevents premature triggers.
- **G9**: Cross-tenant denial test asserts viewer query returns zero rows for foreign tenant; precondition test asserts `flag=true && no scope_grants → no inngest.send`.

## Non-Goals

- **NG1**: No 5-tier expansion per FR6 of umbrella spec. 3-tier MVP matches shipped `messages.trust_tier` enum. Defer until empirical demand.
- **NG2**: No additional action classes beyond `finance.payment_failed` in PR-G. Framework extensible by row insertion.
- **NG3**: No `/dashboard/audit` filter UI in v1 — paginated list only. Defer time-range/search to follow-up.
- **NG4**: No new Playwright E2E config for multi-account cohort coverage. Defer until cohort > 2.
- **NG5**: No backfill of historical scope grants into the new ledger (per #898/#927 fabricated-consent learning).
- **NG6**: No new Inngest functions; PR-G surfaces only the existing `cfo-on-payment-failed` function's run history.
- **NG7**: No Supabase mirror table for Inngest function executions; rely on Inngest HTTP API.
- **NG8**: No grant-revocation handling for in-flight `step.run` calls — revocation effective for next trigger. Plan-time confirms or revises (Open Q5 from brainstorm).

## Functional Requirements

- **FR1**: Migration `048_scope_grants.sql` creates `public.scope_grants (id uuid PK, founder_id uuid REFERENCES users(id) ON DELETE RESTRICT, action_class text NOT NULL, tier text NOT NULL CHECK (tier IN ('auto','draft_one_click','approve_every_time')), granted_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz NULL, revoked_reason text NULL)`. Append-only (no UPDATE trigger on `granted_at, founder_id, action_class`; revoke = column flip).
- **FR2**: RLS `ENABLE ROW LEVEL SECURITY`, policy `scope_grants_owner_select FOR SELECT USING (auth.uid() = founder_id)`. No INSERT/UPDATE/DELETE policies — writes via SECURITY DEFINER RPCs only.
- **FR3**: SECURITY DEFINER RPCs `grant_action_class(p_action_class text, p_tier text)` and `revoke_action_class(p_action_class text, p_reason text)`. `search_path = public, pg_temp`. `GRANT EXECUTE TO authenticated`. Both INSERT a new row (grant = first row for `(founder_id, action_class)`; tier change = INSERT new row, mark previous `revoked_at = now() reason='tier_change'`; revoke = INSERT new row with `revoked_at = granted_at`).
- **FR4**: Code-constant denylist `ACTION_CLASS_DENYLIST` in `apps/web-platform/server/scope-grants/denylist.ts` (action-classes that can NEVER be granted). RPCs check denylist before INSERT; webhook predicate checks denylist before `inngest.send`.
- **FR5**: Webhook predicate at `apps/web-platform/app/api/webhooks/stripe/route.ts` becomes: `SOLEUR_FR5_ENABLED === "true" && (await isGranted(founderId, 'finance.payment_failed'))` AND `!isDenied('finance.payment_failed')`. `isGranted` reads via tenant client.
- **FR6**: Scope-grant UX at `/dashboard/settings/scope-grants` (or path TBD at plan). Renders one row per known action-class (PR-G ships one: `finance.payment_failed`) with three radio states (`auto | draft_one_click | approve_every_time`), deny-by-default if no grant exists. Submit → SECURITY DEFINER RPC.
- **FR7**: Audit viewer at `/dashboard/audit` with two sections: (a) BYOK invocations from `audit_byok_use` paginated 50/page via cookie-scoped RLS Supabase client + belt-and-suspenders `.eq("founder_id", user.id)`; (b) Inngest runs from `/api/dashboard/runs` proxy. Columns: `timestamp, action_class, outcome, model, tokens_in, tokens_out, cost_cents`. `authorizing_event` rendered as `"Stripe invoice.payment_failed for cus_***"` summary; raw payload never exposed.
- **FR8**: `/api/dashboard/runs` server-only route. Calls Inngest HTTP API with `INNGEST_SIGNING_KEY` (server env only). Filters runs by founder_id from event envelope. Returns paginated JSON (cap 50 runs). 4xx on auth failure; Sentry alert on 5xx from Inngest API.
- **FR9**: Migration `049_runtime_explainer_state.sql` adds `users.runtime_explainer_dismissed_at timestamptz` (nullable).
- **FR10**: Onboarding explainer banner renders at top of Today section when `runtime_explainer_dismissed_at IS NULL`. Three beats per K10/K18 of brainstorm. Dismiss button calls `useOnboarding.updateUserField('runtime_explainer_dismissed_at', now())`.
- **FR11**: Trust-tier copy lives at `apps/web-platform/lib/messages/trust-tier-copy.ts` (mirrors `lib/messages/tiers.ts` single-source pattern).
- **FR12**: Legal doc amendments. Files to edit: `docs/legal/terms-and-conditions.md` (new §3a Command Authority + tighten §9), `docs/legal/acceptable-use-policy.md` (new "Automated agent actions" section), `docs/legal/privacy-policy.md` (Art. 22 disclosure), `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` §2.3(o) extension.
- **FR13**: T&C version bump per `knowledge-base/legal/tc-version-bump-policy.md`. Update `apps/web-platform/lib/legal/tc-version.ts` + `tc_acceptances` migration constant. CLO sign-off captured in PR body.
- **FR14**: Doppler `prd` `SOLEUR_FR5_ENABLED=true` set as final PR-G step. Documented in `knowledge-base/engineering/ops/runbooks/inngest-server.md` flip section.

## Technical Requirements

- **TR1**: Migration ordering — `048_scope_grants.sql` MUST apply before webhook code redeploy (predicate references the table). Standard supabase deploy ordering.
- **TR2**: Cross-tenant denial test — new file `test/server/scope-grants/cross-tenant-read-denied.test.ts` asserts founder A's viewer query returns zero rows from founder B's `audit_byok_use` rows, `scope_grants` rows, and Inngest runs (via `/api/dashboard/runs` with mocked Inngest API).
- **TR3**: Precondition test — new test case in `test/server/webhooks/stripe-payment-failed-inngest.test.ts`: `SOLEUR_FR5_ENABLED=true && no scope_grants row for tenant → does NOT call inngest.send`. Existing flag-off test cases remain.
- **TR4**: Grant lifecycle test — `test/server/scope-grants/lifecycle.test.ts` covers: grant fresh / tier change / revoke / re-grant after revoke. Asserts append-only invariant (no UPDATE allowed except `revoked_at` flip).
- **TR5**: Webhook predicate test — assert `flag=true && grant exists (auto tier) && action_class NOT in denylist → calls inngest.send`; `flag=true && grant exists && action_class IN denylist → does NOT call inngest.send`.
- **TR6**: Belt-and-suspenders RLS comment at every cookie-scoped query site in viewer, mirroring `today/route.ts` precedent. Comment cites the protection-against-RLS-loosening reason.
- **TR7**: Server-only enforcement — `INNGEST_SIGNING_KEY` MUST NOT appear in any client bundle. Add `apps/web-platform/test/lint/inngest-key-server-only.test.ts` grep gate on `app/(dashboard)/` and `components/`.
- **TR8**: `gdpr-gate` skill invoked at plan Phase 2.7 and work Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`.
- **TR9**: Sentry breadcrumb for every grant/revoke RPC call (`scope.grant.created` / `scope.grant.revoked` events).
- **TR10**: Post-merge verify cycle — synthetic Stripe `invoice.payment_failed` event fired against prd webhook BEFORE first dogfood founder invited. Validates flag=on + grant=on path lands in Inngest dashboard.

## Acceptance Criteria

- `git grep -l "scope_grants" apps/web-platform/` returns multiple consumer hits (migration, RPCs, predicate, viewer, tests).
- `gh pr view 3984` shows the four legal doc amendments + tc-version bump + 5 new test files + migrations 048 and 049.
- Manual QA: founder A grants `finance.payment_failed` at `auto`; synthetic Stripe event triggers CFO draft; founder A sees the row in `/dashboard/audit`; founder B sees zero rows in their viewer.
- `wg-after-a-pr-merges-to-main-verify-all` post-merge verify: synthetic event smoke on prd passes; BetterStack heartbeat green; first dogfood founder invite sent only after verify completes.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md`
- Umbrella spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
- PR-F plan: `knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md`
- T&C consent precedent: `knowledge-base/project/specs/feat-oauth-tc-consent-3205/spec.md`
- Issue: [#3947](https://github.com/jikig-ai/soleur/issues/3947)
- Draft PR: [#3984](https://github.com/jikig-ai/soleur/pull/3984)
