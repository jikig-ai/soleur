import { beforeEach, describe, expect, it, vi } from "vitest";
import { fireEvent, render, screen } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }));
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock({
    getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
  }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));
vi.mock("next/navigation", () => ({
  useSearchParams: () => new URLSearchParams(),
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

describe("ChatSurface Codex history-transfer acknowledgment", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [{ id: "unsent-turn", type: "text", role: "user", content: "Please continue this draft", delivery: "unsent" }],
      lastError: {
        code: "codex_history_transfer_required",
        message: "OpenAI will receive this conversation's stored history when you resend or send a later message. API-key mode uses your own credential and charges your provider account. Acknowledge history transfer, then resend your message. Your original message was not sent.",
        conversationId: "test-id",
        authModeGeneration: 2,
      },
    });
  });

  it("sends the explicit acknowledgment for the displayed conversation generation", async () => {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    const view = render(<ChatSurface variant="full" conversationId="test-id" />);

    expect(screen.getByText(/OpenAI will receive/)).toBeVisible();
    expect(screen.getByText("Please continue this draft")).toBeVisible();
    expect(screen.getByText("Message not sent")).toBeVisible();
    vi.mocked(wsReturn.sendMessage).mockClear();
    vi.mocked(wsReturn.resendMessage).mockClear();
    vi.mocked(wsReturn.resumeSession).mockClear();
    fireEvent.click(screen.getByRole("button", { name: "Acknowledge history transfer" }));
    expect(wsReturn.acknowledgeCodexHistoryTransfer).toHaveBeenCalledWith("test-id", 2);
    expect(wsReturn.sendMessage).not.toHaveBeenCalled();
    expect(wsReturn.resendMessage).not.toHaveBeenCalled();
    expect(wsReturn.resumeSession).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Acknowledge history transfer" })).toBeVisible();

    const heldMessage = wsReturn.messages[0];
    if (heldMessage.type !== "text") throw new Error("expected held user text message");
    heldMessage.delivery = "retryable";
    view.rerender(<ChatSurface variant="full" conversationId="test-id" />);
    fireEvent.click(screen.getByRole("button", { name: "Resend message" }));
    expect(wsReturn.resendMessage).toHaveBeenCalledWith(expect.objectContaining({ content: "Please continue this draft", delivery: "retryable" }));
  });

  it.each([
    { status: "reconnecting" as const, sessionConfirmed: true },
    { status: "connected" as const, sessionConfirmed: false },
  ])("disables held-draft resend until the connection and session are confirmed: %j", async (connection) => {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    wsReturn = createWebSocketMock({
      ...connection,
      hasPendingCodexHistoryTransfer: true,
      realConversationId: "test-id",
      messages: [{ id: "user-held-turn", type: "text", role: "user", content: "Keep this original draft", delivery: "retryable" }],
      connection: { phase: "unrecoverable" },
    });
    const view = render(<ChatSurface variant="full" conversationId="test-id" />);
    const resend = screen.getByRole("button", { name: "Resend message" });
    expect(resend).toBeDisabled();
    fireEvent.click(resend);
    expect(wsReturn.resendMessage).not.toHaveBeenCalled();
    expect(screen.getByText("Keep this original draft")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Resume with full context" }));
    expect(wsReturn.resumeAfterUnrecoverable).toHaveBeenCalledOnce();
    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(wsReturn.resendMessage).not.toHaveBeenCalled();

    wsReturn.status = "connected";
    wsReturn.sessionConfirmed = true;
    view.rerender(<ChatSurface variant="full" conversationId="test-id" />);
    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(wsReturn.resumeSession).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Resend message" })).toBeEnabled();
    fireEvent.click(screen.getByRole("button", { name: "Resend message" }));
    expect(wsReturn.resendMessage).toHaveBeenCalledOnce();
    expect(wsReturn.resendMessage).toHaveBeenCalledWith(wsReturn.messages[0]);
  });

  it("keeps a new chat from bootstrapping a different session while an acknowledged draft needs recovery", async () => {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    wsReturn = createWebSocketMock({
      status: "connected",
      sessionConfirmed: false,
      hasPendingCodexHistoryTransfer: true,
      realConversationId: "test-id",
      messages: [{ id: "user-held-turn", type: "text", role: "user", content: "Keep this original draft", delivery: "retryable" }],
      connection: { phase: "unrecoverable" },
    });
    const view = render(<ChatSurface variant="full" conversationId="new" />);

    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(wsReturn.resumeSession).not.toHaveBeenCalled();
    expect(screen.getByText("Keep this original draft")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Resume with full context" }));
    expect(wsReturn.resumeAfterUnrecoverable).toHaveBeenCalledOnce();
    expect(wsReturn.startSession).not.toHaveBeenCalled();

    wsReturn.sessionConfirmed = true;
    wsReturn.hasPendingCodexHistoryTransfer = false;
    view.rerender(<ChatSurface variant="full" conversationId="new" />);
    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(screen.getByText("Keep this original draft")).toBeVisible();
  });

  it("does not bootstrap a new session for an unacknowledged held turn after reconnect", async () => {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    wsReturn = createWebSocketMock({
      status: "connected",
      sessionConfirmed: false,
      hasPendingCodexHistoryTransfer: true,
      realConversationId: "test-id",
      messages: [{ id: "user-held-turn", type: "text", role: "user", content: "Keep this original draft", delivery: "unsent" }],
      connection: { phase: "unrecoverable" },
      lastError: {
        code: "codex_history_transfer_required",
        message: "OpenAI will receive this conversation's stored history. Acknowledge before resending.",
        conversationId: "test-id",
        authModeGeneration: 2,
      },
    });
    const view = render(<ChatSurface variant="full" conversationId="new" />);

    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(wsReturn.resumeSession).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Resume with full context" }));
    expect(wsReturn.resumeAfterUnrecoverable).toHaveBeenCalledOnce();
    expect(wsReturn.startSession).not.toHaveBeenCalled();

    wsReturn.sessionConfirmed = true;
    view.rerender(<ChatSurface variant="full" conversationId="new" />);
    expect(wsReturn.startSession).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Acknowledge history transfer" })).toBeVisible();
    expect(screen.getByText("Keep this original draft")).toBeVisible();
  });
});
