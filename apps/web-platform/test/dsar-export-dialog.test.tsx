import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { DsarExportDialog } from "@/components/settings/dsar-export-dialog";

// Phase 8 UI tests for the DSAR confirmation dialog.
//
// Plan rev-2 FR1 + AC31. Verifies:
// - Trigger button is disabled when hasActiveJob=true (AC31).
// - Opening the dialog reveals password input + <details> disclosure.
// - Confirm calls onConfirmPassword with the typed password.
// - Cancel resets the dialog without firing callbacks.

describe("DsarExportDialog", () => {
  beforeEach(() => {
    cleanup();
  });
  afterEach(() => {
    cleanup();
  });

  it("trigger button is disabled when hasActiveJob=true (AC31)", () => {
    const onConfirmPassword = vi.fn();
    const onConfirmOAuth = vi.fn();
    render(
      <DsarExportDialog
        onConfirmPassword={onConfirmPassword}
        onConfirmOAuth={onConfirmOAuth}
        hasActiveJob={true}
      />,
    );
    const btn = screen.getByRole("button", { name: /download my data/i });
    expect(btn).toBeDisabled();
  });

  it("trigger button is enabled when no active job", () => {
    render(
      <DsarExportDialog
        onConfirmPassword={vi.fn()}
        onConfirmOAuth={vi.fn()}
        hasActiveJob={false}
      />,
    );
    const btn = screen.getByRole("button", { name: /download my data/i });
    expect(btn).not.toBeDisabled();
  });

  it("opening the dialog reveals password input + <details> disclosure", () => {
    render(
      <DsarExportDialog
        onConfirmPassword={vi.fn()}
        onConfirmOAuth={vi.fn()}
        hasActiveJob={false}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));

    expect(
      screen.getByLabelText(/confirm your password/i),
    ).toBeInTheDocument();
    // <details> summary
    expect(screen.getByText(/what's included/i)).toBeInTheDocument();
    // The 6 included data classes (rough count via list items in summary).
    expect(screen.getByText(/your account profile/i)).toBeInTheDocument();
    expect(screen.getByText(/conversations.*messages/i)).toBeInTheDocument();
  });

  it("Continue calls onConfirmPassword with the typed password", async () => {
    const onConfirmPassword = vi.fn().mockResolvedValue(undefined);
    render(
      <DsarExportDialog
        onConfirmPassword={onConfirmPassword}
        onConfirmOAuth={vi.fn()}
        hasActiveJob={false}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));
    fireEvent.change(screen.getByLabelText(/confirm your password/i), {
      target: { value: "s3cret" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^continue$/i }));

    expect(onConfirmPassword).toHaveBeenCalledWith("s3cret");
  });

  it("Continue is disabled when password is empty", () => {
    render(
      <DsarExportDialog
        onConfirmPassword={vi.fn()}
        onConfirmOAuth={vi.fn()}
        hasActiveJob={false}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));
    const continueBtn = screen.getByRole("button", { name: /^continue$/i });
    expect(continueBtn).toBeDisabled();
  });

  it("shows error inline when onConfirmPassword rejects", async () => {
    const onConfirmPassword = vi
      .fn()
      .mockRejectedValue(new Error("password verification failed"));
    render(
      <DsarExportDialog
        onConfirmPassword={onConfirmPassword}
        onConfirmOAuth={vi.fn()}
        hasActiveJob={false}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));
    fireEvent.change(screen.getByLabelText(/confirm your password/i), {
      target: { value: "wrong" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^continue$/i }));

    // Wait a microtask for the promise to settle.
    await Promise.resolve();
    await Promise.resolve();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /password verification failed/i,
    );
  });

  it("Cancel closes the dialog and does not call any callback", () => {
    const onConfirmPassword = vi.fn();
    const onConfirmOAuth = vi.fn();
    render(
      <DsarExportDialog
        onConfirmPassword={onConfirmPassword}
        onConfirmOAuth={onConfirmOAuth}
        hasActiveJob={false}
      />,
    );
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    // Back to the trigger button.
    expect(
      screen.getByRole("button", { name: /download my data/i }),
    ).toBeInTheDocument();
    expect(onConfirmPassword).not.toHaveBeenCalled();
    expect(onConfirmOAuth).not.toHaveBeenCalled();
  });
});
