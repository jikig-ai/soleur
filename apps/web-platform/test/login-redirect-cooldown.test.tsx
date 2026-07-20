import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";

const { pushMock, replaceMock, assignMock, searchParamsRef } = vi.hoisted(() => ({
  pushMock: vi.fn(),
  replaceMock: vi.fn(),
  // GAP E (ADR-067 staleTimes): OTP-verify success now HARD-navs via
  // window.location.assign instead of a soft router.push.
  assignMock: vi.fn(),
  searchParamsRef: { current: new URLSearchParams() },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: pushMock, replace: replaceMock, refresh: vi.fn() }),
  useSearchParams: () => searchParamsRef.current,
}));

const signInWithOtpMock = vi.fn();
const verifyOtpMock = vi.fn();

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      signInWithOtp: signInWithOtpMock,
      verifyOtp: verifyOtpMock,
      signInWithOAuth: vi.fn(),
    },
  }),
}));

import { LoginForm } from "@/components/auth/login-form";

const EMAIL = "member@example.com";

async function sendCode() {
  fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
    target: { value: EMAIL },
  });
  fireEvent.click(screen.getByRole("button", { name: /send sign-in code/i }));
  await waitFor(() =>
    expect(screen.getByText(/enter verification code/i)).toBeInTheDocument(),
  );
}

describe("LoginForm — redirectTo on verify (AC2)", () => {
  let originalLocation: Location;
  beforeEach(() => {
    vi.clearAllMocks();
    searchParamsRef.current = new URLSearchParams();
    signInWithOtpMock.mockResolvedValue({ error: null });
    verifyOtpMock.mockResolvedValue({ error: null });
    // Stub window.location for the GAP E hard nav (happy-dom's assign is not
    // spyable by default).
    originalLocation = window.location;
    Object.defineProperty(window, "location", {
      configurable: true,
      writable: true,
      value: { assign: assignMock, pathname: "/login" } as unknown as Location,
    });
  });

  afterEach(() => {
    Object.defineProperty(window, "location", {
      configurable: true,
      writable: true,
      value: originalLocation,
    });
  });

  async function verify() {
    fireEvent.change(screen.getByPlaceholderText("000000"), {
      target: { value: "123456" },
    });
    fireEvent.click(screen.getByRole("button", { name: /^sign in$/i }));
  }

  it("routes to the sanitized redirectTo (/invite/<token>) when present", async () => {
    searchParamsRef.current = new URLSearchParams("redirectTo=/invite/tok123");
    render(<LoginForm />);
    await sendCode();
    await verify();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/invite/tok123"));
  });

  it("routes to /dashboard (default) when redirectTo is absent", async () => {
    render(<LoginForm />);
    await sendCode();
    await verify();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
  });

  it("falls back to /dashboard when redirectTo is an open-redirect vector", async () => {
    searchParamsRef.current = new URLSearchParams("redirectTo=//evil.example");
    render(<LoginForm />);
    await sendCode();
    await verify();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/dashboard"));
    expect(assignMock).not.toHaveBeenCalledWith("//evil.example");
  });

  it("preserves redirectTo through the no-account login→signup bounce", async () => {
    searchParamsRef.current = new URLSearchParams("redirectTo=/invite/tok123");
    signInWithOtpMock.mockResolvedValueOnce({
      error: { message: "Signups not allowed for otp", code: "otp_disabled" },
    });
    render(<LoginForm />);
    fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
      target: { value: "newuser@example.com" },
    });
    fireEvent.click(screen.getByRole("button", { name: /send sign-in code/i }));
    await waitFor(() => expect(replaceMock).toHaveBeenCalled());
    const target = replaceMock.mock.calls[0][0] as string;
    expect(target).toContain("/signup?");
    expect(target).toContain("redirectTo=%2Finvite%2Ftok123");
    expect(target).toContain("reason=no_account");
  });
});

describe("LoginForm — resend cooldown (AC4, AC6)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    searchParamsRef.current = new URLSearchParams();
    signInWithOtpMock.mockResolvedValue({ error: null });
    verifyOtpMock.mockResolvedValue({ error: null });
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  async function sendCodeFake() {
    fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
      target: { value: EMAIL },
    });
    fireEvent.click(
      screen.getByRole("button", { name: /send sign-in code/i }),
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(150);
    });
  }

  it("disables resend with a countdown after a send, re-enables after the cooldown", async () => {
    render(<LoginForm />);
    await sendCodeFake();

    expect(
      screen.getByRole("button", { name: /request a new code/i }),
    ).toBeDisabled();
    expect(signInWithOtpMock).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(59_000);
    });
    expect(
      screen.getByRole("button", { name: /request a new code/i }),
    ).toBeDisabled();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1_000);
    });
    expect(
      screen.getByRole("button", { name: /resend code/i }),
    ).toBeEnabled();
  });

  it("shows distinct cooldown copy, never the rate-limit message (AC6)", async () => {
    render(<LoginForm />);
    await sendCodeFake();

    expect(
      screen.getByText(/you can request a new code in \d+s/i),
    ).toBeInTheDocument();
    expect(
      screen.queryByText(/too many sign-in attempts/i),
    ).not.toBeInTheDocument();
  });

  it("does not fire a second signInWithOtp while the cooldown is active", async () => {
    render(<LoginForm />);
    await sendCodeFake();

    fireEvent.click(
      screen.getByRole("button", { name: /request a new code/i }),
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(100);
    });
    expect(signInWithOtpMock).toHaveBeenCalledTimes(1);
  });

  it("still blocks the SAME email after 'Try a different email' (reset-bypass closed)", async () => {
    render(<LoginForm />);
    await sendCodeFake();

    // Go back to the email screen, keep the SAME email, try to re-send.
    fireEvent.click(screen.getByRole("button", { name: /try a different email/i }));
    const sendBtn = screen.getByRole("button", { name: /request a new code|send sign-in code/i });
    expect(sendBtn).toBeDisabled();
    fireEvent.click(sendBtn);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(100);
    });
    expect(signInWithOtpMock).toHaveBeenCalledTimes(1); // no second send
  });

  it("allows an immediate send to a DIFFERENT email during the cooldown", async () => {
    render(<LoginForm />);
    await sendCodeFake();

    fireEvent.click(screen.getByRole("button", { name: /try a different email/i }));
    fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
      target: { value: "different@example.com" },
    });
    const sendBtn = screen.getByRole("button", { name: /send sign-in code/i });
    expect(sendBtn).toBeEnabled();
    fireEvent.click(sendBtn);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(150);
    });
    expect(signInWithOtpMock).toHaveBeenCalledTimes(2); // different email → allowed
  });
});
