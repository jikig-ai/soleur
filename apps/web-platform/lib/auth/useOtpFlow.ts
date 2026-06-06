"use client";

import { useState, useEffect, useRef } from "react";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { OTP_RESEND_COOLDOWN_MS } from "@/lib/auth/constants";
import {
  type AuthErrorLike,
  mapSupabaseAuthError,
} from "@/lib/auth/error-messages";

/**
 * Shared OTP email-code flow for the login and signup forms. Owns the
 * email/otpSent/otp/error/loading/cooldown state, the otp-input ref, the
 * cooldown timer, and the send/resend/verify handlers — the surface that was
 * duplicated verbatim between `components/auth/login-form.tsx` and the inline
 * `SignupForm` in `app/(auth)/signup/page.tsx`.
 *
 * Behavioral branches are preserved exactly:
 * - `shouldCreateUser` is forwarded to `signInWithOtp` (login=false; signup
 *   passes true).
 * - `onVerifySuccess` runs after a clean `verifyOtp` (login → /dashboard;
 *   signup → /accept-terms).
 * - `onSendError` (login only) sees the raw send error AFTER the
 *   `reportSilentFallback` envelope; returning `true` short-circuits the
 *   default `setError(mapSupabaseAuthError(error))` (login's no-account
 *   /signup redirect path). Signup omits it.
 */
export function useOtpFlow({
  shouldCreateUser,
  onVerifySuccess,
  onSendError,
  initialEmail = "",
}: {
  shouldCreateUser: boolean;
  onVerifySuccess: () => void;
  onSendError?: (error: AuthErrorLike) => boolean;
  initialEmail?: string;
}) {
  const [email, setEmail] = useState(initialEmail);
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

  /** Send (or resend) an OTP for the current email. Returns true on success. */
  async function sendOtp(): Promise<boolean> {
    // Source-level guard: refuse a same-email re-send inside the cooldown
    // window regardless of which control invoked us (send button, resend, or
    // a re-submit after "Try a different email" with the email unchanged).
    if (cooldownActive) return false;
    setLoading(true);
    setError("");

    const supabase = createClient();
    let error: AuthErrorLike | null = null;
    try {
      ({ error } = await supabase.auth.signInWithOtp({
        email,
        options: { shouldCreateUser },
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
      // login passes a handler that performs the no-account → /signup replace
      // and returns true to short-circuit; signup omits it.
      if (onSendError?.(error)) {
        return false;
      }
      setError(mapSupabaseAuthError(error));
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
      onVerifySuccess();
    }
  }

  return {
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
  };
}
