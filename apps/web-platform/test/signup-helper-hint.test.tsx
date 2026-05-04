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

// The signup page also renders a separate role=status banner when the user
// arrives via /login redirect with `?reason=no-account`. The default test
// setup uses an empty URLSearchParams so that banner does NOT render — but
// the unique selector below uses data-testid for stability against a future
// refactor that adds another live region above the divider.
describe("SignupPage helper hint (T&C-gated OAuth)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("renders the live-region hint at first render with the gating copy", () => {
    render(<SignupPage />);

    const hint = screen.getByTestId("tc-hint");
    expect(hint).toBeInTheDocument();
    // No `role="status"` here on purpose: the /signup page already renders a
    // separate role=status banner ("No Soleur account found...") when the user
    // arrives via /login redirect. Two role=status regions would collide with
    // single-role locators in e2e (otp-login.e2e.ts uses page.getByRole("status")
    // expecting exactly one match). aria-live + aria-atomic preserves the
    // announce-as-whole semantics without the role-collision.
    expect(hint).not.toHaveAttribute("role", "status");
    expect(hint).toHaveAttribute("aria-live", "polite");
    expect(hint).toHaveAttribute("aria-atomic", "true");
    expect(hint).toHaveTextContent(HINT_COPY);
  });

  it("empties the hint text when the T&C checkbox is ticked (live region persists)", () => {
    render(<SignupPage />);

    const hint = screen.getByTestId("tc-hint");
    expect(hint).toHaveTextContent(HINT_COPY);

    fireEvent.click(screen.getByRole("checkbox"));

    // Live-region pre-exists invariant: element stays in DOM, text empties.
    const afterTick = screen.getByTestId("tc-hint");
    expect(afterTick).toBeInTheDocument();
    expect(afterTick).toHaveTextContent("");
    // aria-live MUST persist across the text swap so the announcement
    // pipeline keeps observing this region for future content changes.
    expect(afterTick).toHaveAttribute("aria-live", "polite");
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
    // Regression guard: the live region lives in the pre-OTP form branch
    // only. If a future refactor lifts the live region above the otpSent
    // conditional, the announce-on-mount bug returns. Drive the page into
    // the OTP step and assert the hint is gone.
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
