/**
 * Tests for generateInstallationToken() hardening:
 * - PEM shape validation warning (AC3)
 * - Enhanced error logging with appId, PEM fingerprint (AC2)
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

import { describe, test, expect, vi, beforeEach, afterEach, afterAll } from "vitest";

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

function mock500() {
  return {
    ok: false,
    status: 500,
    text: async () => JSON.stringify({ message: "Internal Server Error" }),
    json: async () => ({ message: "Internal Server Error" }),
  };
}

describe("generateInstallationToken hardening", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockFetch.mockReset();
    mockLogWarn.mockReset();
    mockLogError.mockReset();
    mockReportSilentFallback.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("retry-on-401 (AC5)", () => {
    test("retries once on 401, succeeds on second attempt", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mockTokenSuccess());

      const promise = generateInstallationToken(id);
      await vi.advanceTimersByTimeAsync(1_000);
      const token = await promise;

      expect(token).toBe("ghs_hardening_test_token");
      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockLogWarn).toHaveBeenCalledWith(
        expect.objectContaining({ installationId: id }),
        expect.stringContaining("401"),
      );
    });

    test("throws after three consecutive 401s (2 retries, exp backoff)", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      const promise = generateInstallationToken(id);
      // Suppress unhandled rejection — assertion below still catches the error
      promise.catch(() => {});
      await vi.advanceTimersByTimeAsync(1_000); // attempt 0 backoff
      await vi.advanceTimersByTimeAsync(2_000); // attempt 1 backoff

      await expect(promise).rejects.toThrow(
        /GitHub installation token request failed: 401/,
      );
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });

    test("succeeds on 3rd attempt (2 retries)", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mockTokenSuccess());

      const promise = generateInstallationToken(id);
      await vi.advanceTimersByTimeAsync(1_000);
      await vi.advanceTimersByTimeAsync(2_000);
      const token = await promise;

      expect(token).toBe("ghs_hardening_test_token");
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });

    test("does NOT retry on 403", async () => {
      const id = uniqueId();
      mockFetch.mockResolvedValueOnce(mock403());

      await expect(generateInstallationToken(id)).rejects.toThrow(/403/);
      expect(mockFetch).toHaveBeenCalledTimes(1);
    });

    test("uses fresh JWT on retry (calls createAppJwt twice)", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mockTokenSuccess());

      const promise = generateInstallationToken(id);
      await vi.advanceTimersByTimeAsync(1_000);
      await promise;

      const firstAuth = mockFetch.mock.calls[0][1].headers.Authorization;
      const secondAuth = mockFetch.mock.calls[1][1].headers.Authorization;
      expect(firstAuth).toMatch(/^Bearer /);
      expect(secondAuth).toMatch(/^Bearer /);
      // A fresh JWT is minted per attempt: the 1s backoff advanced the (fake)
      // clock, so the retry's iat must be strictly later than the first — a
      // re-used/cached JWT would fail this. This is the property that makes
      // retrying a clock-skew-rejected JWT meaningful.
      const decodeIat = (auth: string) =>
        (
          JSON.parse(
            Buffer.from(auth.slice("Bearer ".length).split(".")[1], "base64url").toString(),
          ) as { iat: number }
        ).iat;
      expect(decodeIat(secondAuth)).toBeGreaterThan(decodeIat(firstAuth));
    });

    test("throws with correct status after 401 followed by 500", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock500());

      const promise = generateInstallationToken(id);
      // Suppress unhandled rejection — assertion below still catches the error
      promise.catch(() => {});
      await vi.advanceTimersByTimeAsync(1_000);

      await expect(promise).rejects.toThrow(/500/);
      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockReportSilentFallback).toHaveBeenCalled();
    });
  });

  describe("reportSilentFallback on final failure (AC4)", () => {
    test("calls reportSilentFallback with structured tags on 401 failure", async () => {
      const id = uniqueId();
      mockFetch
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      const promise = generateInstallationToken(id);
      // Suppress unhandled rejection — assertion below still catches the error
      promise.catch(() => {});
      await vi.advanceTimersByTimeAsync(1_000);
      await vi.advanceTimersByTimeAsync(2_000);
      await expect(promise).rejects.toThrow();

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
        .mockResolvedValueOnce(mock401())
        .mockResolvedValueOnce(mock401());

      const promise = generateInstallationToken(id);
      // Suppress unhandled rejection — assertion below still catches the error
      promise.catch(() => {});
      await vi.advanceTimersByTimeAsync(1_000);
      await vi.advanceTimersByTimeAsync(2_000);
      await expect(promise).rejects.toThrow();

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
  beforeEach(() => {
    vi.useFakeTimers();
    mockFetch.mockReset();
    mockLogWarn.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("does not warn for valid RSA PEM", async () => {
    const id = uniqueId();
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
      mockLogWarn.mockReset();
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
      // Verify safe metadata — no raw PEM content logged
      expect(pemWarnings[0][0]).toHaveProperty("rawLength");
      expect(pemWarnings[0][0]).toHaveProperty("hasBeginMarker");
      expect(pemWarnings[0][0]).not.toHaveProperty("prefix");
    } finally {
      process.env.GITHUB_APP_PRIVATE_KEY = originalKey;
    }
  });
});

describe("JWT exp margin (clock-skew tolerance, #122537945)", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockFetch.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("minted JWT exp leaves margin below GitHub's 600s max", async () => {
    const id = uniqueId();
    mockFetch.mockResolvedValueOnce(mockTokenSuccess());

    await generateInstallationToken(id);

    const auth = mockFetch.mock.calls[0][1].headers.Authorization as string;
    expect(auth).toMatch(/^Bearer /);
    const jwt = auth.slice("Bearer ".length);
    const payload = JSON.parse(
      Buffer.from(jwt.split(".")[1], "base64url").toString(),
    ) as { iat: number; exp: number };

    const nowSeconds = Math.floor(Date.now() / 1000);
    // exp must leave >=60s margin below GitHub's 600s ceiling to absorb
    // positive server-clock skew (the root cause of Sentry issue 122537945).
    expect(payload.exp - nowSeconds).toBeLessThanOrEqual(540);
    expect(payload.exp - nowSeconds).toBeGreaterThan(0);
    // total JWT lifetime (exp - iat) is exactly 600s (iat now-60, exp now+540)
    // — pins both directions: too-long would re-trip GitHub's 600s ceiling, and
    // a too-short window would starve slow exchanges.
    expect(payload.exp - payload.iat).toBe(600);
    // iat is backdated (negative skew preserved).
    expect(payload.iat).toBeLessThanOrEqual(nowSeconds);
  });
});
