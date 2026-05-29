import { describe, it, expect } from "vitest";
import { safeReturnTo } from "@/lib/safe-return-to";

describe("safeReturnTo", () => {
  // The generalized helper returns the param iff it is a same-origin relative
  // path under an allowed prefix (/dashboard, /invite/), else null. Each caller
  // supplies its own fallback (login → /dashboard, signup → /accept-terms).
  // The open-redirect guards (//, \\, .. rejection) are the verified precedent
  // shape, retained verbatim.

  it("returns null for null input (caller picks fallback)", () => {
    expect(safeReturnTo(null)).toBe(null);
  });

  it("returns null for empty string", () => {
    expect(safeReturnTo("")).toBe(null);
  });

  it("allows /dashboard path", () => {
    expect(safeReturnTo("/dashboard")).toBe("/dashboard");
  });

  it("allows /dashboard/settings path", () => {
    expect(safeReturnTo("/dashboard/settings")).toBe("/dashboard/settings");
  });

  it("allows /dashboard/settings/team path", () => {
    expect(safeReturnTo("/dashboard/settings/team")).toBe(
      "/dashboard/settings/team",
    );
  });

  it("allows /invite/<token> path (the multi-user onboarding target)", () => {
    expect(safeReturnTo("/invite/abc123token")).toBe("/invite/abc123token");
  });

  it("blocks absolute URLs", () => {
    expect(safeReturnTo("https://evil.com")).toBe(null);
  });

  it("blocks protocol-relative URLs", () => {
    expect(safeReturnTo("//evil.com")).toBe(null);
  });

  it("blocks backslash-prefixed protocol-relative bypass (/\\evil)", () => {
    expect(safeReturnTo("/\\evil.com")).toBe(null);
  });

  it("blocks paths with backslash", () => {
    expect(safeReturnTo("/dashboard\\@evil.com")).toBe(null);
  });

  it("blocks paths not on the allowlist (/login)", () => {
    expect(safeReturnTo("/login")).toBe(null);
  });

  it("blocks an arbitrary non-allowlisted relative path (/evil)", () => {
    expect(safeReturnTo("/evil")).toBe(null);
  });

  it("blocks encoded-slash bypass that is not allowlisted (/%2Fevil)", () => {
    expect(safeReturnTo("/%2Fevil")).toBe(null);
  });

  it("blocks paths that start with /dashboard but use // after", () => {
    expect(safeReturnTo("/dashboard//evil.com")).toBe(null);
  });

  it("blocks path traversal with ..", () => {
    expect(safeReturnTo("/dashboard/../../etc/passwd")).toBe(null);
  });

  it("blocks path traversal escaping dashboard", () => {
    expect(safeReturnTo("/dashboard/../logout")).toBe(null);
  });

  it("blocks path traversal out of /invite/", () => {
    expect(safeReturnTo("/invite/../dashboard")).toBe(null);
  });
});
