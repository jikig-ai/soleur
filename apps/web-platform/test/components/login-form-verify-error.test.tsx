import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";

// Bug: ops@jikigai.com — a correct OTP code was rejected with the dead-end
// "Something went wrong" after a long wait. Root cause: the verify error path
// mapped only freetext message regexes, so a structured `over_request_rate_limit`
// / HTTP 429 (and any 5xx/transport) fell through to the generic message. The
// fix routes the structured error through `mapSupabaseAuthError`, which keys on
// `code`/`status` first. These tests assert the rendered alert shows recoverable
// copy — never "Something went wrong" — for both the resolved-error and the
// thrown-error (transport) paths.

const searchParamsHolder: { current: URLSearchParams } = {
  current: new URLSearchParams(),
};

vi.mock("next/navigation", () => ({
  useSearchParams: () => searchParamsHolder.current,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn() }),
}));

// Per-test handle so each test can supply its own verifyOtp behavior.
const authMock: {
  signInWithOtp: ReturnType<typeof vi.fn>;
  verifyOtp: ReturnType<typeof vi.fn>;
} = {
  signInWithOtp: vi.fn(),
  verifyOtp: vi.fn(),
};

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: authMock }),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

vi.mock("@/components/auth/oauth-buttons", () => ({
  OAuthButtons: () => null,
}));

import { LoginForm } from "@/components/auth/login-form";

const RATE_LIMIT_COPY = /too many attempts right now/i;
const GENERIC_COPY = /something went wrong/i;

async function advanceToVerifyScreen() {
  render(<LoginForm />);
  // Step 1: send the OTP (resolves with no error → verify screen renders).
  authMock.signInWithOtp.mockResolvedValue({ error: null });
  fireEvent.change(screen.getByPlaceholderText("you@example.com"), {
    target: { value: "ops@jikigai.com" },
  });
  fireEvent.click(screen.getByRole("button", { name: /send sign-in code/i }));

  // Step 2: the verify screen (otp input) appears.
  const otpInput = await screen.findByPlaceholderText("000000");
  fireEvent.change(otpInput, { target: { value: "997473" } });
  return otpInput;
}

describe("LoginForm verifyOtp error mapping", () => {
  beforeEach(() => {
    searchParamsHolder.current = new URLSearchParams();
    authMock.signInWithOtp = vi.fn();
    authMock.verifyOtp = vi.fn();
    reportSilentFallback.mockClear();
  });

  it("renders recoverable rate-limit copy (NOT 'Something went wrong') when verifyOtp REJECTS with a 429", async () => {
    await advanceToVerifyScreen();
    // Transport-style throw carrying the structured 429 shape.
    authMock.verifyOtp.mockRejectedValue({
      name: "AuthApiError",
      code: "over_request_rate_limit",
      status: 429,
      message: "Request rate limit reached",
    });

    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toMatch(RATE_LIMIT_COPY);
    expect(alert.textContent).not.toMatch(GENERIC_COPY);
  });

  it("renders recoverable rate-limit copy when verifyOtp RESOLVES with a 429 error", async () => {
    await advanceToVerifyScreen();
    authMock.verifyOtp.mockResolvedValue({
      error: {
        name: "AuthApiError",
        code: "over_request_rate_limit",
        status: 429,
        message: "Request rate limit reached",
      },
    });

    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toMatch(RATE_LIMIT_COPY);
    expect(alert.textContent).not.toMatch(GENERIC_COPY);
  });

  it("forwards status to Sentry but never the raw error.message (PII discipline)", async () => {
    await advanceToVerifyScreen();
    authMock.verifyOtp.mockResolvedValue({
      error: {
        name: "AuthApiError",
        code: "over_request_rate_limit",
        status: 429,
        message: "rate limited for ops@jikigai.com",
      },
    });

    fireEvent.click(screen.getByRole("button", { name: /sign in/i }));

    await waitFor(() => expect(reportSilentFallback).toHaveBeenCalled());
    const [, options] = reportSilentFallback.mock.calls[0] as [
      unknown,
      { extra?: Record<string, unknown> },
    ];
    expect(options.extra?.status).toBe(429);
    expect(options.extra).not.toHaveProperty("message");
  });
});
