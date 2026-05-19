---
title: Agent-Native Cloudflare Signup via Stripe Projects
date: 2026-05-03
issue: "#3106 (consumer side, active); #3107 (provider side, deferred); parent thematic #1287"
status: complete
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# Brainstorm: Agent-Native Cloudflare Signup via Stripe Projects

## What We're Building

A consumer-side adoption of the Stripe Projects protocol Cloudflare announced on 2026-04-30 (https://blog.cloudflare.com/agents-stripe-projects/), so a Soleur agent can subscribe a user to Cloudflare in one programmatic step (`stripe projects add cloudflare/...`) instead of driving the dashboard via Playwright. Stripe attests the user's identity (OAuth/OIDC) and issues a payment token to Cloudflare; the raw card never touches Soleur or the agent. Cold signup is supported — if the user has no existing Cloudflare account for their Stripe-attested email, Cloudflare provisions one automatically.

Scope is the **consumer side only**. The provider side (Soleur listed in the Stripe Projects catalog so other agents can subscribe their users to Soleur) is deferred to a tracked GitHub issue, candidate parent #1287 ("agent-native discovery & procurement").

Both Soleur entry points get the capability in the same sprint:
- **Cloud chat** (app.soleur.ai) — user says something like "set me up on Cloudflare"; the chat router invokes the flow.
- **CLI plugin** (Claude Code) — a Soleur slash command that shells out to the same shared core.

## Why This Approach

The existing `ops-provisioner` agent uses Playwright MCP for vendor cold-signup. Two prior learnings established that this is the last-resort tier (`2026-03-25-check-mcp-api-before-playwright`, `2026-04-07-buttondown-onboarding-multi-account-playwright`), and the roadmap has a CLO deferral on Playwright vendor signup pending a dedicated agency-liability legal framework. Stripe Projects sits **above** the MCP/CLI/REST/Playwright tiers established by `hr-exhaust-all-automated-options` because Stripe attests user identity rather than the agent simulating a human in a browser. That materially shrinks (but does not eliminate) the agency-liability surface — Stripe attests payment; it does not attest *intent* on plan choice.

Architecture is REST-first with `stripe` CLI as a fallback, shared between cloud platform and CLI plugin. A single core module (`apps/web-platform/server/stripe-projects/`) encapsulates `init`, `catalog`, `add(provider, opts, { idempotencyKey, userId })`, `revoke`. The CLI plugin skill calls the same wrapper via a thin shim. Both code paths share idempotency keys, audit-log writes, Sentry mirroring on silent fallback, and per-user `$HOME/.config/stripe` isolation in workspaces.

The user explicitly chose a bundled all-at-once sequence (spike → ADR → plan → CLI + cloud + Playwright retirement in one sprint) over the recommended phased CLI-first sequence. Trade-off accepted: every blocker delays the launch post and the CMO 14-day first-mover window is taken as the binding constraint.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Scope: consumer side only (A); provider side (B) deferred to GH issue with re-evaluation triggers. | Tighter spec, smaller blast radius, validation gap on provider side (no current external demand signal). CPO recommendation. |
| 2 | Two entry points in the same sprint: cloud chat and CLI plugin. | AGENTS.md `agent-native-architecture` parity rule — anything a user can do, an agent can do. Single shared core eliminates code-path divergence. |
| 3 | Per-action consent UX: every `stripe projects add` shows provider, plan, recurring amount, Approve/Cancel. No session-bounded auto-approve in v1. | CLO: GDPR Art. 4(11) "specific, informed, unambiguous"; CRD Art. 8(2) distance contract pre-disclosure; required by `single-user incident` threshold. |
| 4 | Geographic launch: US-only at v1; EU after DPIA + GDPR-trio updates. | CLO: GDPR Art. 22 (automated decision with financial effect) + Art. 35 DPIA likely required. Matches Stripe Projects' own beta-launch posture. |
| 5 | Spend cap: Soleur-side default $25/mo per provider per user (raisable to Stripe's $100 default). | Reduces billing-surprise blast radius for first-week users; Soleur ToS adds a liability cap matching the user's configured Stripe cap. |
| 6 | Phase placement: Phase 4 hardening, post-spike. Bundled all-at-once sprint. | CPO: don't expand stale Phase 3 P0/P1 backlog. CMO: 14-day first-mover window. User accepted bundle-all-at-once trade-off. |
| 7 | Architecture: REST-first shared core in `apps/web-platform/server/stripe-projects/`, CLI subprocess fallback only when REST is unavailable. CLI plugin = thin shim over the same module. | CTO: avoid long-running shell in cloud, preserve testability, single source of truth for idempotency + audit logging. |
| 8 | Per-user workspace isolation for Stripe credentials: `HOME=/workspaces/<userId>`, `STRIPE_CONFIG_PATH=$HOME/.config/stripe`, encrypted via existing `byok.ts` AES-256-GCM HKDF pattern. | CTO blast-radius mitigation for cross-tenant credential bleed. Workspace isolation test required. |
| 9 | Idempotency: every `add()` call uses `hash(userId, provider, requested-resource)` persisted to a transactional store before the network call. | CTO: prevents duplicate provisioning on retry. Required for billing-surprise safety. |
| 10 | Replace `ops-provisioner` Cloudflare Playwright path behind a feature flag with 2-week rollback window. Other Playwright vendor paths untouched (Hetzner stays on Playwright/Terraform; Vercel/Supabase/Resend wait for catalog inclusion). | COO vendor-coverage map: Cloudflare adopt now, Vercel/Supabase/Resend wait + dual-path, GitHub/Hetzner stay Playwright. |
| 11 | Beta-protocol risk handled by: pinning `stripe` CLI version in workspace Docker image, versioned adapter (`stripe-projects/v1.ts`), nightly contract test against Stripe's published OpenAPI. ToS addendum reserves right to suspend on protocol breaking change with pro-rata refund. | CTO + CLO joint mitigation. |
| 12 | Audit log: append-only, user-exportable from day one (GDPR Art. 15 readiness). Schema captures user prompt, resolved tool call, provider, plan, amount, idempotency key, Stripe Project ID, timestamp. | CLO: dispute-defense + Art. 15 + Art. 22 audit substrate. |
| 13 | Silent-fallback enforcement: every catch block that returns degraded data must call `reportSilentFallback(err, { feature: 'stripe-projects', op, userId })` per `cq-silent-fallback-must-mirror-to-sentry`. The receiving Cloudflare token must NOT surface to the agent until the post-call assertion confirms the returned account email matches the user's verified email. | CTO + AGENTS.md: cross-tenant credential bleed mitigation. |

## User-Brand Impact

**Artifact at risk:** A user's Cloudflare account, the payment method backing it, and the Cloudflare API token returned to the agent.

**Vector:** Agent-initiated provisioning that misattributes account ownership, picks the wrong plan, or leaks credentials via logs/Sentry/audit-log read paths.

**Threshold:** `single-user incident` (per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`). All four impact vectors apply (billing surprise, credential leak, cross-tenant attribution, PII).

**Worst-outcome scenarios:**
- *Billing surprise:* Agent picks the wrong CF plan or provisions an unbounded Workers usage tier; user wakes up to a $99 charge they didn't authorize. Mitigation: per-action modal (#3), $25 default cap (#5), idempotency (#9).
- *Cross-tenant:* User A's Stripe session triggers a CF account attributed to user B. Mitigation: idempotency keyed on `userId` (#9), post-call email-match assertion (#13), workspace isolation (#8).
- *Credential leak:* CF API token returned by Stripe Projects logs to stdout, ends up in pino → Sentry trail visible to other users, or the audit log surfaces tokens in cleartext. Mitigation: byok encryption at rest (#8), redaction filter on Sentry mirror (#13), audit log stores token *reference* not value.
- *PII:* User email/business name forwarded to Cloudflare via Stripe Projects without coverage in our Privacy Policy. Mitigation: GDPR-trio updates (privacy-policy.md, data-protection-disclosure.md, gdpr-policy.md) before EU rollout (#4); US v1 ships with US-only Privacy Policy disclosure.

**Required reviewers at plan time:** CPO + `user-impact-reviewer` (per `hr-weigh-every-decision-against-target-user-impact`). Plan inherits `Brand-survival threshold: single-user incident`.

## Open Questions

1. **REST surface confirmation.** CTO Q1: does Stripe Projects expose a documented REST surface, or is the CLI the only entry point? Spike must answer this on day 1; affects whether cloud-side avoids subprocess entirely.
2. **OAuth scope granularity.** Can we request a token scoped to a single provider (`projects:cloudflare:add`) or only an account-wide grant?
3. **Returned CF token lifetime.** Long-lived API token, or short-lived with refresh? Determines re-encryption cadence.
4. **CF account email assertion.** When Cloudflare auto-provisions an account, is the email the Stripe-attested one or separately asserted? Foundational for cross-tenant verification (#13).
5. **Webhook surface.** Does Stripe Projects emit cap-exceeded events, or only Cloudflare? Determines monitoring path.
6. **DPIA self-assess vs external.** CLO Q3: is a self-assessed DPIA sufficient for US v1, or do we need external counsel before EU rollout?
7. **Audit-log retention period.** GDPR data-minimization vs dispute-defense balance. CLO recommends balancing test in `gdpr-policy.md`.
8. **Hetzner long-term posture.** COO assessment says Hetzner is unlikely to join Stripe Projects (SEPA-first, non-Stripe biller). Confirm via `ops-research` before final spec.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Recommends consumer-side only (A) with provider side (B) deferred to a tracked issue. Phase 4 hardening, not Phase 3 expansion. Stripe Projects partially unblocks the existing CLO Playwright deferral but does NOT fully resolve agency liability — Stripe attests payment, not intent on plan choice. Validation gaps: no beta-user signal yet for "agent provisions vendor for me"; competitive scan needed (Stripe Projects launched 5 days ago).

### Legal (CLO)

**Summary:** Materially safer than Playwright but does NOT replace the deferred agency-framework brainstorm. Required artifacts before US v1 ship: ToS addendum (agent mandate, Stripe Projects, beta deprecation, spend-cap liability), Privacy Policy update, AUP update, audit-log schema + retention policy, per-action consent UX legal sign-off. EU rollout gated on DPIA + GDPR-trio updates. Treat Stripe and Cloudflare as **independent processors** of the user, not sub-processors of each other.

### Engineering (CTO)

**Summary:** Architecture sketch: REST-first shared core in `apps/web-platform/server/stripe-projects/`, CLI subprocess fallback, CLI plugin = thin shim. Per-user workspace isolation (`HOME=/workspaces/<userId>`), `byok` encryption for returned CF tokens, idempotency keyed on `(userId, provider, resource)`, post-call email-match assertion to prevent cross-tenant credential bleed, Sentry mirror on every silent fallback. Beta protocol risk mitigated by versioned adapter + nightly contract test. Recommends ADR before `/work`.

### Marketing (CMO)

**Summary:** 14-day first-mover window from Cloudflare's 2026-04-30 launch. Anchor content piece: "We deleted our Playwright signup flow the day Cloudflare shipped Stripe Projects." Distribution: blog → HN → X thread → LinkedIn → dev.to. Page surfaces: net-new `/integrations/stripe-projects` (P0); `/agents/`, `/pricing`, `llms.txt`, homepage hero badge updates (P1-P2). Pricing communication: $25 Soleur cap is a feature ("agent-safe spending"), not a bug.

### Operations (COO)

**Summary:** Cloudflare adopt now via Stripe Projects (top tier above existing MCP/Playwright). Vercel/Supabase/Resend: wait for catalog inclusion + dual-path. GitHub/Hetzner: stay Playwright/Terraform indefinitely. `ops-provisioner.md` and `service-automator.md` tier order updates required. Expense ledger: net-new `Spend Cap` column + new `## User-Side Agent Spend (Stripe Projects)` section for visibility-only entries (not Soleur burn).

## Capability Gaps

| Gap | Domain | Why needed |
|-----|--------|------------|
| `stripe-projects-adapter` module (`apps/web-platform/server/stripe-projects/`) | Engineering | Net-new code module wrapping REST + CLI fallback. Single source of truth for idempotency and audit logging. |
| Contract-test runner against Stripe Projects OpenAPI | Engineering / Testing | Beta-protocol drift detection before users hit it. Nightly CI run. |
| Per-action consent modal component (cloud chat surface) | Product / Engineering | New UX surface required for `single-user incident` threshold. Legal sign-off on copy. |
| `/integrations/stripe-projects` page | Marketing | New top-of-funnel surface for the launch post. |
| Audit-log schema + user-export endpoint | Legal / Engineering | GDPR Art. 15 readiness from day one. |
| US-only feature flag plumbing | Engineering | Geo-gating for v1. |
| ToS addendum + Privacy Policy + AUP + Data Protection Disclosure + GDPR Policy updates | Legal | Pre-ship gate for US v1 (privacy disclosures); pre-ship gate for EU (full set + DPIA). |

## Provider-Side Tracking (Deferred)

A separate GH issue tracks the provider-side workstream: **#3107** — Soleur becomes a Stripe Projects vendor in the public catalog so other agents can subscribe their users to Soleur. Cross-linked as a concrete protocol implementation under parent thematic issue **#1287** ("agent-native discovery & procurement"). Re-evaluation triggers: (a) ≥3 paying Soleur users, (b) external demand signal (another agent's user requests "subscribe me to Soleur via projects"), (c) Stripe Projects out of beta with stable contract, (d) consumer-side #3106 stable in production for ≥3 months.

The active consumer-side tracking issue is **#3106**. Draft PR: **#3100**.
