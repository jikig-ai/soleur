import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";

// Toggle the support flag per-test via a hoisted mutable.
const flagState = vi.hoisted(() => ({ support: false }));
vi.mock("@/components/feature-flags/provider", () => ({
  useOptionalFeatureFlag: (name: string) =>
    name === "support" ? flagState.support : false,
}));

import { SupportLauncher } from "@/components/support/support-launcher";

describe("SupportLauncher — flag gating", () => {
  beforeEach(() => {
    flagState.support = false;
  });
  afterEach(() => cleanup());

  it("renders nothing when the support flag is OFF", () => {
    const { container } = render(<SupportLauncher />);
    expect(screen.queryByLabelText("Open support")).toBeNull();
    expect(container).toBeEmptyDOMElement();
  });

  it("renders the floating bubble when the flag is ON", () => {
    flagState.support = true;
    render(<SupportLauncher />);
    expect(screen.getByLabelText("Open support")).toBeTruthy();
  });

  it("opens the panel on bubble click and hides the bubble while open", () => {
    flagState.support = true;
    render(<SupportLauncher />);
    fireEvent.click(screen.getByLabelText("Open support"));
    expect(screen.getByRole("dialog")).toBeTruthy();
    // Bubble hides while the panel is open (X is the close affordance).
    expect(screen.queryByLabelText("Open support")).toBeNull();
  });

  it("unmounts cleanly when the flag flips OFF mid-session", () => {
    flagState.support = true;
    const { rerender, container } = render(<SupportLauncher />);
    expect(screen.getByLabelText("Open support")).toBeTruthy();
    flagState.support = false;
    rerender(<SupportLauncher />);
    expect(container).toBeEmptyDOMElement();
  });
});
