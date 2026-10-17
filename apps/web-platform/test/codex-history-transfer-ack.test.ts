import { describe, expect, it } from "vitest";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

describe("Codex history-transfer acknowledgment protocol", () => {
  it.each(["api-key", "managed"])("accepts the required notice's %s mode and correlated turn", (authMode) => {
    expect(parseWSMessage({
      type: "codex_history_transfer_required",
      conversationId: "conversation-1",
      authModeGeneration: 3,
      authMode,
      clientTurnId: "90000000-0000-4000-8000-000000000001",
    }).ok).toBe(true);
  });

  it("accepts notices from a server that omits the new optional fields", () => {
    expect(parseWSMessage({ type: "codex_history_transfer_required", conversationId: "conversation-1", authModeGeneration: 3 }).ok).toBe(true);
  });

  it.each([
    { authMode: "unknown" },
    { clientTurnId: "not-a-uuid" },
    { accountId: "private-account" },
  ])("rejects invalid or private notice metadata %j", (metadata) => {
    expect(parseWSMessage({ type: "codex_history_transfer_required", conversationId: "conversation-1", authModeGeneration: 3, ...metadata }).ok).toBe(false);
  });

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
