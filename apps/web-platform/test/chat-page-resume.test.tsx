import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, waitFor } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

const mockStartSession = vi.fn();
const mockResumeSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();

let wsReturn = createWebSocketMock({
  startSession: mockStartSession,
  resumeSession: mockResumeSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  sessionConfirmed: false,
});

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

// Mock useTeamNames hook
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// Mock next/navigation — conversationId is a UUID (existing conversation)
const EXISTING_CONV_ID = "fc105c6a-3abc-46b4-b92e-c054b4bd8f0f";
const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();

vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: EXISTING_CONV_ID }),
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: mockReplace }),
  usePathname: () => `/dashboard/chat/${EXISTING_CONV_ID}`,
}));

describe("ChatPage — existing conversation (resume_session)", () => {
  beforeEach(() => {
    mockStartSession.mockClear();
    mockResumeSession.mockClear();
    mockSendMessage.mockClear();
    wsReturn = createWebSocketMock({
      startSession: mockStartSession,
      resumeSession: mockResumeSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      sessionConfirmed: false,
    });
    for (const key of [...mockSearchParams.keys()]) {
      mockSearchParams.delete(key);
    }
  });

  async function renderChatPage() {
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  it("calls resumeSession with conversationId for existing conversations", async () => {
    wsReturn.status = "connected";
    await renderChatPage();

    await waitFor(() => {
      expect(mockResumeSession).toHaveBeenCalledWith(EXISTING_CONV_ID);
    });
  });

  it("does NOT call startSession for existing conversations", async () => {
    wsReturn.status = "connected";
    await renderChatPage();

    // Wait for effects to settle
    await waitFor(() => {
      expect(mockResumeSession).toHaveBeenCalled();
    });

    expect(mockStartSession).not.toHaveBeenCalled();
  });

  it("re-sends resumeSession after reconnection", async () => {
    wsReturn.status = "connected";
    const { rerender } = await renderChatPage();

    // First connection: resumeSession called once
    await waitFor(() => {
      expect(mockResumeSession).toHaveBeenCalledTimes(1);
    });

    // Simulate reconnecting status
    wsReturn.status = "reconnecting";
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    rerender(<mod.default />);

    // Simulate reconnected status
    wsReturn.status = "connected";
    rerender(<mod.default />);

    // resumeSession should have been called a second time
    await waitFor(() => {
      expect(mockResumeSession).toHaveBeenCalledTimes(2);
    });
  });

  it("displays cost estimate when usageData is present on resume", async () => {
    wsReturn.status = "connected";
    wsReturn.sessionConfirmed = true;
    wsReturn.usageData = {
      totalCostUsd: 0.0042,
      inputTokens: 1200,
      outputTokens: 300,
    };

    const { container } = await renderChatPage();

    await waitFor(() => {
      // The cost display uses ~$X.XXXX format
      expect(container.textContent).toContain("~$0.0042");
    });
  });

  it("sends initial ?msg= after sessionConfirmed on existing conversation", async () => {
    mockSearchParams.set("msg", "here is the document");
    wsReturn.status = "connected";
    wsReturn.sessionConfirmed = true;

    await renderChatPage();

    await waitFor(() => {
      expect(mockSendMessage).toHaveBeenCalledWith("here is the document");
    });
  });
});
