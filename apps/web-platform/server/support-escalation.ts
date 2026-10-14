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

/**
 * What the registry stores per conversation (#9556): the deny-path source
 * (telemetry) plus the dispatch-time repo-connection flag the support route
 * stamps on the `support_handoff` frame. Recorded AT deny time — never
 * re-resolved at emit — so the deny→emit bridge costs zero extra DB reads.
 */
export interface SupportEscalationRecord {
  source: SupportEscalationSource;
  /**
   * Whether the dispatching workspace had a connected repo when the deny
   * fired — injected from `CanUseToolDeps.repoConnected`, which cc-dispatcher
   * fills from the `repoUrl` it already resolves per dispatch. `undefined`
   * when the dep is unwired (dep-less deny contexts — unit tests and any
   * future runner path that does not fill the field) OR when the wired dep
   * resolved degraded (a transient dispatch-time read blip — cc-dispatcher
   * emits `undefined` rather than a false "not connected"): the emitted
   * frame omits the field and the client renders the legacy copy arm.
   */
  repoConnected?: boolean;
}

const ESCALATION_CAP = 1000;
const escalations = new Map<string, SupportEscalationRecord>();

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
  repoConnected?: boolean,
): void {
  // Refresh insertion order so the FIFO cap evicts genuinely-oldest keys.
  escalations.delete(conversationId);
  escalations.set(conversationId, { source, repoConnected });
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
 * Consume-on-read: returns the recorded escalation and clears the flag. The
 * route calls this once at the terminal frame — a second call (or a turn with
 * no deny) returns null, which is the vacuity guard for the emit.
 */
export function consumeSupportEscalation(
  conversationId: string,
): SupportEscalationRecord | null {
  const record = escalations.get(conversationId) ?? null;
  escalations.delete(conversationId);
  return record;
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
 * and future ESCALATING support deny path gets record + telemetry for free.
 * (The deliberately non-escalating support denies — AskUserQuestion and the
 * UX-signal belts in permission-callback.ts — bypass this helper.)
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
  /**
   * #9556 — the dispatching workspace's repo-connected state at deny time.
   * Stamped onto the escalation record so the route's `support_handoff` frame
   * carries it and the rendered copy degrades honestly for repo-less users.
   * The `deny()` wrapper in permission-callback.ts injects this from
   * `CanUseToolDeps` — deny call sites never pass it themselves.
   */
  repoConnected?: boolean;
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
  recordSupportEscalation(conversationId, source, opts.repoConnected);
  return { behavior: "deny" as const, message };
}
