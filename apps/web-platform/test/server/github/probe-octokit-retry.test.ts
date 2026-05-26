/**
 * Tests for createProbeOctokit() retry-on-401 hardening.
 *
 * The @octokit/auth-app library retries clock-skew and installation-token
 * 401s, but NOT App JWT decode failures ("A JSON web token could not be
 * decoded"). This test verifies createProbeOctokit() adds its own retry
 * for that gap.
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.GITHUB_APP_ID = "99999";
process.env.GITHUB_APP_PRIVATE_KEY =
  "-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----";

const { mockRequest, mockGetInstallationOctokit, MockApp } = vi.hoisted(
  () => {
    const mockRequest = vi.fn();
    const mockGetInstallationOctokit = vi.fn();
    const MockApp = vi.fn().mockImplementation(() => ({
      octokit: { request: mockRequest },
      getInstallationOctokit: mockGetInstallationOctokit,
    }));
    return { mockRequest, mockGetInstallationOctokit, MockApp };
  },
);

vi.mock("@octokit/app", () => ({ App: MockApp }));

import {
  createProbeOctokit,
} from "../../../server/github/probe-octokit";

function httpError(message: string, status: number): Error {
  const err = new Error(message);
  (err as Error & { status: number }).status = status;
  err.name = "HttpError";
  return err;
}

describe("createProbeOctokit retry-on-401", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    mockRequest.mockReset();
    mockGetInstallationOctokit.mockReset();
    MockApp.mockClear();
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

  test("throws after two consecutive 401s", async () => {
    const err401 = httpError(
      "A JSON web token could not be decoded",
      401,
    );
    mockRequest
      .mockRejectedValueOnce(err401)
      .mockRejectedValueOnce(err401);

    const promise = createProbeOctokit();
    // Attach rejection handler before advancing timers to prevent
    // Node's unhandled-rejection detector from racing the assertion.
    const caught = promise.catch((e: unknown) => e);
    await vi.advanceTimersByTimeAsync(1_000);
    const err = await caught;

    expect(err).toBeInstanceOf(Error);
    expect((err as Error).message).toBe(
      "A JSON web token could not be decoded",
    );
    expect(MockApp).toHaveBeenCalledTimes(2);
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
