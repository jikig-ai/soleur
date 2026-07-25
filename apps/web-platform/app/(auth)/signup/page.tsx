"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { useState } from "react";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { OtpCodeStep } from "@/components/auth/OtpCodeStep";
import { safeReturnTo } from "@/lib/safe-return-to";
import { useOtpFlow } from "@/lib/auth/useOtpFlow";
import { SIGNUP_REASON_NO_ACCOUNT } from "@/lib/auth/error-messages";
import Link from "next/link";

export default function SignupPage() {
  return (
    <Suspense>
      <SignupForm />
    </Suspense>
  );
}

function SignupForm() {
  const searchParams = useSearchParams();
  const initialEmail = searchParams.get("email") ?? "";
  const reason = searchParams.get("reason");
  // Validated same-origin relative path to land on after the account is
  // created (e.g. /invite/<token> from the workspace invite flow); null when
  // absent or rejected, in which case we fall back to /accept-terms.
  const redirectTo = safeReturnTo(searchParams.get("redirectTo"));
  const [tcAccepted, setTcAccepted] = useState(false);

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
    shouldCreateUser: true,
    initialEmail,
    // A freshly-created account has NOT recorded T&C acceptance server-side
    // yet, and /invite/<token> is a PUBLIC_PATH (lib/routes.ts) so middleware
    // does NOT interpose /accept-terms there. Routing straight to /invite
    // would let the user accept an invitation before T&C is recorded. So we
    // always route through /accept-terms (which records T&C) and thread the
    // validated redirectTo through it — accept-terms honors it as the
    // terminal hop once T&C + key are satisfied. This preserves the invite
    // target without bypassing the T&C gate.
    // GAP E (ADR-067 staleTimes): account creation is a principal-ENTRY into an
    // authenticated funnel — hard-nav so every funnel exit uniformly wipes the
    // App Router Router Cache (redirectTo is safeReturnTo-sanitized above).
    onVerifySuccess: () =>
      window.location.assign(
        redirectTo
          ? `/accept-terms?redirectTo=${encodeURIComponent(redirectTo)}`
          : "/accept-terms",
      ),
  });

  const showNoAccountBanner =
    reason === SIGNUP_REASON_NO_ACCOUNT &&
    initialEmail.length > 0 &&
    email === initialEmail;

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
        submitLabel="Create account"
      />
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-2xl font-semibold">Create your account</h1>
          <p className="text-sm text-soleur-text-secondary">
            Get started with Soleur — your AI organization
          </p>
        </div>

        {showNoAccountBanner && (
          <div
            role="status"
            className="rounded-lg border border-blue-900/50 bg-blue-950/30 px-4 py-3 text-sm text-blue-200"
          >
            No Soleur account found for <strong>{email}</strong>. Create one below.
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

          <label className="flex items-start gap-3 text-sm text-soleur-text-secondary">
            <input
              type="checkbox"
              required
              checked={tcAccepted}
              onChange={(e) => setTcAccepted(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-soleur-border-default bg-soleur-bg-surface-1"
            />
            <span>
              I agree to the{" "}
              <a
                href="https://soleur.ai/pages/legal/terms-and-conditions.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-soleur-text-primary underline hover:text-soleur-text-secondary"
              >
                Terms &amp; Conditions
              </a>{" "}
              and{" "}
              <a
                href="https://soleur.ai/pages/legal/privacy-policy.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-soleur-text-primary underline hover:text-soleur-text-secondary"
              >
                Privacy Policy
              </a>
            </span>
          </label>

          <button
            type="submit"
            disabled={loading || !tcAccepted || cooldownActive}
            className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-3 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 disabled:opacity-50"
          >
            {cooldownActive
              ? `You can request a new code in ${cooldownSeconds}s`
              : loading
                ? "Sending..."
                : "Send verification code"}
          </button>
        </form>

        <div className="relative flex items-center gap-4">
          <div className="flex-1 border-t border-soleur-border-default" />
          <span className="text-xs text-soleur-text-muted">or</span>
          <div className="flex-1 border-t border-soleur-border-default" />
        </div>

        {/*
          Hint is rendered only while the gating checkbox is unchecked.
          - Sighted users: text is read in normal page flow on initial render
            (checkbox is unchecked at mount, so the hint is present).
          - Screen-reader users: the hint sits in the document at first paint
            and is read in flow; the checkbox itself announces its toggled
            state, which is the load-bearing signal for the disabled OAuth
            buttons. Conditional render avoids the visual "ghost" gap that
            a persistent empty live-region with min-h reservation creates
            once the user accepts the terms.
        */}
        {!tcAccepted && (
          <p
            data-testid="tc-hint"
            className="text-center text-xs text-soleur-text-muted"
          >
            Accept the terms above to continue.
          </p>
        )}

        <OAuthButtons disabled={!tcAccepted} />

        <p className="text-center text-sm text-soleur-text-muted">
          Already have an account?{" "}
          <Link href="/login" className="text-soleur-text-primary hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </main>
  );
}
