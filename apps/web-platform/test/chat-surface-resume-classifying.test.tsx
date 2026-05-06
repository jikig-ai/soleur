import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () =>
    createUseTeamNamesMock({
      getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

describe("ChatSurface — routing chip resume gate (#3251 follow-up)", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  async function renderFull() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant="full" conversationId="test-id" />);
  }

  it("T5a — does NOT render routing chip while historyLoading is true", async () => {
    // While the history fetch is in flight on a resumed thread, the user-only
    // snapshot should not flip `isClassifying` true and render the chip — the
    // assistant row may still be on its way over the wire.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [{ id: "u1", role: "user", content: "hello", type: "text" }],
      routeSource: null,
      workflow: { state: "idle" },
      activeLeaderIds: [],
      historyLoading: true,
    });
    await renderFull();

    expect(screen.queryByTestId("routing-chip")).not.toBeInTheDocument();
  });

  it("T5b — does NOT render routing chip after a confirmed resume even with user-only history", async () => {
    // Legacy cc-chat conversations persisted user messages but not assistant
    // messages. After this fix, NEW conversations persist both — but old
    // conversations remain user-only forever. The resumedFrom signal proves
    // the thread is being resumed, so the chip is a lie regardless of why
    // hasAssistantMessage is false. Belt-and-suspenders to the server fix.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [{ id: "u1", role: "user", content: "hello", type: "text" }],
      routeSource: null,
      workflow: { state: "idle" },
      activeLeaderIds: [],
      historyLoading: false,
      resumedFrom: {
        conversationId: "prior-conv",
        timestamp: "2026-05-05T18:26:00.000Z",
        messageCount: 2,
      },
    });
    await renderFull();

    expect(screen.queryByTestId("routing-chip")).not.toBeInTheDocument();
  });

  it("T5d — does NOT render routing chip when BOTH historyLoading is true AND resumedFrom is set", async () => {
    // Truth-table corner: with both new clauses suppressing simultaneously,
    // the chip must remain hidden. T5a/T5b cover one clause each — T5d locks
    // in the AND semantics so a regression to `||` (suppress on either)
    // would not pass merely because each leg is independently exercised.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [{ id: "u1", role: "user", content: "hello", type: "text" }],
      routeSource: null,
      workflow: { state: "idle" },
      activeLeaderIds: [],
      historyLoading: true,
      resumedFrom: {
        conversationId: "prior-conv",
        timestamp: "2026-05-05T18:26:00.000Z",
        messageCount: 2,
      },
    });
    await renderFull();

    expect(screen.queryByTestId("routing-chip")).not.toBeInTheDocument();
  });

  it("T5c — RENDERS routing chip on a fresh (non-resume) thread that is mid-classification", async () => {
    // Drift guard: the new gate must NOT suppress the chip on a brand-new
    // conversation that legitimately has only the user's first message and is
    // waiting for routing to complete. This is the case the chip exists for.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [{ id: "u1", role: "user", content: "hello", type: "text" }],
      routeSource: null,
      workflow: { state: "idle" },
      activeLeaderIds: [],
      historyLoading: false,
      resumedFrom: null,
    });
    await renderFull();

    expect(await screen.findByTestId("routing-chip")).toBeInTheDocument();
  });
});
