import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act } from "@testing-library/react";
import { useState } from "react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// Phase 6.1: Panel accessibility.
// - <aside-like> role=dialog with aria-label including filename.
// - On open, focus moves to the ChatInput textarea.
// - On close, focus returns to the trigger button that opened the sidebar.
// - Close button has aria-label="Close panel" (covered elsewhere but
//   re-asserted here for negative-space protection).

type MockTextMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  type: "text";
};

const mockTrack = vi.fn();
let wsReturn = {
  messages: [] as MockTextMessage[],
  startSession: vi.fn(),
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
  realConversationId: "cid-1" as string | null,
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
  usePathname: () => "/dashboard/kb/knowledge-base/overview/constitution.md",
}));
vi.mock("@/hooks/use-media-query", () => ({
  useMediaQuery: () => true,
}));

describe("KbChatSidebar — accessibility (Phase 6.1)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    wsReturn = { ...wsReturn, messages: [], resumedFrom: null };
  });

  async function harness() {
    const { KbChatSidebar } = await import("@/components/chat/kb-chat-sidebar");
    const { KbChatTrigger } = await import("@/components/kb/kb-chat-trigger");
    const { KbChatContext } = await import("@/components/kb/kb-chat-context");

    function Host() {
      const [open, setOpen] = useState(false);
      const ctx = {
        open,
        openSidebar: () => setOpen(true),
        closeSidebar: () => setOpen(false),
        contextPath: "knowledge-base/overview/constitution.md",
        enabled: true,
        submitQuote: () => {},
        registerQuoteHandler: () => {},
        messageCount: 0,
        setMessageCount: () => {},
      };
      return (
        <KbChatContext value={ctx}>
          <KbChatTrigger fallbackHref="/dashboard/chat/new" />
          {open && (
            <KbChatSidebar
              open={open}
              onClose={() => setOpen(false)}
              contextPath="knowledge-base/overview/constitution.md"
            />
          )}
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
    await new Promise((r) => setTimeout(r, 0));
    const textarea = document.querySelector("textarea") as HTMLTextAreaElement;
    expect(textarea).not.toBeNull();
    expect(document.activeElement).toBe(textarea);
  });

  it("returns focus to the trigger button on close", async () => {
    await harness();
    const trigger = screen.getByRole("button", { name: /ask about this document/i });
    act(() => { trigger.click(); });
    await new Promise((r) => setTimeout(r, 0));

    // Now close via the Close panel button.
    const closeBtn = screen.getByLabelText(/close panel/i);
    act(() => { closeBtn.click(); });
    await new Promise((r) => setTimeout(r, 0));
    expect(document.activeElement).toBe(trigger);
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
    const leftoverTa = document.createElement("textarea");
    leftoverTa.setAttribute("data-testid", "leftover-ta");
    leftover.appendChild(leftoverTa);
    document.body.insertBefore(leftover, document.body.firstChild);

    try {
      await harness();
      act(() => { screen.getByRole("button", { name: /ask about this document/i }).click(); });
      await new Promise((r) => setTimeout(r, 0));

      const sidebarTa = screen.getByPlaceholderText(/ask about this document/i) as HTMLTextAreaElement;
      expect(document.activeElement).toBe(sidebarTa);
      expect(document.activeElement).not.toBe(leftoverTa);
    } finally {
      document.body.removeChild(leftover);
    }
  });
});
