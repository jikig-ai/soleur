import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act, fireEvent } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// Phase 4 wiring: submitQuote from KbChatContext flows through
// KbChatSidebar → ChatInput.insertQuote. Sending a message containing a
// blockquote emits track("kb.chat.selection_sent", { path }) from the
// sidebar (not from ChatInput — domain leakage).

const mockSendMessage = vi.fn();
const mockStartSession = vi.fn();
const mockTrack = vi.fn();

let wsReturn = createWebSocketMock({
  startSession: mockStartSession,
  sendMessage: mockSendMessage,
  realConversationId: "cid-1",
});

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
  usePathname: () => "/dashboard/kb/knowledge-base/overview/constitution.md",
}));
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => true,
}));

describe("KbChatSidebar — quote wiring", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = createWebSocketMock({
      startSession: mockStartSession,
      sendMessage: mockSendMessage,
      realConversationId: "cid-1",
    });
  });

  async function renderSidebar() {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const { KbChatQuoteBridgeContext } = await import(
      "@/components/kb/kb-chat-quote-bridge"
    );
    const registered: Array<((t: string) => void) | null> = [];
    const ctxValue = {
      open: true,
      openSidebar: vi.fn(),
      closeSidebar: vi.fn(),
      contextPath: "knowledge-base/overview/constitution.md",
      enabled: true,
      messageCount: 0,
      setMessageCount: vi.fn(),
    };
    // Direct-inject a quote-bridge value that captures registrations so the
    // test can invoke the handler KbChatContent registered.
    const bridgeValue = {
      submitQuote: vi.fn(),
      registerQuoteHandler: (h: ((t: string) => void) | null) => {
        registered.push(h);
      },
    };
    const rendered = render(
      <KbChatContext value={ctxValue}>
        <KbChatQuoteBridgeContext value={bridgeValue}>
          <KbChatSidebar
            open={true}
            onClose={vi.fn()}
            contextPath="knowledge-base/overview/constitution.md"
          />
        </KbChatQuoteBridgeContext>
      </KbChatContext>,
    );
    return { rendered, registered };
  }

  it("sidebar registers an insertQuote handler on mount", async () => {
    const { registered } = await renderSidebar();
    // At least one non-null registration should have happened.
    const nonNull = registered.filter((h) => typeof h === "function");
    expect(nonNull.length).toBeGreaterThan(0);
  });

  it("invoking the registered handler inserts a quoted block into the textarea", async () => {
    const { registered } = await renderSidebar();
    const handler = registered.find((h) => typeof h === "function") as
      | ((t: string) => void)
      | undefined;
    expect(handler).toBeTruthy();
    act(() => { handler!("selected passage"); });
    const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(textarea).not.toBeNull();
    expect(textarea.value).toContain("> selected passage\n\n");
  });

  it("sending a message whose content starts with '>' fires kb.chat.selection_sent", async () => {
    await renderSidebar();
    const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
    // Simulate a controlled change: set value via the native setter.
    const nativeSetter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      "value",
    )!.set!;
    act(() => {
      nativeSetter.call(textarea, "> a quoted passage\n\nmy follow-up question");
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    });
    act(() => {
      fireEvent.keyDown(textarea, { key: "Enter" });
    });
    expect(mockSendMessage).toHaveBeenCalled();
    expect(mockTrack).toHaveBeenCalledWith("kb.chat.selection_sent", {
      path: "knowledge-base/overview/constitution.md",
      source: "human",
    });
  });

  it("sending a message without a blockquote does NOT fire kb.chat.selection_sent", async () => {
    await renderSidebar();
    const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
    const nativeSetter = Object.getOwnPropertyDescriptor(
      window.HTMLTextAreaElement.prototype,
      "value",
    )!.set!;
    act(() => {
      nativeSetter.call(textarea, "just a question with no quote");
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
    });
    act(() => {
      fireEvent.keyDown(textarea, { key: "Enter" });
    });
    expect(mockSendMessage).toHaveBeenCalled();
    const calls = mockTrack.mock.calls.map((c) => c[0]);
    expect(calls).not.toContain("kb.chat.selection_sent");
  });

  it("sidebar input placeholder includes the ⌘⇧L shortcut hint", async () => {
    await renderSidebar();
    const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(textarea.getAttribute("placeholder") ?? "").toMatch(
      /ask about this document.*⌘⇧L/i,
    );
  });
});
