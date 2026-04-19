# Feature: Plan-Based Agent Concurrency Enforcement

**Issue:** #1162
**PR:** #2617
**Branch:** `feat-plan-concurrency-enforcement`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-19-plan-concurrency-enforcement-brainstorm.md`
**Parent:** #673 (Phase 4 / roadmap 4.7)

## Problem Statement

The pricing page at `soleur.ai/pricing` advertises per-tier concurrent-agent limits (Solo=2, Startup=5, Scale/Enterprise="unlimited"), but the product enforces none of them. Any user can spawn as many agents as the server allows regardless of subscription tier. This creates (a) a revenue leak — over-consuming users have no incentive to upgrade, (b) a truth-in-advertising liability on the "Unlimited" claim for higher tiers (FTC exposure per recent "unlimited data" settlements), and (c) no upgrade funnel surface at the highest-intent moment (user trying to run one more agent).

## Goals

- Enforce advertised per-tier concurrency limits at the WebSocket `start_session` boundary.
- Define "slot" unambiguously as an agent actively executing a task (not a connected WS, not an open conversation).
- Convert the at-capacity moment into an in-app Stripe Checkout upgrade modal.
- Rewrite the pricing page in the same PR to remove the "Unlimited" liability.
- Instrument `concurrency_cap_hit` telemetry to inform future re-benchmarking of the ladder.
- Ship proactive comms (email to affected users, in-product banner, changelog) to counter silent-enforcement trust erosion.

## Non-Goals

- Queue-with-ETA UX at capacity (rejected — reject + upgrade modal chosen for simpler infra and higher conversion).
- Observe-only telemetry-without-enforcement v1 (deferred; tracking issue to be filed).
- Bumping Solo cap from 2 to 3 in this release (deferred to post-ship A/B test per CMO "don't conflate signal" guidance).
- Redis or other new stateful infrastructure (Postgres row-lock sufficient at current scale).
- Per-IP WebSocket rate limiting (already covered by #1046).
- API requests-per-minute rate limiting (separate concern; out of scope).
- Container-per-workspace isolation (covered by #673 3.2).

## Functional Requirements

### FR1: Enforce per-tier slot limits at session start

When a user attempts to start a new agent session (`ws-handler.ts` `start_session` handler) and their current active-slot count equals their tier limit, the server closes the WebSocket with close code `4008 CONCURRENCY_CAP`. Successful starts increment the count; task completion, error, or abort decrements it.

- Solo: 2 slots
- Startup: 5 slots
- Scale: up to 50 slots (50 is the platform hard cap, not a marketing number)
- Enterprise: up to 50 slots by default; `users.concurrency_override` can raise this per-user via internal admin flow

### FR2: Slot definition = active task

A slot is acquired when an agent begins executing a task and released when the task completes, errors, or is aborted. Idle conversations and connected-but-inactive WebSockets do NOT hold slots. The in-process `activeSessions` Map in `agent-runner.ts` remains the runtime source of truth; persistence to `user_concurrency_slots` is the durability/cross-instance layer.

### FR3: At-capacity upgrade modal

On receipt of WS close code `4008 CONCURRENCY_CAP`, the client shows an inline Stripe Checkout modal pre-filled with the next tier up and a one-sentence value line. Single primary button: "Upgrade to [Next Tier] — $X/mo". Billing-portal deep-links are not acceptable for this surface.

On-brand copy variants (copywriter to finalize one):

- V1: "All [N] of your agents are working. Upgrade to run more in parallel."
- V2: "Your team is at full throttle. Add horsepower — [Next Tier] runs [M] agents in parallel."

### FR4: Pricing-page copy rewrite (same PR, blocks merge)

`plugins/soleur/docs/pages/pricing.njk` must be updated in the same PR:

- Scale: "Up to 50 concurrent agents (contact us if you need more)"
- Enterprise: "Custom concurrency (negotiated per contract)"
- FAQ line "Slots determine parallelism, not access" is retained.

### FR5: Downgrade grace

When a user downgrades (Stripe webhook `customer.subscription.updated` reducing tier), active in-flight sessions continue to completion. New session starts are blocked until active count ≤ new tier limit. A 24-hour hard grace cap bounds indefinite holdouts. Banner in the workspace UI: "You're now on [Tier]. New agents will wait until active ones complete."

### FR6: Stripe webhook-lag grace

If DB tier denies a session start, the server performs an on-demand `stripe.subscriptions.retrieve()` fallback and uses the higher of (DB tier, live tier). Live-lookup result cached 60s per user. Errs toward the paying customer.

### FR7: Proactive comms on ship

- Email to any user whose session count exceeded their Solo cap in the 30 days preceding ship (if zero affected users, email step skipped — verification query runs at ship-prep time).
- In-product banner on the workspace view for 2 weeks post-ship.
- One changelog entry.

### FR8: Telemetry

Emit `concurrency_cap_hit` event on every enforcement block. Fields: `tier`, `attempted_slot_count`, `action` (`upgraded` | `abandoned` | `retried_later`). Feeds future re-benchmarking of the 2→5→50 ladder.

## Technical Requirements

### TR1: Counter storage — Postgres row-lock

Single-instance-safe and cross-instance-safe. Use `SELECT ... FOR UPDATE` on the user row (or `INSERT ... ON CONFLICT ... WHERE count < limit`) inside the session-insert transaction. No Redis. Confirmed: no Redis/ioredis/upstash dependency in `apps/web-platform` today.

### TR2: Schema migration

```sql
ALTER TABLE users
  ADD COLUMN plan_tier text
    CHECK (plan_tier IN ('free','solo','startup','scale','enterprise'))
    DEFAULT 'free',
  ADD COLUMN concurrency_override int NULL;

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

Per AGENTS `wg-when-a-pr-includes-database-migrations`: verify applied to production via Supabase REST API before closing #1162.

### TR3: Tier lookup

`apps/web-platform/lib/plan-limits.ts` exports `PLAN_LIMITS: Record<PlanTier, number>` and `PLATFORM_HARD_CAP = 50`. Grep-stable symbol anchors per `cq-code-comments-symbol-anchors-not-line-numbers`.

### TR4: Stripe webhook handler — write `plan_tier`

`apps/web-platform/app/api/webhooks/stripe/route.ts` must extract `subscription.items[].price.id`, map to tier via new `STRIPE_PRICE_ID_SOLO`/`..._STARTUP`/`..._SCALE`/`..._ENTERPRISE` env vars (Doppler), and write to `users.plan_tier`. Use atomic `UPDATE ... .in("status", [allowed_pre_states])` idempotency pattern per learning `2026-04-14-atomic-webhook-idempotency-via-in-filter`. Non-200 on write error so Stripe retries.

### TR5: WS close code routing

Reserve `4008 CONCURRENCY_CAP` and add to `NON_TRANSIENT_CLOSE_CODES` in `ws-handler.ts` (prevents client reconnect loop per learning `2026-03-27-websocket-close-code-routing-reconnect-loop`).

### TR6: Orphan reconciliation

Extend existing WS heartbeat (ping every 30s, per `ws-handler.ts:761`) to touch `user_concurrency_slots.last_heartbeat_at` for active rows. Background sweep (or lazy sweep on next acquire) evicts rows where `last_heartbeat_at < now() - 120 seconds`. Worst-case stale slot ~130s matching Cloudflare idle timeout.

### TR7: Race condition mitigation

Atomic `UPDATE ... RETURNING` or `SELECT ... FOR UPDATE` inside transaction for every slot acquire. No check-then-increment. RED-phase tests must use `.toBe(cap)` not `.toContain([pre, post])` per `cq-mutation-assertions-pin-exact-post-state` — prevents silent no-op drift where `limit=Infinity` passes tautologically.

### TR8: Tier resolution cache on ClientSession

Cache `plan_tier` on the in-memory `ClientSession` struct at auth time (combine with existing T&C version select per learning `2026-04-13-ws-session-cache-subscription-status`). On downgrade webhook, force-disconnect the user's socket to invalidate cached tier. On upgrade webhook, push a WS message to the client so the UI updates without a full reconnect.

### TR9: Test strategy (TDD per `cq-write-failing-tests-before`)

- Unit tests on `PLAN_LIMITS` lookup with `.toBe(expected)` pins.
- Integration test on WS `start_session` path that (a) seeds a user to Solo tier, (b) starts 2 sessions, (c) attempts a 3rd and asserts WS closes with `4008`, (d) completes 1 session and asserts the 3rd succeeds.
- Integration test on downgrade webhook: seed 5 active sessions, downgrade to Solo, assert existing 5 continue but 6th start is blocked.
- Integration test on Stripe lag: seed user tier=Solo with live-Stripe-retrieve returning Startup, assert 3rd start succeeds.
- Destructive tests must gate on synthetic email allowlist per `cq-destructive-prod-tests-allowlist`.

### TR10: Silent-fallback observability

All enforcement deny paths must mirror pino `logger.warn` to Sentry via `reportSilentFallback()` per `cq-silent-fallback-must-mirror-to-sentry`. Exempt: expected cap-hit rejections (these are the intended enforcement, not silent fallbacks).

### TR11: Admin override path

`users.concurrency_override` is nullable and NOT exposed in any user-facing UI. Internal ops sets via direct SQL or a future admin route; documented in a runbook, not the pricing page.

## Acceptance Criteria

- [ ] Solo user with 2 active sessions: 3rd start rejected with `4008 CONCURRENCY_CAP`.
- [ ] Startup user with 5 active sessions: 6th start rejected with `4008 CONCURRENCY_CAP`.
- [ ] Scale user reaches 50 sessions: 51st start rejected even though pricing page says "unlimited" (soft cap).
- [ ] User with `concurrency_override=100`: 51st start succeeds.
- [ ] Downgrade from Startup to Solo with 4 active sessions: all 4 continue, 5th blocked.
- [ ] Stripe webhook lag: DB says Solo, live Stripe says Startup — 3rd start succeeds.
- [ ] Task completion decrements slot count within 5s.
- [ ] Crashed client (abrupt disconnect): slot freed within 130s.
- [ ] At-capacity Stripe Checkout modal renders with correct next-tier pricing.
- [ ] `concurrency_cap_hit` event emits on every deny with correct `tier` and `action` fields.
- [ ] Pricing page reflects "up to 50" for Scale and "custom" for Enterprise — no "Unlimited" claim remains.
- [ ] Migration applied to production and verified via Supabase REST API before #1162 closes.
- [ ] In-product banner appears for 2 weeks post-ship; changelog entry merged.

## Open Questions (resolve in plan phase)

1. Exact `STRIPE_PRICE_ID_*` env var values for each tier — fetch from Stripe dashboard during plan.
2. Banner copy variant — copywriter to finalize from V1/V2 candidates.
3. Whether to force-disconnect WS on downgrade webhook or update cached tier in-place — decide based on simplicity of WS message protocol.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-19-plan-concurrency-enforcement-brainstorm.md`
- Issue: #1162
- PR: #2617
- Parent: #673 (Phase 4 / roadmap 4.7)
- Dependency (shipped): #1078 Stripe subscription management
- Related (separate): #1046 per-IP WS rate limiting
- Key code paths:
  - `apps/web-platform/server/ws-handler.ts` (enforcement point, heartbeat)
  - `apps/web-platform/server/agent-runner.ts` (activeSessions Map)
  - `apps/web-platform/app/api/webhooks/stripe/route.ts` (tier writes)
  - `apps/web-platform/app/api/checkout/route.ts` (multi-price-ID wiring)
  - `apps/web-platform/supabase/migrations/` (new migration)
  - `plugins/soleur/docs/pages/pricing.njk` (copy rewrite)
