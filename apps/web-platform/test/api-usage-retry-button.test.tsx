import { describe, test, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

const { mockRefresh } = vi.hoisted(() => ({ mockRefresh: vi.fn() }));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: mockRefresh, push: vi.fn() }),
}));

import { ApiUsageRetryButton } from "@/components/settings/api-usage-retry-button";

describe("ApiUsageRetryButton", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("renders a button labeled 'Retry'", () => {
    render(<ApiUsageRetryButton />);
    expect(screen.getByRole("button", { name: /Retry/i })).toBeInTheDocument();
  });

  test("calls router.refresh() on click", () => {
    render(<ApiUsageRetryButton />);
    fireEvent.click(screen.getByRole("button", { name: /Retry/i }));
    expect(mockRefresh).toHaveBeenCalledTimes(1);
  });
});
