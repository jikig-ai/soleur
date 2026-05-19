# Feature: Agent-Native Cloudflare Signup via Stripe Projects

## Problem Statement

Soleur agents currently cannot provision a Cloudflare account for a user without a human in a browser. The `ops-provisioner` agent uses Playwright MCP for cold signup, which (a) requires the user to enter credentials/payment manually, (b) is fragile across vendor UI changes, and (c) carries an unresolved agency-liability concern from the CLO that has the Playwright vendor-signup track deferred on the roadmap pending a dedicated legal framework. Two prior learnings (`2026-03-25-check-mcp-api-before-playwright`, `2026-04-07-buttondown-onboarding-multi-account-playwright`) already establish that Playwright is the last-resort tier when an API or programmatic surface exists.

On 2026-04-30, Cloudflare and Stripe announced **Stripe Projects** (https://blog.cloudflare.com/agents-stripe-projects/), an open-beta agent-native protocol where (i) the user authenticates to Stripe once via OAuth/OIDC, (ii) the agent runs `stripe projects add cloudflare/<resource>` programmatically, (iii) Stripe attests user identity to Cloudflare and issues a payment token (raw card never touches Soleur or the agent), (iv) Cloudflare auto-provisions a new account if one does not exist for the user's email, and (v) returns scoped credentials the agent can store and use. Default $100/mo per-provider agent spend cap, raisable via Cloudflare Budget Alerts.

Adopting Stripe Projects for Cloudflare cold-signup replaces the Playwright path for that vendor specifically and inserts a new top tier above MCP/API/Playwright in the `hr-exhaust-all-automated-options` priority chain.

## Goals

- A Soleur user, in either cloud chat (`app.soleur.ai`) or the CLI plugin (Claude Code), can ask an agent to set them up on Cloudflare and the agent does so via Stripe Projects without the user navigating to `dash.cloudflare.com`.
- Cold signup works end-to-end (no pre-existing Cloudflare account required).
- The Cloudflare API token returned by Stripe Projects is encrypted at rest using the existing `byok.ts` AES-256-GCM HKDF pattern and surfaced to the existing Cloudflare MCP for downstream management.
- Every `stripe projects add` invocation passes through a per-action consent modal that shows the provider, plan, recurring amount, and Approve/Cancel options. No session-bounded auto-approve in v1.
- US-only at v1, gated by feature flag. EU rollout follows DPIA + GDPR-trio updates.
- Soleur-side default spend cap of $25/mo per provider per user (raisable to Stripe's $100 default), enforced via Cloudflare Budget Alerts API.
- The Cloudflare cold-signup path in `ops-provisioner` is retired behind a feature flag with a 2-week rollback window to Playwright.
- An immutable, append-only, user-exportable audit log captures every `add()` invocation (user prompt, resolved tool call, provider, plan, amount, idempotency key, Stripe Project ID, timestamp) — GDPR Art. 15 ready from day one.
- Anchor launch content (blog post, HN, X, LinkedIn) ships within the 14-day first-mover window from Cloudflare's 2026-04-30 announcement.

## Non-Goals

- Provider-side participation (Soleur listed in the Stripe Projects catalog so other agents can subscribe their users to Soleur). Tracked as a separate deferred GH issue with re-evaluation triggers.
- Stripe Projects adoption for vendors other than Cloudflare. Vercel/Supabase/Resend wait for catalog inclusion + dual-path; GitHub/Hetzner stay on Playwright/Terraform indefinitely (per COO vendor-coverage map).
- EU launch. EU rollout is a follow-on, gated on DPIA + Privacy Policy + Data Protection Disclosure + GDPR Policy updates.
- Session-bounded auto-approve under a user-set cap. Per-action modal only in v1.
- Resolution of the broader "agency liability for agent-driven actions" legal framework. Stripe Projects narrows the surface (Stripe attests payment) but does not eliminate the framework need (Stripe does not attest *intent* on plan choice). Out of scope; tracked separately under the existing CLO legal-framework deferral.
- Replacing the existing Cloudflare MCP (`https://mcp.cloudflare.com/mcp`) for managing accounts post-signup. Stripe Projects covers cold-signup only; the existing MCP remains the management surface afterward.

## Functional Requirements

### FR1: Cloud chat entry point

A user message in cloud chat that expresses intent to provision Cloudflare (e.g., "set me up on Cloudflare", "add Cloudflare Workers to my project") is routed by the existing chat router to a flow that invokes the shared Stripe Projects core. The flow renders the per-action consent modal in chat, captures Approve/Cancel, then dispatches the call. Output is rendered in chat as a structured success/failure card with provider, plan, amount, and a link to the audit-log entry.

### FR2: CLI plugin entry point

A Soleur slash command (e.g., `/soleur:vendor-signup cloudflare`) invokes the shared Stripe Projects core through a thin shim. The plugin uses the user's local `stripe` CLI on PATH (token in `~/.config/stripe/`). Per-action consent is rendered in the terminal as a structured prompt; the user types `y` / `n` / `details`. Output is rendered as a structured success/failure block.

### FR3: Per-action consent modal

Every `stripe projects add` call surfaces a confirmation that includes: provider name, plan, recurring amount and currency, one-time charge if any, the Stripe Projects spend cap currently in force, and Approve/Cancel. No session-bounded auto-approve. Cancel returns immediately without invoking the protocol.

### FR4: Cold-signup path

When the Stripe-attested user email has no existing Cloudflare account, Cloudflare auto-provisions one and returns scoped credentials. The flow renders a "new Cloudflare account provisioned" notice in the consent confirmation and surfaces the new account's email + login URL after success.

### FR5: Audit log

Every `add()` invocation writes an immutable, append-only audit-log row with: user prompt (verbatim), resolved tool call (provider + opts), idempotency key, Stripe Project ID, Cloudflare account email (post-signup), plan, recurring amount, status, timestamps. The user can export their full log via a `/audit-log/stripe-projects/export` endpoint (cloud) or a `/soleur:audit-log export` slash command (CLI). The log stores the CF API token *reference* only — never the cleartext token.

### FR6: Spend-cap configuration

A new user starts with a Soleur-side default cap of $25/mo per provider. The user can raise their cap to Stripe's $100 default (or above, via Cloudflare Budget Alerts) through a settings page in cloud chat or `/soleur:vendor-signup config` in the CLI plugin. Cap changes are themselves audit-logged.

### FR7: US-only geo-gating

The feature is gated by a feature flag that allows the flow only for users whose Stripe-attested billing country is US. Non-US users see a "Available in your region soon" message with a link to a status page.

### FR8: ops-provisioner Cloudflare path retirement

The existing Cloudflare cold-signup branch in `plugins/soleur/agents/operations/ops-provisioner.md` is gated by a feature flag that prefers the Stripe Projects path when available and falls back to Playwright for a 2-week rollback window. After the rollback window, the Playwright Cloudflare branch is removed; the agent's Cloudflare entry exclusively uses Stripe Projects.

### FR9: Launch surfaces

A new `/integrations/stripe-projects` page is created. The `/agents/`, `/pricing`, `llms.txt`, and homepage hero pick up Stripe-Projects-related copy per the CMO assessment. The anchor launch post ("We deleted our Playwright signup flow the day Cloudflare shipped Stripe Projects") publishes to blog, HN, X, LinkedIn, and dev.to within the 14-day window.

## Technical Requirements

### TR1: Shared core module

`apps/web-platform/server/stripe-projects/` exports `init()`, `catalog()`, `add(provider, opts, { idempotencyKey, userId })`, `revoke()`. REST-first: prefers the Stripe Projects HTTP API; falls back to the `stripe` CLI subprocess only when REST is unavailable. The CLI plugin skill calls the same module via a thin shim. Both paths share idempotency, audit-log writes, and Sentry mirroring. Versioned via `stripe-projects/v1.ts` adapter for beta-protocol churn.

### TR2: Per-user workspace isolation

Cloud-platform invocations run inside the user's sandboxed agent process (existing `bash-sandbox.ts` model) with `HOME=/workspaces/<userId>` and `STRIPE_CONFIG_PATH=$HOME/.config/stripe` enforced explicitly in `agent-env.ts`. A workspace-isolation test asserts that no other user's Stripe config is reachable from a given user's sandbox.

### TR3: Cross-tenant credential bleed mitigation

Every `add()` call wraps `{stripeAccountId, userId, idempotencyKey}` in a transactional bind *before* the network call. Post-call, the returned Cloudflare account's email is asserted to match the user's verified Stripe-attested email; on mismatch, the call fails closed (no token surfaced) and writes a Sentry incident. The audit-log row is written before the token decryption surfaces it to the agent.

### TR4: Idempotency

Idempotency key = `hash(userId, provider, requested-resource)`, persisted to a transactional store (Postgres `stripe_projects_idempotency` table) before the network call. Duplicate calls within a 24-hour window return the cached response. RLS ensures rows are scoped per user.

### TR5: byok-encrypted token storage

The Cloudflare API token returned by Stripe Projects is encrypted at rest using the existing `apps/web-platform/server/byok.ts` AES-256-GCM HKDF pattern (`byok-key`-derived per-user key). Decryption surfaces the token only to the user's own sandboxed agent process. The token is also surfaced to the existing Cloudflare MCP via the existing token-passthrough channel for downstream management.

### TR6: Silent-fallback Sentry mirror

Every catch block in the Stripe Projects core that returns a degraded result calls `reportSilentFallback(err, { feature: 'stripe-projects', op, userId })` per `cq-silent-fallback-must-mirror-to-sentry`. The receiving Cloudflare token is NOT surfaced to the agent on degraded paths until the email-match assertion (TR3) passes.

### TR7: Beta-protocol drift detection

A nightly CI job runs a contract test against Stripe's published Stripe Projects OpenAPI spec. On schema drift, the job fails and posts a GitHub issue tagged `stripe-projects-protocol-drift`. The `stripe` CLI version is pinned in the workspace Docker image.

### TR8: US-only feature flag

A new feature flag `stripe-projects-cloudflare-us` gates the entire flow. The flag's predicate reads the user's Stripe-attested billing country via the Stripe API (cached per session). Non-US returns a 451-equivalent surface in cloud chat and a `region-not-supported` error in the CLI plugin.

### TR9: Audit-log table

A new `stripe_projects_audit` Postgres table with append-only INSERT-only RLS, columns: id, user_id (FK), prompt_text, tool_call_json, idempotency_key, stripe_project_id, cf_account_email, provider, plan, amount_cents, currency, status, created_at. RLS scopes reads to the row owner. Export endpoint streams the user's rows as JSONL.

### TR10: Migration with `SECURITY DEFINER` rules

If any new SQL function uses `SECURITY DEFINER`, it must `SET search_path = public, pg_temp` (in that order) and qualify every relation as `public.<table>` per `cq-pg-security-definer-search-path-pin-pg-temp`.

### TR11: Architecture Decision Record

Before `/work`, an ADR (`/soleur:architecture create "Adopt Stripe Projects protocol for Cloudflare vendor cold-signup"`) captures (a) REST-first vs CLI-subprocess decision, (b) consumer-only vs consumer+provider scope decision, (c) shared-core vs duplicated-paths decision. CTO sign-off.

### TR12: Plan-time review gates

Per `hr-weigh-every-decision-against-target-user-impact` with `Brand-survival threshold: single-user incident`, the plan inherits CPO sign-off and the `user-impact-reviewer` conditional review agent at PR time. The plan also inherits the legal-artifact gate: ToS addendum, Privacy Policy update, AUP update, and audit-log schema must land in the same PR (or a chained PR merging before the feature flag flip).

### TR13: Spike outputs

The 1-2 day spike must produce documented answers to: (i) Stripe Projects REST surface presence and shape, (ii) OAuth scope granularity per-provider vs account-wide, (iii) returned CF token lifetime + refresh, (iv) CF account email source, (v) cap-exceeded webhook surface, (vi) rate-limit semantics. Spike output is a markdown ADR appendix that the plan references.

### TR14: Hetzner stays Playwright

Hetzner is explicitly out of Stripe Projects scope (SEPA-first, non-Stripe biller). The `ops-provisioner` Hetzner branch is untouched. Confirmed via `ops-research` before final spec; if Hetzner's billing posture changes during the sprint, defer the change to a follow-on issue.

### TR15: Sandboxed CLI invocation

When the CLI fallback path runs `stripe projects add ...` as a subprocess in the cloud platform, it runs under `bash-sandbox.ts` with the user's `HOME` enforced (TR2). No privileged service-account context.
