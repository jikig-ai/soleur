// PR-H (#4077) — Typed-confirm modal component tests.
//
// Asserts the load-bearing UX contract for the approve_every_time tier:
//   - Submit disabled until input value === "SEND" exact
//   - lowercase "send", "send " (trailing space), ZWS, empty → disabled
//   - No .trim() / .normalize() per Kieran P2-7 — server expects exact
//   - Esc closes WITHOUT triggering confirmation (no auto-discard)
//   - role="dialog" + aria-modal + aria-labelledby
//   - Submit calls onConfirm(true, "SEND")
//   - Cancel calls onCancel + does NOT call onConfirm

import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

import { TypedConfirmModal } from "@/components/ui/typed-confirm-modal";

function setup(open = true) {
  const onConfirm = vi.fn();
  const onCancel = vi.fn();
  const utils = render(
    <TypedConfirmModal
      open={open}
      recipientExcerpt="customer@example.com"
      contentExcerpt="Hi — your invoice for May renewed..."
      actionClassLabel="finance.payment_failed"
      tierLabel="Approve every time"
      onCancel={onCancel}
      onConfirm={onConfirm}
    />,
  );
  return { ...utils, onCancel, onConfirm };
}

describe("TypedConfirmModal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("does not render when open=false", () => {
    const { container, onConfirm, onCancel } = setup(false);
    expect(container.firstChild).toBeNull();
    expect(onConfirm).not.toHaveBeenCalled();
    expect(onCancel).not.toHaveBeenCalled();
  });

  it("has role=dialog + aria-modal + aria-labelledby", () => {
    setup();
    const dialog = screen.getByRole("dialog");
    expect(dialog).toBeInTheDocument();
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(dialog.getAttribute("aria-labelledby")).toBeTruthy();
  });

  it("renders recipient + content + action_class + tier labels", () => {
    setup();
    expect(screen.getByText("customer@example.com")).toBeInTheDocument();
    expect(
      screen.getByText(/Hi — your invoice for May renewed/),
    ).toBeInTheDocument();
    expect(
      screen.getByText(/Approve every time.*finance.payment_failed/),
    ).toBeInTheDocument();
  });

  it("submit disabled while input is empty", () => {
    setup();
    const submit = screen.getByTestId("typed-confirm-submit");
    expect(submit).toBeDisabled();
  });

  it("submit disabled for lowercase 'send' (no normalize per Kieran P2-7)", () => {
    setup();
    const input = screen.getByTestId("typed-confirm-input");
    fireEvent.change(input, { target: { value: "send" } });
    const submit = screen.getByTestId("typed-confirm-submit");
    expect(submit).toBeDisabled();
  });

  it("submit disabled for trailing-space 'SEND ' (no trim per Kieran P2-7)", () => {
    setup();
    const input = screen.getByTestId("typed-confirm-input");
    fireEvent.change(input, { target: { value: "SEND " } });
    expect(screen.getByTestId("typed-confirm-submit")).toBeDisabled();
  });

  it("submit disabled for ZWS-padded 'SEND\\u200b'", () => {
    setup();
    const input = screen.getByTestId("typed-confirm-input");
    fireEvent.change(input, { target: { value: "SEND​" } });
    expect(screen.getByTestId("typed-confirm-submit")).toBeDisabled();
  });

  it("submit enabled when input === 'SEND' exact; onConfirm called with (true, 'SEND')", () => {
    const { onConfirm } = setup();
    const input = screen.getByTestId("typed-confirm-input");
    fireEvent.change(input, { target: { value: "SEND" } });
    const submit = screen.getByTestId("typed-confirm-submit");
    expect(submit).not.toBeDisabled();
    fireEvent.click(submit);
    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(onConfirm).toHaveBeenCalledWith(true, "SEND");
  });

  it("Cancel button calls onCancel (NOT onConfirm)", () => {
    const { onCancel, onConfirm } = setup();
    fireEvent.click(screen.getByTestId("typed-confirm-cancel"));
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("Esc closes WITHOUT triggering confirmation", () => {
    const { onCancel, onConfirm } = setup();
    fireEvent.keyDown(window, { key: "Escape" });
    expect(onCancel).toHaveBeenCalledTimes(1);
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("submit + Enter on form does NOT bypass disabled gate", () => {
    const { onConfirm } = setup();
    const input = screen.getByTestId("typed-confirm-input");
    // Type lowercase first so canSubmit=false. Submitting the form via
    // the disabled submit button MUST NOT fire onConfirm. fireEvent on
    // a disabled <button> in jsdom still dispatches click; the handler
    // body must guard.
    fireEvent.change(input, { target: { value: "send" } });
    fireEvent.click(screen.getByTestId("typed-confirm-submit"));
    expect(onConfirm).not.toHaveBeenCalled();
  });

  it("input has autoCapitalize=off + autoCorrect=off (case-sensitive integrity)", () => {
    setup();
    const input = screen.getByTestId(
      "typed-confirm-input",
    ) as HTMLInputElement;
    expect(input.getAttribute("autocapitalize")).toBe("off");
    expect(input.getAttribute("autocorrect")).toBe("off");
  });
});
