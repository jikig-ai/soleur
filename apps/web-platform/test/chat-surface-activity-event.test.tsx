import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, act } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";
import { ChatSurface } from "@/components/chat/chat-surface";

// Emitter-half coverage for PR #9270 — the rail-side listener is proven in
// conversations-rail-activity-event.test.tsx; this file pins the OTHER end:
// chat-surface's derived-state dispatch of CONVERSATION_ACTIVITY_EVENT.
// Without these, deleting the production effect leaves the suite green and
// the whole fix dead — including the inverse-lie AC that a socket
// bind/resume (mount) must NEVER signal activity.

let wsReturn = createWebSocketMock({ realConversationId: "cid-1" });

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

const dispatchSpy = vi.fn();
const realDispatch = window.dispatchEvent.bind(window);

async function mount() {
  return render(<ChatSurface variant="full" conversationId="cid-1" />);
}

const freshEl = () => <ChatSurface variant="full" conversationId="cid-1" />;

function activityCalls() {
  return dispatchSpy.mock.calls.filter(
    ([ev]) => (ev as CustomEvent).type === "soleur:conversation-activity",
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  dispatchSpy.mockClear();
  wsReturn = createWebSocketMock({ realConversationId: "cid-1" });
  window.dispatchEvent = dispatchSpy;
});

afterEach(() => {
  window.dispatchEvent = realDispatch;
});

describe("ChatSurface — CONVERSATION_ACTIVITY_EVENT emission", () => {
  it("emits with detail.conversationId when streamState transitions idle → streaming", async () => {
    const view = await mount();
    expect(activityCalls()).toHaveLength(0);

    wsReturn = {
      ...wsReturn,
      streamState: "streaming",
      activeLeaderIds: ["cto" as never],
    };
    await act(async () => view.rerender(freshEl()));

    const calls = activityCalls();
    expect(calls).toHaveLength(1);
    expect((calls[0][0] as CustomEvent).detail).toEqual({
      conversationId: "cid-1",
    });
  });

  it("does NOT emit on mount even when streamState arrives 'streaming' (resume-on-view is not activity)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "cid-1",
      streamState: "streaming" as never,
      activeLeaderIds: ["cto" as never],
    });
    await mount();
    expect(activityCalls()).toHaveLength(0);
  });

  it("emits when streamState leaves streaming (turn end)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "cid-1",
      streamState: "streaming" as never,
      activeLeaderIds: ["cto" as never],
    });
    const view = await mount();
    expect(activityCalls()).toHaveLength(0);

    wsReturn = { ...wsReturn, streamState: "idle" as never, activeLeaderIds: [] };
    await act(async () => view.rerender(freshEl()));

    expect(activityCalls().length).toBeGreaterThanOrEqual(1);
  });

  it("emits on the awaitingUserInput gate transition (review gate opens)", async () => {
    const view = await mount();
    expect(activityCalls()).toHaveLength(0);

    wsReturn = {
      ...wsReturn,
      streamState: "streaming" as never,
      messages: [
        { role: "user", content: "go" },
        {
          type: "review_gate",
          gateId: "g-1",
          question: "Continue / Abort?",
          options: ["Continue", "Abort"],
          resolved: false,
        },
      ] as never,
    };
    await act(async () => view.rerender(freshEl()));

    expect(activityCalls()).toHaveLength(1);
  });
});
