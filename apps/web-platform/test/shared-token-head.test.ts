import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { hashBytes } from "@/server/kb-content-hash";
import { shareSupabaseFromMock } from "./helpers/share-mocks";
import { __resetShareHashVerdictCacheForTest } from "@/server/share-hash-verdict-cache";

const mocks = vi.hoisted(() => ({
  mockServiceFrom: vi.fn(),
  mockExtractIp: vi.fn(() => "1.2.3.4"),
  mockIsAllowed: vi.fn(() => true),
  mockLogRateLimit: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({
    from: mocks.mockServiceFrom,
  })),
}));

vi.mock("@/server/rate-limiter", () => ({
  shareEndpointThrottle: { isAllowed: mocks.mockIsAllowed },
  extractClientIpFromHeaders: mocks.mockExtractIp,
  logRateLimitRejection: mocks.mockLogRateLimit,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
}));

import { HEAD } from "@/app/api/shared/[token]/route";

let tmpWorkspace: string;
let kbRoot: string;

function buildRequest(token: string, headers: Record<string, string> = {}): Request {
  return new Request(`http://localhost:3000/api/shared/${token}`, { headers });
}

function callHEAD(request: Request, token: string) {
  return HEAD(request, { params: Promise.resolve({ token }) });
}

function hashFile(absPath: string): string | null {
  try {
    return hashBytes(fs.readFileSync(absPath));
  } catch {
    return null;
  }
}

function mockShareAndOwner(
  documentPath: string,
  opts: { revoked?: boolean; contentHash?: string | null } = {},
) {
  const resolvedHash =
    opts.contentHash === undefined
      ? hashFile(path.join(kbRoot, documentPath)) ?? "0".repeat(64)
      : opts.contentHash;
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        shareRow: {
          document_path: documentPath,
          user_id: "user-1",
          revoked: Boolean(opts.revoked),
          content_sha256: resolvedHash,
        },
      },
    }),
  );
}

function mockShareNotFound() {
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      kb_share_links: { shareRow: null, shareError: null },
    }),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetShareHashVerdictCacheForTest();
  mocks.mockIsAllowed.mockReturnValue(true);
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "shared-head-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("HEAD /api/shared/[token]", () => {
  it("returns 200 with application/pdf and empty body for a valid PDF share", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDFBYTES"));
    mockShareAndOwner("report.pdf");
    const res = await callHEAD(buildRequest("abc"), "abc");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/pdf");
    expect(res.headers.get("Content-Length")).toBe("8");
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  it("returns 200 with image/png for a valid PNG share", async () => {
    fs.writeFileSync(path.join(kbRoot, "shot.png"), Buffer.from("PNGBYTES"));
    mockShareAndOwner("shot.png");
    const res = await callHEAD(buildRequest("png1"), "png1");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("image/png");
  });

  it("returns 410 for a revoked binary share (empty body)", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDF"));
    mockShareAndOwner("report.pdf", { revoked: true });
    const res = await callHEAD(buildRequest("rev"), "rev");
    expect(res.status).toBe(410);
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  it("returns 410 for a content-mismatched share (hash gate runs)", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("CURRENT"));
    mockShareAndOwner("report.pdf", { contentHash: "a".repeat(64) });
    const res = await callHEAD(buildRequest("cm"), "cm");
    expect(res.status).toBe(410);
  });

  it("returns 304 when If-None-Match matches the stored content_sha256", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDFBYTES"));
    const storedHash = hashFile(path.join(kbRoot, "report.pdf"))!;
    mockShareAndOwner("report.pdf", { contentHash: storedHash });
    const res = await callHEAD(
      buildRequest("etag", { "if-none-match": `"${storedHash}"` }),
      "etag",
    );
    expect(res.status).toBe(304);
  });

  it("runs the rate limiter (HEAD flood still gets 429)", async () => {
    mocks.mockIsAllowed.mockReturnValue(false);
    const res = await callHEAD(buildRequest("rl"), "rl");
    expect(res.status).toBe(429);
  });

  it("returns 404 when the token does not exist", async () => {
    mockShareNotFound();
    const res = await callHEAD(buildRequest("nope"), "nope");
    expect(res.status).toBe(404);
  });

  it("returns 403 when the stored path is a symlink (preserves ELOOP behavior)", async () => {
    const outside = path.join(tmpWorkspace, "outside.pdf");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link.pdf"));
    mockShareAndOwner("link.pdf");
    const res = await callHEAD(buildRequest("sym"), "sym");
    expect(res.status).toBe(403);
  });

  it("returns 200 with Content-Length matching the GET response for markdown", async () => {
    const mdContent = "# Note\n\nhello";
    fs.writeFileSync(path.join(kbRoot, "note.md"), mdContent);
    mockShareAndOwner("note.md");
    const res = await callHEAD(buildRequest("md"), "md");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/application\/json/);
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });
});
