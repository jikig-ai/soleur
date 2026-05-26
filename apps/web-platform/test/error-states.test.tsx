import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
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

  test("renders dismiss button when onDismiss provided", () => {
    render(
      <ErrorCard
        title="Error"
        message="Something went wrong"
        onDismiss={() => {}}
      />,
    );
    expect(screen.getByRole("button", { name: /dismiss/i })).toBeDefined();
  });

  test("does not render dismiss button when onDismiss omitted", () => {
    render(
      <ErrorCard title="Error" message="Something went wrong" />,
    );
    expect(screen.queryByRole("button", { name: /dismiss/i })).toBeNull();
  });

  test("clicking dismiss invokes onDismiss exactly once", async () => {
    const onDismiss = vi.fn();
    render(
      <ErrorCard
        title="Error"
        message="Something went wrong"
        onDismiss={onDismiss}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: /dismiss/i }));
    expect(onDismiss).toHaveBeenCalledTimes(1);
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

// --- Dismissable error cards on chat surface ---

describe("Error card dismissal on chat surface", () => {
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

  test("clicking dismiss on lastError card hides it without affecting hook state (AC2 + AC14)", async () => {
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    const beforeRef = wsReturn.lastError;
    await renderChatPage();

    expect(screen.getByText("Invalid API Key")).toBeInTheDocument();

    await userEvent.click(
      screen.getByRole("button", { name: /dismiss/i }),
    );

    // Card hidden via render-gating
    expect(screen.queryByText("Invalid API Key")).toBeNull();
    // Hook state untouched: same object identity (AC14)
    expect(wsReturn.lastError).toBe(beforeRef);
  });

  test("dismissing then same (code, message) re-firing after a null intermediate re-shows the card (regression: PR #3558 review)", async () => {
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    const result = render(<mod.default />);

    await userEvent.click(
      screen.getByRole("button", { name: /dismiss/i }),
    );
    expect(screen.queryByText("Invalid API Key")).toBeNull();

    // Reconnect path: lastError nulls (component stays mounted; dismissedErrorKey persists in state).
    wsReturn.lastError = null;
    result.rerender(<mod.default />);
    expect(screen.queryByText("Invalid API Key")).toBeNull();

    // Identical shape re-fires after the null intermediate. Without the
    // null-edge-trigger reset of dismissedErrorKey, the rehydrated key would
    // still match and the card would stay hidden.
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    result.rerender(<mod.default />);

    expect(screen.getByText("Invalid API Key")).toBeInTheDocument();
  });

  test("dismissing one error then a new error code re-shows the card with role=alert (AC3 + AC13)", async () => {
    wsReturn.lastError = {
      code: "key_invalid",
      message: "Your API key is invalid or expired.",
      action: { label: "Update key", href: "/dashboard/settings" },
    };
    const { unmount } = await renderChatPage();
    await userEvent.click(
      screen.getByRole("button", { name: /dismiss/i }),
    );
    expect(screen.queryByText("Invalid API Key")).toBeNull();
    unmount();

    // New error fires (different key); component re-renders
    wsReturn.lastError = {
      code: "rate_limited",
      message: "You hit the rate limit.",
    };
    await renderChatPage();

    expect(screen.getByText("Rate Limited")).toBeInTheDocument();
    expect(screen.getByRole("alert")).toBeInTheDocument();
  });
});
