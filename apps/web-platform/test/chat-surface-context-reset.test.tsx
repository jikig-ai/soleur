// #3269 — chat-surface render coverage for the WS context_reset variant.
// Asserts both `reason` copy strings render verbatim from
// `CONTEXT_RESET_COPY` (single source of truth) and that the inline notice
// uses `data-message-type="context_reset"` for downstream selector hooks.
//
// Tests import `CONTEXT_RESET_COPY` directly — copywriter / test
// divergence is prevented at the type level.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
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

describe("ChatSurface — context_reset render (#3269)", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock({ realConversationId: "test-id" });
  });

  async function renderFull() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface variant="full" conversationId="test-id" />);
  }

  it("renders the prefill-guard copy from CONTEXT_RESET_COPY['prefill-guard']", async () => {
    const { CONTEXT_RESET_COPY } = await import(
      "@/components/chat/chat-copy"
    );
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        {
          id: "ctxrst-1",
          role: "assistant",
          content: "",
          type: "context_reset",
          reason: "prefill-guard",
        },
      ],
    });
    await renderFull();

    expect(
      screen.getByText(CONTEXT_RESET_COPY["prefill-guard"]),
    ).toBeInTheDocument();
  });

  it("renders the tool_use_orphan copy from CONTEXT_RESET_COPY['tool_use_orphan']", async () => {
    const { CONTEXT_RESET_COPY } = await import(
      "@/components/chat/chat-copy"
    );
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        {
          id: "ctxrst-2",
          role: "assistant",
          content: "",
          type: "context_reset",
          reason: "tool_use_orphan",
        },
      ],
    });
    await renderFull();

    expect(
      screen.getByText(CONTEXT_RESET_COPY["tool_use_orphan"]),
    ).toBeInTheDocument();
  });

  it("renders with data-message-type='context_reset' attribute", async () => {
    wsReturn = createWebSocketMock({
      realConversationId: "test-id",
      messages: [
        {
          id: "ctxrst-3",
          role: "assistant",
          content: "",
          type: "context_reset",
          reason: "prefill-guard",
        },
      ],
    });
    const { container } = await renderFull();

    const node = container.querySelector('[data-message-type="context_reset"]');
    expect(node).not.toBeNull();
  });
});
