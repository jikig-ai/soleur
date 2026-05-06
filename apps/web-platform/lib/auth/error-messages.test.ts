// Copy-contract tests: exact strings are intentional.
// Copy edits MUST come with test edits — that is the contract.
import { describe, it, expect } from "vitest";
import {
  DEFAULT_ERROR_MESSAGE,
  isNoAccountError,
  mapRuntimeError,
  mapSupabaseError,
} from "./error-messages";
import { RlsDenyError, AuditWriteError } from "./runtime-errors";

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
describe("mapRuntimeError", () => {
  it("maps RuntimeAuthError (cause: jwt_mint) to sanitized auth string", () => {
    class RuntimeAuthError extends Error {
      constructor() {
        super("internal mint failure shape");
        this.name = "RuntimeAuthError";
      }
    }
    expect(mapRuntimeError(new RuntimeAuthError())).toBe(
      "Authentication unavailable; retry shortly.",
    );
  });

  it("maps ByokLeaseError (cause: escape) to sanitized auth string", () => {
    class ByokLeaseError extends Error {
      constructor() {
        super("internal lease escape");
        this.name = "ByokLeaseError";
      }
    }
    expect(mapRuntimeError(new ByokLeaseError())).toBe(
      "Authentication unavailable; retry shortly.",
    );
  });

  it("maps RlsDenyError to 'Access denied.' (UX is distinct from auth-domain)", () => {
    expect(
      mapRuntimeError(
        new RlsDenyError("explicit_deny", "permission denied for table"),
      ),
    ).toBe("Access denied.");
  });

  it("maps AuditWriteError to DEFAULT (integrity-domain, no user-facing degradation)", () => {
    expect(
      mapRuntimeError(
        new AuditWriteError("audit_byok_use", "insert failed: foreign key"),
      ),
    ).toBe(DEFAULT_ERROR_MESSAGE);
  });

  it("returns DEFAULT for non-Error inputs (defensive)", () => {
    expect(mapRuntimeError("string error")).toBe(DEFAULT_ERROR_MESSAGE);
    expect(mapRuntimeError(undefined)).toBe(DEFAULT_ERROR_MESSAGE);
    expect(mapRuntimeError(null)).toBe(DEFAULT_ERROR_MESSAGE);
    expect(mapRuntimeError({ name: "RuntimeAuthError" })).toBe(
      DEFAULT_ERROR_MESSAGE,
    );
  });

  it("returns DEFAULT for unrecognized Error subclasses", () => {
    expect(mapRuntimeError(new TypeError("oops"))).toBe(DEFAULT_ERROR_MESSAGE);
    expect(mapRuntimeError(new Error("plain"))).toBe(DEFAULT_ERROR_MESSAGE);
  });
});
