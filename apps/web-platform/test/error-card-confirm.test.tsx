import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ErrorCard } from "@/components/ui/error-card";

describe("ErrorCard confirmation action", () => {
  it("renders an explicit confirmation button and invokes its callback", () => {
    const onConfirm = vi.fn();
    render(
      <ErrorCard
        title="Codex account changed"
        message="Acknowledge before sending this conversation history to the selected account."
        confirmLabel="Acknowledge and continue"
        onConfirm={onConfirm}
      />,
    );

    fireEvent.click(screen.getByRole("button", { name: "Acknowledge and continue" }));
    expect(onConfirm).toHaveBeenCalledOnce();
  });
});
