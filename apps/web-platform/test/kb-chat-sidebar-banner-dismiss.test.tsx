import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// AC2: the "Continuing from …" banner that surfaces when a KB thread is
// resumed MUST auto-dismiss once the user sends a new message — the banner
// is transient context, not a sticky affordance.

type MockMsg = {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text";
};

let wsReturn = {
  messages: [] as MockMsg[],
  startSession: vi.fn(),
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
  resumedFrom: null as
    | { conversationId: string; timestamp: string; messageCount: number }
    | null,
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

describe("KbChatSidebar — resumed banner auto-dismiss (AC2)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = {
      ...wsReturn,
      messages: [],
      resumedFrom: {
        conversationId: "existing",
        timestamp: "2026-04-10T12:00:00Z",
        messageCount: 3,
      },
      realConversationId: "existing",
    };
  });

  async function renderSidebar() {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const ctx = {
      open: true,
      openSidebar: vi.fn(),
      closeSidebar: vi.fn(),
      contextPath: "knowledge-base/x.md",
      enabled: true,
      submitQuote: vi.fn(),
      registerQuoteHandler: vi.fn(),
      messageCount: 0,
      setMessageCount: vi.fn(),
    };
    return render(
      <KbChatContext value={ctx}>
        <KbChatSidebar
          open={true}
          onClose={vi.fn()}
          contextPath="knowledge-base/x.md"
        />
      </KbChatContext>,
    );
  }

  it("renders the resumed banner initially", async () => {
    await renderSidebar();
    expect(screen.getByText(/continuing from/i)).toBeTruthy();
  });

  it("dismisses the banner once a NEW user message is sent", async () => {
    const { rerender } = await renderSidebar();
    expect(screen.getByText(/continuing from/i)).toBeTruthy();

    // Simulate: user sends a new message. The WS client's `messages` state
    // goes from [] to [user], triggering ChatSurface's onMessageCountChange
    // with count=1.
    wsReturn.messages = [
      { id: "u1", role: "user", content: "new question", type: "text" },
    ];
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const ctx = {
      open: true,
      openSidebar: vi.fn(),
      closeSidebar: vi.fn(),
      contextPath: "knowledge-base/x.md",
      enabled: true,
      submitQuote: vi.fn(),
      registerQuoteHandler: vi.fn(),
      messageCount: 4,
      setMessageCount: vi.fn(),
    };
    act(() => {
      rerender(
        <KbChatContext value={ctx}>
          <KbChatSidebar
            open={true}
            onClose={vi.fn()}
            contextPath="knowledge-base/x.md"
          />
        </KbChatContext>,
      );
    });

    expect(screen.queryByText(/continuing from/i)).toBeNull();
  });
});
