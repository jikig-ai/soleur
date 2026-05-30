process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// feat-skip-api-key-onboarding (#4642) — AC3 (callback surface). After T&C is
// accepted, the OAuth callback routes to /setup-key ONLY when the user has no
// effective key AND has not skipped. A keyless-but-skipped user, and an
// effective-key user, proceed to the repo/dashboard path — never /setup-key.

const {
  mockExchangeCodeForSession,
  mockGetUser,
  mockServiceFrom,
  mockUserHasEffectiveByokKey,
} = vi.hoisted(() => ({
  mockExchangeCodeForSession: vi.fn(),
  mockGetUser: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockUserHasEffectiveByokKey: vi.fn(),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: vi.fn(() => ({
    auth: { getUser: mockGetUser, exchangeCodeForSession: mockExchangeCodeForSession },
  })),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));

vi.mock("@/server/byok-resolver", () => ({
  userHasEffectiveByokKey: mockUserHasEffectiveByokKey,
}));

vi.mock("@/server/workspace", () => ({ provisionWorkspace: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (fn: () => unknown) => fn(),
  getCurrentScope: () => ({ setUser: vi.fn() }),
  captureException: vi.fn(),
}));
vi.mock("@/lib/auth/resolve-origin", () => ({ resolveOrigin: () => "https://app.soleur.ai" }));
vi.mock("@/lib/legal/tc-version", () => ({ TC_VERSION: "2026-01-01" }));
vi.mock("@/server/userid-pseudonymize", () => ({ hashUserIdValue: (id: string) => `hash:${id}` }));

import { GET } from "@/app/(auth)/callback/route";

const USER_ID = "cb-user-uuid";

function makeRequest(): NextRequest {
  return new NextRequest(new URL("https://app.soleur.ai/callback?code=oauth-code"), {
    method: "GET",
    headers: {
      "x-forwarded-host": "app.soleur.ai",
      "x-forwarded-proto": "https",
      host: "app.soleur.ai",
    },
  });
}

// Single users row covering BOTH service-client reads: ensureWorkspaceProvisioned
// (workspace_status, tc_accepted_version) and the key-gate (repo_status,
// setup_key_skipped_at). The mock ignores selected columns and returns the row.
function stubUsersRow(row: Record<string, unknown>) {
  mockServiceFrom.mockImplementation(() => ({
    select: () => ({ eq: () => ({ single: () => Promise.resolve({ data: row, error: null }) }) }),
    update: () => ({ eq: () => Promise.resolve({ error: null }) }),
    upsert: () => Promise.resolve({ error: null }),
  }));
}

function pathOf(res: Response): string {
  return new URL(res.headers.get("location")!).pathname;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockExchangeCodeForSession.mockResolvedValue({ error: null });
  mockGetUser.mockResolvedValue({ data: { user: { id: USER_ID, email: "u@x.com" } } });
});

describe("GET /callback — setup-key gate (AC3)", () => {
  test("keyless, not skipped → /setup-key", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubUsersRow({
      workspace_status: "ready",
      tc_accepted_version: "2026-01-01",
      repo_status: "connected",
      setup_key_skipped_at: null,
    });
    expect(pathOf(await GET(makeRequest()))).toBe("/setup-key");
  });

  test("keyless but skipped → repo/dashboard path, never /setup-key", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(false);
    stubUsersRow({
      workspace_status: "ready",
      tc_accepted_version: "2026-01-01",
      repo_status: "connected",
      setup_key_skipped_at: "2026-05-30T00:00:00Z",
    });
    expect(pathOf(await GET(makeRequest()))).toBe("/dashboard");
  });

  test("effective key, repo not connected → /connect-repo (not /setup-key)", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    stubUsersRow({
      workspace_status: "ready",
      tc_accepted_version: "2026-01-01",
      repo_status: "not_connected",
      setup_key_skipped_at: null,
    });
    expect(pathOf(await GET(makeRequest()))).toBe("/connect-repo");
  });

  test("passes onErrorReturn:true (fail-open) to the effective-key resolver", async () => {
    mockUserHasEffectiveByokKey.mockResolvedValue(true);
    stubUsersRow({
      workspace_status: "ready",
      tc_accepted_version: "2026-01-01",
      repo_status: "connected",
      setup_key_skipped_at: null,
    });
    await GET(makeRequest());
    expect(mockUserHasEffectiveByokKey).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({ onErrorReturn: true }),
    );
  });
});
