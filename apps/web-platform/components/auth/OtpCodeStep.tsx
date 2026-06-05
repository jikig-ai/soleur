"use client";

import { type RefObject } from "react";
import { EMAIL_OTP_LENGTH } from "@/lib/auth/constants";

/**
 * Presentational verification-code step shared by the login and signup forms.
 * Renders the byte-identical JSX that previously lived inline in the
 * `if (otpSent)` branch of `components/auth/login-form.tsx` and the inline
 * `SignupForm` in `app/(auth)/signup/page.tsx`. The ONLY copy difference is the
 * submit-button label (`submitLabel`): "Sign in" for login, "Create account"
 * for signup. The 5 auth tests are the visual-regression guard.
 */
export function OtpCodeStep({
  email,
  otp,
  setOtp,
  error,
  loading,
  cooldownActive,
  cooldownSeconds,
  otpRef,
  onVerify,
  onResend,
  onTryDifferentEmail,
  submitLabel,
}: {
  email: string;
  otp: string;
  setOtp: (value: string) => void;
  error: string;
  loading: boolean;
  cooldownActive: boolean;
  cooldownSeconds: number;
  otpRef: RefObject<HTMLInputElement | null>;
  onVerify: (e: React.FormEvent) => void;
  onResend: () => void;
  onTryDifferentEmail: () => void;
  submitLabel: string;
}) {
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

        <form onSubmit={onVerify} className="space-y-4">
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
            {loading ? "Verifying..." : submitLabel}
          </button>
        </form>

        <button
          type="button"
          onClick={onResend}
          disabled={loading || cooldownActive}
          className="block w-full text-center text-sm text-soleur-text-muted hover:text-soleur-text-secondary disabled:opacity-50 disabled:hover:text-soleur-text-muted"
        >
          {cooldownActive
            ? `You can request a new code in ${cooldownSeconds}s`
            : "Resend code"}
        </button>

        <button
          onClick={onTryDifferentEmail}
          className="block w-full text-center text-sm text-soleur-text-muted hover:text-soleur-text-secondary"
        >
          Try a different email
        </button>
      </div>
    </main>
  );
}
