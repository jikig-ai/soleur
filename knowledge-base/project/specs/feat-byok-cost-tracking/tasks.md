# Tasks: BYOK Usage/Cost Indicator

**Plan:** [2026-04-10-feat-byok-cost-tracking-plan.md](../../plans/2026-04-10-feat-byok-cost-tracking-plan.md)
**Issue:** #1691
**Branch:** byok-cost-tracking

## Phase 1: Database Migration

- [x] 1.1 Create `017_conversation_cost_tracking.sql` migration
  - Add columns: `total_cost_usd NUMERIC(10,6) DEFAULT 0`, `input_tokens INTEGER DEFAULT 0`, `output_tokens INTEGER DEFAULT 0`
  - Create `increment_conversation_cost` RPC function (atomic increment, SECURITY DEFINER)
  - No down migration (financial PII)
  - Verify latest migration number before creating (may not be 017)
  - File: `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql`

## Phase 2: Server-Side Cost Capture

- [x] 2.1 Capture SDK cost data in agent-runner result handler
  - Extract `total_cost_usd`, `input_tokens`, `output_tokens` from `SDKResultMessage`
  - Insert at `agent-runner.ts:711-714` (after `saveMessage`, before `syncPush`)
  - Verify at implementation time: is `total_cost_usd` per-turn or cumulative? Log first few results.
  - File: `apps/web-platform/server/agent-runner.ts`
- [x] 2.2 Persist cost data via atomic RPC call
  - Call `increment_conversation_cost` with deltas
  - Always destructure `{ error }` — non-blocking on failure
  - File: `apps/web-platform/server/agent-runner.ts`
- [x] 2.3 Stream `usage_update` WebSocket message to client
  - Send per-turn cost delta after persisting
  - File: `apps/web-platform/server/agent-runner.ts`

## Phase 3: WebSocket Types and Client

- [x] 3.1 Add `usage_update` variant to WSMessage union
  - Fields: `conversationId`, `totalCostUsd`, `inputTokens`, `outputTokens`
  - File: `apps/web-platform/lib/types.ts`
- [x] 3.2 Add `case "usage_update"` handler in ws-client
  - Accumulate cost in React state (each message is a delta)
  - Persist last-known value on WS disconnect (don't reset)
  - Return `usageData` from `useWebSocket` hook
  - File: `apps/web-platform/lib/ws-client.ts`

## Phase 4: Live Cost Indicator

- [x] 4.1 Add cost badge to conversation status bar
  - Display `~$X.XXXX estimated` next to leader count
  - Only render when `usageData.totalCostUsd > 0`
  - Guard on BYOK key existence (don't show for non-BYOK users)
  - Match status bar design tokens: `text-xs`, `text-neutral-400`
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

## Phase 5: Billing Page Conversation Cost List

- [x] 5.1 Add conversation cost list to billing page
  - Query conversations WHERE user_id = current AND total_cost_usd > 0, ORDER BY created_at DESC, LIMIT 50
  - Display: domain leader label, relative timestamp, cost (`~$X.XXXX estimated`)
  - Empty state: "No API usage yet"
  - Destructure `{ data, error }` on all Supabase calls
  - Match billing page design tokens: `bg-neutral-900`, `border-neutral-700`, `text-sm`
  - File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`

## Phase 6: Testing and Verification

- [x] 6.1 Write tests for cost capture in agent-runner
  - Verify cost delta extracted from SDK result message
  - Verify `increment_conversation_cost` RPC called with correct params
  - Verify non-blocking on Supabase error
  - Verify `usage_update` WS message sent with delta
- [x] 6.2 Write tests for billing page cost list
  - Verify list renders conversations with costs
  - Verify empty state when no conversations
- [ ] 6.3 Browser verification
  - Navigate to /dashboard/billing, verify cost list below subscription card
  - Start conversation, verify cost indicator in status bar after first turn
  - Test on mobile viewport
