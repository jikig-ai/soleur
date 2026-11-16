// #12600, CTO ruling D17: `listPullRequestsForHead`, the REST read behind the kb-sync `side_pending` PR re-check. One GET with
// `state=all` (an Owner-closed PR must be seen), `merged` from `merged_at`, the head commit from `head.sha`, and a throw on a
// non-OK or malformed reply so the caller creates nothing. Synthesized data only (cq-test-fixtures-synthesized-only).
import { generateKeyPairSync } from "crypto";

const { privateKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});
process.env.GITHUB_APP_ID = "12345";
process.env.GITHUB_APP_PRIVATE_KEY = privateKey;

import { afterAll, beforeEach, describe, expect, test, vi } from "vitest";

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;
afterAll(() => {
  globalThis.fetch = originalFetch;
});

import { listPullRequestsForHead } from "../server/github-app";

let nextInstallationId = 9600;
const tokenReply = () =>
  mockFetch.mockResolvedValueOnce({
    ok: true,
    json: async () => ({ token: ["ghs", "_", "t".repeat(36)].join(""), expires_at: new Date(Date.now() + 3600_000).toISOString() }),
  });
const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);

describe("listPullRequestsForHead (D17)", () => {
  beforeEach(() => mockFetch.mockReset());

  test("one GET with state=all and the owner-qualified head; open, closed-unmerged and merged PRs are mapped", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => [
        { number: 3, html_url: "https://github.com/acme/widget/pull/3", url: "u3", state: "open", merged_at: null, head: { sha: SHA_A } },
        { number: 2, html_url: "https://github.com/acme/widget/pull/2", url: "u2", state: "closed", merged_at: null, head: { sha: SHA_B } },
        { number: 1, html_url: "https://github.com/acme/widget/pull/1", url: "u1", state: "closed", merged_at: "2026-11-01T00:00:00Z", head: { sha: SHA_B } },
      ],
    });
    const prs = await listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main");
    const url = String(mockFetch.mock.calls[1][0]);
    expect(url).toBe("https://api.github.com/repos/acme/widget/pulls?head=acme%3Asoleur%2Fkb-sync&base=main&state=all");
    expect((mockFetch.mock.calls[1][1] as { method: string }).method).toBe("GET");
    expect(prs.map((p) => [p.number, p.state, p.merged, p.headSha])).toEqual([
      [3, "open", false, SHA_A],
      [2, "closed", false, SHA_B],
      [1, "closed", true, SHA_B],
    ]);
  });

  test("a non-OK reply throws (the caller then creates nothing)", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: false, status: 503, text: async () => "unavailable", json: async () => ({ message: "unavailable" }) });
    await expect(listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
  });

  test("a malformed body (not an array, or an entry with no state) throws", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ message: "not a list" }) });
    await expect(listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => [{ number: 1, html_url: "h" }] });
    await expect(listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
  });
});
