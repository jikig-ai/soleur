import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { useState } from "react";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import { DsarExportDialog } from "@/components/settings/dsar-export-dialog";

// Phase 8 UI tests for the DSAR confirmation dialog (rev after the
// post-merge-review fix that lifted `isOpen` to the parent so a
// Re-request CTA on an `expired` job row can open the same dialog —
// see PR #3634 user-impact-reviewer P1).
//
// Plan rev-2 FR1 + AC31. Verifies:
// - Trigger button is disabled when hasActiveJob=true (AC31).
// - Opening the dialog reveals password input + <details> disclosure.
// - Confirm calls onConfirmPassword with the typed password.
// - Cancel closes the dialog without firing callbacks.

// Test-only wrapper that owns `isOpen` so the click-to-open path
// exercises the controlled interface symmetrically with how the
// production parent (`DsarExportJobList`) wires it.
function Harness(props: {
  onConfirmPassword?: (p: string) => Promise<void>;
  hasActiveJob?: boolean;
  initialOpen?: boolean;
}) {
  const [isOpen, setIsOpen] = useState(props.initialOpen ?? false);
  return (
    <DsarExportDialog
      isOpen={isOpen}
      onOpen={() => setIsOpen(true)}
      onClose={() => setIsOpen(false)}
      onConfirmPassword={props.onConfirmPassword ?? (async () => {})}
      hasActiveJob={props.hasActiveJob ?? false}
    />
  );
}

describe("DsarExportDialog", () => {
  beforeEach(() => {
    cleanup();
  });
  afterEach(() => {
    cleanup();
  });

  it("trigger button is disabled when hasActiveJob=true (AC31)", () => {
    render(<Harness hasActiveJob={true} />);
    const btn = screen.getByRole("button", { name: /download my data/i });
    expect(btn).toBeDisabled();
  });

  it("trigger button is enabled when no active job", () => {
    render(<Harness hasActiveJob={false} />);
    const btn = screen.getByRole("button", { name: /download my data/i });
    expect(btn).not.toBeDisabled();
  });

  it("opening the dialog reveals password input + <details> disclosure", () => {
    render(<Harness />);
    fireEvent.click(screen.getByRole("button", { name: /download my data/i }));

    expect(
      screen.getByLabelText(/confirm your password/i),
    ).toBeInTheDocument();
    expect(screen.getByText(/what's included/i)).toBeInTheDocument();
    expect(screen.getByText(/your account profile/i)).toBeInTheDocument();
    expect(screen.getByText(/conversations.*messages/i)).toBeInTheDocument();
  });

  it("opens when parent passes isOpen={true} (AC24 re-request from expired row)", () => {
    // This is the Re-request flow: the job-list parent flips its own
    // dialogOpen state and passes isOpen=true on the next render. The
    // dialog should appear without the user clicking the trigger.
    render(<Harness initialOpen={true} />);
    expect(
      screen.getByLabelText(/confirm your password/i),
    ).toBeInTheDocument();
  });

  it("Continue calls onConfirmPassword with the typed password", async () => {
    const onConfirmPassword = vi.fn().mockResolvedValue(undefined);
    render(<Harness onConfirmPassword={onConfirmPassword} initialOpen={true} />);
    fireEvent.change(screen.getByLabelText(/confirm your password/i), {
      target: { value: "s3cret" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^continue$/i }));

    expect(onConfirmPassword).toHaveBeenCalledWith("s3cret");
  });

  it("Continue is disabled when password is empty", () => {
    render(<Harness initialOpen={true} />);
    const continueBtn = screen.getByRole("button", { name: /^continue$/i });
    expect(continueBtn).toBeDisabled();
  });

  it("shows error inline when onConfirmPassword rejects", async () => {
    const onConfirmPassword = vi
      .fn()
      .mockRejectedValue(new Error("password verification failed"));
    render(<Harness onConfirmPassword={onConfirmPassword} initialOpen={true} />);
    fireEvent.change(screen.getByLabelText(/confirm your password/i), {
      target: { value: "wrong" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^continue$/i }));

    await Promise.resolve();
    await Promise.resolve();

    expect(await screen.findByRole("alert")).toHaveTextContent(
      /password verification failed/i,
    );
  });

  it("Cancel closes the dialog and does not call any callback", () => {
    const onConfirmPassword = vi.fn();
    render(
      <Harness onConfirmPassword={onConfirmPassword} initialOpen={true} />,
    );
    fireEvent.click(screen.getByRole("button", { name: /cancel/i }));

    expect(
      screen.getByRole("button", { name: /download my data/i }),
    ).toBeInTheDocument();
    expect(onConfirmPassword).not.toHaveBeenCalled();
  });

  it("the email-fallback link points to legal@jikigai.com for SSO-only users", () => {
    render(<Harness initialOpen={true} />);
    const link = screen.getByRole("link", { name: /legal@jikigai\.com/i });
    expect(link).toHaveAttribute("href", "mailto:legal@jikigai.com");
  });
});
