import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

type MockTextMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text";
  leaderId?: string;
  state?: "thinking" | "tool_use" | "streaming" | "done" | "error";
};

const mockStartSession = vi.fn();
const mockResumeSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();

let wsReturn = {
  messages: [] as MockTextMessage[],
  startSession: mockStartSession,
  resumeSession: mockResumeSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  status: "connected" as const,
  disconnectReason: undefined as string | undefined,
  lastError: null as import("@/lib/ws-client").WebSocketError | null,
  reconnect: vi.fn(),
  routeSource: null as "auto" | "mention" | null,
  activeLeaderIds: [] as string[],
  sessionConfirmed: true,
  usageData: null as { totalCostUsd: number } | null,
  realConversationId: "test-id",
};

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn() }),
  usePathname: () => "/dashboard/kb/some/path.md",
}));

describe("ChatSurface variant=\"sidebar\"", () => {
  beforeEach(() => {
    wsReturn = {
      messages: [],
      startSession: mockStartSession,
      resumeSession: mockResumeSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      status: "connected",
      disconnectReason: undefined,
      lastError: null,
      reconnect: vi.fn(),
      routeSource: null,
      activeLeaderIds: [],
      sessionConfirmed: true,
      usageData: null,
      realConversationId: "test-id",
    };
  });

  async function renderSidebar() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant="sidebar" conversationId="abc" />);
  }

  it("does NOT render the full-mode Command Center header", async () => {
    await renderSidebar();
    expect(screen.queryByText("Command Center")).toBeNull();
  });

  it("does NOT render the mobile back-to-dashboard arrow", async () => {
    await renderSidebar();
    expect(screen.queryByLabelText(/back to dashboard/i)).toBeNull();
  });

  it("renders messages without the max-w-3xl full-width wrapper", async () => {
    wsReturn.messages = [
      { id: "u1", role: "user", content: "hello there", type: "text" },
    ];
    await renderSidebar();
    const userText = screen.getByText("hello there");
    // Walk up ancestors — none should have the full-route width wrapper.
    let el: HTMLElement | null = userText;
    while (el && el !== document.body) {
      expect(el.className).not.toMatch(/max-w-3xl/);
      el = el.parentElement;
    }
  });

  it("renders user blockquotes as blockquote HTML (markdown on user bubbles)", async () => {
    wsReturn.messages = [
      { id: "u1", role: "user", content: "> quoted passage\n\nmy question", type: "text" },
    ];
    await renderSidebar();
    const bq = document.querySelector("blockquote");
    expect(bq).not.toBeNull();
    expect(bq!.textContent).toContain("quoted passage");
  });

  it("resumes an existing conversation on mount (conversationId !== new)", async () => {
    await renderSidebar();
    expect(mockResumeSession).toHaveBeenCalledWith("abc");
  });
});
