# Tasks: Plan-Based Conversation Concurrency Enforcement

**Plan:** `knowledge-base/project/plans/2026-04-19-feat-plan-concurrency-enforcement-plan.md`
**Spec:** `knowledge-base/project/specs/feat-plan-concurrency-enforcement/spec.md`
**Issue:** #1162 · **PR:** #2617 · **Branch:** `feat-plan-concurrency-enforcement`
**Detail level:** A LOT (10 phases, TDD-ordered where acceptance criteria apply)

Each phase is a top-level task; sub-tasks are RED → GREEN → Gate. Destructive integration tests open with `assertSyntheticEmail(user.email)` from `test/helpers/synthetic-allowlist.ts`.

## Phase 0 — Preflight (infra-only, TDD exempt)

- [ ] 0.1 Fetch four Stripe price IDs (Solo $49, Startup $149, Scale $499, Enterprise custom) from Stripe Dashboard for test + live modes.
- [ ] 0.2 Set four Doppler keys in `soleur/dev` and `soleur/prd`:
  - `STRIPE_PRICE_ID_SOLO`
  - `STRIPE_PRICE_ID_STARTUP`
  - `STRIPE_PRICE_ID_SCALE`
  - `STRIPE_PRICE_ID_ENTERPRISE`
- [ ] 0.3 Write `scripts/verify-stripe-prices.ts` — iterate the four keys and call `stripe.prices.retrieve` on each. Any 404 fails the script with a non-zero exit.
- [ ] 0.4 Run the verification script against both `-c dev` and `-c prd`. Record exit status in PR body.
- [ ] 0.5 Run duplicate-stripe-customer-id preflight query on prd:

  ```sql
  SELECT stripe_customer_id, COUNT(*) FROM users
  WHERE stripe_customer_id IS NOT NULL GROUP BY 1 HAVING COUNT(*) > 1;
  ```

  Record result. If non-zero: resolve duplicates before Phase 2 OR drop the unique partial index sub-task.
- [ ] 0.6 Install `@stripe/react-stripe-js` at `apps/web-platform/package.json` if missing. Regenerate both `bun.lock` and `package-lock.json`.
- [ ] 0.7 Verify lefthook + Doppler login for the worktree.
- [ ] **Gate:** all four Doppler keys present + resolve via Stripe API; duplicate query returns zero; deps installed at correct level.

## Phase 1 — WS close codes + `closeWithPreamble` helper + client routing

- [ ] 1.1 RED: write `apps/web-platform/lib/ws-close-helper.test.ts`:
  - `closeWithPreamble(mockWs, 4010, {type: "concurrency_cap_hit", ...})` calls `send` once then `close(4010, "CONCURRENCY_CAP")` in order.
  - Preamble > 2 KiB logs warning via Sentry mirror.
  - **Expected RED reason:** helper symbol missing at import.
- [ ] 1.2 RED: extend `apps/web-platform/lib/ws-client.test.ts`:
  - `NON_TRANSIENT_CLOSE_CODES.includes(4010)` → `.toBe(true)`.
  - `NON_TRANSIENT_CLOSE_CODES.includes(4011)` → `.toBe(true)`.
  - Preamble + close 4010 → emits `openUpgradeModal` with exact payload.
  - Close 4011 → schedules reconnect after 500 ms via manual `AbortController + setTimeout` (never `AbortSignal.timeout`).
  - **Expected RED reason:** array membership assertions fail; event dispatch assertion fails on missing handler branch.
- [ ] 1.3 GREEN: add `CONCURRENCY_CAP: 4010` and `TIER_CHANGED: 4011` to `WS_CLOSE_CODES` in `lib/types.ts`.
- [ ] 1.4 GREEN: implement `lib/ws-close-helper.ts`. Size-check preamble; mirror oversize warnings via `reportSilentFallback()`.
- [ ] 1.5 GREEN: append 4010 + 4011 to `NON_TRANSIENT_CLOSE_CODES` at `lib/ws-client.ts:66`. Extend close-handler to parse preamble and dispatch to `openUpgradeModal` / scheduled reconnect.
- [ ] 1.6 Add pre-push grep snippet (document in PR body and, if practical, add to lefthook):

  ```bash
  rg 'ws\.close\(40[0-9]{2}' apps/web-platform --type ts -g '!lib/ws-close-helper.ts' && exit 1 || exit 0
  ```

- [ ] **Gate:** both test files GREEN; pre-push grep returns zero hits outside the helper.

## Phase 2 — Migration `029_plan_tier_and_concurrency_slots.sql`

- [ ] 2.1 Create `apps/web-platform/test/helpers/synthetic-allowlist.ts` exporting `SYNTHETIC_EMAIL_RE = /^concurrency-test\+[0-9a-f-]+@soleur\.dev$/` + `assertSyntheticEmail(email)` that throws on non-match.
- [ ] 2.2 RED: write `test/integration/concurrency/slot-rpc.test.ts`. `beforeAll` calls `assertSyntheticEmail(seededUser.email)`. Scenarios (each pinned with `.toBe`):
  - 2.2.1 Acquire on fresh user → `{status: "ok", active_count: 1, effective_cap: 2}`.
  - 2.2.2 Second acquire, same user different conversation_id → `{status: "ok", active_count: 2}`.
  - 2.2.3 Third acquire over Solo cap → `{status: "cap_hit", active_count: 2, effective_cap: 2}`; post-row-count still 2.
  - 2.2.4 Reclaim own orphan: expire heartbeat, re-acquire same key → `{status: "ok", active_count: 1}`. Row count = 1.
  - 2.2.5 Sweep-and-reinsert under same lock window (two concurrent acquires, same user, different conversations) → neither spurious rollback. Final `active_count` = 2.
  - 2.2.6 Lazy sweep: seed 3 expired rows; new acquire returns `active_count: 1`.
  - 2.2.7 `release_conversation_slot` idempotency: release twice → no error, row count 0.
  - **Expected RED reason:** `supabase.rpc("acquire_conversation_slot", ...)` fails with `function does not exist`.
- [ ] 2.3 GREEN: write `apps/web-platform/supabase/migrations/029_plan_tier_and_concurrency_slots.sql`:
  - 2.3.1 `ALTER TABLE users` adds `plan_tier`, `concurrency_override`, `subscription_downgraded_at`.
  - 2.3.2 `CREATE UNIQUE INDEX users_stripe_customer_id_unique ON users (stripe_customer_id) WHERE stripe_customer_id IS NOT NULL` (folds #2188).
  - 2.3.3 `CREATE TABLE user_concurrency_slots` with `UNIQUE(user_id, conversation_id)` + composite index on `(user_id, last_heartbeat_at)`.
  - 2.3.4 `ENABLE ROW LEVEL SECURITY` + `FOR SELECT USING (auth.uid() = user_id)`. No `WITH CHECK (true)` per `rf-rls-for-all-using-applies-to-writes`.
  - 2.3.5 `CREATE OR REPLACE FUNCTION acquire_conversation_slot(...) RETURNS TABLE(status text, active_count integer, effective_cap integer) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp`. Body uses `PERFORM set_config('lock_timeout','500ms',true)` (txn-scoped). `SELECT 1 FROM users WHERE id = p_user_id FOR UPDATE`. Lazy sweep. Upsert with `RETURNING (xmax = 0)`. Conditional rollback + cap_hit return.
  - 2.3.6 `CREATE OR REPLACE FUNCTION release_conversation_slot(...) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp`. Plain DELETE.
  - 2.3.7 `REVOKE ALL ... FROM PUBLIC; GRANT EXECUTE ... TO service_role`.
  - 2.3.8 `DO` block: if `pg_cron` extension exists, `cron.schedule('user_concurrency_slots_sweep', '* * * * *', ...)` deleting rows with `last_heartbeat_at < now() - interval '120 seconds'`.
- [ ] 2.4 Sibling precedent check: read migrations 025, 027, 028; confirm no `CONCURRENTLY`, same RLS-owner-read idiom.
- [ ] 2.5 Apply locally: `doppler run -p soleur -c dev -- supabase migration up`.
- [ ] 2.6 Re-run Phase 2 tests; confirm GREEN for all 7 scenarios.
- [ ] **Gate:** migration applies cleanly; 7 scenarios GREEN.

## Phase 3 — `plan-limits.ts` + `stripe-price-tier-map.ts` + `ClientSession` cache

- [ ] 3.1 RED: `lib/plan-limits.test.ts` (see plan for full matrix). Pin all numeric values with `.toBe`.
- [ ] 3.2 RED: `lib/stripe-price-tier-map.test.ts`:
  - 3.2.1 Known price IDs (env mocked) → correct tier via `.toBe`.
  - 3.2.2 Missing env var on **first `getPriceTier()` call** throws `Error("STRIPE_PRICE_ID_* missing: STRIPE_PRICE_ID_STARTUP")`.
  - 3.2.3 Unknown price id → `.toBe("free")` + Sentry warning dispatched once.
  - 3.2.4 Import does not throw when env vars are missing (lazy init).
- [ ] 3.3 RED: extend `ws-handler.test.ts`:
  - 3.3.1 Post-auth, `session.planTier` matches seeded `plan_tier`.
  - 3.3.2 Subscription refresh tick re-reads both `subscriptionStatus` and `planTier` in one query.
  - **Expected RED reason:** `session.planTier` is `undefined` because select excludes the column.
- [ ] 3.4 GREEN: implement `lib/plan-limits.ts` (pure constants + `effectiveCap` + `nextTier`; no env reads). No `PER_CONVERSATION_SPECIALIST_CAP` — `ROUTABLE_DOMAIN_LEADERS.length` inline in `dispatchToLeaders`.
- [ ] 3.5 GREEN: implement `lib/stripe-price-tier-map.ts` with lazy-init `getPriceTier()` and lazy-init `priceIdForTier()` (reverse lookup for checkout).
- [ ] 3.6 GREEN: extend `ClientSession` (lines 55–70) with `planTier?: PlanTier; concurrencyOverride?: number | null;`. Update auth success block (~line 840) select. Update refresh-timer body.
- [ ] **Gate:** three test files GREEN; `tsc --noEmit` clean; importing the price-map module in a test without env vars does NOT crash.

## Phase 4 — Stripe webhook handler (folds #2190)

- [ ] 4.1 RED: `test/integration/concurrency/stripe-webhook.test.ts`:
  - 4.1.1 `customer.subscription.updated` with Startup price + `active` → DB `plan_tier = "startup"`.
  - 4.1.2 Idempotency: replay same event twice → no double-write.
  - 4.1.3 `status = "incomplete"` → DB unchanged.
  - 4.1.4 `customer.subscription.deleted` out of order → guard prevents regression to free (folds #2190).
  - 4.1.5 `invoice.paid` → DB `plan_tier` unchanged.
  - 4.1.6 Downgrade (scale → solo): `subscription_downgraded_at = new Date(event.created * 1000)`; WS force-disconnect via `closeWithPreamble(4011)`.
  - 4.1.7 Re-upgrade: `subscription_downgraded_at` cleared to NULL.
  - **Expected RED reason:** `plan_tier` unchanged after `customer.subscription.updated` (handler branch missing).
- [ ] 4.2 GREEN: edit `app/api/webhooks/stripe/route.ts`:
  - 4.2.1 Verify via `stripe.webhooks.constructEventAsync(await req.text(), sig, secret)`.
  - 4.2.2 Branch on event type; map price via `getPriceTier()`.
  - 4.2.3 On `incomplete`: send `{type: "upgrade_pending"}` WS message; do NOT update `plan_tier`.
  - 4.2.4 Else: atomic `UPDATE users SET plan_tier, subscription_downgraded_at WHERE id = ? AND status IN (allowed_pre_states)`.
  - 4.2.5 Compute old vs new `effectiveCap`. On reduction: set `subscription_downgraded_at = event.created`, force-disconnect via `closeWithPreamble(4011)`. On increase/equal: clear `subscription_downgraded_at`.
  - 4.2.6 Invalidate `retrieveSubscriptionTier` memo for this user.
  - 4.2.7 Do NOT add a `config` export (per `cq-nextjs-route-files-http-only-exports`).
  - 4.2.8 Mirror any deny/fallback branch via `reportSilentFallback()`. Exempt: `incomplete` as intended state.
- [ ] 4.3 Run `cd apps/web-platform && npx next build --no-lint` after every edit (Kieran M1).
- [ ] 4.4 PR body: `Closes #2190`.
- [ ] **Gate:** integration tests GREEN; `next build` clean.

## Phase 5 — WS start_session slot acquire/release + heartbeat + fan-out slice + Stripe fallback

- [ ] 5.1 RED: `test/integration/concurrency/start-session-cap.test.ts`:
  - 5.1.1 Solo user, 2 conversations active → 3rd receives preamble + close 4010 + telemetry `path: "start_session"`.
  - 5.1.2 Complete one → 3rd retry succeeds.
  - **Expected RED reason:** WS closes with 1000 or times out.
- [ ] 5.2 RED: `test/integration/concurrency/reconnect-reclaim.test.ts`:
  - 5.2.1 Start conversation, abrupt close, reconnect within 120s, resume same `conversationId` → slot row count `.toBe(1)`.
  - **Expected RED reason:** row count is 0 (release removed it) or 2 (second acquire created new row).
- [ ] 5.3 RED: `test/integration/concurrency/fanout-single-slot.test.ts`:
  - 5.3.1 Free user (cap = 1), 1 conversation, `@all` fan-out → slot row count `.toBe(1)`; no `concurrency_cap_hit` emitted.
  - **Expected RED reason:** slot row count is 0 (acquire not wired) or 8 (per-leader acquire leaking).
- [ ] 5.4 RED: `server/agent-runner.fanout-slice.test.ts`:
  - 5.4.1 Stub `startAgentSession` spy. `dispatchToLeaders(userId, convId, [10 leaders], ...)` → spy called `.toBe(8)` times. `sendToClient` called with `{type: "fanout_truncated", dispatched: 8, dropped: 2}`.
  - 5.4.2 With ≤ 8 leaders: no slice, no notice.
  - **Expected RED reason:** spy called 10 times (slice not wired).
- [ ] 5.5 RED: `lib/stripe-retrieve-tier.test.ts`:
  - 5.5.1 Retrieve returns Startup price, `status: active` → `.toBe({tier: "startup", status: "active", at: ...})`.
  - 5.5.2 Second call within 60 s → cache hit; `stripe.subscriptions.retrieve` not invoked.
  - 5.5.3 `invalidateTierMemo(userId)` then next call → re-fetches.
  - **Expected RED reason:** helper missing.
- [ ] 5.6 GREEN: add `retrieveSubscriptionTier` + `invalidateTierMemo` to `lib/stripe.ts` — 60 s `Map`-based memo cache. No circuit breaker, no token bucket (deferred).
- [ ] 5.7 GREEN: slice in `agent-runner.ts` top of `dispatchToLeaders`:

  ```ts
  const ceiling = ROUTABLE_DOMAIN_LEADERS.length;
  if (leaders.length > ceiling) {
    sendToClient(userId, {
      type: "fanout_truncated",
      dispatched: ceiling,
      dropped: leaders.length - ceiling,
    });
    leaders = leaders.slice(0, ceiling);
  }
  ```

- [ ] 5.8 GREEN: acquire path in `ws-handler.ts` `start_session` (after rate-limit, before `dispatchToLeaders`):
  - 5.8.1 `cap = effectiveCap(session.planTier, session.concurrencyOverride)`.
  - 5.8.2 `supabase.rpc("acquire_conversation_slot", { p_user_id, p_conversation_id, p_effective_cap: cap })` with ≤3-attempt retry on `40P01`/`55P03` + ±100 ms jitter.
  - 5.8.3 On `cap_hit`: call `retrieveSubscriptionTier` once; if tier promotes, retry acquire.
  - 5.8.4 On persistent `cap_hit`: `closeWithPreamble(ws, 4010, {...})` + emit telemetry (`path: "start_session"`).
  - 5.8.5 On `ok`: proceed into existing validation + `dispatchToLeaders`.
- [ ] 5.9 GREEN: extend `pingInterval` at `ws-handler.ts:860` to re-call `acquire_conversation_slot` when `session.conversationId` set. Upsert semantics make this idempotent; also refreshes `last_heartbeat_at`.
- [ ] 5.10 GREEN: release paths — `abortActiveSession`, `ws.on("close")`, post-`session_ended` — all call `supabase.rpc("release_conversation_slot", ...)`. Swallow errors with Sentry mirror.
- [ ] **Gate:** all five test files GREEN; `ws-handler.test.ts` no regressions.

## Phase 6 — Checkout route for embedded + return_url

- [ ] 6.1 RED: `app/api/checkout/route.test.ts`:
  - 6.1.1 `{targetTier: "startup"}` with auth → Stripe session with `price = STRIPE_PRICE_ID_STARTUP`, `ui_mode = "embedded"`, `return_url` with `{CHECKOUT_SESSION_ID}` placeholder. Response has `clientSecret`.
  - 6.1.2 Unknown `targetTier` → 400.
  - 6.1.3 Missing auth → 401.
  - **Expected RED reason:** route accepts only legacy `STRIPE_PRICE_ID`; new `targetTier` param produces 400 or wrong price.
- [ ] 6.2 GREEN: refactor to use `priceIdForTier(targetTier)` from `stripe-price-tier-map.ts`. Keep legacy `STRIPE_PRICE_ID` path with `logger.warn` deprecation.
- [ ] 6.3 GREEN: handle `/dashboard?upgrade=complete&session_id=...` landing — force-reconnect WS (re-reads `plan_tier`); replay queued user action if present.
- [ ] 6.4 `cd apps/web-platform && npx next build --no-lint` after every edit.
- [ ] **Gate:** route tests GREEN; end-to-end Checkout → webhook → cap re-check succeeds with stub.

## Phase 7 — Frontend: `UpgradeAtCapacityModal` + `AccountStateBanner`

- [ ] 7.1 RED: `app/components/UpgradeAtCapacityModal.test.tsx`:
  - 7.1.1 Loading variant → exact loading copy (via `data-state="loading"` hook).
  - 7.1.2 Default Solo→Startup variant → exact strings from copy artifact; pin with `.toBe`.
  - 7.1.3 Error variant → error copy; primary CTA re-opens Checkout.
  - 7.1.4 Admin-override variant, enterprise-cap variant.
  - 7.1.5 Default variant has no "Maybe later" button.
  - 7.1.6 Primary CTA calls `/api/checkout` with `targetTier` and mounts `<EmbeddedCheckoutProvider>`.
  - 7.1.7 No layout-gated assertions per `cq-jsdom-no-layout-gated-assertions` — use `data-*` hooks.
  - 7.1.8 Sweep `global.fetch` mocks per `cq-preflight-fetch-sweep-test-mocks`.
  - **Expected RED reason:** component does not exist.
- [ ] 7.2 RED: `app/components/AccountStateBanner.test.tsx`:
  - 7.2.1 `variant="at-capacity"` → copy from artifact §3.
  - 7.2.2 `variant="downgrade-grace"` → copy from artifact §4.
  - **Expected RED reason:** component does not exist.
- [ ] 7.3 GREEN: implement `UpgradeAtCapacityModal.tsx` with `<EmbeddedCheckoutProvider>` + `<EmbeddedCheckout>`.
- [ ] 7.4 GREEN: implement `AccountStateBanner.tsx` — single primitive with `variant` prop.
- [ ] 7.5 GREEN: top-level layout listens for `openUpgradeModal` event (emitted by `ws-client.ts` Phase 1) and mounts the modal.
- [ ] **Gate:** all component tests GREEN.

## Phase 8 — Pricing page rewrite + wireframe re-render

- [ ] 8.1 Apply exact copy-artifact §2 strings to `plugins/soleur/docs/pages/pricing.njk` at lines 184, 199, 214–217, 228–233, FAQ 253–256, JSON-LD 287–291.
- [x] 8.2 Ship-prep task: dropped seat bullets entirely — pivot is conversation-slot-based, "seats" is legacy framing. Startup lost "Team collaboration (up to 3 seats)" and Scale lost "Up to 25 seats". CMO recommended a specific number; CPO flagged that seats are unenforced copy; user called it: drop both.
- [ ] 8.3 Grep checks — all must return zero in `pricing.njk`:

  ```bash
  rg -i "concurrent agent" plugins/soleur/docs/pages/pricing.njk
  rg -i "agents in parallel" plugins/soleur/docs/pages/pricing.njk
  rg -i "unlimited" plugins/soleur/docs/pages/pricing.njk
  ```

- [ ] 8.4 Run `npx markdownlint-cli2 --fix` targeting only the specific paths changed.
- [ ] 8.5 Eleventy build; JSON-LD validates.
- [ ] 8.6 Wireframe re-render:
  - 8.6.1 Pre-flight per `cq-pencil-mcp-silent-drop-diagnosis-checklist` — verify `PENCIL_CLI_KEY`, adapter-drift OK.
  - 8.6.2 `mcp__pencil__open_document` on the committed `.pen` path.
  - 8.6.3 Invoke `ux-design-lead` to re-render 5 states with the final copy; replace every "agents" with "conversations"; re-export PNG screenshots.
  - 8.6.4 Post-save: `stat -c %s` > 0.
  - 8.6.5 Grep saved JSON for `"agents"` — zero matches in customer-copy fields.
- [ ] 8.7 Commit regenerated `.pen` + screenshots.
- [ ] **Gate:** three greps return zero; Eleventy build clean; `.pen` > 0 bytes; no "agents" in customer-copy fields.

## Phase 9 — Telemetry

- [ ] 9.1 RED: `server/telemetry.concurrency-cap-hit.test.ts`:
  - 9.1.1 On cap-hit, event emitted with exactly 5 fields: `tier`, `active_conversation_count`, `effective_cap`, `action`, `path`. Each type pinned with `.toBe` (or `typeof ... === 'number'`).
  - 9.1.2 `action` defaults to `"abandoned"` if no client follow-up within 30 s.
  - 9.1.3 `path` is one of `"start_session" | "downgrade_sweep" | "hard_cap_24h"`.
  - 9.1.4 No extra fields (6 CFO additions deferred to #2626).
  - **Expected RED reason:** telemetry event not emitted at the cap-hit path.
- [ ] 9.2 GREEN: emit `concurrency_cap_hit` at each deny site:
  - 9.2.1 `ws-handler.ts` `start_session` cap-hit branch.
  - 9.2.2 pg_cron downgrade sweep (via a `system_events` Supabase table the cron writes to, or an app-side job that tails the sweep output — specify at implementation).
- [ ] 9.3 Verify event lands in analytics dashboard within 30 s of a staging cap-hit.
- [ ] **Gate:** telemetry test GREEN; staging event visible.

## Phase 10 — Ship + post-merge verification

### Pre-ship

- [ ] 10.1 Run the 30-day count query on prd Supabase (see plan §Phase 10). Record result in PR body.
- [ ] 10.2 If non-zero: enqueue the email template from copy artifact §6.
- [ ] 10.3 Append changelog entry from copy artifact §7 to `CHANGELOG.md`. Verify no line starts with `#NNNN` per `cq-prose-issue-ref-line-start`.
- [ ] 10.4 Run full app test suite. Verify `next build` clean.
- [ ] 10.5 `/soleur:qa` — Playwright MCP run covering 5 modal states + Checkout round-trip + `return_url` replay. Screenshots in PR.

### Ship

- [ ] 10.6 `/ship` with semver label `minor`. PR body: `Closes #1162`, `Closes #2188`, `Closes #2190`; references `#2624`, `#2625`, `#2626`.

### Post-merge (operator)

- [ ] 10.7 Verify migration `029` applied to prd Supabase via REST read-back:
  - `SELECT column_name FROM information_schema.columns WHERE table_name='users' AND column_name IN ('plan_tier','concurrency_override','subscription_downgraded_at')` — 3 rows.
  - `SELECT indexname FROM pg_indexes WHERE tablename='users' AND indexname='users_stripe_customer_id_unique'` — 1 row.
  - `SELECT to_regclass('public.user_concurrency_slots')` — non-NULL.
  - `SELECT polname FROM pg_policies WHERE tablename='user_concurrency_slots'` — `slots_owner_read`.
- [ ] 10.8 Confirm pg_cron sweep alive: `SELECT * FROM cron.job_run_details WHERE jobname='user_concurrency_slots_sweep' ORDER BY start_time DESC LIMIT 5` — at least one recent successful row. If `pg_cron` absent on prd, file follow-up and run the sweep from application code as a ≤5-line fallback.
- [ ] 10.9 Confirm four `STRIPE_PRICE_ID_*` present in Doppler `prd`; each resolves via `stripe.prices.retrieve` in live mode.
- [ ] 10.10 Real webhook end-to-end (test mode): subscribe test account to Startup; DB `plan_tier` flips within 30 s.
- [ ] 10.11 Real cap-hit on prd with internal test account: event appears in analytics dashboard with 5 fields.
- [ ] 10.12 `AccountStateBanner variant="at-capacity"` visible on a logged-in prd session.
- [ ] 10.13 Email (if any from Phase 10.2) dispatched.
- [ ] 10.14 Verify issues auto-closed: `gh pr view` → `#1162`, `#2188`, `#2190` closed.
- [ ] 10.15 Sentry watch 24 h for `reportSilentFallback` events tagged `feature="concurrency"`.

### Follow-up issues filed

- [x] 10.16 File: Scale-tier seat-number confirmation — resolved inline (seats removed per pivot; see 8.2). Filing CPO follow-up for Scale→Enterprise differentiator beyond concurrency (no enforceable seat ceiling means Enterprise needs SSO/SLA/higher-concurrency lever).
- [ ] 10.17 File: legacy `STRIPE_PRICE_ID` deprecation.
- [ ] 10.18 File: banner sunset at ship + 14 days.
- [ ] 10.19 File: `UpgradePendingBanner` for Stripe `incomplete` (reassess on first SCA complaint).
- [ ] 10.20 File: Stripe fallback circuit breaker + token bucket (when telemetry shows measurable false-deny rate).
- [ ] 10.21 Update `#2626` with the 6 deferred telemetry fields + required materialized-view spec.
