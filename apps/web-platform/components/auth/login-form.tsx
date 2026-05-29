"use client";

import { useState, useEffect, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { EMAIL_OTP_LENGTH } from "@/lib/auth/constants";
import {
  type AuthErrorLike,
  CALLBACK_ERRORS,
  DEFAULT_ERROR_MESSAGE,
  isNoAccountError,
  mapSupabaseAuthError,
  SIGNUP_REASON_NO_ACCOUNT,
} from "@/lib/auth/error-messages";
import Link from "next/link";

export function LoginForm() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const otpRef = useRef<HTMLInputElement>(null);

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

  async function handleSendOtp(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const supabase = createClient();
    let error: AuthErrorLike | null = null;
    try {
      ({ error } = await supabase.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false },
      }));
    } catch (thrown) {
      // Transport failure (fetch reject) rejects rather than resolving `error`.
      error = thrown as AuthErrorLike;
    }

    setLoading(false);

    if (error) {
      console.error("[auth] Supabase error:", error.message);
      // Forward only typed enum/int fields in `extra` — error.message embeds
      // the email on OTP failures and Sentry is a shared cross-tenant project.
      // The raw error is still captured via Sentry.captureException, so the
      // message-borne email is scrubbed by sentry.client.config beforeSend
      // (EMAIL_PATTERN), not omitted here.
      reportSilentFallback(error, {
        feature: "auth",
        op: "signInWithOtp",
        extra: {
          errorCode: error.code,
          errorName: error.name,
          status: error.status,
        },
      });
      if (isNoAccountError({ code: error.code, message: error.message ?? "" })) {
        const params = new URLSearchParams({
          email,
          reason: SIGNUP_REASON_NO_ACCOUNT,
        });
        router.replace(`/signup?${params.toString()}`);
        return;
      }
      setError(mapSupabaseAuthError(error));
    } else {
      setOtpSent(true);
      setTimeout(() => otpRef.current?.focus(), 100);
    }
  }

  async function handleVerifyOtp(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const supabase = createClient();
    let error: AuthErrorLike | null = null;
    try {
      ({ error } = await supabase.auth.verifyOtp({
        email,
        token: otp,
        type: "email",
      }));
    } catch (thrown) {
      // verifyOtp can reject (not resolve with `error`) on a transport failure;
      // route the thrown error through the same mapping layer.
      error = thrown as AuthErrorLike;
    }

    setLoading(false);

    if (error) {
      console.error("[auth] Supabase error:", error.message);
      reportSilentFallback(error, {
        feature: "auth",
        op: "verifyOtp",
        extra: {
          errorCode: error.code,
          errorName: error.name,
          status: error.status,
        },
      });
      setError(mapSupabaseAuthError(error));
    } else {
      router.push("/dashboard");
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
            disabled={loading}
            className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-3 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 disabled:opacity-50"
          >
            {loading ? "Sending..." : "Send sign-in code"}
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
