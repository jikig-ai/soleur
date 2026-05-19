---
title: Tasks — PR-G cohort onboarding (#3947)
plan: knowledge-base/project/plans/2026-05-18-feat-pr-g-cohort-onboarding-plan.md
spec: knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md
branch: feat-pr-g-cohort-onboarding
issue: 3947
draft_pr: 3984
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — PR-G cohort onboarding

> Derived from `2026-05-18-feat-pr-g-cohort-onboarding-plan.md` (post-review). 12 phases; phases 0–11 pre-merge, phase 12 post-merge (operator).

## Phase 0 — Preconditions

- [ ] 0.1 Confirm `apps/web-platform/supabase/migrations/047_*.sql` does not exist (use 048 + 049).
- [ ] 0.2 `git grep -lE "scope_grants|scope_grant|grant_action_class|revoke_action_class|runtime_explainer_dismissed_at" apps/web-platform/` returns zero matches.
- [ ] 0.3 Read-only Doppler probe: `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` returns `false`.
- [ ] 0.4 Confirm `inngest@^3.54.2` in `apps/web-platform/package.json`; confirm `INNGEST_BASE_URL`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY` set in Doppler `dev` + `prd`.
- [ ] 0.5 Inngest REST API probe against `dev`: `curl -sS -H "Authorization: Bearer $INNGEST_SIGNING_KEY" "$INNGEST_BASE_URL/v1/events?name=finance.payment_failed&limit=1"` returns 200. Cite output in PR description.
- [ ] 0.6 Read `apps/web-platform/server/account-delete.ts:200-230` for cascade ordering precedent.
- [ ] 0.7 Invoke `/soleur:gdpr-gate` against plan + spec; capture findings in `knowledge-base/legal/compliance-posture.md` Active Items; fold critical findings inline.
- [ ] 0.8 `gh label list --limit 200`; verify required labels exist.
- [ ] 0.9 Code-review overlap (already verified at plan-time): zero matches.

## Phase 1 — Substrate (migrations + server module + cascade + trust-tier copy)

- [ ] 1.1 Create `apps/web-platform/supabase/migrations/048_scope_grants.sql`: table + RLS self-select + WORM triggers (`current_user OR session_user = 'service_role'` bypass + GUC) + 3 RPCs (`grant_action_class`, `revoke_action_class`, `anonymise_scope_grants`). Explicit `REVOKE EXECUTE FROM PUBLIC, anon, authenticated` then `GRANT EXECUTE TO authenticated` (for grant/revoke) or `service_role` (for anonymise).
- [ ] 1.2 Create `apps/web-platform/supabase/migrations/049_runtime_explainer_state.sql`: add nullable `timestamptz` column `users.runtime_explainer_dismissed_at`.
- [ ] 1.3 Create `apps/web-platform/server/scope-grants/action-class-map.ts` (`ACTION_CLASSES`, `ACTION_CLASS_DEFAULTS`, `isKnownActionClass`).
- [ ] 1.3.1 Create `apps/web-platform/server/scope-grants/is-granted.ts` (inlined empty denylist, `isGranted()` with Sentry on DB error vs. null on no-grant).
- [ ] 1.3.2 Edit `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:12-13`: replace inlined `ACTION_CLASS_DEFAULTS` with import from `action-class-map.ts`. Run cross-consumer grep per `hr-type-widening-cross-consumer-grep`.
- [ ] 1.4 Edit `apps/web-platform/server/account-delete.ts:200-230`: insert `anonymise_scope_grants` call BEFORE `anonymise_tc_acceptances`; match `reportSilentFallback` signature against `server/observability.ts` (verify exact form).
- [ ] 1.5 Create `apps/web-platform/lib/messages/trust-tier-copy.ts` (single-source `TRUST_TIER_COPY` const).
- [ ] 1.6 Run `supabase db reset`; verify schema applies cleanly; run `tsc --noEmit`.

## Phase 2 — Webhook predicate + tests

- [ ] 2.1 Edit `apps/web-platform/app/api/webhooks/stripe/route.ts:428-466`: rewrite predicate to `flag && customerId && founderId && isGranted(supabase, founderId, 'finance.payment_failed') && !isDenied(...)`; pass `tier: grant.tier` in `inngest.send.data`. Use `supabase` (NOT `service`) — match the existing service-role client variable name.
- [ ] 2.2 Add TR3 precondition test case to `test/server/webhooks/stripe-payment-failed-inngest.test.ts`: `flag=true && no scope_grants → no inngest.send`.
- [ ] 2.3 Add TR5 tests: denylist-gate (mocked) → no send; grant-exists + not-denied → send with tier pass-through.
- [ ] 2.4 `bun test apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts` exits 0.

## Phase 3 — Scope-grant UX

- [ ] 3.1 Create `apps/web-platform/app/(dashboard)/dashboard/settings/scope-grants/page.tsx` (server component; inline list iteration + empty state).
- [ ] 3.2 Create `apps/web-platform/components/scope-grants/scope-grant-row.tsx` (three-radio + auto-tier inline acknowledgement; pessimistic UI).
- [ ] 3.3 Create `apps/web-platform/app/api/scope-grants/grant/route.ts` (POST inlining `grant_action_class` RPC + Sentry breadcrumb).
- [ ] 3.4 Create `apps/web-platform/app/api/scope-grants/revoke/route.ts` (POST inlining `revoke_action_class` RPC + Sentry breadcrumb).
- [ ] 3.5 Edit settings nav layout to add "Scope Grants" entry (verify exact file path at /work).
- [ ] 3.6 Manual QA: grant `finance.payment_failed` at `draft_one_click`; revoke; auto-tier acknowledgement gates submit.

## Phase 4 — Audit-log viewer

- [ ] 4.1 Create `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` (server component; cookie-scoped RLS read of `audit_byok_use` with belt-and-suspenders `.eq("founder_id", user.id)`).
- [ ] 4.2 Create `apps/web-platform/lib/inngest/list-runs.ts` (server-only; env-guards; UUID shape check on founderId; returns `customerIdMasked` raw — NOT pre-composed summary).
- [ ] 4.3 Create `apps/web-platform/app/api/dashboard/runs/route.ts` (server-only proxy; auth via cookie-scoped Supabase; Sentry on 5xx).
- [ ] 4.4 Create `apps/web-platform/components/audit/audit-sections.tsx` (single component, `source` prop, partial-degradation contract).
- [ ] 4.5 Create `apps/web-platform/components/audit/redacted-event-summary.tsx` (SOLE renderer of masked summary string).
- [ ] 4.6 Create `apps/web-platform/test/lint/inngest-key-server-only.test.ts` (TR7).

## Phase 5 — Onboarding banner

- [ ] 5.1 Edit `apps/web-platform/hooks/use-onboarding.ts:48`: widen `.select(...)` to include `runtime_explainer_dismissed_at`; add state + setter; chase all `tsc --noEmit` TS2322 per `cq-union-widening-grep-three-patterns`.
- [ ] 5.2 Create `apps/web-platform/components/dashboard/runtime-explainer-banner.tsx` (three beats: what runs while you sleep / per-action-class link / `RUNTIME_COST_DISCLOSURE`).
- [ ] 5.3 Edit `apps/web-platform/app/(dashboard)/dashboard/page.tsx:591-606`: mount `<RuntimeExplainerBanner />` above Today section.

## Phase 6 — Art. 22(3) affordance (inlined)

- [ ] 6.1 In `audit-sections.tsx`, each Inngest row inlines `<a href="mailto:legal@jikigai.com?...">Request human review →</a>` with encoded subject + body.
- [ ] 6.2 Each Inngest row also inlines `<Link href="/dashboard/settings/scope-grants">Change authorization →</Link>`.

## Phase 7 — Legal doc amendments (4 × 2 = 8 file edits)

- [ ] 7.1 Edit `docs/legal/terms-and-conditions.md` + `plugins/soleur/docs/pages/legal/terms-and-conditions.md`: add §3a "Agent Command Authority"; tighten §9.
- [ ] 7.2 Edit `docs/legal/acceptable-use-policy.md` + plugin mirror: add "Automated agent actions taken on your behalf" section.
- [ ] 7.3 Edit `docs/legal/privacy-policy.md` + plugin mirror: add Art. 22 disclosure; amend "no automated decision-making" line.
- [ ] 7.4 Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` + `docs/legal/` mirror: extend §2.3(o).

## Phase 8 — T&C version bump + enforcement-surface parity

- [ ] 8.1 Bump `apps/web-platform/lib/legal/tc-version.ts`; compute new `document_sha` per amended doc.
- [ ] 8.2 Run `git grep -nE "tc_accepted_version|TC_VERSION" apps/web-platform/ | grep -v '\.test\.'`; verify every site uses `!== TC_VERSION` (not null-check). Document in PR body.

## Phase 9 — Tests

- [ ] 9.1 Create `test/server/scope-grants/cross-tenant-read-denied.test.ts` (TR2 + founderId-typo regression). Use `crypto.randomUUID()` for synthetic IDs.
- [ ] 9.2 Create `test/server/scope-grants/lifecycle.test.ts` (TR4 — grant, re-grant, revoke, re-grant; WORM invariants).
- [ ] 9.3 Create `test/server/scope-grants/account-delete-scope-grants-cascade.test.ts` (cascade ordering + abort-on-failure).
- [ ] 9.4 `bun test apps/web-platform/test/server/scope-grants/` all green.

## Phase 10 — Documentation + ADR

- [ ] 10.1 Create `knowledge-base/engineering/architecture/decisions/ADR-031-per-tenant-scope-grants.md` (sibling to ADR-030).
- [ ] 10.2 Edit `knowledge-base/engineering/ops/runbooks/inngest-server.md`: append "PR-G post-merge: Flipping SOLEUR_FR5_ENABLED" section with prerequisites, flip command, rollback command, and inline synthetic-smoke procedure (curl-based, replaces the cut Phase 11 script).
- [ ] 10.3 Edit `knowledge-base/legal/article-30-register.md`: add "Scope Grants" processing activity row.

## Phase 11 — CI green + plan-review pass + ready

- [ ] 11.1 `bun test` green.
- [ ] 11.2 `bun run typecheck` clean.
- [ ] 11.3 `bun run lint` clean.
- [ ] 11.4 `bun run docs:build` green.
- [ ] 11.5 `/soleur:preflight` green.
- [ ] 11.6 `/soleur:gdpr-gate` final pass — no new critical findings.
- [ ] 11.7 `gh pr ready 3984`.
- [ ] 11.8 `gh pr merge 3984 --squash --auto`.

## Phase 12 — Post-merge (operator)

- [ ] 12.1 Verify migrations applied on prd via `psql`.
- [ ] 12.2 Manually seed operator's `scope_grants` row + dry-run via preview env with `SOLEUR_FR5_ENABLED=true` toggled briefly.
- [ ] 12.3 Capture CPO sign-off + first dogfood founder selection in compliance-posture.md.
- [ ] 12.4 (GATE) `doppler secrets set SOLEUR_FR5_ENABLED=true -p soleur -c prd`.
- [ ] 12.5 Within 1h: synthetic Stripe smoke against prd via runbook snippet; verify Inngest dashboard + `/dashboard/audit` rendering.
- [ ] 12.6 `gh issue close 3947 --reason completed`.
- [ ] 12.7 `/soleur:postmerge` verification.
- [ ] 12.8 File deferred tracking issue: legal-doc mirror transclusion (per DHH P1.3 deferred decision).
