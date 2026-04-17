import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { hashBytes } from "@/server/kb-content-hash";
import { shareSupabaseFromMock } from "./helpers/share-mocks";
import { __resetShareHashVerdictCacheForTest } from "@/server/share-hash-verdict-cache";

const { hashStreamSpy, ...mocks } = vi.hoisted(() => ({
  hashStreamSpy: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockExtractIp: vi.fn(() => "1.2.3.4"),
  mockIsAllowed: vi.fn(() => true),
  mockLogRateLimit: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({ from: mocks.mockServiceFrom })),
}));

vi.mock("@/server/rate-limiter", () => ({
  shareEndpointThrottle: { isAllowed: mocks.mockIsAllowed },
  extractClientIpFromHeaders: mocks.mockExtractIp,
  logRateLimitRejection: mocks.mockLogRateLimit,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
}));

// Wrap the real hashStream so we can count drain calls without losing
// behavior (the share route compares the drain result against the stored
// content_sha256 — a stubbed return would always mismatch).
vi.mock("@/server/kb-content-hash", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/kb-content-hash")>(
      "@/server/kb-content-hash",
    );
  return {
    ...actual,
    hashStream: (...args: Parameters<typeof actual.hashStream>) => {
      hashStreamSpy(...args);
      return actual.hashStream(...args);
    },
  };
});

import { GET, HEAD } from "@/app/api/shared/[token]/route";

let tmpWorkspace: string;
let kbRoot: string;

function buildRequest(token: string, headers: Record<string, string> = {}): Request {
  return new Request(`http://localhost:3000/api/shared/${token}`, { headers });
}

function callGET(token: string, headers: Record<string, string> = {}) {
  return GET(buildRequest(token, headers), {
    params: Promise.resolve({ token }),
  });
}

function callHEAD(token: string, headers: Record<string, string> = {}) {
  return HEAD(buildRequest(token, headers), {
    params: Promise.resolve({ token }),
  });
}

function primeMocks(documentPath: string, fixture: Buffer) {
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        shareRow: {
          document_path: documentPath,
          user_id: "user-1",
          revoked: false,
          content_sha256: hashBytes(fixture),
        },
      },
    }),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetShareHashVerdictCacheForTest();
  mocks.mockIsAllowed.mockReturnValue(true);
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "share-cache-parity-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("shareHashVerdictCache — HEAD populates, follow-up GET skips the drain", () => {
  it("HEAD on a cold share drains hash once; subsequent GET on same token drains 0 more times", async () => {
    const pdf = Buffer.from("%PDF-1.1\n%FIXTURE\n");
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), pdf);
    primeMocks("report.pdf", pdf);

    const headRes = await callHEAD("tok-1");
    expect(headRes.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);

    const getRes = await callGET("tok-1");
    expect(getRes.status).toBe(200);
    // Second call uses the verdict cache populated by HEAD — no second drain.
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);

    const body = Buffer.from(await getRes.arrayBuffer());
    expect(body.equals(pdf)).toBe(true);
  });

  it("GET then HEAD: same cache-sharing works in reverse", async () => {
    const pdf = Buffer.from("%PDF-1.1\n%REVERSE\n");
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), pdf);
    primeMocks("doc.pdf", pdf);

    const getRes = await callGET("tok-2");
    expect(getRes.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);
    await getRes.arrayBuffer();

    const headRes = await callHEAD("tok-2");
    expect(headRes.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);
  });

  it("HEAD with If-None-Match matching content_sha256 short-circuits to 304 before any drain", async () => {
    const pdf = Buffer.from("%PDF-1.1\n%CACHED\n");
    fs.writeFileSync(path.join(kbRoot, "cached.pdf"), pdf);
    const storedHash = hashBytes(pdf);
    primeMocks("cached.pdf", pdf);

    const res = await callHEAD("tok-3", {
      "if-none-match": `"${storedHash}"`,
    });
    expect(res.status).toBe(304);
    // Early short-circuit happens in resolveShareForServe before any
    // filesystem work. Zero hash drains.
    expect(hashStreamSpy).not.toHaveBeenCalled();
  });

  it("GET with If-None-Match matching content_sha256 short-circuits to 304 before any drain", async () => {
    const pdf = Buffer.from("%PDF-1.1\n%GET-304\n");
    fs.writeFileSync(path.join(kbRoot, "cached2.pdf"), pdf);
    const storedHash = hashBytes(pdf);
    primeMocks("cached2.pdf", pdf);

    const res = await callGET("tok-4", {
      "if-none-match": `"${storedHash}"`,
    });
    expect(res.status).toBe(304);
    expect(hashStreamSpy).not.toHaveBeenCalled();
  });
});
