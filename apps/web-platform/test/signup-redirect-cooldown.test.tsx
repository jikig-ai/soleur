import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, waitFor, act } from "@testing-library/react";

const { pushMock, replaceMock, assignMock, searchParamsRef } = vi.hoisted(() => ({
  pushMock: vi.fn(),
  replaceMock: vi.fn(),
  // GAP E (ADR-067 staleTimes): signup verify-success now HARD-navs via
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

import SignupPage from "@/app/(auth)/signup/page";

const EMAIL = "invitee@example.com";

/** Drive the form from the email screen to the OTP-entry screen (one send). */
async function sendCode() {
  fireEvent.change(screen.getByPlaceholderText(/you@example.com/i), {
    target: { value: EMAIL },
  });
  fireEvent.click(screen.getByRole("checkbox"));
  fireEvent.click(screen.getByRole("button", { name: /send verification code/i }));
  await waitFor(() =>
    expect(screen.getByText(/enter verification code/i)).toBeInTheDocument(),
  );
}

describe("SignupPage — redirectTo on verify (AC1)", () => {
  let originalLocation: Location;
  beforeEach(() => {
    vi.clearAllMocks();
    searchParamsRef.current = new URLSearchParams();
    signInWithOtpMock.mockResolvedValue({ error: null });
    verifyOtpMock.mockResolvedValue({ error: null });
    originalLocation = window.location;
    Object.defineProperty(window, "location", {
      configurable: true,
      writable: true,
      value: { assign: assignMock, pathname: "/signup" } as unknown as Location,
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
    fireEvent.click(screen.getByRole("button", { name: /create account/i }));
  }

  it("routes THROUGH /accept-terms carrying redirectTo (T&C recorded before invite accept)", async () => {
    searchParamsRef.current = new URLSearchParams("redirectTo=/invite/tok123");
    render(<SignupPage />);
    await sendCode();
    await verify();
    // A fresh signup has no server-recorded T&C, and /invite is a PUBLIC_PATH
    // (middleware does not interpose /accept-terms), so signup must route
    // through /accept-terms — never straight to /invite — to avoid a T&C bypass.
    await waitFor(() =>
      expect(assignMock).toHaveBeenCalledWith(
        `/accept-terms?redirectTo=${encodeURIComponent("/invite/tok123")}`,
      ),
    );
    expect(assignMock).not.toHaveBeenCalledWith("/invite/tok123");
  });

  it("routes to /accept-terms (no redirectTo) when absent", async () => {
    render(<SignupPage />);
    await sendCode();
    await verify();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/accept-terms"));
  });

  it("routes to bare /accept-terms when redirectTo is an open-redirect vector", async () => {
    searchParamsRef.current = new URLSearchParams(
      "redirectTo=https://evil.example",
    );
    render(<SignupPage />);
    await sendCode();
    await verify();
    await waitFor(() => expect(assignMock).toHaveBeenCalledWith("/accept-terms"));
    expect(assignMock).not.toHaveBeenCalledWith("https://evil.example");
  });
});

describe("SignupPage — resend cooldown (AC5, AC6)", () => {
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
    fireEvent.click(screen.getByRole("checkbox"));
    fireEvent.click(
      screen.getByRole("button", { name: /send verification code/i }),
    );
    await act(async () => {
      await vi.advanceTimersByTimeAsync(150);
    });
  }

  it("disables resend with a countdown after a send, re-enables after the cooldown", async () => {
    render(<SignupPage />);
    await sendCodeFake();

    const resend = screen.getByRole("button", { name: /request a new code/i });
    expect(resend).toBeDisabled();
    expect(signInWithOtpMock).toHaveBeenCalledTimes(1);

    // Still cooling down near the end of the window.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(59_000);
    });
    expect(
      screen.getByRole("button", { name: /request a new code/i }),
    ).toBeDisabled();

    // After the full cooldown the control is enabled and relabeled.
    await act(async () => {
      await vi.advanceTimersByTimeAsync(1_000);
    });
    const ready = screen.getByRole("button", { name: /resend code/i });
    expect(ready).toBeEnabled();
  });

  it("shows distinct cooldown copy, never the rate-limit message (AC6)", async () => {
    render(<SignupPage />);
    await sendCodeFake();

    expect(
      screen.getByText(/you can request a new code in \d+s/i),
    ).toBeInTheDocument();
    expect(
      screen.queryByText(/too many sign-in attempts/i),
    ).not.toBeInTheDocument();
  });

  it("does not fire a second signInWithOtp while the cooldown is active", async () => {
    render(<SignupPage />);
    await sendCodeFake();

    const resend = screen.getByRole("button", { name: /request a new code/i });
    fireEvent.click(resend);
    await act(async () => {
      await vi.advanceTimersByTimeAsync(100);
    });
    expect(signInWithOtpMock).toHaveBeenCalledTimes(1);
  });
});
