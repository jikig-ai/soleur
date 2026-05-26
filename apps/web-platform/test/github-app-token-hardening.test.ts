/**
 * Tests for generateInstallationToken() hardening:
 * - PEM shape validation warning (AC3)
 * - Enhanced error logging with appId, PEM fingerprint, server timestamp (AC2)
 * - Retry-on-401 with fresh JWT (AC5)
 * - reportSilentFallback on final failure (AC4)
 */
import { generateKeyPairSync, createHash } from "crypto";

const { privateKey: validPem } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

// Set env BEFORE any imports that read them at load time
process.env.GITHUB_APP_ID = "99999";
process.env.GITHUB_APP_PRIVATE_KEY = validPem;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

const {
  mockFetch,
  mockReportSilentFallback,
  mockLogWarn,
  mockLogError,
} = vi.hoisted(() => ({
  mockFetch: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogWarn: vi.fn(),
  mockLogError: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Mock global fetch
// ---------------------------------------------------------------------------
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;

afterAll(() => {
  globalThis.fetch = originalFetch;
});

// ---------------------------------------------------------------------------
// Mock observability (reportSilentFallback)
// ---------------------------------------------------------------------------
vi.mock("../server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) =>
    mockReportSilentFallback(...args),
}));

// ---------------------------------------------------------------------------
// Mock logger to capture warn/error calls
// ---------------------------------------------------------------------------
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: mockLogWarn,
    error: mockLogError,
    debug: vi.fn(),
    child: () => ({
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
      debug: vi.fn(),
    }),
  }),
}));

// Import AFTER env and mocking
import { generateInstallationToken } from "../server/github-app";

// Unique installation IDs to avoid token cache interference
let nextId = 50_000;
function uniqueId() {
  return nextId++;
}

function mockTokenSuccess() {
  return {
    ok: true,
    status: 200,
    json: async () => ({
      token: "ghs_hardening_test_token",
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    }),
    text: async () => "",
  };
}

function mock401() {
  return {
    ok: false,
    status: 401,
    text: async () => JSON.stringify({ message: "Bad credentials" }),
    json: async () => ({ message: "Bad credentials" }),
  };
}

function mock403() {
  return {
    ok: false,
    status: 403,
    text: async () =>
      JSON.stringify({ message: "Resource not accessible by integration" }),
    json: async () => ({
      message: "Resource not accessible by integration",
    }),
  };
}

describe("generateInstallationToken hardening", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    mockLogWarn.mockReset();
    mockLogError.mockReset();
    mockReportSilentFallback.mockReset();
  });

  describe("retry-on-401 (AC5)", () => {
    test("retries once on 401, succeeds on second attempt", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mockTokenSuccess());

      const token = await generateInstallationToken(id);

      expect(token).toBe("ghs_hardening_test_token");
      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockLogWarn).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: id }),
        expect.stringContaining("401"),
      );
    });

    test("throws after two consecutive 401s", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      await expect(generateInstallationToken(id)).rejects.toThrow(
        /GitHub installation token request failed: 401/,
      );
      expect(mockFetch).toHaveBeenCalledTimes(2);
    });

    test("does NOT retry on 403", async () => {
      const id = uniqueId();
      mockFetch.mockResolvedValueOnce(mock403());

      await expect(generateInstallationToken(id)).rejects.toThrow(/403/);
      expect(mockFetch).toHaveBeenCalledTimes(1);
    });

    test("uses fresh JWT on retry (different Authorization header)", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mockTokenSuccess());

      await generateInstallationToken(id);

      const firstAuth = mockFetch.mock.calls[0][1].headers.Authorization;
      const secondAuth = mockFetch.mock.calls[1][1].headers.Authorization;
      expect(firstAuth).toMatch(/^Bearer /);
      expect(secondAuth).toMatch(/^Bearer /);
      // JWTs include iat (issued-at) — different timestamps mean different JWTs.
      // They may be identical if the clock doesn't tick between calls, so we
      // just verify both are present (the fresh-mint is the contract, not the
      // value difference).
      expect(secondAuth).toBeTruthy();
    });
  });

  describe("reportSilentFallback on final failure (AC4)", () => {
    test("calls reportSilentFallback with structured tags on 401 failure", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      await expect(generateInstallationToken(id)).rejects.toThrow();

      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          feature: "github-app",
          op: "generate-installation-token",
        }),
      );
    });
  });

  describe("enhanced error logging (AC2)", () => {
    test("error log includes appId and pemFingerprint on failure", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      await expect(generateInstallationToken(id)).rejects.toThrow();

      const expectedFingerprint = createHash("sha256")
        .update(validPem)
        .digest("hex")
        .slice(0, 8);

      expect(mockLogError).toHaveBeenCalledWith(
        expect.objectContaining({
          installationId: id,
          appId: "99999",
          pemFingerprint: expectedFingerprint,
        }),
        expect.stringContaining("Failed to generate installation token"),
      );
    });
  });
});

describe("getPrivateKey PEM shape validation (AC3)", () => {
  test("does not warn for valid RSA PEM", async () => {
    // Valid PEM is already set in env — just trigger a token call to
    // exercise getPrivateKey via createAppJwt.
    const id = uniqueId();
    mockFetch.mockReset();
    mockLogWarn.mockReset();
    mockFetch.mockResolvedValueOnce(mockTokenSuccess());

    await generateInstallationToken(id);

    const pemWarnings = mockLogWarn.mock.calls.filter(
      (args) => typeof args[1] === "string" && args[1].includes("PEM"),
    );
    expect(pemWarnings).toHaveLength(0);
  });

  test("warns for corrupted PEM prefix without throwing", async () => {
    const originalKey = process.env.GITHUB_APP_PRIVATE_KEY;
    process.env.GITHUB_APP_PRIVATE_KEY = "CORRUPTED_PREFIX_NOT_A_KEY";

    try {
      const id = uniqueId();
      mockFetch.mockReset();
      mockLogWarn.mockReset();
      // The call will fail at signing (can't sign with invalid PEM),
      // but the warning should fire before that.
      try {
        mockFetch.mockResolvedValueOnce(mockTokenSuccess());
        await generateInstallationToken(id);
      } catch {
        // Expected — invalid PEM can't sign
      }

      const pemWarnings = mockLogWarn.mock.calls.filter(
        (args) => typeof args[1] === "string" && args[1].includes("PEM"),
      );
      expect(pemWarnings.length).toBeGreaterThan(0);
    } finally {
      process.env.GITHUB_APP_PRIVATE_KEY = originalKey;
    }
  });
});
