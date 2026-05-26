import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () =>
    createUseTeamNamesMock({
      getDisplayName: (id: DomainLeaderId) =>
        id === "cmo" ? "Marketing Lead" : id.toUpperCase(),
    }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

describe("ChatSurface — Soleur Concierge visibility in routing panel (#3251)", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  async function renderFull() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant="full" conversationId="test-id" />);
  }

  it("T1 — isClassifying chip uses the active-bubble + Working badge treatment", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
      ],
      routeSource: null,
      workflow: { state: "idle" },
      activeLeaderIds: [],
    });
    await renderFull();

    const chip = await screen.findByTestId("routing-chip");
    expect(chip).toBeInTheDocument();

    // Concierge avatar still left-positioned
    expect(within(chip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();

    // Active-bubble treatment (matches subsequent tool_use bubbles)
    expect(chip.querySelector(".message-bubble-active")).not.toBeNull();
    expect(within(chip).getByText("Working")).toBeInTheDocument();

    // Routing prose preserved (now rendered as the toolLabel inside the bubble body).
    // The doubled-header regression (#3225) is guarded by message-bubble-header.test.tsx
    // against the real titleContainsName branch — this test mock returns id.toUpperCase()
    // for getDisplayName so the production "Concierge" → "Soleur Concierge" promotion is
    // not exercised here.
    expect(
      within(chip).getByText(/routing to the right experts/i),
    ).toBeInTheDocument();
  });

  it("T2 — strip renders Concierge slot + routed-leader name when both bubbles present", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
        { id: "a1", role: "assistant", content: "routing", leaderId: "cc_router", type: "text" },
        { id: "a2", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
      ],
      routeSource: "auto",
      workflow: { state: "idle" },
      activeLeaderIds: ["cmo"],
    });
    await renderFull();

    const strip = await screen.findByTestId("routed-leaders-strip");
    expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
    expect(within(strip).getByText("Soleur Concierge")).toBeInTheDocument();
    expect(within(strip).getByText(/Marketing Lead/i)).toBeInTheDocument();
  });

  it("T3 — strip shows Concierge even when respondingLeaders excludes cc_router", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
        { id: "a1", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
      ],
      routeSource: "auto",
      activeLeaderIds: ["cmo"],
    });
    await renderFull();

    const strip = await screen.findByTestId("routed-leaders-strip");
    expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
    expect(within(strip).getByText("Soleur Concierge")).toBeInTheDocument();
  });

  it("T4 — strip is absent when routeSource is null (pre-routing regression guard)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
      ],
      routeSource: null,
    });
    await renderFull();

    expect(screen.queryByTestId("routed-leaders-strip")).not.toBeInTheDocument();
  });

  it("T5 — strip emits 'Soleur Concierge' exactly once and never the bare 'Concierge' (#3225 regression)", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
        { id: "a1", role: "assistant", content: "routing", leaderId: "cc_router", type: "text" },
        { id: "a2", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
      ],
      routeSource: "auto",
      activeLeaderIds: ["cmo"],
    });
    await renderFull();

    const strip = await screen.findByTestId("routed-leaders-strip");
    expect(within(strip).getAllByText("Soleur Concierge")).toHaveLength(1);
    expect(within(strip).queryAllByText(/^Concierge$/)).toHaveLength(0);
  });

  it("T6 — strip is hidden when only cc_router responded (load-bearing some() predicate)", async () => {
    // The chat-surface gate uses respondingLeaders.some(id => id !== CC_ROUTER_LEADER_ID).
    // Without this test, the predicate could regress to .length > 0 and the suite would
    // still pass — yet a Concierge-only response would render an empty leader strip.
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        { id: "u1", role: "user", content: "hello", type: "text" },
        { id: "a1", role: "assistant", content: "handled", leaderId: "cc_router", type: "text" },
      ],
      routeSource: "auto",
      activeLeaderIds: [],
    });
    await renderFull();

    expect(screen.queryByTestId("routed-leaders-strip")).not.toBeInTheDocument();
  });
});
