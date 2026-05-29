/** Length of the email OTP code. Must match Supabase mailer_otp_length. */
export const EMAIL_OTP_LENGTH = 6;

/**
 * Client-side resend cooldown for OTP sign-in codes, in milliseconds.
 *
 * Must be >= GoTrue's per-user OTP window (`auth.rate_limits.otp.period`,
 * which defaults to 60s — `configure-auth.sh` does not override it). A second
 * `signInWithOtp` to the same email inside that window returns HTTP 429
 * `email rate limit exceeded` ("Too many sign-in attempts."). Disabling the
 * resend control for this duration keeps the UI from firing a same-email
 * re-send before GoTrue will accept it.
 */
export const OTP_RESEND_COOLDOWN_MS = 60_000;
