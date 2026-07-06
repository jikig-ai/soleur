import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { ChatMessage } from "@/lib/chat-state-machine";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

// feat-one-shot-concierge-web-duplicate-question-box (AC3–AC5c): while the
// agent is PARKED awaiting the operator's answer to a review_gate /
// autonomous_disclosure, the bottom "Still working…" live-narration slot must
// NOT render — the amber prompt card already conveys the waiting state, and a
// spinner contradicts it. The suppression is awaiting-input-scoped (resolved
// gates resume narration), turn-scoped (a stale prior-turn gate does not dark
// later turns), and must NOT fire for informational interactive_prompt cards
// (diff / todo_write) that stream while the agent keeps working.

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

const userMsg = (id: string): ChatMessage => ({
  id,
  role: "user",
  content: "please proceed",
  type: "text",
});

const reviewGate = (id: string, resolved: boolean): ChatMessage => ({
  id,
  role: "assistant",
  content: "",
  type: "review_gate",
  gateId: `gate-${id}`,
  question: "Continue implementing / Investigate first / Abort?",
  options: ["Continue implementing", "Investigate first", "Abort"],
  resolved,
  ...(resolved ? { selectedOption: "Continue implementing" } : {}),
});

const autonomousDisclosure = (id: string, resolved: boolean): ChatMessage => ({
  id,
  role: "assistant",
  content: "",
  type: "autonomous_disclosure",
  gateId: `disc-${id}`,
  existingWorkspace: false,
  resolved,
});

const diffPrompt = (id: string): ChatMessage => ({
  id,
  role: "assistant",
  content: "",
  type: "interactive_prompt",
  promptId: `pr-${id}`,
  conversationId: "test-id",
  promptKind: "diff",
  promptPayload: { path: "/w/src/foo.ts", additions: 3, deletions: 1 },
});

async function renderStreaming(messages: ChatMessage[]) {
  wsReturn = createWebSocketMock({
    realConversationId: "test-id",
    streamState: "streaming",
    liveNarration: null,
    messages,
  });
  const { ChatSurface } = await import("@/components/chat/chat-surface");
  return render(<ChatSurface variant="full" conversationId="test-id" />);
}

describe("ChatSurface — 'Still working…' suppressed while awaiting operator input", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  it("AC3 — unresolved current-turn review_gate → live-narration slot ABSENT", async () => {
    await renderStreaming([userMsg("u1"), reviewGate("g1", false)]);
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
  });

  it("AC3 (autonomous_disclosure disjunct) — unresolved current-turn autonomous_disclosure → slot ABSENT", async () => {
    await renderStreaming([userMsg("u1"), autonomousDisclosure("d1", false)]);
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
  });

  it("AC4 — streaming with NO gate → live-narration slot PRESENT ('Still working…')", async () => {
    await renderStreaming([userMsg("u1")]);
    const slot = screen.getByTestId("live-narration");
    expect(slot).toBeInTheDocument();
    expect(slot).toHaveTextContent("Still working…");
  });

  it("AC5 — resolved review_gate + streaming → slot PRESENT (suppression is awaiting-input-scoped, not permanent)", async () => {
    await renderStreaming([userMsg("u1"), reviewGate("g1", true)]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });

  it("AC5b — unresolved informational interactive_prompt (diff) + no gate → slot PRESENT (informational cards must NOT suppress)", async () => {
    await renderStreaming([userMsg("u1"), diffPrompt("p1")]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });

  it("AC5c — unresolved review_gate BEFORE the last user message (stale prior-turn gate) → slot PRESENT (turn-scoping excludes stale gates)", async () => {
    await renderStreaming([reviewGate("g0", false), userMsg("u1")]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });
});
