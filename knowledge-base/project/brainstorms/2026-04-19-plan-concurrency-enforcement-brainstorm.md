---
title: Plan-Based Agent Concurrency Enforcement
date: 2026-04-19
issue: 1162
pr: 2617
branch: feat-plan-concurrency-enforcement
status: brainstorm-complete
---

# Plan-Based Agent Concurrency Enforcement

## What We're Building

Plan-aware enforcement of concurrent agent sessions per user, matching the tiers advertised on the pricing page:

| Plan | Price | Concurrent Slots | Platform Hard Cap |
|------|-------|------------------|-------------------|
| Solo | $49/mo | 2 | — |
| Startup | $149/mo | 5 | — |
| Scale | $499/mo | "up to 50 (more on request)" | 50 |
| Enterprise | Custom | "custom per contract" | 50 (overridable per user) |

**Slot definition:** a slot is held while an agent is **actively executing a task**. Held on task start, released on task complete/error. Idle chats and connected WebSockets do **not** count.

**Enforcement point:** `ws-handler.ts` `start_session` handler — mirrors the existing `sessionThrottle` pattern (`apps/web-platform/server/ws-handler.ts:345`).

**At-capacity UX:** WS close with new code `4008 CONCURRENCY_CAP` → client shows inline Stripe Checkout modal pre-filled with next-tier upsell. No queue.

## Why This Approach

**Decision-driver summary from domain leaders:**

- **CTO** — Postgres row-lock counter (no Redis dep; single Bun instance today; ≤50 concurrent users pre-GA). Reject-with-429 simpler than queue. Heartbeat TTL reuses existing ping interval.
- **CPO** — Slot = active task matches "AI organization" pricing-page promise. In-app Checkout modal is the highest-intent upgrade surface in the product.
- **CMO** — Pricing page "Unlimited" claim is a truth-in-advertising liability; must change in the same PR as enforcement. Silent enforcement risks HN-grade bait-and-switch narrative with the technical-founder beachhead.
- **CFO** — Instrument `concurrency_cap_hit` from day one; this is the only dataset that will justify or re-benchmark the 2→5→50 ladder post-ship.

**Dissent captured:** CPO + CFO recommended observe-only telemetry for 30 days before hard enforcement, citing Phase 4 pre-GA status (0 beta users, Stripe test mode). User explicitly chose full enforcement at v1 — rationale: the pricing page advertises the caps, so enforcement aligns product with public commitment even without usage data. Risk accepted; `concurrency_cap_hit` telemetry is in scope to inform future re-benchmarking.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Full enforcement at v1, not observe-only | User override of CPO/CFO caution. Aligns shipped behavior with pricing-page claims. |
| 2 | Slot = agent actively executing task | Matches founder mental model of "2 agents running." All 3 technical/product leaders aligned. |
| 3 | Reject with WS close `4008 CONCURRENCY_CAP` + inline Stripe Checkout modal | Simpler infra (CTO), highest-intent upgrade conversion (CMO). Close code added to `NON_TRANSIENT_CLOSE_CODES` to prevent reconnect loop. |
| 4 | Postgres row-lock counter, no Redis | No Redis dependency in stack today. `SELECT ... FOR UPDATE` on a `user_concurrency_slots` row inside the session-insert transaction. Revisit when sessions/sec > ~100. |
| 5 | New `plan_tier` column on `users` table | Populated by Stripe webhook via `subscription.items[].price.id` → tier lookup. Checkout today uses single `STRIPE_PRICE_ID`; this PR introduces multi-price wiring. |
| 6 | Downgrade: grace — finish in-flight, block new starts, 24h hard cap | Founder-empathetic; revenue leakage bounded to realistic agent runtimes (minutes, not days). |
| 7 | Stripe webhook lag: live `stripe.subscriptions.retrieve()` fallback on cap-hit | On deny, do on-demand Stripe lookup; use higher of (DB tier, live tier). 60s cache bounds API cost. Err toward paying customer. |
| 8 | Enterprise "unlimited" = platform hard cap 50, `concurrency_override` nullable column | Protects OOM / DB connection pool from runaway clients. Ops can raise per-user for genuine Enterprise need. Documented in internal runbook, not pricing page. |
| 9 | Pricing page copy rewrite in same PR | Scale: "up to 50 concurrent (more on request)". Enterprise: "custom per contract". Closes FTC truth-in-advertising risk CMO flagged. Blocks merge. |
| 10 | Comms: email + 2-week in-product banner + changelog | Email users who exceeded cap in last 30d (if any). Counters bait-and-switch narrative with the technical-founder audience. |
| 11 | Orphan cleanup: reuse WS heartbeat + 60s DB sweep | `last_heartbeat_at` on slot row; background sweep evicts rows where heartbeat < now() − 2× ping interval. Worst-case stale slot ~130s (current Cloudflare idle timeout). |
| 12 | Instrument `concurrency_cap_hit` event from ship | Fields: tier, attempted-slot-count, action (upgraded/queued-impossible/abandoned). Input for future re-benchmarking of the 2→5→50 ladder. |

## Non-Goals

- Queue-with-ETA at capacity — decided reject + upgrade modal (#11 key decision)
- Observe-only telemetry-only v1 — deferred to separate issue (see below)
- Bumping Solo from 2 to 3 in this release — CMO warned it conflates signal; A/B test post-ship
- Per-IP WebSocket rate limiting — covered by #1046
- API request/minute rate limiting — separate concern
- Container-per-workspace isolation — covered by #673 3.2

## Data Model (new)

```sql
-- New column on users
ALTER TABLE users ADD COLUMN plan_tier text
  CHECK (plan_tier IN ('free', 'solo', 'startup', 'scale', 'enterprise'))
  DEFAULT 'free';
ALTER TABLE users ADD COLUMN concurrency_override int NULL;

-- Per-user active-slot tracking
CREATE TABLE user_concurrency_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL,
  leader_id text NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_heartbeat_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, conversation_id, leader_id)
);
CREATE INDEX ON user_concurrency_slots (user_id, last_heartbeat_at);
```

Tier-to-limit lookup is a const in `apps/web-platform/lib/plan-limits.ts`, not a DB table — cheaper to change, grep-stable per AGENTS.md symbol-anchor rule.

## Open Questions

1. **Tier lookup at checkout.** Today checkout uses a single `STRIPE_PRICE_ID` env var. Enforcement needs 4 price IDs (Solo/Startup/Scale/Enterprise). Plan will introduce `STRIPE_PRICE_ID_SOLO`, `..._STARTUP`, etc. via Doppler. Confirm during plan phase.
2. **Email list for comms.** If any user actually exceeded Solo cap in last 30d, they get the proactive email. Verification query runs at ship-prep time — may be empty (0 beta users). If empty, skip email; banner + changelog still ship.
3. **Test strategy for "cap actually enforces."** Per learnings, use `.toBe(cap)` not `.toContain` to prevent silent-no-op drift (AGENTS rule `cq-mutation-assertions-pin-exact-post-state`). RED tests must fail for the gating reason, not because the code path doesn't exist.
4. **Cross-instance concurrency (future).** Current design is single-Bun-instance. When platform scales horizontally, Postgres row-lock already handles cross-instance — but in-process `activeSessions` Map does not. Confirm the counter lives in DB, not only in-process.

## Deferred Items (tracked)

- **#2624** — Observe-only telemetry re-eval after #1162 cap enforcement. Re-evaluate if cap-hit rate <5%. Milestone: Post-MVP / Later.
- **#2625** — A/B test Solo cap (2 vs 3 vs metered). CPO flagged Solo=2 as papercut vs. "AI organization" pitch. Milestone: Phase 5.
- **#2626** — Finance cost model (per-concurrent-agent infra cost). CFO's Phase 4 exit-criteria deliverable. Milestone: Phase 4.

## Domain Assessments

**Assessed:** Engineering, Product, Marketing, Finance
**Not assessed:** Operations, Sales, Legal, Support (scope did not surface vendor procurement, sales motion, new legal docs, or support workflow changes; pricing-page truth-in-advertising is captured in-scope as a marketing deliverable).

### Engineering (CTO)

**Summary:** Postgres row-lock counter is the right primitive (no Redis, single Bun instance). Orphan reconciliation reuses existing WS heartbeat. Top risks: downgrade UX cliff, multi-tab same-user being the 90% case (not abuse), Cloudflare idle-timeout interaction with heartbeat-based cleanup.

### Product (CPO)

**Summary:** Recommended observe-only first (user declined). Slot = active task is the only definition that maps to founder mental model. Challenged Solo=2 as misaligned with "AI organization" pitch — deferred to post-ship A/B test. In-app Stripe Checkout at the cap is the single highest-intent upgrade surface the product has.

### Marketing (CMO)

**Summary:** "Unlimited" claim on pricing page must be rewritten in the same PR — truth-in-advertising risk. Silent enforcement is a brand liability with the technical-founder beachhead audience; proactive email + banner required. At-capacity copy must avoid punitive triggers ("limit reached", "exceeded"). Inline plan-compare modal at cap, not billing-portal deep-link.

### Finance (CFO)

**Summary:** Recommended observe-only first (user declined). Instrument `concurrency_cap_hit` from ship — only dataset that will justify the 2→5→50 ladder. Downgrade policy: Stripe-native prorated refund is defensible (user chose grace path instead — finance accepts the bounded-leakage tradeoff).

## Capability Gaps

None. No new agents or skills needed. Existing CTO/CPO/CMO/CFO + repo-research-analyst + learnings-researcher covered the design.
