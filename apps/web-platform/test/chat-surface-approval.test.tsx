/**
 * #4672 task 3.1: the chat thread renders the durable approval card, sends the Owner's decision through the hook's
 * `sendApprovalDecide`, and a pending approval the agent is still waiting on counts as "awaiting user input" (the
 * "Still working…" narration is suppressed, exactly like a review gate).
 */
import { beforeEach, describe, expect, it, vi } from "vitest";
import { act, fireEvent, render, screen } from "@testing-library/react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { ChatMessage } from "@/lib/chat-state-machine";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";
import { canonicalizeAction } from "@/server/approval/canonical";
import { renderApprovalView } from "@/server/approval/render";
import { SAMPLES, TOOLS } from "./approval/fixtures";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }));
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock({ getDisplayName: (id: DomainLeaderId) => id.toUpperCase() }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));
const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

const userMsg: ChatMessage = { id: "u1", role: "user", content: "please proceed", type: "text" };
const s = SAMPLES[TOOLS.emailSend];
const view = renderApprovalView(canonicalizeAction(TOOLS.emailSend, s.input, s.server));

type Card = Extract<ChatMessage, { type: "approval_request" }>;
const card = (id: string, over: Partial<Card> = {}): ChatMessage => ({
  id: `approval-${id}`,
  role: "assistant",
  content: view.title,
  type: "approval_request",
  approvalId: id,
  conversationId: "test-id",
  toolName: TOOLS.emailSend,
  view,
  status: "pending",
  expiresAt: "2099-01-01T00:00:00.000Z",
  requestCount: 1,
  viewerRole: "owner",
  agentWaiting: true,
  ...over,
});

const ID1 = "00000000-0000-4000-8000-000000000006";
const ID2 = "00000000-0000-4000-8000-0000000000c2";

async function renderStreaming(messages: ChatMessage[], extra: Parameters<typeof createWebSocketMock>[0] = {}) {
  wsReturn = createWebSocketMock({
    realConversationId: "test-id",
    streamState: "streaming",
    liveNarration: "Looking into your request…",
    messages,
    ...extra,
  });
  const { ChatSurface } = await import("@/components/chat/chat-surface");
  return render(<ChatSurface variant="full" conversationId="test-id" />);
}

beforeEach(() => {
  wsReturn = createWebSocketMock({ realConversationId: "test-id" });
});

describe("approval card in the thread", () => {
  it("renders the server-built card with the bound action and Approve/Deny for the Owner", async () => {
    await renderStreaming([userMsg, card(ID1)]);
    expect(screen.getByTestId("approval-request-card")).toBeInTheDocument();
    expect(screen.getByTestId("approval-bound-block").textContent).toContain(String(s.input.to));
    expect(screen.getByRole("button", { name: "Approve" })).toBeInTheDocument();
  });

  it("a member's card is read-only: no buttons", async () => {
    await renderStreaming([userMsg, card(ID1, { viewerRole: "member" })]);
    expect(screen.queryByRole("button", { name: "Approve" })).toBeNull();
    expect(screen.getByText("Waiting for the workspace Owner")).toBeInTheDocument();
  });

  it("Approve sends approval_decide through the hook with the approval id and the closed enum", async () => {
    await renderStreaming([userMsg, card(ID1)]);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(wsReturn.sendApprovalDecide).toHaveBeenCalledWith(ID1, "approve");
  });

  it("Deny sends the deny decision", async () => {
    await renderStreaming([userMsg, card(ID1)]);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Deny" }));
    });
    expect(wsReturn.sendApprovalDecide).toHaveBeenCalledWith(ID1, "deny");
  });

  it("a socket that is not open (hook returns false) shows the static error and no optimistic state", async () => {
    await renderStreaming([userMsg, card(ID1)], { sendApprovalDecide: vi.fn(() => false) });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Approve" }));
    });
    expect(screen.getByTestId("approval-decide-error")).toBeInTheDocument();
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("pending_owner");
  });

  it("the older of two pending cards for the same tool shows the newer-request banner, the newer one does not", async () => {
    await renderStreaming([userMsg, card(ID1), card(ID2)]);
    const cards = screen.getAllByTestId("approval-request-card");
    expect(cards).toHaveLength(2);
    expect(cards[0].querySelector("[data-testid=approval-newer-banner]")).not.toBeNull();
    expect(cards[1].querySelector("[data-testid=approval-newer-banner]")).toBeNull();
  });

  it("the outcome of this socket's own decide settles the card (released while the agent waits)", async () => {
    await renderStreaming([userMsg, card(ID1, { status: "approved", agentWaiting: true, decideOutcome: "decided" })]);
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("released");
    expect(screen.getByTestId("approval-decided-label").textContent).toBe("by you");
  });

  it("a late approval (the agent stopped waiting) tells the Owner to ask again", async () => {
    await renderStreaming([userMsg, card(ID1, { status: "approved", agentWaiting: false })]);
    expect(screen.getByRole("heading", { name: "Approved. Ask your agent again." })).toBeInTheDocument();
  });

  it("an approved card offers Revoke approval, which sends the same decide with deny through the hook", async () => {
    await renderStreaming([userMsg, card(ID1, { status: "approved", agentWaiting: false })]);
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "Revoke approval" }));
    });
    expect(wsReturn.sendApprovalDecide).toHaveBeenCalledWith(ID1, "deny");
  });

  it("a revoked card renders the revoked state with no buttons", async () => {
    await renderStreaming([userMsg, card(ID1, { status: "rejected", decideOutcome: "revoked", agentWaiting: false })]);
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("revoked");
    expect(screen.queryByRole("button", { name: "Revoke approval" })).toBeNull();
  });
});

describe("awaitingUserInput counts a pending approval the agent is waiting on", () => {
  it("pending + agent waiting -> live narration ABSENT", async () => {
    await renderStreaming([userMsg, card(ID1)]);
    expect(screen.queryByTestId("live-narration")).not.toBeInTheDocument();
  });

  it("pending but the agent stopped waiting -> narration PRESENT (the agent is working again)", async () => {
    await renderStreaming([userMsg, card(ID1, { agentWaiting: false })]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });

  it("a resolved approval does not suppress narration", async () => {
    await renderStreaming([userMsg, card(ID1, { status: "consumed", agentWaiting: false })]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });

  it("a stale card from BEFORE the last user message does not suppress narration (turn-scoped)", async () => {
    await renderStreaming([card(ID1), userMsg]);
    expect(screen.getByTestId("live-narration")).toBeInTheDocument();
  });
});
