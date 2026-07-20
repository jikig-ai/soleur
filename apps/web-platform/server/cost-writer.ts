// Shared per-turn cost writer used by both the legacy agent-runner.ts
// path and the cc-soleur-go dispatcher path. Centralizes the four
// side-effects that close the "API Usage" undercount loop:
//
//   1. Atomically increment `conversations.{total_cost_usd,
//      input_tokens, output_tokens, cache_read_input_tokens,
//      cache_creation_input_tokens}` via the v2 RPC.
//   2a. Solo path — append a forensic row to `audit_byok_use` via the
//      existing `write_byok_audit` RPC (migration 037).
//   2b. BYOK Delegations PR-A (#4232) — when `delegationId` is set,
//      route the audit through the merged atomic RPC
//      `check_and_record_byok_delegation_use` (migration 064) which
//      performs grace + expired + hourly + daily cap checks under a
//      single FOR UPDATE row lock before INSERTing the audit row.
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
import { reportSilentFallback, mirrorP0Deduped } from "@/server/observability";
import { sendToClient } from "@/server/ws-handler";
import { createChildLogger } from "@/server/logger";
import {
  emitClaudeCostMarker,
  type ClaudeCostSource,
} from "@/server/claude-cost-marker";
import {
  ByokDelegationRevokedError,
  ByokDelegationExpiredError,
  ByokDelegationHourlyCapError,
  ByokDelegationDailyCapError,
  ByokDelegationCrossTenantError,
} from "./byok-resolver";

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
}

/**
 * Persist a single turn's cost + usage deltas. Called from both
 * `agent-runner.ts` (legacy single-leader path) and `cc-dispatcher.ts`
 * `onResult` (cc-soleur-go path). Fire-and-forget: the function awaits
 * nothing the caller cares about; failures land in Sentry via
 * `reportSilentFallback`.
 *
 * Phase 3 (feat-team-workspace-multi-user) — `workspaceId` is the
 * `audit_byok_use.workspace_id` value (NOT NULL after migration 059).
 * Threads through `write_byok_audit`'s 6-arg signature (migration 061).
 *
 * @param userId         Authenticated founder UUID (BYOK key owner).
 * @param conversationId Conversation UUID the turn belongs to.
 * @param leaderId       Domain leader id (cc-soleur-go uses the router
 *                       leader; legacy uses the per-message leader).
 * @param workspaceId    Workspace UUID for cost attribution. Sourced from
 *                       `lease.workspaceContextUserId` under the N2
 *                       invariant; future non-solo callers resolve via
 *                       `workspace-resolver.getDefaultWorkspaceForUser`.
 * @param input          Cost + usage payload from the SDK result message.
 */
/**
 * BYOK Delegations PR-A (#4232). Optional delegation context. When
 * `delegationId` is set, the audit RPC routes to the merged atomic
 * `check_and_record_byok_delegation_use` (mig 064) which enforces
 * caps under a row lock + writes the audit row with attribution
 * shift on post-grace/expired paths. `callerUserId` is the actual
 * lease consumer (grantee under delegation, self under solo); see
 * the SS F3 invariant comment in `byok-resolver.ts`.
 */
export interface ByokDelegationContext {
  delegationId: string;
  callerUserId: string;
}

// Attribution marker context threaded from the 3 session call sites
// (`agent-runner`, `cc-dispatcher`, `agent-on-spawn-requested`; plan R2/R6).
// `TurnCostInput` carries neither `source` nor `model`, so we widen the
// signature rather than mutate the cost payload (hr-type-widening-cross-
// consumer-grep).
export interface TurnCostMarker {
  source: ClaudeCostSource;
  model: string | null;
}

export function persistTurnCost(
  userId: string,
  conversationId: string,
  leaderId: string,
  workspaceId: string,
  input: TurnCostInput,
  marker: TurnCostMarker,
  delegation?: ByokDelegationContext,
): void {
  const costDelta = Number.isFinite(input.totalCostUsd) ? input.totalCostUsd : 0;
  const usage = input.usage;

  // Side-effect #5 (plan Phase 1): emit the queryable cost marker. Synchronous,
  // BEFORE the fire-and-forget RPCs (does not change turn timing). Fail-open —
  // `emitClaudeCostMarker` never throws.
  emitClaudeCostMarker({
    source: marker.source,
    model: marker.model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    cache_read_input_tokens: usage.cache_read_input_tokens,
    cache_creation_input_tokens: usage.cache_creation_input_tokens,
    cost_usd: costDelta,
    id: conversationId,
    capture_status: "ok",
  });

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

  // (2) Forensic audit row. WORM trigger raises on UPDATE/DELETE, so
  //     plain INSERT semantics. Sub-cent precision is lost intentionally
  //     — the cent-precision surface stays on
  //     `conversations.total_cost_usd`. With `invocation_id` UNIQUE
  //     (mig 064Phase 0.9), the merged RPC's `ON CONFLICT
  //     (invocation_id) DO NOTHING` makes Inngest retries idempotent.
  const totalTokens =
    usage.input_tokens +
    usage.output_tokens +
    usage.cache_read_input_tokens +
    usage.cache_creation_input_tokens;
  const invocationId = randomUUID();
  const unitCostCents = Math.round(costDelta * 100);

  if (delegation) {
    // (2b) Delegated path — merged atomic RPC. SQLSTATE P0001 with a
    // `^byok_delegations:<reason>` message maps to sibling errors
    // (see ByokDelegationError hierarchy in byok-resolver.ts). The
    // RPC itself writes the audit row with `attribution_shift_reason`
    // set on post-grace / expired paths; cap-exceeded raises WITHOUT
    // a row.
    supabase()
      .rpc("check_and_record_byok_delegation_use", {
        p_delegation_id: delegation.delegationId,
        p_invocation_id: invocationId,
        p_token_count: totalTokens,
        p_unit_cost_cents: unitCostCents,
        p_caller_user_id: delegation.callerUserId,
        p_agent_role: leaderId,
      })
      .then(({ error }) => {
        if (!error) return;
        const message = error.message ?? "";
        const baseExtra = {
          conversationId,
          delegationId: delegation.delegationId,
          totalTokens,
          costCents: unitCostCents,
        };
        if (message.includes("byok_delegations:revoked_post_grace")) {
          reportSilentFallback(
            new ByokDelegationRevokedError(delegation.delegationId),
            { feature: "byok-delegations", op: "revoke-past-grace", extra: baseExtra },
          );
        } else if (message.includes("byok_delegations:expired")) {
          reportSilentFallback(
            new ByokDelegationExpiredError(delegation.delegationId),
            { feature: "byok-delegations", op: "expired", extra: baseExtra },
          );
        } else if (message.includes("byok_delegations:hourly_cap_exceeded")) {
          reportSilentFallback(
            new ByokDelegationHourlyCapError(delegation.delegationId),
            { feature: "byok-delegations", op: "hourly-cap-exceeded", extra: baseExtra },
          );
        } else if (message.includes("byok_delegations:daily_cap_exceeded")) {
          reportSilentFallback(
            new ByokDelegationDailyCapError(delegation.delegationId),
            { feature: "byok-delegations", op: "daily-cap-exceeded", extra: baseExtra },
          );
        } else if (message.includes("byok_delegations:cross-tenant:")) {
          // GDPR Art. 33 breach surface: the grantee used the grantor's BYOK
          // key from outside the grantor's workspace. Route through
          // `mirrorP0Deduped` (#4656 items 2+3) — NOT `reportSilentFallback`:
          //   - FATAL severity (a cross-tenant key leak is a breach, not a
          //     degraded fallback) so it pages, not folds into noise. This is
          //     the load-bearing distinction from `reportSilentFallback`, which
          //     captures at default (error) severity with no clock anchor.
          //   - `first_seen_at` + `severity=breach_attempt` clock anchor for the
          //     Art. 33(1) 72h notification window (item 3), even when re-fires
          //     within the 1h dedup window are suppressed.
          //   - Pino mirror BEFORE the try/catch-guarded Sentry call, so a
          //     swallowed/rate-limited Sentry capture still leaves a durable
          //     stdout signal (item 2 — capture-swallow resilience).
          // The `feature` + `art33Breach` options carry the two tags the
          // `byok_art_33_breach` rule (#4364) filters on (filter_match="all"):
          // `feature=byok-delegations` AND `art_33_breach=true`. Raise string is
          // the HYPHEN form `byok_delegations:cross-tenant:` per mig 064
          // L214/220/227 (sibling reasons use underscores; only cross-tenant is
          // hyphenated in the migration).
          mirrorP0Deduped(
            new ByokDelegationCrossTenantError(delegation.delegationId),
            {
              op: "cross-tenant-violation",
              userId,
              conversationId,
              delegationId: delegation.delegationId,
              feature: "byok-delegations",
              art33Breach: true,
            },
          );
        } else {
          log.error(
            { err: error, conversationId, userId, delegationId: delegation.delegationId },
            "Failed to record delegation use",
          );
          reportSilentFallback(error, {
            feature: "byok-delegations",
            op: "merged-rpc-failure",
            extra: baseExtra,
          });
        }
      });
  } else {
    // (2a) Solo path — existing migration-037 RPC (extended to 6 args
    // in mig 061 with p_workspace_id).
    supabase()
      .rpc("write_byok_audit", {
        p_invocation_id: invocationId,
        p_founder_id: userId,
        p_workspace_id: workspaceId,
        p_agent_role: leaderId,
        p_token_count: totalTokens,
        p_unit_cost_cents: unitCostCents,
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
            extra: { conversationId, totalTokens, costCents: unitCostCents },
          });
        }
      });
  }

  // (3) Fan out `usage_update` so the client cost badge reflects the
  //     just-billed turn. Widened with cache tokens so the chat-surface
  //     bubble can render the same Input semantics the dashboard does.
  sendToClient(userId, {
    type: "usage_update",
    conversationId,
    workspaceId,
    totalCostUsd: costDelta,
    inputTokens: usage.input_tokens,
    outputTokens: usage.output_tokens,
    cacheReadInputTokens: usage.cache_read_input_tokens,
    cacheCreationInputTokens: usage.cache_creation_input_tokens,
  });
}

/**
 * Awaitable variant of `persistTurnCost` for the PR-B (#4379) Anthropic-SDK
 * leader loop. Resolves AFTER both the `increment_conversation_cost` RPC and
 * the `write_byok_audit` RPC settle (success or fail). Per AC12, the loop's
 * `step.run("turn-${n}-claude", ...)` MUST await this BEFORE the step
 * returns so the next `step.run("turn-${n}-progress-write", ...)` (which
 * triggers the Supabase Realtime fanout) reads a deterministically-updated
 * `audit_byok_use` row.
 *
 * Failure mode parity with `persistTurnCost`: errors are mirrored to
 * Sentry via `reportSilentFallback` (same `feature` / `op` tags) and
 * SWALLOWED — the lease scope must close cleanly even if the cost
 * write trips a transient DB error, otherwise Inngest would retry the
 * whole leader turn and re-issue the Anthropic call.
 */
export async function persistTurnCostAwaitable(
  userId: string,
  conversationId: string,
  leaderId: string,
  workspaceId: string,
  input: TurnCostInput,
  marker: TurnCostMarker,
): Promise<void> {
  const costDelta = Number.isFinite(input.totalCostUsd) ? input.totalCostUsd : 0;
  const usage = input.usage;

  // Cost marker (plan Phase 1 / leader-loop path). Fail-open, before the RPCs.
  emitClaudeCostMarker({
    source: marker.source,
    model: marker.model,
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    cache_read_input_tokens: usage.cache_read_input_tokens,
    cache_creation_input_tokens: usage.cache_creation_input_tokens,
    cost_usd: costDelta,
    id: conversationId,
    capture_status: "ok",
  });

  const incrementResult = supabase().rpc("increment_conversation_cost", {
    conv_id: conversationId,
    cost_delta: costDelta,
    input_delta: usage.input_tokens,
    output_delta: usage.output_tokens,
    cache_read_delta: usage.cache_read_input_tokens,
    cache_creation_delta: usage.cache_creation_input_tokens,
  });

  const totalTokens =
    usage.input_tokens +
    usage.output_tokens +
    usage.cache_read_input_tokens +
    usage.cache_creation_input_tokens;

  const auditResult = supabase().rpc("write_byok_audit", {
    p_invocation_id: randomUUID(),
    p_founder_id: userId,
    p_workspace_id: workspaceId,
    p_agent_role: leaderId,
    p_token_count: totalTokens,
    p_unit_cost_cents: Math.round(costDelta * 100),
  });

  const [incr, audit] = await Promise.all([incrementResult, auditResult]);
  if (incr.error) {
    log.error(
      { err: incr.error, conversationId },
      "Failed to increment conversation cost",
    );
    reportSilentFallback(incr.error, {
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
  if (audit.error) {
    log.error(
      { err: audit.error, conversationId, userId },
      "Failed to write byok audit row",
    );
    reportSilentFallback(audit.error, {
      feature: "agent-cost-tracking",
      op: "audit-write",
      extra: { conversationId, totalTokens, costCents: Math.round(costDelta * 100) },
    });
  }

  sendToClient(userId, {
    type: "usage_update",
    conversationId,
    workspaceId,
    totalCostUsd: costDelta,
    inputTokens: usage.input_tokens,
    outputTokens: usage.output_tokens,
    cacheReadInputTokens: usage.cache_read_input_tokens,
    cacheCreationInputTokens: usage.cache_creation_input_tokens,
  });
}
