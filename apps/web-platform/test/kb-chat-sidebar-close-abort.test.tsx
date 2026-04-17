import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { useState } from "react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// AC15: closing the panel mid-stream aborts the session; reopening shows
// user messages only. The client-side half of this contract is:
//   - closing unmounts <ChatSurface> (via Sheet returning null), which
//     tears down the useWebSocket hook and its WS connection.
//   - reopening remounts, which calls startSession afresh. No partial
//     assistant content from the aborted session carries over in-memory
//     (server replay is a separate ws-handler contract).

type MockMsg = { id: string; role: "user" | "assistant"; content: string; type: "text"; state?: string };

const mockStartSession = vi.fn();
let wsReturn = {
  messages: [] as MockMsg[],
  startSession: mockStartSession,
  resumeSession: vi.fn(),
  sendMessage: vi.fn(),
  sendReviewGateResponse: vi.fn(),
  status: "connected" as const,
  disconnectReason: undefined as string | undefined,
  lastError: null as import("@/lib/ws-client").WebSocketError | null,
  reconnect: vi.fn(),
  routeSource: null as "auto" | "mention" | null,
  activeLeaderIds: [] as string[],
  sessionConfirmed: true,
  usageData: null as { totalCostUsd: number } | null,
  realConversationId: "cid-1" as string | null,
  resumedFrom: null as { conversationId: string; timestamp: string; messageCount: number } | null,
};

vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }));
vi.mock("@/lib/analytics-client", () => ({ track: vi.fn() }));
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));
vi.mock("next/navigation", () => ({
  useSearchParams: () => new URLSearchParams(),
  useRouter: () => ({ replace: vi.fn() }),
  usePathname: () => "/dashboard/kb/knowledge-base/x.md",
}));
vi.mock("@/hooks/use-media-query", () => ({ useMediaQuery: () => true }));

describe("KbChatSidebar — close/reopen teardown (AC15)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = { ...wsReturn, messages: [], resumedFrom: null };
  });

  async function harness() {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const { KbChatQuoteBridgeProvider } = await import(
      "@/components/kb/kb-chat-quote-bridge"
    );

    function Host() {
      const [open, setOpen] = useState(true);
      const ctx = {
        open,
        openSidebar: () => setOpen(true),
        closeSidebar: () => setOpen(false),
        contextPath: "knowledge-base/x.md",
        enabled: true,
        messageCount: 0,
        setMessageCount: () => {},
      };
      return (
        <KbChatContext value={ctx}>
          <KbChatQuoteBridgeProvider onOpenSidebar={() => setOpen(true)}>
            <KbChatSidebar
              open={open}
              onClose={() => setOpen(false)}
              contextPath="knowledge-base/x.md"
            />
            <button data-testid="toggle" onClick={() => setOpen((o) => !o)}>toggle</button>
          </KbChatQuoteBridgeProvider>
        </KbChatContext>
      );
    }
    return render(<Host />);
  }

  it("closing the sidebar unmounts the dialog (tears down ChatSurface + WS)", async () => {
    await harness();
    expect(screen.queryByRole("dialog")).not.toBeNull();
    act(() => { screen.getByTestId("toggle").click(); });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("reopening the sidebar starts a fresh session (new startSession call)", async () => {
    await harness();
    // Initial mount triggered startSession once.
    const initialCalls = mockStartSession.mock.calls.length;
    expect(initialCalls).toBeGreaterThanOrEqual(1);

    act(() => { screen.getByTestId("toggle").click(); }); // close
    expect(screen.queryByRole("dialog")).toBeNull();
    act(() => { screen.getByTestId("toggle").click(); }); // reopen

    expect(mockStartSession.mock.calls.length).toBeGreaterThan(initialCalls);
  });
});
