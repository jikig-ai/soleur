import { afterEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { NewIssueDialog } from "@/components/workstream/new-issue-dialog";

afterEach(() => cleanup());

describe("NewIssueDialog", () => {
  it("creates an optimistic Backlog issue from the title (primary path unchanged)", () => {
    const onCreate = vi.fn();
    const onClose = vi.fn();
    render(<NewIssueDialog open onClose={onClose} onCreate={onCreate} />);

    fireEvent.change(screen.getByLabelText(/title/i), {
      target: { value: "Add export" },
    });
    fireEvent.click(screen.getByRole("button", { name: /create issue/i }));

    expect(onCreate).toHaveBeenCalledTimes(1);
    const created = onCreate.mock.calls[0][0];
    expect(created.title).toBe("Add export");
    expect(created.status).toBe("backlog");
    expect(onClose).toHaveBeenCalled();
  });

  it("shows a clearly-disabled, non-submittable 'Create with Concierge' field (offline)", () => {
    render(<NewIssueDialog open onClose={vi.fn()} onCreate={vi.fn()} />);

    // "Create with Concierge" appears twice (the legend + the disabled button).
    expect(
      screen.getAllByText("Create with Concierge").length,
    ).toBeGreaterThanOrEqual(2);
    expect(screen.getByText(/offline — coming soon/i)).toBeTruthy();

    const conciergeInput = screen.getByLabelText(
      /describe the issue for concierge/i,
    ) as HTMLTextAreaElement;
    expect(conciergeInput.disabled).toBe(true);

    const conciergeBtn = screen.getByRole("button", {
      name: "Create with Concierge",
    }) as HTMLButtonElement;
    expect(conciergeBtn.disabled).toBe(true);
  });
});
