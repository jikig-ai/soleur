import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { hashBytes } from "@/server/kb-content-hash";
import {
  shareHashVerdictCache,
  __resetShareHashVerdictCacheForTest,
} from "@/server/share-hash-verdict-cache";
import { shareSupabaseFromMock } from "./helpers/share-mocks";

const mocks = vi.hoisted(() => ({
  mockServiceFrom: vi.fn(),
  mockIsAllowed: vi.fn(() => true),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({
    from: mocks.mockServiceFrom,
  })),
}));

vi.mock("@/server/rate-limiter", () => ({
  shareEndpointThrottle: { isAllowed: mocks.mockIsAllowed },
  extractClientIpFromHeaders: vi.fn(() => "1.2.3.4"),
  logRateLimitRejection: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
}));

// Spy on hashStream to count invocations. The route calls hashStream
// only on cache miss; this spy is the core assertion of this file.
const hashStreamSpy = vi.fn();
vi.mock("@/server/kb-content-hash", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/kb-content-hash")>(
      "@/server/kb-content-hash",
    );
  return {
    ...actual,
    hashStream: async (...args: unknown[]) => {
      hashStreamSpy();
      // @ts-expect-error -- forwarded args match actual signature.
      return actual.hashStream(...args);
    },
  };
});

import { GET } from "@/app/api/shared/[token]/route";

let tmpWorkspace: string;
let kbRoot: string;

function buildRequest(token: string, headers?: Record<string, string>): Request {
  return new Request(`http://localhost:3000/api/shared/${token}`, { headers });
}
function callGET(req: Request, token: string) {
  return GET(req, { params: Promise.resolve({ token }) });
}

function mockShareAndOwner(
  documentPath: string,
  opts: { contentHash: string },
) {
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        shareRow: {
          document_path: documentPath,
          user_id: "user-1",
          revoked: false,
          content_sha256: opts.contentHash,
        },
      },
    }),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  hashStreamSpy.mockClear();
  __resetShareHashVerdictCacheForTest();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "shared-cache-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  __resetShareHashVerdictCacheForTest();
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("GET /api/shared/[token] — verdict cache (streaming)", () => {
  it("first view hashes, second view skips hash on same file", async () => {
    const pdfBytes = Buffer.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x0a, 0xff]);
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), pdfBytes);
    const hash = hashBytes(pdfBytes);
    mockShareAndOwner("doc.pdf", { contentHash: hash });

    const first = await callGET(buildRequest("tok-a"), "tok-a");
    expect(first.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);

    const second = await callGET(buildRequest("tok-a"), "tok-a");
    expect(second.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1); // not called again
  });

  it("Range request on cached token returns 206 without re-hashing", async () => {
    const pdfBytes = Buffer.alloc(1024, 0x42);
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), pdfBytes);
    const hash = hashBytes(pdfBytes);
    mockShareAndOwner("doc.pdf", { contentHash: hash });

    // Prime the cache.
    const first = await callGET(buildRequest("tok-range"), "tok-range");
    expect(first.status).toBe(200);
    const hashCallsAfterPrime = hashStreamSpy.mock.calls.length;

    // Mock must remain valid across invocations (reset call count).
    mockShareAndOwner("doc.pdf", { contentHash: hash });

    const rangeReq = buildRequest("tok-range", { Range: "bytes=0-99" });
    const ranged = await callGET(rangeReq, "tok-range");
    expect(ranged.status).toBe(206);
    expect(ranged.headers.get("Content-Length")).toBe("100");
    expect(ranged.headers.get("Content-Range")).toBe("bytes 0-99/1024");
    expect(hashStreamSpy.mock.calls.length).toBe(hashCallsAfterPrime);
  });

  it("mtime change invalidates cache and re-hashes", async () => {
    const origBytes = Buffer.from("original content padding padding");
    const filePath = path.join(kbRoot, "doc.pdf");
    fs.writeFileSync(filePath, origBytes);
    const origHash = hashBytes(origBytes);
    mockShareAndOwner("doc.pdf", { contentHash: origHash });

    const first = await callGET(buildRequest("tok-mtime"), "tok-mtime");
    expect(first.status).toBe(200);
    expect(hashStreamSpy).toHaveBeenCalledTimes(1);

    // Modify file. Advance mtime by writing with a future timestamp so
    // the fs layer reports a different mtimeMs reliably.
    const newBytes = Buffer.from("different content different length");
    fs.writeFileSync(filePath, newBytes);
    const future = new Date(Date.now() + 10_000);
    fs.utimesSync(filePath, future, future);

    mockShareAndOwner("doc.pdf", { contentHash: origHash });
    const second = await callGET(buildRequest("tok-mtime"), "tok-mtime");
    expect(second.status).toBe(410); // content-changed
    expect(hashStreamSpy).toHaveBeenCalledTimes(2);
    const stat = fs.statSync(filePath);
    expect(
      shareHashVerdictCache.get(
        "tok-mtime",
        stat.ino,
        stat.mtimeMs,
        stat.size,
      ),
    ).toBeNull();
  });

  it("streaming response body contains the full file bytes", async () => {
    const bytes = Buffer.from("streamable content bytes ABCDEFG");
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), bytes);
    const hash = hashBytes(bytes);
    mockShareAndOwner("doc.pdf", { contentHash: hash });

    const res = await callGET(buildRequest("tok-body"), "tok-body");
    expect(res.status).toBe(200);
    const body = await res.arrayBuffer();
    expect(Buffer.from(body).equals(bytes)).toBe(true);
  });

  it("hash mismatch on first view returns 410 and does NOT cache the verdict", async () => {
    const actualBytes = Buffer.from("these are the real file bytes");
    const storedHash = hashBytes(Buffer.from("something else was stored"));
    const filePath = path.join(kbRoot, "doc.pdf");
    fs.writeFileSync(filePath, actualBytes);
    mockShareAndOwner("doc.pdf", { contentHash: storedHash });

    const res = await callGET(buildRequest("tok-mismatch"), "tok-mismatch");
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("content-changed");

    const stat = fs.statSync(filePath);
    expect(
      shareHashVerdictCache.get(
        "tok-mismatch",
        stat.ino,
        stat.mtimeMs,
        stat.size,
      ),
    ).toBeNull();
  });

  it("stores the exact validated tuple on cache set (ino, mtimeMs, size)", async () => {
    const bytes = Buffer.from("payload to hash");
    const filePath = path.join(kbRoot, "doc.pdf");
    fs.writeFileSync(filePath, bytes);
    const hash = hashBytes(bytes);
    mockShareAndOwner("doc.pdf", { contentHash: hash });

    const res = await callGET(buildRequest("tok-tuple"), "tok-tuple");
    expect(res.status).toBe(200);
    const stat = fs.statSync(filePath);
    expect(
      shareHashVerdictCache.get(
        "tok-tuple",
        stat.ino,
        stat.mtimeMs,
        stat.size,
      ),
    ).toBe(true);
  });
});
