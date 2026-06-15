// Copy-contract tests: exact strings are intentional.
// Copy edits MUST come with test edits — that is the contract.
import { describe, it, expect } from "vitest";
import {
  CONNECTION_FAILURE_MESSAGE,
  DEFAULT_ERROR_MESSAGE,
  EMAIL_SEND_RATE_LIMIT_MESSAGE,
  EXPIRED_CODE_MESSAGE,
  isNoAccountError,
  mapSupabaseAuthError,
  mapSupabaseError,
  RATE_LIMIT_MESSAGE,
  TEMPORARILY_UNAVAILABLE_MESSAGE,
} from "./error-messages";

describe("mapSupabaseError", () => {
  it("maps 'Signups not allowed for otp' to the no-account string", () => {
    expect(mapSupabaseError("Signups not allowed for otp")).toBe(
      "No Soleur account found for this email. Sign up instead.",
    );
  });

  it("matches the no-account pattern case-insensitively", () => {
    expect(mapSupabaseError("signups not allowed for OTP")).toBe(
      "No Soleur account found for this email. Sign up instead.",
    );
  });

  it("still maps 'email rate limit exceeded' to the email-send rate-limit copy (regression guard)", () => {
    // Reference the exported constant rather than a stale inline literal so a
    // copy-tone edit (2026-06-15) keeps this guard honest. The mapping target
    // (email-send ceiling → its own distinct constant) is what's pinned here.
    expect(mapSupabaseError("email rate limit exceeded")).toBe(
      EMAIL_SEND_RATE_LIMIT_MESSAGE,
    );
  });

  it("still maps 'invalid otp' to the invalid-otp string (regression guard)", () => {
    expect(mapSupabaseError("Invalid OTP")).toBe(
      "That code is incorrect or has expired. Please request a new one.",
    );
  });

  it("maps 'token has expired' to the expired-code string", () => {
    expect(mapSupabaseError("Token has expired")).toBe(
      "Your sign-in code has expired. Please request a new one.",
    );
  });

  it("falls back to the generic message for unknown errors", () => {
    expect(mapSupabaseError("some new gotrue error")).toBe(
      "Something went wrong. Please try again.",
    );
  });
});

describe("mapSupabaseAuthError (code/status-aware)", () => {
  it("maps code 'over_request_rate_limit' to the rate-limit copy (not generic)", () => {
    expect(mapSupabaseAuthError({ code: "over_request_rate_limit" })).toBe(
      RATE_LIMIT_MESSAGE,
    );
    expect(mapSupabaseAuthError({ code: "over_request_rate_limit" })).not.toBe(
      DEFAULT_ERROR_MESSAGE,
    );
  });

  it("maps HTTP status 429 to the rate-limit copy", () => {
    expect(mapSupabaseAuthError({ status: 429 })).toBe(RATE_LIMIT_MESSAGE);
  });

  it("distinguishes verify rate-limit copy from the email-send rate-limit copy", () => {
    // The new per-request ceiling copy must NOT collide with the existing
    // freetext 'email rate limit exceeded' copy — they are different limits.
    // Reference the exported constant so a copy edit to either string keeps
    // this divergence guard honest (no stale inline literal).
    expect(RATE_LIMIT_MESSAGE).not.toBe(EMAIL_SEND_RATE_LIMIT_MESSAGE);
  });

  it("maps code 'otp_expired' to the expired-code copy", () => {
    expect(mapSupabaseAuthError({ code: "otp_expired" })).toBe(
      EXPIRED_CODE_MESSAGE,
    );
  });

  it("maps HTTP status 500 to the temporarily-unavailable copy", () => {
    expect(mapSupabaseAuthError({ status: 500 })).toBe(
      TEMPORARILY_UNAVAILABLE_MESSAGE,
    );
  });

  it("maps HTTP status 503 (AuthRetryableFetchError) to the temporarily-unavailable copy", () => {
    expect(
      mapSupabaseAuthError({ name: "AuthRetryableFetchError", status: 503 }),
    ).toBe(TEMPORARILY_UNAVAILABLE_MESSAGE);
  });

  it("maps a status-less AuthRetryableFetchError throw to the connection-failure copy", () => {
    expect(mapSupabaseAuthError({ name: "AuthRetryableFetchError" })).toBe(
      CONNECTION_FAILURE_MESSAGE,
    );
  });

  it("maps a bare TypeError (fetch reject, no status) to the connection-failure copy", () => {
    expect(mapSupabaseAuthError({ name: "TypeError", message: "Failed to fetch" })).toBe(
      CONNECTION_FAILURE_MESSAGE,
    );
  });

  it("falls back to the freetext regexes when no code/status matches", () => {
    expect(mapSupabaseAuthError({ message: "Invalid OTP" })).toBe(
      "That code is incorrect or has expired. Please request a new one.",
    );
    expect(mapSupabaseAuthError({ message: "Token has expired" })).toBe(
      EXPIRED_CODE_MESSAGE,
    );
  });

  it("falls back to the generic message for an unknown error with no code/status", () => {
    expect(mapSupabaseAuthError({ message: "some novel gotrue error" })).toBe(
      DEFAULT_ERROR_MESSAGE,
    );
  });

  it("returns the generic message for a null/undefined error (defensive)", () => {
    expect(mapSupabaseAuthError(null)).toBe(DEFAULT_ERROR_MESSAGE);
    expect(mapSupabaseAuthError(undefined)).toBe(DEFAULT_ERROR_MESSAGE);
  });

  it("prefers the structured code over a misleading freetext message", () => {
    // A 429 whose message does NOT contain 'email rate limit exceeded' must
    // still map to the rate-limit copy via code/status, not fall through.
    expect(
      mapSupabaseAuthError({
        code: "over_request_rate_limit",
        status: 429,
        message: "Request rate limit reached",
      }),
    ).toBe(RATE_LIMIT_MESSAGE);
  });
});

describe("isNoAccountError", () => {
  it("returns true when error.code === 'otp_disabled' (typed contract)", () => {
    expect(isNoAccountError({ code: "otp_disabled", message: "" })).toBe(true);
  });

  it("returns true when message matches 'Signups not allowed for otp'", () => {
    expect(
      isNoAccountError({ message: "Signups not allowed for otp" }),
    ).toBe(true);
  });

  it("returns true for the case-insensitive plural form (defense-in-depth)", () => {
    expect(
      isNoAccountError({ message: "signups not allowed for OTP" }),
    ).toBe(true);
  });

  it("returns false for unrelated errors", () => {
    expect(
      isNoAccountError({ code: "invalid_credentials", message: "Invalid OTP" }),
    ).toBe(false);
    expect(isNoAccountError({ message: "email rate limit exceeded" })).toBe(
      false,
    );
    expect(isNoAccountError({ message: "" })).toBe(false);
  });
});

// PR-B §1.7.1 — runtime typed-error mapper. Discriminates on `error.name`
// (string) rather than `instanceof` so the mapper does not pull
// `byok-lease.ts` (server) or `tenant.ts` into client bundles.
