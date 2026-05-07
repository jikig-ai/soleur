import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// ---------------------------------------------------------------------------
// Mock @supabase/ssr BEFORE importing the route. The mock captures the
// `cookies.setAll` callback that the route passes in, then invokes it from
// `signInWithPassword` to simulate Supabase's real cookie-write behavior.
// This is the lever the cookie-writer regression test (R3) pulls on.
// ---------------------------------------------------------------------------

type CookieSpec = { name: string; value: string; options?: Record<string, unknown> };

let capturedSetAll: ((cookies: CookieSpec[]) => void) | null = null;
const mockSignInWithPassword = vi.fn();

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn((_url: string, _key: string, opts: { cookies: { setAll: (c: CookieSpec[]) => void } }) => {
    capturedSetAll = opts.cookies.setAll;
    return {
      auth: {
        signInWithPassword: mockSignInWithPassword,
      },
    };
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}));

// Force a stable Supabase URL so the mocked cookie name ref segment is
// predictable in assertions.
const FAKE_SUPABASE_REF = "abcdefghijklmnopqrst";
const FAKE_SUPABASE_URL = `https://${FAKE_SUPABASE_REF}.supabase.co`;
const FAKE_ANON_KEY = "anon-key-stub";

// ---------------------------------------------------------------------------

function makeFormRequest(body: Record<string, string>) {
  const params = new URLSearchParams(body);
  return new Request("http://localhost/api/auth/dev-signin", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
}

beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", FAKE_SUPABASE_URL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", FAKE_ANON_KEY);
  capturedSetAll = null;
  mockSignInWithPassword.mockReset();
});

afterEach(() => {
  vi.unstubAllEnvs();
});

async function importRoute() {
  // Re-import each test so module-top-level captures don't leak across cases.
  vi.resetModules();
  return import("../../app/api/auth/dev-signin/route");
}

describe("POST /api/auth/dev-signin — gate behaviour", () => {
  it("returns 404 in production even with FLAG_DEV_SIGNIN=1 and a valid slot", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    vi.stubEnv("DEV_USER_1_PASSWORD", "pw");
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));
    expect(res.status).toBe(404);
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
  });

  it("returns 404 under NODE_ENV=test even with FLAG_DEV_SIGNIN=1 (strict === \"development\")", async () => {
    vi.stubEnv("NODE_ENV", "test");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    vi.stubEnv("DEV_USER_1_PASSWORD", "pw");
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));
    expect(res.status).toBe(404);
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
  });

  it("returns 404 in development when FLAG_DEV_SIGNIN is unset", async () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", undefined);
    vi.stubEnv("DEV_USER_1_PASSWORD", "pw");
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));
    expect(res.status).toBe(404);
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
  });
});

describe("POST /api/auth/dev-signin — input validation", () => {
  beforeEach(() => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    vi.stubEnv("DEV_USER_1_PASSWORD", "pw1");
    vi.stubEnv("DEV_USER_2_PASSWORD", "pw2");
    vi.stubEnv("DEV_USER_3_PASSWORD", "pw3");
  });

  it.each([
    ["slot=4 (out of range)", { slot: "4" }],
    ["slot=0 (out of range)", { slot: "0" }],
    ["slot=x (NaN)", { slot: "x" }],
    ["slot missing", {}],
  ])("returns 400 for %s", async (_label, body) => {
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest(body));
    expect(res.status).toBe(400);
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
  });

  it("returns 500 when DEV_USER_<slot>_PASSWORD is unset; env-var key is scrubbed from response body", async () => {
    vi.stubEnv("DEV_USER_1_PASSWORD", undefined);
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));
    expect(res.status).toBe(500);
    const text = await res.text();
    // The env-var key MUST NOT leak — operators reading 500 logs would
    // otherwise see exactly which Doppler key is missing, and the dev
    // password names are the lever for an authenticated-as-dev-N session.
    expect(text).not.toContain("DEV_USER_1_PASSWORD");
    expect(text).not.toContain("DEV_USER_");
    expect(mockSignInWithPassword).not.toHaveBeenCalled();
  });
});

describe("POST /api/auth/dev-signin — happy path + cookie-writer regression (R3)", () => {
  beforeEach(() => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    vi.stubEnv("DEV_USER_1_PASSWORD", "pw1");

    mockSignInWithPassword.mockImplementation(async (credentials: { email: string; password: string }) => {
      // Simulate Supabase writing its auth-token cookie via the setAll
      // callback the route handed it. This is the load-bearing path:
      // if the route forgot to construct `response = NextResponse.redirect()`
      // BEFORE the supabase client (so `response.cookies.set` could be
      // called from setAll), the cookie below would land on the request
      // bag instead of the response — user authenticated server-side,
      // logged-out client-side, middleware bounces them back to /login.
      // See R3 in the plan + 2026-04-15 cookie-writer learnings.
      if (!capturedSetAll) {
        throw new Error("test bug: route did not pass cookies.setAll to createServerClient");
      }
      capturedSetAll([
        {
          name: `sb-${FAKE_SUPABASE_REF}-auth-token`,
          value: "encoded-jwt-value",
          options: { path: "/", httpOnly: true, sameSite: "lax", secure: false },
        },
      ]);
      return {
        data: { user: { id: "user-1", email: credentials.email }, session: { access_token: "x" } },
        error: null,
      };
    });
  });

  it("returns 303 redirect to / with Supabase auth-token Set-Cookie when slot is valid", async () => {
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));

    expect(res.status).toBe(303);
    // NextResponse.redirect requires an absolute URL; the route constructs
    // it via `new URL("/", request.url)` → the Location header is the
    // resolved absolute form, with pathname "/".
    const location = res.headers.get("location") ?? "";
    expect(new URL(location).pathname).toBe("/");

    const setCookie = res.headers.get("set-cookie") ?? "";
    expect(setCookie).toMatch(/sb-[a-z0-9]+-auth-token=/);

    expect(mockSignInWithPassword).toHaveBeenCalledTimes(1);
    expect(mockSignInWithPassword).toHaveBeenCalledWith({
      email: "dev-1@example.com",
      password: "pw1",
    });
  });

  it("dispatches the slot's email and password to signInWithPassword (slot 2)", async () => {
    vi.stubEnv("DEV_USER_2_PASSWORD", "pw2-secret");
    const { POST } = await importRoute();
    await POST(makeFormRequest({ slot: "2" }));

    expect(mockSignInWithPassword).toHaveBeenCalledWith({
      email: "dev-2@example.com",
      password: "pw2-secret",
    });
  });

  it("returns 500 when signInWithPassword returns an error; response body does not echo password", async () => {
    mockSignInWithPassword.mockImplementationOnce(async () => ({
      data: { user: null, session: null },
      error: { message: "Invalid login credentials", status: 400, name: "AuthApiError" },
    }));
    const { POST } = await importRoute();
    const res = await POST(makeFormRequest({ slot: "1" }));
    expect(res.status).toBe(500);
    const text = await res.text();
    expect(text).not.toContain("pw1");
    expect(text).not.toContain("DEV_USER_1_PASSWORD");
  });
});
