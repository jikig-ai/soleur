"use client";

import { Suspense, useState, useEffect, useRef } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { OAuthButtons } from "@/components/auth/oauth-buttons";
import { EMAIL_OTP_LENGTH } from "@/lib/auth/constants";
import Link from "next/link";

const CALLBACK_ERRORS: Record<string, string> = {
  auth_failed:
    "Sign-in failed. This GitHub account may already be linked to another Soleur account. Try signing in with your email instead.",
  code_verifier_missing: "Session expired. Please try signing in again.",
  provider_disabled:
    "This sign-in provider is not enabled. Please use a different method.",
};

const SUPABASE_ERROR_PATTERNS: [RegExp, string][] = [
  [
    /email rate limit exceeded/i,
    "Too many sign-in attempts. Please wait a few minutes and try again.",
  ],
  [
    /invalid otp/i,
    "That code is incorrect or has expired. Please request a new one.",
  ],
  [
    /token.*expired/i,
    "Your sign-in code has expired. Please request a new one.",
  ],
];

function mapSupabaseError(message: string): string {
  for (const [pattern, friendly] of SUPABASE_ERROR_PATTERNS) {
    if (pattern.test(message)) return friendly;
  }
  return "Something went wrong. Please try again.";
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}

function LoginForm() {
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
        CALLBACK_ERRORS[callbackError] ??
          "Something went wrong. Please try again.",
      );
    }
  }, [searchParams]);

  async function handleSendOtp(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false },
    });

    setLoading(false);

    if (error) {
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
      setError(mapSupabaseError(error.message));
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
              {loading ? "Verifying..." : "Sign in"}
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
          <h1 className="text-2xl font-semibold">Sign in to Soleur</h1>
          <p className="text-sm text-neutral-400">
            Enter your email to receive a sign-in code
          </p>
        </div>

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

          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50"
          >
            {loading ? "Sending..." : "Send sign-in code"}
          </button>
        </form>

        <div className="relative flex items-center gap-4">
          <div className="flex-1 border-t border-neutral-700" />
          <span className="text-xs text-neutral-500">or</span>
          <div className="flex-1 border-t border-neutral-700" />
        </div>

        <OAuthButtons />

        <p className="text-center text-sm text-neutral-500">
          Don&apos;t have an account?{" "}
          <Link href="/signup" className="text-white hover:underline">
            Sign up
          </Link>
        </p>
      </div>
    </main>
  );
}
