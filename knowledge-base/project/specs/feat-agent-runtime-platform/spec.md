# Feature: Soleur Server-Side Agentic Runtime

> **Branding (decided 2026-05-05):** Single brand "Soleur" across CLI plugin + Web Platform; no "Command Center" sub-brand. Earlier brainstorm CMO recommendation superseded by user directive — one product, one brand, two surfaces. References to "Command Center" in this spec or the brainstorm reflect prior framing only.

**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-05-command-center-runtime-brainstorm.md`
**Issue:** [#3244](https://github.com/jikig-ai/soleur/issues/3244)
**PR:** [#3240](https://github.com/jikig-ai/soleur/pull/3240) (draft)
**Branch:** `feat-agent-runtime-platform`
**Brand-survival threshold:** `single-user incident`

## Problem Statement

Soleur Web Platform (`apps/web-platform/`) today runs synchronous WS-based Claude Agent SDK sessions per logged-in user. Three constraints prevent it from being the operator OS the roadmap describes:

1. **Cross-tenant isolation is paper-only.** `server/agent-runner.ts` instantiates Supabase with `SUPABASE_SERVICE_ROLE_KEY`, bypassing RLS. Acceptable for sync WS bound to a verified user; brand-ending the moment one process schedules autonomous work for N founders.
2. **Domain leaders have no memory.** Stateless one-shots; the runtime amplifies whatever signal they emit, so amnesia compounds. #1044 multi-turn continuity is a prerequisite for any background reactions.
3. **No proactive surface.** Solo founder lands in chat. There is no "what needs you today across your 8 domains" home page; cross-domain priority arbitration (the moat) is invisible.

The roadmap, brand guide, and Phase 1.10/1.11 already imply this work. Augment Cosmos's public preview crystallized the framing but is not the competitive target — Polsia, Lindy, Notion AI 3.3 are. This spec ships the runtime the roadmap implies.

## Goals

- Eliminate the service-role escape hatch for tenant-scoped operations; RLS becomes the enforced boundary.
- Land #1044 multi-turn continuity so leaders remember per-(founder, domain, conversation) context.
- Ship a Daily Priorities home page with one end-to-end Inngest-driven background trigger (Stripe failed-payment → CFO).
- Capture the architectural decision (Inngest agent kit) as an ADR with rejected alternatives.
- Establish the trust model: "Drafts everywhere, sends nowhere" + 5-tier per-action-class autonomy.
- Define the launch gate: closed free preview until E&O insurance, DPA, audit log, scope-grant UX are in place.

## Non-Goals

- **Not** a pivot vs Augment Cosmos. Cosmos is reference design, not competitor. Position vs Polsia/Lindy/Notion AI.
- **Not** server-side rewrite. Existing `server/agent-runner.ts` (durable Claude Agent SDK on Hetzner) stays; Inngest layers on top.
- **Not** Bedrock AgentCore (AWS lock), LangGraph + custom (operationally heavy), Cloudflare Durable Objects (can't host Agent SDK long-running process).
- **Not** the recall-vs-precision review-mode split (Cosmos borrow C). Deferred to follow-up.
- **Not** an episodic-vs-procedural compound classifier (Cosmos borrow B). Soleur mechanically ahead via existing placement gate; vocabulary borrow only.
- **Not** an Expert Registry with quality signals (Cosmos borrow D). Re-evaluate post-5-org adoption.
- **Not** paid tier launch in this scope. Closed free preview only.
- **Not** a marketing relaunch to public surfaces. CMO collateral (positioning refresh under the existing Soleur brand, landing page, demo video) tracked separately.

## Functional Requirements

### FR1: Per-invocation tenant isolation

`server/agent-runner.ts` must mint a user-scoped Supabase JWT per invocation (short TTL, founder's `auth.uid()` in claims). All tenant-data reads/writes go through the anon-key client with `setSession`. The service-role key is allowlisted to one server-side function: minting that JWT and writing audit rows. Cross-tenant leak becomes a privilege-escalation bug, not a one-line typo.

### FR2: BYOK lease + audit

BYOK keys decrypt on-demand inside an `AsyncLocalStorage` scope per invocation. Before each Anthropic call, write an `audit_byok_use` row (`{invocation_id, founder_id, agent_role, ts, token_count}`). Zeroize the lease on scope exit. Plaintext never logs to pino, never echoes to Sentry payloads (extend redaction allowlist per `cq-silent-fallback-must-mirror-to-sentry`).

### FR3: Multi-turn continuity (#1044)

Domain leaders persist conversation state per `(founder_id, domain, conversation_id)`. Storage shape: Postgres table with RLS, message history retrieved on each turn. Resumption recovers the agent's prior context without re-priming.

### FR4: Daily Priorities home page

Dashboard route `/dashboard` shows a "Today" card listing N items aggregated across at least 3 signal sources (e.g., GitHub open issues, Stripe events, KB drift). Each item has metadata: source, owning domain leader, suggested action, urgency. One-click "Let [leader] handle it" delegates to a background Inngest run.

### FR5: One end-to-end background trigger

Stripe failed-payment webhook → Inngest event `{founderId}.finance.payment_failed` → CFO leader runs in background → drafts a customer response + logs the expense → result surfaces as a "Today" card with draft attached. Demonstrates the inbound-event-to-cross-domain-cascade pattern.

### FR6: Trust-tier policy

Per-action-class autonomy enforced before any external-facing action:

| Tier | Default |
|---|---|
| Read/research/draft (KB writes, plan writes, internal artifacts) | Auto |
| Internal infra changes (commits to user repo on branch, no merge) | Auto + daily digest |
| External-facing low-stakes (draft tweet, draft email, internal Slack) | Draft + 1-click send |
| External-facing brand-critical (publish blog, send to customer, post to community) | Approve every time |
| Money/legal/credentials (charge, contract, BYOK rotation, prod migration) | Per-command ack |

Policy stored declaratively (Postgres or YAML; see Open Questions in brainstorm).

### FR7: Closed-preview launch gate

Web Platform serves invite-only access until: E&O bound ($1-3M), DPA template signed by sub-processors, forensic audit log live, scope-grant UX shipped, sub-processor public page, breach runbook documented, AUP updated, ToS updated with command-authority clause. No paid tier flag flips before all 9 land.

### FR8: ADR capture

`/soleur:architecture create "Adopt Inngest as durable trigger layer for server-side agents"` writes the ADR with: chosen substrate, rejected alternatives (LangGraph, Bedrock AgentCore, custom DO + LISTEN/NOTIFY), rationale, load-bearing invariants (per-invocation user-scoped JWT, per-invocation BYOK lease, per-(founder, domain, eventKey) in-flight cap).

## Technical Requirements

### TR1: Runtime substrate — Inngest agent kit

Library installed into existing Hetzner Node host. Inngest Cloud free tier covers alpha (50K steps/mo); paid tier triggers ~30 founders. Events keyed `{founderId}.{domain}.{event}`. Fan-out via `step.parallel`. One in-flight invocation per `(founderId, domain, eventKey)` to prevent ralph-loop pathology (`2026-03-13-ralph-loop-idle-detection-and-repetition`). Cron lives in Inngest, not GH Actions (sidesteps `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs`).

### TR2: Tenant isolation invariant

`createSupabaseClient` factory enforces user-scoped JWT for any tenant-data path. A linter rule (`no-service-role-in-runtime`) flags new uses of `SUPABASE_SERVICE_ROLE_KEY` outside the JWT-mint + audit allowlist. CI fails on violation. Belt-and-suspenders alongside RLS, mirroring `cq-pg-security-definer-search-path-pin-pg-temp` precedent.

### TR3: Episodic memory store

Per-founder pgvector table in their Supabase project. Schema: `(founder_id, domain, ts, vector, payload)`. RLS policy: row visible only to JWT with matching `auth.uid() = founder_id`. Indexed on `(founder_id, domain, ts)`.

### TR4: Procedural memory unchanged

AGENTS.md rules and skill definitions remain on the shared Hetzner host, symlinked into each per-founder workspace. No cross-tenant leak risk because these are open-source plugin content.

### TR5: Audit log forensic-grade

WORM (write-once read-many) storage; hash-chained rows; 7-year retention; replicated to R2 backend. Schema: `{agent_id, tenant_id, action_type, target_resource, authorizing_event, scope_grant_id, credential_used (ref only), outcome, timestamp, prev_hash, this_hash}`. Separate from pino/Sentry. Required for legal defensibility per CLO.

### TR6: Per-tenant cost attribution + kill-switch

Anthropic token counts attributed per-tenant via audit rows. Per-tenant cost ceiling configured (default $X/hr); soft alert at 50%, hard kill-switch at 100%, per-domain pause on threshold breach. Anomaly detector pages on-call on >3σ tenant-level cost spike in 1h.

### TR7: Observability

Grafana Cloud (free tier → $8/mo Pro at beta) + OpenTelemetry SDK in agent runtime. Sentry stays for errors. Per-tenant dashboards keyed on `founder_id`. PagerDuty (or Better Stack Incidents) for on-call rotation; runtime outage = founder revenue loss.

### TR8: Infra cost ceiling

Alpha ~$30/mo additional on top of current $569 Soleur baseline. Beta (50 founders) ~$300-400/mo. Gross margin per founder positive at $99 ARPU even before Inngest paid tier kicks in. Doppler stays for Soleur infra secrets only; per-tenant BYOK custody requires per-tenant envelope encryption (KMS or pgcrypto with HKDF-per-user — primitive already correct).

### TR9: Failure-mode prevention

Architecture must defend against documented patterns:
- `2026-03-23-skip-ci-blocks-auto-merge-on-scheduled-prs` — sidestepped by Inngest cron (not GH Actions).
- `2026-03-13-ralph-loop-idle-detection-and-repetition` — single in-flight per `(founder, domain, eventKey)`.
- `2026-03-23-action-completion-workflow-gap` — orchestrator owns "what's next," not the LLM. Inngest run state is the source of truth.
- `2026-03-20-claude-code-action-max-turns-budget` — per-invocation max-turns ceiling configured per-domain.

## Out of MVP scope (deferred)

- **Cosmos borrow (C):** recall-vs-precision review modes — file follow-up issue post-MVP.
- **Cosmos borrow (B):** episodic-vs-procedural compound classifier — vocabulary borrow only; mechanical work not warranted.
- **Cosmos borrow (D):** Expert Registry with quality signals — re-evaluate post-5-org adoption.
- **Sub-brand collateral rollout:** CMO produces brand guide, positioning doc, landing page, demo video, content calendar separately.
- **5 follow-up validation interviews:** CPO recommendation; conduct mid-MVP between FR1-FR3 and FR4-FR5.
- **SOC2 Type I program:** within 6 months of paid launch, not MVP-blocking.

## User-Brand Impact

Inherits from brainstorm (`## User-Brand Impact` section). Threshold `single-user incident`. Three vectors: cross-tenant data leak, BYOK credential leak, agent fires wrong action while founder sleeps. Plan Phase 2.6 carries this forward; `user-impact-reviewer` must sign off; preflight Check 6 fires on `apps/web-platform/server/**`, `supabase/migrations/**`, BYOK custody surfaces.
