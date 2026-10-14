import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

// #9053 — the canonical latch() site: onSubmit is the parent's
// fire-and-forget async handler whose success path unmounts this component,
// so `pending` must NOT release when asyncFn resolves — the unmount is the
// reset. These tests pin the latch-hold and the thrown-onSubmit release.

import { CreateProjectState } from "@/components/connect-repo/create-project-state";

describe("CreateProjectState — latch semantics (#9053)", () => {
  it("keeps the submit control pending after onSubmit resolves (latch held until unmount)", async () => {
    const onSubmit = vi.fn();
    render(<CreateProjectState onBack={vi.fn()} onSubmit={onSubmit} />);

    await userEvent.type(screen.getByLabelText(/project name/i), "my-app");
    await userEvent.click(screen.getByRole("button", { name: /create project/i }));

    expect(onSubmit).toHaveBeenCalledWith("my-app", true);
    // Resolved + latched → the button stays in the pending state; the only
    // release is the parent's unmounting setState.
    const btn = screen.getByRole("button", { name: /creating/i });
    await vi.waitFor(() => expect(btn).toBeDisabled());
  });

  it("a thrown onSubmit releases pending and surfaces the local error", async () => {
    const onSubmit = vi.fn(() => {
      throw new Error("boom");
    });
    render(<CreateProjectState onBack={vi.fn()} onSubmit={onSubmit} />);

    await userEvent.type(screen.getByLabelText(/project name/i), "my-app");
    await userEvent.click(screen.getByRole("button", { name: /create project/i }));

    await vi.waitFor(() => {
      expect(screen.getByRole("alert")).toHaveTextContent(/something went wrong/i);
    });
    await vi.waitFor(() => {
      expect(screen.getByRole("button", { name: /create project/i })).toBeEnabled();
    });
  });
});
