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

// Mock global fetch for GitHub API calls
const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;

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
    globalThis.fetch = mockFetch as unknown as typeof fetch;

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
  });

  afterEach(() => {
    globalThis.fetch = originalFetch;
  });

  test("stores github_username and redirects on valid code+state", async () => {
    const stateNonce = "test-state-123";

    // Mock GitHub token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    // Mock GET /user
    mockFetch.mockResolvedValueOnce({
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

    mockFetch.mockResolvedValueOnce({
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

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    mockFetch.mockResolvedValueOnce({
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

    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ access_token: "ghu_test_token", token_type: "bearer" }),
    });
    mockFetch.mockResolvedValueOnce({
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
