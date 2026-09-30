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
});
