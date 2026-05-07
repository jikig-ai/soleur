import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, act, fireEvent } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// Tasks 5.3 – 5.7 (RED) — Stop button + Esc shortcut + cleanup.
//
// All five tests render the real ChatSurface with a mocked useWebSocket so
// we can assert on the abort spy. ChatSurface is the binding site for both
// (a) the Stop button replacing Send (delegated to ChatInput via props)
// and (b) the document-level keydown listener with the focus guard.

const mockAbort = vi.fn();
const mockSend = vi.fn();
let wsReturn: ReturnType<typeof createWebSocketMock> & {
  abort: typeof mockAbort;
  streamState: "idle" | "streaming" | "stopping";
};

vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }));
vi.mock("@/lib/analytics-client", () => ({ track: vi.fn() }));
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock(),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));
vi.mock("next/navigation", () => ({
  useSearchParams: () => new URLSearchParams(),
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
  usePathname: () => "/dashboard/chat/cid-1",
}));
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

function makeWs(overrides: { streamState: "idle" | "streaming" | "stopping" }) {
  const base = createWebSocketMock({
    sendMessage: mockSend,
    realConversationId: "cid-1",
    activeLeaderIds: overrides.streamState === "idle" ? [] : ["cto"],
  }) as ReturnType<typeof createWebSocketMock>;
  return {
    ...base,
    abort: mockAbort,
    streamState: overrides.streamState,
  };
}

async function mount() {
  const { ChatSurface } = await import("@/components/chat/chat-surface");
  return render(<ChatSurface variant="full" conversationId="cid-1" />);
}

beforeEach(() => {
  vi.clearAllMocks();
  mockAbort.mockClear();
});

describe("Stop button (task 5.3)", () => {
  it("renders Stop in place of Send while streamState='streaming' and click invokes abort()", async () => {
    wsReturn = makeWs({ streamState: "streaming" });
    await mount();

    // Send button is gone; Stop button is present.
    expect(screen.queryByRole("button", { name: /send message/i })).toBeNull();
    const stop = screen.getByRole("button", { name: /stop/i });

    act(() => {
      stop.click();
    });

    expect(mockAbort).toHaveBeenCalledTimes(1);
  });

  it("Stop button is disabled and labeled 'Stopping…' while streamState='stopping'", async () => {
    wsReturn = makeWs({ streamState: "stopping" });
    await mount();

    const stop = screen.getByRole("button", { name: /stop/i });
    expect((stop as HTMLButtonElement).disabled).toBe(true);
    // Visible label transitions to "Stopping…" while waiting for session_ended
    expect(stop.textContent).toMatch(/stopping/i);
  });
});

describe("Esc keyboard shortcut (tasks 5.4 – 5.5)", () => {
  it("invokes abort() when Esc is pressed and the textarea is empty (focus on chat surface)", async () => {
    wsReturn = makeWs({ streamState: "streaming" });
    await mount();

    // Default focus state: textarea empty, no element explicitly focused.
    act(() => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });

    expect(mockAbort).toHaveBeenCalledTimes(1);
  });

  it("does NOT invoke abort() when textarea has 10+ chars and is focused (Esc-while-typing guard)", async () => {
    wsReturn = makeWs({ streamState: "streaming" });
    await mount();

    const textarea = screen.getByRole("textbox") as HTMLTextAreaElement;
    fireEvent.change(textarea, { target: { value: "user is mid-sentence here" } });
    textarea.focus();

    act(() => {
      // Dispatch on document so the chat-surface's document-level listener
      // would fire if the focus guard is broken.
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });

    expect(mockAbort).not.toHaveBeenCalled();
  });

  it("does NOT invoke abort() when streamState='idle' (no in-flight turn)", async () => {
    wsReturn = makeWs({ streamState: "idle" });
    await mount();

    act(() => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });

    expect(mockAbort).not.toHaveBeenCalled();
  });
});

describe("double-click safety (task 5.6)", () => {
  it("a second Stop click while streamState='stopping' is a no-op (button disabled)", async () => {
    wsReturn = makeWs({ streamState: "stopping" });
    await mount();

    const stop = screen.getByRole("button", { name: /stop/i });
    act(() => {
      stop.click();
      stop.click();
    });

    // The disabled button must not fire abort even on programmatic .click().
    expect(mockAbort).not.toHaveBeenCalled();
  });
});

describe("useEffect cleanup (task 5.7)", () => {
  it("removes the document keydown listener on unmount", async () => {
    wsReturn = makeWs({ streamState: "streaming" });
    const { unmount } = await mount();

    unmount();

    // After unmount, dispatching Esc must NOT reach the abort spy — the
    // useEffect cleanup function returned by the effect must have called
    // document.removeEventListener.
    act(() => {
      document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
    });

    expect(mockAbort).not.toHaveBeenCalled();
  });
});
