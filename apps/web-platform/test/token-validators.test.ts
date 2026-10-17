import { describe, test, expect, vi, beforeEach } from "vitest";
import { validateToken } from "../server/token-validators";
import logger from "../server/logger";

vi.mock("../server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

// Mock global fetch
const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

beforeEach(() => {
  mockFetch.mockReset();
  vi.mocked(logger.warn).mockClear();
});

describe("validateToken", () => {
  test("returns true for openai when API responds 200", async () => {
    mockFetch.mockResolvedValue({ ok: true });
    expect(await validateToken("openai", "sk-openai-test")).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.openai.com/v1/models",
      expect.objectContaining({
        headers: expect.objectContaining({ Authorization: "Bearer sk-openai-test" }),
      }),
    );
  });

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

const LI_USERINFO = "https://api.linkedin.com/v2/userinfo";
const LI_ME = "https://api.linkedin.com/v2/me";
const LI_ACLS =
  "https://api.linkedin.com/v2/organizationalEntityAcls?q=roleAssignee&role=ADMINISTRATOR&state=APPROVED";

describe("linkedin capability-aware probe chain (#9188)", () => {
  // Per-URL verdict map: the chain asks each endpoint what THIS token can do —
  // a pasted token's minting app is unknowable, so the probe order IS the
  // assertion. A verdict-only test would pass with the fallback deleted.
  const respond = (map: Record<string, { ok: boolean; status: number }>) =>
    mockFetch.mockImplementation((url: string) =>
      Promise.resolve(map[url] ?? { ok: false, status: 500 }),
    );
  const calledUrls = () => mockFetch.mock.calls.map((c) => c[0] as string);

  test("Community-app org token (403 userinfo, 200 /v2/me) validates true", async () => {
    respond({ [LI_USERINFO]: { ok: false, status: 403 }, [LI_ME]: { ok: true, status: 200 } });
    expect(await validateToken("linkedin", "li-org-token")).toBe(true);
    expect(calledUrls()).toEqual([LI_USERINFO, LI_ME]);
  });

  test("org-capable member-denied token (403/403, 200 ACLs) validates true", async () => {
    respond({
      [LI_USERINFO]: { ok: false, status: 403 },
      [LI_ME]: { ok: false, status: 403 },
      [LI_ACLS]: { ok: true, status: 200 },
    });
    expect(await validateToken("linkedin", "li-org-capable")).toBe(true);
    expect(calledUrls()).toEqual([LI_USERINFO, LI_ME, LI_ACLS]);
  });

  test("scope-empty token (403 on all probes) validates false", async () => {
    respond({
      [LI_USERINFO]: { ok: false, status: 403 },
      [LI_ME]: { ok: false, status: 403 },
      [LI_ACLS]: { ok: false, status: 403 },
    });
    expect(await validateToken("linkedin", "li-scope-empty")).toBe(false);
    expect(calledUrls()).toEqual([LI_USERINFO, LI_ME, LI_ACLS]);
  });

  test("dead token (401 on userinfo) validates false with NO fallback burn", async () => {
    respond({ [LI_USERINFO]: { ok: false, status: 401 } });
    expect(await validateToken("linkedin", "li-dead")).toBe(false);
    expect(calledUrls()).toEqual([LI_USERINFO]);
  });

  test("OIDC token (200 on userinfo) resolves in exactly one probe", async () => {
    respond({ [LI_USERINFO]: { ok: true, status: 200 } });
    expect(await validateToken("linkedin", "li-oidc")).toBe(true);
    expect(calledUrls()).toEqual([LI_USERINFO]);
  });

  test("unexpected status (500) stops the chain and validates false", async () => {
    respond({ [LI_USERINFO]: { ok: false, status: 500 } });
    expect(await validateToken("linkedin", "li-err")).toBe(false);
    expect(calledUrls()).toEqual([LI_USERINFO]);
  });

  test("transport failure (fetch throws) validates false, no fallback burn", async () => {
    mockFetch.mockRejectedValue(new Error("Network error"));
    expect(await validateToken("linkedin", "li-net")).toBe(false);
    expect(calledUrls()).toEqual([LI_USERINFO]);
  });

  test("every linkedin probe pins redirect: manual (no Bearer leak via redirect)", async () => {
    respond({
      [LI_USERINFO]: { ok: false, status: 403 },
      [LI_ME]: { ok: false, status: 403 },
      [LI_ACLS]: { ok: true, status: 200 },
    });
    expect(await validateToken("linkedin", "li-org-capable")).toBe(true);
    for (const call of mockFetch.mock.calls) {
      expect(call[1]).toEqual(expect.objectContaining({ redirect: "manual" }));
    }
  });

  test("inconclusive linkedin outcome logs a warning (never the token)", async () => {
    respond({ [LI_USERINFO]: { ok: false, status: 500 } });
    expect(await validateToken("linkedin", "li-secret-token")).toBe(false);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.objectContaining({ provider: "linkedin", status: 500 }),
      expect.any(String),
    );
    expect(vi.mocked(logger.warn).mock.calls.flat().join(" ")).not.toContain("li-secret-token");
  });

  test("non-linkedin providers keep single-probe behavior (github 403)", async () => {
    respond({ "https://api.github.com/user": { ok: false, status: 403 } });
    expect(await validateToken("github", "ghp_x")).toBe(false);
    expect(mockFetch).toHaveBeenCalledTimes(1);
  });
});
