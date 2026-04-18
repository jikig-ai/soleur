import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { hashBytes } from "@/server/kb-content-hash";
import { shareSupabaseFromMock } from "./helpers/share-mocks";
import { __resetShareHashVerdictCacheForTest } from "@/server/share-hash-verdict-cache";

// ---------------------------------------------------------------------------
// Hoisted mocks — same primitives used by both route tests, combined.
// ---------------------------------------------------------------------------

const mocks = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockIsAllowed: vi.fn(() => true),
  mockExtractIp: vi.fn(() => "1.2.3.4"),
  mockLogRateLimit: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mocks.mockGetUser },
  })),
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

import { GET as ownerGET, HEAD as ownerHEAD } from "@/app/api/kb/content/[...path]/route";
import { GET as sharedGET, HEAD as sharedHEAD } from "@/app/api/shared/[token]/route";

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

// Real 67-byte 1×1 transparent PNG — hash-sensitive. Don't swap bytes.
const PNG_1x1 = Buffer.from(
  "89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C4890000000D4944415478DA63F8CFC0F01F00050001FF6D1DBA5B0000000049454E44AE426082",
  "hex",
);

const PDF_FIXTURE = Buffer.from(
  "%PDF-1.1\n%\xe2\xe3\xcf\xd3\n1 0 obj\n<<>>\nendobj\ntrailer<<>>\n%%EOF\n",
);

// Headers that MUST be identical across both routes. Explicitly excludes
// ETag (strong for share, weak for owner — documented divergence) and
// Cache-Control (intentionally divergent: owner private, share public —
// see the `Cache-Control is intentionally divergent` describe block below).
const PARITY_HEADERS = [
  "Content-Type",
  "Content-Disposition",
  "Content-Length",
  "X-Content-Type-Options",
  "Content-Security-Policy",
  "Accept-Ranges",
] as const;

const PUBLIC_CACHE_CONTROL =
  "public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate";
const PRIVATE_CACHE_CONTROL = "private, max-age=60";

let tmpWorkspace: string;
let kbRoot: string;

function buildOwnerRequest(pathStr: string, headers: Record<string, string> = {}): Request {
  return new Request(`http://localhost:3000/api/kb/content/${pathStr}`, { headers });
}

function buildSharedRequest(token: string, headers: Record<string, string> = {}): Request {
  return new Request(`http://localhost:3000/api/shared/${token}`, { headers });
}

function callOwnerGET(pathStr: string, headers: Record<string, string> = {}) {
  return ownerGET(buildOwnerRequest(pathStr, headers), {
    params: Promise.resolve({ path: [pathStr] }),
  });
}

function callSharedGET(token: string, headers: Record<string, string> = {}) {
  return sharedGET(buildSharedRequest(token, headers), {
    params: Promise.resolve({ token }),
  });
}

function callOwnerHEAD(pathStr: string) {
  return ownerHEAD(buildOwnerRequest(pathStr), {
    params: Promise.resolve({ path: [pathStr] }),
  });
}

function callSharedHEAD(token: string) {
  return sharedHEAD(buildSharedRequest(token), {
    params: Promise.resolve({ token }),
  });
}

/**
 * Prime all Supabase mocks so the same fixture resolves through either
 * route. Owner route sees an authenticated user with workspace_path
 * pointing at tmpWorkspace; shared route sees a non-revoked share row
 * with content_sha256 = hashBytes(fixture).
 */
function primeMocks(documentPath: string, fixture: Buffer) {
  mocks.mockGetUser.mockResolvedValue({
    data: { user: { id: "user-1" } },
    error: null,
  });
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
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "parity-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("contract: /api/kb/content and /api/shared/[token] — bytes + headers parity", () => {
  it("GET returns byte-identical bodies and matching headers for a PDF", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerGET("report.pdf");
    const sharedRes = await callSharedGET("tok-pdf");

    expect(ownerRes.status).toBe(200);
    expect(sharedRes.status).toBe(200);

    const ownerBody = Buffer.from(await ownerRes.arrayBuffer());
    const sharedBody = Buffer.from(await sharedRes.arrayBuffer());
    expect(ownerBody.equals(sharedBody)).toBe(true);
    expect(ownerBody.equals(PDF_FIXTURE)).toBe(true);

    for (const key of PARITY_HEADERS) {
      expect(sharedRes.headers.get(key)).toBe(ownerRes.headers.get(key));
    }
  });

  it("GET returns byte-identical bodies and matching headers for a PNG", async () => {
    fs.writeFileSync(path.join(kbRoot, "shot.png"), PNG_1x1);
    primeMocks("shot.png", PNG_1x1);

    const ownerRes = await callOwnerGET("shot.png");
    const sharedRes = await callSharedGET("tok-png");

    expect(ownerRes.status).toBe(200);
    expect(sharedRes.status).toBe(200);

    const ownerBody = Buffer.from(await ownerRes.arrayBuffer());
    const sharedBody = Buffer.from(await sharedRes.arrayBuffer());
    expect(ownerBody.equals(sharedBody)).toBe(true);
    expect(ownerBody.equals(PNG_1x1)).toBe(true);

    for (const key of PARITY_HEADERS) {
      expect(sharedRes.headers.get(key)).toBe(ownerRes.headers.get(key));
    }
  });

  it("HEAD returns matching headers (empty body on both routes) for a PDF", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerHEAD("report.pdf");
    const sharedRes = await callSharedHEAD("tok-pdf");

    expect(ownerRes.status).toBe(200);
    expect(sharedRes.status).toBe(200);

    expect((await ownerRes.arrayBuffer()).byteLength).toBe(0);
    expect((await sharedRes.arrayBuffer()).byteLength).toBe(0);

    for (const key of PARITY_HEADERS) {
      expect(sharedRes.headers.get(key)).toBe(ownerRes.headers.get(key));
    }
    // Content-Length on HEAD matches the full-resource size (RFC 7231).
    expect(ownerRes.headers.get("Content-Length")).toBe(String(PDF_FIXTURE.length));
    expect(sharedRes.headers.get("Content-Length")).toBe(String(PDF_FIXTURE.length));
  });

  it("Range GET returns identical 206 bodies and Content-Range for bytes=0-31", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerGET("report.pdf", { range: "bytes=0-31" });
    const sharedRes = await callSharedGET("tok-pdf", { range: "bytes=0-31" });

    expect(ownerRes.status).toBe(206);
    expect(sharedRes.status).toBe(206);
    expect(sharedRes.headers.get("Content-Range")).toBe(
      ownerRes.headers.get("Content-Range"),
    );

    const ownerBody = Buffer.from(await ownerRes.arrayBuffer());
    const sharedBody = Buffer.from(await sharedRes.arrayBuffer());
    expect(ownerBody.equals(sharedBody)).toBe(true);
    expect(ownerBody.length).toBe(32);
  });
});

describe("streaming discipline: bodies must be streamed, not buffered", () => {
  it("GET binary response body is a ReadableStream (not a buffered array)", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerGET("report.pdf");
    const sharedRes = await callSharedGET("tok-pdf");

    // If a future change accidentally swaps openBinaryStream for
    // readFileSync + new Response(buffer), this assertion catches it
    // before a 50 MB PDF OOMs production. Both routes must keep the
    // stream contract.
    expect(ownerRes.body).toBeInstanceOf(ReadableStream);
    expect(sharedRes.body).toBeInstanceOf(ReadableStream);

    await ownerRes.arrayBuffer();
    await sharedRes.arrayBuffer();
  });
});

describe("Cache-Control is intentionally divergent (issue #2329)", () => {
  it("owner GET emits private, shared GET emits public", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerGET("report.pdf");
    const sharedRes = await callSharedGET("tok-pdf");

    expect(ownerRes.headers.get("Cache-Control")).toBe(PRIVATE_CACHE_CONTROL);
    expect(sharedRes.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });

  it("owner HEAD emits private, shared HEAD emits public", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    const ownerRes = await callOwnerHEAD("report.pdf");
    const sharedRes = await callSharedHEAD("tok-pdf");

    expect(ownerRes.headers.get("Cache-Control")).toBe(PRIVATE_CACHE_CONTROL);
    expect(sharedRes.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });

  it("owner 304 emits private, shared 304 emits public", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), PDF_FIXTURE);
    primeMocks("report.pdf", PDF_FIXTURE);

    // Owner weak ETag: derived from fstat tuple.
    const stat = fs.statSync(path.join(kbRoot, "report.pdf"));
    const ownerWeakETag = `W/"${stat.ino}-${stat.size}-${Math.floor(stat.mtimeMs)}"`;
    const ownerRes = await callOwnerGET("report.pdf", {
      "if-none-match": ownerWeakETag,
    });
    expect(ownerRes.status).toBe(304);
    expect(ownerRes.headers.get("Cache-Control")).toBe(PRIVATE_CACHE_CONTROL);

    // Shared strong ETag: content_sha256 from the share row.
    const sharedStrongETag = `"${hashBytes(PDF_FIXTURE)}"`;
    const sharedRes = await callSharedGET("tok-pdf", {
      "if-none-match": sharedStrongETag,
    });
    expect(sharedRes.status).toBe(304);
    expect(sharedRes.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });
});

describe("regression guards carried from PR #2477 / TOCTOU hardening", () => {
  it("no pre-open fs.lstat call in shared or owner route files", () => {
    const sharedSrc = fs.readFileSync(
      path.resolve(
        __dirname,
        "../app/api/shared/[token]/route.ts",
      ),
      "utf8",
    );
    const ownerSrc = fs.readFileSync(
      path.resolve(
        __dirname,
        "../app/api/kb/content/[...path]/route.ts",
      ),
      "utf8",
    );
    for (const src of [sharedSrc, ownerSrc]) {
      expect(src).not.toMatch(/fs\.promises\.lstat\b/);
      expect(src).not.toMatch(/fs\.lstat\b/);
    }
  });
});
