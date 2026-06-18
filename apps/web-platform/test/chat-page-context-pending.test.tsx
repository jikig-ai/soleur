import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// Audit M1: the conversation page used to `return null` while the optional
// `?context=` KB fetch was in flight, leaving the route blank. The fix renders
// <ChatSurface> immediately (shell visible) and threads `contextPending` so the
// WS session-start still defers until context resolves — preserving the
// once-only `initialContext` delivery invariant (chat-page.test.tsx covers the
// no-regression side; this file asserts the new "no blank screen" behavior).

const mockStartSession = vi.fn();
const mockSendMessage = vi.fn();

let wsReturn = createWebSocketMock({
  startSession: mockStartSession,
  sendMessage: mockSendMessage,
  sessionConfirmed: false,
});

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();
vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: "new" }),
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: mockReplace }),
  usePathname: () => "/dashboard/chat/new",
}));

describe("ChatPage — context-pending render (audit M1)", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let fetchSpy: any;

  beforeEach(() => {
    mockStartSession.mockClear();
    mockSendMessage.mockClear();
    wsReturn = createWebSocketMock({
      startSession: mockStartSession,
      sendMessage: mockSendMessage,
      sessionConfirmed: false,
    });
    wsReturn.status = "connected";
    for (const key of [...mockSearchParams.keys()]) {
      mockSearchParams.delete(key);
    }
  });

  afterEach(() => {
    fetchSpy?.mockRestore();
  });

  async function renderChatPage() {
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  it("renders the chat shell immediately while the ?context= fetch is pending (no blank screen)", async () => {
    // KB-content fetch never resolves → context stays pending. The unrelated
    // active-repo mount poll (useActiveRepo, #5394) gets a benign 200 so it
    // doesn't interfere now that ChatSurface mounts while context is pending.
    fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
      const url =
        typeof input === "string"
          ? input
          : input instanceof Request
            ? input.url
            : String(input);
      if (url.includes("/api/kb/content/")) return new Promise<Response>(() => {});
      return Promise.resolve(new Response(JSON.stringify({}), { status: 200 }));
    });
    mockSearchParams.set("context", "product/roadmap.md");

    await renderChatPage();

    // The shell must be visible immediately even though context is pending.
    // (Before the fix, the page returned null and this text never appeared.)
    await waitFor(() => {
      expect(
        screen.getByText(/send a message to get started/i),
      ).toBeInTheDocument();
    });

    // …but the WS session must NOT have started yet — it waits for context.
    expect(mockStartSession).not.toHaveBeenCalled();
  });

  it("starts the session with the resolved initialContext once the fetch resolves", async () => {
    let resolveKbFetch!: (value: Response) => void;
    const kbPromise = new Promise<Response>((resolve) => {
      resolveKbFetch = resolve;
    });
    fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation((input) => {
      const url =
        typeof input === "string"
          ? input
          : input instanceof Request
            ? input.url
            : String(input);
      if (url.includes("/api/kb/content/")) return kbPromise;
      return Promise.resolve(new Response(JSON.stringify({}), { status: 200 }));
    });
    mockSearchParams.set("context", "product/roadmap.md");

    await renderChatPage();

    // Shell visible, session still deferred.
    await waitFor(() => {
      expect(
        screen.getByText(/send a message to get started/i),
      ).toBeInTheDocument();
    });
    expect(mockStartSession).not.toHaveBeenCalled();

    // Resolve the KB fetch → session starts with the resolved context only now.
    resolveKbFetch(
      new Response(JSON.stringify({ content: "# Roadmap\nPhase 1..." }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }),
    );

    await waitFor(() => {
      expect(mockStartSession).toHaveBeenCalledWith(
        undefined,
        expect.objectContaining({
          path: "product/roadmap.md",
          type: "kb-viewer",
          content: "# Roadmap\nPhase 1...",
        }),
      );
    });
  });
});
