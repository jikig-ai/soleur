import { describe, test, expect } from "vitest";
import { buildAuthenticatedClaims, buildAnonClaims } from "./claim";
import { classifyWriteOutcome, classifySelectOutcome, isPass, RLS_VIOLATION_SQLSTATE } from "./verdict";

describe("buildAuthenticatedClaims", () => {
  test("sub becomes auth.uid(); role is authenticated", () => {
    const c = JSON.parse(buildAuthenticatedClaims({ sub: "user-B" }));
    expect(c.sub).toBe("user-B");
    expect(c.role).toBe("authenticated");
    expect(c.app_metadata).toBeUndefined(); // no org given → omitted
    expect(c.jti).toBeUndefined();
  });
  test("org id mirrors the prod hook shape (app_metadata.current_organization_id)", () => {
    const c = JSON.parse(buildAuthenticatedClaims({ sub: "u", organizationId: "org-B" }));
    expect(c.app_metadata.current_organization_id).toBe("org-B");
  });
  test("jti is included for the revoked-jti dimension", () => {
    const c = JSON.parse(buildAuthenticatedClaims({ sub: "u", jti: "jti-1" }));
    expect(c.jti).toBe("jti-1");
  });
  test("anon claims carry role only, no sub", () => {
    const c = JSON.parse(buildAnonClaims());
    expect(c.role).toBe("anon");
    expect(c.sub).toBeUndefined();
  });
});

describe("classifyWriteOutcome (SQLSTATE discrimination — AC2)", () => {
  test("42501 → denied (RLS blocked the write)", () => {
    const v = classifyWriteOutcome({ code: RLS_VIOLATION_SQLSTATE });
    expect(v).toEqual({ kind: "denied" });
    expect(isPass(v)).toBe(true);
  });
  test("no error → leaked (cross-tenant write succeeded)", () => {
    const v = classifyWriteOutcome(null);
    expect(v).toEqual({ kind: "leaked" });
    expect(isPass(v)).toBe(false);
  });
  test.each(["23502", "23503", "23514", "42703", "unknown"])(
    "constraint/other SQLSTATE %s → test-error, NOT a pass",
    (code) => {
      const v = classifyWriteOutcome({ code });
      expect(v.kind).toBe("test-error");
      expect(isPass(v)).toBe(false); // a constraint failure must NEVER count as denied
    },
  );
  test("undefined error object with no code → test-error unknown", () => {
    expect(classifyWriteOutcome({})).toEqual({ kind: "test-error", sqlstate: "unknown" });
  });
});

describe("classifySelectOutcome", () => {
  test("0 rows of the seeded target row → denied", () => {
    expect(classifySelectOutcome(0)).toEqual({ kind: "denied" });
  });
  test(">0 rows → leaked (tenant B saw tenant A's row)", () => {
    expect(isPass(classifySelectOutcome(1))).toBe(false);
  });
});
