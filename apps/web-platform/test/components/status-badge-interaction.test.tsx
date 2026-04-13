import { render, screen, fireEvent } from "@testing-library/react";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { ConversationRow } from "@/components/inbox/conversation-row";
import type { ConversationWithPreview } from "@/hooks/use-conversations";

const mockPush = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
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

describe("StatusBadge interactions", () => {
  beforeEach(() => {
    mockPush.mockClear();
  });

  it("opens dropdown with Dismiss when failed badge is clicked", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "failed" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Needs attention");
    fireEvent.click(badges[0]);

    expect(screen.getByText("Dismiss")).toBeInTheDocument();
  });

  it("opens dropdown with Mark resolved when waiting badge is clicked", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "waiting_for_user" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Needs your decision");
    fireEvent.click(badges[0]);

    expect(screen.getByText("Mark resolved")).toBeInTheDocument();
  });

  it("does not show dropdown for active status", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "active" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Executing");
    fireEvent.click(badges[0]);

    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
  });

  it("does not show dropdown for completed status", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "completed" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Completed");
    fireEvent.click(badges[0]);

    expect(screen.queryByRole("menu")).not.toBeInTheDocument();
  });

  it("calls onStatusChange with completed when Dismiss is clicked", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "failed" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Needs attention");
    fireEvent.click(badges[0]);
    fireEvent.click(screen.getByText("Dismiss"));

    expect(onStatusChange).toHaveBeenCalledWith("conv-1", "completed");
  });

  it("calls onStatusChange with completed when Mark resolved is clicked", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "waiting_for_user" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Needs your decision");
    fireEvent.click(badges[0]);
    fireEvent.click(screen.getByText("Mark resolved"));

    expect(onStatusChange).toHaveBeenCalledWith("conv-1", "completed");
  });

  it("badge click does not trigger row navigation", () => {
    const onStatusChange = vi.fn();
    render(
      <ConversationRow
        conversation={makeConversation({ status: "failed" })}
        onStatusChange={onStatusChange}
      />,
    );

    const badges = screen.getAllByText("Needs attention");
    fireEvent.click(badges[0]);

    expect(mockPush).not.toHaveBeenCalled();
  });

  it("does not show dropdown when onStatusChange is not provided", () => {
    render(
      <ConversationRow
        conversation={makeConversation({ status: "failed" })}
      />,
    );

    const badges = screen.getAllByText("Needs attention");
    fireEvent.click(badges[0]);

    expect(screen.queryByText("Dismiss")).not.toBeInTheDocument();
  });
});
