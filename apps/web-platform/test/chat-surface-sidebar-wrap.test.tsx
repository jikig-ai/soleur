import { describe, it, expect, vi, beforeEach } from "vitest";
import { render } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// Narrow-column hardening for Phase 3.1 + AC10:
// "Long URLs and code blocks wrap (not scroll) inside 380px sidebar."
// The full-page chat variant keeps `overflow-x-auto` on <pre>; the sidebar
// variant must switch to `whitespace-pre-wrap` + `[overflow-wrap:anywhere]`
// so a long fenced code line or URL reflows inside a 380px panel instead of
// forcing horizontal scroll.

const mockStartSession = vi.fn();
const mockResumeSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();

let wsReturn = createWebSocketMock({
  startSession: mockStartSession,
  resumeSession: mockResumeSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  realConversationId: "test-id",
});

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
    wsReturn = createWebSocketMock({
      startSession: mockStartSession,
      resumeSession: mockResumeSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      realConversationId: "test-id",
    });
  });

  async function renderWithMessage(content: string, variant: "full" | "sidebar") {
    wsReturn.messages = [
      { id: "a1", role: "assistant", content, type: "text", state: "done" },
    ];
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant={variant} conversationId="abc" />);
  }

  it("sidebar variant exposes a data-narrow-wrap='true' hook on rendered markdown", async () => {
    await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "sidebar");
    expect(
      document.querySelector("[data-narrow-wrap='true']"),
    ).not.toBeNull();
  });

  it("full variant does NOT set data-narrow-wrap", async () => {
    await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "full");
    expect(
      document.querySelector("[data-narrow-wrap='true']"),
    ).toBeNull();
  });

  it("sidebar variant: long URL is rendered inside the narrow-wrap container", async () => {
    await renderWithMessage(`See ${LONG_URL} for details.`, "sidebar");
    const wrapper = document.querySelector("[data-narrow-wrap='true']");
    expect(wrapper).not.toBeNull();
    expect(wrapper?.textContent ?? "").toContain("example.com");
  });

  it("sidebar variant: <pre> sits inside a narrow-wrap container (structural)", async () => {
    // jsdom doesn't compute layout, so a `scrollWidth <= clientWidth` check
    // would silently pass as a no-op (both values are always 0). Assert the
    // structural invariant instead: the sidebar <pre> must live inside a
    // `[data-narrow-wrap='true']` ancestor — the same hook the first test
    // proves the sidebar variant emits. An e2e test (Playwright) is the
    // right place for true visual wrap verification.
    await renderWithMessage("```ts\n" + LONG_CODE + "\n```", "sidebar");
    const pre = document.querySelector("pre");
    expect(pre).not.toBeNull();
    expect(pre?.closest("[data-narrow-wrap='true']")).not.toBeNull();
  });
});
