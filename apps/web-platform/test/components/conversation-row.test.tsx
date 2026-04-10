import { render, screen } from "@testing-library/react";
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
    last_active: new Date().toISOString(),
    created_at: new Date().toISOString(),
    title: "Test conversation",
    preview: "Some preview text",
    lastMessageLeader: null,
    ...overrides,
  };
}

describe("ConversationRow LeaderBadge", () => {
  it("renders a Soleur logo image instead of text when domain_leader is set", () => {
    const { container } = render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const imgs = container.querySelectorAll<HTMLImageElement>("img[src*='soleur-logo-mark']");
    expect(imgs.length).toBeGreaterThan(0);
    expect(imgs[0].src).toContain("/icons/soleur-logo-mark.png");
  });

  it("does not render leader ID text in the badge", () => {
    render(<ConversationRow conversation={makeConversation({ domain_leader: "cmo" })} />);

    const badges = screen.queryAllByText("CMO");
    expect(badges).toHaveLength(0);
  });

  it("has aria-label combining Soleur with leader ID", () => {
    render(<ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />);

    const badge = screen.getAllByLabelText(/Soleur CTO/i);
    expect(badge.length).toBeGreaterThan(0);
  });

  it("sets alt='' on the logo image (decorative)", () => {
    const { container } = render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const img = container.querySelector<HTMLImageElement>("img[src*='soleur-logo-mark']");
    expect(img).not.toBeNull();
    expect(img).toHaveAttribute("alt", "");
  });

  it("does not render a badge when domain_leader is null", () => {
    const { container } = render(
      <ConversationRow conversation={makeConversation({ domain_leader: null })} />,
    );

    const img = container.querySelector<HTMLImageElement>("img[src*='soleur-logo-mark']");
    expect(img).toBeNull();
  });
});
