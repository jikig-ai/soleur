"use client";

import { useState, useEffect } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { OtpCodeStep } from "@/components/auth/OtpCodeStep";
import { safeReturnTo } from "@/lib/safe-return-to";
import { useOtpFlow } from "@/lib/auth/useOtpFlow";
import {
  type AuthErrorLike,
  CALLBACK_ERRORS,
  DEFAULT_ERROR_MESSAGE,
  isNoAccountError,
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

  // login's send-error branch: a no-account error bounces login → signup,
  // preserving the validated invite target through the hop. Returning true
  // short-circuits the hook's default `setError(...)`.
  function redirectIfNoAccount(error: AuthErrorLike): boolean {
    if (isNoAccountError({ code: error.code, message: error.message ?? "" })) {
      const params = new URLSearchParams({
        email,
        reason: SIGNUP_REASON_NO_ACCOUNT,
      });
      // Preserve the invite target through the login→signup bounce so a
      // no-account invitee still lands on /invite/<token> after creating.
      if (redirectTo) params.set("redirectTo", redirectTo);
      router.replace(`/signup?${params.toString()}`);
      return true;
    }
    return false;
  }

  const {
    email,
    setEmail,
    otpSent,
    setOtpSent,
    otp,
    setOtp,
    error,
    setError,
    loading,
    cooldownSeconds,
    cooldownActive,
    otpRef,
    handleSendOtp,
    handleResendOtp,
    handleVerifyOtp,
  } = useOtpFlow({
    shouldCreateUser: false,
    // GAP E (ADR-067 staleTimes amendment): the default OTP sign-in verifies
    // client-side, so success is a principal-ENTRY into an authenticated
    // context. HARD-navigate (not a soft router.push) so the App Router Router
    // Cache is wiped — otherwise a prior user's warm RSC shell on this device
    // could be served to the freshly-signed-in principal (middleware does not
    // re-run on a cache hit). `redirectTo` is already `safeReturnTo`-sanitized
    // (:24), so assign() is open-redirect-safe.
    onVerifySuccess: () => window.location.assign(redirectTo ?? "/dashboard"),
    onSendError: redirectIfNoAccount,
  });

  useEffect(() => {
    const callbackError = searchParams.get("error");
    if (callbackError) {
      setError(
        CALLBACK_ERRORS[callbackError] ?? DEFAULT_ERROR_MESSAGE,
      );
    }
  }, [searchParams, setError]);

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

  if (otpSent) {
    return (
      <OtpCodeStep
        email={email}
        otp={otp}
        setOtp={setOtp}
        error={error}
        loading={loading}
        cooldownActive={cooldownActive}
        cooldownSeconds={cooldownSeconds}
        otpRef={otpRef}
        onVerify={handleVerifyOtp}
        onResend={handleResendOtp}
        onTryDifferentEmail={() => {
          setOtpSent(false);
          setOtp("");
          setError("");
        }}
        submitLabel="Sign in"
      />
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
            autoComplete="email"
            inputMode="email"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-base placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none md:text-sm"
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
