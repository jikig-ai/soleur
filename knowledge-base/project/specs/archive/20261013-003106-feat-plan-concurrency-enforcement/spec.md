# Feature: Plan-Based Conversation Concurrency Enforcement

**Issue:** #1162
**PR:** #2617
**Branch:** `feat-plan-concurrency-enforcement`
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-19-plan-concurrency-enforcement-brainstorm.md` (see Amendment A)
**Parent:** #673 (Phase 4 / roadmap 4.7)

## Problem Statement

The pricing page at `soleur.ai/pricing` advertises per-tier concurrent-agent limits (Solo=2, Startup=5, Scale/Enterprise="unlimited"), but the product enforces none of them. Any user can spawn as many conversations as the server allows regardless of subscription tier. This creates (a) a revenue leak — over-consuming users have no incentive to upgrade, (b) a truth-in-advertising liability on the "Unlimited" claim for higher tiers (FTC exposure per recent "unlimited data" settlements), and (c) no upgrade funnel surface at the highest-intent moment (user trying to open one more conversation).

**Terminology (per brainstorm Amendment A, 2026-04-19):** the user-facing noun is **"concurrent conversations"**. One conversation = one slot, regardless of how many domain-leader specialists the conversation fans out to internally. Fan-out is an implementation detail the user did not opt into.

## Goals

- Enforce advertised per-tier **concurrent-conversation** limits at the WebSocket `start_session` boundary.
- Define "slot" unambiguously as **one active conversation with any in-flight task** (not a connected WS, not an idle conversation, not a per-specialist count inside a fan-out).
- Convert the at-capacity moment into an in-app Stripe Checkout upgrade modal.
- Rewrite the pricing page in the same PR to remove the "Unlimited" liability and flip public copy to "concurrent conversations".
- Instrument `concurrency_cap_hit` telemetry (with `active_conversation_count`) to inform future re-benchmarking of the ladder.
- Ship proactive comms (email to affected users, in-product banner, changelog) to counter silent-enforcement trust erosion.
- Add a secondary **per-conversation specialist fan-out cap** (infra-cost guard; not user-facing).

## Non-Goals

- Queue-with-ETA UX at capacity (rejected — reject + upgrade modal chosen for simpler infra and higher conversion).
- Observe-only telemetry-without-enforcement v1 (deferred; tracked in #2624).
- Bumping Solo cap from 2 to 3 in this release (deferred to #2625 A/B; conversation-slot framing likely dissolves the papercut anyway).
- Redis or other new stateful infrastructure (Postgres row-lock sufficient at current scale).
- Per-IP WebSocket rate limiting (already covered by #1046).
- API requests-per-minute rate limiting (separate concern; out of scope).
- Container-per-workspace isolation (covered by #673 3.2).
- Slot-count UI in the workspace header (scope-out; post-ship follow-up).
- "Wait for current slot" secondary modal action (scope-out; revisit if `concurrency_cap_hit` telemetry supports demand).

## Functional Requirements

### FR1: Enforce per-tier concurrent-conversation limits at session start

When a user attempts to start a new conversation task (`ws-handler.ts` `start_session` handler) and their current active-conversation count equals their effective cap, the server closes the WebSocket with close code `4010 CONCURRENCY_CAP`. Successful starts acquire a slot; task completion, error, or abort releases it. A conversation holds one slot from the moment its first task starts until the last specialist's task completes — fan-out within the conversation does not multiply the slot count.

- Free: 1 conversation
- Solo: 2 conversations
- Startup: 5 conversations
- Scale: up to 50 conversations (50 is the platform hard cap, not a marketing number)
- Enterprise: up to 50 conversations by default; `users.concurrency_override` can raise this per-user via internal admin flow

**Effective cap:** `MAX(tier_default, concurrency_override ?? 0)`. Override is raise-only — it cannot lower a user's cap below the tier default.

### FR2: Slot definition = one active conversation

A slot is acquired on `(user_id, conversation_id)` when the first task in that conversation begins executing. It is released when the conversation's in-flight task count returns to zero. Idle conversations (open WS, no running task) do NOT hold slots. Conversations that fan out to N domain-leader specialists via `dispatchToLeaders` (`apps/web-platform/server/agent-runner.ts`) hold **one** slot for the duration of the fan-out, not N.

The in-process `activeSessions` Map in `agent-runner.ts` remains the runtime source of truth for which specialist sessions are live; persistence to `user_concurrency_slots` keyed on `(user_id, conversation_id)` is the durability / cross-instance / cap-enforcement layer.

### FR3: At-capacity upgrade modal

On receipt of WS close code `4010 CONCURRENCY_CAP`, the client shows an inline Stripe Checkout modal pre-filled with the next tier up and a one-sentence value line. Single primary button: "Upgrade to [Next Tier] — $X/mo". Billing-portal deep-links are not acceptable for this surface.

Copy uses **"conversations"** not "agents" throughout. CMO to finalize post-pivot (see `knowledge-base/marketing/copy/` output after re-consult). Candidate lines:

- Default: "All [N] of your conversations are working. Upgrade to run more in parallel."
- Loading: "Opening checkout…"
- Error: "Checkout didn't open. Try again, or contact support."
- Enterprise cap: "50 conversations in parallel. That's the platform ceiling today — reach out for a custom quota."

Copy must avoid punitive triggers ("limit reached", "exceeded", "you have hit").

### FR4: Pricing-page copy rewrite (same PR, blocks merge)

`plugins/soleur/docs/pages/pricing.njk` must be updated in the same PR. All occurrences of "concurrent agents" / "agents in parallel" flip to **"concurrent conversations"** / "conversations in parallel". Specific updates:

- Lines 184, 199, 214–217, 228–233: tier-feature bullets.
- Lines 288–291: JSON-LD `offers.description` text.
- Scale tier: "Up to 50 concurrent conversations (contact us if you need more)".
- Enterprise tier: "Custom concurrency (negotiated per contract)".
- FAQ line "Slots determine parallelism, not access" retained, reworded to refer to conversations.

### FR5: Downgrade grace

When a user downgrades (Stripe webhook `customer.subscription.updated` reducing tier), active in-flight conversations continue to completion. New conversation starts are blocked until active count ≤ new tier limit. A 24-hour hard grace cap bounds indefinite holdouts; a scheduled sweep aborts the oldest in-flight conversation(s) over cap after 24h and the user receives a banner + email. Banner copy: "You're now on [Tier]. New conversations will wait until active ones complete."

### FR6: Stripe webhook-lag grace

If DB tier denies a session start, the server performs an on-demand `stripe.subscriptions.retrieve()` fallback and uses the higher of (DB tier, live tier). Live-lookup result cached 60s per user keyed on `sub_id`; cache invalidated on any `customer.subscription.*` webhook. Errs toward the paying customer. A circuit breaker (3 consecutive Stripe 5xx in 30s → DB-deny fallback for 60s, in-memory) prevents cascading failure into the Stripe API rate limit (100 reads/s prod, 25 sandbox) and into a ≤30s-per-user token bucket.

### FR7: Stripe `incomplete` status (3DS/SCA)

Upgrades completing via embedded Checkout may land in Stripe `incomplete` status pending SCA verification. The server must NOT grant the higher tier on `incomplete`; it shows a banner "Upgrade pending payment verification" and retries the tier read after 30s. Grant occurs only on `customer.subscription.updated` → `active`.

### FR8: Proactive comms on ship

- Email to any user whose conversation count exceeded their Solo cap (or free cap) in the 30 days preceding ship (if zero affected users, email step skipped — verification query runs at ship-prep time).
- In-product banner on the workspace view for 2 weeks post-ship, wording: "Conversations now run per-plan. See pricing."
- One changelog entry.

### FR9: Telemetry

Emit `concurrency_cap_hit` event on every enforcement block. Fields:

- `tier`
- `active_conversation_count` (renamed from `attempted_slot_count` — the count at the moment of deny, for ladder re-benchmarking)
- `effective_cap`
- `action` (`upgraded` | `abandoned` | `retried_later`)
- `path` (`start_session` | `downgrade_sweep` | `hard_cap_24h`)

Feeds future re-benchmarking of the 1→2→5→50 ladder (#2624).

### FR10: Per-conversation specialist fan-out cap (new)

`PER_CONVERSATION_SPECIALIST_CAP = 8` (default; matches `ROUTABLE_DOMAIN_LEADERS.length` today). Enforced in `agent-runner.ts` `dispatchToLeaders`: slice leaders to cap before `Promise.allSettled`. Excess leaders receive a single user-visible notice ("Dispatched to first 8 specialists — @mention fewer to target specific ones.") and are dropped. This is an infra-cost guard, not a user-facing tier gate; the cap is defined in `apps/web-platform/lib/plan-limits.ts` and can be raised when `ROUTABLE_DOMAIN_LEADERS` grows.

## Technical Requirements

### TR1: Counter storage — Postgres atomic upsert, not SELECT-FOR-UPDATE + check

Per learnings (best-practices research, 2026-04-19): prefer `UPDATE … RETURNING` with atomic predicate over `SELECT … FOR UPDATE + check-then-increment`. For our model, the acquire path is:

1. `SELECT 1 FROM users WHERE id = p_user_id FOR UPDATE` (per-xact lock scope on the owning user row — serializes concurrent acquires for the same user).
2. Lazy sweep: `DELETE FROM user_concurrency_slots WHERE user_id = p_user_id AND last_heartbeat_at < now() - interval '120 seconds'`.
3. Own-orphan reclaim: `INSERT INTO user_concurrency_slots (user_id, conversation_id) VALUES ($1, $2) ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_heartbeat_at = now()`.
4. Count after upsert: `SELECT COUNT(*) FROM user_concurrency_slots WHERE user_id = p_user_id`.
5. If count > effective_cap, `DELETE` the row just inserted (if it was a fresh insert) and return `cap_hit`.

Wrap in `SET LOCAL lock_timeout = '500ms'` and retry on SQLSTATE `40P01` / `55P03` with jitter, ≤3 attempts. Confirmed: no Redis / ioredis / upstash dependency in `apps/web-platform` today.

**Heartbeat + sweep beats `pg_try_advisory_lock`** under Supabase pooling (orphan-lock risk). Heartbeat every 30s, background sweep every 60s, reclaim at >120s staleness.

### TR2: Schema migration (`029_plan_tier_and_concurrency_slots.sql`)

Plain DDL; no `CONCURRENTLY` (forbidden in Supabase transaction-wrapped migrations per `2026-04-18-supabase-migration-concurrently-forbidden.md`).

```sql
ALTER TABLE users
  ADD COLUMN plan_tier text NOT NULL DEFAULT 'free'
    CHECK (plan_tier IN ('free','solo','startup','scale','enterprise')),
  ADD COLUMN concurrency_override integer NULL
    CHECK (concurrency_override IS NULL OR concurrency_override >= 0);

-- Folds in #2188: prevent duplicate stripe_customer_id mappings.
CREATE UNIQUE INDEX users_stripe_customer_id_unique
  ON users (stripe_customer_id) WHERE stripe_customer_id IS NOT NULL;

CREATE TABLE user_concurrency_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_heartbeat_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, conversation_id)  -- one slot per conversation, regardless of fan-out
);
CREATE INDEX user_concurrency_slots_user_heartbeat_idx
  ON user_concurrency_slots (user_id, last_heartbeat_at);

ALTER TABLE user_concurrency_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY slots_owner_read ON user_concurrency_slots
  FOR SELECT USING (auth.uid() = user_id);
-- No WITH CHECK (true); service role bypasses RLS for writes.
```

RPC functions:

```sql
CREATE OR REPLACE FUNCTION acquire_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid,
  p_effective_cap integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ ... $$;

CREATE OR REPLACE FUNCTION release_conversation_slot(
  p_user_id uuid,
  p_conversation_id uuid
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  DELETE FROM user_concurrency_slots
  WHERE user_id = p_user_id AND conversation_id = p_conversation_id;
$$;

REVOKE ALL ON FUNCTION acquire_conversation_slot, release_conversation_slot FROM PUBLIC;
GRANT EXECUTE ON FUNCTION acquire_conversation_slot, release_conversation_slot TO service_role;
```

Per AGENTS `wg-when-a-pr-includes-database-migrations`: verify applied to production via Supabase REST API before closing #1162.

### TR3: Tier lookup

`apps/web-platform/lib/plan-limits.ts` (new) exports:

- `PLAN_LIMITS: Record<PlanTier, number>` = `{ free: 1, solo: 2, startup: 5, scale: 50, enterprise: 50 }`
- `PLATFORM_HARD_CAP = 50`
- `PER_CONVERSATION_SPECIALIST_CAP = 8`
- `effectiveCap(tier, override): number` = `Math.max(PLAN_LIMITS[tier], override ?? 0)` (raise-only override)
- `nextTier(tier): PlanTier | null` for upsell modal routing

Grep-stable symbol anchors per `cq-code-comments-symbol-anchors-not-line-numbers`.

### TR4: Stripe webhook handler — write `plan_tier`

`apps/web-platform/app/api/webhooks/stripe/route.ts`:

- `customer.subscription.updated` is **authoritative** for tier; `invoice.paid` is for dunning only — never drive tier from it.
- Extract `subscription.items[].price.id`, map to tier via new `apps/web-platform/lib/stripe-price-tier-map.ts` module reading `STRIPE_PRICE_ID_SOLO` / `..._STARTUP` / `..._SCALE` / `..._ENTERPRISE` env vars (Doppler, 4 new keys each in `dev` and `prd`).
- Use atomic `UPDATE … .in("status", [allowed_pre_states])` idempotency pattern per learning `2026-04-14-atomic-webhook-idempotency-via-in-filter` (currently only applied on `invoice.paid` — extend to `customer.subscription.updated` and `customer.subscription.deleted`; folds in #2190 out-of-order guard).
- On Stripe `status = "incomplete"`, do NOT grant the new tier (per FR7).
- Non-200 on write error so Stripe retries.
- `stripe.webhooks.constructEventAsync(await req.text(), sig, secret)` — `req.text()`, not `arrayBuffer`. No `config` export in App Router (per `cq-nextjs-route-files-http-only-exports`).

### TR5: WS close code routing

Add to `apps/web-platform/lib/types.ts` `WS_CLOSE_CODES`:

- `CONCURRENCY_CAP = 4010`
- `TIER_CHANGED = 4011`

Add both to `NON_TRANSIENT_CLOSE_CODES` in **`apps/web-platform/lib/ws-client.ts`** (corrected from TR5's previous `ws-handler.ts` reference — the constant lives client-side). Prevents reconnect loop per learning `2026-03-27-websocket-close-code-routing-reconnect-loop`.

Server-side: always send a JSON preamble message describing the reason before `ws.close(4010, "…")` (browser delivers clean-close codes only; TCP reset = 1006; reason cap 123 bytes).

### TR6: Orphan reconciliation

Extend existing WS heartbeat (ping every 30s, per `ws-handler.ts:761`) to touch `user_concurrency_slots.last_heartbeat_at` for the current conversation's row on each ping. Sweep runs in **two places**: (a) background every 60s for system-wide cleanup, (b) lazy inside `acquire_conversation_slot` RPC for per-acquire hygiene. Both evict rows where `last_heartbeat_at < now() - interval '120 seconds'`. Worst-case stale slot ~130s matching Cloudflare idle timeout.

Own-orphan reclaim: on client reconnect, the acquire RPC upserts via `ON CONFLICT (user_id, conversation_id) DO UPDATE SET last_heartbeat_at = now()`, so a dropped-then-resumed conversation does not double-count.

### TR7: Race condition mitigation

Atomic `INSERT … ON CONFLICT DO UPDATE` with post-insert count check inside the RPC; the per-user-row `FOR UPDATE` serializes concurrent acquires for the same user. Count measures DISTINCT `conversation_id` per `user_id` with any active (non-swept) row. No check-then-increment.

RED-phase tests must pin exact post-state with `.toBe(cap)` (not `.toContain([pre, post])`) per `cq-mutation-assertions-pin-exact-post-state` — prevents silent no-op drift where `limit=Infinity` passes tautologically.

### TR8: Tier resolution cache on ClientSession

Cache `plan_tier` (NOT just `subscriptionStatus`) on the in-memory `ClientSession` struct at auth time. **Current state (2026-04-19):** `ws-handler.ts:55-70` caches `subscriptionStatus` but does not cache `tc_version` or `plan_tier`. Extend the cache to hold both `plan_tier` and `concurrency_override`, read once at connect.

On downgrade webhook, force-disconnect the user's WS with `4011 TIER_CHANGED`; client reconnects and re-reads the fresh tier. On upgrade webhook, push a typed WS message to the client so the UI updates without full reconnect.

### TR9: Test strategy (TDD per `cq-write-failing-tests-before`)

Test helpers: `test/helpers/mock-supabase.ts` currently supports select/eq/neq/in/is/gt/gte/lt/lte/order/limit/range/insert/update/upsert/delete/single but **no FOR UPDATE simulation**. Integration tests that exercise the RPC must hit a real Supabase local instance; unit tests mock the RPC response shape.

- Unit: `PLAN_LIMITS` lookup with `.toBe(expected)` pins. `effectiveCap` raise-only semantics (override < tier default returns tier default). `nextTier` boundary (enterprise returns null).
- Unit: Stripe price→tier mapping.
- Unit: Per-conversation specialist cap slicing in `dispatchToLeaders`.
- Integration: WS `start_session` path. Seed user to Solo. Start 2 conversations. Attempt a 3rd; assert WS closes with `4010` and `active_conversation_count=2` telemetry. Complete 1 conversation; assert the 3rd succeeds.
- Integration: `@all` fan-out inside a conversation does NOT multiply the slot count (start 1 conversation on Free tier, dispatch to all leaders, verify `user_concurrency_slots` has 1 row).
- Integration: Downgrade. Seed 5 active conversations on Startup. Webhook downgrades to Solo. Assert existing 5 continue. Assert 6th start blocked. Assert 24h sweep aborts oldest 3 (bringing count to new cap=2).
- Integration: Stripe lag. Seed user tier=Solo in DB, mock `stripe.subscriptions.retrieve()` to return Startup. Assert 3rd start succeeds.
- Integration: Stripe `incomplete` status. Mock retrieve returns `status='incomplete'`. Assert tier NOT granted; banner state set.
- Integration: Circuit breaker. Three consecutive retrieve() 5xx. Assert subsequent deny uses DB tier.
- Integration: Own-orphan reclaim on reconnect. Disconnect mid-conversation, reconnect, assert single row persists.
- Destructive tests gate on synthetic-email allowlist per `cq-destructive-prod-tests-allowlist`.

Use `node node_modules/vitest/vitest.mjs run` in worktree (per `cq-in-worktrees-run-vitest-via-node-node`).

### TR10: Silent-fallback observability

All enforcement deny paths must mirror pino `logger.warn` to Sentry via `reportSilentFallback()` per `cq-silent-fallback-must-mirror-to-sentry`. Exempt: expected cap-hit rejections on `start_session` (these are the intended enforcement, not silent fallbacks). Report: Stripe lookup failure → DB fallback; RPC retry-exhausted; sweep orphan-count > threshold; webhook `incomplete`-state divergence > 5 minutes.

### TR11: Admin override path

`users.concurrency_override` is nullable and NOT exposed in any user-facing UI. Override is raise-only via `effectiveCap`. Internal ops sets via direct SQL or a future admin route; documented in the internal runbook, not the pricing page.

### TR12: Module-scope Supabase client (test caveat)

Both `ws-handler.ts:38` and `agent-runner.ts` call `createServiceClient()` at module scope. The `vi.mock` factory must return a function, not the client directly — or integration tests must use the real Supabase client. Confirmed during research; no refactor needed for this PR.

### TR13: Doppler secrets

Add four new keys to Doppler `soleur/dev` and `soleur/prd`:

- `STRIPE_PRICE_ID_SOLO`
- `STRIPE_PRICE_ID_STARTUP`
- `STRIPE_PRICE_ID_SCALE`
- `STRIPE_PRICE_ID_ENTERPRISE`

Update `.env.example` to document them. The existing single `STRIPE_PRICE_ID` is retained for backward-compat during deploy, deprecated post-ship.

## Acceptance Criteria

- [ ] Free user with 1 active conversation: 2nd start rejected with `4010 CONCURRENCY_CAP`.
- [ ] Solo user with 2 active conversations: 3rd start rejected with `4010 CONCURRENCY_CAP`.
- [ ] Startup user with 5 active conversations: 6th start rejected with `4010 CONCURRENCY_CAP`.
- [ ] Scale user reaches 50 conversations: 51st start rejected even though pricing page says "up to 50" (platform hard cap).
- [ ] User with `concurrency_override=100`: 51st start succeeds; effective cap respects raise-only semantics.
- [ ] User with `concurrency_override=0` on Solo tier: 3rd start still rejected (override cannot lower cap).
- [ ] `@all` fan-out inside one conversation: single row in `user_concurrency_slots`; count toward user cap is 1, not 8.
- [ ] Conversation with 9 `@mention`ed leaders dispatches to only 8 (per-conversation specialist cap).
- [ ] Downgrade from Startup to Solo with 4 active conversations: all 4 continue, 5th blocked. After 24h, oldest 2 are swept, user gets banner + email.
- [ ] Stripe webhook lag: DB says Solo, live Stripe says Startup — 3rd start succeeds. Live lookup cached 60s.
- [ ] Stripe `incomplete` status: tier NOT granted; "Upgrade pending payment verification" banner shown; retried after 30s.
- [ ] Circuit breaker: 3 consecutive Stripe 5xx in 30s triggers DB-only fallback for 60s.
- [ ] Task completion decrements slot count within 5s.
- [ ] Crashed client (abrupt disconnect): slot freed within 130s via sweep.
- [ ] Client reconnects mid-conversation: single row reclaimed; no double-count.
- [ ] At-capacity Stripe Checkout modal renders with correct next-tier pricing and **"conversations"** copy.
- [ ] Modal has 5 states implemented matching wireframes: loading, default, error, admin-override, enterprise-cap.
- [ ] `concurrency_cap_hit` telemetry emits on every deny with `tier`, `active_conversation_count`, `effective_cap`, `action`, `path` fields.
- [ ] Pricing page reflects "up to 50 concurrent conversations" for Scale and "custom" for Enterprise — no "Unlimited" claim and no "agents" language remains in customer-facing copy.
- [ ] Migration applied to production and verified via Supabase REST API before #1162 closes.
- [ ] In-product banner appears for 2 weeks post-ship; changelog entry merged.
- [ ] Stripe embedded Checkout loads with `ui_mode: "embedded"` and `return_url: /dashboard?upgrade=complete&session_id={CHECKOUT_SESSION_ID}`. On return, WS force-reconnects to re-read plan_tier and retries the original action.

## Open Questions (resolve in plan phase)

1. Exact `STRIPE_PRICE_ID_*` values for each tier — fetch from Stripe dashboard during plan phase.
2. Modal + pricing + banner final copy — CMO re-consult pending with "concurrent conversations" pivot.
3. Whether `PER_CONVERSATION_SPECIALIST_CAP = 8` stays at 8 forever or tracks `ROUTABLE_DOMAIN_LEADERS.length` dynamically — decide in plan (static constant with comment vs. runtime calculation).
4. Email template wording for affected-users comms — copywriter.
5. Variable cost per conversation-slot under fan-out economics — CFO re-consult pending; feeds #2626.

## Code-Review Overlap (Step 1.7.5)

- **#2190** (guard `customer.subscription.deleted` against out-of-order events) → **Fold in** via TR4 idempotency extension. `Closes #2190` in PR body.
- **#2188** (unique partial index on `users.stripe_customer_id`) → **Fold in** via TR2 migration. `Closes #2188`.
- **#2191** (`clearSessionTimers` helper + jitter) → **Acknowledge** — orthogonal refactor, separate PR.
- **#2217** (`activeStreams` reducer) → **Acknowledge** — different concern, separate PR.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-19-plan-concurrency-enforcement-brainstorm.md` (Amendment A)
- Issue: #1162
- PR: #2617
- Parent: #673 (Phase 4 / roadmap 4.7)
- Dependency (shipped): #1078 Stripe subscription management
- Related (separate): #1046 per-IP WS rate limiting
- Folded: #2188 (unique partial index), #2190 (subscription.deleted idempotency)
- Deferred: #2624 (observe-only re-eval), #2625 (Solo cap A/B), #2626 (CFO cost model)
- Wireframes: `knowledge-base/product/design/upgrade-modal-at-capacity.pen` (copy currently says "agents" — re-render post-pivot)
- Key code paths:
  - `apps/web-platform/server/ws-handler.ts` (enforcement, heartbeat; cache at `ws-handler.ts:55-70`)
  - `apps/web-platform/server/agent-runner.ts` (`activeSessions` Map, `dispatchToLeaders` fan-out)
  - `apps/web-platform/app/api/webhooks/stripe/route.ts` (tier writes)
  - `apps/web-platform/app/api/checkout/route.ts` (multi-price-ID wiring)
  - `apps/web-platform/lib/types.ts` (`WS_CLOSE_CODES`)
  - `apps/web-platform/lib/ws-client.ts` (`NON_TRANSIENT_CLOSE_CODES`)
  - `apps/web-platform/supabase/migrations/029_plan_tier_and_concurrency_slots.sql` (new)
  - `apps/web-platform/lib/plan-limits.ts` (new)
  - `apps/web-platform/lib/stripe-price-tier-map.ts` (new)
  - `plugins/soleur/docs/pages/pricing.njk` (copy rewrite; lines 184, 199, 214–217, 228–233, 288–291)
