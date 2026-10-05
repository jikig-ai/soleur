// Support-persona deny → handoff escalation registry (#9539, ADR-113 addendum).
//
// A support turn that ATTEMPTS an engineering action is denied at the
// `canUseTool` chokepoint — but the deny's only reach is the model's prose,
// which demonstrably dead-ends ("file writes are disabled in this session").
// The user-facing escape is a `support_handoff` SSE frame emitted by the
// support route at the terminal boundary; this registry is the process-local
// bridge between the two — deny paths record, the route consumes on terminal.
//
// Process-local by design: the flag is set inside the SDK query and consumed
// by the route that started the same dispatch — no persistence, no cross-turn
// state. Consume-on-read makes "a flag survives into the next turn" impossible
// by construction; the stream-open `clearSupportEscalation` in the route covers
// the residual zombie-turn race (a prior turn's dispatch still running after
// the client aborted).
//
// Bounded FIFO Map: `newConversation:true` re-mints support conversations, so
// the keyspace is NOT conversation-bounded — evict the oldest entry at a fixed
// cap, mirroring the `bashApprovalCache`/`pendingPrompts` registry idiom.

import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

import { createChildLogger } from "./logger";
import { logPermissionDecision } from "./permission-log";

const log = createChildLogger("permission");

export type SupportEscalationSource = "skill" | "bash";

const ESCALATION_CAP = 1000;
const escalations = new Map<string, SupportEscalationSource>();

/** Record that a support turn attempted a denied engineering action. */
export function recordSupportEscalation(
  conversationId: string,
  source: SupportEscalationSource,
): void {
  // Refresh insertion order so the FIFO cap evicts genuinely-oldest keys.
  escalations.delete(conversationId);
  escalations.set(conversationId, source);
  if (escalations.size > ESCALATION_CAP) {
    const oldest = escalations.keys().next().value;
    if (oldest !== undefined) escalations.delete(oldest);
  }
}

/**
 * Consume-on-read: returns the recorded source and clears the flag. The route
 * calls this once at the terminal frame — a second call (or a turn with no
 * deny) returns null, which is the vacuity guard for the emit.
 */
export function consumeSupportEscalation(
  conversationId: string,
): SupportEscalationSource | null {
  const source = escalations.get(conversationId) ?? null;
  escalations.delete(conversationId);
  return source;
}

/**
 * Drop any live flag. Returns whether one was dropped — the route logs the
 * `support-handoff-cleared-unconsumed` marker on true so the deny→emit
 * observability join distinguishes "flag orphaned" from "never recorded".
 */
export function clearSupportEscalation(conversationId: string): boolean {
  return escalations.delete(conversationId);
}

/**
 * One authoring point for a support-persona deny: structured `deny-support-*`
 * log (the observability join key is `conversationId`), permission-decision
 * log, escalation record, and the ADR-070 user-relayable deny — every present
 * and future support deny path gets record + telemetry for free.
 */
export function denySupport(opts: {
  conversationId: string;
  toolName: string;
  source: SupportEscalationSource;
  message: string;
  detail?: string;
}): Extract<PermissionResult, { behavior: "deny" }> {
  const { conversationId, toolName, source, message, detail } = opts;
  log.info(
    {
      sec: true,
      tool: toolName,
      decision: `deny-support-${source}`,
      conversationId,
      ...(detail ? { detail } : {}),
    },
    "Support persona denied an engineering action",
  );
  logPermissionDecision(
    `canUseTool-support-${source}`,
    toolName,
    "deny",
    detail,
  );
  recordSupportEscalation(conversationId, source);
  return { behavior: "deny" as const, message };
}
