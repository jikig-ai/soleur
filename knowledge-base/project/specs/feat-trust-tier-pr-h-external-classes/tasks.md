---
title: PR-H — Trust-tier external classes wiring — Tasks
date: 2026-05-19
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tracking_issue: 4077
draft_pr: 4065
plan: knowledge-base/project/plans/2026-05-19-feat-trust-tier-pr-h-external-classes-plan.md
spec: knowledge-base/project/specs/feat-trust-tier-pr-h-external-classes/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-19-pr-h-trust-tier-external-classes-brainstorm.md
---

# Tasks — PR-H Trust-tier external classes

Derived from the plan. Each leaf task is intended to be executable by `/soleur:work`. TDD discipline (`cq-write-failing-tests-before`) is encoded in numbering: `.1` always = failing test (RED); `.2+` = implementation (GREEN); `.x` = verify.

## Phase 0 — Preconditions

- [ ] **0.1** Confirm mig 051 is next free: `ls apps/web-platform/supabase/migrations/ | grep -E '^0[5-9][0-9]_' | head -5`.
- [ ] **0.2** Re-read `apps/web-platform/supabase/migrations/046_*.sql` L266-285 to confirm compound CHECK shape on `messages.tier`.
- [ ] **0.3** Re-verify Doppler hot-reload learning land status; if on `main`, cite file; else cite PR-G body.
- [ ] **0.4** Confirm ADR-034 number free: `ls knowledge-base/engineering/architecture/decisions/ | grep -E '^ADR-034'` returns empty.
- [ ] **0.5** Type-widening cross-consumer grep enumerates ALL 6 sites:
  - `apps/web-platform/server/scope-grants/is-granted.ts:15, 17, 25-29, 30`
  - `apps/web-platform/app/api/webhooks/stripe/route.ts:456`
  - `apps/web-platform/test/server/scope-grants/cross-tenant-read-denied.test.ts:225, 230`
  - `apps/web-platform/test/server/webhooks/stripe-payment-failed-inngest.test.ts:92`
- [ ] **0.6** Verify every rule ID cited in plan against `AGENTS.{md,core.md,docs.md,rest.md}` + `scripts/retired-rule-ids.txt`.

## Phase 1 — Registry + types

- [ ] **1.1 RED** Create `apps/web-platform/test/server/scope-grants/action-class-exhaustive.test.ts` — combined parity + exhaustiveness + enum-absence regex.
- [ ] **1.2 RED** Create `apps/web-platform/test/lint/action-class-typed-literals.test.ts` — rg-based; accepts narrowed-union expressions, rejects raw `string`/`any`; fixture pass/fail cases.
- [ ] **1.3 GREEN** Edit `apps/web-platform/server/scope-grants/action-class-map.ts`:
  - Widen `ACTION_CLASSES` to 11 entries (per plan FR1 final list).
  - Widen `ActionClassTier` to 4 values including `auto_with_digest`.
  - Extend `ACTION_CLASS_DEFAULTS` per category.
  - Add `ACTION_CLASS_CATEGORY: Record<ActionClass, "finance" | "external_low_stakes" | "external_brand_critical" | "infra">`.
- [ ] **1.4 GREEN** Sweep type-widening across 6 sites enumerated at 0.5: tighten `isGranted`, `isDenied`, `ACTION_CLASS_DENYLIST`; update both test files.
- [ ] **1.5 GREEN** `bun run tsc --noEmit` clean — close every `TS2322 ... not assignable to never` rail.
- [ ] **1.6 VERIFY** `bun test apps/web-platform/test/server/scope-grants/` + `bun test apps/web-platform/test/lint/` pass.

## Phase 2 — Migration 051

- [ ] **2.1 RED** Create `apps/web-platform/test/server/action-sends-worm.test.ts` (gated `TENANT_INTEGRATION_TEST=1`) covering 9 cases: INSERT happy, UPDATE/DELETE rejection, NULL shape rejection, tier widening accept/reject, enum-absence DB CHECK rejection (`payment.refund`), Art-17 anonymise round-trip, cross-tenant denial.
- [ ] **2.2 GREEN** Create `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` — NO outer `BEGIN/COMMIT`; includes scope_grants.tier widening, scope_grants.action_class DB CHECK regex, `messages.action_class` add + bounded backfill, `action_sends` table with pure-reject trigger + RLS + index + `anonymise_action_sends(uuid)` SECURITY DEFINER RPC.
- [ ] **2.3 GREEN** Create `apps/web-platform/supabase/verify/051_action_sends_worm.sql` — sentinel for `verify-migrations` CI.
- [ ] **2.4 GREEN** Create `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.down.sql` — reverse.
- [ ] **2.5 VERIFY** Apply locally to dev Supabase per `hr-dev-prd-distinct-supabase-projects`; run `TENANT_INTEGRATION_TEST=1 bun test` against integration suite.

## Phase 3 — Producer extension

- [ ] **3.1 GREEN** Edit `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts` — extend `PaymentFailedPayload` to require `action_class`; add to L214-227 INSERT.
- [ ] **3.2 GREEN** Edit `apps/web-platform/app/api/webhooks/stripe/route.ts:491` — `inngest.send` data carries `action_class: "finance.payment_failed"`.
- [ ] **3.3 VERIFY** Existing CFO tests pass; Phase 1 lint test passes.

## Phase 4 — Routes + write-action-send helper + Art-17 cascade

- [ ] **4.1 GREEN** Create `apps/web-platform/server/action-sends/write-action-send.ts` — single write boundary; canonical JSON serialization for `approval_signature_sha256`.
- [ ] **4.2 RED** Create `apps/web-platform/test/api/dashboard/today/send-route.test.ts` — 8 cases per plan.
- [ ] **4.3 GREEN** Create `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts`. **Cookie-scoped `supabase` client passed to `isGranted` (not service-role).** Branches on tier; calls `writeActionSend`. Returns 409 / 400 / 403 / 422 per plan.
- [ ] **4.4 GREEN** Create `apps/web-platform/app/api/dashboard/today/[id]/edit/route.ts` and `discard/route.ts`.
- [ ] **4.5 GREEN** Edit `apps/web-platform/server/account-delete.ts` — extend Art-17 cascade to call `supabase.rpc("anonymise_action_sends", { p_user_id })` BEFORE `auth.admin.deleteUser`. Sibling pattern from `anonymise_scope_grants` + `anonymise_tc_acceptances`.
- [ ] **4.6 VERIFY** `bun test apps/web-platform/test/api/dashboard/`.

## Phase 5 — today-card.tsx wiring + typed-confirm-modal (under components/ui/)

- [ ] **5.1 RED** Create `apps/web-platform/test/components/ui/typed-confirm-modal.test.tsx` — RTL + Playwright a11y (keyboard, ARIA, tap-target, ZWS rejection, no `.trim()`/`.normalize()`).
- [ ] **5.2 GREEN** Create `apps/web-platform/components/ui/typed-confirm-modal.tsx` — operation-bounded primitive; reusable by future PR-I template-authorization.
- [ ] **5.3 GREEN** Edit `apps/web-platform/components/dashboard/today-card.tsx`:
  - Remove `disabled` + `aria-disabled` + `title="Wires in PR-G (#3947)"` from 3 buttons.
  - Wire `onClick` handlers calling `/api/dashboard/today/[id]/send|edit|discard`.
  - On Send 409 response: open `<TypedConfirmModal>` with payload from 409 body.
  - On modal submit: second POST with `confirmed_typed=true` + `typed_value`.
  - Optimistic UI for discard.
- [ ] **5.4 VERIFY** Component tests pass; manual smoke in `bun run dev`.

## Phase 6 — DEFERRED to PR-I

- [ ] **6.1 BOOKKEEPING** No PR-H code change. File PR-I tracking issue (child of #4078) at Phase 10 POST-6 carrying: `digests` table schema, `digest-infra-actions.ts` Inngest function, `anonymise_digests` RPC, `users.next_digest_at` column (per Arch F9 cheap alternative), Today-section digest card variant, `SOLEUR_FR5_ENABLED` short-circuit on digest emitter.

## Phase 7 — Legal artifacts

- [ ] **7.1 GREEN** Invoke `legal-document-generator` agent with 9-limb CLO framing → append PA-15 to `knowledge-base/legal/article-30-register.md`.
- [ ] **7.2 GREEN** Edit `docs/legal/data-protection-disclosure.md` — add §2.3(p) + §2.3(q); `**Last Updated:** May 19, 2026`; no PR/issue numbers in body.
- [ ] **7.3 GREEN** Edit `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` — mirror.
- [ ] **7.4 GREEN** Edit `docs/legal/privacy-policy.md` §8.3 — extend 3→4 tier enumeration + Art. 22(3) one-liner; Last Updated bump.
- [ ] **7.5 GREEN** Edit `plugins/soleur/docs/pages/legal/privacy-policy.md` — mirror §8.3.
- [ ] **7.6 GREEN** Edit `docs/legal/terms-and-conditions.md` §3a.2 L57 — surgical edit "(b) Auto tier" → "(b) `Auto` or `Auto with daily digest` tier"; Last Updated bump.
- [ ] **7.7 GREEN** Edit `plugins/soleur/docs/pages/legal/terms-and-conditions.md` — mirror §3a.2.
- [ ] **7.8 VERIFY** Greps from AC8 pass against both canonical + mirror; canonical + mirror agree on §2.3 letter ordering, §8.3 tier count, §3a.2 phrasing.

## Phase 8 — ADR (single merged)

- [ ] **8.1 GREEN** Create `knowledge-base/engineering/architecture/decisions/ADR-034-action-class-registry-static-literals-and-enum-absence.md`. Status: `accepted`. Three sections per plan Phase 8.1.
- [ ] **8.2 VERIFY** `find knowledge-base/engineering/architecture/decisions/ -name 'ADR-034*'` returns 1; YAML frontmatter `status: accepted`.

## Phase 9 — Verification + multi-agent review

- [ ] **9.1** `bun run tsc --noEmit` clean.
- [ ] **9.2** `bun test apps/web-platform` clean.
- [ ] **9.3** `TENANT_INTEGRATION_TEST=1 bun test apps/web-platform/test/server/action-sends-worm.test.ts` against DEV Supabase.
- [ ] **9.4** `semgrep-sast` returns 0 findings.
- [ ] **9.5** Push branch (`rf-before-spawning-review-agents-push-the`); spawn brand-survival-extended review ≥9 agents: `user-impact-reviewer`, `data-integrity-guardian`, `security-sentinel`, `semgrep-sast`, `agent-native-reviewer`, `code-quality-analyst`, `architecture-strategist`, `pattern-recognition-specialist`, `spec-flow-analyzer`.
- [ ] **9.6** Fix all P1 findings inline; ≤2 P2 acceptable.

## Phase 10 — Ship

- [ ] **10.1** `/soleur:ship` — preflight Check 6 passes (User-Brand Impact section present + threshold set).
- [ ] **10.2** Mark PR #4065 ready; auto-merge enabled.
- [ ] **10.3 POST-1** Verify `web-platform-release.yml` migrate + verify-migrations green on dev + prd.
- [ ] **10.4 POST-2** `doppler secrets get SOLEUR_FR5_ENABLED -p soleur -c prd --plain` returns `true`.
- [ ] **10.5 POST-3** Synthetic Stripe TEST `invoice.payment_failed` smoke against prd; CFO Today card → Send → modal → second click → `action_sends` row.
- [ ] **10.6 POST-4** `mcp__plugin_supabase_supabase__execute_sql` confirms `action_sends` row written.
- [ ] **10.7 POST-5** Art-17 round-trip on synthetic founder; `action_sends.user_id IS NULL` post-call.
- [ ] **10.8 POST-6** File PR-I tracking issue (digest emitter scope) as child of #4078; file mig-number-conflict hygiene issue.
- [ ] **10.9 POST-7** `gh issue close 4077`; `gh issue edit 3244` updating §3.4 partial-AC checkbox with PR-I deferral note.

## Acceptance Criteria Summary

AC1-AC14 per plan. AC10 grep tightened to `grep -cE '<button[^>]*disabled' …` per DHH P3. AC12 verifies cookie-scoped client at Phase 4.2. AC13 + AC14 verify Art-17 cascade + DB CHECK enum-absence (the two new Kieran/Arch P1 catches).
