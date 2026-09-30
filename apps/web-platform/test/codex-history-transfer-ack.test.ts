import { describe, expect, it } from "vitest";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

describe("Codex history-transfer acknowledgment protocol", () => {
  it("accepts the member's explicit acknowledgment for one conversation generation", () => {
    expect(parseWSMessage({
      type: "codex_history_transfer_acknowledge",
      conversationId: "conversation-1",
      authModeGeneration: 3,
    }).ok).toBe(true);
  });

  it("accepts the server confirmation frame for the acknowledged generation", () => {
    expect(parseWSMessage({
      type: "codex_history_transfer_acknowledged",
      conversationId: "conversation-1",
      authModeGeneration: 3,
    }).ok).toBe(true);
  });

  it("rejects acknowledgment frames with extra identity fields", () => {
    expect(parseWSMessage({
      type: "codex_history_transfer_acknowledge",
      conversationId: "conversation-1",
      authModeGeneration: 3,
      userId: "forged-user",
    }).ok).toBe(false);
  });
});
