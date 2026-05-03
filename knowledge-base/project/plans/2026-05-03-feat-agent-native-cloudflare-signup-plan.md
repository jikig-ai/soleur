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
deepen_completed: true
deepen_date: 2026-05-03
date: 2026-05-03
---

# Plan: Agent-Native Cloudflare Signup via Stripe Projects (Consumer Side)

## Sprint Re-Evaluation — OPEN FOR USER DECISION

The deepen-plan pass (8 parallel agents) invalidated two v1 substrate choices and elevated three deferrals into v1 blockers. The revised surface area is ~1.5–2x the post-review plan. **Operator must confirm one of:**

- **(a) Bundle all-at-once, accept timeline 3w → 4–5w**, slip the 14-day first-mover window. Land the right plan; ship the launch post retroactively.
- **(b) Phased: ship US-only Stripe Projects MVP behind feature flag** with reduced surface (Stripe Secret Store + Shared Payment Tokens MUST land in v1; the polish cuts — async-progress UX, Redis status cache, mandate-ceiling re-consent surface — defer to a fast-follow PR), hit the 14-day launch post window. Risk: launch post claims a capability that's still being completed.
- **(c) Hold the launch post**, write the plan correctly, ship in 4–5 weeks.

Until this is resolved, the phase day-numbers below assume (a). Pick (b) or (c) and the implementation phases retitle accordingly.

## Overview

Adopt Cloudflare's Stripe Projects protocol (https://blog.cloudflare.com/agents-stripe-projects/, open beta 2026-04-30) so a Soleur agent can subscribe a US-only user to Cloudflare in one programmatic step, replacing the deferred Playwright cold-signup path. Two entry points — cloud chat and CLI plugin — share a single executor in `apps/web-platform/server/vendor-actions/`. **Cloud server is the only authorized executor of the Stripe Projects subprocess** (Research Reconciliation §1, §2); the CLI plugin POSTs intent to the cloud, which renders the per-action consent modal in the browser, hands off to **Stripe Shared Payment Tokens** for SCA-compliant payment authorization (Research Reconciliation §8), then invokes the protocol.

Soleur-side default cap $25/mo per provider per user (raisable to Stripe's $100). Mandate ceiling captured separately at consent time so a vendor price change voids the MIT exemption and triggers re-consent (Research Reconciliation §10). All `add()` invocations are idempotent against a dedicated `vendor_actions_idempotency` table (NOT `processed_stripe_events` reuse — see Research Reconciliation §6); byok-encrypt **payment-result metadata** at rest (NOT the OAuth refresh token — that lives in **Stripe Secret Store**, Research Reconciliation §7); append to a generic `vendor_actions_audit` table with vendor-agnostic `vendor` column + `provider_metadata jsonb`; pass through a fail-closed three-invariant post-call email-match assertion to prevent cross-tenant attribution.

Modules re-layered into one-way deps `consent/` ← `vendor-actions/` ← `stripe-projects/` so the consent and audit substrates can be reused by sibling protocols (#3107 provider-side, future Playwright re-introduction, MCP-tier) without protocol-specific bleed.

ops-provisioner's Cloudflare cold-signup branch is gated behind a feature flag with a 2-week Playwright rollback. Anchor launch post sequencing depends on the Sprint Re-Evaluation outcome.

## Why

User-brand-critical (`single-user incident` threshold per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`). All four user-impact vectors apply: billing surprise, credential leak, cross-tenant attribution, PII. CPO sign-off is required at plan time before `/work`, and `user-impact-reviewer` is invoked at PR time per the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## User-Brand Impact

Carried forward from the brainstorm's `## User-Brand Impact` section + extended via deepen pass.

**If this lands broken, the user experiences:** an unauthorized `$X/mo` Cloudflare charge they did not approve, OR a Cloudflare API token leaked to logs/Sentry/audit-log read paths visible to other tenants, OR provisioning attributed to the wrong tenant (user A's intent triggers user B's CF account provisioning), OR a Stripe charge that committed without a Soleur-side audit row (the partial-orphan class — TS9b).

**If this leaks, the user's payment + auth credentials are exposed via:** (a) the Cloudflare API token returned by Stripe Projects logging to stdout via subprocess inheritance; (b) Stripe Secret Store decryption surfacing the OAuth refresh token before the email-match assertion; (c) the audit-log JSONL export endpoint streaming a different user's rows due to RLS misconfiguration; (d) the orphan-account class — Cloudflare auto-provisioned account left dangling with the user's Stripe email but no Soleur-side persistence (Research Reconciliation §3); (e) the `.projects/vault/` plaintext `.env` material that Stripe Projects writes by default (Research Reconciliation §4); (f) cross-tenant prompt content leakage if a system-prompt template references another user's resource (deepen Sec-4); (g) `STRIPE_API_KEY` token shape in unredacted Sentry breadcrumbs (deepen Sec-2).

**Brand-survival threshold:** `single-user incident`.

**Mandatory reviewers:** CPO sign-off at plan time (this gate); `user-impact-reviewer` at PR time. CLO concerns from brainstorm + deepen Best-practices §3 (PSD2/SCA + DRCF mandate-ceiling) are reflected in Risks & Mitigations, Phase 8 legal artifacts, and the Acceptance Criteria — CLO does not re-sign here per the lifecycle staging in `plugins/soleur/skills/plan/SKILL.md` Phase 2.6.

## Research Reconciliation — Spec vs. Codebase + External

The spec was written before research returned. The deepen pass added five further reconciliations (§6–§10). Implementation diverges from the spec on these points; the spec will be updated to match this plan during Phase 0.

| # | Spec/brainstorm/post-review claim | Reality | Plan response |
|---|----------------------|---------|---------------|
| 1 | TR1: "REST-first shared core ... falls back to the `stripe` CLI subprocess only when REST is unavailable" | No public REST API for `stripe projects add/init/catalog/revoke` exists as of 2026-05-03. Stripe Projects research §1. CLI is the only reliable surface. | Phase 0 spike resolves definitively. Default plan: CLI-subprocess primary, REST opportunistic. Module wraps the `stripe` binary via `execFile` under `bash-sandbox`. If spike confirms a REST surface, swap behind the same module interface. |
| 2 | Brainstorm #2: "CLI plugin uses local `stripe` CLI on PATH" for funded actions | Stripe's CLI-issued restricted keys cannot legitimately authorize user-funded actions on the user's behalf. Best-practices §3. | Cloud server is the only executor of `stripe projects add`. CLI plugin POSTs intent to `/api/vendor-actions/intent`, server returns short-lived signed consent URL, user authenticates via Stripe-hosted Shared Payment Token flow (§8), server invokes Stripe Projects via the cloud-bound substrate. |
| 3 | Spec FR4: "renders a 'new Cloudflare account provisioned' notice in the consent confirmation" | Cloudflare auto-provisions with the **Stripe-attested email** as the only documented option. No override. Stripe Projects research §5. | FR4 (revised): consent modal shows "Cloudflare will use your Stripe email `<email>` for the new account. To use a different email, set up a Cloudflare account manually first and revoke this consent." User must actively check an "I confirm" box (deepen UI-2 elevation: trust-breach severity HIGH, not MEDIUM). |
| 4 | Spec TR9: append-only audit log with no retention specified | UK contract limitation runs **6 years**; GDPR Art. 5(1)(c) rules out 10+. SOC 2 expects ≥1 year. Best-practices §2. | TR9 (revised): retention target 6 years total. v1 ships hot-only Postgres `vendor_actions_audit` with append-only history-events table (deepen Data-F1 fix: split into mutable `vendor_actions` head + INSERT-only `vendor_actions_audit_events` history; resolves the RLS-vs-state-machine contradiction). Tiered cold-tier deferred (#3112). Hash-chained tamper-evidence deferred (#3110); Postgres WAL + RLS is v1 floor. Audit substrate stores `prompt_hash + redacted_prompt` (deepen Sec-4: pre-encryption PII redactor strips email/UUID/account-id patterns). |
| 5 | Spec TR1 module name `apps/web-platform/server/stripe-projects/`; TR9 table name `stripe_projects_audit` | Provider-side companion (#3107) needs the same audit + intent shape; naming for one vendor invites a second table in 2 weeks. Functional-discovery §Risk 2. Architecture deepen F3: vendor identity buried in `tool_call_json` forces protocol branching at every read site. | Re-layered into 3 sub-modules with one-way deps (deepen DDD F1+F2, Arch F6): `apps/web-platform/server/consent/` ← `apps/web-platform/server/vendor-actions/` ← `apps/web-platform/server/stripe-projects/`. Audit table `vendor_actions_audit` with top-level `vendor text NOT NULL` indexed column (deepen Arch F3); `cf_account_email`/`cf_account_id`/`stripe_project_id` move into `provider_metadata jsonb`. RLS, indexing, export endpoint protocol-agnostic. |
| 6 | Post-review claim: reuse `processed_stripe_events.scope` for outbound idempotency | Inbound webhooks (immutable history, `event_id`-keyed) and outbound action dedup (synthesized hash, lease semantics) have orthogonal lifecycles, retention, RLS, writers (deepen DDD F4). Existing PK is `(event_id)` — outbound `sha256` hashes share namespace without enforcement; missing `response_json` column makes TS3's "returns cached response" claim fiction (deepen Data-F3). | **REVERSE the reuse.** Restore separate `vendor_actions_idempotency` table (migration 036). Schema: `(idempotency_key text PRIMARY KEY, user_id uuid, vendor text, provider_metadata jsonb, response_json jsonb, state text CHECK IN ('pending','succeeded','failed'), expires_at timestamptz, created_at timestamptz)`. 24h TTL via partial index. |
| 7 | Post-review claim: `byok.encryptKey(refresh_token, userId)` for Stripe Connect refresh tokens | Per-user HKDF on a server-issued secret defends the wrong threat model (deepen Sec-1, Best-practices §1). RFC 9700 + Google KMS docs + AWS multi-tenant pattern + Stripe's own Secret Store API all converge on envelope encryption. HKDF blocks autonomous server-side rotation (cron + `account.application.deauthorized` webhook have no user session). | Use **Stripe Secret Store API** (`docs.stripe.com/stripe-apps/store-secrets`) — natively typed for `oauth_refresh_token`, Stripe runs the KMS substrate. Migration 037 reduces to: `stripe_connect_tokens (user_id uuid PRIMARY KEY, secret_store_path text, expires_at timestamptz, refreshed_at timestamptz)`. NO byok columns. Encrypted-at-rest contract held by Stripe. |
| 8 | Post-review claim: Stripe-hosted 3DS in existing Checkout satisfies PSD2 SCA Art. 97 for agent-initiated charges | Best-practices §3 conclusive: agent triggering 3DS user passively dismisses is NOT valid SCA. Art. 97 requires the *payer's* knowledge + possession factors. Stripe's own agentic-commerce stack uses **Shared Payment Tokens** precisely because raw agent charges don't satisfy SCA. EBA Q&A 2018_4031 explicit on MIT vs SCA distinction. | Adopt **Stripe Shared Payment Tokens** (`docs.stripe.com/agentic-commerce/concepts/shared-payment-tokens`). User issues a token at consent time with per-token usage limits + agent ID + mandate ceiling. First charge against the token = SCA-authenticated by user (3DS user-tap-confirm). Subsequent charges within mandate = MIT exemption. New Phase 2.5 to integrate. |
| 9 | Post-review claim: 11-month manual operator monitoring of Stripe Connect refresh tokens; D6 deferred | Best-practices §2: proactive refresh at <50% TTL eliminates the failure class entirely. Race condition documented (Nango): two workers refreshing simultaneously → one gets `invalid_grant` → connection dies. Mid-session "seamless re-prompt" is impossible — Stripe Connect requires full-page redirect. | Move D6 INTO v1. Phase 9 ships proactive 6-month refresh cron + distributed lock per `connected_account_id` (Postgres `SELECT FOR UPDATE`). Subscribe to `account.application.deauthorized` webhook → mark connection dead. Mid-session `invalid_grant` = typed error → UI surfaces "Reconnect Stripe" CTA (no pretense of seamless). Close #3114 as "rolled into #3106 v1". |
| 10 | Brainstorm: $25/mo cap is sufficient consent boundary | DRCF: PSD2 MIT exemption voids on amount change. Best-practices §3: "mandate scope ceiling" is a MUST for agent-initiated charges. | Add `mandate_ceiling_cents` column to `vendor_actions_audit` (distinct from `cap_cents`). Modal explicit copy: "We'll re-confirm if Cloudflare ever changes this price." On Stripe webhook for plan/price change → invalidate idempotency, force re-consent. New Phase 3 step. |
| 11 | Spec TR2: `STRIPE_CONFIG_PATH=$HOME/.config/stripe enforced explicitly in agent-env.ts` | Reframed by §2: cloud server invokes against the cloud-bound Stripe Connect token, not per-user `~/.config/stripe/`. | `STRIPE_CONFIG_PATH` workspace isolation no longer needed for consumer-side. CLI plugin's local `~/.config/stripe/` used only for read-only catalog browsing. Funded operations always round-trip cloud. |

## Domain Review

**Domains relevant:** Marketing, Engineering, Operations, Product, Legal (carried forward from brainstorm `## Domain Assessments` + deepen pass).

### Marketing (CMO)

**Status:** reviewed (carry-forward)
**Assessment:** Sprint Re-Evaluation outcome determines launch-post timing. If (a) bundle slip → retroactive post; (b) phased → on-time post claiming flag-gated MVP; (c) hold → 4–5w late post no longer first-mover. Surfaces unchanged: net-new `/integrations/stripe-projects` (P0), `/agents/`, `/pricing`, `llms.txt`, homepage hero (P1-P2). Pricing communication: $25 cap + mandate ceiling as "agent-safe spending" feature.

### Engineering (CTO)

**Status:** reviewed (carry-forward + Reconciliation §1, §2, §6, §7, §8, §9 + deepen 8-agent pass)
**Assessment:** Architecture revised — cloud server is sole executor; CLI plugin intent-passing only. Token storage = Stripe Secret Store, not byok-HKDF. Payment authorization = Shared Payment Tokens, not direct 3DS dismiss-by-agent. Module re-layer into 3 contexts. Critical risks: cross-tenant credential bleed, beta protocol churn, Stripe Projects e2e latency UX cliff (Phase 0 spike to capture). Spike scope expanded to include cold-start performance + Stripe Secret Store + Shared Payment Tokens API verification.

### Operations (COO)

**Status:** reviewed (carry-forward)
**Assessment:** Cloudflare adopt now via Stripe Projects (top tier). Vercel/Supabase/Resend wait + dual-path. GitHub/Hetzner stay Playwright/Terraform. ops-provisioner.md and service-automator.md tier-order updates. Expense ledger gets `Spend Cap` + `Mandate Ceiling` columns + user-side visibility section.

### Legal (CLO)

**Status:** reviewed (carry-forward + deepen Best-practices §3)
**Assessment:** Materially safer than Playwright but does NOT replace the deferred agency-framework brainstorm. Stripe Shared Payment Tokens substantially de-risks the SCA + MIT posture (Stripe legally owns the SCA ceremony). Required artifacts before US v1 ship: ToS addendum, Privacy Policy update (Stripe Secret Store + Shared Payment Tokens disclosure), AUP update, audit-log schema + 6-year retention policy aligned with v1 hot-only capability, per-action consent UX legal sign-off, mandate-ceiling disclosure. EU rollout gated on DPIA + GDPR-trio updates. Stripe and Cloudflare are independent processors of the user.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer, copywriter (deferred to launch-post phase), cpo (carried forward from brainstorm)
**Skipped specialists:** ux-design-lead (Pencil MCP not invoked — deferred to start of `/work` Phase 4. The deepen pass surfaced 6 net-new agent-parity API surfaces and a granular state machine that materially expand what the wireframes need to cover; running them now would re-do them when Phase 4 begins).
**Pencil available:** N/A (skipped)

#### Findings

spec-flow-analyzer surfaced 23 spec gaps including 5 critical pre-freeze blockers; all addressed in FRs/TRs or Open Questions. Deepen agent-native parity review surfaced 6 additional surfaces (proposal payload echo, `last_user_interaction_at` heartbeat, structured error envelope, `/audit-log/query` agent tool, granular SCA state machine, `/abort` endpoint) — all folded into Phase 4 Acceptance Criteria.

**Brainstorm-recommended specialists:** copywriter (Phase 7 launch-post), business-validator (deferred), competitive-intelligence (out of scope for v1).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Phase 0 spike has answered Stripe Projects research items 1, 3, 5, 7, 8, 11 + deepen-added items: cold-start latency p50/p95/p99, Stripe Secret Store API for `oauth_refresh_token`, Shared Payment Tokens issuance + redemption flow, `account.application.deauthorized` webhook payload shape, race-condition behavior on concurrent token refresh; ADR landed via `/soleur:architecture create`; spec.md updated.
- [ ] `vendor_actions_audit` migration (035) created. **Two-table model** per Data-F1: mutable `vendor_actions` head row (owner-SELECT + service-role UPDATE allowed) + INSERT-only `vendor_actions_audit_events` history table (trigger-driven, append-only RLS). Top-level `vendor text NOT NULL` indexed; `provider_metadata jsonb`; `cap_cents`, `mandate_ceiling_cents`, `consent_token_id`, `prompt_hash`, `redacted_prompt` (NOT raw or encrypted-raw — pre-redacted at write time per Sec-4). **No FK on `user_id`** per Data-F2 (GDPR Art. 17 conflict). `anonymized_at timestamptz` column + documented anonymization SQL job.
- [ ] `vendor_actions_idempotency` migration (036) created — separate table per Reconciliation §6, NOT `processed_stripe_events.scope` reuse. Schema: `(idempotency_key text PK, user_id uuid, vendor text, provider_metadata jsonb, response_json jsonb, state text CHECK IN ('pending','succeeded','failed'), expires_at timestamptz, created_at timestamptz)`. 24h TTL via partial index. Insert-first dedup pattern.
- [ ] `stripe_connect_tokens` migration (037) — minimal shape per Reconciliation §7: `(user_id uuid PK, secret_store_path text NOT NULL, expires_at timestamptz, refreshed_at timestamptz, deauthorized_at timestamptz)`. Refresh token lives in **Stripe Secret Store**, not in our DB.
- [ ] All Postgres types use `text + CHECK` constraints (NOT `ENUM`) per deepen Data-F4 — Supabase wraps migrations in transactions, `ALTER TYPE ADD VALUE` cannot run in a transaction.
- [ ] All `SECURITY DEFINER` helpers pin `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`.
- [ ] `apps/web-platform/lib/feature-flags/server.ts` extended with `getFlagForUser(name, ctx)`. `stripe-projects-cloudflare-us` flag wired with US-billing-country predicate. Cache TTL ≤ 30s for safety-disable flags (deepen Perf-F5).
- [ ] **3-folder module re-layer shipped same PR** per Reconciliation §5 + deepen Arch F6:
  - `apps/web-platform/server/consent/` — token signing, decision recording, status polling, abort. Routes at `/api/consent/[id]/{decision,status,abort}` (protocol-agnostic).
  - `apps/web-platform/server/vendor-actions/` — audit writer, idempotency, cap snapshot, mandate ceiling enforcement, `VendorActionCommand` typed value object.
  - `apps/web-platform/server/stripe-projects/` — CLI subprocess wrapper + Stripe Connect OAuth + Stripe Secret Store integration + Shared Payment Tokens.
- [ ] Stripe Connect OAuth: `/api/stripe-projects/oauth/start` + `/api/stripe-projects/oauth/callback`. Refresh token persisted via **Stripe Secret Store API**, NOT byok-encrypted columns. **Distributed lock** per `connected_account_id` on token refresh (Postgres `SELECT FOR UPDATE`) to prevent the Nango-documented race-condition `invalid_grant`. Subscribe to `account.application.deauthorized` webhook → mark `deauthorized_at`, surface "Reconnect Stripe" CTA on next interaction.
- [ ] **Proactive 6-month refresh cron** in v1 (Reconciliation §9; D6/#3114 absorbed into this PR). `apps/web-platform/server/cron/stripe-connect-refresh.ts`. Wired via `vercel.json` (or platform equivalent).
- [ ] **Phase 2.5: Shared Payment Tokens integration** per Reconciliation §8. User issues token at consent time with per-token usage limits + agent ID + mandate ceiling. First charge = SCA via active 3DS (user-tap-confirm, not modal-dismiss). Subsequent within-mandate = MIT exemption.
- [ ] `vendor-actions/index.ts` exports `add(provider, opts, command: VendorActionCommand)` with inlined idempotency, three-invariant email-match, audit write. **State transitions:** `pending → consent_shown → approved → 3ds_required → 3ds_in_progress → 3ds_succeeded → executing → succeeded` (granular per agent-parity P5). Atomic transaction at `approved → 3ds_required`: state mutation + idempotency-row insert in same `BEGIN/COMMIT` (deepen Arch F1 crash-recovery).
- [ ] Three-invariant email-match assertion (Kieran fix #2 from prior review, retained): `cfAccount.email == user.stripe_email` AND `cfAccount.id == addResponse.account_id` AND `cfAccount.created_at < 60s ago`. Fail-closed.
- [ ] **Inline orphan-detection with Sentry-as-fallback-substrate** (deepen UI-1, TS9b): if email-match fails AFTER Stripe Projects reported `add` success, AND audit-row write also fails, **the Sentry P1 incident IS the durable record** — write Sentry FIRST with full context (`user_id`, `stripe_project_id`, `cf_account_id`, `idempotency_key`), then attempt audit-row retry. Success-card MUST NOT render until audit OR Sentry returns success.
- [ ] **Pre-encryption PII redactor** for prompts (deepen Sec-4): strips email/UUID/account-id patterns before persistence. Audit row stores `redacted_prompt` (not encrypted-raw). Test seeds user A's prompt with sentinel email; user B's export contains zero occurrences.
- [ ] Idempotency hash = `sha256(userId || provider || resource || plan_id || cap_cents || day_bucket)`. **Includes `cap_cents`** so cap-raise invalidates prior cached `cap-would-exceed` (deepen Sec-7). NOT `consent_token_id`.
- [ ] Per-action consent modal in `components/chat/`: vendor + plan + recurring amount + funding source last-4 + rationale + reversal-window + **mandate ceiling explicit re-consent disclosure** ("We'll re-confirm if Cloudflare ever changes this price") + email-confirm checkbox (deepen UI-2 active confirmation, not passive copy) + Approve / Edit / Cancel buttons + audit-log link.
- [ ] **Agent-native parity API surfaces** (deepen P1–P6, all six):
  - `POST /api/vendor-actions/intent` returns `{ consentUrl, statusEndpoint, consentTokenId, proposal: { provider, plan_id, recurring_amount_cents, one_time_charge_cents, currency, funding_source_last4, rationale, reversal_window_days, cap_cents_snapshot, mandate_ceiling_cents } }`
  - `GET /api/consent/[id]/status` returns `{ state, last_user_interaction_at, modal_opened_at, consent_token_expires_at, server_time, stage_entered_at }` with the granular state machine
  - Uniform error envelope on every terminal failure: `{ state: 'failed', error: { code, user_message, agent_hint, recoverable, suggested_actions } }`. Per-code shapes for `ERR_EMAIL_MISMATCH`, `ERR_CAP_EXCEEDED` (with `lower_plan_alternatives`), `ERR_REGION_NOT_SUPPORTED` (with `suggested_alternatives` like `{ provider: 'hetzner', protocol: 'terraform' }`), `ERR_CONTRACT_DRIFT`, `ERR_3DS_FAILED` (with `stripe_decline_code`), `ERR_OAUTH_LAPSE`, `ERR_MANDATE_CEILING_EXCEEDED`
  - `GET /api/vendor-actions/audit-log/query?vendor=&since=&state=&limit=` returns ≤50 structured rows RLS-bound to caller; registered as agent-callable tool `vendor_actions_audit_query` in `agent-runner-tools.ts` (export endpoint stays for bulk download)
  - `POST /api/consent/[id]/abort` for CLI SIGINT/timeout cleanup
- [ ] CLI polling cadence pinned: 2s with exponential backoff to 10s (max ~75 GETs per 5min consent flow). Status endpoint rate-limited 120 req/min/user. Status row cached in Redis/upstash with 1s TTL to avoid Postgres SELECT per poll (deepen Perf-F3).
- [ ] **Async-with-progress UX conditional on Phase 0 spike outcome**: if `add()` p95 > 10s, ship 202 + job-ID + progress polling (reuses CLI status infra). If p95 ≤ 10s, synchronous spinner is acceptable (deepen Perf-F6).
- [ ] `/api/vendor-actions/audit-log/export` — synchronous JSONL streaming with hard 10MB / 10k-row cap. Pre-ship benchmark in Phase 4.5 (seed 10k rows with realistic 6KB redacted prompts; assert p95 < 15s end-to-end). If >20s, lower cap to 5k rows OR move to `Transfer-Encoding: chunked` flushing every 500 rows. Rate-limit 10 req/hour. CSV format + async job pattern deferred (#3111).
- [ ] **STRIPE_LOG=info hard-set** in env allowlist (never `debug` — deepen Sec-2). `STRIPE_API_KEY` injected via `serviceTokens`; subprocess invocation passes `ALLOWED_SERVICE_ENV_VARS` check (`stripe-projects` provider entry added to `PROVIDER_CONFIG`).
- [ ] **Pre-Sentry breadcrumb token-redactor** for `stripe-projects` scope (deepen Sec-2): regex strip `sk_(live|test)_[A-Za-z0-9]{24,}`, `rk_(live|test)_...`, and CF token shape `[A-Za-z0-9_-]{40,}` before sending. Unit test with 50 fake-key fuzz samples asserting zero reach Sentry.
- [ ] **HMAC consent-token secret rotation**: secret stored as JSON map `{ "kid-2026-05": "<secret>", "kid-2026-08": "<secret>" }`. `kid` embedded in signed token; verify accepts current + previous kid. Quarterly rotation runbook in `runbooks/stripe-projects-incident-response.md`. Alert on any audit row with `kid` older than 6 months (deepen Sec-3).
- [ ] **Status endpoint requires Soleur PAT bearer** bound to `consent_token_id` at issue time; rejects mismatches as 404 (not 403, to avoid enumeration — deepen Sec-6).
- [ ] **bash-sandbox tempdir contract**: `mkdtemp` 0700 perms, try/finally `rm -rf` on panic. TS18 asserts no `.projects/` artifact survives between invocations + concurrent invocations get distinct tempdirs (deepen Sec-8).
- [ ] CLI plugin slash commands: `/soleur:vendor-signup cloudflare`, `/soleur:vendor-signup config`, `/soleur:vendor-signup revoke`, `/soleur:audit-log export`, `/soleur:audit-log show`. Exit codes 0/1/4/5/6/7. CLI sends `/abort` on SIGINT and 6-min idle timer.
- [ ] `plugins/soleur/agents/operations/ops-provisioner.md`, `service-automator.md`, `service-deep-links.md` updated. `ops-provisioner-cloudflare-stripe-projects` flag (2-week rollback window).
- [ ] Nightly contract test in `.github/workflows/scheduled-stripe-projects-contract.yml`. Auto-disable hook flips `stripe-projects-cloudflare-us` flag OFF on contract-test failure. Vendor-specific fixture (`jq '.cloudflare'`) — full-catalog diff would fire daily.
- [ ] **Flag-flip propagation chaos test** in Phase 10: flip flag during simulated load, assert no `add()` executes >60s after flip (deepen Perf-F5).
- [ ] **`processed_stripe_events` extension for `customer.subscription.updated`**: when Stripe emits a price/plan change for a Stripe Projects-provisioned subscription, invalidate `vendor_actions_idempotency` and emit a re-consent banner (Reconciliation §10 mandate-ceiling enforcement).
- [ ] **Privacy Policy / capability alignment** (deepen UI-4): policy claim must match v1 capability. Either (a) downgrade policy to "minimum 18 months hot, extending to 6 years upon cold-tier rollout" OR (b) block ship until cold-tier (#3112) lands. Choose at ship time.
- [ ] PR body uses `Ref #3106` (NOT `Closes`) since post-merge operator actions remain. `Ref #3107` for cross-link. `Closes #3114` (D6 absorbed). Final `gh issue close 3106` is operator step OP7.
- [ ] CPO sign-off comment on PR before merge.
- [ ] `user-impact-reviewer` invoked at review time and findings resolved fix-inline.
- [ ] `/integrations/stripe-projects` Eleventy page shipped with critical CSS inlined; pricing page + agents page + llms.txt + homepage hero badge updates landed in same PR.
- [ ] Legal artifacts landed in same PR (or chained PR merging before flag flip): ToS, Privacy Policy, AUP, Data Protection Disclosure — all updated for Stripe Secret Store + Shared Payment Tokens posture.
- [ ] Smoke E2E: cold signup, three-invariant email-match positive + 3 negatives (TS2 a/b/c), $25 cap exceed, mandate-ceiling re-consent on price change, geo-reject for non-US, OAuth refresh race (TS20), revoke cascade, idempotency replay across consent-token-TTL boundary (TS3 retained from prior review).
- [ ] **Phase 0 spike load-test target**: 50 concurrent `add()` invocations with p95 < 2s wall-clock, p99 RSS < 256MB. If p95 > 5s, Phase 3 must add subprocess pool (deepen Perf-F1).
- [ ] TDD: failing tests written BEFORE implementation per `cq-write-failing-tests-before` for every TR (excluding pure-config tasks).
- [ ] All `## Files to Edit` and `## Files to Create` paths verified against `git ls-files`.
- [ ] All catch blocks emitting 4xx/5xx mirror via `reportSilentFallback`; no exemption requests for the consumer-side flow.

### Post-merge (operator)

Per `cq-when-a-pr-has-post-merge-operator-actions`, this section uses `Ref #3106` semantics in PR body — final issue close happens after operator steps complete.

- [ ] Operator runs `terraform apply -auto-approve` against `apps/web-platform/infra/` to provision Doppler secrets (`STRIPE_PROJECTS_CLIENT_ID`, `STRIPE_PROJECTS_CLIENT_SECRET`, `STRIPE_PROJECTS_REDIRECT_URI`, `STRIPE_PROJECTS_CONSENT_TOKEN_SECRET` JSON map, `STRIPE_SECRET_STORE_API_KEY`, `STRIPE_SHARED_PAYMENT_TOKEN_API_KEY`).
- [ ] Operator runs `gh secret set STRIPE_PROJECTS_WEBHOOK_SECRET` (per `hr-menu-option-ack-not-prod-write-auth`: show command, wait for go-ahead).
- [ ] Operator manually flips `stripe-projects-cloudflare-us` ON for staff users only first; runs internal smoke test; then flips for general US users.
- [ ] Operator triggers `gh workflow run scheduled-stripe-projects-contract.yml` to verify nightly contract path is healthy on main (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- [ ] Operator confirms US-only flag predicate by attempting flow from non-US IP (VPN test).
- [ ] Operator verifies launch post published to all 5 surfaces within Sprint Re-Evaluation outcome's window.
- [ ] Operator runs `gh issue close 3106` after smoke test passes.

## Test Scenarios

TDD per `cq-write-failing-tests-before`. Tests land BEFORE implementation in each phase.

| # | Scenario | Layer | Failure mode covered |
|---|----------|-------|---------------------|
| TS1 | Cold signup happy path: US user, no existing CF, valid Stripe OAuth, approves modal, Shared Payment Token issued, user actively confirms 3DS, CF account auto-provisioned with Stripe email, byok-encrypted result metadata persisted, audit row written, success card rendered. | E2E | None (golden path) |
| TS2 | Email-match assertion fails closed under THREE invariants: (a) mismatched email, (b) matched email + mismatched `account.id` (orphan-account variant), (c) matched email + matched id but `account.created_at > 60s ago` (CF cache-hit variant). All three fail closed; token does NOT surface; Sentry incident; audit-row marks `protocol_state: 'email_mismatch_blocked'`. | Integration | Cross-tenant credential bleed + orphan-account hijack |
| TS3 | Idempotency replay: same user invokes `add()` with identical `(provider, resource, plan, cap_cents, day_bucket)` twice within 24h. Second call returns cached `response_json` from `vendor_actions_idempotency`. Variant: retry AFTER consent-token TTL expiry STILL hits cache (does NOT double-provision). | Unit + integration | Double-provisioning + cross-token-TTL replay |
| TS4 | Cross-entry-point lock: cloud-chat starts flow, abandons at modal, retries from CLI within 5min. CLI must NOT block forever and must NOT bypass consent — server returns `flow-pending-elsewhere` with TTL. | Integration | RC1 — cross-entry-point race |
| TS5 | Spend cap exceed: user has $25 cap; agent attempts plan exceeding it. Server pre-flight returns `ERR_CAP_EXCEEDED` envelope with `cap_cents`, `requested_cents`, `delta_cents`, `lower_plan_alternatives`; no provisioning. | Unit | FR6 + ME11 + agent-parity P3 |
| TS6 | Cap raise mid-flight: cap value captured at consent-modal-render time; locked into audit row; later cap raise does NOT retroactively apply. cap_cents source-of-truth is the audit row keyed by `consent_token_id`, NOT `users.cap_cents` (deepen Data-F5). | Integration | ME5 + cap-raise race |
| TS7 | Geo-reject for non-US: `DE`-billing user invokes flow. Cloud surface returns 451 + waitlist; CLI returns `ERR_REGION_NOT_SUPPORTED` envelope with `suggested_alternatives: [{ provider: 'hetzner', protocol: 'terraform' }]`, exit code 4. | Unit | FR7 + FG10 + agent-parity P3 |
| TS8 | OAuth lapse re-consent: mid-session, Stripe Connect refresh fails with `invalid_grant`. User redirected to OAuth re-consent; original intent + idempotency key preserved; on success, flow resumes from consent-modal step. | Integration | ME1 + ME2 + Reconciliation §9 |
| TS9 | Audit-log write failure (token has NOT yet surfaced from `add`): mock `vendor_actions` insert to fail. Token MUST NOT surface; user sees "provisioning held" card; Sentry incident; idempotency-row TTL releases. | Integration | ME7 + RP2 |
| **TS9b** | **Partial-orphan: Stripe Projects `add` succeeded + audit-row write fails. Sentry P1 IS the durable record (deepen UI-1). Success-card MUST NOT render. User sees "provisioning held — support paged" with ticket ID. Reconciliation surface verifies Sentry breadcrumb contains `stripe_project_id`, `cf_account_id`, `idempotency_key` for manual reconciliation.** | Integration | NEW — billed-without-soleur-record class |
| TS10 | Revoke cascade: user invokes `/soleur:vendor-signup revoke cloudflare`. Server calls `stripe projects remove cloudflare`; on success marks audit row `revoked`, deletes Stripe Secret Store entry, CF API token invalidated. | Integration | FR11 + FG7 |
| TS11 | Beta protocol drift: nightly contract test detects schema change. Job posts `stripe-projects-protocol-drift` issue and flips flag to OFF. In-flight users see "feature paused for safety" card. | E2E (against staging) | TR7 + TR17 + ME12 |
| **TS11b** | **In-flight `add()` during contract-failure flag-flip MUST complete to a terminal state (succeeded or rolled-back). Flag-flip blocks NEW intents only — feature-flag check happens at intent-creation, not per-step inside `add()` (deepen UI-5).** | Integration | NEW — flag-flip-mid-execution race |
| TS12 | Sentry mirror failure: mock Sentry SDK to throw. `reportSilentFallback` swallows error per `cq-silent-fallback-must-mirror-to-sentry` try/catch contract; pino is durable signal. | Unit | ME8 |
| TS13 | RLS isolation: user A's audit-log `/export` AND `/query` endpoints return ZERO of user B's rows. Test seeds user A's prompt with sentinel email; user B's export must not contain the sentinel (deepen Sec-4 cross-tenant prompt content leakage). | Integration | FR5 RLS + cross-tenant audit/prompt leak |
| TS14 | First-charge SCA via Stripe Shared Payment Token + active 3DS user-tap-confirm (NOT modal-dismiss). Stripe drives the SCA ceremony; Soleur surfaces the success/failure as part of `add()` response. PSD2 SCA Art. 97 satisfied via Stripe-owned ceremony (Reconciliation §8). | Integration (mocked Stripe SCA) | PSD2 SCA Art. 97 + DRCF mandate-bundling defense |
| TS15 | CLI fallback under sandbox: subprocess invocation rejects any command containing `$STRIPE_*` direct references; subprocess `env` is explicit allowlist plus `STRIPE_API_KEY` injected via `serviceTokens`. `STRIPE_LOG=info` enforced. | Unit | TR15 + agent-env CWE-526 + deepen Sec-2 |
| TS16 | Append-only INSERT-only RLS on `vendor_actions_audit_events` history table — non-service-role UPDATE/DELETE returns `0 rows affected`. (Mutable head row `vendor_actions` allows owner SELECT + service-role UPDATE.) | Unit | TR9 append-only RLS (corrected per Data-F1) |
| TS17 | ops-provisioner Playwright fallback: feature-flagged path. Flag ON + Stripe Projects healthy → new tier. Flag OFF → Playwright fallback. | Unit | FR8 |
| **TS18** | **bash-sandbox tempdir isolation: concurrent `add()` invocations get distinct tempdirs; panic in invocation A does NOT leave `.projects/vault/` material visible to invocation B; cleanup runs in finally even on subprocess panic (deepen Sec-8).** | Unit | NEW — concurrent invocation cross-leak |
| **TS19** | **Pre-Sentry token redactor: subprocess error containing fake `sk_live_...`, `rk_test_...`, or CF-token-shaped strings MUST land in Sentry with the token redacted. 50-sample fuzz (deepen Sec-2).** | Unit | NEW — Sentry breadcrumb token leak |
| **TS20** | **Distributed-lock token refresh: two concurrent workers attempt refresh on same `connected_account_id`. One acquires the Postgres `SELECT FOR UPDATE`; the other blocks; both observe the same post-refresh `(access_token, refresh_token, expires_at)` triple. No `invalid_grant` (deepen Reconciliation §9).** | Integration | NEW — Nango-documented OAuth race |
| **TS21** | **Mandate-ceiling re-consent: simulate Stripe webhook `customer.subscription.updated` with price increase on a CF subscription provisioned via Stripe Projects. Audit row marks `mandate_invalidated`; in-flight `vendor_actions_idempotency` rows TTL'd; user sees re-consent banner on next interaction (deepen Reconciliation §10).** | Integration | NEW — DRCF mandate-bundling, MIT exemption void |
| **TS22** | **SCA active-tap requirement: agent triggers Shared Payment Token charge; user is presented with active 3DS challenge (not silent dismiss). Test simulates user navigating away (no tap) → `ERR_3DS_FAILED` envelope, no charge committed (deepen Best-practices §3).** | Integration (mocked Stripe SCA) | NEW — PSD2 Art. 97 user-presence requirement |
| **TS23** | **Audit-log export performance: seed 10k rows with realistic 6KB redacted prompts; assert p95 < 15s end-to-end. If exceeded: streaming chunks must flush every 500 rows OR cap drops to 5k rows (deepen Perf-F4).** | Performance | NEW — Vercel 30s timeout cliff |
| **TS24** | **Flag-flip propagation chaos: under simulated load (10 concurrent in-flight intents), flip `stripe-projects-cloudflare-us` to OFF. Assert (a) no NEW intent succeeds within 60s, (b) all in-flight `add()` calls reach terminal state, (c) audit rows show `feature_paused` for blocked NEW (deepen Perf-F5).** | E2E (chaos) | NEW — flag propagation SLA |

## Implementation Phases

Day numbers below assume Sprint Re-Evaluation outcome (a) (3w → 4-5w). For (b) phased: Phases 0-3 + minimal 4 + 8 + flag-gated launch land in 14 days; Phases 5-7 + remaining 4 + 9-10 in fast-follow PR. For (c) hold-launch: same as (a) without launch-post window pressure.

### Phase 0: Spike + ADR (Days 1-3, expanded scope)

Goal: resolve the unanswered Stripe Projects research items + verify the new substrate APIs.

1. Install `stripe` ≥ 1.40.0 + `stripe plugin install projects` in sandbox container; capture pinned versions.
2. Run `stripe projects init`, `catalog --json`, `add cloudflare/...` against Stripe sandbox; capture exit codes, stdout shapes, side-effect files (`.projects/vault/`, `~/.config/stripe/`).
3. Test `Idempotency-Key` HTTP header behavior on retry.
4. Test `--json` output stability across `stripe projects --version` bumps.
5. Test cold-signup email override mechanisms — confirm Stripe-email = CF-email is hard constraint.
6. Test revoke cascade — does `stripe projects remove cloudflare` delete CF account or just unlink?
7. Test webhook surface — register wildcard, capture event types.
8. Inspect OpenRouter integration as comparable provider for Connect-OAuth-flow shape.
9. **NEW — capture cold-start performance**: p50/p95/p99 wall-clock for `stripe projects add ...` under bash-sandbox. Record RSS per invocation. This output drives Phase 3 (subprocess pool decision) and Phase 4 (sync vs async-with-progress UX decision).
10. **NEW — verify Stripe Secret Store API for `oauth_refresh_token`**: confirm endpoint shape, retrieval latency from cron context, deletion behavior on `account.application.deauthorized`. Drives Phase 2 module shape.
11. **NEW — verify Shared Payment Tokens issuance + redemption flow**: how does the agent issue a token; how does the user actively complete 3DS; what error envelope does Stripe return on user-not-tap; what's the per-token usage limit shape; how does mandate ceiling fit. Drives Phase 2.5 design.
12. **NEW — capture `account.application.deauthorized` webhook payload shape** for Phase 2 webhook handler.
13. **NEW — test concurrent token refresh**: two workers simultaneously attempting refresh on same `connected_account_id` — confirm Postgres `SELECT FOR UPDATE` serializes correctly OR identify alternate lock primitive (Redis SETNX).
14. Write spike report to `knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md`.
15. Run `/soleur:architecture create "Adopt Stripe Projects + Stripe Secret Store + Shared Payment Tokens for Cloudflare cold-signup"` — one ADR per load-bearing decision per deepen Arch F7: (i) CLI-vs-REST, (ii) cloud-server-sole-executor pivot, (iii) consent-domain crash-recovery contract, (iv) `vendor_actions_audit` two-table model, (v) `vendor_actions_idempotency` separate-table reversal, (vi) Stripe Secret Store substrate, (vii) Shared Payment Tokens substrate.
16. Update spec.md to reflect spike outputs; update Reconciliation table if any item resolves differently.
17. Commit: `docs: spike report + 7 ADRs for stripe-projects integration`.

### Phase 1: Foundations (Days 4-6)

1. Migration `035_vendor_actions_audit.sql` — **two-table model** per Data-F1:
   - `vendor_actions` (mutable head): `(id uuid PK, user_id uuid NOT NULL [no FK], vendor text NOT NULL, protocol text CHECK IN ('stripe-projects','playwright','mcp-tier'), protocol_state text CHECK IN (...), provider_metadata jsonb, idempotency_key text, cap_cents int, mandate_ceiling_cents int, consent_token_id text, prompt_hash text, redacted_prompt text, created_at, updated_at, anonymized_at timestamptz NULL)`. Owner-SELECT RLS, service-role-UPDATE RLS.
   - `vendor_actions_audit_events` (INSERT-only history): `(id uuid PK, vendor_action_id uuid REFERENCES vendor_actions(id), state_from text, state_to text, occurred_at, actor text, payload jsonb)`. Trigger on `vendor_actions` UPDATE writes a row. Append-only INSERT-only RLS — TS16 verifies.
   - **No FK on `user_id`** per Data-F2 (GDPR Art. 17). Anonymization SQL: `UPDATE vendor_actions SET user_id = NULL, redacted_prompt = NULL, provider_metadata = jsonb_set(provider_metadata, '{cf_account_email}', 'null'), anonymized_at = now() WHERE user_id = $1`. Documented in `runbooks/gdpr-erasure-vendor-actions.md`.
   - All columns use `text + CHECK` (NOT enum) per Data-F4.
2. Migration `036_vendor_actions_idempotency.sql` — separate table per Reconciliation §6:
   - `(idempotency_key text PK, user_id uuid, vendor text, provider_metadata jsonb, response_json jsonb, state text CHECK IN ('pending','succeeded','failed','feature_paused','mandate_invalidated'), expires_at timestamptz, created_at)`. Partial index on `expires_at` for 24h TTL purge.
3. Migration `037_stripe_connect_tokens.sql` — minimal shape per Reconciliation §7:
   - `(user_id uuid PK, secret_store_path text NOT NULL, expires_at timestamptz, refreshed_at timestamptz, deauthorized_at timestamptz NULL)`.
   - Refresh token lives in **Stripe Secret Store**, not in our DB.
4. Migration `038_processed_stripe_events_subscription_updated.sql` — extend the existing inbound-webhook handler for `customer.subscription.updated` events tied to a Stripe Projects-provisioned subscription (mandate-ceiling re-consent trigger, Reconciliation §10).
5. Extend `apps/web-platform/lib/feature-flags/server.ts` with `getFlagForUser(name, ctx)` per Functional-discovery §Reuse 1. Wire `stripe-projects-cloudflare-us` flag with US billing-country predicate. **Cache TTL ≤ 30s for safety-disable flags** per Perf-F5. Tests in `apps/web-platform/test/feature-flags.test.ts`.
6. Add `/api/vendor-actions/billing-country` Server Action that queries Stripe customer billing country and caches per-session.
7. Add doc-comment on `getFlagForUser` per deepen Arch F5: "do not call from middleware/edge runtime — predicate may issue Stripe API calls; cache per-session at the route-handler/server-action layer."
8. Wire `reportSilentFallback` import sites for the upcoming module.

### Phase 2: Stripe Connect OAuth + Stripe Secret Store + Refresh Cron (Days 7-9)

1. `/api/stripe-projects/oauth/start` (POST): generates `state` (CSRF), PKCE pair. Honors `validateOrigin`.
2. `/api/stripe-projects/oauth/callback` (GET): exchanges code for `access_token` + `refresh_token`. **Refresh token persisted via Stripe Secret Store API** (NOT byok). `stripe_connect_tokens` row stores `secret_store_path` + lifetimes. 1-year refresh TTL per Stripe docs.
3. `apps/web-platform/server/stripe-projects/oauth.ts` exports `getValidConnectToken(userId)`: retrieves from Secret Store; refreshes if `<1h to expiry`; **acquires distributed lock via Postgres `SELECT FOR UPDATE` on `stripe_connect_tokens` row before refresh** (deepen Reconciliation §9 race fix); writes new triple atomically; releases lock. Sentry-mirrors any refresh failure.
4. `/api/stripe-projects/oauth/revoke` (POST): explicit revoke. Cascades to `vendor_actions` (mark active rows `revoked`) + deletes Secret Store entry.
5. `/api/stripe-projects/webhook/account-deauthorized` (POST): handler for `account.application.deauthorized` Stripe webhook. Marks `stripe_connect_tokens.deauthorized_at`; on next user interaction surfaces "Reconnect Stripe" CTA. NO seamless re-prompt pretense (Reconciliation §9).
6. `apps/web-platform/server/cron/stripe-connect-refresh.ts` — **proactive 6-month refresh cron** (Reconciliation §9, D6 absorbed into v1). Daily scan of `stripe_connect_tokens.refreshed_at`; refresh any older than 180 days. Distributed lock as in step 3. Wired in `vercel.json`.
7. TDD scenarios: TS8, TS20.

### Phase 2.5: Shared Payment Tokens Integration (Days 10-11) — NEW per Reconciliation §8

1. `apps/web-platform/server/stripe-projects/shared-payment-tokens.ts` — wraps Stripe's Shared Payment Tokens API.
   - `issueToken(userId, vendor, mandateCeilingCents, agentId): Promise<{ tokenId, redirectUrl }>` — invoked by consent-decision endpoint when user clicks Approve. Returns Stripe-hosted SCA URL.
   - `redeemToken(tokenId): Promise<{ accountId, charge }>` — invoked by `add()` after user has actively completed 3DS in Stripe-hosted flow.
2. Consent flow re-shaped: Approve button now redirects user to Stripe-hosted 3DS URL. State machine adds `3ds_required → 3ds_in_progress → 3ds_succeeded` (or `→ 3ds_failed`). User-presence requirement: Stripe controls the SCA ceremony; Soleur cannot dismiss it on the user's behalf.
3. `customer.subscription.updated` webhook handler (migration 038) checks whether new price exceeds `mandate_ceiling_cents`; if yes → invalidate idempotency row + emit re-consent banner.
4. Modal copy update: "Stripe will ask you to confirm this purchase on your bank app" instead of passive 3DS dismissal.
5. TDD scenarios: TS14 (rewritten), TS21, TS22.

### Phase 3: Shared core module (vendor-actions/) (Days 12-15)

1. Failing tests TS1, TS2 (three-invariant), TS3 (cap_cents-included key), TS5, TS6 (audit-row source-of-truth), TS9, TS9b, TS11b, TS12, TS13, TS15, TS18, TS19, TS24 first.
2. Scaffold `apps/web-platform/server/vendor-actions/` (parent context per DDD F1):
   - `index.ts` — public API: `add(provider, opts, command: VendorActionCommand)`. Inlined: idempotency, three-invariant email-match, audit write, mandate-ceiling check, structured-error envelope construction, partial-orphan inline detection.
   - `types.ts` — `VendorActionCommand` typed value object: `{ userId, vendor, capCents, mandateCeilingCents, consentTokenId, prompt }`.
   - `audit.ts` — append-only history-events writer; pre-encryption PII redactor for prompts.
3. `apps/web-platform/server/stripe-projects/` (protocol ACL per DDD F1):
   - `subprocess.ts` — `execFile` + `bash-sandbox`, `--json` only, `STRIPE_API_KEY` injected via serviceTokens, `STRIPE_LOG=info` hard-set, output piped through `| head -n 500`, full stderr captured to Sentry breadcrumb (with pre-Sentry token-redactor per Sec-2). Tempdir contract: `mkdtemp` 0700 + try/finally `rm -rf` (Sec-8).
   - `oauth.ts` — Phase 2 refresh + Secret Store integration.
   - `shared-payment-tokens.ts` — Phase 2.5 wrapper.
   - `index.ts` — translates CLI exit codes / stdout into structured `VendorActionCommand` outcomes; depends on `vendor-actions/`, NOT vice versa.
4. `apps/web-platform/server/consent/` (parent context per DDD F2):
   - `tokens.ts` — HMAC-SHA256 with `kid` rotation, JSON-map secret structure (Sec-3).
   - `decision.ts`, `status.ts`, `abort.ts` — protocol-agnostic consent ceremony writers.
5. **Idempotency** (inlined in `vendor-actions/index.ts`): key = `sha256(userId || provider || resource || plan_id || cap_cents || day_bucket)`. NOT `consent_token_id`. Insert-first dedup against `vendor_actions_idempotency` (the new dedicated table). Cached `response_json` on hit.
6. **Three-invariant email-match assertion** (inlined): `cfAccount.email == user.stripe_email` AND `cfAccount.id == addResponse.account_id` AND `cfAccount.created_at < 60s ago`. Fail-closed.
7. **Inline orphan-detection with Sentry-as-fallback-substrate** (UI-1): on email-match-fail-after-CF-write-success, write Sentry P1 incident FIRST with full context, THEN attempt `protocol_state: 'orphaned'` audit row. Success-card MUST NOT render until at least one of (audit, Sentry) returns success.
8. **Structured error envelope** (P3): every terminal failure returns `{ state: 'failed', error: { code, user_message, agent_hint, recoverable, suggested_actions } }`. Per-code shapes per AC.
9. **Granular state machine transitions** (P5): `pending → consent_shown → approved → 3ds_required → 3ds_in_progress → 3ds_succeeded → executing → succeeded`. Each transition writes `last_user_interaction_at` and `stage_entered_at` to `vendor_actions` head.
10. **Atomic transaction** at `approved → 3ds_required` (Arch F1): state mutation + idempotency-row insert in same `BEGIN/COMMIT`.
11. Add `stripe-projects` provider entry to `apps/web-platform/server/providers.ts` with `envVar: STRIPE_API_KEY`.
12. **Crash-recovery runbook** added per Arch F7 ADR (iii).

### Phase 4: Consent surfaces + agent-native parity (Days 16-19)

1. ux-design-lead wireframes (Pencil MCP) for consent modal + mandate-ceiling banner — invoked at start of Phase 4 per Domain Review.
2. Failing tests TS4, TS7, TS21 (mandate-ceiling re-consent UX side), agent-parity tests for status endpoint heartbeat and structured errors first.
3. `components/chat/stripe-projects-consent-modal.tsx` — props: provider, plan, recurringAmountCents, oneTimeChargeCents, currency, fundingSourceLast4, rationale, reversalWindow, **mandateCeilingCents**. Active **email-confirm checkbox** (UI-2). **Mandate-ceiling re-consent disclosure** ("We'll re-confirm if Cloudflare ever changes this price"). Buttons: Approve (kicks off Shared Payment Token issuance + redirect to Stripe-hosted SCA), Edit, Cancel. Copy floor per Best-practices §1.
4. `components/chat/stripe-projects-success-card.tsx` — failure path uses uniform error envelope rendering (no separate failure-card).
5. `/api/vendor-actions/intent` (POST) — accepts CLI-plugin intent payloads. Validates Soleur PAT. Returns `{ consentUrl, statusEndpoint, consentTokenId, proposal: {...} }` with full proposal payload (P1).
6. `app/consent/[consentTokenId]/page.tsx` — standalone consent page for CLI path (outside `app/api/`).
7. `/api/consent/[consentTokenId]/decision` (POST) — protocol-agnostic. Records Approve/Cancel; on Approve calls `vendor-actions.add()` server-side.
8. `/api/consent/[consentTokenId]/status` (GET) — returns `{ state, last_user_interaction_at, modal_opened_at, consent_token_expires_at, server_time, stage_entered_at }`. **Soleur PAT bearer required** bound to `consent_token_id` (Sec-6); reject mismatches as 404. **Redis cache 1s TTL** (Perf-F3). **Polling pinned 2s with exp backoff to 10s; rate-limit 120 req/min/user.**
9. `/api/consent/[consentTokenId]/abort` (POST) — CLI SIGINT/timeout cleanup (P6).
10. `/api/vendor-actions/audit-log/query?vendor=&since=&state=&limit=` (GET) — structured rows ≤50, RLS-bound. **Registered as agent-callable tool `vendor_actions_audit_query` in `agent-runner-tools.ts`** (P4).
11. `/api/vendor-actions/audit-log/export` (GET) — synchronous JSONL streaming, hard 10MB / 10k-row cap. Pre-ship benchmark in Phase 4.5.
12. **Conditional async-with-progress UX** (Perf-F6): if Phase 0 spike captured `add()` p95 > 10s, ship 202 + job-ID + progress polling. Same infra as CLI status endpoint. If p95 ≤ 10s, sync spinner.
13. copywriter agent review of all consent + success-card + mandate-ceiling-banner copy.

### Phase 4.5: Pre-Ship Benchmark (Day 20)

1. Seed `vendor_actions_audit_events` with 10k rows containing realistic 6KB `redacted_prompt`s.
2. Hit `/audit-log/export` with cold cache. Measure p95 end-to-end.
3. Decision tree: p95 < 15s → ship as-is; 15-20s → ship with `Transfer-Encoding: chunked` flush every 500 rows; >20s → reduce cap to 5k rows AND chunk.
4. Failing test TS23 first.

### Phase 5: ops-provisioner integration (Day 21)

1. Failing test TS17 first.
2. Edit `plugins/soleur/agents/operations/ops-provisioner.md` — Tier 0: Stripe Projects above Playwright.
3. Edit `plugins/soleur/agents/operations/service-automator.md` — insert Stripe Projects tier above MCP; new "Cloudflare (Stripe Projects Tier)" playbook; clarify CF MCP playbook is for management of existing accounts.
4. Edit `plugins/soleur/agents/operations/references/service-deep-links.md` — Stripe Projects-first instruction; dashboard URL fallback.
5. Add `ops-provisioner-cloudflare-stripe-projects` flag (2-week rollback window).

### Phase 6: CLI plugin slash commands (Day 22)

1. Token-budget check: `bun test plugins/soleur/test/components.test.ts` — note `current/1800` words; new SKILL.md ≤ 30 words.
2. `plugins/soleur/skills/vendor-signup/SKILL.md` — `/soleur:vendor-signup <provider>`, `config`, `revoke`. Posts intent → opens `consentUrl` (Stripe-hosted SCA) via `xdg-open`/`open` → polls status (2s exp backoff to 10s) → renders structured success/failure block. Sends `/abort` on SIGINT and 6-min idle.
3. `plugins/soleur/skills/audit-log/SKILL.md` — `/soleur:audit-log export`, `show [--last N]`. Calls `/audit-log/query` (structured) for `show`, `/audit-log/export` (JSONL) for `export`.
4. Verify exit codes (0/1/4/5/6/7).
5. Failing tests TS4 (CLI), TS7 (CLI), TS10 first.

### Phase 7: Marketing surfaces + launch post (Days 23-24, parallel with Phase 8)

Sequencing depends on Sprint Re-Evaluation outcome. If (a) bundle-slip → retroactive post; if (b) phased → on-time post claiming flag-gated MVP; if (c) → 4-5w-late post no longer first-mover.

1. `plugins/soleur/docs/pages/integrations/stripe-projects.njk` — inline critical CSS, pass `screenshot-gate.mjs`. Page describes Stripe Secret Store + Shared Payment Tokens posture (Stripe handles SCA + token storage; Soleur handles agent reasoning + audit).
2. Update `pages/agents.njk` with Stripe Projects badge.
3. Update `pages/pricing/index.njk` with $25 cap explainer + mandate-ceiling explainer ("agent-safe spending").
4. Update `_data/site.json` and `llms.txt`.
5. Homepage hero badge in `_includes/base.njk`.
6. Draft `pages/blog/2026-05-XX-stripe-projects-launch.njk`.
7. Run `copywriter` agent for brand voice.
8. Wire `social-distribute` skill for blog → HN → X → LinkedIn → dev.to.

### Phase 8: Legal artifacts (Days 23-25, parallel with Phase 7)

1. Update `docs/legal/terms-and-conditions.md` — agent mandate addendum, beta-deprecation right with pro-rata refund, spend-cap + mandate-ceiling liability, beta force-majeure clause, chargeback playbook. **Disclose Stripe Shared Payment Tokens substrate**: Stripe owns the SCA ceremony; Soleur cannot bypass it.
2. Update `docs/legal/privacy-policy.md` — Agent-Initiated Third-Party Subscriptions section. Stripe + Cloudflare as separate processors. **Disclose Stripe Secret Store as the OAuth refresh-token storage substrate** (Stripe is the encryption-at-rest controller, not Soleur). Legal basis: contract performance + explicit consent for agent mandate. **Retention claim aligned to v1 capability** (UI-4): "minimum 18 months hot, extending to 6 years upon cold-tier rollout" OR (if cold-tier ships in v1) 6-year tiered.
3. Update `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
4. Update `docs/legal/acceptable-use-policy.md`.
5. Update `compliance-posture.md` Vendor DPA table — new "Stripe Projects (provider role)" row + "Stripe Secret Store" row + "Stripe Shared Payment Tokens" row.
6. Run `legal-compliance-auditor` agent on updated docs.
7. Open follow-on issue `feat-stripe-projects-eu-rollout` (DPIA + GDPR Policy update).
8. Document GDPR anonymization runbook — `runbooks/gdpr-erasure-vendor-actions.md` (Data-F2).

### Phase 9: CI + observability (Days 25-26)

1. `.github/workflows/scheduled-stripe-projects-contract.yml` (cron 02:00 UTC) — vendor-specific diff (`jq '.cloudflare'`).
2. `.github/fixtures/stripe-projects-catalog-cloudflare-baseline.json`.
3. Auto-disable hook for `stripe-projects-cloudflare-us` flag on contract-test failure.
4. **Stripe Connect refresh cron wired** (Phase 2 step 6) into `vercel.json` — daily.
5. Failing test TS11, TS24 first.

### Phase 10: Pre-ship + smoke + load-test (Days 27-29)

1. Full E2E against Stripe sandbox + Cloudflare staging.
2. **Load-test target** per Perf-F1: sustain 50 concurrent `add()` invocations with p95 < 2s wall-clock, p99 RSS < 256MB. If exceeded, Phase 3 must add subprocess pool BEFORE ship.
3. **Chaos test** per Perf-F5 (TS24): flip `stripe-projects-cloudflare-us` flag during simulated load; assert no `add()` executes >60s after flip; in-flight intents complete to terminal state.
4. `gh issue list --label code-review --state open` overlap re-check.
5. `/soleur:preflight` — Check 6 validates `## User-Brand Impact`.
6. `/soleur:review` — 9-agent multi-review.
7. Resolve all review findings fix-inline.
8. `/soleur:qa` functional QA.
9. `/soleur:compound` to capture session learnings.
10. `/soleur:ship` with `semver:minor` label.

## Files to Create

```text
apps/web-platform/server/consent/tokens.ts
apps/web-platform/server/consent/decision.ts
apps/web-platform/server/consent/status.ts
apps/web-platform/server/consent/abort.ts
apps/web-platform/server/vendor-actions/index.ts
apps/web-platform/server/vendor-actions/types.ts
apps/web-platform/server/vendor-actions/audit.ts
apps/web-platform/server/stripe-projects/index.ts
apps/web-platform/server/stripe-projects/subprocess.ts
apps/web-platform/server/stripe-projects/oauth.ts
apps/web-platform/server/stripe-projects/shared-payment-tokens.ts
apps/web-platform/server/cron/stripe-connect-refresh.ts
apps/web-platform/app/api/stripe-projects/oauth/start/route.ts
apps/web-platform/app/api/stripe-projects/oauth/callback/route.ts
apps/web-platform/app/api/stripe-projects/oauth/revoke/route.ts
apps/web-platform/app/api/stripe-projects/webhook/account-deauthorized/route.ts
apps/web-platform/app/api/vendor-actions/intent/route.ts
apps/web-platform/app/api/vendor-actions/billing-country/route.ts
apps/web-platform/app/api/vendor-actions/audit-log/export/route.ts
apps/web-platform/app/api/vendor-actions/audit-log/query/route.ts
apps/web-platform/app/api/consent/[consentTokenId]/decision/route.ts
apps/web-platform/app/api/consent/[consentTokenId]/status/route.ts
apps/web-platform/app/api/consent/[consentTokenId]/abort/route.ts
apps/web-platform/app/consent/[consentTokenId]/page.tsx
apps/web-platform/components/chat/stripe-projects-consent-modal.tsx
apps/web-platform/components/chat/stripe-projects-success-card.tsx
apps/web-platform/components/chat/mandate-ceiling-reconsent-banner.tsx
apps/web-platform/supabase/migrations/035_vendor_actions_audit.sql
apps/web-platform/supabase/migrations/036_vendor_actions_idempotency.sql
apps/web-platform/supabase/migrations/037_stripe_connect_tokens.sql
apps/web-platform/supabase/migrations/038_processed_stripe_events_subscription_updated.sql
apps/web-platform/test/vendor-actions-core.test.ts
apps/web-platform/test/vendor-actions-email-match.test.ts
apps/web-platform/test/vendor-actions-idempotency.test.ts
apps/web-platform/test/vendor-actions-rls.test.ts
apps/web-platform/test/vendor-actions-cap.test.ts
apps/web-platform/test/vendor-actions-mandate-ceiling.test.ts
apps/web-platform/test/vendor-actions-geo.test.ts
apps/web-platform/test/vendor-actions-partial-orphan.test.ts
apps/web-platform/test/vendor-actions-flag-flip-chaos.test.ts
apps/web-platform/test/vendor-actions-export-perf.test.ts
apps/web-platform/test/stripe-projects-subprocess-tempdir.test.ts
apps/web-platform/test/stripe-projects-sentry-redactor.test.ts
apps/web-platform/test/stripe-connect-refresh-race.test.ts
apps/web-platform/test/shared-payment-tokens-active-tap.test.ts
apps/web-platform/test/feature-flags-getFlagForUser.test.ts
apps/web-platform/test/consent-modal.test.tsx
apps/web-platform/test/vendor-actions-e2e.test.ts
apps/web-platform/test/ops-provisioner-stripe-projects.test.ts
plugins/soleur/skills/vendor-signup/SKILL.md
plugins/soleur/skills/audit-log/SKILL.md
plugins/soleur/docs/pages/integrations/stripe-projects.njk
plugins/soleur/docs/pages/blog/2026-05-XX-stripe-projects-launch.njk
.github/workflows/scheduled-stripe-projects-contract.yml
.github/fixtures/stripe-projects-catalog-cloudflare-baseline.json
knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spike-2026-05-04.md
knowledge-base/architecture/decisions/ADR-XXXX-stripe-projects-cli-vs-rest.md
knowledge-base/architecture/decisions/ADR-XXXY-cloud-server-sole-executor.md
knowledge-base/architecture/decisions/ADR-XXXZ-consent-crash-recovery-contract.md
knowledge-base/architecture/decisions/ADR-XXYA-vendor-actions-two-table-model.md
knowledge-base/architecture/decisions/ADR-XXYB-vendor-actions-idempotency-separate-table.md
knowledge-base/architecture/decisions/ADR-XXYC-stripe-secret-store-substrate.md
knowledge-base/architecture/decisions/ADR-XXYD-shared-payment-tokens-substrate.md
knowledge-base/engineering/ops/runbooks/stripe-projects-incident-response.md
knowledge-base/engineering/ops/runbooks/gdpr-erasure-vendor-actions.md
docs/legal/terms-and-conditions.md (additions only)
docs/legal/privacy-policy.md (additions only)
docs/legal/acceptable-use-policy.md (additions only)
plugins/soleur/docs/pages/legal/data-protection-disclosure.md (additions only)
knowledge-base/legal/compliance-posture.md (row additions for Stripe Secret Store + Shared Payment Tokens)
```

**Cuts vs prior post-review draft:** removed `webauthn/*` route handlers, `stripe-projects-failure-card.tsx`, `migration 038_vendor_webauthn_attestations.sql`, `cron/vendor-actions-reconcile.ts`, byok-encrypted-token columns in migration 037. **Added (deepen pass):** 7 ADRs, Stripe Secret Store + Shared Payment Tokens modules, `account-deauthorized` webhook handler, proactive refresh cron, `mandate_ceiling_cents` column + banner component, `audit-log/query` route + agent tool, `consent/abort` route, `processed_stripe_events_subscription_updated` migration, GDPR erasure runbook, ~10 new test files.

## Files to Edit

```text
apps/web-platform/lib/feature-flags/server.ts
apps/web-platform/server/agent-env.ts (add stripe-projects + STRIPE_LOG=info enforcement)
apps/web-platform/server/observability.ts (add pre-Sentry token-redactor scope for stripe-projects breadcrumbs)
apps/web-platform/server/providers.ts (add stripe-projects entry)
apps/web-platform/server/agent-runner-tools.ts (register stripe_projects_add + vendor_actions_audit_query as agent-callable)
apps/web-platform/lib/stripe.ts (no edit; reuse via getStripe())
apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx (add Stripe Projects + Shared Payment Tokens connection card)
apps/web-platform/app/(dashboard)/layout.tsx (sidebar entry for Connected Services)
apps/web-platform/app/api/webhooks/stripe/route.ts (add customer.subscription.updated handler for mandate-ceiling re-consent)
plugins/soleur/agents/operations/ops-provisioner.md
plugins/soleur/agents/operations/service-automator.md
plugins/soleur/agents/operations/references/service-deep-links.md
plugins/soleur/docs/pages/agents.njk
plugins/soleur/docs/pages/pricing/index.njk
plugins/soleur/docs/_data/site.json
plugins/soleur/docs/_includes/base.njk
plugins/soleur/docs/llms.txt
knowledge-base/operations/expenses.md (Spend Cap + Mandate Ceiling columns)
knowledge-base/project/specs/feat-agent-native-cloudflare-signup/spec.md (Phase 0 spike updates)
knowledge-base/product/roadmap.md (Phase 4 entry linked to #3106)
vercel.json (cron entry for stripe-connect-refresh)
package.json (verify @stripe/connect-js + @stripe/stripe-js for browser SCA flow; verify NO @simplewebauthn/server)
```

Glob verification per `hr-when-a-plan-specifies-relative-paths-e-g`: each path mapped to a real codebase location during plan-time research; new paths are net-new.

## Open Code-Review Overlap

None — verified via `gh issue list --label code-review --state open` + per-path jq grep on 2026-05-03. (Re-run before merge per Phase 10 step 4.)

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Stripe Projects has no REST API; CLI is the only entry point | HIGH | Phase 0 spike confirms; module API stable through future REST swap. |
| Beta protocol breaking change mid-sprint | HIGH | Pin `stripe` ≥ 1.40.0 + `projects` plugin in Docker. Nightly contract test (TR7). Auto-disable flag on detection (TR17). |
| Orphan CF account if signup partially fails | HIGH | Inline orphan-detection in `add()` catch (Phase 3.7). Sentry-as-fallback-substrate (UI-1, TS9b). Hourly reconciliation cron deferred (#3113). |
| Cross-tenant credential bleed | HIGH (single-user incident) | Three-invariant email-match (fail-closed); idempotency keyed on `(userId, ...)`; RLS on every read; **Stripe Secret Store** for OAuth tokens (no per-user HKDF); `bash-sandbox` for subprocess; pre-Sentry token-redactor; pre-encryption PII redactor. |
| CLI's local `~/.config/stripe/` used for funded actions | HIGH (legal) | Architecturally enforced: cloud server is sole executor; CLI POSTs intent only. Best-practices §3. |
| Cold-signup email mismatch (user wanted personal email, got Stripe email) | HIGH (elevated UI-2) | Active email-confirm checkbox in modal (NOT passive copy). FAQ entry. |
| Cap-raise mid-flight race | LOW | cap_cents captured at consent-modal-render time; locked into audit row keyed by `consent_token_id`. Idempotency hash includes `cap_cents`. |
| Stripe Connect refresh-token expires (1 year) | MEDIUM (elevated UI-3) | **Proactive 6-month refresh cron in v1** (#3114 absorbed). Distributed lock prevents Nango-documented race. `account.application.deauthorized` webhook handler. |
| Audit-log JSONL export streaming a different user's rows | HIGH | RLS test TS13 + sentinel-email test extending TS13 (Sec-4). |
| Existing feature-flags module is global-only | MEDIUM | Extend with `getFlagForUser(name, ctx)` + per-flag cache TTL (Functional-discovery §Reuse 1, Perf-F5). |
| Sentry SDK partially shimmed | LOW | `reportSilentFallback` wraps Sentry calls in try/catch; pino is durable signal. |
| Hetzner billing pivots to Stripe during sprint | LOW | Defer to follow-on per spec TR14. Out of scope. |
| Provider-side (#3107) is invite-only via `provider-request@stripe.com` | LOW (deferred) | Update #3107 with finding; re-evaluation criteria documented. |
| **Subprocess cold-start latency cliff** | MEDIUM (NEW Perf-F1) | Phase 0 spike captures p50/p95/p99. Phase 4 conditional async-with-progress UX if p95 > 10s. Phase 10 load-test target. |
| **Audit-log export Vercel 30s timeout** | MEDIUM (NEW Perf-F4) | Phase 4.5 pre-ship benchmark. Streaming chunks if needed; cap reduction fallback. |
| **Flag-flip propagation lag during in-flight calls** | MEDIUM (NEW Perf-F5) | Cache TTL ≤ 30s. Phase 10 chaos test (TS24). Feature-flag check at intent-creation only (TS11b). |
| **PSD2 SCA non-compliance via agent-dismissed 3DS** | HIGH (NEW Best-practices §3) | Stripe Shared Payment Tokens substrate. Active 3DS user-tap-confirm (TS22). Stripe owns the SCA ceremony. |
| **GDPR Art. 17 erasure blocked by 6-year audit retention** | HIGH (NEW Data-F2) | Drop user FK; anonymization SQL + runbook. `anonymized_at` column. Privacy Policy aligned to capability (UI-4). |
| **Mandate-ceiling drift via vendor price change** | MEDIUM (NEW DRCF + Best-practices §3) | `mandate_ceiling_cents` column distinct from `cap_cents`. `customer.subscription.updated` webhook handler invalidates idempotency, surfaces re-consent banner (TS21). |
| **Stripe Secret Store availability dependency** | MEDIUM (NEW Reconciliation §7) | If Secret Store unavailable, fail closed at OAuth start; surface "Stripe service degraded" CTA. Phase 0 spike confirms availability + retrieval latency. |
| **Shared Payment Tokens API beta status / churn** | MEDIUM (NEW Reconciliation §8) | Same nightly contract test extended to Shared Payment Tokens schema. Auto-disable hook covers both. |

## Sharp Edges

- The `STRIPE_API_KEY` env var override pattern for subprocess invocation must NOT inherit from operator's shell — use `agent-env.ts`'s explicit allowlist + serviceTokens. `STRIPE_LOG=info` hard-set (NEVER `debug` per Sec-2).
- `vendor_actions_audit` is generic across protocols; do NOT name new audit columns with `stripe_` prefix unless Stripe-specific. Future protocols share the table.
- Vendor identity at top level — `vendor text NOT NULL indexed`. Do NOT bury vendor slug in `provider_metadata jsonb` — cross-protocol queries become branched JSON-extract (Arch F3).
- `stripe projects catalog` returns 41 providers. Contract-test fixture vendor-specific (`jq '.cloudflare'`).
- HMAC `consent_token_id` secret is JSON-map with `kid` rotation (Sec-3); quarterly rotation runbook; alert on rows with kid older than 6 months.
- `webhooks/stripe/route.ts` already exists; new flow extends it for `customer.subscription.updated` (mandate-ceiling re-consent) and adds new endpoint for `account.application.deauthorized`.
- New skill `vendor-signup` token-budget check at plan-write time; description ≤ 30 words.
- Migration 035 must NOT use `CREATE INDEX CONCURRENTLY` (Supabase tx-wrapped — SQLSTATE 25001).
- App Router route files under `app/api/**` only export HTTP handlers per `cq-nextjs-route-files-http-only-exports`. Standalone CLI consent page lives at `app/consent/[id]/page.tsx`.
- `consent_token_id` URL is short-lived (5min TTL); CLI plugin surfaces error if user takes longer. Document in `vendor-signup` skill body.
- **Idempotency hash MUST NOT include `consent_token_id`** but MUST include `cap_cents` (Sec-7).
- **Email-match assertion must check THREE invariants** (Kieran fix #2 retained).
- **Stripe Connect refresh-token storage = Stripe Secret Store, NOT byok columns** (Reconciliation §7). byok pattern reserved for user-supplied entropy, not server-issued secrets.
- **First-charge SCA ceremony lives in Stripe Shared Payment Tokens flow, NOT Soleur modal-dismiss** (Reconciliation §8). User actively taps; Soleur waits for Stripe's outcome.
- **Mandate ceiling distinct from spend cap**: cap = total $/month bound; ceiling = per-charge price-change re-consent trigger. Both stored at consent time, locked into audit row.
- `vendor_actions_audit` two-table model: mutable head + INSERT-only history. UPDATEs allowed on head via service role; trigger writes history row. Append-only is the history table, NOT the head (Data-F1).
- `user_id` is NOT a FK on `users`. Anonymization SQL severs the link via NULL (Data-F2). Postgres won't enforce — runbook + test must (extended TS13).
- All Postgres types use `text + CHECK` (NOT enum) per Data-F4. Adding states is a `DROP CONSTRAINT` + `ADD CONSTRAINT` migration.
- Status endpoint requires Soleur PAT bearer bound to `consent_token_id`; reject mismatches as 404 (not 403, to avoid enumeration — Sec-6).
- bash-sandbox tempdir: `mkdtemp` 0700, try/finally `rm -rf` on panic (Sec-8). TS18 verifies.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is concrete; do not regress.

## Open Questions

Carried forward from brainstorm + spec-flow + research + deepen pass:

1. **REST surface confirmation.** Phase 0 spike answers; if YES, Phase 3 `stripe-projects/index.ts` swaps implementation behind same module interface.
2. **OAuth scope granularity.** Per-provider or account-wide? Affects whether each new vendor (post-v1) re-prompts.
3. **CF token lifetime.** Long-lived API token (assumed) or short-lived with refresh? Determines re-encryption cadence.
4. **CF account email source.** Confirmed: Stripe-attested email, no override (Research §5). Surfaced in consent copy.
5. **Cap-exceeded webhook.** Does Stripe Projects emit one? If no, poll Cloudflare Budget Alerts API hourly.
6. **DPIA self-assess vs external.** Out of scope for US v1; tracked under EU-rollout follow-on.
7. **Audit-log retention.** Confirmed: 6 years tiered (Best-practices §2). v1 hot-only; cold-tier deferred (#3112). Privacy Policy aligned to capability per UI-4.
8. **Hetzner long-term posture.** Confirmed: stays Playwright/Terraform indefinitely. Out of scope.
9. **Plan-selection UX.** Default free-tier; agent reasoning surfaces "why this plan" rationale to modal.
10. **CF email-verification race.** Token works for API even before email verified; modal copy notes "verify your email at the link Cloudflare sends to use the dashboard."
11. **Concurrent same-user lock.** Implemented via `vendor_actions_idempotency` row state machine — `pending` rows TTL out at 5min; second attempt during window returns `flow-pending-elsewhere`.
12. **Auto-disable feature flag on protocol drift.** Implemented via Phase 9.
13. **Reconciliation job for orphans.** v1 inline detection (Phase 3.7) + Sentry-as-fallback-substrate (UI-1). Hourly cron deferred (#3113).
14. **Sentry-mirror fallback.** Sentry call wrapped in try/catch already; pino is durable signal. Disk-buffered events out of scope for v1.
15. **CLI plugin Stripe-account-mismatch.** Architecture pivot makes this moot — CLI plugin no longer uses local `stripe login` for funded actions.
16. **Idempotency `requested-resource` granularity.** Hash = `sha256(userId || provider || resource || plan_id || cap_cents || day_bucket)`. NOT `consent_token_id` (Kieran #1). INCLUDES `cap_cents` (Sec-7).
17. **Email-mismatch user-facing message.** "We blocked this provisioning for security: Cloudflare returned an account that doesn't match your Stripe email. Support has been paged. No charge has been made." With ticket ID.
18. **ops-provisioner fallback consent re-prompt.** During 2-week rollback window: if Stripe Projects fails mid-flight and Playwright fallback engages, surface "switching to legacy flow — re-confirm?" modal.
19. **Anchor launch post timing.** Depends on Sprint Re-Evaluation outcome (a)/(b)/(c).
20. **SCA substrate.** Confirmed: Stripe Shared Payment Tokens (Reconciliation §8, Best-practices §3). Active 3DS user-tap-confirm; Stripe owns ceremony.
21. **OAuth token storage substrate.** Confirmed: Stripe Secret Store (Reconciliation §7, Best-practices §1). Stripe holds encryption-at-rest substrate.
22. **Mandate ceiling lifecycle.** Captured at consent; `customer.subscription.updated` webhook invalidates on price change; user sees re-consent banner.
23. **Subprocess pool decision.** Depends on Phase 0 spike cold-start measurement. If p95 > 5s under 50-concurrent load, Phase 3 adds `piscina`-style pool.

## Deepen-Plan Synthesis Appendix

8 parallel agents ran on the post-review plan (security-sentinel, architecture-strategist, data-integrity-guardian, agent-native-reviewer, user-impact-reviewer, ddd-architect, performance-oracle, best-practices-researcher). Findings synthesized into:

- **Reconciliation rows §6–§10** (5 new external-research-driven reconciliations)
- **CRITICAL fixes folded into Acceptance Criteria**: two-table audit model (Data-F1), GDPR FK drop (Data-F2), Stripe Secret Store substrate (Sec-1 + BP §1), Shared Payment Tokens substrate (Sec-5 + BP §3), Phase 0 cold-start spike (Perf-F1)
- **HIGH fixes**: idempotency table reversal (DDD F4 + Data-F3), 3-folder re-layer (DDD F1+F2 + Arch F6), top-level vendor column (Arch F3), crash-recovery atomic transaction (Arch F1), 6 agent-parity API surfaces (P1-P6), 4 user-impact severity calibrations (UI-1 through UI-4), proactive refresh cron + distributed lock (Reconciliation §9)
- **MEDIUM fixes**: token-redactor for Sentry breadcrumbs (Sec-2), HMAC `kid` rotation (Sec-3), pre-encryption PII redactor (Sec-4), idempotency `cap_cents` inclusion (Sec-7), bash-sandbox tempdir contract (Sec-8), `text + CHECK` over enum (Data-F4), cap_cents source-of-truth (Data-F5), polling cadence + cache (Perf-F3), pre-ship export benchmark (Perf-F4), flag-flip SLA (Perf-F5), `VendorActionCommand` typed value object (DDD F5)
- **NEW test scenarios**: TS9b, TS11b, TS18, TS19, TS20, TS21, TS22, TS23, TS24

D6 (#3114, 11-month re-prompt cron) absorbed into v1 — closed at merge.

Five new ADRs added to spike Phase 0 output beyond the original two.
