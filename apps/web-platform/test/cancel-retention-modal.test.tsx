import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
}));

import { CancelRetentionModal } from "@/components/settings/cancel-retention-modal";

const BASE_PROPS = {
  open: true,
  onClose: vi.fn(),
  onConfirmCancel: vi.fn(),
  conversationCount: 128,
  serviceTokenCount: 5,
  createdAt: new Date("2026-01-10").toISOString(),
};

describe("CancelRetentionModal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-13"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("renders stats grid with conversation count, services, and days", () => {
    render(<CancelRetentionModal {...BASE_PROPS} />);

    expect(screen.getByText("128")).toBeInTheDocument();
    expect(screen.getByText(/conversations/i)).toBeInTheDocument();
    expect(screen.getByText("5")).toBeInTheDocument();
    expect(screen.getByText(/connected services/i)).toBeInTheDocument();
    expect(screen.getByText("93")).toBeInTheDocument();
    expect(screen.getByText(/days building/i)).toBeInTheDocument();
  });

  it("calls onClose when Keep my account is clicked", () => {
    render(<CancelRetentionModal {...BASE_PROPS} />);

    fireEvent.click(screen.getByRole("button", { name: /keep my account/i }));
    expect(BASE_PROPS.onClose).toHaveBeenCalledTimes(1);
  });

  it("calls onConfirmCancel when Continue to cancel is clicked", () => {
    render(<CancelRetentionModal {...BASE_PROPS} />);

    fireEvent.click(
      screen.getByRole("button", { name: /continue to cancel/i }),
    );
    expect(BASE_PROPS.onConfirmCancel).toHaveBeenCalledTimes(1);
  });

  it("does not render when open is false", () => {
    const { container } = render(
      <CancelRetentionModal {...BASE_PROPS} open={false} />,
    );

    expect(container.innerHTML).toBe("");
  });

  it("renders without stats section when counts are zero", () => {
    render(
      <CancelRetentionModal
        {...BASE_PROPS}
        conversationCount={0}
        serviceTokenCount={0}
      />,
    );

    // Modal should still render with CTAs functional
    expect(
      screen.getByRole("button", { name: /keep my account/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /continue to cancel/i }),
    ).toBeInTheDocument();
  });

  it("has role=dialog and aria-modal=true", () => {
    render(<CancelRetentionModal {...BASE_PROPS} />);

    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveAttribute("aria-modal", "true");
    expect(dialog).toHaveAttribute("aria-labelledby", "retention-heading");
  });

  it("calls onClose when Escape key is pressed", () => {
    render(<CancelRetentionModal {...BASE_PROPS} />);

    fireEvent.keyDown(document, { key: "Escape" });
    expect(BASE_PROPS.onClose).toHaveBeenCalledTimes(1);
  });
});
