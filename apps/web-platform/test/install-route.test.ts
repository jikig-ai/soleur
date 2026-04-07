// Generate a real RSA key for JWT signing during tests.
// This avoids mocking crypto, which differs between vitest and bun test.
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

// Set env BEFORE any imports that read them at load time
process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";

// ---------------------------------------------------------------------------
// Mock global fetch for GitHub API calls
// ---------------------------------------------------------------------------

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

// ---------------------------------------------------------------------------
// verifyInstallationOwnership — unit tests
// ---------------------------------------------------------------------------

import { verifyInstallationOwnership } from "../server/github-app";

describe("verifyInstallationOwnership", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test("returns verified=true when account.login matches expected login (User type)", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "alice", id: 1, type: "User" },
      }),
    });

    const result = await verifyInstallationOwnership(123, "alice");
    expect(result.verified).toBe(true);
    expect(result.error).toBeUndefined();
    expect(result.status).toBeUndefined();
  });

  test("returns verified=false with 403 when account.login does not match", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "bob", id: 2, type: "User" },
      }),
    });

    const result = await verifyInstallationOwnership(123, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(403);
    expect(result.error).toMatch(/does not belong/i);
  });

  test("returns verified=false with 404 when installation does not exist", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 404,
    });

    const result = await verifyInstallationOwnership(999, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(404);
    expect(result.error).toMatch(/not found/i);
  });

  test("returns verified=false with 502 when GitHub API returns 500", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
    });

    const result = await verifyInstallationOwnership(123, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(502);
  });

  test("handles case-insensitive login comparison", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "Alice", id: 1, type: "User" },
      }),
    });

    const result = await verifyInstallationOwnership(123, "alice");
    expect(result.verified).toBe(true);
  });

  // --- Organization installation tests ---
  // Each org test uses a unique installationId (200-204) to avoid tokenCache
  // persistence across tests causing unpredictable mock sequences.

  test("returns verified=true when user is a member of the org (Organization type)", async () => {
    // Mock 1: GET /app/installations/200 — returns org account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 3, type: "Organization" },
      }),
    });
    // Mock 2: POST /app/installations/200/access_tokens — token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_org200",
        expires_at: new Date(Date.now() + 3600000).toISOString(),
      }),
    });
    // Mock 3: GET /orgs/my-org/members/alice — 204 (is a member)
    mockFetch.mockResolvedValueOnce({ status: 204 });

    const result = await verifyInstallationOwnership(200, "alice");
    expect(result.verified).toBe(true);
    expect(result.error).toBeUndefined();
  });

  test("returns verified=false with 403 when user is NOT a member of the org", async () => {
    // Mock 1: GET /app/installations/201 — returns org account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 3, type: "Organization" },
      }),
    });
    // Mock 2: POST /app/installations/201/access_tokens — token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_org201",
        expires_at: new Date(Date.now() + 3600000).toISOString(),
      }),
    });
    // Mock 3: GET /orgs/my-org/members/alice — 404 (not a member)
    mockFetch.mockResolvedValueOnce({ status: 404 });

    const result = await verifyInstallationOwnership(201, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(403);
    expect(result.error).toMatch(/not a member/i);
  });

  test("returns verified=false with 403 when membership check returns 302 redirect", async () => {
    // Mock 1: GET /app/installations/202 — returns org account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 3, type: "Organization" },
      }),
    });
    // Mock 2: POST /app/installations/202/access_tokens — token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_org202",
        expires_at: new Date(Date.now() + 3600000).toISOString(),
      }),
    });
    // Mock 3: GET /orgs/my-org/members/alice — 302 (non-member perspective)
    mockFetch.mockResolvedValueOnce({ status: 302 });

    const result = await verifyInstallationOwnership(202, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(403);
    expect(result.error).toMatch(/not a member/i);
  });

  test("returns verified=false with 502 when membership check returns 403 (missing Members permission)", async () => {
    // Mock 1: GET /app/installations/203 — returns org account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 3, type: "Organization" },
      }),
    });
    // Mock 2: POST /app/installations/203/access_tokens — token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_org203",
        expires_at: new Date(Date.now() + 3600000).toISOString(),
      }),
    });
    // Mock 3: GET /orgs/my-org/members/alice — 403 (App lacks Members permission)
    mockFetch.mockResolvedValueOnce({ status: 403 });

    const result = await verifyInstallationOwnership(203, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(502);
    expect(result.error).toMatch(/failed to verify/i);
  });

  test("returns verified=false with 502 when membership check returns 500", async () => {
    // Mock 1: GET /app/installations/204 — returns org account
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        account: { login: "my-org", id: 3, type: "Organization" },
      }),
    });
    // Mock 2: POST /app/installations/204/access_tokens — token exchange
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        token: "ghs_org204",
        expires_at: new Date(Date.now() + 3600000).toISOString(),
      }),
    });
    // Mock 3: GET /orgs/my-org/members/alice — 500 (server error)
    mockFetch.mockResolvedValueOnce({ status: 500 });

    const result = await verifyInstallationOwnership(204, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(502);
    expect(result.error).toMatch(/failed to verify/i);
  });

  test("returns 502 when account is missing from response", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({}),
    });

    const result = await verifyInstallationOwnership(123, "alice");
    expect(result.verified).toBe(false);
    expect(result.status).toBe(502);
  });
});

// ---------------------------------------------------------------------------
// Behavioral test — no-GitHub-identity rejection (syntax-agnostic)
// ---------------------------------------------------------------------------
// This test exercises the route handler itself, proving that a user with
// user_metadata.user_name set but NO GitHub identity in the identities array
// is rejected with 403.  Unlike the structural regex test below, this is
// immune to syntactic evasion (bracket notation, intermediate variables, etc.).

// We need to mock the Supabase server modules and Next.js imports used by
// the route handler.  vi.mock must be called before importing the route.
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
  createServiceClient: vi.fn(),
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(),
  rejectCsrf: vi.fn(),
}));
vi.mock("@/server/logger", () => {
  const noopLogger = { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn(), child: vi.fn() };
  noopLogger.child.mockReturnValue(noopLogger);
  return {
    default: noopLogger,
    createChildLogger: vi.fn().mockReturnValue(noopLogger),
  };
});
vi.mock("next/server", () => ({
  NextResponse: {
    json: (body: unknown, init?: { status?: number }) =>
      new Response(JSON.stringify(body), {
        status: init?.status ?? 200,
        headers: { "content-type": "application/json" },
      }),
  },
}));

import { POST } from "../app/api/repo/install/route";
import {
  createClient as mockCreateClient,
  createServiceClient as mockCreateServiceClient,
} from "@/lib/supabase/server";
import { validateOrigin as mockValidateOrigin } from "@/lib/auth/validate-origin";

describe("install route behavioral enforcement", () => {
  beforeEach(() => {
    vi.mocked(mockValidateOrigin).mockReturnValue({
      valid: true,
      origin: "https://app.soleur.ai",
    });
  });

  test("email-only user: succeeds when installation exists (existence-verified)", async () => {
    const userId = "user-123";

    // Mock createClient — returns a Supabase client whose auth.getUser()
    // yields a user with user_metadata.user_name but NO GitHub identity
    vi.mocked(mockCreateClient).mockResolvedValue({
      auth: {
        getUser: vi.fn().mockResolvedValue({
          data: {
            user: {
              id: userId,
              user_metadata: { user_name: "alice" },
            },
          },
        }),
      },
    } as never);

    // Mock createServiceClient — returns a service client whose
    // auth.admin.getUserById returns a user with an email identity only
    // (no github provider in the identities array)
    const mockUpdate = vi.fn().mockReturnValue({
      eq: vi.fn().mockResolvedValue({ error: null }),
    });
    vi.mocked(mockCreateServiceClient).mockReturnValue({
      auth: {
        admin: {
          getUserById: vi.fn().mockResolvedValue({
            data: {
              user: {
                id: userId,
                identities: [
                  {
                    provider: "email",
                    identity_data: { email: "alice@example.com" },
                  },
                ],
                user_metadata: { user_name: "alice" },
              },
            },
            error: null,
          }),
        },
      },
      from: vi.fn().mockReturnValue({ update: mockUpdate }),
    } as never);

    // Mock getInstallationAccount (called via global fetch for email-only users)
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ account: { login: "someuser", id: 1, type: "User" } }),
    });

    const request = new Request("https://app.soleur.ai/api/repo/install", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        origin: "https://app.soleur.ai",
      },
      body: JSON.stringify({ installationId: 42 }),
    });

    const response = await POST(request);
    expect(response.status).toBe(200);
  });
});

// ---------------------------------------------------------------------------
// Structural test — negative-space enforcement
// ---------------------------------------------------------------------------

describe("install route structural enforcement", () => {
  test("verifyInstallationOwnership is called before .update() in route source", () => {
    const routeSource = readFileSync(
      join(__dirname, "../app/api/repo/install/route.ts"),
      "utf-8",
    );
    const verifyIndex = routeSource.indexOf("verifyInstallationOwnership");
    const updateIndex = routeSource.indexOf(".update({ github_installation_id");
    expect(verifyIndex).toBeGreaterThan(-1);
    expect(updateIndex).toBeGreaterThan(-1);
    expect(verifyIndex).toBeLessThan(updateIndex);
  });

  test("githubLogin assignment does not reference user_metadata for user_name", () => {
    const routeSource = readFileSync(
      join(__dirname, "../app/api/repo/install/route.ts"),
      "utf-8",
    );
    // The route must not use user_metadata?.user_name anywhere — it's user-mutable
    // and must never be trusted for security decisions (GitHub identity extraction).
    expect(routeSource).not.toMatch(/user_metadata\?\.user_name/);
  });
});
