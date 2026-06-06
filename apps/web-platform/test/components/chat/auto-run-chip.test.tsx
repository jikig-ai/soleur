import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

// feat-bash-autonomous-default-on — persistent posture chip. Reflects the
// server-resolved posture and deep-links to the relocated Scope-Grants toggle.

const { mockPush } = vi.hoisted(() => ({ mockPush: vi.fn() }));
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: mockPush }),
}));

import { AutoRunChip } from "@/components/chat/auto-run-chip";

describe("AutoRunChip", () => {
  beforeEach(() => vi.clearAllMocks());

  test("renders 'Auto-run on' when autonomous", () => {
    render(<AutoRunChip autonomous={true} />);
    expect(screen.getByText("Auto-run on")).toBeTruthy();
  });

  test("renders 'Approve each' when not autonomous", () => {
    render(<AutoRunChip autonomous={false} />);
    expect(screen.getByText("Approve each")).toBeTruthy();
  });

  test("click deep-links to the Scope-Grants concierge anchor", () => {
    render(<AutoRunChip autonomous={true} />);
    fireEvent.click(screen.getByRole("button"));
    expect(mockPush).toHaveBeenCalledWith(
      "/dashboard/settings/scope-grants#concierge-command-execution",
    );
  });

  test("uses sharp corners (rounded-none), not pill", () => {
    render(<AutoRunChip autonomous={true} />);
    const btn = screen.getByRole("button");
    expect(btn.className).toContain("rounded-none");
    expect(btn.className).not.toContain("rounded-full");
  });
});
