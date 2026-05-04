import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signInWithOtp: vi.fn(),
      signInWithOAuth: vi.fn(),
      verifyOtp: vi.fn(),
    },
  }),
}));

import SignupPage from "@/app/(auth)/signup/page";

const HINT_COPY = "Accept the terms above to continue.";
const OAUTH_PROVIDERS = ["Google", "Apple", "GitHub", "Microsoft"] as const;

describe("SignupPage helper hint (T&C-gated OAuth)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the role=status hint at first render with the gating copy", () => {
    render(<SignupPage />);

    const hint = screen.getByTestId("tc-hint");
    expect(hint).toBeInTheDocument();
    expect(hint).toHaveAttribute("role", "status");
    expect(hint).toHaveAttribute("aria-live", "polite");
    expect(hint).toHaveTextContent(HINT_COPY);
  });

  it("empties the hint text when the T&C checkbox is ticked (live region persists)", () => {
    render(<SignupPage />);

    const hint = screen.getByTestId("tc-hint");
    expect(hint).toHaveTextContent(HINT_COPY);

    fireEvent.click(screen.getByRole("checkbox"));

    // Live-region pre-exists invariant: element stays in DOM, text empties.
    expect(screen.getByTestId("tc-hint")).toBeInTheDocument();
    expect(screen.getByTestId("tc-hint")).toHaveTextContent("");
  });

  it("keeps every OAuth provider button disabled before the checkbox is ticked", () => {
    render(<SignupPage />);

    for (const label of OAUTH_PROVIDERS) {
      const button = screen.getByRole("button", {
        name: new RegExp(`Continue with ${label}`, "i"),
      });
      expect(button).toBeDisabled();
    }
  });

  it("enables every OAuth provider button after the checkbox is ticked", () => {
    render(<SignupPage />);

    fireEvent.click(screen.getByRole("checkbox"));

    for (const label of OAUTH_PROVIDERS) {
      const button = screen.getByRole("button", {
        name: new RegExp(`Continue with ${label}`, "i"),
      });
      expect(button).not.toBeDisabled();
    }
  });
});
