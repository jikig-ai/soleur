---
adr: 030
title: Inngest as durable trigger layer for server-side agents
status: accepted
date: 2026-05-17
related: [3244, 3940, 3947, 3948]
related_adrs: [ADR-005, ADR-023, ADR-027]
related_plans:
  - knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md
  - knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md
brand_survival_threshold: single-user incident
---

# ADR-030: Inngest as durable trigger layer for server-side agents

## Status

**Accepted** (2026-05-17, PR #3940).

Flipped from `proposed` at Phase 6 of `2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md` after the substrate landed green: Inngest client + serve route (Phase 2), CFO function with single-pass verify + per-step lease (Phase 3), Stripe `invoice.payment_failed` → `inngest.send` bridge gated by `SOLEUR_FR5_ENABLED` (Phase 4), `/api/dashboard/today` + page-level disclosure banner (Phase 5).

## Context

PR-A through PR-E (#3240, #3395, #3854, #3883, #3922) shipped the security/isolation hardening required to safely run autonomous agents on behalf of multiple founders: user-scoped Supabase JWT minting, `audit_byok_use` writer at every BYOK SDK call path, `is_jti_denied` JWT-mint consumer, RLS-bound attachments. The runtime is now safe to run *synchronous* workloads on behalf of a logged-in founder.

The parent epic (#3244) calls for *autonomous* leaders that react to inbound events while the founder sleeps:

- Inbound-event-to-leader pipelines (Stripe failed-payment, GitHub issue created, KB drift detected).
- Cross-domain priority arbitration ("Today" surface).
- Cron-driven background analyses.

Without a durable trigger substrate, these are unbuildable. PR-F (this slice) chooses the substrate.

Brand-survival threshold: `single-user incident`. Operator (2026-05-17) confirmed all-of-the-above failure framing — cross-tenant data leak, BYOK credential leak, wrong-action while founder sleeps, billing surprise. The substrate decision is load-bearing for all four vectors.

## Decision

**Adopt Inngest as the durable trigger layer for server-side agents. Deploy the OSS `inngest` server binary (`inngest start`) self-hosted alongside the existing Node process on the Hetzner host. SQLite for state persistence (alpha-default). Bound to `127.0.0.1` only.**

The Node application uses `inngest@^3` SDK and exposes `/api/inngest` via `serve()`. Events are sent via `inngest.send(...)` to the local server endpoint `http://127.0.0.1:8288`.

## Rejected alternatives

### Inngest Cloud (Hobby / Pro)

**Rejected.** Routing founder-tagged event payloads (Stripe `customer_email`, draft response text, `founderId`) through Inngest Cloud creates a 5th sub-processor and a corresponding DPA / Article 30 / Privacy Policy / DPD / GDPR Policy / sub-processor-page / breach-runbook update cycle. PR-B→E spent five increments keeping founder data off external substrates inside the EU-only Hetzner posture; inverting that ladder for alpha velocity contradicts the brand-survival threshold.

**Re-evaluation criteria** (operator-confirmed):

1. **Concurrency cap pressure.** Hobby tier limits to 5 concurrent steps; Pro is $75/mo (corrected from umbrella spec's $25 — verified at plan time). When self-hosted concurrency on the Hetzner box becomes the bottleneck OR a tenant-cost-fairness primitive requires Cloud-hosted multi-tenant queuing, re-open.
2. **Third hosted founder onboarded.** At 3 active founders, the operational cost of running the OSS Inngest server (process supervision, upgrades, SQLite-to-Postgres migration if needed, debugging UI absence) MAY exceed the legal-surface cost of a 5th sub-processor. Re-evaluate.

### LangGraph + custom orchestration

**Rejected.** Operationally heavy (separate worker pool, separate state store, separate retry semantics). Forces a duplicate "what's next" implementation alongside the existing `step.run` model. Inngest's batteries-included primitives (concurrency CEL, schema versioning, signed webhooks, replay-window, dashboard) ship correctness PR-F would otherwise hand-roll.

### Bedrock AgentCore (AWS)

**Rejected.** AWS vendor lock; no EU-residency parity with the current Hetzner posture; would add AWS as a sub-processor (same disclosure cycle as Inngest Cloud above).

### Cloudflare Durable Objects + LISTEN/NOTIFY

**Rejected.** Cannot host the Claude Agent SDK long-running process (DO execution model is incompatible with multi-minute SDK turns). LISTEN/NOTIFY in Supabase Postgres lacks durable replay and would require custom dead-letter + retry implementation on top.

## Load-bearing invariants

The following invariants are LOAD-BEARING. Violation = brand-survival regression at `single-user incident` threshold. Each is enforced by code, test, or DB constraint per PR-F's implementation plan.

### I1 — BYOK lease opened INSIDE each `step.run` that calls the Anthropic SDK

`AsyncLocalStorage` at `apps/web-platform/server/byok-lease.ts:115` does NOT survive across Inngest step-replay boundaries. Every `step.run("name", async () => { ... })` that calls the SDK MUST open its own `runWithByokLease(founderId, async (lease) => { ... })` scope. Outer-scope lease reuse triggers the sync-escape check at `byok-lease.ts:133–139` → `ByokLeaseError("escape")` → fail-closed.

**Enforced by:** the existing `byok-audit-writer-sweep.test.ts` CI sentinel + the new alias-rename extension (RV3 / Phase 2 of PR-F plan).

### I2 — User-scoped Supabase JWT minted INSIDE each `step.run` that touches tenant data

`getFreshTenantClient(event.data.founderId)` runs per-step. The `is_jti_denied` consumer at `apps/web-platform/lib/supabase/tenant.ts:341` fires automatically on every fresh-client call. **Never cache JWTs across step boundaries via `event.data` or step return values.**

**Enforced by:** code review at PR-F Phase 3 + Phase 4 tests.

### I3 — Singleton concurrency per founderId (per function-name)

Each Inngest function declares `concurrency: [{ scope: "fn", key: "event.data.founderId", limit: 1 }]`. Function-name namespace is implicit (each function triggers on one event-name; Inngest v3 has no wildcard triggers).

**Enforced by:** the CEL key in the function declaration + a test asserting 5 events same `founderId` → exactly 1 runs, 4 blocked.

### I4 — Signature verification REQUIRED at startup

`serve()` is configured with `signingKey: process.env.INNGEST_SIGNING_KEY`. Missing key = throw at process boot, NOT log-and-continue. The Inngest server binary also requires the key (`inngest start --signing-key $INNGEST_SIGNING_KEY`).

**Enforced by:** `apps/web-platform/server/inngest/client.ts` module-load throw + `apps/web-platform/app/api/inngest/route.ts` module-load throw.

### I5 — "Drafts everywhere, sends nowhere" — DB-level CHECK constraint AND code

The `messages_external_tier_status_check` constraint on `public.messages` (migration 046) enforces `status IN ('draft', 'archived')` for `tier IN ('external_brand_critical', 'external_low_stakes')`. Any future code attempting to INSERT `status='sent'` on an external-tier row is rejected at DB level with SQLSTATE 23514.

**Future auto-send capability** (e.g., a class that would transition from `draft` → `sent` for an external tier) requires (a) explicit migration to DROP and replace this constraint, (b) Article 22(3) right-to-human-review notice and DPD update, (c) re-amendment of this ADR.

**Enforced by:** Postgres CHECK constraint + Phase 1 test.

### I6 — Verify-external-state is single-pass-only

`step.run` memoizes results. On a 6h-deadlettered retry, a checkpointed verify result becomes stale (Stripe state may have moved `failed → succeeded → refunded`). PR-F's CFO function therefore does NOT split verify into a `step.run` artifact that downstream steps consume by reference; verify lives in the function body and is recomputed on each pass.

Any future code adding a step.run-checkpointed verify whose result feeds a downstream draft MUST first amend this ADR to either (a) split verify into a watchdog + last-call-before-fire pattern, or (b) bound the deadletter window such that staleness is acceptable.

**Enforced by:** code review at PR-F Phase 3 + a test asserting any retry path re-enters from verify.

## Implementation references

- Plan: `knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md` (v2, post-review)
- Spec: `knowledge-base/project/specs/feat-pr-f-inngest-trigger-layer/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
- Parent plan (Increment 3 is PR-F): `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` §3.1–3.5
- Parent epic: [#3244](https://github.com/jikig-ai/soleur/issues/3244)
- Predecessor PRs (all MERGED, verified /work Phase 0.1 2026-05-17): #3240, #3395, #3854, #3883, #3922
- Follow-up issues: #3947 (PR-G cohort onboarding), #3948 (cron migration TR9)

## Trade-offs accepted

- **Operational cost.** Self-hosted Inngest adds a sidecar process (systemd unit, upgrade cadence, no debugging UI for non-Pro). Mitigated by: SQLite default (zero new persistence config), `Restart=always`, `127.0.0.1` binding.
- **No Cloud dashboard.** The OSS server has a basic UI; not the Pro debugging surface. Acceptable for alpha (operator + 1 dogfood founder). Re-evaluate per criteria above.
- **SQLite single-host limitation.** State persistence is local-disk; no high-availability. Mitigated by: Hetzner backups, Inngest's redelivery semantics (Stripe redelivers webhooks for ~3 days; missed events recoverable). Migration to Postgres-backed Inngest deferred to future PR if/when warranted.

## Updates / amendment log

(Empty at proposed time. Future amendments appended here with date + rationale.)
