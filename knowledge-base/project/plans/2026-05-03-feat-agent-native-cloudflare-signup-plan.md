---
type: feature
classification: user-brand-critical
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: "3106"
related_issues: ["3107", "1287"]
worktree: ".worktrees/feat-agent-native-cloudflare-signup"
branch: feat-agent-native-cloudflare-signup
draft_pr: 3100
brainstorm: knowledge-base/project/brainstorms/2026-05-03-agent-native-cloudflare-signup-brainstorm.md
spec: knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spec.md
date: 2026-05-03
---

# Plan: Agent-Native Cloudflare Signup via Stripe Projects (Consumer Side)

## Overview

Adopt Cloudflare's Stripe Projects protocol (https://blog.cloudflare.com/agents-stripe-projects/, open beta 2026-04-30) so a Soleur agent can subscribe a US-only user to Cloudflare in one programmatic step, replacing the deferred Playwright cold-signup path. Two entry points — cloud chat and CLI plugin — share a single executor in `apps/web-platform/server/stripe-projects/`. **Cloud server is the only authorized executor of `stripe projects add`** (see Research Reconciliation §1); the CLI plugin POSTs intent to the cloud, which renders the per-action consent modal in the browser, requires WebAuthn step-up on first vendor relationship, then invokes the protocol. Soleur-side default cap $25/mo per provider per user (raisable to Stripe's $100). All `add()` invocations are idempotent, byok-encrypt the returned Cloudflare token at rest, append to a generic `vendor_actions_audit` table with 6-year tiered retention, and pass through a fail-closed post-call email-match assertion to prevent cross-tenant attribution. ops-provisioner's Cloudflare cold-signup branch is gated behind a feature flag with a 2-week Playwright rollback. Anchor launch post ships within the 14-day first-mover window from Cloudflare's announcement.

User-elected sequence per brainstorm decision #6: bundle all-at-once 3-week sprint (spike → ADR → CLI + cloud + Playwright retirement in one pass), accepting blast-radius and beta-protocol risk to hit the launch window.

## Why

User-brand-critical (`single-user incident` threshold per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`). All four user-impact vectors apply: billing surprise, credential leak, cross-tenant attribution, PII. CPO sign-off is required at plan time before `/work`, and `user-impact-reviewer` is invoked at PR time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## User-Brand Impact

Carried forward from the brainstorm's `## User-Brand Impact` section.

**If this lands broken, the user experiences:** an unauthorized `$X/mo` Cloudflare charge they did not approve, OR a Cloudflare API token leaked to logs/Sentry/audit-log read paths visible to other tenants, OR provisioning attributed to the wrong tenant (user A's intent triggers user B's CF account provisioning).

**If this leaks, the user's payment + auth credentials are exposed via:** (a) the Cloudflare API token returned by Stripe Projects logging to stdout via subprocess inheritance; (b) `byok` decryption surfacing tokens before the email-match assertion; (c) the audit-log JSONL export endpoint streaming a different user's rows due to RLS misconfiguration; (d) the orphan-account class — Cloudflare auto-provisioned account left dangling with the user's Stripe email but no Soleur-side persistence (Research Reconciliation §3); (e) the `.projects/vault/` plaintext `.env` material that Stripe Projects writes by default (Research Reconciliation §4).

**Brand-survival threshold:** `single-user incident`.

**Mandatory reviewers:** CPO sign-off at plan time (this gate); `user-impact-reviewer` at PR time. CLO concerns from brainstorm are reflected in the Risks & Mitigations and Files to Create (legal-artifact track) sections — CLO does not re-sign here, per the lifecycle staging in `plugins/soleur/skills/plan/SKILL.md` Phase 2.6.

## Research Reconciliation — Spec vs. Codebase + External

The spec was written before Stripe Projects API research and best-practices research returned. Five claims need correction at plan time. Implementation diverges from the spec on these points; the spec will be updated to match this plan during Phase 0 of implementation.

| # | Spec/brainstorm claim | Reality | Plan response |
|---|----------------------|---------|---------------|
| 1 | TR1: "REST-first shared core ... falls back to the `stripe` CLI subprocess only when REST is unavailable" | No public REST API for `stripe projects add/init/catalog/revoke` exists as of 2026-05-03. Provider integration uses OAuth/OIDC + payment tokenization, but the Stripe-side endpoints are not documented. CLI is the only reliable surface. (Stripe Projects research §1) | Phase 0 spike resolves this definitively. **Default plan assumes CLI-subprocess primary**, REST opportunistic. The shared core wraps the `stripe` binary via `execFile` under `bash-sandbox`. If the spike confirms a REST surface, Phase 3 swaps the implementation behind the same module interface — module API stays stable. |
| 2 | Brainstorm #2: "Both entry points (cloud chat + CLI plugin) consume a shared REST-first core via thin shim ... CLI plugin uses local `stripe` CLI on PATH" | Stripe's CLI-issued restricted keys cannot legitimately authorize user-funded actions on the user's behalf. Stripe Connect server-side OAuth (cloud-bound, encrypted refresh token) is the only valid substrate for `single-user incident` threshold. Best-practices §3. | **Cloud server is the only executor of `stripe projects add`.** CLI plugin POSTs intent to `/api/stripe-projects/intent`, server returns a short-lived signed consent URL, user opens in browser, approves with WebAuthn step-up, server invokes Stripe Projects via the cloud-bound Stripe Connect token. The CLI's local `~/.config/stripe/` is **not the substrate** — it remains a developer-convenience surface only and is never used to authorize user-funded actions. |
| 3 | Spec FR4: "renders a 'new Cloudflare account provisioned' notice in the consent confirmation" | Cloudflare auto-provisions the new account with the **Stripe-attested email** as the only documented option (Stripe Projects research §5). No override mechanism is documented. The user cannot pick a different email at consent time. | FR4 (revised): the consent modal shows "Cloudflare will use your Stripe email `<email>` for the new account. To use a different email, set up a Cloudflare account manually first and revoke this consent." This becomes a hard product constraint surfaced in the modal copy and the pricing-page disclosure. |
| 4 | Spec TR9: append-only audit log with no retention specified | UK contract limitation for "agent charged me without consent" disputes runs **6 years** (Best-practices §2). GDPR Art. 5(1)(c) data minimization rules out 10+ years. SOC 2 expects ≥1 year. Stripe Issuing analogue uses 7 years for charge records (separate substrate). | TR9 (revised): retention target is 6 years total. **v1 ships hot-only in Postgres `vendor_actions_audit` with append-only INSERT-only RLS** — sufficient for SOC 2 ≥1 year and the first 18 months of disputes. Tiered cold-tier (R2 object-lock + cold-migration job) is deferred to a follow-on issue, triggered when the table approaches 1M rows or 18 months of data. Hash-chained tamper-evidence is also deferred (Postgres WAL + RLS gives sufficient floor at 0 users); follow-on issue tracked. Audit-log substrate stores `prompt_hash + encrypted_prompt`, not cleartext, to bound exposure. |
| 5 | Spec TR1 module name `apps/web-platform/server/stripe-projects/`; Spec TR9 table name `stripe_projects_audit` | The provider-side companion (#3107) will need the same audit-log shape and intent-execution flow. Naming for one vendor protocol invites a second table in 2 weeks. (Functional-discovery §Risk 2) | Module stays `apps/web-platform/server/stripe-projects/` (vendor-protocol-specific). Audit table generalizes to `vendor_actions_audit` (vendor-agnostic columns + `protocol` enum: `stripe-projects`, `playwright`, `mcp-tier`). RLS policies, indexing, and export endpoint are protocol-agnostic. |
| 6 | Spec TR2: "STRIPE_CONFIG_PATH=$HOME/.config/stripe enforced explicitly in agent-env.ts" | `agent-env.ts` line 12-28 has a hardcoded 14-var `AGENT_ENV_ALLOWLIST` that does not include STRIPE_CONFIG_PATH. The serviceTokens override path validates against `PROVIDER_CONFIG.envVar`, where STRIPE_CONFIG_PATH is not currently registered. | Reframed by Reconciliation §2: cloud server invokes `stripe projects` against the cloud-bound Stripe Connect token, NOT a per-user `~/.config/stripe/`. The `STRIPE_CONFIG_PATH` workspace isolation is no longer needed for the consumer-side path. The CLI plugin path runs on the user's local machine outside our sandbox and uses whatever `~/.config/stripe/` the user has — but only for non-funded operations like `stripe projects catalog --json` (read-only catalog browsing). Funded operations always round-trip the cloud server. |

## Domain Review

**Domains relevant:** Marketing, Engineering, Operations, Product, Legal (carried forward from brainstorm `## Domain Assessments`).

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** 14-day first-mover window from 2026-04-30; anchor launch post by 2026-05-07. Surfaces: net-new `/integrations/stripe-projects` (P0), `/agents/`, `/pricing`, `llms.txt`, homepage hero (P1-P2). Pricing communication: $25 cap as "agent-safe spending" feature, not bug.

### Engineering (CTO)

**Status:** reviewed (carry-forward + Reconciliation §1, §2 refinement)
**Assessment:** Architecture revised — cloud server is the sole executor; CLI plugin is intent-passing only. Critical risks: cross-tenant credential bleed, silent fallback wrong-token, $100 cap UX cliff, beta protocol churn. Spike required before module work.

### Operations (COO)

**Status:** reviewed (carry-forward)
**Assessment:** Cloudflare adopt now via Stripe Projects (top tier). Vercel/Supabase/Resend wait + dual-path. GitHub/Hetzner stay Playwright/Terraform. ops-provisioner.md and service-automator.md tier-order updates required. Expense ledger gets `Spend Cap` column + user-side visibility section.

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** Materially safer than Playwright but does NOT replace the deferred agency-framework brainstorm. Required artifacts before US v1 ship: ToS addendum, Privacy Policy update, AUP update, audit-log schema + retention policy, per-action consent UX legal sign-off. EU rollout gated on DPIA + GDPR-trio updates. Stripe and Cloudflare are independent processors of the user.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, copywriter (deferred to launch-post phase), cpo (carried forward from brainstorm)
**Skipped specialists:** ux-design-lead (Pencil MCP not invoked — this plan defers wireframes to deepen-plan / start of `/work` Phase 4. Justification: per AGENTS.md Phase 2.5 BLOCKING gate, this is a `Skip with acknowledgment` — the consent modal copy is constrained by GDPR Art. 4(11) and Smashing 2026 (Best-practices §1) and has near-zero UX freedom; wireframes will run when implementation begins.)
**Pencil available:** N/A (skipped)

#### Findings

spec-flow-analyzer surfaced **23 spec gaps**, including 5 critical pre-freeze blockers: missing Stripe OAuth flow specification (FG1), missing token-revocation surface (FG7), no geo-gate recovery path (FG10), audit-log write-failure reconciliation (ME7), cross-entry-point idempotency lock (RC1). All 23 gaps are addressed in the FRs/TRs below or in the Open Questions section as known-deferred follow-ons. Full findings are in the spec-flow-analyzer task output (preserved in the brainstorm worktree for reference).

**Brainstorm-recommended specialists:** copywriter (CMO; deferred to Phase 7 launch-post), business-validator (CPO; deferred — re-validation triggered by Phase 4 founder recruitment, not by this plan), competitive-intelligence (CPO; out of scope for this plan, but tracked separately under post-ship monitoring).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 spike has answered Stripe Projects research items 1, 3, 5, 7, 8, 11 (see Research Reconciliation + Open Questions); ADR landed via `/soleur:architecture create`; spec.md updated to reflect spike outputs.
- [ ] `vendor_actions_audit` migration (035) created: append-only INSERT-only RLS, indexed `(user_id, created_at)`, `protocol` enum (`stripe-projects`, `playwright`, `mcp-tier`), `protocol_state` enum. **No hash-chain in v1** — Postgres WAL + append-only RLS is the v1 tamper-evidence floor; hash-chain deferred to follow-on issue.
- [ ] Idempotency for outbound Stripe Projects calls reuses the `processed_stripe_events` shape via a `scope` column extension (migration 036_processed_stripe_events_scope.sql). Single source of truth for inbound + outbound idempotency.
- [ ] `apps/web-platform/lib/feature-flags/server.ts` extended with `getFlagForUser(name, ctx)` per-user predicate evaluation; `stripe-projects-cloudflare-us` flag wired and predicate uses Stripe-attested billing country.
- [ ] `apps/web-platform/server/stripe-projects/` core module shipped with `init/catalog/add/revoke`, idempotency wrap, post-call email-match assertion (fails closed; asserts `account.email == user.stripe_email` AND `account.id == add_response.account_id` AND `account.created_at < 60s ago`), byok encryption of returned CF token, `reportSilentFallback` on every catch path, `bash-sandbox`-wrapped subprocess. Inline orphan-detection in `add()` catch block (no separate cron in v1).
- [ ] Per-action consent modal component shipped in `apps/web-platform/components/chat/` with: vendor + plan + recurring amount + funding source last-4 + rationale + reversal-window note + 3 buttons (Approve / Edit / Cancel) + audit-log link. Copy reviewed against Best-practices §1 floor.
- [ ] First-charge SCA satisfied by Stripe-hosted 3DS in the existing Checkout flow (PSD2 Art. 97 floor). **WebAuthn step-up deferred to follow-on** — not required for v1 since Stripe-hosted 3DS already satisfies SCA for the funded action.
- [ ] `/api/stripe-projects/oauth/start` + `/api/stripe-projects/oauth/callback` Stripe Connect server-side OAuth; refresh token rotation + invalidation on `customer.subscription.deleted` and explicit revoke. 1-year refresh-token TTL is acceptable in v1 — operator manually re-prompts users at 11-month mark; automated re-prompt cron deferred to follow-on.
- [ ] `/api/stripe-projects/intent` endpoint accepts CLI-plugin intent payloads, validates Soleur-issued PAT, returns short-lived signed consent URL. CLI polls a status endpoint (no WebSocket — simpler, sufficient for v1).
- [ ] `/api/stripe-projects/audit-log/export` endpoint streams JSONL of caller's own rows synchronously with a 10MB / 10k-row hard cap. Rate-limited (10 req/hour). **Async-job pattern + CSV format deferred** to follow-on issue triggered when first user hits the cap.
- [ ] CLI plugin slash commands: `/soleur:vendor-signup cloudflare`, `/soleur:vendor-signup config`, `/soleur:vendor-signup revoke`, `/soleur:audit-log export` — all delegate to `service-automator`.
- [ ] `plugins/soleur/agents/operations/ops-provisioner.md` and `service-automator.md` updated with Stripe Projects as new top tier above MCP (with disambiguation: catalog vendors only).
- [ ] `plugins/soleur/agents/operations/references/service-deep-links.md` updated for the new tier.
- [ ] Nightly contract test job in `.github/workflows/scheduled-stripe-projects-contract.yml` runs against pinned `stripe` CLI + `projects` plugin versions; fails closed and posts `stripe-projects-protocol-drift` issue on schema/output drift.
- [ ] Auto-disable feature flag on contract-test failure (TR17 from spec-flow recommendations) — wired via the existing scheduled-action skeleton.
- [ ] PR body uses `Ref #3106` (NOT `Closes`) since post-merge operator actions remain. `Ref #3107` for cross-link. Final `gh issue close 3106` is operator step OP7.
- [ ] CPO sign-off comment on PR before merge.
- [ ] `user-impact-reviewer` invoked at review-time and findings resolved fix-inline.
- [ ] `/integrations/stripe-projects` Eleventy page shipped; `/agents/`, `/pricing`, `llms.txt`, homepage hero badge updates landed in the same PR.
- [ ] Legal artifacts landed in the same PR (or chained PR merging before flag flip): ToS addendum, Privacy Policy update, AUP update, Data Protection Disclosure update.
- [ ] Smoke E2E test against Stripe sandbox + Cloudflare staging (where available) covers: cold signup, email-match assertion (positive + negative), $25 cap exceed, geo-reject for non-US, OAuth lapse re-consent, idempotency replay, revoke cascade.
- [ ] TDD: failing tests written BEFORE implementation per `cq-write-failing-tests-before` for every TR (excluding pure-config tasks).
- [ ] All `## Files to Edit` and `## Files to Create` paths verified against `git ls-files` (per `hr-when-a-plan-specifies-relative-paths-e-g`).
- [ ] No new package.json deps introduced beyond `@stripe/connect-js` (browser-side); existing `stripe` SDK covers server side.
- [ ] All catch blocks emitting 4xx/5xx mirror via `reportSilentFallback`; no exemption requests for the consumer-side flow.

### Post-merge (operator)

Per `cq-when-a-pr-has-post-merge-operator-actions`, this section uses `Ref #3106` semantics in the PR body — final issue close happens after operator steps complete.

- [ ] Operator runs `terraform apply -auto-approve` against `apps/web-platform/infra/` to provision the `STRIPE_PROJECTS_CLIENT_ID`, `STRIPE_PROJECTS_CLIENT_SECRET`, `STRIPE_PROJECTS_REDIRECT_URI` Doppler secrets.
- [ ] Operator runs `gh secret set STRIPE_PROJECTS_WEBHOOK_SECRET` (per `hr-menu-option-ack-not-prod-write-auth`: show command, wait for go-ahead).
- [ ] Operator manually flips the `stripe-projects-cloudflare-us` feature flag ON for staff users only first; runs internal smoke test; then flips for general US users.
- [ ] Operator triggers `gh workflow run scheduled-stripe-projects-contract.yml` to verify the nightly contract test path is healthy on main (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- [ ] Operator confirms US-only flag predicate by attempting the flow from a non-US IP (VPN test) — must return geo-reject surface.
- [ ] Operator verifies the launch post is published to blog + HN + X + LinkedIn + dev.to within the 14-day window.
- [ ] Operator runs `gh issue close 3106` after the smoke test passes.

## Test Scenarios

TDD per `cq-write-failing-tests-before`. Tests land BEFORE implementation in each phase.

| # | Scenario | Layer | Failure mode covered |
|---|----------|-------|---------------------|
| TS1 | Cold signup happy path: US user, no existing CF, valid Stripe OAuth, approves modal, WebAuthn passes, CF account auto-provisioned with Stripe email, byok-encrypted token persisted, audit-log row written, success card rendered. | E2E | None (golden path) |
| TS2 | Email-match assertion fails closed under THREE invariants (Kieran review fix #2): (a) mismatched email, (b) matched email + mismatched `account.id` (orphan-account variant), (c) matched email + matched id but `account.created_at > 60s ago` (CF cache-hit variant). All three must fail closed; token must NOT surface; Sentry incident written; audit-log row marks `protocol_state: 'email_mismatch_blocked'`. | Integration | Cross-tenant credential bleed (TR3) + orphan-account hijack |
| TS3 | Idempotency replay: same user invokes `add()` with identical `(provider, resource, plan, day_bucket)` twice within 24h. Second call returns cached response from first; no duplicate provisioning. **Kieran review fix #1**: also verify that retry AFTER consent-token TTL expiry (new `consent_token_id`, same `(provider, resource, plan, day_bucket)`) STILL hits the cached response — does NOT double-provision. | Unit + integration | Double-provisioning (TR4) + Kieran idempotency foot-gun |
| TS4 | Cross-entry-point lock: user starts cloud-chat flow, abandons at consent modal, retries from CLI within 5min. CLI must NOT block forever and must NOT bypass consent — server returns `flow-pending-elsewhere` with TTL. | Integration | RC1 — cross-entry-point race |
| TS5 | Spend cap exceed: user has $25 cap; agent attempts a Workers Paid plan that exceeds it. Server pre-flight returns `cap-would-exceed` with copy; no provisioning attempted. | Unit | FR6 + ME11 |
| TS6 | Cap raise mid-flight: cap value captured at consent-modal-render time is locked into the audit-log row; later cap raise does NOT retroactively apply to the in-flight call. | Integration | ME5 — cap-raise race |
| TS7 | Geo-reject for non-US: user with Stripe-attested billing country `DE` invokes the flow. Cloud surface returns 451-equivalent + waitlist email capture. CLI returns `region-not-supported` exit code 4. | Unit | FR7 + FG10 |
| TS8 | OAuth lapse re-consent: mid-session, Stripe Connect refresh fails (token revoked externally). User is redirected to OAuth re-consent; original intent + idempotency key are preserved; on success, flow resumes from consent-modal step. | Integration | ME1 + ME2 |
| TS9 | Audit-log write failure: mock the `vendor_actions_audit` insert to fail before CF token surfaces. Token MUST NOT surface; user sees a "provisioning held — support paged" card; Sentry incident written; reconciliation job picks up the orphan within 1 hour. | Integration | ME7 + RP2 |
| TS10 | Revoke cascade: user invokes `/soleur:vendor-signup revoke cloudflare`. Server calls `stripe projects remove cloudflare`; if successful, marks audit row `protocol_state: 'revoked'`, decrypts and deletes byok token. CF API token is invalidated. | Integration | FR11 + FG7 |
| TS11 | Beta protocol drift: nightly contract test detects schema change in `stripe projects catalog --json` output. Job posts `stripe-projects-protocol-drift` issue and flips `stripe-projects-cloudflare-us` flag to OFF. In-flight users see "feature paused for safety" card. | E2E (against staging) | TR7 + TR17 + ME12 |
| TS12 | Sentry mirror failure: mock Sentry SDK to throw. `reportSilentFallback` swallows the error per `cq-silent-fallback-must-mirror-to-sentry`'s try/catch contract; pino log is the durable signal. Test asserts no propagated exception. | Unit | ME8 |
| TS13 | RLS isolation: user A's audit-log export endpoint returns ZERO of user B's rows. Test runs with two seeded users and exercises the JSONL streaming endpoint. | Integration | FR5 RLS + cross-tenant audit leak |
| TS14 | First-charge SCA via Stripe-hosted 3DS in the existing Checkout flow — Stripe drives the SCA ceremony; Soleur surfaces the success/failure as part of the `add()` response. PSD2 SCA Art. 97 floor satisfied without WebAuthn (DHH + Code-Simplicity review). WebAuthn step-up deferred. | Integration (mocked Stripe 3DS) | PSD2 SCA Art. 97 floor (Best-practices §1) |
| TS15 | CLI fallback under sandbox: when the `stripe` subprocess is invoked, `bash-sandbox.ts` patterns reject any command containing `$STRIPE_*` direct references; subprocess `env` is the explicit allowlist plus `STRIPE_CONNECT_TOKEN` injected via `serviceTokens`. | Unit | TR15 + agent-env CWE-526 |
| TS16 | RLS append-only invariant: attempt UPDATE/DELETE against `vendor_actions_audit` from a non-service-role connection — must return `0 rows affected` per RLS. Postgres WAL + RLS is the v1 tamper-evidence floor; hash-chain TS deferred to follow-on issue. | Unit | TR9 append-only RLS |
| TS17 | ops-provisioner Playwright fallback: feature-flagged path. With `stripe-projects-cloudflare-us=ON` and Stripe Projects responding healthy, ops-provisioner CF branch invokes the new tier. With flag OFF, falls through to existing Playwright path. | Unit | FR8 |

## Implementation Phases

### Phase 0: Spike (Days 1-2)

Goal: resolve the 6 unanswered Stripe Projects research items before module-level work.

1. Install `stripe` ≥ 1.40.0 + `stripe plugin install projects` in a sandbox container; capture pinned versions for the workspace Docker image.
2. Run `stripe projects init`, `stripe projects catalog --json`, `stripe projects add cloudflare/...` against a Stripe sandbox account; capture exit codes, stdout shapes, and any side-effect files (`.projects/`, `~/.config/stripe/`).
3. Test `Idempotency-Key` HTTP header behavior on retry (Research §3).
4. Test `--json` output stability across `stripe projects --version` bumps.
5. Test cold-signup email override mechanisms (env vars, CLI flags) — confirm Stripe-email = CF-email is a hard constraint (Research §5).
6. Test revoke cascade: does `stripe projects remove cloudflare` delete the auto-provisioned CF account, or just unlink? (Research §11.)
7. Test webhook surface: register a wildcard Stripe webhook, run end-to-end, capture event types (Research §7-8).
8. Test the OpenRouter integration as a comparable provider (it has more documented surface) — informs whether Stripe Projects exposes a Connect-OAuth flow for headless servers.
9. Write spike report to `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md`.
10. Run `/soleur:architecture create "Adopt Stripe Projects protocol for Cloudflare vendor cold-signup"` to capture the load-bearing architectural decisions (CLI vs REST primary, single-executor cloud-only, audit-log retention, sandbox model).
11. Update spec.md to reflect spike outputs; update this plan's Research Reconciliation table if any item resolves differently.
12. Commit: `docs: spike report + ADR for stripe-projects integration`.

### Phase 1: Foundations (Days 3-4)

1. Migration `apps/web-platform/supabase/migrations/035_vendor_actions_audit.sql`: create `vendor_actions_audit` table with append-only INSERT-only RLS, indexed `(user_id, created_at)`, `protocol` enum (`stripe-projects`, `playwright`, `mcp-tier`), `protocol_state` enum (`pending`, `consent_shown`, `approved`, `executing`, `succeeded`, `failed`, `email_mismatch_blocked`, `revoked`, `orphaned`). Columns: `id`, `user_id` (FK), `protocol`, `protocol_state`, `prompt_hash`, `encrypted_prompt` (byok), `encrypted_iv`, `encrypted_tag`, `tool_call_json` (jsonb), `idempotency_key`, `stripe_project_id`, `cf_account_email`, `cf_account_id`, `provider`, `plan`, `amount_cents`, `currency`, `cap_cents` (snapshot at consent), `consent_token_id`, `created_at`. Reuse migration 030's RLS shape. Per `cq-pg-security-definer-search-path-pin-pg-temp`, any `SECURITY DEFINER` helper pins `SET search_path = public, pg_temp`. **No hash-chain in v1** — Postgres WAL + INSERT-only RLS + R2-archived backups give the v1 tamper-evidence floor; hash-chain deferred to follow-on issue.
2. Migration `036_processed_stripe_events_scope.sql`: add `scope` column to `processed_stripe_events` (default `'webhook-inbound'`). Reuse the existing dedup-insert-first idempotency pattern for outbound Stripe Projects calls under `scope = 'stripe-projects-outbound'`. Single source of truth for inbound + outbound idempotency. **Drops the previously-planned new `vendor_actions_idempotency` table** per Code-Simplicity reuse opportunity.
3. Migration `037_stripe_connect_tokens.sql`: per-user encrypted Stripe Connect refresh-token storage. byok-encrypted columns (encrypted, iv, tag) following `users.byok_*` shape. (Kept — Stripe Connect is legally required per Best-practices §3.)
4. Extend `apps/web-platform/lib/feature-flags/server.ts` with `getFlagForUser(name, ctx)` per Functional-discovery §Reuse 1. Add `stripe-projects-cloudflare-us` flag definition with US billing-country predicate. Tests in `apps/web-platform/test/feature-flags.test.ts`.
5. Add `/api/stripe-projects/billing-country` Server Action that queries the user's Stripe customer billing country and caches per-session.
6. Wire `reportSilentFallback` import sites for the upcoming module.

### Phase 2: Stripe Connect OAuth (Days 5-6)

1. Implement `/api/stripe-projects/oauth/start` (POST): generates `state` (CSRF), PKCE pair, returns OAuth URL. Honors `validateOrigin` per existing route convention.
2. Implement `/api/stripe-projects/oauth/callback` (GET): exchanges code for `access_token` + `refresh_token`, encrypts via `byok.encryptKey(refresh_token, userId)`, stores in `stripe_connect_tokens`. Refresh token has 1-year TTL per Stripe docs. **Note** (Kieran): per-user HKDF on a server-issued OAuth refresh token is functional but conceptually atypical (server-side secret bound to cloud server's Connect application, not user-supplied material). v1 accepts this pattern; if a follow-on user-impact review demands envelope encryption (KMS DEK + per-user AAD), the migration is straightforward (re-encrypt in-place via a one-shot migration script).
3. Implement refresh-token rotation: `apps/web-platform/server/stripe-projects/oauth.ts` exports `getValidConnectToken(userId)` that decrypts, refreshes if `<1h to expiry`, re-encrypts. Sentry-mirrors any refresh failure.
4. Implement `/api/stripe-projects/oauth/revoke` (POST): explicit revoke. Cascades to `vendor_actions_audit` (mark all active rows `protocol_state: 'revoked'`).
5. **WebAuthn step-up DROPPED for v1.** Stripe-hosted 3DS in the existing Checkout flow already satisfies PSD2 SCA Art. 97 for the funded action. Layering a second SCA factor is duplicate and over-built for 0 paying users. WebAuthn step-up tracked as a separate follow-on issue, triggered when (a) auditor explicitly requires it, or (b) cap-raise UX needs a step-up surface that 3DS can't cover.
6. TDD scenarios: TS8.

### Phase 3: Shared core module (Days 7-9)

1. Scaffold `apps/web-platform/server/stripe-projects/` with: `index.ts` (public API + inlined idempotency + email-match + errors), `subprocess.ts` (CLI wrapper under `bash-sandbox`), `audit.ts` (`vendor_actions_audit` writer). Standalone `email-match.ts` / `idempotency.ts` / `errors.ts` modules are NOT created in v1 — inlined into `index.ts` per Code-Simplicity unanimous "module-ize when count exceeds 3 consumers" guideline. Split out when `index.ts` exceeds 300 lines.
2. `index.ts` exports `init`, `catalog`, `add(provider, opts, ctx)`, `revoke(provider, ctx)`. `ctx: { userId, capCents, consentTokenId, prompt }`. (Note: `idempotencyKey` is derived inside `add()` per step 4, not passed in.)
3. `subprocess.ts`: invokes `stripe projects ...` via `execFile` with explicit env (Stripe Connect token injected as `STRIPE_API_KEY` override), cwd in a per-invocation tempdir, output piped through `| head -n 500` per `hr-never-run-commands-with-unbounded-output`. JSON output only (`--json` flag). **Note**: a verbose `stripe projects` error may exceed 500 lines; if `head -n 500` truncates the error tail, capture full stderr to a Sentry breadcrumb (not the response body) so debugging never relies on the truncated output.
4. **Idempotency (inlined in `index.ts`)**: key = `sha256(userId || provider || resource || plan_id || day_bucket)` — where `day_bucket = floor(now() / 24h)`. **`consent_token_id` is NOT in the hash** (Kieran #1 fix): including it would mean a retry after consent-token TTL expiry produces a different key → double-provision risk on the orphan-class failure (CF-side write succeeded, audit-row write failed). Insert-first dedup pattern reuses `processed_stripe_events` table with `scope = 'stripe-projects-outbound'`. The `consent_token_id` IS recorded on the audit-log row separately for traceability — it just doesn't gate idempotency.
5. **Email-match assertion (inlined in `index.ts`, post-call)** — Kieran #2 fix: assert THREE invariants, not just email equality:
   - `cfAccount.email == user.stripe_email` (existing)
   - `cfAccount.id == addResponse.account_id` (NEW — defends against orphan accounts from prior failed signups with coincidentally-matching email)
   - `cfAccount.created_at < 60s ago` (NEW — defends against CF cache-hit on pre-Stripe-Projects email during verification window)
   On any mismatch: fail closed — do NOT surface the token, do NOT persist via byok, write Sentry incident, mark audit row `email_mismatch_blocked`, surface user message "We blocked this provisioning for security: Cloudflare returned an account that doesn't match your Stripe email. Support has been paged. No charge has been made." with ticket ID. **Inline orphan-detection** (replaces deferred reconciliation cron): if the email-match fails AFTER Stripe Projects reported `add` success, write a `protocol_state: 'orphaned'` row + Sentry priority-1 incident, paging support directly. No separate cron.
6. `audit.ts`: append-only entry write. Encrypts the user prompt via `byok.encryptKey(prompt, userId)` before persisting. **No hash-chain in v1** — straight `INSERT` under append-only RLS; `created_at` is the chronology anchor.
7. Add `stripe-projects` provider entry to `apps/web-platform/server/providers.ts` with `envVar: STRIPE_API_KEY` so the subprocess invocation passes the `ALLOWED_SERVICE_ENV_VARS` check in `agent-env.ts`.
8. TDD scenarios: TS1, TS2 (with three-invariant assertion), TS3 (with day-bucket key), TS5, TS6, TS9 (inline orphan-detection variant), TS12, TS13, TS15.

### Phase 4: Consent surfaces (Days 10-12)

1. `apps/web-platform/components/chat/stripe-projects-consent-modal.tsx`: renders the per-action consent modal. Props: `provider`, `plan`, `recurringAmountCents`, `oneTimeChargeCents`, `currency`, `fundingSourceLast4`, `rationale` (free-text from agent reasoning), `reversalWindow` (string). Three buttons: Approve (kicks off `add()` server-side; first-charge SCA happens inside Stripe Checkout/3DS flow, not a separate WebAuthn ceremony), Edit (returns to chat with a re-prompt), Cancel (audit-logs cancellation with TTL release). Copy reviewed against Best-practices §1 minimum-acceptable-floor.
2. `apps/web-platform/components/chat/stripe-projects-success-card.tsx`: renders the post-success card with provider/plan/amount/CF account email/audit-log link. Failure cases use the existing chat error surface — no separate `failure-card.tsx` per Code-Simplicity (one component is enough).
3. `/api/stripe-projects/intent` (POST): accepts CLI-plugin intent payloads (`{ provider, resource, plan, rationale }`). Validates Soleur-issued PAT. Returns `{ consentUrl, statusEndpoint }` — short-lived signed URL the user opens in browser; CLI **polls** the status endpoint (no WebSocket — simpler, sufficient for v1, Code-Simplicity & DHH agreement).
4. `apps/web-platform/app/consent/[consentTokenId]/page.tsx`: renders the modal in a standalone page for the CLI-plugin path. Same modal component as cloud chat. **Note**: per Kieran #3 fix, this page lives at `app/consent/...` NOT `app/api/consent/...` — `app/api/**` is reserved for HTTP route handlers per `cq-nextjs-route-files-http-only-exports`.
5. `/api/stripe-projects/consent/[consentTokenId]/decision` (POST): records Approve/Cancel; if Approve, kicks off `add()` server-side; updates a row the CLI status endpoint reads.
6. `/api/stripe-projects/consent/[consentTokenId]/status` (GET): returns the current state for CLI polling (`pending | approved | executing | succeeded | failed`).
7. `/api/stripe-projects/audit-log/export` (GET): synchronous JSONL streaming with a hard 10MB / 10k-row cap. Rate-limit: 10 req/hour per user via existing rate-limit middleware. **CSV format and async-job pattern DROPPED for v1** — deferred to follow-on issue triggered when first user hits the cap. Above the cap, returns 413 with a `Retry-Later` recommendation pointing at the deferred follow-on.
8. TDD scenarios: TS4, TS7, TS9 (UX side), TS13.

### Phase 5: ops-provisioner integration (Day 14)

1. Edit `plugins/soleur/agents/operations/ops-provisioner.md`: insert a "Tier 0: Stripe Projects" section above "Use Playwright MCP tools" — checks `stripe projects catalog --json` for the target vendor; if listed, delegates to `service-automator` Stripe Projects path; else proceeds with Playwright as today. Add to Sharp Edges: "Stripe Projects path requires the cloud server's Stripe Connect OAuth grant; CLI plugin path round-trips the cloud."
2. Edit `plugins/soleur/agents/operations/service-automator.md`: insert "Stripe Projects" tier ABOVE "MCP" in the Tier Selection table. Add a new Service Playbook "Cloudflare (Stripe Projects Tier)" describing the cold-signup path. Update existing "Cloudflare (MCP Tier)" playbook to clarify it's for management of an existing CF account, not cold signup.
3. Edit `plugins/soleur/agents/operations/references/service-deep-links.md`: replace the manual `dash.cloudflare.com/sign-up` deep link with a Stripe Projects-first instruction; keep the dashboard URL as fallback.
4. Add a 2-week feature flag `ops-provisioner-cloudflare-stripe-projects` for the rollback window. After the window expires, remove the Playwright Cloudflare branch in a follow-up PR.
5. TDD scenarios: TS17.

### Phase 6: CLI plugin slash commands (Day 15)

1. Create `plugins/soleur/skills/vendor-signup/SKILL.md` — implements `/soleur:vendor-signup <provider>`, `/soleur:vendor-signup config`, `/soleur:vendor-signup revoke <provider>`. The skill's body:
   - Calls `/api/stripe-projects/intent` with the user's Soleur PAT.
   - Receives `consentUrl` + `websocketChannel`.
   - Opens consent URL via `xdg-open` (Linux) / `open` (mac) / browser (Windows).
   - Subscribes to WS channel; renders status updates to terminal.
   - On completion, fetches the audit-log row and renders a structured success/failure block.
   - Exit code: 0 on success, 4 on geo-reject, 5 on cap-would-exceed, 6 on email-mismatch, 7 on contract-drift, 1 on other failures.
2. Create `plugins/soleur/skills/audit-log/SKILL.md` — implements `/soleur:audit-log export`, `/soleur:audit-log show [--last N]`. Calls the cloud export endpoint.
3. Update `plugins/soleur/.claude-plugin/plugin.json` description fields if needed (no version bump per `wg-never-bump-version-files-in-feature`).
4. TDD scenarios: TS4 (CLI side), TS7 (CLI exit code), TS10.

### Phase 7: Marketing surfaces + launch post (Days 16-17, parallel with Phase 8)

1. Create `plugins/soleur/docs/pages/integrations/stripe-projects.njk` — landing page describing the integration, the per-action consent UX, the cap model, the US-only beta status. Inline critical CSS per `cq-eleventy-critical-css-screenshot-gate`. Pass `screenshot-gate.mjs`.
2. Update `plugins/soleur/docs/pages/agents.njk` (or equivalent) with a Stripe Projects badge + ops-provisioner playbook reference.
3. Update `plugins/soleur/docs/pages/pricing/index.njk` with the $25 default cap explainer.
4. Update `plugins/soleur/docs/_data/site.json` and `llms.txt` with the new integration.
5. Update homepage hero in `plugins/soleur/docs/_includes/base.njk` with a 30-day "Now on Stripe Projects" badge.
6. Draft anchor blog post `plugins/soleur/docs/pages/blog/2026-05-XX-stripe-projects-launch.njk`. Title: "We deleted our Playwright signup flow the day Cloudflare shipped Stripe Projects." Run through the `copywriter` agent for brand voice.
7. Wire content distribution to `social-distribute` skill: blog → HN → X → LinkedIn → dev.to within 14-day window.

### Phase 8: Legal artifacts (Days 16-18, parallel with Phase 7)

1. Update `docs/legal/terms-and-conditions.md` with the agent-mandate addendum: Stripe Projects scope, beta-deprecation right-to-suspend with pro-rata refund, spend-cap liability, beta force-majeure clause covering "third-party protocol deprecation," chargeback playbook for agent-initiated disputes.
2. Update `docs/legal/privacy-policy.md` with the new "Agent-Initiated Third-Party Subscriptions" section: Stripe Projects + Cloudflare as separate processors (not sub-processors of each other). Legal basis: contract performance + explicit consent for agent mandate. Audit-log retention disclosed (6 years tiered).
3. Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` with the new processing-activity entry.
4. Update `docs/legal/acceptable-use-policy.md` with a section covering agent-initiated provisioning prohibitions.
5. Update `compliance-posture.md` Vendor DPA table with a new "Stripe Projects (provider role)" row separate from existing Stripe billing relationship.
6. Defer DPIA + GDPR Policy update to the EU-rollout follow-on issue (open new issue `feat-stripe-projects-eu-rollout`, milestone Phase 4 follow-on, link from the spec).
7. Run `legal-compliance-auditor` agent on the updated docs.

### Phase 9: CI + observability (Day 17)

1. Create `.github/workflows/scheduled-stripe-projects-contract.yml` — cron-triggered (nightly 02:00 UTC) wrapper around `claude-code-action` that runs `stripe projects catalog --json | jq '.cloudflare' | diff -u - .github/fixtures/stripe-projects-catalog-cloudflare-baseline.json`; fails closed on drift; posts `stripe-projects-protocol-drift` issue. Reuse the `scheduled-cf-token-expiry-check.yml` skeleton. **Vendor-specific fixture** (`jq '.cloudflare'`) — full-catalog diff would fire daily as Stripe adds providers (Sharp Edges).
2. Add the auto-disable hook: on contract-test failure, the workflow flips `stripe-projects-cloudflare-us` to OFF via the feature-flag admin API.
3. **Hourly reconciliation cron DROPPED for v1.** Inline orphan-detection lives in Phase 3 step 5's `add()` catch block (Sentry priority-1 incident on email-match-fail-after-CF-write-success). Hourly cron is deferred to a follow-on issue, triggered when the first orphan-class incident reveals a class of failures that inline detection can't cover.
4. **No `vercel.json` cron edit needed** (no cron file in v1).
5. TDD scenarios: TS11.

### Phase 10: Pre-ship + smoke test (Day 20-21)

1. Run full E2E against Stripe sandbox + Cloudflare staging.
2. Run `gh issue list --label code-review --state open` overlap check before final review per `1.7.5` (already checked at plan time; re-run before merge to catch new arrivals).
3. Run `/soleur:preflight` (Check 6 will validate `## User-Brand Impact` is non-empty + threshold valid).
4. Run `/soleur:review` — 9-agent multi-review including `user-impact-reviewer`, `security-sentinel`, `architecture-strategist`, `data-integrity-guardian`, `data-migration-expert`, `deployment-verification-agent`, `code-quality-analyst`, `dhh-rails-reviewer`, `kieran-rails-reviewer`.
5. Resolve all review findings fix-inline per `rf-review-finding-default-fix-inline`.
6. Run `/soleur:qa` for functional QA before merge.
7. Run `/soleur:compound` to capture session learnings.
8. Run `/soleur:ship` for the lifecycle checklist + semver label (`semver:minor` for the new skill / new user-facing capability).

## Files to Create

```text
apps/web-platform/server/stripe-projects/index.ts
apps/web-platform/server/stripe-projects/subprocess.ts
apps/web-platform/server/stripe-projects/audit.ts
apps/web-platform/server/stripe-projects/oauth.ts
apps/web-platform/app/api/stripe-projects/oauth/start/route.ts
apps/web-platform/app/api/stripe-projects/oauth/callback/route.ts
apps/web-platform/app/api/stripe-projects/oauth/revoke/route.ts
apps/web-platform/app/api/stripe-projects/intent/route.ts
apps/web-platform/app/api/stripe-projects/consent/[consentTokenId]/decision/route.ts
apps/web-platform/app/api/stripe-projects/consent/[consentTokenId]/status/route.ts
apps/web-platform/app/api/stripe-projects/audit-log/export/route.ts
apps/web-platform/app/api/stripe-projects/billing-country/route.ts
apps/web-platform/app/consent/[consentTokenId]/page.tsx
apps/web-platform/components/chat/stripe-projects-consent-modal.tsx
apps/web-platform/components/chat/stripe-projects-success-card.tsx
apps/web-platform/supabase/migrations/035_vendor_actions_audit.sql
apps/web-platform/supabase/migrations/036_processed_stripe_events_scope.sql
apps/web-platform/supabase/migrations/037_stripe_connect_tokens.sql
apps/web-platform/test/stripe-projects-core.test.ts
apps/web-platform/test/stripe-projects-email-match.test.ts
apps/web-platform/test/stripe-projects-idempotency.test.ts
apps/web-platform/test/stripe-projects-rls.test.ts
apps/web-platform/test/stripe-projects-cap.test.ts
apps/web-platform/test/stripe-projects-geo.test.ts
apps/web-platform/test/feature-flags-getFlagForUser.test.ts
apps/web-platform/test/stripe-projects-consent-modal.test.tsx
apps/web-platform/test/stripe-projects-e2e.test.ts
apps/web-platform/test/stripe-projects-ops-provisioner.test.ts
plugins/soleur/skills/vendor-signup/SKILL.md
plugins/soleur/skills/audit-log/SKILL.md
plugins/soleur/docs/pages/integrations/stripe-projects.njk
plugins/soleur/docs/pages/blog/2026-05-XX-stripe-projects-launch.njk
.github/workflows/scheduled-stripe-projects-contract.yml
.github/fixtures/stripe-projects-catalog-cloudflare-baseline.json
knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md
knowledge-base/architecture/decisions/ADR-XXXX-stripe-projects-protocol-adoption.md
knowledge-base/engineering/ops/runbooks/stripe-projects-incident-response.md
docs/legal/terms-and-conditions.md (additions only)
docs/legal/privacy-policy.md (additions only)
docs/legal/acceptable-use-policy.md (additions only)
plugins/soleur/docs/pages/legal/data-protection-disclosure.md (additions only)
knowledge-base/legal/compliance-posture.md (row addition)
```

**Cuts vs initial draft (post-review):** removed 13 files — `idempotency.ts`, `email-match.ts`, `errors.ts`, `billing-country.ts` (all inlined into `index.ts`), `cron/vendor-actions-reconcile.ts` (orphan detection inlined in `add()` catch), `webauthn/challenge`+`webauthn/verify` route handlers, migration `038_vendor_webauthn_attestations.sql`, `stripe-projects-failure-card.tsx`, `stripe-projects-webauthn.test.ts`, `vendor-actions-audit-hash-chain.test.ts`, `audit-log-export-button.tsx`, `migration 036` renamed from `vendor_actions_idempotency` to `processed_stripe_events_scope` (reuse). Net: 50 → 38 files. **Added** `app/consent/[id]/page.tsx` (Kieran #3 — moved out of `/api/`), `consent/[id]/status/route.ts` (CLI polling endpoint, replaces WebSocket), and `runbooks/stripe-projects-incident-response.md` (Kieran completeness gap — single-user-incident threshold without a runbook is a workflow gap).

## Files to Edit

```text
apps/web-platform/lib/feature-flags/server.ts
apps/web-platform/server/agent-env.ts
apps/web-platform/server/observability.ts (no edit; reference only)
apps/web-platform/server/providers.ts
apps/web-platform/lib/stripe.ts (no edit; reuse via getStripe())
apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx (add Stripe Projects connection card)
plugins/soleur/agents/operations/ops-provisioner.md
plugins/soleur/agents/operations/service-automator.md
plugins/soleur/agents/operations/references/service-deep-links.md
plugins/soleur/docs/pages/agents.njk
plugins/soleur/docs/pages/pricing/index.njk
plugins/soleur/docs/_data/site.json
plugins/soleur/docs/_includes/base.njk
plugins/soleur/docs/llms.txt
knowledge-base/operations/expenses.md (Spend Cap column + user-side section)
knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spec.md (Phase 0 spike updates)
knowledge-base/product/roadmap.md (Phase 4 entry for the consumer-side feature, linked to #3106)
apps/web-platform/server/agent-runner-tools.ts (register stripe-projects-add as agent-callable tool)
apps/web-platform/app/(dashboard)/layout.tsx (sidebar entry for Connected Services / Stripe Projects)
package.json (+ @stripe/connect-js for browser OAuth; no @simplewebauthn/server needed in v1)
```

Glob verification (per `hr-when-a-plan-specifies-relative-paths-e-g`): each path above mapped to a real codebase location during plan-time research; the new paths are net-new files (no glob match required).

## Open Code-Review Overlap

None — 29 open `code-review` issues exist but none mention any file in the `## Files to Edit` or `## Files to Create` lists (verified via `gh issue list --label code-review --state open` + per-path jq grep on 2026-05-03).

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Stripe Projects has no REST API; CLI is the only entry point | HIGH | Phase 0 spike confirms; if true, all execution paths route through `bash-sandbox`-wrapped subprocess; module API stays stable so a future REST surface swaps in transparently. |
| Beta protocol breaking change mid-sprint | HIGH | Pin `stripe` ≥ 1.40.0 + `projects` plugin version in workspace Docker. Nightly contract test (TR7) detects drift. Auto-disable feature flag on detection (TR17). |
| Orphan CF account if signup partially fails | HIGH | Inline orphan-detection in `add()` catch (Phase 3.7) — writes `protocol_state: 'orphaned'` row + Sentry P1 incident, paging support directly. User-facing "provisioning held" card on audit-log write failure. Hourly reconciliation cron deferred to follow-on (D5), triggered when first orphan incident reveals a class inline detection can't cover. Stripe Projects research §11 spike answer determines whether full deletion is possible. |
| Cross-tenant credential bleed | HIGH (single-user incident) | Email-match assertion (fails closed); idempotency keyed on `(userId, ...)`; RLS on every read; byok per-user key derivation; `bash-sandbox` for subprocess; Sentry mirror on every catch. |
| CLI's local `~/.config/stripe/` used for funded actions | HIGH (legal) | Architecturally enforced: cloud server is the only executor. CLI plugin POSTs intent only. Best-practices §3. |
| Cold-signup email mismatch (user wanted personal email, got Stripe email) | MEDIUM | Surface clearly in consent modal copy: "Cloudflare will use your Stripe email `<email>`." Add FAQ entry. |
| Cap raise mid-flight race | LOW | Cap value captured at consent-modal-render time; locked into audit-log row. |
| Stripe Connect refresh-token expires (1 year) | LOW (manual monitor v1) | Operator monitors `stripe_connect_tokens.refreshed_at` and manually re-prompts users at 11-month mark. Automated re-prompt cron deferred to follow-on issue, triggered when first token expires (~Q2 2027). |
| Audit-log JSONL export streaming a different user's rows | HIGH | RLS test TS13. CI gate: any change to the export endpoint requires both unit + integration tests passing. |
| Existing feature-flags module is global-only | MEDIUM | Extend rather than create parallel system (Functional-discovery §Reuse 1). |
| Sentry SDK partially shimmed | LOW | `reportSilentFallback` already wraps Sentry calls in try/catch; pino is the durable signal. |
| Hetzner billing pivots to Stripe during sprint | LOW | If Hetzner posture changes, defer the change to a follow-on issue per spec TR14. Out of scope for this plan. |
| Provider-side (#3107) is invite-only via `provider-request@stripe.com` | LOW (deferred) | Update #3107 with this finding; re-evaluation triggers (a) ≥3 paying users, (b) external demand, (c) Stripe Projects out of beta, (d) consumer-side stable for ≥3 months, (e) Stripe accepts our provider intake email. |

## Sharp Edges

- The `STRIPE_API_KEY` env var override pattern for `stripe projects` subprocess invocation must NOT inherit from the operator's shell — use `agent-env.ts`'s explicit allowlist + serviceTokens injection. Add `stripe-projects` provider entry to `PROVIDER_CONFIG` so the env var passes the `ALLOWED_SERVICE_ENV_VARS` check.
- The `vendor_actions_audit` table is generic across protocols; do NOT name new audit columns with `stripe_` prefix unless they are Stripe-specific. Future protocols (`playwright`, `mcp-tier`, `provider-side`) will share the table.
- `service-deep-links.md` has a `provider routing aliases` mechanism that the new tier extends — verify the alias table in `apps/web-platform/server/providers.ts` does not collide with `stripe-projects` (it does not as of 2026-05-03; verified during plan-time research).
- `stripe projects catalog` returns 41 providers (Stripe Projects research §10). The contract-test fixture must be vendor-specific (`stripe projects catalog --json | jq '.cloudflare'`), not the full catalog — Stripe will add providers without notice and a full-catalog diff will fire daily.
- The `consent_token_id` must be cryptographically signed (HMAC-SHA256 with a server-side secret) so a malicious CLI cannot forge a consent approval. The signing secret is a separate Doppler value (`STRIPE_PROJECTS_CONSENT_TOKEN_SECRET`).
- `webhooks/stripe/route.ts` already exists; the new flow doesn't need a new webhook surface unless the Phase 0 spike confirms `project.*` events exist (Stripe Projects research §8 — likely none).
- New skill `vendor-signup` token-budget check: run `bun test plugins/soleur/test/components.test.ts` at plan-write time; description ≤ `1800 - current_total` words. The new SKILL.md description ≤ 30 words to keep within `cq-when-a-plan-adds-a-new-skill-OR-a-new`.
- Migration 035 must NOT use `CREATE INDEX CONCURRENTLY` (Supabase wraps each migration in a transaction; this fails SQLSTATE 25001 — see learning `2026-04-18-supabase-migration-concurrently-forbidden`).
- App Router route files under `app/api/**` may export only HTTP handlers per `cq-nextjs-route-files-http-only-exports`. The standalone CLI consent page (`app/consent/[consentTokenId]/page.tsx`) is correctly OUTSIDE `app/api/` per Kieran review fix #3.
- `consent_token_id` URL is short-lived (5min TTL); the CLI plugin must surface an error if the user takes longer to click Approve. Document this in the `vendor-signup` skill body.
- **Idempotency hash MUST NOT include `consent_token_id`** (Kieran review fix #1) — including it produces double-provisioning on retry after consent-token TTL expiry. Use `(userId, provider, resource, plan_id, day_bucket)` only.
- **Email-match assertion must check THREE invariants** (Kieran review fix #2): email equality, `account.id` matches the freshly-returned `add` response, and `account.created_at < 60s ago`. Email-only is insufficient against orphan-account attacks.
- Stripe Connect refresh-token TTL is 1 year. Operator manually monitors and re-prompts at 11 months in v1; automated re-prompt cron is deferred. Set a calendar reminder at first user OAuth + 11 months.

## Open Questions

Carried forward from brainstorm + new from spec-flow + research:

1. **REST surface confirmation.** Phase 0 spike must answer: does Stripe Projects expose a documented REST surface? If yes, plan Phase 3 swaps the implementation. If no, CLI subprocess is the durable path.
2. **OAuth scope granularity.** Per-provider scope or account-wide? Affects whether each new vendor (post-v1) re-prompts.
3. **CF token lifetime.** Long-lived API token (assumed) or short-lived with refresh? Determines re-encryption cadence.
4. **CF account email source.** Confirmed: Stripe-attested email, no override (Research §5). Surfaced in consent copy.
5. **Cap-exceeded webhook.** Does Stripe Projects emit one? If no, poll Cloudflare Budget Alerts API hourly.
6. **DPIA self-assess vs external.** Out of scope for US v1; tracked under EU-rollout follow-on issue.
7. **Audit-log retention.** Confirmed: 6 years tiered (Best-practices §2).
8. **Hetzner long-term posture.** Confirmed: stays Playwright/Terraform indefinitely (COO + ops-research). Out of scope.
9. **Plan-selection UX.** spec-flow FG3: how does the user (or agent) pick the CF plan? Default to free-tier; agent reasoning surfaces the "why this plan" rationale to the modal.
10. **CF email-verification race.** spec-flow FG5: token works for API even before email verified, but dashboard locked. Consent modal copy notes "verify your email at the link Cloudflare sends to use the dashboard."
11. **Concurrent same-user lock.** spec-flow RC1: cross-entry-point distributed lock. Implemented via the `processed_stripe_events` (scope=`stripe-projects-outbound`) insert-first dedup pattern + a consent-token-id state row — `pending` rows TTL out at 5min; second attempt during pending-window returns `flow-pending-elsewhere`.
12. **Auto-disable feature flag on protocol drift.** Implemented via Phase 9 step 2.
13. **Reconciliation job for orphans.** v1 uses inline detection in `add()` catch (Phase 3.7) — Sentry P1 incident paging support directly. Hourly reconciliation cron deferred to follow-on (D5).
14. **Sentry-mirror fallback.** spec-flow ME8: Sentry call wrapped in try/catch already; pino is durable signal. Disk-buffered events are out of scope for v1.
15. **CLI plugin Stripe-account-mismatch.** Architecture pivot makes this moot — CLI plugin no longer uses local `stripe login` for funded actions.
16. **Idempotency `requested-resource` granularity.** Hash = `sha256(userId || provider || resource || plan_id || day_bucket)`. **`consent_token_id` is NOT in the hash** (Kieran review fix #1) — including it would double-provision on retry after consent-token TTL expiry on the orphan-class failure (CF write succeeded, audit row write failed). `consent_token_id` is recorded on the audit row for traceability but does not gate idempotency.
17. **Email-mismatch user-facing message.** "We blocked this provisioning for security: Cloudflare returned an account that doesn't match your Stripe email. Support has been paged. No charge has been made." With ticket ID.
18. **ops-provisioner fallback consent re-prompt.** During the 2-week rollback window: if Stripe Projects fails mid-flight and Playwright fallback engages, surface a "switching to legacy flow — re-confirm?" modal. Different consent surface = different consent record.
19. **Anchor launch post timing if window slips.** If sprint slips past 2026-05-14, CMO drafts a retroactive "we shipped Stripe Projects" post without first-mover framing. Sprint-time check at end of Phase 6.
20. **Hard-cap-on-cap-raise UX.** spec-flow FG8: cap raises are high-risk actions. v1 routes cap raises through Stripe Checkout (3DS where applicable) since the cap is enforced server-side at consent-render time. WebAuthn step-up for cap raises is deferred to follow-on D1, triggered when (a) auditor explicitly requires it, or (b) cap-raise UX surfaces a gap 3DS can't cover.
