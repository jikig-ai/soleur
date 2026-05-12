// Shared per-turn cost writer used by both the legacy agent-runner.ts
// path and the cc-soleur-go dispatcher path. Centralizes the four
// side-effects that close the "API Usage" undercount loop:
//
//   1. Atomically increment `conversations.{total_cost_usd,
//      input_tokens, output_tokens, cache_read_input_tokens,
//      cache_creation_input_tokens}` via the v2 RPC.
//   2. Append a forensic row to `audit_byok_use` via the existing
//      `write_byok_audit` RPC (migration 037).
//   3. Fan out a `usage_update` WS event to the client (widened with
//      cache tokens).
//   4. Mirror all silent fallbacks to Sentry per
//      `cq-silent-fallback-must-mirror-to-sentry`.
//
// Fire-and-forget: turn termination must not block on DB writes. Per the
// plan's R3, the v2 RPC preserves the atomic UPDATE pattern from
// migration 017, so concurrent multi-leader turns remain race-safe.
import { randomUUID } from "node:crypto";

import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import { sendToClient } from "@/server/ws-handler";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("cost-writer");

let _supabase: ReturnType<typeof createServiceClient> | null = null;
function supabase() {
  return (_supabase ??= createServiceClient());
}

// SDK exposes nullable cache fields per
// `node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:69-70`.
// Coerce with `?? 0` at this boundary so DB writes never see NULL on a
// NOT NULL column. `input_tokens` is the SDK's uncached-input count —
// the "true" total input (matching the Anthropic Console headline) is
// `input_tokens + cache_read_input_tokens + cache_creation_input_tokens`
// (R8 mitigation; see plan §Risks).
export interface UsageDeltas {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
}

export interface TurnCostInput {
  totalCostUsd: number;
  usage: UsageDeltas;
  modelHint: string | null;
}

export function normalizeUsage(
  usage: { input_tokens?: number | null; output_tokens?: number | null; cache_read_input_tokens?: number | null; cache_creation_input_tokens?: number | null } | null | undefined,
): UsageDeltas {
  return {
    input_tokens: usage?.input_tokens ?? 0,
    output_tokens: usage?.output_tokens ?? 0,
    cache_read_input_tokens: usage?.cache_read_input_tokens ?? 0,
    cache_creation_input_tokens: usage?.cache_creation_input_tokens ?? 0,
  };
}

/**
 * Persist a single turn's cost + usage deltas. Called from both
 * `agent-runner.ts` (legacy single-leader path) and `cc-dispatcher.ts`
 * `onResult` (cc-soleur-go path). Fire-and-forget: the function awaits
 * nothing the caller cares about; failures land in Sentry via
 * `reportSilentFallback`.
 *
 * @param userId         Authenticated founder UUID.
 * @param conversationId Conversation UUID the turn belongs to.
 * @param leaderId       Domain leader id (cc-soleur-go uses the router
 *                       leader; legacy uses the per-message leader).
 * @param input          Cost + usage payload from the SDK result message.
 */
export function persistTurnCost(
  userId: string,
  conversationId: string,
  leaderId: string,
  input: TurnCostInput,
): void {
  const costDelta = Number.isFinite(input.totalCostUsd) ? input.totalCostUsd : 0;
  const usage = input.usage;

  // (1) Atomic increment via v2 RPC (5 deltas).
  supabase()
    .rpc("increment_conversation_cost", {
      conv_id: conversationId,
      cost_delta: costDelta,
      input_delta: usage.input_tokens,
      output_delta: usage.output_tokens,
      cache_read_delta: usage.cache_read_input_tokens,
      cache_creation_delta: usage.cache_creation_input_tokens,
    })
    .then(({ error }) => {
      if (error) {
        log.error(
          { err: error, conversationId },
          "Failed to increment conversation cost",
        );
        reportSilentFallback(error, {
          feature: "agent-cost-tracking",
          op: "increment",
          extra: {
            conversationId,
            costDelta,
            inputDelta: usage.input_tokens,
            outputDelta: usage.output_tokens,
            cacheReadDelta: usage.cache_read_input_tokens,
            cacheCreationDelta: usage.cache_creation_input_tokens,
          },
        });
      }
    });

  // (2) Forensic audit row via the existing migration-037 RPC. WORM
  //     trigger raises on UPDATE/DELETE, so plain INSERT semantics.
  //     Sub-cent precision is lost intentionally — the cent-precision
  //     surface stays on `conversations.total_cost_usd`. Duplicate
  //     audit rows on retry are tolerated (idempotency is not
  //     load-bearing for a forensic surface).
  const totalTokens =
    usage.input_tokens +
    usage.output_tokens +
    usage.cache_read_input_tokens +
    usage.cache_creation_input_tokens;
  supabase()
    .rpc("write_byok_audit", {
      p_invocation_id: randomUUID(),
      p_founder_id: userId,
      p_agent_role: leaderId,
      p_token_count: totalTokens,
      p_unit_cost_cents: Math.round(costDelta * 100),
    })
    .then(({ error }) => {
      if (error) {
        log.error(
          { err: error, conversationId, userId },
          "Failed to write byok audit row",
        );
        reportSilentFallback(error, {
          feature: "agent-cost-tracking",
          op: "audit-write",
          extra: { conversationId, totalTokens, costCents: Math.round(costDelta * 100) },
        });
      }
    });

  // (3) Fan out `usage_update` so the client cost badge reflects the
  //     just-billed turn. Widened with cache tokens so the chat-surface
  //     bubble can render the same Input semantics the dashboard does.
  sendToClient(userId, {
    type: "usage_update",
    conversationId,
    totalCostUsd: costDelta,
    inputTokens: usage.input_tokens,
    outputTokens: usage.output_tokens,
    cacheReadInputTokens: usage.cache_read_input_tokens,
    cacheCreationInputTokens: usage.cache_creation_input_tokens,
  });
}
