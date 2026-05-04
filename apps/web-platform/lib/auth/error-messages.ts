export const DEFAULT_ERROR_MESSAGE = "Something went wrong. Please try again.";

export const CALLBACK_ERRORS: Record<string, string> = {
  auth_failed:
    "Sign-in failed. If you have an existing account, try signing in with email instead.",
  code_verifier_missing: "Session expired. Please try signing in again.",
  provider_disabled:
    "This sign-in provider is not enabled. Please use a different method.",
  oauth_cancelled:
    "Sign-in cancelled. Click your sign-in option to try again.",
  oauth_failed:
    "The sign-in service had a temporary problem. Please try again.",
};

export const NO_ACCOUNT_PATTERN = /signups? not allowed for otp/i;

export const SIGNUP_REASON_NO_ACCOUNT = "no_account";

const SUPABASE_ERROR_PATTERNS: [RegExp, string][] = [
  [
    NO_ACCOUNT_PATTERN,
    "No Soleur account found for this email. Sign up instead.",
  ],
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

export function mapSupabaseError(message: string): string {
  for (const [pattern, friendly] of SUPABASE_ERROR_PATTERNS) {
    if (pattern.test(message)) return friendly;
  }
  return DEFAULT_ERROR_MESSAGE;
}

export function isNoAccountError(error: {
  code?: string;
  message: string;
}): boolean {
  if (error.code === "otp_disabled") return true;
  return NO_ACCOUNT_PATTERN.test(error.message);
}
