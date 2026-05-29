"use client";

import { Suspense, useState, useRef, useEffect } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { safeReturnTo } from "@/lib/safe-return-to";
import { EMAIL_OTP_LENGTH, OTP_RESEND_COOLDOWN_MS } from "@/lib/auth/constants";
import {
  mapSupabaseError,
  SIGNUP_REASON_NO_ACCOUNT,
} from "@/lib/auth/error-messages";
import Link from "next/link";

export default function SignupPage() {
  return (
    <Suspense>
      <SignupForm />
    </Suspense>
  );
}

function SignupForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const initialEmail = searchParams.get("email") ?? "";
  const reason = searchParams.get("reason");
  // Validated same-origin relative path to land on after the account is
  // created (e.g. /invite/<token> from the workspace invite flow); null when
  // absent or rejected, in which case we fall back to /accept-terms.
  const redirectTo = safeReturnTo(searchParams.get("redirectTo"));
  const [email, setEmail] = useState(initialEmail);
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [tcAccepted, setTcAccepted] = useState(false);
  const [cooldownSeconds, setCooldownSeconds] = useState(0);
  // The email the active cooldown was started for — the cooldown is per-email
  // (see login-form.tsx for the rationale; closes the "Try a different email"
  // reset bypass).
  const [cooldownEmail, setCooldownEmail] = useState("");
  const otpRef = useRef<HTMLInputElement>(null);
  const cooldownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

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

  useEffect(() => {
    return () => {
      if (cooldownTimerRef.current) clearInterval(cooldownTimerRef.current);
    };
  }, []);

  const showNoAccountBanner =
    reason === SIGNUP_REASON_NO_ACCOUNT &&
    initialEmail.length > 0 &&
    email === initialEmail;

  /** Send (or resend) an OTP for the current email. Returns true on success. */
  async function sendOtp(): Promise<boolean> {
    // Source-level guard: refuse a same-email re-send inside the cooldown.
    if (cooldownActive) return false;
    setLoading(true);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({ email });

    setLoading(false);

    if (error) {
      console.error("[auth] Supabase error:", error.message);
      reportSilentFallback(error, {
        feature: "auth",
        op: "signInWithOtp",
        extra: {
          errorCode: (error as { code?: string }).code,
          errorName: error.name,
        },
      });
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
      // A freshly-created account has NOT recorded T&C acceptance server-side
      // yet, and /invite/<token> is a PUBLIC_PATH (lib/routes.ts) so middleware
      // does NOT interpose /accept-terms there. Routing straight to /invite
      // would let the user accept an invitation before T&C is recorded. So we
      // always route through /accept-terms (which records T&C) and thread the
      // validated redirectTo through it — accept-terms honors it as the
      // terminal hop once T&C + key are satisfied. This preserves the invite
      // target without bypassing the T&C gate.
      router.push(
        redirectTo
          ? `/accept-terms?redirectTo=${encodeURIComponent(redirectTo)}`
          : "/accept-terms",
      );
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
              {loading ? "Verifying..." : "Create account"}
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
            className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-3 text-sm placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none"
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
