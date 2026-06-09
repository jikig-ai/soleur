/**
 * Unit tests for getDefaultBranchHeadCommitAt() — the #4717 went-quiet probe.
 * Mocks global fetch (token mint + GET /commits). Verifies: HEAD commit
 * committer.date → epoch ms; empty repo (409 and []) → null; other non-200 →
 * throw. Mirrors the fetch-mock pattern in github-app-token-hardening.test.ts.
 */
import { generateKeyPairSync } from "crypto";

const { privateKey: validPem } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "pkcs1", format: "pem" },
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
});

// Env must be set BEFORE importing the module (read at load time).
process.env.GITHUB_APP_ID = "99999";
process.env.GITHUB_APP_PRIVATE_KEY = validPem;

import { describe, test, expect, vi, beforeEach, afterAll } from "vitest";

const { mockFetch } = vi.hoisted(() => ({ mockFetch: vi.fn() }));
const originalFetch = globalThis.fetch;
globalThis.fetch = mockFetch as unknown as typeof fetch;
afterAll(() => {
  globalThis.fetch = originalFetch;
});

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
    child: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
  }),
}));

import { getDefaultBranchHeadCommitAt } from "../server/github-app";
import { loadGithubFixture } from "./fixtures/github/load";

// Unique installation ids so the per-id token cache never short-circuits the
// token-mint fetch between tests.
let nextId = 70_000;
const uid = () => nextId++;

function tokenSuccess() {
  const body = loadGithubFixture<{ token: string; expires_at: string }>(
    "installation-access-token",
  );
  return {
    ok: true,
    status: 200,
    json: async () => ({
      ...body,
      expires_at: new Date(Date.now() + 3_600_000).toISOString(),
    }),
    text: async () => "",
  };
}
function commitsResponse(status: number, body: unknown) {
  return {
    ok: status === 200,
    status,
    json: async () => body,
    text: async () => JSON.stringify(body),
  };
}
function route(commits: { status: number; body: unknown }) {
  mockFetch.mockImplementation((url: string) => {
    const u = String(url);
    if (u.includes("/access_tokens")) return Promise.resolve(tokenSuccess());
    if (u.includes("/commits")) return Promise.resolve(commitsResponse(commits.status, commits.body));
    throw new Error(`unexpected fetch ${u}`);
  });
}

describe("getDefaultBranchHeadCommitAt", () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  test("returns the default-branch HEAD commit committer.date as epoch ms", async () => {
    const iso = "2026-05-20T12:00:00Z";
    route({ status: 200, body: [{ commit: { committer: { date: iso } } }] });
    const at = await getDefaultBranchHeadCommitAt(uid(), "acme", "widget");
    expect(at).toBe(Date.parse(iso));
  });

  test("returns null for an empty repo (GitHub 409)", async () => {
    route({ status: 409, body: { message: "Git Repository is empty." } });
    expect(await getDefaultBranchHeadCommitAt(uid(), "acme", "empty")).toBeNull();
  });

  test("returns null for an empty commit array", async () => {
    route({ status: 200, body: [] });
    expect(await getDefaultBranchHeadCommitAt(uid(), "acme", "nocommits")).toBeNull();
  });

  test("throws on a non-200/409 response (e.g. 404 repo gone / access revoked)", async () => {
    route({ status: 404, body: { message: "Not Found" } });
    await expect(getDefaultBranchHeadCommitAt(uid(), "acme", "gone")).rejects.toThrow();
  });
});
