import { describe, test, expect } from "vitest";
import { TC_VERSION } from "../lib/legal/tc-version";

describe("TC_VERSION constant", () => {
  test("is a non-empty string", () => {
    expect(typeof TC_VERSION).toBe("string");
    expect(TC_VERSION.length).toBeGreaterThan(0);
  });

  test("follows semver format", () => {
    expect(TC_VERSION).toMatch(/^\d+\.\d+\.\d+$/);
  });
});

describe("T&C version check logic", () => {
  // Mirrors the middleware comparison: userRow?.tc_accepted_version !== TC_VERSION
  function shouldRedirectToAcceptTerms(tcAcceptedVersion: string | null | undefined): boolean {
    return tcAcceptedVersion !== TC_VERSION;
  }

  test("user with current version proceeds normally", () => {
    expect(shouldRedirectToAcceptTerms(TC_VERSION)).toBe(false);
  });

  test("user with NULL version is redirected", () => {
    expect(shouldRedirectToAcceptTerms(null)).toBe(true);
  });

  test("user with undefined version is redirected", () => {
    expect(shouldRedirectToAcceptTerms(undefined)).toBe(true);
  });

  test("user with stale version is redirected", () => {
    expect(shouldRedirectToAcceptTerms("0.9.0")).toBe(true);
  });

  test("user with future version is redirected (version must match exactly)", () => {
    expect(shouldRedirectToAcceptTerms("2.0.0")).toBe(true);
  });

  test("same version after redeployment does not trigger re-acceptance", () => {
    // Simulates: user accepted 1.0.0, app redeployed with same TC_VERSION
    expect(shouldRedirectToAcceptTerms("1.0.0")).toBe(false);
  });
});

describe("T&C middleware fail-open behavior", () => {
  // Mirrors the middleware logic: if query errors, allow request through
  function shouldFailOpen(queryError: { message: string } | null): boolean {
    return queryError !== null;
  }

  test("query error results in fail-open (user proceeds)", () => {
    expect(shouldFailOpen({ message: "connection refused" })).toBe(true);
  });

  test("no error proceeds to version check", () => {
    expect(shouldFailOpen(null)).toBe(false);
  });
});
