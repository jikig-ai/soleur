# Tasks: feat-agent-native-cloudflare-signup

Derived from `knowledge-base/project/plans/2026-05-03-feat-agent-native-cloudflare-signup-plan.md` (post-review Hybrid revision).

## Phase 0: Spike + ADR (Days 1-2)

- [ ] 0.1 Install `stripe` ≥ 1.40.0 + `stripe plugin install projects` in a sandbox container; capture pinned versions
- [ ] 0.2 Run `stripe projects init`, `catalog --json`, `add cloudflare/...` against Stripe sandbox; capture exit codes, stdout shapes, side-effect files (`.projects/`, `~/.config/stripe/`)
- [ ] 0.3 Test `Idempotency-Key` HTTP header behavior on retry
- [ ] 0.4 Test `--json` output stability across `stripe projects --version` bumps
- [ ] 0.5 Test cold-signup email override mechanisms (env vars, CLI flags) — confirm Stripe-email = CF-email is hard constraint
- [ ] 0.6 Test revoke cascade for auto-provisioned CF account (full delete vs unlink)
- [ ] 0.7 Test webhook surface — register wildcard Stripe webhook, capture events
- [ ] 0.8 Inspect OpenRouter integration as comparable provider (Connect-OAuth flow shape for headless servers)
- [ ] 0.9 Write spike report to `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md`
- [ ] 0.10 Run `/soleur:architecture create "Adopt Stripe Projects protocol for Cloudflare vendor cold-signup"`
- [ ] 0.11 Update `spec.md` with spike outputs; update plan Research Reconciliation table if anything resolves differently
- [ ] 0.12 Commit: `docs: spike report + ADR for stripe-projects integration`

## Phase 1: Foundations (Days 3-4)

- [ ] 1.1 Migration `035_vendor_actions_audit.sql` — append-only INSERT-only RLS, indexed `(user_id, created_at)`, `protocol` enum (`stripe-projects`, `playwright`, `mcp-tier`), `protocol_state` enum (incl. `email_mismatch_blocked`, `orphaned`, `revoked`); columns include `prompt_hash`, `encrypted_prompt`, `cap_cents`, `consent_token_id`. **No hash-chain in v1.** Pin `SET search_path = public, pg_temp` on any `SECURITY DEFINER` helper.
- [ ] 1.2 Migration `036_processed_stripe_events_scope.sql` — add `scope` column (default `'webhook-inbound'`); reuse for outbound idempotency under `scope = 'stripe-projects-outbound'`. Single source of truth for inbound + outbound.
- [ ] 1.3 Migration `037_stripe_connect_tokens.sql` — per-user encrypted Stripe Connect refresh-token storage; byok-encrypted columns following `users.byok_*` shape
- [ ] 1.4 Extend `apps/web-platform/lib/feature-flags/server.ts` with `getFlagForUser(name, ctx)` per-user predicate
  - [ ] 1.4.1 Failing test `feature-flags-getFlagForUser.test.ts`
  - [ ] 1.4.2 Implementation
  - [ ] 1.4.3 Wire `stripe-projects-cloudflare-us` flag with US-billing-country predicate
- [ ] 1.5 `/api/stripe-projects/billing-country/route.ts` Server Action — query Stripe customer billing country, cache per-session
- [ ] 1.6 Wire `reportSilentFallback` import sites for the upcoming module

## Phase 2: Stripe Connect OAuth (Days 5-6)

- [ ] 2.1 `/api/stripe-projects/oauth/start/route.ts` — `state` (CSRF) + PKCE; honors `validateOrigin`
- [ ] 2.2 `/api/stripe-projects/oauth/callback/route.ts` — exchange code for tokens, byok-encrypt refresh token via `byok.encryptKey`
- [ ] 2.3 `apps/web-platform/server/stripe-projects/oauth.ts` — `getValidConnectToken(userId)` with rotation (decrypt, refresh if `<1h to expiry`, re-encrypt); Sentry-mirror failures
- [ ] 2.4 `/api/stripe-projects/oauth/revoke/route.ts` — explicit revoke + cascade to audit (`protocol_state: 'revoked'` on active rows)
- [ ] 2.5 Failing test TS8 first; then implementation
- [ ] 2.6 (DROPPED) WebAuthn step-up — Stripe-hosted 3DS in existing Checkout satisfies PSD2 SCA Art. 97. Tracked as deferred follow-on.

## Phase 3: Shared core module (Days 7-9)

- [ ] 3.1 Failing tests TS1, TS2 (three-invariant), TS3 (day-bucket key), TS5, TS6, TS9 (inline orphan-detection), TS12, TS13, TS15 first
- [ ] 3.2 Scaffold `apps/web-platform/server/stripe-projects/`: `index.ts` (public API + inlined idempotency + email-match + errors), `subprocess.ts`, `audit.ts`. Standalone `idempotency.ts` / `email-match.ts` / `errors.ts` NOT created (inline until `index.ts` exceeds 300 lines).
- [ ] 3.3 `index.ts` exports `init`, `catalog`, `add(provider, opts, ctx)`, `revoke(provider, ctx)`. `ctx: { userId, capCents, consentTokenId, prompt }`.
- [ ] 3.4 `subprocess.ts` — `execFile` + `bash-sandbox`, `--json` only, `STRIPE_API_KEY` injected via serviceTokens, output piped through `| head -n 500`; capture full stderr to Sentry breadcrumb (not response body)
- [ ] 3.5 Inlined idempotency in `index.ts` — key = `sha256(userId || provider || resource || plan_id || day_bucket)`; **NO `consent_token_id` in hash** (Kieran #1). Insert-first dedup against `processed_stripe_events` with `scope = 'stripe-projects-outbound'`. Record `consent_token_id` on audit-log row only (traceability).
- [ ] 3.6 Inlined email-match assertion in `index.ts` — three invariants (Kieran #2): `cfAccount.email == user.stripe_email` AND `cfAccount.id == addResponse.account_id` AND `cfAccount.created_at < 60s ago`. Fail-closed: do not surface token, do not byok-persist, write Sentry incident, mark audit row `email_mismatch_blocked`.
- [ ] 3.7 Inline orphan-detection in `add()` catch — if email-match fails AFTER Stripe Projects reported `add` success, write `protocol_state: 'orphaned'` row + Sentry P1 incident, page support directly. (Replaces deferred reconciliation cron.)
- [ ] 3.8 `audit.ts` — append-only entry write; encrypts user prompt via `byok.encryptKey(prompt, userId)` before persisting; straight `INSERT` under append-only RLS (no hash-chain)
- [ ] 3.9 Add `stripe-projects` provider entry to `apps/web-platform/server/providers.ts` with `envVar: STRIPE_API_KEY` so subprocess passes `ALLOWED_SERVICE_ENV_VARS` check

## Phase 4: Consent surfaces (Days 10-12)

- [ ] 4.1 ux-design-lead wireframes (Pencil MCP) for consent modal — invoked at start of Phase 4 per Domain Review
- [ ] 4.2 Failing tests TS4, TS7 (UX side), TS9 (UX side), TS13 first
- [ ] 4.3 `components/chat/stripe-projects-consent-modal.tsx` — props: provider, plan, recurringAmountCents, oneTimeChargeCents, currency, fundingSourceLast4, rationale, reversalWindow; buttons Approve / Edit / Cancel; copy floor per Best-practices §1
- [ ] 4.4 `components/chat/stripe-projects-success-card.tsx` — failure path reuses existing chat error surface (no separate failure-card)
- [ ] 4.5 `/api/stripe-projects/intent/route.ts` — accepts CLI intent payload; validates Soleur PAT; returns `{ consentUrl, statusEndpoint }`
- [ ] 4.6 `app/consent/[consentTokenId]/page.tsx` — standalone consent page for CLI path. **Outside `app/api/`** per `cq-nextjs-route-files-http-only-exports` (Kieran #3).
- [ ] 4.7 `/api/stripe-projects/consent/[consentTokenId]/decision/route.ts` — records Approve/Cancel; on Approve kicks off `add()` server-side
- [ ] 4.8 `/api/stripe-projects/consent/[consentTokenId]/status/route.ts` — GET returns `pending | approved | executing | succeeded | failed` for CLI polling (no WebSocket)
- [ ] 4.9 `/api/stripe-projects/audit-log/export/route.ts` — synchronous JSONL streaming, hard 10MB / 10k-row cap, rate-limit 10 req/hour. **No CSV / no async job in v1** — 413 above cap with deferred-follow-on pointer.
- [ ] 4.10 copywriter agent review of all consent + success-card copy

## Phase 5: ops-provisioner integration (Day 14)

- [ ] 5.1 Failing test TS17 first
- [ ] 5.2 Edit `plugins/soleur/agents/operations/ops-provisioner.md` — Tier 0: Stripe Projects above Playwright; checks `stripe projects catalog --json` for target vendor
- [ ] 5.3 Edit `plugins/soleur/agents/operations/service-automator.md` — insert Stripe Projects tier above MCP; new "Cloudflare (Stripe Projects Tier)" playbook; clarify existing CF MCP playbook is for management of existing accounts
- [ ] 5.4 Edit `plugins/soleur/agents/operations/references/service-deep-links.md` — replace manual signup deep link with Stripe Projects-first instruction; keep dashboard URL as fallback
- [ ] 5.5 Add `ops-provisioner-cloudflare-stripe-projects` flag (2-week rollback window); follow-up PR removes Playwright CF branch after window expires

## Phase 6: CLI plugin slash commands (Day 15)

- [ ] 6.1 Token-budget check: `bun test plugins/soleur/test/components.test.ts` — note `current/1800` words; new SKILL.md ≤ 30 words
- [ ] 6.2 `plugins/soleur/skills/vendor-signup/SKILL.md` — `/soleur:vendor-signup <provider>`, `config`, `revoke`. Posts intent → opens `consentUrl` via `xdg-open`/`open` → polls status endpoint → renders structured success/failure block
- [ ] 6.3 `plugins/soleur/skills/audit-log/SKILL.md` — `/soleur:audit-log export`, `show [--last N]`
- [ ] 6.4 Verify exit codes (0 success, 4 geo-reject, 5 cap-exceed, 6 email-mismatch, 7 contract-drift, 1 other)
- [ ] 6.5 Failing tests TS4 (CLI), TS7 (CLI), TS10 first

## Phase 7: Marketing surfaces + launch post (Days 16-17, parallel with Phase 8)

- [ ] 7.1 `plugins/soleur/docs/pages/integrations/stripe-projects.njk` — inline critical CSS, pass `screenshot-gate.mjs`
- [ ] 7.2 Update `pages/agents.njk` with Stripe Projects badge + ops-provisioner playbook reference
- [ ] 7.3 Update `pages/pricing/index.njk` with $25 cap explainer
- [ ] 7.4 Update `_data/site.json` and `llms.txt`
- [ ] 7.5 Homepage hero badge (30-day duration) in `_includes/base.njk`
- [ ] 7.6 Draft `pages/blog/2026-05-XX-stripe-projects-launch.njk`
- [ ] 7.7 Run `copywriter` agent for brand voice
- [ ] 7.8 Wire `social-distribute` skill for blog → HN → X → LinkedIn → dev.to within 14-day window

## Phase 8: Legal artifacts (Days 16-18, parallel with Phase 7)

- [ ] 8.1 Update `docs/legal/terms-and-conditions.md` — agent mandate addendum, beta-deprecation right with pro-rata refund, spend-cap liability, beta force-majeure clause, chargeback playbook
- [ ] 8.2 Update `docs/legal/privacy-policy.md` — Agent-Initiated Third-Party Subscriptions section; Stripe + Cloudflare as separate processors; legal basis (contract performance + explicit consent); 6-year retention disclosed
- [ ] 8.3 Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 8.4 Update `docs/legal/acceptable-use-policy.md`
- [ ] 8.5 Update `compliance-posture.md` Vendor DPA table — new "Stripe Projects (provider role)" row
- [ ] 8.6 Run `legal-compliance-auditor` agent on updated docs
- [ ] 8.7 Open follow-on issue `feat-stripe-projects-eu-rollout` (DPIA + GDPR Policy update)

## Phase 9: CI + observability (Day 17)

- [ ] 9.1 `.github/workflows/scheduled-stripe-projects-contract.yml` (cron 02:00 UTC) — wraps `claude-code-action`; runs vendor-specific diff
- [ ] 9.2 `.github/fixtures/stripe-projects-catalog-cloudflare-baseline.json` (vendor-specific, jq-filtered to `.cloudflare`)
- [ ] 9.3 Auto-disable hook for `stripe-projects-cloudflare-us` flag on contract-test failure (TR17)
- [ ] 9.4 Failing test TS11 first
- [ ] 9.5 (DROPPED) Hourly reconciliation cron — orphan-detection inlined in `add()` catch (Phase 3.7); deferred to follow-on issue

## Phase 10: Pre-ship + smoke (Days 20-21)

- [ ] 10.1 Full E2E against Stripe sandbox + Cloudflare staging
- [ ] 10.2 `gh issue list --label code-review --state open` overlap re-check before review
- [ ] 10.3 `/soleur:preflight` — Check 6 validates `## User-Brand Impact`
- [ ] 10.4 `/soleur:review` — 9-agent multi-review (incl. `user-impact-reviewer`, `security-sentinel`)
- [ ] 10.5 Resolve all review findings fix-inline
- [ ] 10.6 `/soleur:qa` functional QA
- [ ] 10.7 `/soleur:compound` to capture session learnings
- [ ] 10.8 `/soleur:ship` with `semver:minor` label

## Post-merge (operator)

- [ ] OP1 `terraform apply -auto-approve` for Doppler secrets (per `hr-menu-option-ack-not-prod-write-auth`: show command, wait for go-ahead)
- [ ] OP2 `gh secret set STRIPE_PROJECTS_WEBHOOK_SECRET` (per `hr-menu-option-ack-not-prod-write-auth`)
- [ ] OP3 Flip `stripe-projects-cloudflare-us` ON for staff first; smoke test; then GA US
- [ ] OP4 `gh workflow run scheduled-stripe-projects-contract.yml` to verify path on main
- [ ] OP5 Geo-test from non-US IP (VPN)
- [ ] OP6 Verify launch post published to all 5 surfaces within 14-day window
- [ ] OP7 `gh issue close 3106` after smoke test passes

## Deferred follow-on issues (created at plan-finalize per `wg-when-deferring-a-capability-create-a`)

- [ ] D1 WebAuthn step-up for cap-raise / future high-risk actions (re-evaluation: auditor request OR cap-raise UX gap)
- [ ] D2 Hash-chain tamper-evidence for `vendor_actions_audit` (re-evaluation: ≥1k audit rows OR auditor request)
- [ ] D3 Async export job + CSV format for `/audit-log/export` (re-evaluation: first user hits 10MB/10k-row cap)
- [ ] D4 Tiered cold-tier audit retention (R2 object-lock + cold-migration job) (re-evaluation: table approaches 1M rows OR 18 months)
- [ ] D5 Hourly reconciliation cron for orphan-class failures (re-evaluation: first orphan incident reveals failure class inline detection can't cover)
- [ ] D6 Automated 11-month Stripe Connect refresh-token re-prompt cron (re-evaluation: first user OAuth + 11 months ≈ Q2 2027)
