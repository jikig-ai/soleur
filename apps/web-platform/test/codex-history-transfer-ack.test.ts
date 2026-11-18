import { describe, expect, it } from "vitest";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

const noticeNonce = "n".repeat(43);

describe("Codex history-transfer acknowledgment protocol", () => {
  it.each(["api-key", "managed"])("accepts the required notice's %s mode and correlated turn", (authMode) => {
    expect(parseWSMessage({
      type: "codex_history_transfer_required",
      conversationId: "conversation-1",
      authModeGeneration: 3,
      noticeNonce,
      authMode,
      clientTurnId: "90000000-0000-4000-8000-000000000001",
    }).ok).toBe(true);
  });

  it("accepts notices from a server that omits the new optional fields", () => {
    expect(parseWSMessage({ type: "codex_history_transfer_required", conversationId: "conversation-1", authModeGeneration: 3, noticeNonce }).ok).toBe(true);
  });

  it.each([
    { authMode: "unknown" },
    { clientTurnId: "not-a-uuid" },
    { accountId: "private-account" },
  ])("rejects invalid or private notice metadata %j", (metadata) => {
    expect(parseWSMessage({ type: "codex_history_transfer_required", conversationId: "conversation-1", authModeGeneration: 3, noticeNonce, ...metadata }).ok).toBe(false);
  });

  it("accepts the member's explicit acknowledgment for one conversation generation", () => {
    expect(parseWSMessage({
      type: "codex_history_transfer_acknowledge",
      conversationId: "conversation-1",
      authModeGeneration: 3,
      noticeNonce,
    }).ok).toBe(true);
  });

  it.each(["codex_history_transfer_required", "codex_history_transfer_acknowledge"])(
    "requires a valid nonce on %s frames",
    (type) => {
      const frame = { type, conversationId: "conversation-1", authModeGeneration: 3 };
      expect(parseWSMessage(frame).ok).toBe(false);
      for (const invalidNonce of ["", "n".repeat(42), "n".repeat(44), "+".repeat(43)]) {
        expect(parseWSMessage({ ...frame, noticeNonce: invalidNonce }).ok).toBe(false);
      }
    },
  );

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
      noticeNonce,
      userId: "forged-user",
    }).ok).toBe(false);
  });
});
