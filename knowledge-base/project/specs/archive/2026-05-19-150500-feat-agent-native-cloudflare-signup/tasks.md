# Tasks: feat-agent-native-cloudflare-signup

Derived from `knowledge-base/project/plans/2026-05-03-feat-agent-native-cloudflare-signup-plan.md` (post-deepen-plan revision).

> **Sprint Re-Evaluation OPEN.** Day numbers below assume outcome (a) (3w → 4-5w bundle-all-at-once with timeline slip). Renumber for (b) phased / (c) hold-launch-post when operator confirms.

## Phase 0: Spike + 7 ADRs (Days 1-3)

- [ ] 0.1 Install `stripe` ≥ 1.40.0 + `stripe plugin install projects` in sandbox container; capture pinned versions
- [ ] 0.2 Run `stripe projects init`, `catalog --json`, `add cloudflare/...` against Stripe sandbox; capture exit codes, stdout shapes, side-effect files
- [ ] 0.3 Test `Idempotency-Key` HTTP header behavior on retry
- [ ] 0.4 Test `--json` output stability across `stripe projects --version` bumps
- [ ] 0.5 Test cold-signup email override mechanisms — confirm Stripe-email = CF-email is hard constraint
- [ ] 0.6 Test revoke cascade for auto-provisioned CF account (full delete vs unlink)
- [ ] 0.7 Test webhook surface — register wildcard, capture event types
- [ ] 0.8 Inspect OpenRouter integration as comparable provider for Connect-OAuth-flow shape
- [ ] 0.9 **NEW — Capture cold-start performance**: p50/p95/p99 wall-clock for `stripe projects add ...` under bash-sandbox; record RSS per invocation
- [ ] 0.10 **NEW — Verify Stripe Secret Store API for `oauth_refresh_token`**: endpoint shape, retrieval latency from cron context, deletion behavior on `account.application.deauthorized`
- [ ] 0.11 **NEW — Verify Shared Payment Tokens issuance + redemption flow**: agent issues token; user actively completes 3DS; error envelope on user-not-tap; per-token usage limits; mandate ceiling fit
- [ ] 0.12 **NEW — Capture `account.application.deauthorized` webhook payload shape**
- [ ] 0.13 **NEW — Test concurrent token refresh**: two workers simultaneously on same `connected_account_id` — confirm Postgres `SELECT FOR UPDATE` serializes correctly
- [ ] 0.14 Write spike report to `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md`
- [ ] 0.15 Run `/soleur:architecture create` for **7 ADRs**: CLI-vs-REST, cloud-server-sole-executor, consent-crash-recovery, vendor-actions-two-table-model, vendor-actions-idempotency-separate-table, stripe-secret-store-substrate, shared-payment-tokens-substrate
- [ ] 0.16 Update `spec.md` with spike outputs; update plan Research Reconciliation table if anything resolves differently
- [ ] 0.17 Commit: `docs: spike report + 7 ADRs for stripe-projects integration`

## Phase 1: Foundations (Days 4-6)

- [ ] 1.1 Migration `035_vendor_actions_audit.sql` — **two-table model** per Data-F1
  - [ ] 1.1.1 Failing test `vendor-actions-rls.test.ts` first (TS16: history INSERT-only RLS)
  - [ ] 1.1.2 Mutable head `vendor_actions` (owner-SELECT, service-role-UPDATE) with top-level `vendor text NOT NULL` indexed; `provider_metadata jsonb`; `cap_cents`, `mandate_ceiling_cents`, `consent_token_id`, `prompt_hash`, `redacted_prompt`; **NO FK on `user_id`** (Data-F2); `anonymized_at timestamptz NULL`
  - [ ] 1.1.3 INSERT-only history `vendor_actions_audit_events` with trigger on head UPDATE
  - [ ] 1.1.4 All Postgres types use `text + CHECK` (NOT enum) per Data-F4
  - [ ] 1.1.5 `SECURITY DEFINER` helpers pin `SET search_path = public, pg_temp`
- [ ] 1.2 Migration `036_vendor_actions_idempotency.sql` — **separate table** per Reconciliation §6 (REVERSES `processed_stripe_events.scope` reuse from prior plan)
  - [ ] 1.2.1 Failing test `vendor-actions-idempotency.test.ts` (TS3 with cap_cents-included key + cross-token-TTL retry)
  - [ ] 1.2.2 Schema with 24h TTL partial index; insert-first dedup
- [ ] 1.3 Migration `037_stripe_connect_tokens.sql` — minimal shape per Reconciliation §7: `secret_store_path text NOT NULL`, lifetimes, `deauthorized_at`. **NO byok-encrypted columns.**
- [ ] 1.4 Migration `038_processed_stripe_events_subscription_updated.sql` — extend inbound webhook for `customer.subscription.updated` events on Stripe-Projects-provisioned subscriptions (mandate-ceiling re-consent trigger)
- [ ] 1.5 Extend `apps/web-platform/lib/feature-flags/server.ts` with `getFlagForUser(name, ctx)` per-user predicate
  - [ ] 1.5.1 Failing test `feature-flags-getFlagForUser.test.ts`
  - [ ] 1.5.2 Implementation
  - [ ] 1.5.3 Wire `stripe-projects-cloudflare-us` flag with US-billing-country predicate
  - [ ] 1.5.4 Cache TTL ≤ 30s for safety-disable flags (Perf-F5)
  - [ ] 1.5.5 Doc-comment warning against middleware/edge-runtime use (Arch F5)
- [ ] 1.6 `/api/vendor-actions/billing-country/route.ts` Server Action
- [ ] 1.7 Wire `reportSilentFallback` import sites for upcoming module

## Phase 2: Stripe Connect OAuth + Stripe Secret Store + Refresh Cron (Days 7-9)

- [ ] 2.1 Failing tests TS8, TS20 first
- [ ] 2.2 `/api/stripe-projects/oauth/start/route.ts` — state + PKCE
- [ ] 2.3 `/api/stripe-projects/oauth/callback/route.ts` — exchange code; **persist refresh token via Stripe Secret Store API** (NOT byok); store `secret_store_path` + lifetimes
- [ ] 2.4 `apps/web-platform/server/stripe-projects/oauth.ts` — `getValidConnectToken(userId)` with **distributed lock via Postgres `SELECT FOR UPDATE`** before refresh; atomic write of `(access_token, refresh_token, expires_at)` triple
- [ ] 2.5 `/api/stripe-projects/oauth/revoke/route.ts` — explicit revoke + cascade to audit + delete Secret Store entry
- [ ] 2.6 `/api/stripe-projects/webhook/account-deauthorized/route.ts` — Stripe `account.application.deauthorized` handler; mark `deauthorized_at`; surface "Reconnect Stripe" CTA on next interaction
- [ ] 2.7 `apps/web-platform/server/cron/stripe-connect-refresh.ts` — **proactive 6-month refresh cron** (D6/#3114 absorbed). Daily scan; refresh any older than 180 days; distributed lock as in 2.4
- [ ] 2.8 Wire cron in `vercel.json`
- [ ] 2.9 (DROPPED) WebAuthn step-up — Stripe Shared Payment Tokens covers SCA. Tracked in #3109.

## Phase 2.5: Shared Payment Tokens Integration (Days 10-11) — NEW

- [ ] 2.5.1 Failing tests TS14 (rewritten — Stripe Shared Payment Tokens substrate), TS21 (mandate-ceiling re-consent), TS22 (active-tap requirement) first
- [ ] 2.5.2 `apps/web-platform/server/stripe-projects/shared-payment-tokens.ts` — `issueToken(userId, vendor, mandateCeilingCents, agentId)` + `redeemToken(tokenId)`
- [ ] 2.5.3 Consent flow re-shaped: Approve redirects to Stripe-hosted SCA URL; state machine adds `3ds_required → 3ds_in_progress → 3ds_succeeded`/`3ds_failed`
- [ ] 2.5.4 `customer.subscription.updated` webhook handler — invalidate idempotency on price > `mandate_ceiling_cents`; emit re-consent banner
- [ ] 2.5.5 Modal copy update: "Stripe will ask you to confirm this purchase on your bank app"

## Phase 3: Shared core module (vendor-actions/) (Days 12-15)

- [ ] 3.1 Failing tests TS1, TS2 (three-invariant), TS3, TS5, TS6, TS9, TS9b, TS11b, TS12, TS13, TS15, TS18, TS19, TS24 first
- [ ] 3.2 Scaffold `apps/web-platform/server/vendor-actions/` (parent context per DDD F1)
  - [ ] 3.2.1 `index.ts` — public API: `add(provider, opts, command: VendorActionCommand)`. Inlined idempotency, three-invariant email-match, audit write, mandate-ceiling check, structured error envelope, partial-orphan inline detection
  - [ ] 3.2.2 `types.ts` — `VendorActionCommand` typed value object (DDD F5)
  - [ ] 3.2.3 `audit.ts` — append-only history-events writer + pre-encryption PII redactor (Sec-4)
- [ ] 3.3 Scaffold `apps/web-platform/server/stripe-projects/` (protocol ACL per DDD F1)
  - [ ] 3.3.1 `subprocess.ts` — `execFile` + `bash-sandbox`, `--json`, `STRIPE_API_KEY` via serviceTokens, **`STRIPE_LOG=info` hard-set** (Sec-2), `| head -n 500`, **pre-Sentry token-redactor** (Sec-2), **mkdtemp 0700 + try/finally rm -rf** (Sec-8)
  - [ ] 3.3.2 `oauth.ts` — Phase 2 integration
  - [ ] 3.3.3 `shared-payment-tokens.ts` — Phase 2.5 integration
  - [ ] 3.3.4 `index.ts` — translates CLI to `VendorActionCommand` outcomes; depends on `vendor-actions/`, NOT vice versa
- [ ] 3.4 Scaffold `apps/web-platform/server/consent/` (parent context per DDD F2)
  - [ ] 3.4.1 `tokens.ts` — HMAC-SHA256 with **`kid` rotation, JSON-map secret structure** (Sec-3)
  - [ ] 3.4.2 `decision.ts`, `status.ts`, `abort.ts` — protocol-agnostic
- [ ] 3.5 Idempotency (inlined): hash = `sha256(userId || provider || resource || plan_id || cap_cents || day_bucket)`. NO `consent_token_id`; INCLUDES `cap_cents` (Sec-7). Insert-first against `vendor_actions_idempotency`. Cached `response_json` on hit.
- [ ] 3.6 Three-invariant email-match assertion (inlined). Fail-closed.
- [ ] 3.7 **Inline orphan-detection with Sentry-as-fallback-substrate** (UI-1, TS9b): on email-match-fail-after-CF-success, write Sentry P1 FIRST with full context, THEN attempt audit row. Success-card MUST NOT render until at least one returns success.
- [ ] 3.8 Structured error envelope per code (P3): `ERR_EMAIL_MISMATCH`, `ERR_CAP_EXCEEDED` (with `lower_plan_alternatives`), `ERR_REGION_NOT_SUPPORTED` (with `suggested_alternatives`), `ERR_CONTRACT_DRIFT`, `ERR_3DS_FAILED`, `ERR_OAUTH_LAPSE`, `ERR_MANDATE_CEILING_EXCEEDED`
- [ ] 3.9 Granular state machine: `pending → consent_shown → approved → 3ds_required → 3ds_in_progress → 3ds_succeeded → executing → succeeded` (P5). Each transition writes `last_user_interaction_at` + `stage_entered_at`
- [ ] 3.10 Atomic transaction at `approved → 3ds_required` (Arch F1): state mutation + idempotency-row insert in same `BEGIN/COMMIT`
- [ ] 3.11 Add `stripe-projects` provider entry to `apps/web-platform/server/providers.ts` with `envVar: STRIPE_API_KEY`
- [ ] 3.12 Crash-recovery runbook documented per ADR (iii)

## Phase 4: Consent surfaces + agent-native parity API surfaces (Days 16-19)

- [ ] 4.1 ux-design-lead wireframes (Pencil MCP) for consent modal + mandate-ceiling banner
- [ ] 4.2 Failing tests TS4, TS7, TS21 (UX side) + agent-parity tests for status heartbeat & structured errors first
- [ ] 4.3 `components/chat/stripe-projects-consent-modal.tsx` — **active email-confirm checkbox** (UI-2), **mandate-ceiling re-consent disclosure**, Approve (kicks off Shared Payment Token + Stripe-hosted SCA redirect) / Edit / Cancel
- [ ] 4.4 `components/chat/stripe-projects-success-card.tsx` (failure path uses uniform error envelope rendering — no separate failure-card)
- [ ] 4.5 `components/chat/mandate-ceiling-reconsent-banner.tsx`
- [ ] 4.6 `/api/vendor-actions/intent/route.ts` — full **`proposal` payload echo** (P1)
- [ ] 4.7 `app/consent/[consentTokenId]/page.tsx` — standalone consent page (CLI path, OUTSIDE `/api/`)
- [ ] 4.8 `/api/consent/[consentTokenId]/decision/route.ts` — protocol-agnostic
- [ ] 4.9 `/api/consent/[consentTokenId]/status/route.ts` — `last_user_interaction_at` heartbeat (P2). **Soleur PAT bearer required** bound to `consent_token_id`; reject mismatches as 404 (Sec-6). **Redis 1s cache** + **polling pinned 2s exp-backoff to 10s** + rate-limit 120 req/min/user (Perf-F3)
- [ ] 4.10 `/api/consent/[consentTokenId]/abort/route.ts` (P6)
- [ ] 4.11 `/api/vendor-actions/audit-log/query/route.ts` — structured ≤50 rows, RLS-bound (P4)
- [ ] 4.12 **Register `vendor_actions_audit_query` + `stripe_projects_add` as agent-callable tools** in `agent-runner-tools.ts` (P4)
- [ ] 4.13 `/api/vendor-actions/audit-log/export/route.ts` — synchronous JSONL streaming, hard 10MB / 10k-row cap, rate-limit 10 req/hour
- [ ] 4.14 **Conditional async-with-progress UX** (Perf-F6): if Phase 0 spike showed `add()` p95 > 10s, ship 202 + job-ID + progress polling
- [ ] 4.15 copywriter agent review of all consent + success-card + mandate-ceiling-banner copy

## Phase 4.5: Pre-Ship Benchmark (Day 20) — NEW

- [ ] 4.5.1 Failing test TS23 first
- [ ] 4.5.2 Seed `vendor_actions_audit_events` with 10k rows × 6KB redacted prompts
- [ ] 4.5.3 Hit `/audit-log/export` cold cache; measure p95 end-to-end
- [ ] 4.5.4 Decision tree: <15s ship as-is; 15-20s `Transfer-Encoding: chunked` flush every 500; >20s reduce cap to 5k AND chunk

## Phase 5: ops-provisioner integration (Day 21)

- [ ] 5.1 Failing test TS17 first
- [ ] 5.2 Edit `plugins/soleur/agents/operations/ops-provisioner.md` — Tier 0: Stripe Projects above Playwright
- [ ] 5.3 Edit `plugins/soleur/agents/operations/service-automator.md` — Stripe Projects tier above MCP; new "Cloudflare (Stripe Projects Tier)" playbook
- [ ] 5.4 Edit `plugins/soleur/agents/operations/references/service-deep-links.md`
- [ ] 5.5 Add `ops-provisioner-cloudflare-stripe-projects` flag (2-week rollback)

## Phase 6: CLI plugin slash commands (Day 22)

- [ ] 6.1 Token-budget check: `bun test plugins/soleur/test/components.test.ts`; new SKILL.md ≤ 30 words
- [ ] 6.2 `plugins/soleur/skills/vendor-signup/SKILL.md` — `/soleur:vendor-signup <provider>`, `config`, `revoke`. Posts intent → opens Stripe-hosted SCA URL → polls (2s exp-backoff to 10s) → renders structured success/failure block. Sends `/abort` on SIGINT and 6-min idle.
- [ ] 6.3 `plugins/soleur/skills/audit-log/SKILL.md` — `/soleur:audit-log export` (JSONL) + `show [--last N]` (calls `/query` for structured)
- [ ] 6.4 Verify exit codes (0/1/4/5/6/7)
- [ ] 6.5 Failing tests TS4 (CLI), TS7 (CLI), TS10 first

## Phase 7: Marketing surfaces + launch post (Days 23-24, parallel with Phase 8)

Sequencing depends on Sprint Re-Evaluation outcome.

- [ ] 7.1 `plugins/soleur/docs/pages/integrations/stripe-projects.njk` — describes Stripe Secret Store + Shared Payment Tokens posture; inline critical CSS; pass `screenshot-gate.mjs`
- [ ] 7.2 Update `pages/agents.njk` with Stripe Projects badge
- [ ] 7.3 Update `pages/pricing/index.njk` with $25 cap + mandate-ceiling explainer
- [ ] 7.4 Update `_data/site.json` and `llms.txt`
- [ ] 7.5 Homepage hero badge in `_includes/base.njk`
- [ ] 7.6 Draft `pages/blog/2026-05-XX-stripe-projects-launch.njk`
- [ ] 7.7 Run `copywriter` agent for brand voice
- [ ] 7.8 Wire `social-distribute` skill for blog → HN → X → LinkedIn → dev.to within window

## Phase 8: Legal artifacts (Days 23-25, parallel with Phase 7)

- [ ] 8.1 Update `docs/legal/terms-and-conditions.md` — agent mandate addendum + beta-deprecation right + spend-cap + **mandate-ceiling liability** + force-majeure + **Stripe Shared Payment Tokens substrate disclosure** (Stripe owns SCA)
- [ ] 8.2 Update `docs/legal/privacy-policy.md` — Agent-Initiated Third-Party Subscriptions section + **Stripe Secret Store substrate disclosure** (Stripe holds encryption-at-rest) + **retention claim aligned to v1 capability** (UI-4)
- [ ] 8.3 Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 8.4 Update `docs/legal/acceptable-use-policy.md`
- [ ] 8.5 Update `compliance-posture.md` Vendor DPA — Stripe Projects + Stripe Secret Store + Shared Payment Tokens rows
- [ ] 8.6 Run `legal-compliance-auditor` agent
- [ ] 8.7 Open follow-on issue `feat-stripe-projects-eu-rollout`
- [ ] 8.8 Document GDPR anonymization runbook `runbooks/gdpr-erasure-vendor-actions.md` (Data-F2)

## Phase 9: CI + observability (Days 25-26)

- [ ] 9.1 `.github/workflows/scheduled-stripe-projects-contract.yml` (cron 02:00 UTC)
- [ ] 9.2 `.github/fixtures/stripe-projects-catalog-cloudflare-baseline.json` (vendor-specific, jq-filtered)
- [ ] 9.3 Auto-disable hook for `stripe-projects-cloudflare-us` flag on contract failure
- [ ] 9.4 Stripe Connect refresh cron wired in `vercel.json` (Phase 2.7)
- [ ] 9.5 Failing tests TS11, TS24 first

## Phase 10: Pre-ship + smoke + load-test (Days 27-29)

- [ ] 10.1 Full E2E against Stripe sandbox + Cloudflare staging
- [ ] 10.2 **Load-test target**: 50 concurrent `add()`, p95 < 2s, p99 RSS < 256MB. If exceeded, Phase 3 adds subprocess pool BEFORE ship (Perf-F1)
- [ ] 10.3 **Chaos test** TS24: flag-flip during simulated load; assert no `add()` >60s after flip; in-flight reach terminal state (Perf-F5)
- [ ] 10.4 `gh issue list --label code-review --state open` overlap re-check
- [ ] 10.5 `/soleur:preflight` — Check 6 validates User-Brand Impact
- [ ] 10.6 `/soleur:review` — 9-agent multi-review
- [ ] 10.7 Resolve all review findings fix-inline
- [ ] 10.8 `/soleur:qa` functional QA
- [ ] 10.9 `/soleur:compound` to capture session learnings
- [ ] 10.10 `/soleur:ship` with `semver:minor` label

## Post-merge (operator)

- [ ] OP1 `terraform apply -auto-approve` for Doppler secrets — including `STRIPE_PROJECTS_CONSENT_TOKEN_SECRET` (JSON-map with kid), `STRIPE_SECRET_STORE_API_KEY`, `STRIPE_SHARED_PAYMENT_TOKEN_API_KEY` (per `hr-menu-option-ack-not-prod-write-auth`)
- [ ] OP2 `gh secret set STRIPE_PROJECTS_WEBHOOK_SECRET`
- [ ] OP3 Flip `stripe-projects-cloudflare-us` ON for staff first; smoke test; then GA US
- [ ] OP4 `gh workflow run scheduled-stripe-projects-contract.yml` to verify path on main
- [ ] OP5 Geo-test from non-US IP (VPN)
- [ ] OP6 Verify launch post published to all 5 surfaces within Sprint Re-Evaluation outcome window
- [ ] OP7 `gh issue close 3106` after smoke test passes

## Deferred follow-on issues

| Issue | Status | Re-evaluation criterion |
|-------|--------|-------------------------|
| #3109 WebAuthn step-up | tracked Post-MVP | Auditor request OR cap-raise UX gap not covered by Stripe SCA |
| #3110 Hash-chain tamper-evidence | tracked Post-MVP | ≥1k audit rows OR auditor request |
| #3111 Async export job + CSV | tracked Post-MVP | First user hits 10MB/10k cap |
| #3112 Tiered cold-tier retention | tracked Post-MVP | Table approaches 1M rows OR 18 months |
| #3113 Hourly reconciliation cron | tracked Post-MVP | First orphan incident reveals failure class inline detection can't cover |
| ~~#3114~~ ~~11-month re-prompt cron~~ | **ABSORBED INTO v1** (Phase 2.7) — close at merge | n/a — proactive 6-month refresh ships in v1 per Reconciliation §9 |

## Sprint Re-Evaluation — pending operator decision

- [ ] OP-DECISION (a) Bundle all-at-once 4-5w (slip launch window) — fold every checkbox above
- [ ] OP-DECISION (b) Phased: ship Stripe Secret Store + Shared Payment Tokens + minimal consent in 14d behind feature flag, fast-follow PR for full agent-parity surfaces + chaos test + cold-tier
- [ ] OP-DECISION (c) Hold launch post; ship correct plan in 4-5w
