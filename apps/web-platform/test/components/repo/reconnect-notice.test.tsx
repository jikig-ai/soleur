import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks — control the shared reconnect hook so the notice can be tested in
// isolation (the hook itself is covered by use-reconnect.test.tsx).
// ---------------------------------------------------------------------------

const { mockReconnect, mockUseReconnect } = vi.hoisted(() => ({
  mockReconnect: vi.fn(),
  mockUseReconnect: vi.fn(),
}));

vi.mock("@/components/repo/use-reconnect", () => ({
  useReconnect: mockUseReconnect,
}));

import { ReconnectNotice } from "@/components/repo/reconnect-notice";

describe("ReconnectNotice", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUseReconnect.mockReturnValue({
      reconnect: mockReconnect,
      isPending: false,
    });
  });

  test.each(["card", "banner"] as const)(
    "renders the notice copy + Reconnect button for variant=%s",
    (variant) => {
      render(<ReconnectNotice variant={variant} onReconnected={vi.fn()} />);
      expect(screen.getByText(/can't sync/i)).toBeInTheDocument();
      expect(
        screen.getByRole("button", { name: /^reconnect$/i }),
      ).toBeInTheDocument();
    },
  );

  test("clicking Reconnect invokes the hook's reconnect()", () => {
    render(<ReconnectNotice variant="card" onReconnected={vi.fn()} />);
    screen.getByRole("button", { name: /^reconnect$/i }).click();
    expect(mockReconnect).toHaveBeenCalledTimes(1);
  });

  test("passes onReconnected through to useReconnect", () => {
    const onReconnected = vi.fn();
    render(<ReconnectNotice variant="card" onReconnected={onReconnected} />);
    expect(mockUseReconnect).toHaveBeenCalledWith(onReconnected);
  });

  test("disables the button and shows 'Reconnecting…' when pending", () => {
    mockUseReconnect.mockReturnValue({
      reconnect: mockReconnect,
      isPending: true,
    });
    render(<ReconnectNotice variant="banner" onReconnected={vi.fn()} />);
    const btn = screen.getByRole("button", { name: /reconnecting/i });
    expect(btn).toBeDisabled();
  });
});
