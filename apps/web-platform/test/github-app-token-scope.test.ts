/**
 * Least-privilege installation-token scope (#5046 PR-1 / feat-tier2-cron-egress-firewall).
 *
 * `generateInstallationToken` gained optional `permissions` / `repositories`
 * that narrow the minted token via the access_tokens POST body. The token cache
 * is keyed on `installationId` ALONE in the pre-fix code — so a narrowed cron
 * token would be returned to the ~10 broad-scope callers that share the same
 * installation id (and vice versa), a silent privilege collision. These tests
 * pin:
 *   1. an unscoped mint posts NO body (byte-for-byte backward compatible) and
 *      caches under the bare installation id;
 *   2. a scoped mint posts `{ permissions, repositories }` in the body;
 *   3. THE COLLISION FIX: a scoped request after an unscoped one for the SAME
 *      installation id does NOT return the cached broad token — it re-mints
 *      (distinct cache key). And the reverse direction.
 */
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: () => ({
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    }),
  }),
}));

import { generateInstallationToken } from "../server/github-app";

// Each test uses a fresh installation id so the module-level token cache (no
// reset hook is exported) never bleeds across tests.
let nextId = 70_000;
function uniqueId() {
  return nextId++;
}

function okTokenResponse(token: string) {
  return {
    ok: true,
    status: 200,
    json: async () => ({
      token,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
      repository_selection: "selected",
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
    }),
    text: async () => "",
  };
}

function lastFetchBody(): unknown {
  const call = mockFetch.mock.calls.at(-1)!;
  const init = call[1] as RequestInit;
  return init.body ? JSON.parse(init.body as string) : undefined;
}

describe("generateInstallationToken — least-privilege scope", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test("unscoped mint posts NO body (backward compatible)", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_broad"));

    const token = await generateInstallationToken(id);

    expect(token).toBe("ghs_broad");
    expect(mockFetch).toHaveBeenCalledTimes(1);
    expect(lastFetchBody()).toBeUndefined();
  });

  test("scoped mint posts { permissions, repositories } in the body", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_narrow"));

    const token = await generateInstallationToken(id, {
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    });

    expect(token).toBe("ghs_narrow");
    expect(lastFetchBody()).toEqual({
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    });
  });

  test("COLLISION FIX: a scoped request does NOT return the cached broad token (same installation id)", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_broad"));
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_narrow"));

    const broad = await generateInstallationToken(id); // caches under bare id
    const narrow = await generateInstallationToken(id, {
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    });

    expect(broad).toBe("ghs_broad");
    // Pre-fix (cache keyed on installationId alone) this returns "ghs_broad"
    // from cache and never re-mints — the silent over-privilege bug.
    expect(narrow).toBe("ghs_narrow");
    expect(mockFetch).toHaveBeenCalledTimes(2);
    expect(lastFetchBody()).toEqual({
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    });
  });

  test("COLLISION FIX (reverse): an unscoped request does NOT return the cached narrow token", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_narrow"));
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_broad"));

    const narrow = await generateInstallationToken(id, {
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    });
    const broad = await generateInstallationToken(id);

    expect(narrow).toBe("ghs_narrow");
    expect(broad).toBe("ghs_broad");
    expect(mockFetch).toHaveBeenCalledTimes(2);
    expect(lastFetchBody()).toBeUndefined();
  });

  test("a second scoped request with the SAME scope is served from cache (no re-mint)", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(okTokenResponse("ghs_narrow"));

    const scope = {
      permissions: { contents: "write", issues: "write", pull_requests: "write" },
      repositories: ["soleur"],
    };
    const first = await generateInstallationToken(id, scope);
    const second = await generateInstallationToken(id, scope);

    expect(first).toBe("ghs_narrow");
    expect(second).toBe("ghs_narrow");
    expect(mockFetch).toHaveBeenCalledTimes(1);
  });
});
