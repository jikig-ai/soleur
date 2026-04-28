import { describe, it, expect } from "vitest";
import { classifyCallbackError } from "@/lib/auth/error-classifier";

describe("classifyCallbackError", () => {
  // Source of truth: @supabase/auth-js error-codes.d.ts (installed v2.49.0).
  // The five verifier-class codes all surface to the user as
  // `code_verifier_missing` ("Session expired. Please try signing in again.")
  // because the recovery action is identical: re-initiate the OAuth round-trip.
  it.each([
    "bad_code_verifier",
    "flow_state_not_found",
    "flow_state_expired",
    "bad_oauth_state",
    "bad_oauth_callback",
  ])("maps Supabase error code %s to code_verifier_missing", (code) => {
    expect(classifyCallbackError({ code })).toBe("code_verifier_missing");
  });

  it.each([
    "invalid_credentials",
    "unexpected_failure",
    "user_banned",
    "session_not_found",
    "validation_failed",
  ])("maps non-verifier code %s to auth_failed", (code) => {
    expect(classifyCallbackError({ code })).toBe("auth_failed");
  });

  it("falls through to auth_failed when error.code is undefined (network error)", () => {
    expect(classifyCallbackError({ code: undefined })).toBe("auth_failed");
  });

  it("falls through to auth_failed when err is null", () => {
    expect(classifyCallbackError(null)).toBe("auth_failed");
  });

  it("falls through to auth_failed when err is a plain Error without code", () => {
    expect(classifyCallbackError(new Error("network timeout"))).toBe(
      "auth_failed",
    );
  });

  it("falls through to auth_failed when err is undefined", () => {
    expect(classifyCallbackError(undefined)).toBe("auth_failed");
  });

  it("falls through to auth_failed for non-string code values", () => {
    expect(classifyCallbackError({ code: 42 })).toBe("auth_failed");
    expect(classifyCallbackError({ code: null })).toBe("auth_failed");
  });
});
