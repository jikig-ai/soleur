import type { WSMessage } from "@/lib/types";
import type { DomainLeaderId } from "./domain-leaders";
import type { EngineEvent } from "./agent-engine-contract";

/** Map neutral engine events onto the existing conversation wire contract. */
export function mapCodexEngineEventToWsMessage(
  event: EngineEvent,
  options: { leaderId: DomainLeaderId; conversationId?: string; workspaceId?: string },
): WSMessage {
  const { leaderId } = options;
  switch (event.payload.type) {
    case "status":
      if (event.payload.status === "completed" || event.payload.status === "cancelled" || event.payload.status === "failed") {
        return { type: "stream_end", leaderId };
      }
      return { type: "stream_start", leaderId };
    case "text":
      return { type: "stream", content: event.payload.text, partial: true, leaderId };
    case "progress":
      return { type: "reasoning_narration", message: event.payload.message.slice(0, 256) };
    case "approval":
      return { type: "tool_use", leaderId, label: "Approval required" };
    case "error":
      return { type: "error", message: "Codex execution failed" };
    case "artifact":
      return { type: "tool_use", leaderId, label: "Codex execution updated" };
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
