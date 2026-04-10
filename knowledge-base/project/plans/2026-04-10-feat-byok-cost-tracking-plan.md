---
title: "feat: Usage/cost indicator for BYOK spending"
type: feat
date: 2026-04-10
---

# feat: Usage/cost indicator for BYOK spending

## Overview

Add cost transparency for BYOK users across two UI surfaces: a live cost indicator during active conversations (updating per agent turn) and a conversation cost list on the billing page. The Agent SDK already provides `total_cost_usd` on every result message — the codebase currently discards it.

**Issue:** #1691
**Brainstorm:** `knowledge-base/project/brainstorms/2026-04-10-byok-cost-tracking-brainstorm.md`
**Spec:** `knowledge-base/project/specs/feat-byok-cost-tracking/spec.md`
**Deferred:** #1866 (budget setting/progress bar)

## Problem Statement

BYOK users bear AI model costs directly via their own API keys but have zero visibility into spending. The subscription covers platform costs; AI model costs are separate. Without cost transparency, users cannot budget or understand which conversations are expensive.

## Proposed Solution

Single-pass implementation across four layers: database migration, server-side capture, WebSocket transport, and frontend display. Ships as one coherent PR.

## Technical Approach

### Architecture

```text
SDK Result Message ──► agent-runner.ts ──► UPDATE conversations SET total_cost_usd += delta
                              │
                              ▼
                       sendToClient({ type: "usage_update", ... })
                              │
                              ▼
                       ws-client.ts ──► React state update
                              │
                              ▼
                 ┌─────────────┴─────────────┐
                 │                           │
        Conversation UI              Billing Page
        (live indicator)         (conversation cost list)
```

### Implementation Phases

#### Phase 1: Database Migration

**File:** `apps/web-platform/supabase/migrations/017_conversation_cost_tracking.sql`

Add cost columns to `conversations` table and an atomic increment function:

```sql
-- Cost tracking columns (minimal: dollar cost + token counts)
ALTER TABLE conversations
  ADD COLUMN total_cost_usd NUMERIC(10, 6) DEFAULT 0,
  ADD COLUMN input_tokens INTEGER DEFAULT 0,
  ADD COLUMN output_tokens INTEGER DEFAULT 0;

-- Atomic increment to avoid race conditions under concurrent multi-leader turns
CREATE OR REPLACE FUNCTION increment_conversation_cost(
  conv_id UUID,
  cost_delta NUMERIC,
  input_delta INTEGER,
  output_delta INTEGER
) RETURNS VOID AS $$
BEGIN
  UPDATE conversations SET
    total_cost_usd = total_cost_usd + cost_delta,
    input_tokens = input_tokens + input_delta,
    output_tokens = output_tokens + output_delta
  WHERE id = conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

RLS policy: existing `conversations` RLS already scopes to `user_id`. New columns inherit the table-level grant — no separate column policy needed (per learning: column-level REVOKE is silently ineffective with table-level grants).

**Gotcha:** No down migration. Cost data is financial PII — irreversible by design per GDPR remediation learning.

**[Updated 2026-04-10] Review changes applied:** Dropped `cache_read_tokens`, `cache_creation_tokens`, and `model_usage JSONB` columns per reviewer consensus (YAGNI — users need dollar cost, not cache internals or per-model splits). Added atomic increment function per Kieran's correctness finding (avoids race conditions).

#### Phase 2: Server-Side Cost Capture

**File:** `apps/web-platform/server/agent-runner.ts` (insertion at lines 711-714)

In the `message.type === "result"` handler, after `saveMessage` and before `syncPush`:

```typescript
// Capture cost data from SDK result (per-turn delta)
const costDelta = message.total_cost_usd ?? 0;
const inputDelta = message.usage?.input_tokens ?? 0;
const outputDelta = message.usage?.output_tokens ?? 0;

// Atomic increment — safe under concurrent multi-leader turns
const { error: costError } = await supabase.rpc(
  "increment_conversation_cost",
  {
    conv_id: conversationId,
    cost_delta: costDelta,
    input_delta: inputDelta,
    output_delta: outputDelta,
  }
);

if (costError) {
  console.error("Failed to save cost data:", costError.message);
  // Non-blocking — don't fail the conversation over cost tracking
}

// Stream cost update to client
sendToClient(userId, {
  type: "usage_update",
  conversationId,
  totalCostUsd: costDelta,
  inputTokens: inputDelta,
  outputTokens: outputDelta,
});
```

**Cost accumulation strategy:** Each SDK result's `total_cost_usd` is the cost for that single agent turn invocation (the conversation runner calls the SDK once per turn). Use atomic increment (`total_cost_usd = total_cost_usd + delta`) to accumulate safely across concurrent turns. Verify this assumption at implementation time by logging the first few results.

**Gotcha:** Always destructure `{ error }` from Supabase calls — client never throws (per learning). Log errors but don't block the conversation.

#### Phase 3: WebSocket Types and Client

**File:** `apps/web-platform/lib/types.ts` (lines 34-48)

Add to the `WSMessage` discriminated union:

```typescript
| {
    type: "usage_update";
    conversationId: string;
    totalCostUsd: number;
    inputTokens: number;
    outputTokens: number;
  }
```

**File:** `apps/web-platform/lib/ws-client.ts` (lines 132-284)

Add `case "usage_update"` to the switch handler. Accumulate cost in React state (each message is a per-turn delta):

```typescript
case "usage_update":
  setUsageData((prev) => ({
    totalCostUsd: (prev?.totalCostUsd ?? 0) + msg.totalCostUsd,
    inputTokens: (prev?.inputTokens ?? 0) + msg.inputTokens,
    outputTokens: (prev?.outputTokens ?? 0) + msg.outputTokens,
  }));
  break;
```

Return `usageData` from the `useWebSocket` hook. Persist last-known value on WS disconnect (don't reset to zero).

**Gotcha:** Follow error sanitization pattern — never include raw error messages if the cost update fails (per CWE-209 learning).

#### Phase 4: Live Cost Indicator (Conversation UI)

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

Add a cost badge in the status bar area (lines 282-289), next to the `{activeLeaderIds.length} leaders responding` text:

```tsx
{usageData && usageData.totalCostUsd > 0 && (
  <span className="text-xs text-neutral-400">
    ~${usageData.totalCostUsd.toFixed(4)}
    <span className="text-neutral-500 ml-1">estimated</span>
  </span>
)}
```

Design tokens: match existing status bar — `text-xs`, `text-neutral-400`, no additional background. The `~` prefix and "estimated" label address the cost accuracy concern from the brainstorm.

Mobile: `text-xs` is already compact. No special mobile treatment needed — it's a single line of text.

#### Phase 5: Billing Page Conversation Cost List

**File:** `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx`

Add a usage section below the existing subscription card inside the `max-w-md space-y-6` wrapper. **Flat list only — no tabs, no time-range selector, no aggregation queries.**

Query `conversations` WHERE `user_id = current` AND `total_cost_usd > 0`, ordered by `created_at DESC`, limit 50. Display each as a row: domain leader label, relative timestamp, cost (`~$X.XXXX estimated`).

Empty state: "No API usage yet. Conversations will appear here with their costs." Show only when user has a BYOK key configured but no cost data.

**Design tokens:** Match existing billing page — `bg-neutral-900` card, `border-neutral-700` borders, `text-neutral-400` secondary text, `rounded-lg`, `text-sm`.

**Supabase queries:** Destructure `{ data, error }` and handle errors gracefully (per learning).

**[Updated 2026-04-10] Review changes applied:** Tabs (per-conversation, tokens breakdown, per-domain), time-range selector, and aggregation queries cut per reviewer consensus. Ship a flat list; add breakdowns when users request them.

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Separate `usage_events` table (per-turn records) | Over-engineered for MVP — per-conversation columns suffice. Revisit if per-turn drill-down is requested. |
| Independent pricing table | Maintenance burden when Anthropic changes rates. SDK's `costUSD` is authoritative. |
| Real-time streaming estimation (per-chunk) | Requires verifying SDK streaming event usage data. Per-turn updates are accurate and simpler. |
| New `/dashboard/usage` page | Extra surface to maintain. Billing page already exists. |
| Token-count estimation during streaming | Inaccurate (character-count heuristic). |
| Tabbed dashboard with time-range selector | Over-scoped for MVP (per plan review). Ship flat list, add breakdowns when users ask. |
| `model_usage` JSONB + cache token columns | YAGNI — users need dollar cost, not per-model splits or cache internals. SDK data is available for backfill. |

## Acceptance Criteria

### Functional Requirements

- [x] Per-conversation cost captured from SDK result and stored in `conversations` table via atomic increment (`agent-runner.ts`)
- [x] `usage_update` WebSocket message sent to client after each agent turn
- [x] Live cost indicator visible in conversation UI during active conversations
- [x] Billing page shows conversation cost list (flat list, most recent first)
- [x] All cost figures labeled as "estimated"
- [x] Works on mobile viewport (PWA)

### Non-Functional Requirements

- [x] Cost tracking does not block conversation flow (non-blocking error handling)
- [x] New migration is forward-only (no down migration)
- [x] RLS enforced — users see only their own cost data
- [x] No raw error messages exposed to client via WebSocket

## Domain Review

**Domains relevant:** Product, Marketing, Engineering

### Marketing (CMO) — carried forward from brainstorm

**Status:** reviewed
**Assessment:** Live cost indicator creates a "taxi meter effect" (loss aversion). Pricing tension between $49/month flat messaging and visible BYOK API costs. Opportunity: full cost transparency as trust differentiator. Recommends delegating layout to conversion-optimizer and mobile to ux-design-lead.

### Engineering (CTO) — carried forward from brainstorm

**Status:** reviewed
**Assessment:** SDK provides all required data but codebase discards it. Per-conversation columns on conversations table. Per-turn updates avoid streaming estimation complexity. Affected: agent-runner.ts, types.ts, ws-client.ts, billing page, migration + RLS.

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** ux-design-lead
**Skipped specialists:** spec-flow-analyzer (agent rate-limited), cpo (agent rate-limited), copywriter (not invoked — flat list has minimal copy)
**Pencil available:** yes

#### Wireframes

Design file: `knowledge-base/product/design/byok-cost-tracking/cost-tracking-wireframes.pen`
Screenshots: `knowledge-base/product/design/byok-cost-tracking/screenshots/`

- `01-desktop-chat-status-bar.png` — Status bar: "3 leaders responding · ~$0.0042 estimated"
- `02-mobile-chat-status-bar.png` — Mobile variant, abbreviated to "~$0.0042 est."
- `03-desktop-billing-page.png` — API Usage section with running total and conversation cost cards
- `04-mobile-billing-page.png` — Mobile variant with reduced padding
- `05-desktop-billing-empty-state.png` — "No API usage yet" with helper text

#### Findings

- **Flow gap: No API key state** — Cost indicator should not render. Billing usage section shows empty state prompting key setup.
- **Flow gap: WS disconnect** — Last-known cost persists in React state (not reset to zero). Next turn updates with authoritative SDK total.
- **Flow gap: Loading state** — Cost indicator absent until first turn completes (no skeleton/spinner).
- **Mobile** — Status bar cost badge abbreviated on mobile. Billing list uses reduced padding.

[Updated 2026-04-10] UX gate originally missed due to agent rate limits. Plan skill fixed to enforce BLOCKING gates on agent failure. Wireframes produced retroactively.

## Test Scenarios

### Acceptance Tests

- Given a BYOK user starts a conversation, when the agent completes a turn, then the conversation's `total_cost_usd` column is incremented by the SDK's reported cost
- Given a BYOK user is viewing an active conversation, when an agent turn completes, then the live cost indicator updates to show the accumulated dollar cost
- Given a BYOK user visits the billing page, when they have conversations with cost data, then a flat list shows each conversation with its domain and cost
- Given two concurrent agent turns in the same conversation, when both complete, then the total cost reflects both increments (atomic update, no race condition)

### Edge Cases

- Given a conversation where the SDK result has `total_cost_usd: 0` (e.g., cached response), when viewing the billing page, then zero-cost conversations are included in the list but don't inflate totals
- Given a Supabase cost update fails, when the agent completes a turn, then the conversation still completes normally (cost tracking is non-blocking) and the error is logged server-side
- Given a user with no conversations, when visiting the billing page usage section, then an empty state message is shown (not an error)
- Given a user on mobile viewport, when viewing the live cost indicator, then the indicator fits within the status bar without overflow

### Integration Verification

- **Browser:** Navigate to `/dashboard/billing`, verify conversation cost list appears below subscription card
- **Browser:** Start a conversation with a BYOK key, verify cost indicator appears in status bar after first agent turn completes
- **API verify:** After a conversation, query `conversations` table for `total_cost_usd > 0` to verify persistence

## Dependencies and Prerequisites

- Agent SDK `SDKResultMessage` exposes `total_cost_usd`, `usage`, `modelUsage` — **verified available** in current SDK (`@anthropic-ai/claude-agent-sdk`)
- Multi-turn conversations (#1044) — **CLOSED**, dependency met
- Supabase migration infrastructure — exists, next number is `017`

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SDK changes `total_cost_usd` field name | Low | High | Pin SDK version in package.json. Add type assertion. |
| Cost data diverges from Anthropic billing | Medium | Medium | Label as "estimated" in all UI. SDK cost is best-effort. |
| Taxi meter effect reduces conversation quality | Medium | Medium | Accepted trade-off per brainstorm. Budget feature (#1866) deferred. |
| GDPR deletion cascade missing cost data | Low | High | TR6 in spec tracks this. Blocked by roadmap items 2.4/2.9. |

## References and Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:711-732` — SDK result handler (insertion point)
- `apps/web-platform/lib/types.ts:34-48` — WSMessage discriminated union
- `apps/web-platform/lib/ws-client.ts:132-284` — WS message switch handler
- `apps/web-platform/supabase/migrations/016_github_username.sql` — latest migration
- `apps/web-platform/supabase/migrations/001_initial_schema.sql:46-56` — conversations table
- `apps/web-platform/app/(dashboard)/dashboard/billing/page.tsx` — billing page (126 lines)
- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:282-289` — conversation status bar

### Institutional Learnings Applied

- Supabase silent error returns — always destructure `{ data, error }` (`2026-03-20`)
- Column-level REVOKE ineffective — rely on table-level RLS (`2026-03-20`)
- WebSocket error sanitization CWE-209 — never forward raw err.message (`2026-03-20`)
- GDPR migration — no down migration for financial PII (`2026-03-20`)
- WebSocket TOCTOU race — check `ws.readyState` after async (`2026-03-20`)

### Related Issues

- #1691 — This feature
- #1866 — Deferred budget setting/progress bar
- #1044 — Multi-turn conversations (CLOSED, dependency met)
- #672 — Phase 3 parent epic
