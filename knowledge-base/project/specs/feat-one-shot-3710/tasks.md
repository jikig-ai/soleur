---
issue: 3710
parent_pr: 3701
plan: knowledge-base/project/plans/2026-05-13-feat-sentry-symmetric-userid-pseudonymisation-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-05-13
---

# Tasks — Sentry symmetric userId pseudonymisation (#3710)

Derived from `knowledge-base/project/plans/2026-05-13-feat-sentry-symmetric-userid-pseudonymisation-plan.md`.

## Phase 0 — Setup

- [ ] 0.1 Run `/soleur:gdpr-gate` plan-time (already captured in plan §"GDPR / Compliance Gate")
- [ ] 0.2 Verify CPO sign-off carry-forward from `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md`
- [ ] 0.3 Path-existence sweep: confirm every file path cited in the plan returns `test -f` green
- [ ] 0.4 Worktree confirmed: `.worktrees/feat-one-shot-3710` (current)

## Phase 1 — F3 scope-isolation integration test (load-bearing gate)

- [ ] 1.1 Create `apps/web-platform/test/sentry-scope-isolation.test.ts`
- [ ] 1.2 Add `vi.mock("@sentry/nextjs")` capturing `captureException`, `captureMessage`, `withIsolationScope`, `getCurrentScope().setUser`
- [ ] 1.3 Stub a `withUserRateLimit`-wrapped handler exercising the candidate placement form (`Sentry.withIsolationScope` wrap)
- [ ] 1.4 Implement assertion 1: sequential request A (auth=userA) → captured event carries `user.id = hashUserIdValue(userA.id)`
- [ ] 1.5 Implement assertion 2: sequential request B (unauth, post-A) → captured event carries `user.id === undefined`
- [ ] 1.6 Implement assertion 3: concurrent A+B via `Promise.all` → each event matches its own request
- [ ] 1.7 Run test suite — all 3 assertions GREEN before Phase 2

## Phase 2 — Sentry.setUser HOC binding

- [ ] 2.1 Edit `apps/web-platform/server/with-user-rate-limit.ts`: import `Sentry`, `hashUserIdValue`
- [ ] 2.2 Wrap post-`getUser` body in `Sentry.withIsolationScope(async () => { Sentry.getCurrentScope().setUser({id: hashUserIdValue(user.id)}); ... })`
- [ ] 2.3 Add inline comment block citing ADR-029, F3 gate rationale, pointer to `sentry-scope-isolation.test.ts`
- [ ] 2.4 Update `apps/web-platform/test/with-user-rate-limit.test.ts` to preserve isolation semantics under the new wrap shape
- [ ] 2.5 Re-run Phase 1 tests — remain GREEN

## Phase 3 — 10-site helper migration + inline setUser

- [ ] 3.1 `apps/web-platform/app/(auth)/callback/route.ts:310` → `reportSilentFallback` + inline setUser, feature `"auth-callback"`, op `"user-upsert-fallback"`
- [ ] 3.2 `apps/web-platform/app/(auth)/callback/route.ts:323` → `reportSilentFallback`, feature `"auth-callback"`, op `"workspace-provisioning"`
- [ ] 3.3 `apps/web-platform/app/api/services/route.ts:103` → `reportSilentFallback`, feature `"services"`, op `"token-store"`
- [ ] 3.4 `apps/web-platform/app/api/services/route.ts:133` → `reportSilentFallback`, feature `"services"`, op `"list"`
- [ ] 3.5 `apps/web-platform/app/api/services/route.ts:198` → `reportSilentFallback`, feature `"services"`, op `"token-delete"`
- [ ] 3.6 `apps/web-platform/app/api/workspace/route.ts:68` → `reportSilentFallback`, feature `"workspace"`, op `"provisioning"`
- [ ] 3.7 `apps/web-platform/app/api/webhooks/stripe/route.ts:180` → `reportSilentFallback`, feature `"stripe-webhook"`, op `"checkout.session.completed"` (verify Stripe metadata.userId source)
- [ ] 3.8 `apps/web-platform/app/api/repo/setup/route.ts:196` → `reportSilentFallback`, feature `"repo-setup"`, op `"clone"`
- [ ] 3.9 `apps/web-platform/app/api/auth/github-resolve/callback/route.ts:153` → `reportSilentFallback`, feature `"github-resolve"`, op `"callback"`
- [ ] 3.10 `apps/web-platform/app/api/accept-terms/route.ts:73` → `reportSilentFallback`, feature `"accept-terms"`, op `"user-row-missing"`
- [ ] 3.11 Wrap each migration's setUser in `Sentry.withIsolationScope(...)` (since these routes do NOT use the HOC)
- [ ] 3.12 Sweep verification: `grep -nE 'logger\.(error|warn)\(.*userId' apps/web-platform/app/` returns zero matches (except the explicit `logger.info` success-path scope-out)

## Phase 4 — sentry-scrub rename special-case + tests (RED→GREEN)

- [ ] 4.1 Create `apps/web-platform/test/sentry-scrub.test.ts` with 8 scenarios (RED)
- [ ] 4.2 Test: `scrubSentryEvent({extra: {userId: "abc"}})` → `{extra: {userIdHash: "<hex>"}}`
- [ ] 4.3 Test: `scrubSentryEvent({tags: {user_id: "abc"}})` → `{tags: {userIdHash: "<hex>"}}`
- [ ] 4.4 Test: mixed rename + redact in same `extra` object
- [ ] 4.5 Test: case-insensitive (`UserId`, `USER_ID`, `User_Id`)
- [ ] 4.6 Test: nested `contexts.request.extra.userId` renamed
- [ ] 4.7 Test: cycle / shared-DAG rename consistency via memo
- [ ] 4.8 Test: `{userId, userIdHash}` both present → preserve preset `userIdHash`, drop raw
- [ ] 4.9 Test: `{userId: null}` → `{userIdHash: "pepper_unset_null"}`
- [ ] 4.10 Edit `apps/web-platform/server/sentry-scrub.ts:43-49` to add rename special-case BEFORE `SENSITIVE_LOWER.has()` (GREEN)
- [ ] 4.11 Add inline comment block citing ADR-029 I8 + rename-wins-over-redact precedence
- [ ] 4.12 All 8 scenarios GREEN

## Phase 5 — PA8 §(c) Article 30 register update

- [ ] 5.1 Edit `knowledge-base/legal/article-30-register.md:157` — drop §(c)(i) "migration to the helpers is tracked under the follow-up issue" forward-reference; replace per plan AC wording
- [ ] 5.2 Edit §(c)(ii) — drop "symmetric direct-capture coverage … tracked under follow-up #3710" forward-reference; replace per plan AC wording
- [ ] 5.3 `grep -n "#3710\|tracked under follow-up\|symmetric coverage tracked" knowledge-base/legal/article-30-register.md` → expect zero matches
- [ ] 5.4 `grep -n "ADR-029" knowledge-base/legal/article-30-register.md` → expect ≥1 match
- [ ] 5.5 Run `/soleur:gdpr-gate` work-phase exit per `hr-gdpr-gate-on-regulated-data-surfaces`

## Phase 6 — Full verification

- [ ] 6.1 `bash scripts/test-all.sh` → all suites GREEN
- [ ] 6.2 `tsc --noEmit` in `apps/web-platform/` → CLEAN
- [ ] 6.3 `apps/web-platform/test/observability.test.ts` GREEN
- [ ] 6.4 `apps/web-platform/test/observability-pepper-unset.test.ts` GREEN
- [ ] 6.5 `apps/web-platform/test/observability-mirror-debounce.test.ts` GREEN
- [ ] 6.6 `apps/web-platform/test/userid-pseudonymize.test.ts` GREEN
- [ ] 6.7 `apps/web-platform/test/logger-formatters.test.ts` GREEN
- [ ] 6.8 `apps/web-platform/test/with-user-rate-limit.test.ts` GREEN
- [ ] 6.9 CI gate `userid-bypass-lint` continues to pass

## Phase 7 — Multi-agent review

- [ ] 7.1 `/soleur:review` spawning: security-sentinel, architecture-strategist, user-impact-reviewer (mandatory at single-user-incident threshold), data-integrity-guardian, code-simplicity-reviewer
- [ ] 7.2 Address P1 findings inline
- [ ] 7.3 Push for human PR review

## Phase 8 — Ship

- [ ] 8.1 `/soleur:ship` Phase 5.5 conditional gates fire (regulated data + brand threshold)
- [ ] 8.2 CPO sign-off carry-forward verified
- [ ] 8.3 `user-impact-reviewer` re-fires per single-user-incident threshold
- [ ] 8.4 `gh pr merge <N> --squash --auto` after CI green
- [ ] 8.5 Post-merge: `gh workflow run sentry-post-merge-smoke.yml` (assert prod boot Sentry event carries `user.id = hashUserIdValue(<known-test-uuid>)`)
- [ ] 8.6 `gh issue close 3710 --comment "closed by PR #<N>"` after Sentry smoke green

## Done-when

- [ ] Phase 1 F3 gate test PASSES with the production placement form (`withIsolationScope` wrap)
- [ ] All 10 helper-migration sites verified at deployment via Sentry dashboard (each emits `user.id = userIdHash` on event capture)
- [ ] `sentry-scrub.ts` rename special-case GREEN against 8 unit-test scenarios
- [ ] PA8 §(c)(i) and §(c)(ii) carry no `#3710` forward-reference
- [ ] PR body uses `Closes #3710`
- [ ] No regression on the 5 existing test files cited in plan AC
