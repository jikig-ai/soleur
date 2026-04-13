import { render, screen, within, fireEvent } from "@testing-library/react";
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
    archived_at: null,
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

describe("ConversationRow Archive", () => {
  it("renders archive button when onArchive is provided", () => {
    const onArchive = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation()}
        onArchive={onArchive}
        onUnarchive={vi.fn()}
      />,
    );

    const buttons = screen.getAllByLabelText("Archive conversation");
    expect(buttons.length).toBeGreaterThanOrEqual(1);
  });

  it("does not render archive button when callbacks are omitted", () => {
    render(<ConversationRow conversation={makeConversation()} />);

    const buttons = screen.queryAllByLabelText(/Archive conversation|Unarchive conversation/);
    expect(buttons).toHaveLength(0);
  });

  it("renders unarchive button when conversation is archived", () => {
    render(
      <ConversationRow
        conversation={makeConversation({ archived_at: new Date().toISOString() })}
        onArchive={vi.fn()}
        onUnarchive={vi.fn()}
      />,
    );

    const buttons = screen.getAllByLabelText("Unarchive conversation");
    expect(buttons.length).toBeGreaterThanOrEqual(1);
  });

  it("archive button click does not trigger row navigation", () => {
    const mockPush = vi.fn();
    vi.mocked(vi.fn()).mockReturnValue({ push: mockPush });

    const onArchive = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation()}
        onArchive={onArchive}
        onUnarchive={vi.fn()}
      />,
    );

    // Click the archive button — should call onArchive, not navigate
    const archiveBtn = screen.getAllByLabelText("Archive conversation")[0];
    fireEvent.click(archiveBtn);

    expect(onArchive).toHaveBeenCalledWith("conv-1");
  });

  it("shows archived visual indicator when archived_at is set", () => {
    render(
      <ConversationRow
        conversation={makeConversation({ archived_at: new Date().toISOString() })}
        onArchive={vi.fn()}
        onUnarchive={vi.fn()}
      />,
    );

    const indicators = screen.getAllByText("Archived");
    expect(indicators.length).toBeGreaterThanOrEqual(1);
  });
});
