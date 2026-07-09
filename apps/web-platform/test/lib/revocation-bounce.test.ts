import { describe, it, expect } from "vitest";
import { isRevocationBounce } from "@/lib/auth/revocation-bounce";

// GAP F (ADR-067 staleTimes amendment): the client-side revocation-bounce
// detector must catch BOTH a direct 401 AND the #4307 middleware 302→/login
// (fetch follows the redirect to 200 HTML). A `status===401`-only guard would
// silently never fire for the revocation path — the exact defect this closes.

function mockRes(init: {
  status?: number;
  redirected?: boolean;
  url?: string;
}): Response {
  return {
    status: init.status ?? 200,
    redirected: init.redirected ?? false,
    url: init.url ?? "https://app.soleur.ai/api/x",
  } as unknown as Response;
}

describe("isRevocationBounce (GAP F)", () => {
  it("returns true for a direct 401", () => {
    expect(isRevocationBounce(mockRes({ status: 401 }))).toBe(true);
  });

  it("returns true for a FOLLOWED 302→/login (status 200, redirected, /login pathname)", () => {
    // This is the #4307 revocation shape: middleware 302s to /login and fetch
    // follows it to the login HTML. A status===401-only guard would MISS this.
    expect(
      isRevocationBounce(
        mockRes({ status: 200, redirected: true, url: "https://app.soleur.ai/login" }),
      ),
    ).toBe(true);
  });

  it("returns true for a followed 302→/login carrying a query string", () => {
    expect(
      isRevocationBounce(
        mockRes({
          status: 200,
          redirected: true,
          url: "https://app.soleur.ai/login?revoked=removed",
        }),
      ),
    ).toBe(true);
  });

  it("returns false for a normal 200 that was NOT redirected (the common tab-switch path)", () => {
    expect(
      isRevocationBounce(
        mockRes({ status: 200, redirected: false, url: "https://app.soleur.ai/api/kb/tree" }),
      ),
    ).toBe(false);
  });

  it("returns false for a redirect to a DIFFERENT path (no false-positive on canonicalization / /dashboard)", () => {
    expect(
      isRevocationBounce(
        mockRes({ status: 200, redirected: true, url: "https://app.soleur.ai/dashboard" }),
      ),
    ).toBe(false);
  });

  it("does not match a path that merely CONTAINS /login (exact pathname only)", () => {
    expect(
      isRevocationBounce(
        mockRes({ status: 200, redirected: true, url: "https://app.soleur.ai/login-help" }),
      ),
    ).toBe(false);
  });

  it("returns false (not throw) on a malformed url", () => {
    expect(isRevocationBounce(mockRes({ status: 200, redirected: true, url: "" }))).toBe(false);
  });

  it("returns false for other non-401 error statuses (503/404 have distinct handling)", () => {
    expect(isRevocationBounce(mockRes({ status: 503 }))).toBe(false);
    expect(isRevocationBounce(mockRes({ status: 404 }))).toBe(false);
  });
});
