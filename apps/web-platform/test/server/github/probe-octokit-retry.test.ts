/**
 * Tests for createProbeOctokit() retry-on-401 hardening.
 *
 * The @octokit/auth-app library retries clock-skew and installation-token
 * 401s, but NOT App JWT decode failures ("A JSON web token could not be
 * decoded"). This test verifies createProbeOctokit() adds its own retry
 * for that gap.
 */
import { describe, test, expect, vi, beforeEach } from "vitest";
import { generateKeyPairSync } from "crypto";

process.env.GITHUB_APP_ID = "99999";
// Synthesized throwaway keypair (cq-test-fixtures-synthesized-only). Must be a
// real, parseable PEM: createProbeOctokit now canonicalizes the key via
// crypto.createPrivateKey().export() BEFORE constructing (the mocked) App, so a
// bogus "fake" body would throw at normalization and never reach the retry path.
process.env.GITHUB_APP_PRIVATE_KEY = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
}).privateKey as string;

const {
  mockRequest,
  mockGetInstallationOctokit,
  MockApp,
  warnSilentFallback,
  reportSilentFallback,
} = vi.hoisted(() => {
  const mockRequest = vi.fn();
  const mockGetInstallationOctokit = vi.fn();
  const MockApp = vi.fn().mockImplementation(() => ({
    octokit: { request: mockRequest },
    getInstallationOctokit: mockGetInstallationOctokit,
  }));
  return {
    mockRequest,
    mockGetInstallationOctokit,
    MockApp,
    warnSilentFallback: vi.fn(),
    reportSilentFallback: vi.fn(),
  };
});

vi.mock("@octokit/app", () => ({ App: MockApp }));
vi.mock("@/server/observability", () => ({
  warnSilentFallback,
  reportSilentFallback,
}));

import {
  createProbeOctokit,
} from "../../../server/github/probe-octokit";

function httpError(message: string, status: number): Error {
  const err = new Error(message);
  (err as Error & { status: number }).status = status;
  err.name = "HttpError";
  return err;
}

// Builds an @octokit/request-error-shaped error: `.status` + `.response`
// carrying lower-cased GitHub headers (`date`, `x-github-request-id`) and a
// `data` body. Mirrors what createProbeOctokit() reads for diagnostics.
function httpErrorWithResponse(
  message: string,
  status: number,
  resp: { date?: string; requestId?: string; body?: unknown },
): Error {
  const err = httpError(message, status);
  (err as Error & { response: unknown }).response = {
    status,
    headers: {
      date: resp.date,
      "x-github-request-id": resp.requestId,
    },
    data: resp.body,
  };
  return err;
}

describe("createProbeOctokit retry-on-401", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockRequest.mockReset();
    mockGetInstallationOctokit.mockReset();
    MockApp.mockClear();
    warnSilentFallback.mockClear();
    reportSilentFallback.mockClear();
  });

  test("succeeds on first attempt without retry", async () => {
    mockRequest.mockResolvedValueOnce({ data: { id: 12345 } });
    const fakeOctokit = { request: vi.fn() };
    mockGetInstallationOctokit.mockResolvedValueOnce(fakeOctokit);

    const result = await createProbeOctokit();

    expect(result).toBe(fakeOctokit);
    expect(MockApp).toHaveBeenCalledTimes(1);
    expect(mockRequest).toHaveBeenCalledTimes(1);
  });

  test("retries once on 401 JWT decode failure, succeeds on second attempt", async () => {
    const err401 = httpError(
      "A JSON web token could not be decoded",
      401,
    );
    mockRequest
      .mockRejectedValueOnce(err401)
      .mockResolvedValueOnce({ data: { id: 12345 } });
    const fakeOctokit = { request: vi.fn() };
    mockGetInstallationOctokit.mockResolvedValueOnce(fakeOctokit);

    const promise = createProbeOctokit();
    await vi.advanceTimersByTimeAsync(1_000);
    const result = await promise;

    expect(result).toBe(fakeOctokit);
    // Two App instances created — fresh JWT on retry
    expect(MockApp).toHaveBeenCalledTimes(2);
    expect(mockRequest).toHaveBeenCalledTimes(2);
  });

  test("retries twice on consecutive 401s, succeeds on third attempt", async () => {
    const err401 = httpError("A JSON web token could not be decoded", 401);
    mockRequest
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401)
      .mockResolvedValueOnce({ data: { id: 12345 } });
    const fakeOctokit = { request: vi.fn() };
    mockGetInstallationOctokit.mockResolvedValueOnce(fakeOctokit);

    const promise = createProbeOctokit();
    // Pin the EXACT backoff schedule (1s, then 2s = BASE_DELAY_MS * 2 ** i),
    // not just total elapsed time. Asserting attempt counts at the boundaries
    // catches a regression in PROBE_JWT_BASE_DELAY_MS or the exponent that a
    // coarse advance(3_000) would silently pass.
    await vi.advanceTimersByTimeAsync(999);
    expect(mockRequest).toHaveBeenCalledTimes(1); // 1s timer not yet fired
    await vi.advanceTimersByTimeAsync(1);
    expect(mockRequest).toHaveBeenCalledTimes(2); // second attempt at exactly 1s
    await vi.advanceTimersByTimeAsync(1_999);
    expect(mockRequest).toHaveBeenCalledTimes(2); // 2s timer not yet fired
    await vi.advanceTimersByTimeAsync(1);
    const result = await promise;

    expect(result).toBe(fakeOctokit); // third attempt at exactly +2s
    // Three App instances — fresh JWT per attempt.
    expect(MockApp).toHaveBeenCalledTimes(3);
    expect(mockRequest).toHaveBeenCalledTimes(3);
  });

  test("throws after three consecutive 401s (3-attempt budget)", async () => {
    const err401 = httpError(
      "A JSON web token could not be decoded",
      401,
    );
    mockRequest
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401);

    const promise = createProbeOctokit();
    // Attach rejection handler before advancing timers to prevent
    // Node's unhandled-rejection detector from racing the assertion.
    const caught = promise.catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(1_000);
    await vi.advanceTimersByTimeAsync(2_000);
    const err = await caught;

    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toBe(
      "A JSON web token could not be decoded",
    );
    expect(MockApp).toHaveBeenCalledTimes(3);
  });

  test("captures GitHub diagnostics on exhausted 401s before rethrowing", async () => {
    const err401 = httpErrorWithResponse(
      "A JSON web token could not be decoded",
      401,
      {
        date: new Date().toUTCString(),
        requestId: "REQ-123",
        body: { message: "A JSON web token could not be decoded" },
      },
    );
    mockRequest
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401);

    const promise = createProbeOctokit();
    const caught = promise.catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(1_000);
    await vi.advanceTimersByTimeAsync(2_000);
    await caught;

    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "cron-oauth-probe",
        op: expect.stringContaining("app-jwt"),
        extra: expect.objectContaining({
          ghStatus: 401,
          ghRequestId: "REQ-123",
          ghBody: expect.any(String),
          clockSkewMs: expect.any(Number),
          attempts: 3,
        }),
      }),
    );
  });

  test("computes clockSkewMs as local-now minus GitHub Date header (positive = local ahead)", async () => {
    // Freeze local clock at a round-second epoch; GitHub Date header is 5s
    // BEHIND local → local is ahead → positive skew. Use a non-401 status so
    // the capture fires immediately with no retry/timer advance, keeping the
    // skew deterministic (HTTP Date headers have 1s resolution).
    const NOW = 1_800_000_000_000; // ms, exact second boundary
    vi.setSystemTime(NOW);
    const ghDate = new Date(NOW - 5_000).toUTCString();
    const err500 = httpErrorWithResponse("Server Error", 500, {
      date: ghDate,
      requestId: "REQ-skew",
      body: "boom",
    });
    mockRequest.mockRejectedValueOnce(err500);

    await expect(createProbeOctokit()).rejects.toThrow("Server Error");

    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        extra: expect.objectContaining({ clockSkewMs: 5_000 }),
      }),
    );
  });

  test("captured body strips control chars + Unicode separators and slices to <=500", async () => {
    // Include CR/LF AND Unicode line/paragraph separators (/) +
    // a control char — the canonical log-injection class, not just \r\n.
    const oversized =
      "A".repeat(400) + "\nLINE2\r\n\u2028\u2029\x07" + "B".repeat(400);
    const err500 = httpErrorWithResponse("Server Error", 500, {
      date: new Date().toUTCString(),
      requestId: "REQ-body",
      body: oversized,
    });
    mockRequest.mockRejectedValueOnce(err500);

    await expect(createProbeOctokit()).rejects.toThrow("Server Error");

    const call = warnSilentFallback.mock.calls.at(-1);
    const ghBody = (call?.[1] as { extra: { ghBody: string } }).extra.ghBody;
    expect(ghBody.length).toBeLessThanOrEqual(500);
    // No control chars, DEL, or Unicode line/paragraph separators survive.
    expect(ghBody).not.toMatch(/[\x00-\x1f\x7f\u2028\u2029]/);
  });

  test("does NOT retry on 404", async () => {
    const err404 = httpError("Not Found", 404);
    mockRequest.mockRejectedValueOnce(err404);

    await expect(createProbeOctokit()).rejects.toThrow("Not Found");
    expect(MockApp).toHaveBeenCalledTimes(1);
    expect(mockRequest).toHaveBeenCalledTimes(1);
  });

  test("does NOT retry on 403", async () => {
    const err403 = httpError("Forbidden", 403);
    mockRequest.mockRejectedValueOnce(err403);

    await expect(createProbeOctokit()).rejects.toThrow("Forbidden");
    expect(MockApp).toHaveBeenCalledTimes(1);
  });
});
