import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks must be hoisted BEFORE the route import. Use vi.hoisted because
// vitest hoists vi.mock() to the top of the file before any const/let runs.
// ---------------------------------------------------------------------------

const { mockReportSilentFallback, mockExchangeCodeForSession, mockGetUser } =
  vi.hoisted(() => ({
    mockReportSilentFallback: vi.fn(),
    mockExchangeCodeForSession: vi.fn(),
    mockGetUser: vi.fn(),
  }));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

vi.mock("@/lib/auth/resolve-origin", () => ({
  resolveOrigin: () => "https://app.soleur.ai",
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: {
      exchangeCodeForSession: mockExchangeCodeForSession,
      getUser: mockGetUser,
    },
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(),
}));

vi.mock("@/server/workspace", () => ({
  provisionWorkspace: vi.fn(),
}));

vi.mock("@/lib/legal/tc-version", () => ({
  TC_VERSION: "2026-01-01",
}));

import { NextRequest } from "next/server";
import { GET } from "@/app/(auth)/callback/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(
  query: string,
  headers: Record<string, string> = {},
): NextRequest {
  // NextRequest parses the `cookie` header into `request.cookies.getAll()`,
  // which the route reads on the verifier-class clear path.
  return new NextRequest(`https://app.soleur.ai/callback${query}`, {
    method: "GET",
    headers: {
      host: "app.soleur.ai",
      "x-forwarded-proto": "https",
      "x-forwarded-host": "app.soleur.ai",
      ...headers,
    },
  });
}

const PROVIDER_ERROR_EXTRA_KEYS = [
  "bucket",
  "origin",
  "providerErrorCode",
  "refererHost",
  "urlPath",
];

const NO_CODE_EXTRA_KEYS = [
  "codePresent",
  "origin",
  "refererHost",
  "searchParamKeys",
  "urlPath",
];

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GET /callback — no-code branches", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each([
    ["?error=access_denied", "access_denied", "oauth_cancelled"],
    ["?error=server_error", "server_error", "oauth_failed"],
    ["?error=temporarily_unavailable", "temporarily_unavailable", "oauth_failed"],
    ["?error=invalid_scope", "invalid_scope", "oauth_failed"],
  ])(
    "%s → /login?error=%s with op callback_provider_error",
    async (query, expectedRawCode, expectedBucket) => {
      const res = await GET(makeRequest(query));

      expect(res.status).toBe(307);
      expect(res.headers.get("location")).toBe(
        `https://app.soleur.ai/login?error=${expectedBucket}`,
      );
      expect(res.headers.get("cache-control")).toBe("no-store");

      expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
      const [, opts] = mockReportSilentFallback.mock.calls[0];
      expect(opts.feature).toBe("auth");
      expect(opts.op).toBe("callback_provider_error");
      expect(opts.extra.providerErrorCode).toBe(expectedRawCode);
      expect(opts.extra.bucket).toBe(expectedBucket);
      // Closed-set assertion — fails the day someone adds error_description,
      // url, or any other PII-bearing key.
      expect(Object.keys(opts.extra).sort()).toEqual(PROVIDER_ERROR_EXTRA_KEYS);
    },
  );

  it("unrecognized ?error=<value> is forwarded as 'unknown' (no Sentry tag inflation)", async () => {
    // Attacker-controlled query: `?error=user@example.com`. The user-facing
    // redirect is sanitized to oauth_failed; the raw value MUST NOT land in
    // Sentry extras (cardinality + log-injection discipline).
    const res = await GET(makeRequest("?error=user@example.com"));

    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=oauth_failed",
    );

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra.providerErrorCode).toBe("unknown");
  });

  it("bare /callback (no params) → /login?error=auth_failed with op callback_no_code", async () => {
    const res = await GET(makeRequest(""));

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=auth_failed",
    );
    expect(res.headers.get("cache-control")).toBe("no-store");

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.feature).toBe("auth");
    expect(opts.op).toBe("callback_no_code");
    expect(opts.extra.codePresent).toBe(false);
    expect(opts.extra.urlPath).toBe("/callback");
    expect(Array.isArray(opts.extra.searchParamKeys)).toBe(true);
    expect(opts.extra.searchParamKeys).toEqual([]);
    // Closed-set assertion — vacuous `not.toHaveProperty` would pass even if
    // a future regression added `referer`, `url`, or `host` to extras.
    expect(Object.keys(opts.extra).sort()).toEqual(NO_CODE_EXTRA_KEYS);
  });

  it("malformed ?error[]=access_denied falls through to bare-/callback branch", async () => {
    // WHATWG URL semantics: 'error[]' is its own key. Provider classifier
    // returns null, so we land on `callback_no_code`.
    const res = await GET(makeRequest("?error[]=access_denied"));

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=auth_failed",
    );

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.op).toBe("callback_no_code");
  });

  it("refererHost contains hostname only — never path, query, or port", async () => {
    // Paste-protected unit test for Risk R3: a regression that swaps
    // `.hostname` for `.host` (port leaks) or to raw `referer` (path/query
    // leaks) gets caught here.
    const res = await GET(
      makeRequest("?error=access_denied", {
        referer: "https://accounts.google.com:443/o/oauth2?email=user@x.com",
      }),
    );

    expect(res.status).toBe(307);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra.refererHost).toBe("accounts.google.com");
    // Lock down: no port, no path, no query.
    expect(opts.extra.refererHost).not.toContain(":");
    expect(opts.extra.refererHost).not.toContain("/");
    expect(opts.extra.refererHost).not.toContain("?");
    expect(opts.extra.refererHost).not.toContain("email");
  });

  it("searchParamKeys is capped, shape-filtered, and keys-only", async () => {
    // Pump 25 keys with mixed shapes — the route caps at 20, filters out
    // any non-[a-zA-Z0-9_.-]{1,32} keys, dedupes, sorts.
    const params = new URLSearchParams();
    for (let i = 0; i < 25; i++) params.append(`k${i}`, "v");
    params.append("evil key with spaces", "x");
    params.append("a".repeat(64), "x");
    const res = await GET(makeRequest(`?${params.toString()}`));

    expect(res.status).toBe(307);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra.searchParamKeys.length).toBeLessThanOrEqual(20);
    // No spaces or 64-char keys survived the filter.
    for (const k of opts.extra.searchParamKeys) {
      expect(k).toMatch(/^[a-zA-Z0-9_.-]{1,32}$/);
    }
    // Sorted.
    expect(opts.extra.searchParamKeys).toEqual(
      [...opts.extra.searchParamKeys].sort(),
    );
  });
});

describe("GET /callback — verifier-cookie clearing (folds in #3001)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("clears sb-*-auth-token-code-verifier cookies on verifier-class failure", async () => {
    mockExchangeCodeForSession.mockResolvedValue({
      error: { code: "bad_code_verifier", name: "AuthError", status: 400 },
    });

    const res = await GET(
      makeRequest("?code=abc", {
        cookie:
          "sb-projref-auth-token-code-verifier=stale1; sb-projref-auth-token=session",
      }),
    );

    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=code_verifier_missing",
    );
    expect(res.headers.get("cache-control")).toBe("no-store");

    // The cleared verifier cookie shows up as a Set-Cookie with Max-Age=0.
    const setCookies = res.headers.getSetCookie?.() ?? [];
    const verifierClear = setCookies.find((c) =>
      c.startsWith("sb-projref-auth-token-code-verifier="),
    );
    expect(verifierClear).toBeDefined();
    expect(verifierClear).toMatch(/Max-Age=0/);

    // The session cookie must NOT be cleared.
    const sessionClear = setCookies.find(
      (c) => c.startsWith("sb-projref-auth-token=") && c.includes("Max-Age=0"),
    );
    expect(sessionClear).toBeUndefined();
  });

  it("clears chunked verifier variants (sb-*-auth-token-code-verifier.0)", async () => {
    mockExchangeCodeForSession.mockResolvedValue({
      error: { code: "flow_state_expired", name: "AuthError", status: 400 },
    });

    const res = await GET(
      makeRequest("?code=abc", {
        cookie: "sb-projref-auth-token-code-verifier.0=part1",
      }),
    );

    const setCookies = res.headers.getSetCookie?.() ?? [];
    const verifierClear = setCookies.find((c) =>
      c.startsWith("sb-projref-auth-token-code-verifier.0="),
    );
    expect(verifierClear).toBeDefined();
    expect(verifierClear).toMatch(/Max-Age=0/);
  });

  it("does not clear cookies on non-verifier-class exchange failures", async () => {
    mockExchangeCodeForSession.mockResolvedValue({
      error: { code: "invalid_credentials", name: "AuthError", status: 401 },
    });

    const res = await GET(
      makeRequest("?code=abc", {
        cookie: "sb-projref-auth-token-code-verifier=stale1",
      }),
    );

    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=auth_failed",
    );
    const setCookies = res.headers.getSetCookie?.() ?? [];
    const verifierClear = setCookies.find(
      (c) => c.includes("auth-token-code-verifier") && c.includes("Max-Age=0"),
    );
    expect(verifierClear).toBeUndefined();
  });
});
