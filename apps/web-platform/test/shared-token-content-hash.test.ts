import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mocks = vi.hoisted(() => ({
  mockServiceFrom: vi.fn(),
  mockIsAllowed: vi.fn(),
  mockLoggerInfo: vi.fn(),
  mockLoggerWarn: vi.fn(),
  mockLoggerError: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: vi.fn(() => ({
    from: mocks.mockServiceFrom,
  })),
}));

vi.mock("@/server/rate-limiter", () => ({
  shareEndpointThrottle: { isAllowed: mocks.mockIsAllowed },
  extractClientIpFromHeaders: vi.fn(() => "127.0.0.1"),
  logRateLimitRejection: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: {
    info: mocks.mockLoggerInfo,
    error: mocks.mockLoggerError,
    warn: mocks.mockLoggerWarn,
    debug: vi.fn(),
  },
}));

import { GET } from "@/app/api/shared/[token]/route";

function hex(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

let tmpWorkspace: string;
let kbRoot: string;
let shareRow: Record<string, unknown> | null;

function mockShareLookup() {
  const makeChain = (terminal: Record<string, unknown>) => {
    const chain: Record<string, unknown> = { ...terminal };
    chain.eq = vi.fn().mockReturnValue(chain);
    return chain;
  };

  let fromCalls = 0;
  mocks.mockServiceFrom.mockImplementation(() => {
    fromCalls++;
    if (fromCalls === 1) {
      // kb_share_links lookup by token
      return {
        select: vi.fn().mockReturnValue(
          makeChain({
            single: vi.fn().mockResolvedValue({
              data: shareRow,
              error: shareRow ? null : new Error("not found"),
            }),
          }),
        ),
      };
    }
    // users lookup for owner workspace
    return {
      select: vi.fn().mockReturnValue(
        makeChain({
          single: vi.fn().mockResolvedValue({
            data: {
              workspace_path: tmpWorkspace,
              workspace_status: "ready",
            },
            error: null,
          }),
        }),
      ),
    };
  });
}

function getReq(): Request {
  return new Request("http://localhost:3000/api/shared/token-123");
}

async function callGET() {
  return GET(getReq(), { params: Promise.resolve({ token: "token-123" }) });
}

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "shared-hash-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
  mocks.mockIsAllowed.mockReturnValue(true);
  shareRow = null;
  mockShareLookup();
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("GET /api/shared/[token] — content hash verification", () => {
  it("serves markdown when the stored hash matches current bytes", async () => {
    const raw = "---\ntitle: Hi\n---\nBody text.";
    fs.writeFileSync(path.join(kbRoot, "note.md"), raw);
    shareRow = {
      document_path: "note.md",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(Buffer.from(raw)),
    };

    const res = await callGET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.content).toContain("Body text.");
    expect(mocks.mockLoggerInfo).toHaveBeenCalledWith(
      expect.objectContaining({ event: "shared_page_viewed" }),
      expect.any(String),
    );
  });

  it("returns 410 with code content-changed when markdown body drifts", async () => {
    fs.writeFileSync(path.join(kbRoot, "note.md"), "new body");
    shareRow = {
      document_path: "note.md",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(Buffer.from("old body")),
    };

    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("content-changed");
  });

  it("returns 410 when ONLY the markdown frontmatter changes (raw bytes hashed)", async () => {
    const originalRaw = "---\ntitle: Old\n---\nSame body.";
    const editedRaw = "---\ntitle: New\n---\nSame body.";
    fs.writeFileSync(path.join(kbRoot, "note.md"), editedRaw);
    shareRow = {
      document_path: "note.md",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(Buffer.from(originalRaw)),
    };

    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("content-changed");
  });

  it("serves a PDF when the stored hash matches current bytes", async () => {
    const pdfBytes = Buffer.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x01, 0x02]);
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), pdfBytes);
    shareRow = {
      document_path: "doc.pdf",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(pdfBytes),
    };

    const res = await callGET();
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/pdf");
  });

  it("returns 410 with code content-changed when PDF bytes drift", async () => {
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), Buffer.from("new pdf bytes"));
    shareRow = {
      document_path: "doc.pdf",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(Buffer.from("old pdf bytes")),
    };

    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("content-changed");
  });

  it("returns 404 unchanged when the file is missing (resurrection not relevant)", async () => {
    shareRow = {
      document_path: "gone.pdf",
      user_id: "owner-1",
      revoked: false,
      content_sha256: hex(Buffer.from("whatever")),
    };

    const res = await callGET();
    expect(res.status).toBe(404);
  });

  it("returns 410 with code legacy-null-hash when content_sha256 is null", async () => {
    fs.writeFileSync(path.join(kbRoot, "note.md"), "body");
    shareRow = {
      document_path: "note.md",
      user_id: "owner-1",
      revoked: false,
      content_sha256: null,
    };

    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.code).toBe("legacy-null-hash");
  });

  it("keeps the revoked 410 path intact (distinct from content-changed)", async () => {
    shareRow = {
      document_path: "doc.pdf",
      user_id: "owner-1",
      revoked: true,
      content_sha256: hex(Buffer.from("x")),
    };

    const res = await callGET();
    expect(res.status).toBe(410);
    const body = await res.json();
    // Must NOT claim content-changed when the row is explicitly revoked.
    expect(body.code).not.toBe("content-changed");
  });

  it("rate-limits before hashing (no fs work on 429)", async () => {
    mocks.mockIsAllowed.mockReturnValue(false);
    const fsReadSpy = vi.spyOn(fs.promises, "open");
    const res = await callGET();
    expect(res.status).toBe(429);
    expect(fsReadSpy).not.toHaveBeenCalled();
    fsReadSpy.mockRestore();
  });
});
