import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Set env BEFORE any imports that read at load time
// ---------------------------------------------------------------------------
process.env.GITHUB_CLIENT_ID = "test-client-id";
process.env.GITHUB_CLIENT_SECRET = "test-client-secret";

// ---------------------------------------------------------------------------
// Mock modules BEFORE importing the route handlers
// ---------------------------------------------------------------------------

const mockGetUser = vi.fn();
const mockServiceFrom = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
  }),
  createServiceClient: () => ({
    from: mockServiceFrom,
  }),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

// ---------------------------------------------------------------------------
// URL-routing mock for global fetch (GitHub API calls)
// ---------------------------------------------------------------------------

type MockRoute = {
  test: (url: string, init?: RequestInit) => boolean;
  response: () => Promise<Partial<Response>>;
};

const fetchRoutes: MockRoute[] = [];
const originalFetch = globalThis.fetch;

/** Register a URL-matching mock response. Routes are checked in order. */
function mockFetchRoute(
  match: string | ((url: string, init?: RequestInit) => boolean),
  response: Partial<Response> | (() => Promise<Partial<Response>>),
) {
  const test = typeof match === "string"
    ? (url: string) => url.includes(match)
    : match;
  const responseFn = typeof response === "function"
    ? response
    : () => Promise.resolve(response);
  fetchRoutes.push({ test, response: responseFn });
}

/** Clear all registered routes. */
function clearFetchRoutes() {
  fetchRoutes.length = 0;
}

/** The routing fetch mock — matches registered routes by URL. */
const routingFetch = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
  for (const route of fetchRoutes) {
    if (route.test(url, init)) {
      return route.response();
    }
  }
  throw new Error(`Unmatched fetch URL: ${url}`);
}) as unknown as typeof fetch;

// ---------------------------------------------------------------------------
// Import route handlers
// ---------------------------------------------------------------------------

import { GET as initiateHandler } from "../app/api/auth/github-resolve/route";
import { GET as callbackHandler } from "../app/api/auth/github-resolve/callback/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeInitiateRequest() {
  return new Request("https://app.soleur.ai/api/auth/github-resolve", {
    method: "GET",
  });
}

function makeCallbackRequest(params: Record<string, string>, cookieHeader?: string) {
  const url = new URL("https://app.soleur.ai/api/auth/github-resolve/callback");
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  const headers: Record<string, string> = {};
  if (cookieHeader) {
    headers.Cookie = cookieHeader;
  }
  return new Request(url.toString(), { method: "GET", headers });
}

function extractCookie(response: Response, name: string): string | undefined {
  const cookies = response.headers.getSetCookie?.() ?? [];
  for (const cookie of cookies) {
    if (cookie.startsWith(`${name}=`)) {
      return cookie.split("=")[1].split(";")[0];
    }
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Tests: OAuth initiate route
// ---------------------------------------------------------------------------

describe("GET /api/auth/github-resolve (initiate)", () => {
  beforeEach(() => {
    // Initiate route now checks auth (defense-in-depth)
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-123" } } });
  });

  test("returns 302 redirect to GitHub OAuth authorize URL", async () => {
    const response = await initiateHandler(makeInitiateRequest());

    expect(response.status).toBe(302);
    const location = response.headers.get("Location");
    expect(location).toContain("https://github.com/login/oauth/authorize");
    expect(location).toContain("client_id=test-client-id");
    expect(location).toContain("state=");
  });

  test("sets soleur_github_resolve cookie with state nonce", async () => {
    const response = await initiateHandler(makeInitiateRequest());

    const stateFromCookie = extractCookie(response, "soleur_github_resolve");
    expect(stateFromCookie).toBeDefined();
    expect(stateFromCookie!.length).toBeGreaterThan(0);

    // State in cookie should match state in redirect URL
    const location = response.headers.get("Location")!;
    const url = new URL(location);
    const stateFromUrl = url.searchParams.get("state");
    expect(stateFromUrl).toBe(stateFromCookie);
  });

  test("cookie has correct attributes (SameSite=Lax, HttpOnly, Secure)", async () => {
    const response = await initiateHandler(makeInitiateRequest());

    const cookies = response.headers.getSetCookie?.() ?? [];
    const stateCookie = cookies.find((c: string) => c.startsWith("soleur_github_resolve="));
    expect(stateCookie).toBeDefined();
    // Next.js normalizes SameSite to lowercase
    expect(stateCookie?.toLowerCase()).toContain("samesite=lax");
    expect(stateCookie).toContain("HttpOnly");
    expect(stateCookie).toContain("Secure");
    expect(stateCookie).toContain("Max-Age=300");
  });

  test("does not include scope parameter in authorize URL", async () => {
    const response = await initiateHandler(makeInitiateRequest());

    const location = response.headers.get("Location")!;
    expect(location).not.toContain("scope=");
  });
});

// ---------------------------------------------------------------------------
// Tests: OAuth callback route
// ---------------------------------------------------------------------------

describe("GET /api/auth/github-resolve/callback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    clearFetchRoutes();
    globalThis.fetch = routingFetch;

    // Default: authenticated user
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-123" } },
    });

    // Default: successful DB update
    mockServiceFrom.mockReturnValue({
      update: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    });

    // Default: token revocation succeeds (fire-and-forget, matched by URL)
    mockFetchRoute("/applications/", { ok: true, status: 204 });
  });

  afterEach(() => {
    clearFetchRoutes();
    globalThis.fetch = originalFetch;
  });

  test("stores github_username and redirects on valid code+state", async () => {
    const stateNonce = "test-state-123";

    // Mock GitHub token exchange (matched by URL)
    mockFetchRoute("login/oauth/access_token", {
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    // Mock GET /user (matched by URL)
    mockFetchRoute((url, init) => url.includes("api.github.com/user") && init?.method !== "DELETE", {
      ok: true,
      json: async () => ({ login: "deruelle" }),
    });

    const response = await callbackHandler(
      makeCallbackRequest(
        { code: "valid-code", state: stateNonce },
        `soleur_github_resolve=${stateNonce}`,
      ),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("/connect-repo");
    expect(response.headers.get("Location")).not.toContain("resolve_error");

    // Verify github_username was stored
    expect(mockServiceFrom).toHaveBeenCalledWith("users");
  });

  test("redirects with resolve_error=1 when code param is missing", async () => {
    const response = await callbackHandler(
      makeCallbackRequest(
        { state: "some-state" },
        "soleur_github_resolve=some-state",
      ),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("resolve_error=1");
  });

  test("redirects with resolve_error=1 when state does not match cookie", async () => {
    const response = await callbackHandler(
      makeCallbackRequest(
        { code: "valid-code", state: "wrong-state" },
        "soleur_github_resolve=correct-state",
      ),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("resolve_error=1");
  });

  test("redirects with resolve_error=1 when state cookie is missing", async () => {
    const response = await callbackHandler(
      makeCallbackRequest({ code: "valid-code", state: "some-state" }),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("resolve_error=1");
  });

  test("redirects with resolve_error=1 when token exchange fails", async () => {
    const stateNonce = "test-state-456";

    mockFetchRoute("login/oauth/access_token", {
      ok: false,
      status: 400,
      json: async () => ({ error: "bad_verification_code" }),
    });

    const response = await callbackHandler(
      makeCallbackRequest(
        { code: "expired-code", state: stateNonce },
        `soleur_github_resolve=${stateNonce}`,
      ),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("resolve_error=1");
  });

  test("redirects with resolve_error=1 when GET /user returns empty login", async () => {
    const stateNonce = "test-state-789";

    mockFetchRoute("login/oauth/access_token", {
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    mockFetchRoute((url, init) => url.includes("api.github.com/user") && init?.method !== "DELETE", {
      ok: true,
      json: async () => ({ login: "" }),
    });

    const response = await callbackHandler(
      makeCallbackRequest(
        { code: "valid-code", state: stateNonce },
        `soleur_github_resolve=${stateNonce}`,
      ),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("Location")).toContain("resolve_error=1");
  });

  test("deletes state cookie on successful callback", async () => {
    const stateNonce = "test-state-cleanup";

    mockFetchRoute("login/oauth/access_token", {
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    mockFetchRoute((url, init) => url.includes("api.github.com/user") && init?.method !== "DELETE", {
      ok: true,
      json: async () => ({ login: "deruelle" }),
    });

    const response = await callbackHandler(
      makeCallbackRequest(
        { code: "valid-code", state: stateNonce },
        `soleur_github_resolve=${stateNonce}`,
      ),
    );

    // Cookie should be deleted (Max-Age=0)
    const cookies = response.headers.getSetCookie?.() ?? [];
    const deleteCookie = cookies.find((c: string) =>
      c.startsWith("soleur_github_resolve=") && c.includes("Max-Age=0"),
    );
    expect(deleteCookie).toBeDefined();
  });
});
