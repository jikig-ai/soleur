/**
 * Mint-time observability tests (feat-one-shot-concierge-gh-403-token-diagnosis).
 *
 * AC1: generateInstallationToken logs `installationId`, `repositorySelection`,
 * and sorted `permissionKeys` at log.info on every mint, and NEVER logs
 * `data.token` (hr-github-app-auth-not-pat). These logs make the next 403
 * self-diagnosing — a wrong-installation token surfaces its
 * repository_selection + granted-permission keys without a remote shell.
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

const { mockLogInfo } = vi.hoisted(() => ({ mockLogInfo: vi.fn() }));

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: mockLogInfo,
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
import { loadGithubFixture } from "./fixtures/github/load";

let nextId = 90_000;
function uniqueId() {
  return nextId++;
}

describe("generateInstallationToken — mint-time observability", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    mockLogInfo.mockReset();
  });

  test("logs installationId, repositorySelection, sorted permissionKeys; never logs token", async () => {
    const installationId = uniqueId();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        ...loadGithubFixture("installation-access-token"),
        // Distinct sentinel value the test asserts is NEVER logged.
        token: "ghs_super_secret_value",
        expires_at: new Date(Date.now() + 3_600_000).toISOString(),
      }),
      text: async () => "",
    });

    await generateInstallationToken(installationId);

    const mintLog = mockLogInfo.mock.calls.find(
      (c) => c[1] === "Minted installation token",
    );
    expect(mintLog, "expected a 'Minted installation token' log.info").toBeTruthy();

    const fields = mintLog![0] as Record<string, unknown>;
    expect(fields.installationId).toBe(installationId);
    expect(fields.repositorySelection).toBe("selected");
    // sorted, de-duplicated permission KEYS only — never values
    expect(fields.permissionKeys).toEqual(["contents", "issues", "metadata"]);

    // hr-github-app-auth-not-pat: the secret token must NEVER appear in any
    // log.info argument (neither as a field value nor inside the message).
    const serialized = JSON.stringify(mockLogInfo.mock.calls);
    expect(serialized).not.toContain("ghs_super_secret_value");
  });

  test("tolerates a response with no permissions/repository_selection (older shape)", async () => {
    const installationId = uniqueId();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        token: "ghs_minimal",
        expires_at: new Date(Date.now() + 3_600_000).toISOString(),
      }),
      text: async () => "",
    });

    await generateInstallationToken(installationId);

    const mintLog = mockLogInfo.mock.calls.find(
      (c) => c[1] === "Minted installation token",
    );
    expect(mintLog).toBeTruthy();
    const fields = mintLog![0] as Record<string, unknown>;
    expect(fields.installationId).toBe(installationId);
    expect(fields.repositorySelection).toBeUndefined();
    expect(fields.permissionKeys).toEqual([]);
  });
});
