import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createUseTeamNamesMock } from "./mocks/use-team-names";

// Mock useWebSocket hook
const mockStartSession = vi.fn();
const mockSendMessage = vi.fn();
const mockSendReviewGateResponse = vi.fn();

type MockTextMessage = { id: string; role: "user" | "assistant"; content: string; type: "text"; leaderId?: string; state?: "thinking" | "tool_use" | "streaming" | "done" | "error" };
type MockGateMessage = { id: string; role: "user" | "assistant"; content: string; type: "review_gate"; leaderId?: string; gateId: string; question: string; options: string[]; header?: string; descriptions?: Record<string, string | undefined>; stepProgress?: { current: number; total: number }; resolved?: boolean; selectedOption?: string; gateError?: string };
type MockChatMessage = MockTextMessage | MockGateMessage;

let wsReturn = {
  messages: [] as MockChatMessage[],
  startSession: mockStartSession,
  sendMessage: mockSendMessage,
  sendReviewGateResponse: mockSendReviewGateResponse,
  status: "connected" as const,
  disconnectReason: undefined as string | undefined,
  lastError: null as import("@/lib/ws-client").WebSocketError | null,
  reconnect: vi.fn(),
  routeSource: null as "auto" | "mention" | null,
  activeLeaderIds: [] as string[],
  sessionConfirmed: false,
};

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

// Mock useTeamNames hook
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

// Mock next/navigation
const mockSearchParams = new URLSearchParams();
const mockReplace = vi.fn();
vi.mock("next/navigation", () => ({
  useParams: () => ({ conversationId: "new" }),
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: mockReplace }),
  usePathname: () => "/dashboard/chat/new",
}));

describe("ChatPage", () => {
  beforeEach(() => {
    mockStartSession.mockClear();
    mockSendMessage.mockClear();
    wsReturn = {
      messages: [],
      startSession: mockStartSession,
      sendMessage: mockSendMessage,
      sendReviewGateResponse: mockSendReviewGateResponse,
      status: "connected",
      disconnectReason: undefined,
      lastError: null,
      reconnect: vi.fn(),
      routeSource: null,
      activeLeaderIds: [],
      sessionConfirmed: false,
    };
    // Reset search params
    for (const key of [...mockSearchParams.keys()]) {
      mockSearchParams.delete(key);
    }
  });

  async function renderChatPage() {
    // Dynamic import to pick up mocks
    const mod = await import(
      "@/app/(dashboard)/dashboard/chat/[conversationId]/page"
    );
    return render(<mod.default />);
  }

  it("does NOT send msg when sessionConfirmed is false", async () => {
    mockSearchParams.set("msg", "help with pricing");
    wsReturn.sessionConfirmed = false;
    await renderChatPage();
    // Verify component rendered (effects have run)
    await waitFor(() => {
      expect(screen.getByText(/send a message to get started/i)).toBeInTheDocument();
    });
    // Now assert the negative — effects already confirmed
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("sends msg only after sessionConfirmed becomes true", async () => {
    mockSearchParams.set("msg", "help with pricing");
    wsReturn.sessionConfirmed = true;
    await renderChatPage();
    await waitFor(() => {
      expect(mockSendMessage).toHaveBeenCalledWith("help with pricing");
    });
  });

  it("does not re-send msg after reconnection resets sessionConfirmed", async () => {
    mockSearchParams.set("msg", "help with pricing");
    // First render: sessionConfirmed true, message gets sent
    wsReturn.sessionConfirmed = true;
    const { unmount } = await renderChatPage();
    await waitFor(() => {
      expect(mockSendMessage).toHaveBeenCalledWith("help with pricing");
    });
    unmount();

    // Reset mocks and simulate reconnection: sessionConfirmed back to false
    mockSendMessage.mockClear();
    mockStartSession.mockClear();
    wsReturn.sessionConfirmed = false;
    wsReturn.status = "connected";
    mockSearchParams.set("msg", "help with pricing");
    await renderChatPage();
    // Verify component rendered (effects have run)
    await waitFor(() => {
      expect(screen.getByText(/send a message to get started/i)).toBeInTheDocument();
    });
    // Now assert the negative — effects already confirmed
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("handleSend works when sessionConfirmed is false and status is connected", async () => {
    wsReturn.sessionConfirmed = false;
    wsReturn.status = "connected";
    await renderChatPage();

    const input = screen.getByPlaceholderText(/follow up or ask another question/i);
    await userEvent.type(input, "manual message");
    await userEvent.click(screen.getByLabelText("Send message"));

    expect(mockSendMessage).toHaveBeenCalledWith("manual message");
  });

  it("does not send any message when no ?msg= param is present even after sessionConfirmed", async () => {
    wsReturn.sessionConfirmed = true;
    wsReturn.status = "connected";
    await renderChatPage();

    // Verify component rendered (effects have run)
    await waitFor(() => {
      expect(screen.getByText(/send a message to get started/i)).toBeInTheDocument();
    });
    // Now assert the negative — effects already confirmed
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("shows error card and does not send msg when server errors before session_started", async () => {
    mockSearchParams.set("msg", "help with pricing");
    wsReturn.sessionConfirmed = false;
    wsReturn.lastError = {
      code: "rate_limited",
      message: "You've been rate limited.",
    };
    await renderChatPage();

    // Verify component rendered (effects have run)
    await waitFor(() => {
      expect(screen.getByText("You've been rate limited.")).toBeInTheDocument();
    });
    // Now assert the negative — effects already confirmed
    expect(mockSendMessage).not.toHaveBeenCalled();
  });

  it("shows routing badge for auto-routed messages", async () => {
    wsReturn.routeSource = "auto";
    wsReturn.activeLeaderIds = ["cmo", "cro"];
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help with strategy", type: "text" },
      { id: "s1", role: "assistant", content: "Here is my analysis", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    expect(screen.getByText(/auto-routed to/i)).toBeInTheDocument();
  });

  it("shows 'Directed to @' badge for mention-routed messages", async () => {
    wsReturn.routeSource = "mention";
    wsReturn.messages = [
      { id: "u1", role: "user", content: "@cmo help", type: "text" },
      { id: "s1", role: "assistant", content: "Sure", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    expect(screen.getByText(/directed to/i)).toBeInTheDocument();
  });

  it("shows pulsing indicator during classification delay", async () => {
    wsReturn.status = "connected";
    wsReturn.routeSource = null;
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help me", type: "text" },
    ];
    // No stream_start yet = classification delay
    await renderChatPage();
    expect(screen.getByText(/routing to the right experts/i)).toBeInTheDocument();
  });

  it("shows N leaders responding status during streaming", async () => {
    wsReturn.activeLeaderIds = ["cmo", "cro"];
    wsReturn.messages = [
      { id: "u1", role: "user", content: "test", type: "text" },
      { id: "s1", role: "assistant", content: "...", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    // Appears in both desktop and mobile views
    expect(screen.getAllByText(/2 leaders responding/i).length).toBeGreaterThanOrEqual(1);
  });

  it("renders leader message with domain-specific icon badge", async () => {
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "My analysis", type: "text", leaderId: "cmo" },
    ];
    await renderChatPage();
    // Domain icon badge should appear with aria-label
    const badge = screen.getByLabelText(/CMO avatar/i);
    expect(badge).toBeInTheDocument();
    // Should render lucide icon, not Soleur logo
    const img = badge.querySelector('img[src="/icons/soleur-logo-mark.png"]');
    expect(img).toBeNull();
    // Name label still shows display name
    expect(screen.getByText("CMO")).toBeInTheDocument();
  });

  it("shows mobile back arrow", async () => {
    await renderChatPage();
    // Back arrow should exist (md:hidden is a Tailwind concern)
    const backLink = screen.getByLabelText(/back to dashboard/i);
    expect(backLink).toBeInTheDocument();
  });

  it("shows user messages as right-aligned bubbles", async () => {
    wsReturn.messages = [
      { id: "u1", role: "user", content: "help with pricing", type: "text" },
    ];
    await renderChatPage();
    expect(screen.getByText("help with pricing")).toBeInTheDocument();
  });

  it("shows thinking dots when assistant bubble is in 'thinking' state", async () => {
    // Post-#2139: assistant bubbles always carry a state. Live bubbles set
    // it at stream_start; history-loaded bubbles get "done" at hydration.
    // The previous fallback heuristic (`!messageState && content === ""`)
    // was removed because it silently covered for a missing-state bug.
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "", type: "text", leaderId: "cpo", state: "thinking" },
    ];
    await renderChatPage();
    const dots = document.querySelectorAll("[data-testid='thinking-dots'] span");
    expect(dots.length).toBe(3);
  });

  it("hides thinking dots when assistant bubble is 'done' with content", async () => {
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "Here is my response", type: "text", leaderId: "cpo", state: "done" },
    ];
    await renderChatPage();
    const dots = document.querySelectorAll("[data-testid='thinking-dots']");
    expect(dots.length).toBe(0);
    expect(screen.getByText(/Here is my response/)).toBeInTheDocument();
  });

  it("renders markdown headings as styled elements (not raw ###)", async () => {
    wsReturn.activeLeaderIds = [];
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "### Current State", type: "text", leaderId: "coo" },
    ];
    await renderChatPage();
    // Should render as an h3, not raw "### Current State" text
    const heading = document.querySelector("h3");
    expect(heading).not.toBeNull();
    expect(heading!.textContent).toBe("Current State");
  });

  it("renders GFM tables as HTML tables", async () => {
    wsReturn.activeLeaderIds = [];
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "| Item | Status |\n| --- | --- |\n| Git | Done |", type: "text", leaderId: "coo" },
    ];
    await renderChatPage();
    const table = document.querySelector("table");
    expect(table).not.toBeNull();
    const cells = document.querySelectorAll("td");
    expect(cells.length).toBeGreaterThanOrEqual(2);
  });

  it("strips dangerous script tags from markdown", async () => {
    wsReturn.activeLeaderIds = [];
    wsReturn.messages = [
      { id: "s1", role: "assistant", content: "<script>alert('xss')</script>Safe text", type: "text", leaderId: "cpo" },
    ];
    await renderChatPage();
    // Script tag should not be present
    const scripts = document.querySelectorAll("script");
    expect(scripts.length).toBe(0);
    // Safe text should still render
    expect(screen.getByText(/Safe text/)).toBeInTheDocument();
  });

  describe("ConversationContext from ?context= param", () => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let fetchSpy: any;

    beforeEach(() => {
      fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(
        new Response(JSON.stringify({ content: "# Roadmap\nPhase 1..." }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    });

    afterEach(() => {
      fetchSpy.mockRestore();
    });

    it("passes ConversationContext to startSession when ?context= is present", async () => {
      mockSearchParams.set("context", "product/roadmap.md");
      mockSearchParams.set("msg", "Tell me about this file");
      wsReturn.status = "connected";

      await renderChatPage();

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

    it("starts session without context when KB API returns 404 (graceful degradation)", async () => {
      fetchSpy.mockResolvedValueOnce(
        new Response("Not found", { status: 404 }),
      );
      mockSearchParams.set("context", "missing/file.md");
      wsReturn.status = "connected";

      await renderChatPage();

      await waitFor(() => {
        expect(mockStartSession).toHaveBeenCalledWith(undefined, undefined);
      });
    });

    it("starts session without context when no ?context= param (no regression)", async () => {
      // No context param set
      wsReturn.status = "connected";

      await renderChatPage();

      await waitFor(() => {
        expect(mockStartSession).toHaveBeenCalledWith(undefined, undefined);
      });
      // fetch should not be called for KB content
      expect(fetchSpy).not.toHaveBeenCalled();
    });

    it("does not start session until context fetch resolves", async () => {
      let resolveKbFetch!: (value: Response) => void;
      fetchSpy.mockReturnValueOnce(
        new Promise<Response>((resolve) => {
          resolveKbFetch = resolve;
        }),
      );
      mockSearchParams.set("context", "product/roadmap.md");
      wsReturn.status = "connected";

      await renderChatPage();

      // Session should NOT have started yet (fetch still pending)
      expect(mockStartSession).not.toHaveBeenCalled();

      // Resolve the fetch
      resolveKbFetch(
        new Response(JSON.stringify({ content: "file content" }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );

      await waitFor(() => {
        expect(mockStartSession).toHaveBeenCalledWith(
          undefined,
          expect.objectContaining({ content: "file content" }),
        );
      });
    });

    it("gracefully degrades and logs when fetch rejects (network error)", async () => {
      const consoleSpy = vi.spyOn(console, "error").mockImplementation(() => {});
      fetchSpy.mockRejectedValueOnce(new Error("network failure"));
      mockSearchParams.set("context", "product/roadmap.md");
      wsReturn.status = "connected";

      await renderChatPage();

      await waitFor(() => {
        expect(mockStartSession).toHaveBeenCalledWith(undefined, undefined);
      });
      expect(consoleSpy).toHaveBeenCalledWith(
        "KB context fetch failed:",
        expect.any(Error),
      );
      consoleSpy.mockRestore();
    });

    it("treats empty ?context= as no context", async () => {
      mockSearchParams.set("context", "");
      wsReturn.status = "connected";

      await renderChatPage();

      await waitFor(() => {
        expect(mockStartSession).toHaveBeenCalledWith(undefined, undefined);
      });
      expect(fetchSpy).not.toHaveBeenCalled();
    });
  });

  describe("ReviewGateCard", () => {
    it("renders the question text prominently", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Which library?",
          type: "review_gate", gateId: "g1", question: "Which library?",
          options: ["React Query", "SWR"],
        },
      ];
      await renderChatPage();
      expect(screen.getByText("Which library?")).toBeInTheDocument();
    });

    it("renders header as a tag when provided", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Which library?",
          type: "review_gate", gateId: "g1", question: "Which library?",
          header: "Library", options: ["React Query", "SWR"],
        },
      ];
      await renderChatPage();
      expect(screen.getByText("Library")).toBeInTheDocument();
    });

    it("renders option descriptions as subtext", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Which approach?",
          type: "review_gate", gateId: "g1", question: "Which approach?",
          options: ["A", "B"],
          descriptions: { A: "First approach", B: "Second approach" },
        },
      ];
      await renderChatPage();
      expect(screen.getByText("First approach")).toBeInTheDocument();
      expect(screen.getByText("Second approach")).toBeInTheDocument();
    });

    it("renders option buttons", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
        },
      ];
      await renderChatPage();
      expect(screen.getByRole("button", { name: "Yes" })).toBeInTheDocument();
      expect(screen.getByRole("button", { name: "No" })).toBeInTheDocument();
    });

    it("calls onSelect and shows selected state when button clicked", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
        },
      ];
      await renderChatPage();
      await userEvent.click(screen.getByRole("button", { name: "Yes" }));
      expect(mockSendReviewGateResponse).toHaveBeenCalledWith("g1", "Yes");
    });

    it("renders collapsed summary when resolved", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
          resolved: true, selectedOption: "Yes",
        },
      ];
      await renderChatPage();
      expect(screen.getByText("Yes")).toBeInTheDocument();
      // Buttons should not be present in collapsed state
      expect(screen.queryByRole("button", { name: "No" })).not.toBeInTheDocument();
    });

    it("renders error message inline when gateError is set", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
          gateError: "Review gate not found or already resolved",
        },
      ];
      await renderChatPage();
      expect(screen.getByText(/Review gate not found/)).toBeInTheDocument();
    });

    it("has role=group and aria-label on card container", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Which library?",
          type: "review_gate", gateId: "g1", question: "Which library?",
          options: ["React Query", "SWR"],
        },
      ];
      await renderChatPage();
      const group = screen.getByRole("group", { name: "Which library?" });
      expect(group).toBeInTheDocument();
    });

    it("sets aria-busy during pending state", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
        },
      ];
      await renderChatPage();
      const group = screen.getByRole("group", { name: "Choose" });
      expect(group).toHaveAttribute("aria-busy", "false");
      await userEvent.click(screen.getByRole("button", { name: "Yes" }));
      expect(group).toHaveAttribute("aria-busy", "true");
    });

    it("renders error message with role=alert", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Choose",
          type: "review_gate", gateId: "g1", question: "Choose",
          options: ["Yes", "No"],
          gateError: "Review gate not found or already resolved",
        },
      ];
      await renderChatPage();
      const alert = screen.getByRole("alert");
      expect(alert).toHaveTextContent(/Review gate not found/);
    });

    it("renders step progress indicator when stepProgress is present", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Configure DNS",
          type: "review_gate", gateId: "g1", question: "Navigate to the DNS settings and add the A record.",
          header: "Step 2 of 6: Configure DNS",
          options: ["Done -- proceed to next step", "I need help", "Skip this step"],
          stepProgress: { current: 2, total: 6 },
        },
      ];
      await renderChatPage();
      expect(screen.getByText("Step 2 of 6")).toBeDefined();
      expect(screen.getByText("33%")).toBeDefined();
    });

    it("does not render step progress when stepProgress is absent", async () => {
      wsReturn.messages = [
        {
          id: "gate-g1", role: "assistant", content: "Which library?",
          type: "review_gate", gateId: "g1", question: "Which library?",
          options: ["React Query", "SWR"],
        },
      ];
      await renderChatPage();
      expect(screen.queryByText(/Step \d+ of \d+/)).toBeNull();
    });
  });
});
