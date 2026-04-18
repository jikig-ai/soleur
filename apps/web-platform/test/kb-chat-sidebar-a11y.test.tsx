import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, act, waitFor } from "@testing-library/react";
import { useState } from "react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// Phase 6.1: Panel accessibility.
// - <aside-like> role=dialog with aria-label including filename.
// - On open, focus moves to the ChatInput textarea.
// - On close, focus returns to the trigger button that opened the sidebar.
// - Close button has aria-label="Close panel" (covered elsewhere but
//   re-asserted here for negative-space protection).
//
// Uses real timers — focus flush is rAF-driven. Do not add
// vi.useFakeTimers() here; the `waitFor` focus assertions below rely
// on real rAF / microtask settle.

const mockTrack = vi.fn();
let wsReturn = createWebSocketMock({ realConversationId: "cid-1" });

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

describe("KbChatSidebar — accessibility (Phase 6.1)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = createWebSocketMock({ realConversationId: "cid-1" });
  });

  // Belt-and-braces cleanup: a stray leftover `[data-kb-chat]` node injected
  // by a test would shadow subsequent focus assertions (the legacy bug the
  // a11y test below characterizes). Runs even when a test throws before
  // reaching its own try/finally. Leftover nodes are tagged
  // `data-leftover-cleanup` so we only remove test fixtures, never real
  // KbChatContent output.
  afterEach(() => {
    document
      .querySelectorAll("[data-leftover-cleanup]")
      .forEach((node) => node.parentElement?.removeChild(node));
  });

  async function harness() {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatTrigger } = await import("@/components/kb/kb-chat-trigger");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");
    const { KbChatQuoteBridgeProvider } = await import(
      "@/components/kb/kb-chat-quote-bridge"
    );

    function Host() {
      const [open, setOpen] = useState(false);
      const ctx = {
        open,
        openSidebar: () => setOpen(true),
        closeSidebar: () => setOpen(false),
        contextPath: "knowledge-base/overview/constitution.md",
        enabled: true,
        messageCount: 0,
        setMessageCount: () => {},
      };
      return (
        <KbChatContext value={ctx}>
          <KbChatQuoteBridgeProvider onOpenSidebar={() => setOpen(true)}>
            <KbChatTrigger fallbackHref="/dashboard/chat/new" />
            {open && (
              <KbChatSidebar
                open={open}
                onClose={() => setOpen(false)}
                contextPath="knowledge-base/overview/constitution.md"
              />
            )}
          </KbChatQuoteBridgeProvider>
        </KbChatContext>
      );
    }
    return render(<Host />);
  }

  it("sidebar dialog has an aria-label that includes the filename", async () => {
    await harness();
    act(() => { screen.getByRole("button", { name: /ask about this document/i }).click(); });
    const dialog = screen.getByRole("dialog");
    const label = dialog.getAttribute("aria-label") ?? "";
    expect(label).toMatch(/constitution\.md/);
  });

  it("moves focus to the textarea on open", async () => {
    await harness();
    act(() => { screen.getByRole("button", { name: /ask about this document/i }).click(); });
    const textarea = await screen.findByPlaceholderText(/ask about this document/i) as HTMLTextAreaElement;
    await waitFor(() => expect(document.activeElement).toBe(textarea));
  });

  it("returns focus to the trigger button on close", async () => {
    await harness();
    const trigger = screen.getByRole("button", { name: /ask about this document/i });
    act(() => { trigger.click(); });
    const closeBtn = await screen.findByLabelText(/close panel/i);
    act(() => { closeBtn.click(); });
    await waitFor(() => expect(document.activeElement).toBe(trigger));
  });

  it("renders a Close panel button with an accessible name", async () => {
    await harness();
    act(() => { screen.getByRole("button", { name: /ask about this document/i }).click(); });
    expect(screen.getByLabelText(/close panel/i)).toBeTruthy();
  });

  it("focuses its own textarea when a pre-existing [data-kb-chat] scope exists (#2384 5B)", async () => {
    // Inject a leftover [data-kb-chat] container with its own textarea
    // BEFORE the sidebar mounts. The legacy focus effect called
    // `document.querySelector("[data-kb-chat] textarea")` which returns
    // the FIRST matching element in document order — the leftover, not
    // the sidebar's textarea. The ref-based fix bypasses the DOM query.
    const leftover = document.createElement("div");
    leftover.setAttribute("data-kb-chat", "");
    leftover.setAttribute("data-leftover-cleanup", "");
    const leftoverTa = document.createElement("textarea");
    leftoverTa.setAttribute("data-testid", "leftover-ta");
    leftover.appendChild(leftoverTa);
    document.body.insertBefore(leftover, document.body.firstChild);

    try {
      await harness();
      act(() => { screen.getByRole("button", { name: /ask about this document/i }).click(); });

      const sidebarTa = await screen.findByPlaceholderText(/ask about this document/i) as HTMLTextAreaElement;
      // Focus is scheduled via requestAnimationFrame inside kb-chat-content.
      // `waitFor` retries until rAF fires — more robust across CI timing
      // variance than a fixed `setTimeout(r, 0)` flush.
      await waitFor(() => {
        expect(document.activeElement).toBe(sidebarTa);
      });
      expect(document.activeElement).not.toBe(leftoverTa);
    } finally {
      document.body.removeChild(leftover);
    }
  });
});
