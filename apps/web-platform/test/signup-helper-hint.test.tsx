import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

const signInWithOtpMock = vi.fn();

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signInWithOtp: signInWithOtpMock,
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

  it("renders the gating-copy hint while the checkbox is unchecked", () => {
    render(<SignupPage />);

    const hint = screen.getByTestId("tc-hint");
    expect(hint).toBeInTheDocument();
    expect(hint).toHaveTextContent(HINT_COPY);
  });

  it("removes the hint from the DOM when the T&C checkbox is ticked", () => {
    render(<SignupPage />);

    expect(screen.getByTestId("tc-hint")).toHaveTextContent(HINT_COPY);

    fireEvent.click(screen.getByRole("checkbox"));

    // Conditional render: the hint is fully unmounted post-tick so the
    // parent's space-y stacking collapses cleanly between the "or" divider
    // and the OAuth buttons. A persistent empty live-region with min-h
    // reservation produced a visible ~64px ghost gap (see PR #3199 follow-up).
    expect(screen.queryByTestId("tc-hint")).not.toBeInTheDocument();
  });

  it("re-renders the hint when the user un-ticks the checkbox", () => {
    render(<SignupPage />);

    const checkbox = screen.getByRole("checkbox");
    fireEvent.click(checkbox);
    expect(screen.queryByTestId("tc-hint")).not.toBeInTheDocument();

    fireEvent.click(checkbox);
    expect(screen.getByTestId("tc-hint")).toHaveTextContent(HINT_COPY);
  });

  it("keeps every OAuth provider button disabled before the checkbox is ticked", () => {
    render(<SignupPage />);

    for (const label of OAUTH_PROVIDERS) {
      const button = screen.getByRole("button", {
        name: new RegExp(`Continue with ${label}`, "i"),
      });
      // Include the provider label in the failure message so a regression
      // pinpoints which provider broke without re-running.
      expect(button, `OAuth provider ${label} should be disabled pre-tick`).toBeDisabled();
    }
  });

  it("enables every OAuth provider button after the checkbox is ticked", () => {
    render(<SignupPage />);

    fireEvent.click(screen.getByRole("checkbox"));

    for (const label of OAUTH_PROVIDERS) {
      const button = screen.getByRole("button", {
        name: new RegExp(`Continue with ${label}`, "i"),
      });
      expect(button, `OAuth provider ${label} should be enabled post-tick`).not.toBeDisabled();
    }
  });

  it("does NOT render the hint in the OTP-sent step (form has unmounted)", async () => {
    // Regression guard: the hint lives in the pre-OTP form branch only.
    // If a future refactor lifts the conditional above the otpSent branch,
    // the empty-DOM contract for the OTP step would silently break.
    signInWithOtpMock.mockResolvedValueOnce({ error: null });
    render(<SignupPage />);

    fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
      target: { value: "test@example.com" },
    });
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(screen.getByRole("button", { name: /send verification code/i }));

    await waitFor(() => {
      expect(screen.queryByText(/enter verification code/i)).toBeInTheDocument();
    });
    expect(screen.queryByTestId("tc-hint")).not.toBeInTheDocument();
  });
});
