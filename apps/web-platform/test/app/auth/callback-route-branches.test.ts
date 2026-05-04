import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks must be hoisted BEFORE the route import. Use vi.hoisted because
// vitest hoists vi.mock() to the top of the file before any const/let runs.
// ---------------------------------------------------------------------------

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  APP_URL_FALLBACK: "https://app.soleur.ai",
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

// resolveOrigin always returns the canonical app origin in tests so the
// expected redirect URL is deterministic.
vi.mock("@/lib/auth/resolve-origin", () => ({
  resolveOrigin: () => "https://app.soleur.ai",
}));

// The createServerClient + createServiceClient + provisionWorkspace
// dependencies are unreachable in the tests below (no `code` param means the
// route never enters the exchange branch). Stub them defensively.
vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(),
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

import { GET } from "@/app/(auth)/callback/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeRequest(query: string): Request {
  // Use NextRequest-compatible Request — the route only consumes
  // `request.url`, `request.headers.get`, and `request.cookies.getAll`.
  // `Request` from the standard fetch API is sufficient because the route
  // delegates cookie reads to createServerClient (which we stubbed).
  return new Request(`https://app.soleur.ai/callback${query}`, {
    method: "GET",
    headers: {
      host: "app.soleur.ai",
      "x-forwarded-proto": "https",
      "x-forwarded-host": "app.soleur.ai",
    },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GET /callback — no-code branches", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("?error=access_denied → /login?error=oauth_cancelled with op callback_provider_error", async () => {
    // The cast targets NextRequest; the route only touches the methods we
    // stubbed on the standard Request. Casting through `unknown` keeps the
    // typecheck honest without requiring a NextRequest-shaped fixture.
    const res = await GET(makeRequest("?error=access_denied") as never);

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=oauth_cancelled",
    );

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.feature).toBe("auth");
    expect(opts.op).toBe("callback_provider_error");
    expect(opts.extra.providerErrorCode).toBe("access_denied");
    // Hostname-only — never the full referer URL or the inbound URL with
    // its `error_description` query param (PII discipline).
    expect(opts.extra).not.toHaveProperty("error_description");
    expect(opts.extra).not.toHaveProperty("url");
  });

  it("?error=server_error → /login?error=oauth_failed with op callback_provider_error", async () => {
    const res = await GET(makeRequest("?error=server_error") as never);

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=oauth_failed",
    );

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.op).toBe("callback_provider_error");
    expect(opts.extra.providerErrorCode).toBe("server_error");
  });

  it("?error=temporarily_unavailable → /login?error=oauth_failed", async () => {
    const res = await GET(
      makeRequest("?error=temporarily_unavailable") as never,
    );

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=oauth_failed",
    );
  });

  it("bare /callback (no params) → /login?error=auth_failed with op callback_no_code", async () => {
    const res = await GET(makeRequest("") as never);

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=auth_failed",
    );

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.feature).toBe("auth");
    expect(opts.op).toBe("callback_no_code");
    expect(opts.extra.codePresent).toBe(false);
    // The new mirror extras must be present so root-cause-class is
    // queryable in Sentry without re-deploying.
    expect(opts.extra).toHaveProperty("urlPath", "/callback");
    expect(opts.extra).toHaveProperty("searchParamKeys");
    expect(Array.isArray(opts.extra.searchParamKeys)).toBe(true);
  });

  it("malformed ?error[]=access_denied falls through to bare-/callback branch", async () => {
    // WHATWG URL semantics: 'error[]' is its own key. The provider classifier
    // returns null, so we fall through to the existing `callback_no_code`
    // branch — NOT the new `callback_provider_error` op.
    const res = await GET(makeRequest("?error[]=access_denied") as never);

    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toBe(
      "https://app.soleur.ai/login?error=auth_failed",
    );

    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.op).toBe("callback_no_code");
  });
});
