"use client";

import { useState, useEffect, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { safeReturnTo } from "@/lib/safe-return-to";
import { EMAIL_OTP_LENGTH, OTP_RESEND_COOLDOWN_MS } from "@/lib/auth/constants";
import {
  CALLBACK_ERRORS,
  DEFAULT_ERROR_MESSAGE,
  isNoAccountError,
  mapSupabaseError,
  SIGNUP_REASON_NO_ACCOUNT,
} from "@/lib/auth/error-messages";
import Link from "next/link";

export function LoginForm() {
  const searchParams = useSearchParams();
  const router = useRouter();
  // Validated same-origin relative path to land on after sign-in (e.g.
  // /invite/<token> from the workspace invite flow); null when absent or
  // rejected, in which case we fall back to /dashboard.
  const redirectTo = safeReturnTo(searchParams.get("redirectTo"));
  const [email, setEmail] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [cooldownSeconds, setCooldownSeconds] = useState(0);
  // The email the active cooldown was started for. The cooldown is per-email
  // (GoTrue's rate window is per-user), so switching to a DIFFERENT email is
  // immediately sendable, while reverting to the same email inside the window
  // stays blocked — closing the "Try a different email" reset bypass.
  const [cooldownEmail, setCooldownEmail] = useState("");
  const otpRef = useRef<HTMLInputElement>(null);
  const cooldownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // True only while a cooldown is running AND the current email matches the
  // one it was started for.
  const cooldownActive = cooldownSeconds > 0 && email === cooldownEmail;

  function clearCooldown() {
    if (cooldownTimerRef.current) {
      clearInterval(cooldownTimerRef.current);
      cooldownTimerRef.current = null;
    }
  }

  // Disable resend for >= GoTrue's 60s per-user OTP window so the UI cannot
  // fire a same-email re-send before GoTrue will accept it (the double-send
  // that returns "Too many sign-in attempts").
  function startCooldown() {
    clearCooldown();
    setCooldownEmail(email);
    setCooldownSeconds(Math.ceil(OTP_RESEND_COOLDOWN_MS / 1000));
    cooldownTimerRef.current = setInterval(() => {
      setCooldownSeconds((s) => {
        if (s <= 1) {
          clearCooldown();
          return 0;
        }
        return s - 1;
      });
    }, 1000);
  }

  // Clear the interval on unmount so the countdown can't tick into an
  // unmounted component.
  useEffect(() => {
    return () => {
      if (cooldownTimerRef.current) clearInterval(cooldownTimerRef.current);
    };
  }, []);

  useEffect(() => {
    const callbackError = searchParams.get("error");
    if (callbackError) {
      setError(
        CALLBACK_ERRORS[callbackError] ?? DEFAULT_ERROR_MESSAGE,
      );
    }
  }, [searchParams]);

  // #4307 revocation banner. Middleware redirects revoked sessions to
  // /login?revoked=removed|role-changed and clears the auth cookies.
  // Render a banner above the form so the user knows why they were
  // signed out. Unknown values render no banner (defensive default).
  const revokedReason = searchParams.get("revoked");
  const revokedBanner =
    revokedReason === "removed"
      ? "A workspace owner removed you. Sign in below to continue with your other workspaces."
      : revokedReason === "role-changed"
        ? "Your role was updated. Sign in again to apply the new permissions."
        : revokedReason === "ownership-transferred"
          ? "You transferred ownership of this workspace. Sign in again to continue as a member."
          : revokedReason === "session-error"
            ? "Your session ended unexpectedly. Please sign in again."
            : null;

  /** Send (or resend) an OTP for the current email. Returns true on success. */
  async function sendOtp(): Promise<boolean> {
    // Source-level guard: refuse a same-email re-send inside the cooldown
    // window regardless of which control invoked us (send button, resend, or
    // a re-submit after "Try a different email" with the email unchanged).
    if (cooldownActive) return false;
    setLoading(true);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false },
    });

    setLoading(false);

    if (error) {
      console.error("[auth] Supabase error:", error.message);
      // Forward only typed enum fields — error.message embeds the email on
      // OTP failures and Sentry is a shared project (PII / cross-tenant risk).
      reportSilentFallback(error, {
        feature: "auth",
        op: "signInWithOtp",
        extra: {
          errorCode: (error as { code?: string }).code,
          errorName: error.name,
        },
      });
      if (isNoAccountError(error as { code?: string; message: string })) {
        const params = new URLSearchParams({
          email,
          reason: SIGNUP_REASON_NO_ACCOUNT,
        });
        // Preserve the invite target through the login→signup bounce so a
        // no-account invitee still lands on /invite/<token> after creating.
        if (redirectTo) params.set("redirectTo", redirectTo);
        router.replace(`/signup?${params.toString()}`);
        return false;
      }
      setError(mapSupabaseError(error.message));
      return false;
    }

    startCooldown();
    return true;
  }

  async function handleSendOtp(e: React.FormEvent) {
    e.preventDefault();
    const ok = await sendOtp();
    if (ok) {
      setOtpSent(true);
      setTimeout(() => otpRef.current?.focus(), 100);
    }
  }

  async function handleResendOtp() {
    await sendOtp();
  }

  async function handleVerifyOtp(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.verifyOtp({
      email,
      token: otp,
      type: "email",
    });

    setLoading(false);

    if (error) {
      console.error("[auth] Supabase error:", error.message);
      reportSilentFallback(error, {
        feature: "auth",
        op: "verifyOtp",
        extra: {
          errorCode: (error as { code?: string }).code,
          errorName: error.name,
        },
      });
      setError(mapSupabaseError(error.message));
    } else {
      router.push(redirectTo ?? "/dashboard");
    }
  }

  if (otpSent) {
    return (
      <main className="flex min-h-screen items-center justify-center p-4">
        <div className="w-full max-w-sm space-y-6">
          <div className="space-y-2 text-center">
            <h1 className="text-2xl font-semibold">Enter verification code</h1>
            <p className="text-sm text-soleur-text-secondary">
              We sent a {EMAIL_OTP_LENGTH}-digit code to{" "}
              <strong className="text-soleur-text-primary">{email}</strong>
            </p>
          </div>

          <form onSubmit={handleVerifyOtp} className="space-y-4">
            <input
              ref={otpRef}
              type="text"
              inputMode="numeric"
              autoComplete="one-time-code"
              required
              maxLength={EMAIL_OTP_LENGTH}
              value={otp}
              onChange={(e) => setOtp(e.target.value.replace(/\D/g, ""))}
              placeholder="000000"
              className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-center text-lg tracking-[0.3em] placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none"
            />

            {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

            <button
              type="submit"
              disabled={loading || otp.length !== EMAIL_OTP_LENGTH}
              className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-3 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 disabled:opacity-50"
            >
              {loading ? "Verifying..." : "Sign in"}
            </button>
          </form>

          <button
            type="button"
            onClick={handleResendOtp}
            disabled={loading || cooldownActive}
            className="block w-full text-center text-sm text-soleur-text-muted hover:text-soleur-text-secondary disabled:opacity-50 disabled:hover:text-soleur-text-muted"
          >
            {cooldownActive
              ? `You can request a new code in ${cooldownSeconds}s`
              : "Resend code"}
          </button>

          <button
            onClick={() => {
              setOtpSent(false);
              setOtp("");
              setError("");
            }}
            className="block w-full text-center text-sm text-soleur-text-muted hover:text-soleur-text-secondary"
          >
            Try a different email
          </button>
        </div>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-2xl font-semibold">Sign in to Soleur</h1>
          <p className="text-sm text-soleur-text-secondary">
            Enter your email to receive a sign-in code
          </p>
        </div>

        {revokedBanner && (
          <div
            role="status"
            data-testid="revoked-banner"
            className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-sm text-soleur-text-secondary"
          >
            {revokedBanner}
          </div>
        )}

        <form onSubmit={handleSendOtp} className="space-y-4">
          <input
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-sm placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none"
          />

          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

          <button
            type="submit"
            disabled={loading || cooldownActive}
            className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-3 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 disabled:opacity-50"
          >
            {cooldownActive
              ? `You can request a new code in ${cooldownSeconds}s`
              : loading
                ? "Sending..."
                : "Send sign-in code"}
          </button>
        </form>

        <div className="relative flex items-center gap-4">
          <div className="flex-1 border-t border-soleur-border-default" />
          <span className="text-xs text-soleur-text-muted">or</span>
          <div className="flex-1 border-t border-soleur-border-default" />
        </div>

        <OAuthButtons />

        <p className="text-center text-sm text-soleur-text-muted">
          Don&apos;t have an account?{" "}
          <Link href="/signup" className="text-soleur-text-primary hover:underline">
            Sign up
          </Link>
        </p>
      </div>
    </main>
  );
}
