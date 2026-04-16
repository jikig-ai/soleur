# Tasks: fix(kb-chat) cost estimate not restored on conversation resume

Closes #2436

## Phase 1: Server -- Include cost data in messages API response

- [ ] 1.1 RED: Write test for api-messages handler returning cost fields
  - File: `apps/web-platform/test/api-messages-cost.test.ts`
  - Assert response includes `totalCostUsd`, `inputTokens`, `outputTokens`
  - Assert values match conversation row data
- [ ] 1.2 GREEN: Expand conversation query in `api-messages.ts`
  - File: `apps/web-platform/server/api-messages.ts`
  - Change `.select("id")` to `.select("id, total_cost_usd, input_tokens, output_tokens")`
  - Include cost fields in JSON response (camelCase: `totalCostUsd`, `inputTokens`, `outputTokens`)
  - blockedBy: 1.1

## Phase 2: Client -- Seed usageData from history fetch

- [ ] 2.1 RED: Write test for usageData seeding on resume
  - File: `apps/web-platform/test/ws-usage-update.test.ts` (extend)
  - Test that historical cost data seeds `usageData` state
  - Test race condition: `usage_update` before fetch resolves does NOT get overwritten
- [ ] 2.2 GREEN: Update `fetchConversationHistory` to return cost data
  - File: `apps/web-platform/lib/ws-client.ts`
  - Update return type to include `{ messages, totalCostUsd, inputTokens, outputTokens }`
  - Parse cost fields from fetch response
  - blockedBy: 2.1
- [ ] 2.3 GREEN: Seed `setUsageData` in both resume effects
  - File: `apps/web-platform/lib/ws-client.ts`
  - In mount-time effect (line ~427): after setting messages, seed usageData if null
  - In realConversationId effect (line ~452): after setting messages, seed usageData if null
  - Guard: `setUsageData(prev => prev ?? fetchedCostData)` to avoid overwriting in-flight accumulation
  - blockedBy: 2.2

## Phase 3: Integration test

- [ ] 3.1 Extend chat-page-resume test for cost display
  - File: `apps/web-platform/test/chat-page-resume.test.tsx` (extend)
  - Set `usageData` in mock `wsReturn` to simulate resumed cost
  - Assert cost estimate text appears in rendered output
  - blockedBy: 2.3
