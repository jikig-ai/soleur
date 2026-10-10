import type { WSMessage } from "@/lib/types";
import type { DomainLeaderId } from "./domain-leaders";
import type { EngineEvent } from "./agent-engine-contract";

/** One mapper per admitted Web turn. The neutral adapter keeps native text
 * semantics for routine consumers; the Web reducer requires snapshots.
 * codex-code-message-translator.ts › translateCodexAppServerStream() assigns
 * item delta identities and distinct persisted-message identities. Retain
 * those distinctions here without exposing item identities on the wire.
 */
export function createCodexWebEventMapper(
  options: Parameters<typeof mapCodexEngineEventToWsMessage>[1],
): (event: EngineEvent) => WSMessage {
  const items = new Map<string, string>();
  let retainedBytes = 0;
  const encoder = new TextEncoder();
  return (event) => {
    if (event.payload.type === "text") {
      const delta = /^codex:item:(.+):delta:\d+$/.exec(event.eventId);
      const snapshot = /^codex:item:(.+):message$/.exec(event.eventId);
      const itemId = delta?.[1] ?? snapshot?.[1];
      if (itemId) {
        const previous = items.get(itemId) ?? "";
        const content = delta ? previous + event.payload.text : event.payload.text;
        const nextBytes = retainedBytes - encoder.encode(previous).byteLength + encoder.encode(content).byteLength;
        // Fail visibly instead of silently dropping older answer fragments.
        // This retention is scoped to one turn and never persisted.
        if (nextBytes > 256 * 1024 || (!items.has(itemId) && items.size >= 32)) {
          throw Object.assign(new Error("codex_web_text_limit"), { code: "codex_web_text_limit" });
        }
        items.set(itemId, content);
        retainedBytes = nextBytes;
        return mapCodexEngineEventToWsMessage({ ...event, payload: { type: "text", text: content } }, options);
      }
    }
    if (event.payload.type === "error" || (event.payload.type === "status"
      && ["completed", "cancelled", "failed"].includes(event.payload.status))) {
      items.clear();
      retainedBytes = 0;
    }
    return mapCodexEngineEventToWsMessage(event, options);
  };
}

/** Map neutral engine events onto the existing conversation wire contract. */
export function mapCodexEngineEventToWsMessage(
  event: EngineEvent,
  options: { leaderId: DomainLeaderId; conversationId?: string; workspaceId?: string },
): WSMessage {
  const { leaderId } = options;
  const conversation = options.conversationId ? { conversationId: options.conversationId } : {};
  switch (event.payload.type) {
    case "status":
      if (event.payload.status === "completed" || event.payload.status === "cancelled" || event.payload.status === "failed") {
        return { type: "stream_end", leaderId, ...conversation };
      }
      return { type: "stream_start", leaderId, ...conversation };
    case "text":
      return { type: "stream", content: event.payload.text, partial: true, leaderId, ...conversation };
    case "progress":
      return { type: "reasoning_narration", message: event.payload.message.slice(0, 256), ...conversation };
    case "approval":
      return { type: "tool_use", leaderId, label: "Approval required", ...conversation };
    case "error":
      return { type: "error", message: "Codex execution failed", ...conversation };
    case "artifact":
      return { type: "tool_use", leaderId, label: "Codex execution updated", ...conversation };
    case "usage": {
      const inputTokens = event.payload.usage.native.find((unit) => unit.unit === "input_tokens")?.value ?? 0;
      const outputTokens = event.payload.usage.native.find((unit) => unit.unit === "output_tokens")?.value ?? 0;
      return {
        type: "usage_update",
        conversationId: options.conversationId ?? "",
        ...(options.workspaceId ? { workspaceId: options.workspaceId } : {}),
        totalCostUsd: event.payload.usage.cost.provenance === "reported" && event.payload.usage.cost.currency === "USD"
          ? event.payload.usage.cost.amount
          : 0,
        inputTokens,
        outputTokens,
      };
    }
  }
}
