import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { NewIssueDialog } from "@/components/workstream/new-issue-dialog";

afterEach(() => cleanup());

describe("NewIssueDialog", () => {
  it("submits the title (+ optional body) to onSubmit and closes on success (AC1)", async () => {
    const onSubmit = vi.fn().mockResolvedValue(undefined);
    const onClose = vi.fn();
    render(<NewIssueDialog open onClose={onClose} onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "Add export" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));

    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1));
    expect(onSubmit.mock.calls[0][0]).toEqual({ title: "Add export" });
    await waitFor(() => expect(onClose).toHaveBeenCalled());
  });

  it("does NOT fire two creates on a rapid double-submit (idempotency guard, AC8/AC9)", async () => {
    let resolve!: () => void;
    const onSubmit = vi.fn(
      () => new Promise<void>((r) => (resolve = r)),
    );
    render(<NewIssueDialog open onClose={vi.fn()} onSubmit={onSubmit} />);
    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "X" },
    });
    const btn = screen.getByRole("button", { name: /create issue/i });
    fireEvent.click(btn);
    fireEvent.click(btn); // second click while the first is in flight
    expect(onSubmit).toHaveBeenCalledTimes(1);
    // button is disabled while submitting
    expect((btn as HTMLButtonElement).disabled).toBe(true);
    resolve();
    await waitFor(() => expect(onSubmit).toHaveBeenCalledTimes(1));
  });

  it("blocks an empty/whitespace title client-side (AC9)", () => {
    const onSubmit = vi.fn();
    render(<NewIssueDialog open onClose={vi.fn()} onSubmit={onSubmit} />);
    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "   " },
    });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));
    expect(onSubmit).not.toHaveBeenCalled();
  });

  it("preserves the form + shows an inline retry when onSubmit rejects", async () => {
    const onSubmit = vi.fn().mockRejectedValue(new Error("boom"));
    const onClose = vi.fn();
    render(<NewIssueDialog open onClose={onClose} onSubmit={onSubmit} />);
    const input = screen.getByLabelText(/title/i) as HTMLInputElement;
    fireEvent.change(input, { target: { value: "Keep me" } });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));

    await waitFor(() => expect(screen.getByRole("alert")).toBeTruthy());
    expect(onClose).not.toHaveBeenCalled();
    expect(input.value).toBe("Keep me"); // values preserved for retry
  });

  it("keeps the offline 'Create with Concierge' field clearly disabled", () => {
    render(<NewIssueDialog open onClose={vi.fn()} onSubmit={vi.fn()} />);
    expect(
      screen.getAllByText("Create with Concierge").length,
    ).toBeGreaterThanOrEqual(2);
    expect(screen.getByText(/offline — coming soon/i)).toBeTruthy();
    const conciergeBtn = screen.getByRole("button", {
      name: "Create with Concierge",
    }) as HTMLButtonElement;
    expect(conciergeBtn.disabled).toBe(true);
  });
});
