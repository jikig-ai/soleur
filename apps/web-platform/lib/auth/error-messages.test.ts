import { describe, it, expect } from "vitest";
import { mapSupabaseError } from "./error-messages";

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

  it("still maps 'email rate limit exceeded' to the rate-limit string (regression guard)", () => {
    expect(mapSupabaseError("email rate limit exceeded")).toBe(
      "Too many sign-in attempts. Please wait a few minutes and try again.",
    );
  });

  it("still maps 'invalid otp' to the invalid-otp string (regression guard)", () => {
    expect(mapSupabaseError("Invalid OTP")).toBe(
      "That code is incorrect or has expired. Please request a new one.",
    );
  });

  it("falls back to the generic message for unknown errors", () => {
    expect(mapSupabaseError("some new gotrue error")).toBe(
      "Something went wrong. Please try again.",
    );
  });
});
