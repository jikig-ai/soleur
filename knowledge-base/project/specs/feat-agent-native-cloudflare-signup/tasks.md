# Tasks: feat-agent-native-cloudflare-signup

Derived from `knowledge-base/project/plans/2026-05-03-feat-agent-native-cloudflare-signup-plan.md`.

## Phase 0: Spike + ADR (Days 1-2)

- [ ] 0.1 Install `stripe` ≥ 1.40.0 + `stripe plugin install projects` in a sandbox container; capture pinned versions
- [ ] 0.2 Run `stripe projects init`, `catalog --json`, `add cloudflare/...` against Stripe sandbox; capture exit codes, stdout shapes, side-effect files
- [ ] 0.3 Test `Idempotency-Key` HTTP header behavior on retry
- [ ] 0.4 Test `--json` output stability across `stripe projects --version` bumps
- [ ] 0.5 Test cold-signup email override mechanisms (env vars, CLI flags)
- [ ] 0.6 Test revoke cascade for auto-provisioned CF account (full delete vs unlink)
- [ ] 0.7 Test webhook surface — register wildcard Stripe webhook, capture events
- [ ] 0.8 Inspect OpenRouter integration as comparable provider
- [ ] 0.9 Write spike report to `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md`
- [ ] 0.10 Run `/soleur:architecture create "Adopt Stripe Projects protocol for Cloudflare vendor cold-signup"`
- [ ] 0.11 Update `spec.md` with spike outputs; update plan Research Reconciliation table
- [ ] 0.12 Commit: `docs: spike report + ADR for stripe-projects integration`

## Phase 1: Foundations (Days 3-5)

- [ ] 1.1 Migration `035_vendor_actions_audit.sql` — append-only RLS, hash-chain, indexed `(user_id, created_at)`, `protocol` + `protocol_state` enums
  - [ ] 1.1.1 Failing test `vendor-actions-audit-hash-chain.test.ts` first
  - [ ] 1.1.2 Migration body
- [ ] 1.2 Migration `036_vendor_actions_idempotency.sql` — dedup-insert-first, RLS, 24h TTL via partial index
- [ ] 1.3 Migration `037_stripe_connect_tokens.sql` — byok-encrypted columns
- [ ] 1.4 Extend `apps/web-platform/lib/feature-flags/server.ts` with `getFlagForUser(name, ctx)` per-user predicate
  - [ ] 1.4.1 Failing test `feature-flags-getFlagForUser.test.ts`
  - [ ] 1.4.2 Implementation
  - [ ] 1.4.3 Wire `stripe-projects-cloudflare-us` flag with US-billing-country predicate
- [ ] 1.5 `/api/stripe-projects/billing-country/route.ts` Server Action

## Phase 2: Stripe Connect OAuth + WebAuthn (Days 6-7)

- [ ] 2.1 `/api/stripe-projects/oauth/start/route.ts` — state + PKCE
- [ ] 2.2 `/api/stripe-projects/oauth/callback/route.ts` — exchange, byok-encrypt refresh token
- [ ] 2.3 `apps/web-platform/server/stripe-projects/oauth.ts` — `getValidConnectToken(userId)` with rotation
- [ ] 2.4 `/api/stripe-projects/oauth/revoke/route.ts` — explicit revoke + cascade to audit
- [ ] 2.5 Add `@simplewebauthn/server` dep (verify both `bun.lock` and `package-lock.json` regenerate)
- [ ] 2.6 Migration `038_vendor_webauthn_attestations.sql`
- [ ] 2.7 `/api/stripe-projects/webauthn/challenge/route.ts`
- [ ] 2.8 `/api/stripe-projects/webauthn/verify/route.ts`
- [ ] 2.9 Failing tests TS8, TS14 first; then implementation

## Phase 3: Shared core module (Days 8-10)

- [ ] 3.1 Failing tests TS1, TS2, TS3, TS5, TS6, TS9, TS12, TS13, TS15, TS16 first
- [ ] 3.2 `apps/web-platform/server/stripe-projects/index.ts` (public API)
- [ ] 3.3 `apps/web-platform/server/stripe-projects/subprocess.ts` — `execFile` + `bash-sandbox`, `--json`, `| head -n 500`
- [ ] 3.4 `apps/web-platform/server/stripe-projects/idempotency.ts` — sha256 key derivation + persistence
- [ ] 3.5 `apps/web-platform/server/stripe-projects/email-match.ts` — post-call assertion, fail-closed
- [ ] 3.6 `apps/web-platform/server/stripe-projects/audit.ts` — hash-chain entry write, byok-encrypt prompt
- [ ] 3.7 `apps/web-platform/server/stripe-projects/errors.ts` — typed error codes
- [ ] 3.8 Add `stripe-projects` provider entry to `apps/web-platform/server/providers.ts` with `STRIPE_API_KEY` envVar so subprocess invocation passes the `ALLOWED_SERVICE_ENV_VARS` check

## Phase 4: Consent surfaces (Days 11-13)

- [ ] 4.1 ux-design-lead wireframes (Pencil MCP) for consent modal — invoked at start of Phase 4 per Domain Review
- [ ] 4.2 Failing tests TS4, TS7 (UX side), TS9 (UX side), TS13 first
- [ ] 4.3 `components/chat/stripe-projects-consent-modal.tsx` — copy floor per Best-practices §1
- [ ] 4.4 `components/chat/stripe-projects-success-card.tsx`
- [ ] 4.5 `components/chat/stripe-projects-failure-card.tsx`
- [ ] 4.6 `components/audit-log/audit-log-export-button.tsx`
- [ ] 4.7 `/api/stripe-projects/intent/route.ts` — CLI intent endpoint
- [ ] 4.8 `/api/stripe-projects/consent/[consentTokenId]/page.tsx` — standalone consent page (CLI path)
- [ ] 4.9 `/api/stripe-projects/consent/[consentTokenId]/decision/route.ts`
- [ ] 4.10 `/api/stripe-projects/audit-log/export/route.ts` — JSONL + CSV + async-job for >10k rows
- [ ] 4.11 copywriter agent review of all consent + success/failure modal copy

## Phase 5: ops-provisioner integration (Day 14)

- [ ] 5.1 Failing test TS17 first
- [ ] 5.2 Edit `plugins/soleur/agents/operations/ops-provisioner.md` — Tier 0: Stripe Projects above Playwright
- [ ] 5.3 Edit `plugins/soleur/agents/operations/service-automator.md` — insert Stripe Projects tier above MCP
- [ ] 5.4 Edit `plugins/soleur/agents/operations/references/service-deep-links.md` — replace manual signup deep link
- [ ] 5.5 Add `ops-provisioner-cloudflare-stripe-projects` flag (2-week rollback window)

## Phase 6: CLI plugin slash commands (Day 15)

- [ ] 6.1 Token-budget check: `bun test plugins/soleur/test/components.test.ts` — note `current/1800` words; new SKILL.md ≤ 30 words
- [ ] 6.2 `plugins/soleur/skills/vendor-signup/SKILL.md` — `/soleur:vendor-signup <provider>`, `config`, `revoke`
- [ ] 6.3 `plugins/soleur/skills/audit-log/SKILL.md` — `/soleur:audit-log export`, `show`
- [ ] 6.4 Verify exit codes (0 success, 4 geo-reject, 5 cap-exceed, 6 email-mismatch, 7 contract-drift, 1 other)
- [ ] 6.5 Failing tests TS4 (CLI), TS7 (CLI), TS10 first

## Phase 7: Marketing surfaces + launch post (Days 16-17, parallel with Phase 8)

- [ ] 7.1 `plugins/soleur/docs/pages/integrations/stripe-projects.njk` — inline critical CSS, pass `screenshot-gate.mjs`
- [ ] 7.2 Update `pages/agents.njk` with Stripe Projects badge
- [ ] 7.3 Update `pages/pricing/index.njk` with $25 cap explainer
- [ ] 7.4 Update `_data/site.json` and `llms.txt`
- [ ] 7.5 Homepage hero badge (30-day duration) in `_includes/base.njk`
- [ ] 7.6 Draft `pages/blog/2026-05-XX-stripe-projects-launch.njk`
- [ ] 7.7 Run `copywriter` agent for brand voice
- [ ] 7.8 Wire `social-distribute` skill for blog → HN → X → LinkedIn → dev.to

## Phase 8: Legal artifacts (Days 16-18, parallel with Phase 7)

- [ ] 8.1 Update `docs/legal/terms-and-conditions.md` — agent mandate addendum + beta-deprecation right + spend-cap liability + force-majeure
- [ ] 8.2 Update `docs/legal/privacy-policy.md` — Agent-Initiated Third-Party Subscriptions section
- [ ] 8.3 Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 8.4 Update `docs/legal/acceptable-use-policy.md`
- [ ] 8.5 Update `compliance-posture.md` Vendor DPA table
- [ ] 8.6 Run `legal-compliance-auditor` agent on updated docs
- [ ] 8.7 Open follow-on issue `feat-stripe-projects-eu-rollout` (DPIA + GDPR Policy update)

## Phase 9: CI + observability (Day 19)

- [ ] 9.1 `.github/workflows/scheduled-stripe-projects-contract.yml` (cron 02:00 UTC)
- [ ] 9.2 `.github/fixtures/stripe-projects-catalog-baseline.json` (vendor-specific, jq-filtered)
- [ ] 9.3 Auto-disable hook for `stripe-projects-cloudflare-us` flag on contract-test failure
- [ ] 9.4 `apps/web-platform/server/cron/vendor-actions-reconcile.ts` (hourly)
- [ ] 9.5 Wire reconcile cron into `vercel.json`
- [ ] 9.6 Failing test TS11 first

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
