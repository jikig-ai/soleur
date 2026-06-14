// #5282 — reconnect state-machine render coverage (AC4 / AC5 / AC7 / AC12).
// Asserts the rewired State-1 banner renders exactly once (no duplicate of the
// old inline chat-surface.tsx:567 banner), that connection state takes
// precedence over the State-2 watchdog chip (mutual exclusion), and that an
// `unrecoverable` connection never renders the State-4 "resumed" notice (no
// 3→4 flip at the render layer).
//
// Lives under test/components/chat/ so the vitest `component` project glob
// (test/**/*.test.tsx) collects it; a co-located components/**/*.test.tsx would
// be silently skipped.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { ChatMessage } from "@/lib/chat-state-machine";
import { createUseTeamNamesMock } from "../../mocks/use-team-names";
import { createWebSocketMock } from "../../mocks/use-websocket";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () =>
    createUseTeamNamesMock({
      getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

function retryingBubble(): ChatMessage {
  return {
    id: "retry-1",
    role: "assistant",
    content: "",
    type: "text",
    leaderId: "cpo" as DomainLeaderId,
    state: "tool_use",
    toolLabel: "Searching",
    retrying: true,
  } as ChatMessage;
}

async function renderFull() {
  const { ChatSurface } = await import("@/components/chat/chat-surface");
  return render(<ChatSurface variant="full" conversationId="test-id" />);
}

describe("ChatSurface — reconnect state machine (#5282)", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  it("AC4/AC7: State 1 renders exactly ONE connection-banner (no duplicate)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      status: "reconnecting",
      connection: { phase: "reconnecting" },
    });
    await renderFull();

    expect(screen.getAllByTestId("connection-banner")).toHaveLength(1);
    expect(screen.getByText("Connection lost. Reconnecting...")).toBeInTheDocument();
  });

  it("AC12: connection-lost banner present ⟹ retrying-chip absent (mutual exclusion)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      status: "reconnecting",
      connection: { phase: "reconnecting" },
      messages: [retryingBubble()],
    });
    await renderFull();

    expect(screen.queryByTestId("connection-banner")).toBeInTheDocument();
    expect(screen.queryByTestId("retrying-chip")).not.toBeInTheDocument();
  });

  it("State 2: live + retrying bubble shows the retrying-chip and NO connection-banner", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      connection: { phase: "live" },
      messages: [retryingBubble()],
    });
    await renderFull();

    expect(screen.getByTestId("retrying-chip")).toBeInTheDocument();
    expect(screen.queryByTestId("connection-banner")).not.toBeInTheDocument();
  });

  it("AC5: unrecoverable renders State 3 and NEVER the State-4 resumed notice (no 3→4 flip)", async () => {
    // resumedAt is set (a reattach happened) but phase is sticky-unrecoverable:
    // State 3 must win and State 4 must NOT render.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      connection: { phase: "unrecoverable", resumedAt: 1_000 },
    });
    await renderFull();

    expect(screen.getByTestId("connection-unrecoverable")).toBeInTheDocument();
    expect(screen.queryByTestId("connection-resumed")).not.toBeInTheDocument();
    // State 1 banner must also be absent under unrecoverable.
    expect(screen.queryByTestId("connection-banner")).not.toBeInTheDocument();
  });

  it("State 4: a live reattach with resumedAt shows the transient resumed notice", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      connection: { phase: "live", resumedAt: 2_000 },
    });
    await renderFull();

    expect(await screen.findByTestId("connection-resumed")).toBeInTheDocument();
    expect(screen.queryByTestId("connection-unrecoverable")).not.toBeInTheDocument();
  });
});
