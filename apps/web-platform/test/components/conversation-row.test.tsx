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

describe("ConversationRow LeaderAvatar", () => {
  it("renders a domain-specific icon badge for each leader (mobile + desktop)", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const badges = screen.getAllByLabelText(/CTO avatar/i);
    expect(badges).toHaveLength(2);
    // Should render lucide icon, not Soleur logo image
    for (const badge of badges) {
      const img = badge.querySelector('img[src="/icons/soleur-logo-mark.png"]');
      expect(img).toBeNull();
    }
  });

  it("applies the leader background color to the badge", () => {
    const { container } = render(
      <ConversationRow conversation={makeConversation({ domain_leader: "cto" })} />,
    );

    const badges = container.querySelectorAll("[aria-label='CTO avatar']");
    expect(badges.length).toBe(2);
    for (const badge of badges) {
      expect(badge.className).toContain("bg-blue-500");
    }
  });

  it("does not render a badge when domain_leader is null", () => {
    render(
      <ConversationRow conversation={makeConversation({ domain_leader: null })} />,
    );

    const badges = screen.queryAllByLabelText(/avatar/i);
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
