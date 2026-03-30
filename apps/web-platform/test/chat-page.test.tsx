import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";

// Mock useWebSocket hook
const mockStartSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();

let wsReturn = {
  messages: [] as Array<{ id: string; role: "user" | "assistant"; content: string; type: "text" | "review_gate"; leaderId?: string }>,
  startSession: mockStartSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  status: "connected" as const,
  disconnectReason: undefined as string | undefined,
  routeSource: null as "auto" | "mention" | null,
  activeLeaderIds: [] as string[],
};

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

// Mock next/navigation
const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();
vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: "new" }),
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: mockReplace }),
  usePathname: () => "/dashboard/chat/new",
}));

describe("ChatPage", () => {
  beforeEach(() => {
    mockStartSession.mockClear();
    mockSendMessage.mockClear();
    wsReturn = {
      messages: [],
      startSession: mockStartSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      status: "connected",
      disconnectReason: undefined,
      routeSource: null,
      activeLeaderIds: [],
    };
    // Reset search params
    for (const key of [...mockSearchParams.keys()]) {
      mockSearchParams.delete(key);
    }
  });

  async function renderChatPage() {
    // Dynamic import to pick up mocks
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  it("reads msg from search params and sends after session_started", async () => {
    mockSearchParams.set("msg", "help with pricing");
    await renderChatPage();
    // Effects are async — wait for sendMessage to be called
    await waitFor(() => {
      expect(mockSendMessage).toHaveBeenCalledWith("help with pricing");
    });
  });

  it("shows routing badge for auto-routed messages", async () => {
    wsReturn.routeSource = "auto";
    wsReturn.activeLeaderIds = ["cmo", "cro"];
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help with strategy", type: "text" },
      { id: "s1", role: "assistant", content: "Here is my analysis", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    expect(screen.getByText(/auto-routed to/i)).toBeInTheDocument();
  });

  it("shows 'Directed to @' badge for mention-routed messages", async () => {
    wsReturn.routeSource = "mention";
    wsReturn.messages = [
      { id: "u1", role: "user", content: "@cmo help", type: "text" },
      { id: "s1", role: "assistant", content: "Sure", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    expect(screen.getByText(/directed to/i)).toBeInTheDocument();
  });

  it("shows pulsing indicator during classification delay", async () => {
    wsReturn.status = "connected";
    wsReturn.routeSource = null;
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help me", type: "text" },
    ];
    // No stream_start yet = classification delay
    await renderChatPage();
    expect(screen.getByText(/routing to the right experts/i)).toBeInTheDocument();
  });

  it("shows N leaders responding status during streaming", async () => {
    wsReturn.activeLeaderIds = ["cmo", "cro"];
    wsReturn.messages = [
      { id: "u1", role: "user", content: "test", type: "text" },
      { id: "s1", role: "assistant", content: "...", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    // Appears in both desktop and mobile views
    expect(screen.getAllByText(/2 leaders responding/i).length).toBeGreaterThanOrEqual(1);
  });

  it("renders leader message with colored name badge", async () => {
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "My analysis", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    // CMO name badge should be present
    expect(screen.getByText("CMO")).toBeInTheDocument();
  });

  it("shows mobile back arrow", async () => {
    await renderChatPage();
    // Back arrow should exist (md:hidden is a Tailwind concern)
    const backLink = screen.getByLabelText(/back to dashboard/i);
    expect(backLink).toBeInTheDocument();
  });

  it("shows user messages as right-aligned bubbles", async () => {
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help with pricing", type: "text" },
    ];
    await renderChatPage();
    expect(screen.getByText("help with pricing")).toBeInTheDocument();
  });
});
