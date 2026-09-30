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
      lastError: {
        code: "codex_history_transfer_required",
        message: "Acknowledge before continuing.",
        conversationId: "test-id",
        authModeGeneration: 2,
      },
    });
  });

  it("sends the explicit acknowledgment for the displayed conversation generation", async () => {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    render(<ChatSurface variant="full" conversationId="test-id" />);

    fireEvent.click(screen.getByRole("button", { name: "Acknowledge and continue" }));
    expect(wsReturn.acknowledgeCodexHistoryTransfer).toHaveBeenCalledWith("test-id", 2);
  });
});
