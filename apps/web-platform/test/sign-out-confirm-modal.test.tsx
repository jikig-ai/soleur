import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SignOutConfirmModal } from "@/components/auth/sign-out-confirm-modal";

const BASE_PROPS = {
  open: true,
  onClose: vi.fn(),
  onConfirm: vi.fn(),
  isSigningOut: false,
};

describe("SignOutConfirmModal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("does not render when open is false", () => {
    const { container } = render(
      <SignOutConfirmModal {...BASE_PROPS} open={false} />,
    );

    expect(container.innerHTML).toBe("");
  });

  it("renders dialog with role and aria-modal when open is true", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveAttribute("aria-modal", "true");
    expect(dialog).toHaveAttribute("aria-labelledby", "signout-heading");
  });

  it("focuses the Cancel button on open (least-destructive default)", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    const cancelButton = screen.getByRole("button", { name: /cancel/i });
    expect(document.activeElement).toBe(cancelButton);
  });

  it("calls onClose when Escape key is pressed", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    fireEvent.keyDown(document, { key: "Escape" });
    expect(BASE_PROPS.onClose).toHaveBeenCalledTimes(1);
  });

  it("calls onClose when the backdrop is clicked", () => {
    const { container } = render(<SignOutConfirmModal {...BASE_PROPS} />);

    const backdrop = container.querySelector('[role="presentation"]');
    expect(backdrop).not.toBeNull();
    fireEvent.click(backdrop!);
    expect(BASE_PROPS.onClose).toHaveBeenCalledTimes(1);
  });

  it("does NOT call onClose when the backdrop is clicked while signing out", () => {
    const { container } = render(
      <SignOutConfirmModal {...BASE_PROPS} isSigningOut={true} />,
    );

    const backdrop = container.querySelector('[role="presentation"]');
    expect(backdrop).not.toBeNull();
    fireEvent.click(backdrop!);
    expect(BASE_PROPS.onClose).not.toHaveBeenCalled();
  });

  it("calls onClose when Cancel is clicked", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));
    expect(BASE_PROPS.onClose).toHaveBeenCalledTimes(1);
  });

  it("calls onConfirm when Sign out is clicked", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    fireEvent.click(screen.getByRole("button", { name: /^sign out$/i }));
    expect(BASE_PROPS.onConfirm).toHaveBeenCalledTimes(1);
  });

  it("disables both buttons and shows Signing out… when isSigningOut is true", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} isSigningOut={true} />);

    // aria-label="Sign out" is pinned across visual state changes so the
    // accessible name is stable for agent selectors. Visible text flips to
    // "Signing out…" and aria-busy="true" surfaces the in-flight state to AT.
    const cancelButton = screen.getByRole("button", { name: /cancel/i });
    const confirmButton = screen.getByRole("button", { name: "Sign out" });

    expect(cancelButton).toBeDisabled();
    expect(confirmButton).toBeDisabled();
    expect(confirmButton).toHaveAttribute("aria-busy", "true");
    expect(confirmButton).toHaveTextContent(/signing out/i);
  });

  it("does not call onClose when ESC is pressed while signing out", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} isSigningOut={true} />);

    fireEvent.keyDown(document, { key: "Escape" });
    expect(BASE_PROPS.onClose).not.toHaveBeenCalled();
  });

  it("restores focus to the trigger element when closed", () => {
    const trigger = document.createElement("button");
    trigger.textContent = "Sign out";
    document.body.appendChild(trigger);
    trigger.focus();
    expect(document.activeElement).toBe(trigger);

    const { rerender } = render(<SignOutConfirmModal {...BASE_PROPS} />);
    // Modal opened — focus moved into modal
    expect(document.activeElement).not.toBe(trigger);

    // Close the modal
    rerender(<SignOutConfirmModal {...BASE_PROPS} open={false} />);

    // Focus restored to the trigger
    expect(document.activeElement).toBe(trigger);

    trigger.remove();
  });

  it("traps Tab focus inside the dialog (Shift+Tab from first wraps to last)", () => {
    render(<SignOutConfirmModal {...BASE_PROPS} />);

    const cancelButton = screen.getByRole("button", { name: /cancel/i });
    const confirmButton = screen.getByRole("button", { name: /^sign out$/i });

    // Initial focus is on Cancel (first focusable)
    expect(document.activeElement).toBe(cancelButton);

    // Shift+Tab from first wraps to last
    fireEvent.keyDown(document, { key: "Tab", shiftKey: true });
    expect(document.activeElement).toBe(confirmButton);

    // Tab from last wraps to first
    fireEvent.keyDown(document, { key: "Tab" });
    expect(document.activeElement).toBe(cancelButton);
  });
});
