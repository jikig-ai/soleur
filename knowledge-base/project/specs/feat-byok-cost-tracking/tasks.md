# Tasks: BYOK Usage/Cost Indicator

**Plan:** [2026-04-10-feat-byok-cost-tracking-plan.md](../../plans/2026-04-10-feat-byok-cost-tracking-plan.md)
**Issue:** #1691
**Branch:** byok-cost-tracking

## Phase 1: Database Migration

- [ ] 1.1 Create `017_conversation_cost_tracking.sql` migration
  - Add columns: `total_cost_usd NUMERIC(10,6)`, `input_tokens INTEGER`, `output_tokens INTEGER`, `cache_read_tokens INTEGER`, `cache_creation_tokens INTEGER`, `model_usage JSONB`
  - All default to 0 or `'{}'`
  - No down migration (financial PII)
  - File: `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql`

## Phase 2: Server-Side Cost Capture

- [ ] 2.1 Capture SDK cost data in agent-runner result handler
  - Extract `total_cost_usd`, `usage`, `modelUsage` from `SDKResultMessage`
  - Insert at `agent-runner.ts:711-714` (after `saveMessage`, before `syncPush`)
  - File: `apps/web-platform/server/agent-runner.ts`
- [ ] 2.2 Persist cost data to conversations table
  - UPDATE conversations SET cost columns WHERE id = conversationId
  - `total_cost_usd` is cumulative per SDK (store directly, no summing)
  - Deep-merge `model_usage` JSONB across turns
  - Always destructure `{ error }` — non-blocking on failure
  - File: `apps/web-platform/server/agent-runner.ts`
- [ ] 2.3 Stream `usage_update` WebSocket message to client
  - Call `sendToClient` with usage data after persisting
  - File: `apps/web-platform/server/agent-runner.ts`

## Phase 3: WebSocket Types and Client

- [ ] 3.1 Add `usage_update` variant to WSMessage union
  - Fields: `conversationId`, `totalCostUsd`, `inputTokens`, `outputTokens`, `cacheReadTokens`, `cacheCreationTokens`, `modelUsage`
  - File: `apps/web-platform/lib/types.ts`
- [ ] 3.2 Add `case "usage_update"` handler in ws-client
  - Create `usageData` state via `useState`
  - Return `usageData` from `useWebSocket` hook
  - File: `apps/web-platform/lib/ws-client.ts`

## Phase 4: Live Cost Indicator

- [ ] 4.1 Add cost badge to conversation status bar
  - Display `~$X.XXXX estimated` next to leader count
  - Only render when `usageData.totalCostUsd > 0`
  - Guard on BYOK key existence (don't show for non-BYOK users)
  - Persist last-known cost in React state on WS disconnect
  - Match status bar design tokens: `text-xs`, `text-neutral-400`
  - File: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

## Phase 5: Billing Page Usage Dashboard

- [ ] 5.1 Create usage section component with three tabs
  - Tab navigation: Per-Conversation / Tokens / By Domain
  - Time range selector: Day / Week / Month (default: Month)
  - Place below existing subscription card in `max-w-md space-y-6` wrapper
  - File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`
- [ ] 5.2 Implement Per-Conversation tab
  - Query conversations WHERE user_id = current AND total_cost_usd > 0
  - Display: domain leader, timestamp, cost
  - Empty state for no conversations
  - File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`
- [ ] 5.3 Implement Tokens Breakdown tab
  - Aggregate input/output/cache tokens by time range
  - Per-model breakdown from model_usage JSONB
  - Show Opus/Sonnet/Haiku separately with costUSD
  - File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`
- [ ] 5.4 Implement Cost by Domain tab
  - Aggregate by domain_leader: total cost, conversation count
  - File: `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`
- [ ] 5.5 Add responsive design for mobile
  - Stack tabs vertically if viewport too narrow
  - Test on mobile viewport

## Phase 6: Testing and Verification

- [ ] 6.1 Write tests for cost capture in agent-runner
  - Verify cost data extracted from SDK result message
  - Verify non-blocking on Supabase error
  - Verify usage_update WS message sent
- [ ] 6.2 Write tests for billing page usage section
  - Verify three tabs render
  - Verify time range filtering
  - Verify empty state
- [ ] 6.3 Browser verification
  - Navigate to /dashboard/billing, verify usage section with tabs
  - Start conversation, verify cost indicator appears after first turn
  - Test on mobile viewport
