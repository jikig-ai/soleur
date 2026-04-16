import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

type MockTextMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text";
};

const mockStartSession = vi.fn();
const mockTrack = vi.fn();

let wsReturn = {
  messages: [] as MockTextMessage[],
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
  realConversationId: null as string | null,
  resumedFrom: null as { conversationId: string; timestamp: string; messageCount: number } | null,
};

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/lib/analytics-client", () => ({
  track: (...args: unknown[]) => mockTrack(...args),
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn() }),
  usePathname: () => "/dashboard/kb/knowledge-base/product/roadmap.md",
}));

// Mock useMediaQuery so Sheet renders desktop layout (portal still used).
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => true,
}));

describe("KbChatSidebar", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = {
      messages: [],
      startSession: mockStartSession,
      resumeSession: vi.fn(),
      sendMessage: vi.fn(),
      sendReviewGateResponse: vi.fn(),
      status: "connected",
      disconnectReason: undefined,
      lastError: null,
      reconnect: vi.fn(),
      routeSource: null,
      activeLeaderIds: [],
      sessionConfirmed: true,
      usageData: null,
      realConversationId: null,
      resumedFrom: null,
    };
  });

  async function renderSidebar(open = true) {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const ctxValue = {
      open,
      openSidebar: vi.fn(),
      closeSidebar: vi.fn(),
      contextPath: "knowledge-base/product/roadmap.md",
      enabled: true,
      submitQuote: vi.fn(),
      registerQuoteHandler: vi.fn(),
      messageCount: 0,
      setMessageCount: vi.fn(),
    };
    return render(
      <KbChatContext value={ctxValue}>
        <KbChatSidebar
          open={open}
          onClose={vi.fn()}
          contextPath="knowledge-base/product/roadmap.md"
        />
      </KbChatContext>,
    );
  }

  it("renders a close button with aria-label when open", async () => {
    await renderSidebar(true);
    expect(screen.getByLabelText("Close panel")).toBeTruthy();
  });

  it("renders filename in monospace in header", async () => {
    await renderSidebar(true);
    const header = screen.getByText("roadmap.md");
    expect(header.className).toContain("font-mono");
  });

  it("passes resumeByContextPath to ChatSurface → startSession", async () => {
    await renderSidebar(true);
    expect(mockStartSession).toHaveBeenCalled();
    const call = mockStartSession.mock.calls[0];
    // Object-form call with resumeByContextPath set.
    expect(call[0]).toMatchObject({
      resumeByContextPath: "knowledge-base/product/roadmap.md",
    });
  });

  it("emits kb.chat.opened when session is established (no resume)", async () => {
    await renderSidebar(true);
    wsReturn.realConversationId = "brand-new-conv";
    // Re-render to trigger effect via state change.
    await act(async () => {
      await renderSidebar(true);
    });
    expect(mockTrack).toHaveBeenCalledWith("kb.chat.opened", {
      path: "knowledge-base/product/roadmap.md",
    });
  });

  it("renders resumed banner + emits thread_resumed when resumedFrom set", async () => {
    wsReturn.resumedFrom = {
      conversationId: "existing-xyz",
      timestamp: "2026-04-10T12:00:00Z",
      messageCount: 5,
    };
    wsReturn.realConversationId = "existing-xyz";
    await renderSidebar(true);
    // Banner copy
    expect(screen.getByText(/Continuing from/)).toBeTruthy();
    expect(mockTrack).toHaveBeenCalledWith("kb.chat.thread_resumed", {
      path: "knowledge-base/product/roadmap.md",
    });
    expect(mockTrack).toHaveBeenCalledWith("kb.chat.opened", {
      path: "knowledge-base/product/roadmap.md",
    });
  });

  it("does not mount Sheet content when open=false", async () => {
    await renderSidebar(false);
    expect(screen.queryByLabelText("Close panel")).toBeNull();
  });

  it("includes time in the resumed banner, not just date (AC2)", async () => {
    wsReturn.resumedFrom = {
      conversationId: "existing-xyz",
      timestamp: "2026-04-16T14:15:00Z",
      messageCount: 5,
    };
    wsReturn.realConversationId = "existing-xyz";
    await renderSidebar(true);
    const banner = screen.getByText(/Continuing from/);
    const text = banner.textContent ?? "";
    // The banner must include a time component (colon-separated hours:minutes),
    // not just a date. toLocaleDateString() produces "4/16/2026" without time;
    // toLocaleString() with timeStyle produces something like "2:15 PM".
    expect(text).toMatch(/\d{1,2}:\d{2}/);
  });
});
