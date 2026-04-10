import { render, screen, within } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import { ConversationRow } from "@/components/inbox/conversation-row";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn() }),
}));

function makeConversation(
  overrides: Partial<ConversationWithPreview> = {},
): ConversationWithPreview {
  return {
    id: "conv-1",
    user_id: "user-1",
    domain_leader: "cto",
    session_id: null,
    status: "active",
    total_cost_usd: 0,
    input_tokens: 0,
    output_tokens: 0,
    last_active: new Date().toISOString(),
    created_at: new Date().toISOString(),
    title: "Test conversation",
    preview: "Some preview text",
    lastMessageLeader: null,
    ...overrides,
  };
}

describe("ConversationRow LeaderBadge", () => {
  it("renders a logo image inside each badge container", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const badges = screen.getAllByLabelText(/Soleur CTO/i);
    expect(badges).toHaveLength(2);

    for (const badge of badges) {
      const img = within(badge).getByRole("presentation");
      expect(img.tagName).toBe("IMG");
    }
  });

  it("sets the correct src on the logo image", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const badge = screen.getAllByLabelText(/Soleur CTO/i)[0];
    const img = within(badge).getByRole("presentation");
    expect(img).toHaveAttribute("src", "/icons/soleur-logo-mark.png");
  });

  it("does not render leader ID text in the badge", () => {
    render(<ConversationRow conversation={makeConversation({ domain_leader: "cmo" })} />);

    const badges = screen.queryAllByText("CMO");
    expect(badges).toHaveLength(0);
  });

  it("has aria-label combining Soleur with leader ID (mobile + desktop)", () => {
    render(<ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />);

    const badges = screen.getAllByLabelText(/Soleur CTO/i);
    expect(badges).toHaveLength(2);
  });

  it("sets alt='' on the logo image (decorative)", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const badge = screen.getAllByLabelText(/Soleur CTO/i)[0];
    const img = within(badge).getByRole("presentation");
    expect(img).toHaveAttribute("alt", "");
  });

  it("does not render a badge when domain_leader is null", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: null })} />,
    );

    const badges = screen.queryAllByLabelText(/Soleur/i);
    expect(badges).toHaveLength(0);
  });
});
