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

const LOG = vi.hoisted(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }));
vi.mock("../server/logger", () => ({ createChildLogger: () => LOG, default: LOG }));

const mockFetch = vi.fn();
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;
afterAll(() => {
  globalThis.fetch = originalFetch;
});

import { findOpenPullRequest, listPullRequestsForHead } from "../server/github-app";

let nextInstallationId = 9600;
const tokenReply = () =>
  mockFetch.mockResolvedValueOnce({
    ok: true,
    json: async () => ({ token: ["ghs", "_", "t".repeat(36)].join(""), expires_at: new Date(Date.now() + 3600_000).toISOString() }),
  });
const SHA_A = "a".repeat(40);
const SHA_B = "b".repeat(40);

describe("listPullRequestsForHead (D17)", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    LOG.error.mockClear();
  });

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
    // D23: newest-updated first, one bounded page
    expect(url).toBe("https://api.github.com/repos/acme/widget/pulls?head=acme%3Asoleur%2Fkb-sync&base=main&state=all&sort=updated&direction=desc&per_page=10");
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

  test("D23: an entry whose head.sha is missing or not 40-hex throws (never a silent empty sha that hides a declined PR)", async () => {
    const entry = { number: 1, html_url: "https://github.com/acme/widget/pull/1", url: "u1", state: "closed", merged_at: null };
    for (const head of [undefined, {}, { sha: "" }, { sha: "A".repeat(40) }, { sha: "a".repeat(39) }, { sha: 42 }]) {
      tokenReply();
      mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => [{ ...entry, ...(head === undefined ? {} : { head }) }] });
      await expect(listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main"), JSON.stringify(head)).rejects.toThrow();
    }
  });

  test("D23: a non-OK reply logs the helper that failed", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: false, status: 403, text: async () => "forbidden", json: async () => ({ message: "forbidden" }) });
    await expect(listPullRequestsForHead(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
    expect(LOG.error).toHaveBeenCalledTimes(1);
    expect(LOG.error.mock.calls[0][0]).toEqual(expect.objectContaining({ helper: "listPullRequestsForHead", status: 403 }));
  });
});

// D23: `findOpenPullRequest` is a filter over the same private lister (one GET shape, one validation, one log line).
describe("findOpenPullRequest (D23)", () => {
  beforeEach(() => {
    mockFetch.mockReset();
    LOG.error.mockClear();
  });

  test("one GET with state=open and the same bounded, newest-first page; the first open entry is returned", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => [
        { number: 4, html_url: "https://github.com/acme/widget/pull/4", url: "u4", state: "open", merged_at: null, head: { sha: SHA_A } },
        { number: 3, html_url: "https://github.com/acme/widget/pull/3", url: "u3", state: "open", merged_at: null, head: { sha: SHA_B } },
      ],
    });
    const pr = await findOpenPullRequest(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main");
    expect(String(mockFetch.mock.calls[1][0])).toBe(
      "https://api.github.com/repos/acme/widget/pulls?head=acme%3Asoleur%2Fkb-sync&base=main&state=open&sort=updated&direction=desc&per_page=10",
    );
    expect(pr).toEqual({ number: 4, htmlUrl: "https://github.com/acme/widget/pull/4", url: "u4" });
  });

  test("no open entry -> null; a malformed entry throws; a non-OK reply logs the helper", async () => {
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => [] });
    expect(await findOpenPullRequest(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).toBeNull();
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: true, status: 200, json: async () => [{ number: 1, html_url: "h", state: "open" }] });
    await expect(findOpenPullRequest(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
    tokenReply();
    mockFetch.mockResolvedValueOnce({ ok: false, status: 502, text: async () => "bad gateway", json: async () => ({ message: "bad gateway" }) });
    await expect(findOpenPullRequest(nextInstallationId++, "acme", "widget", "soleur/kb-sync", "main")).rejects.toThrow();
    expect(LOG.error.mock.calls.map(([o]) => (o as { helper?: string }).helper)).toEqual(["findOpenPullRequest"]);
  });
});
