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
// by the route that started the same dispatch — no persistence. Consume-on-read
// makes "a flag survives into the next turn" impossible by construction for
// SEQUENTIAL turns; the stream-open `clearSupportEscalation` in the route
// narrows the residual zombie-turn race (a prior turn's dispatch still running
// after the client aborted — see the route's own comment; a per-dispatch key
// cannot reach the per-Query `canUseTool` ctx without new plumbing, so the
// route additionally rejects a second POST while a turn is in-flight).
//
// Bounded process-local Map (the `bashApprovalCache`/`pendingPrompts` registry
// precedent — not their exact eviction shape): `newConversation:true` re-mints
// support conversations, so the keyspace is NOT conversation-bounded — evict
// the oldest entry at a fixed cap. An evicted flag is almost always a zombie
// orphan, but eviction still logs so the deny→emit join stays complete.

import type { PermissionResult } from "@anthropic-ai/claude-agent-sdk";

import { createChildLogger } from "./logger";
import { logPermissionDecision } from "./permission-log";

const log = createChildLogger("permission");

/**
 * Deny-path class for telemetry. `"tool"` covers the non-Skill non-Bash arms
 * (file-tool writes, `Agent`, platform tools, deny-by-default) added by the
 * review panel's uncovered-path enumeration.
 */
export type SupportEscalationSource = "skill" | "bash" | "tool";

const ESCALATION_CAP = 1000;
const escalations = new Map<string, SupportEscalationSource>();

// Model-controlled strings (the `.skill` field, truncated commands) are
// prompt-steerable — strip control chars + Unicode line separators and cap
// length before they reach a structured log line (the same sanitizer shape
// used for SubagentStart payloads).
function sanitizeDetail(detail: string | undefined): string | undefined {
  if (detail === undefined) return undefined;
  // `\p{Cc}` covers C0+C1+DEL control chars without a literal-escape regex
  // (which the no-control-eslint ratchet counts).
  return detail.replace(/[\p{Cc}\u2028\u2029]/gu, " ").slice(0, 200);
}

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
    if (oldest !== undefined) {
      escalations.delete(oldest);
      log.info(
        { sec: true, evictedConversationId: oldest },
        "support-escalation-evicted",
      );
    }
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
 *
 * `detail` is sanitized before logging and ALSO emitted under the legacy
 * `requested` key for the skill arm — the original `deny-support-skill` line
 * predates this helper and Better Stack queries key on `requested`.
 */
export function denySupport(opts: {
  conversationId: string;
  toolName: string;
  source: SupportEscalationSource;
  message: string;
  detail?: string;
}): Extract<PermissionResult, { behavior: "deny" }> {
  const { conversationId, toolName, source, message } = opts;
  const detail = sanitizeDetail(opts.detail);
  log.info(
    {
      sec: true,
      tool: toolName,
      decision: `deny-support-${source}`,
      conversationId,
      ...(detail !== undefined ? { detail, requested: detail } : {}),
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
