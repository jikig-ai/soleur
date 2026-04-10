import { describe, test, expect, vi, beforeEach } from "vitest";
import { validateToken } from "../server/token-validators";

// Mock global fetch
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
});

describe("validateToken", () => {
  test("returns true for anthropic when API responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("anthropic", "sk-ant-test")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.anthropic.com/v1/models",
      expect.objectContaining({
        headers: expect.objectContaining({ "x-api-key": "sk-ant-test" }),
      }),
    );
  });

  test("returns false for anthropic when API responds 401", async () => {
    mockFetch.mockResolvedValue({ ok: false });
    expect(await validateToken("anthropic", "bad-key")).toBe(false);
  });

  test("returns true for cloudflare when verify endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("cloudflare", "cf-token")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.cloudflare.com/client/v4/user/tokens/verify",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer cf-token" }),
      }),
    );
  });

  test("returns true for stripe when balance endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("stripe", "sk_test_123")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.stripe.com/v1/balance",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer sk_test_123" }),
      }),
    );
  });

  test("returns true for github when user endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("github", "ghp_test")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.github.com/user",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer ghp_test" }),
      }),
    );
  });

  test("returns true for hetzner when servers endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("hetzner", "hetzner-token")).toBe(true);
  });

  test("returns true for doppler when me endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("doppler", "dp-token")).toBe(true);
  });

  test("returns true for resend when api-keys endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("resend", "re_test")).toBe(true);
  });

  test("returns true for x when users/me endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("x", "x-bearer")).toBe(true);
  });

  test("returns true for linkedin when userinfo endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("linkedin", "li-token")).toBe(true);
  });

  test("returns true for bluesky when profile endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("bluesky", "bsky-pass")).toBe(true);
  });

  test("returns true for buttondown when emails endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("buttondown", "bd-key")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("api.buttondown.com"),
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Token bd-key" }),
      }),
    );
  });

  test("returns true for plausible when stats endpoint responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("plausible", "pl-key")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("site_id=soleur.ai"),
      expect.any(Object),
    );
  });

  test("plausible uses PLAUSIBLE_SITE_ID env var when set", async () => {
    process.env.PLAUSIBLE_SITE_ID = "example.com";
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("plausible", "pl-key")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("site_id=example.com"),
      expect.any(Object),
    );
    delete process.env.PLAUSIBLE_SITE_ID;
  });

  test("returns false when fetch throws (network error)", async () => {
    mockFetch.mockRejectedValue(new Error("Network error"));
    expect(await validateToken("cloudflare", "cf-token")).toBe(false);
  });

  test("returns false when fetch times out", async () => {
    mockFetch.mockRejectedValue(new DOMException("Aborted", "AbortError"));
    expect(await validateToken("stripe", "sk_test")).toBe(false);
  });

  test("returns false for unsupported provider (bedrock)", async () => {
    expect(await validateToken("bedrock", "aws-key")).toBe(false);
  });

  test("returns false for unsupported provider (vertex)", async () => {
    expect(await validateToken("vertex", "gcp-key")).toBe(false);
  });
});
