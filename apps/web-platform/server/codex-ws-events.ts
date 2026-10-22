import type { WSMessage } from "@/lib/types";
import type { DomainLeaderId } from "./domain-leaders";
import type { EngineEvent } from "./agent-engine-contract";

/** One mapper per admitted Web turn. The neutral adapter keeps native text
 * semantics for routine consumers; the Web reducer requires complete answers.
 * codex-code-message-translator.ts › translateCodexAppServerStream() assigns
 * item delta identities and distinct persisted-message identities. Retain
 * those distinctions here without exposing item identities on the wire.
 */
export function createCodexWebEventMapper(
  options: Parameters<typeof mapCodexEngineEventToWsMessage>[1],
  now: () => number = Date.now,
): ((event: EngineEvent) => WSMessage | undefined) & { takeFinalSnapshot: () => WSMessage | undefined } {
  const items = new Map<string, { chunks: string[]; byteLength: number }>();
  let retainedBytes = 0;
  let textEventCount = 0;
  let intermediateSnapshotBytes = 0;
  let lastSnapshotAt = Number.NEGATIVE_INFINITY;
  let intermediateSnapshotsSuppressed = false;
  let finalSnapshot: WSMessage | undefined;
  let neutralSnapshot: string | undefined;
  const encoder = new TextEncoder();
  const map = ((event: EngineEvent): WSMessage | undefined => {
    if (event.payload.type === "text") {
      textEventCount++;
      if (textEventCount > 4096) {
        throw Object.assign(new Error("codex_web_text_limit"), { code: "codex_web_text_limit" });
      }
      const delta = /^codex:item:(.+):delta:\d+$/.exec(event.eventId);
      const snapshot = /^codex:item:(.+):message$/.exec(event.eventId);
      const itemId = delta?.[1] ?? snapshot?.[1];
      if (itemId) {
        if (neutralSnapshot !== undefined) {
          items.clear();
          retainedBytes = 0;
        }
        neutralSnapshot = undefined;
        const previous = items.get(itemId);
        const contentBytes = encoder.encode(event.payload.text).byteLength;
        const nextBytes = delta && previous
          ? retainedBytes + contentBytes
          : retainedBytes - (previous?.byteLength ?? 0) + contentBytes;
        // Fail visibly instead of silently dropping older answer fragments.
        // This retention is scoped to one turn and never persisted.
        if (nextBytes > 256 * 1024 || (!items.has(itemId) && items.size >= 32)) {
          throw Object.assign(new Error("codex_web_text_limit"), { code: "codex_web_text_limit" });
        }
        if (delta && previous) {
          previous.chunks.push(event.payload.text);
          previous.byteLength += contentBytes;
        } else {
          items.set(itemId, { chunks: [event.payload.text], byteLength: contentBytes });
        }
        retainedBytes = nextBytes;
        const snapshotBytes = retainedBytes + Math.max(0, items.size - 1) * 2;
        if (intermediateSnapshotsSuppressed || now() - lastSnapshotAt < 100) return undefined;
        if (intermediateSnapshotBytes + snapshotBytes > 8 * 1024 * 1024) {
          intermediateSnapshotsSuppressed = true;
          return undefined;
        }
        lastSnapshotAt = now();
        intermediateSnapshotBytes += snapshotBytes;
        return mapCodexEngineEventToWsMessage({
          ...event,
          payload: { type: "text", text: [...items.values()].map((item) => item.chunks.join("")).join("\n\n") },
        }, options);
      }
      const contentBytes = encoder.encode(event.payload.text).byteLength;
      if (contentBytes > 256 * 1024) {
        throw Object.assign(new Error("codex_web_text_limit"), { code: "codex_web_text_limit" });
      }
      items.clear();
      retainedBytes = contentBytes;
      neutralSnapshot = event.payload.text;
      if (intermediateSnapshotsSuppressed || now() - lastSnapshotAt < 100) return undefined;
      if (intermediateSnapshotBytes + contentBytes > 8 * 1024 * 1024) {
        intermediateSnapshotsSuppressed = true;
        return undefined;
      }
      lastSnapshotAt = now();
      intermediateSnapshotBytes += contentBytes;
      return mapCodexEngineEventToWsMessage(event, options);
    }
    if (event.payload.type === "status" && event.payload.status === "completed" && (items.size > 0 || neutralSnapshot !== undefined)) {
      finalSnapshot = mapCodexEngineEventToWsMessage({
        ...event,
        payload: { type: "text", text: neutralSnapshot ?? [...items.values()].map((item) => item.chunks.join("")).join("\n\n") },
      }, options);
      items.clear();
      retainedBytes = 0;
      neutralSnapshot = undefined;
    } else if (event.payload.type === "error" || (event.payload.type === "status"
      && ["cancelled", "failed"].includes(event.payload.status))) {
      items.clear();
      retainedBytes = 0;
      neutralSnapshot = undefined;
    }
    return mapCodexEngineEventToWsMessage(event, options);
  }) as ((event: EngineEvent) => WSMessage | undefined) & { takeFinalSnapshot: () => WSMessage | undefined };
  map.takeFinalSnapshot = () => {
    const frame = finalSnapshot;
    finalSnapshot = undefined;
    return frame;
  };
  return map;
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
      return { type: "stream", content: event.payload.text, partial: true, answerSnapshot: true, leaderId, ...conversation };
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
