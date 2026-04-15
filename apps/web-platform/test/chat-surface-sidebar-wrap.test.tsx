import { describe, it, expect, vi, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// Narrow-column hardening for Phase 3.1 + AC10:
// "Long URLs and code blocks wrap (not scroll) inside 380px sidebar."
// The full-page chat variant keeps `overflow-x-auto` on <pre>; the sidebar
// variant must switch to `whitespace-pre-wrap` + `[overflow-wrap:anywhere]`
// so a long fenced code line or URL reflows inside a 380px panel instead of
// forcing horizontal scroll.

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

const LONG_URL = "https://example.com/a/very/long/path/that/should/wrap/" +
  "not/scroll/inside/a/three-hundred-eighty-pixel-sidebar/with/no/break/points/here";

const LONG_CODE = "const absurdlyLongIdentifier_that_should_wrap_instead_of_forcing_horizontal_scroll = " +
  "someFunction(arg1, arg2, arg3, arg4);";

describe("ChatSurface variant=\"sidebar\" — narrow-column wrap (Phase 3.1 / AC10)", () => {
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

  async function renderWithMessage(content: string, variant: "full" | "sidebar") {
    wsReturn.messages = [
      { id: "a1", role: "assistant", content, type: "text", state: "done" },
    ];
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant={variant} conversationId="abc" />);
  }

  it("sidebar variant renders <pre> with wrap classes (not overflow-x-auto)", async () => {
    await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "sidebar");
    const pre = document.querySelector("pre");
    expect(pre).not.toBeNull();
    expect(pre!.className).toMatch(/whitespace-pre-wrap/);
    expect(pre!.className).toMatch(/overflow-wrap:anywhere|break-words/);
    expect(pre!.className).not.toMatch(/overflow-x-auto/);
  });

  it("full variant keeps <pre> scroll behavior (overflow-x-auto)", async () => {
    await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "full");
    const pre = document.querySelector("pre");
    expect(pre).not.toBeNull();
    expect(pre!.className).toMatch(/overflow-x-auto/);
  });

  it("sidebar variant: long URL container has overflow-wrap:anywhere", async () => {
    await renderWithMessage(`See ${LONG_URL} for details.`, "sidebar");
    // MarkdownRenderer wraps output in a div with min-w-0 + [overflow-wrap:anywhere].
    const wrapper = document.querySelector(".\\[overflow-wrap\\:anywhere\\]");
    expect(wrapper).not.toBeNull();
  });

  it("sidebar variant: min-w-0 is applied at every flex ancestor of message content", async () => {
    await renderWithMessage("some assistant reply", "sidebar");
    const text = document.body.querySelector("p, span, div");
    // Walk up from the rendered text and require every intermediate flex
    // container to also include min-w-0 so text truncation / wrap works.
    let el: Element | null = document.body.querySelector(".message-bubble-active, [class*='rounded-xl']");
    let flexAncestorsChecked = 0;
    while (el && el !== document.body) {
      const cls = el.className ?? "";
      if (typeof cls === "string" && /\bflex\b/.test(cls)) {
        expect(cls, `missing min-w-0 on flex ancestor: ${cls}`).toMatch(/\bmin-w-0\b/);
        flexAncestorsChecked += 1;
      }
      el = el.parentElement;
    }
    expect(flexAncestorsChecked).toBeGreaterThan(0);
    void text;
  });
});
