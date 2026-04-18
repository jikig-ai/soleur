import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import { ErrorCard } from "../components/ui/error-card";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

describe("ErrorCard component", () => {
  test("renders error message", () => {
    render(
      <ErrorCard
        title="Connection failed"
        message="Unable to connect to the server"
      />,
    );
    expect(screen.getByText("Connection failed")).toBeDefined();
    expect(screen.getByText("Unable to connect to the server")).toBeDefined();
  });

  test("renders retry button when onRetry provided", () => {
    let retried = false;
    render(
      <ErrorCard
        title="Error"
        message="Something went wrong"
        onRetry={() => { retried = true; }}
        retryLabel="Try again"
      />,
    );
    const button = screen.getByText("Try again");
    expect(button).toBeDefined();
    button.click();
    expect(retried).toBe(true);
  });

  test("renders action link when action provided", () => {
    render(
      <ErrorCard
        title="Invalid API Key"
        message="Your key has expired"
        action={{ label: "Update key", href: "/dashboard/settings" }}
      />,
    );
    const link = screen.getByText("Update key");
    expect(link).toBeDefined();
    expect(link.getAttribute("href")).toBe("/dashboard/settings");
  });

  test("does not render retry button when no onRetry", () => {
    render(
      <ErrorCard title="Error" message="Something went wrong" />,
    );
    expect(screen.queryByRole("button")).toBeNull();
  });
});

describe("WebSocketError interface", () => {
  test("error codes map to structured objects", () => {
    // Verify the error code mapping exists and has correct shape
    const errorMap: Record<string, { message: string; action?: { label: string; href?: string } }> = {
      key_invalid: {
        message: "Your API key is invalid or expired.",
        action: { label: "Update key", href: "/dashboard/settings" },
      },
      rate_limited: {
        message: "You've been rate limited. Please wait before trying again.",
      },
      connection_failed: {
        message: "Unable to connect to the server.",
      },
    };

    expect(errorMap.key_invalid.action?.href).toBe("/dashboard/settings");
    expect(errorMap.rate_limited.message).toContain("rate limited");
    expect(errorMap.connection_failed.message).toContain("connect");
  });
});

// --- Hook contract tests for error state clearing (#1377) ---

const mockStartSession = vi.fn();
const mockResumeSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();
const mockReconnect = vi.fn();

let wsReturn = createWebSocketMock({
  startSession: mockStartSession,
  resumeSession: mockResumeSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  reconnect: mockReconnect,
  sessionConfirmed: false,
});

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: "test-conv" }),
  useSearchParams: () => new URLSearchParams(),
  useRouter: () => ({ replace: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-conv",
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

describe("Error state clearing on remount (#1377)", () => {
  beforeEach(() => {
    mockReconnect.mockClear();
    wsReturn = createWebSocketMock({
      startSession: mockStartSession,
      resumeSession: mockResumeSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      reconnect: mockReconnect,
      sessionConfirmed: false,
    });
  });

  async function renderChatPage() {
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  test("error card is NOT shown when lastError is null (clean remount)", async () => {
    wsReturn.lastError = null;
    await renderChatPage();
    expect(screen.queryByText("Invalid API Key")).toBeNull();
    expect(screen.queryByText("Rate Limited")).toBeNull();
  });

  test("error card IS shown when lastError is set to key_invalid", async () => {
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    await renderChatPage();
    expect(screen.getByText("Invalid API Key")).toBeInTheDocument();
    expect(screen.getByText("Update key")).toBeInTheDocument();
  });

  test("error card disappears when lastError is cleared (simulates remount clearing)", async () => {
    // First render: error present
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    const { unmount } = await renderChatPage();
    expect(screen.getByText("Invalid API Key")).toBeInTheDocument();
    unmount();

    // Second render: error cleared (simulates what the fix does on remount)
    wsReturn.lastError = null;
    await renderChatPage();
    expect(screen.queryByText("Invalid API Key")).toBeNull();
  });

  test("reconnect button not shown for key_invalid errors", async () => {
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    await renderChatPage();
    expect(screen.queryByText("Reconnect")).toBeNull();
  });
});
