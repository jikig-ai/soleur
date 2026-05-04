"use client";

import { Suspense, useState, useRef } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { EMAIL_OTP_LENGTH } from "@/lib/auth/constants";
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
  const [email, setEmail] = useState(initialEmail);
  const [otpSent, setOtpSent] = useState(false);
  const [otp, setOtp] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [tcAccepted, setTcAccepted] = useState(false);
  const otpRef = useRef<HTMLInputElement>(null);

  const showNoAccountBanner =
    reason === SIGNUP_REASON_NO_ACCOUNT &&
    initialEmail.length > 0 &&
    email === initialEmail;

  async function handleSendOtp(e: React.FormEvent) {
    e.preventDefault();
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
      router.push("/accept-terms");
    }
  }

  if (otpSent) {
    return (
      <main className="flex min-h-screen items-center justify-center p-4">
        <div className="w-full max-w-sm space-y-6">
          <div className="space-y-2 text-center">
            <h1 className="text-2xl font-semibold">Enter verification code</h1>
            <p className="text-sm text-neutral-400">
              We sent a {EMAIL_OTP_LENGTH}-digit code to{" "}
              <strong className="text-white">{email}</strong>
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
              className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-center text-lg tracking-[0.3em] placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
            />

            {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

            <button
              type="submit"
              disabled={loading || otp.length !== EMAIL_OTP_LENGTH}
              className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50"
            >
              {loading ? "Verifying..." : "Create account"}
            </button>
          </form>

          <button
            onClick={() => {
              setOtpSent(false);
              setOtp("");
              setError("");
            }}
            className="block w-full text-center text-sm text-neutral-500 hover:text-neutral-300"
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
          <p className="text-sm text-neutral-400">
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
            className="w-full rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm placeholder:text-neutral-500 focus:border-neutral-500 focus:outline-none"
          />

          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

          <label className="flex items-start gap-3 text-sm text-neutral-400">
            <input
              type="checkbox"
              required
              checked={tcAccepted}
              onChange={(e) => setTcAccepted(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-neutral-700 bg-neutral-900"
            />
            <span>
              I agree to the{" "}
              <a
                href="https://soleur.ai/pages/legal/terms-and-conditions.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-white underline hover:text-neutral-300"
              >
                Terms &amp; Conditions
              </a>{" "}
              and{" "}
              <a
                href="https://soleur.ai/pages/legal/privacy-policy.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-white underline hover:text-neutral-300"
              >
                Privacy Policy
              </a>
            </span>
          </label>

          <button
            type="submit"
            disabled={loading || !tcAccepted}
            className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50"
          >
            {loading ? "Sending..." : "Send verification code"}
          </button>
        </form>

        <div className="relative flex items-center gap-4">
          <div className="flex-1 border-t border-neutral-700" />
          <span className="text-xs text-neutral-500">or</span>
          <div className="flex-1 border-t border-neutral-700" />
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
            className="text-center text-xs text-neutral-500"
          >
            Accept the terms above to continue.
          </p>
        )}

        <OAuthButtons disabled={!tcAccepted} />

        <p className="text-center text-sm text-neutral-500">
          Already have an account?{" "}
          <Link href="/login" className="text-white hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </main>
  );
}
