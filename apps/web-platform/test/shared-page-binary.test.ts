import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

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

import { GET } from "@/app/api/shared/[token]/route";

let tmpWorkspace: string;
let kbRoot: string;

function buildRequest(token: string): Request {
  return new Request(`http://localhost:3000/api/shared/${token}`);
}

function callGET(request: Request, token: string) {
  return GET(request, { params: Promise.resolve({ token }) });
}

function mockShareAndOwner(
  documentPath: string,
  opts: { revoked?: boolean } = {},
) {
  let fromCallCount = 0;
  mocks.mockServiceFrom.mockImplementation(() => {
    fromCallCount++;
    if (fromCallCount === 1) {
      return {
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            single: vi.fn().mockResolvedValue({
              data: {
                document_path: documentPath,
                user_id: "user-1",
                revoked: Boolean(opts.revoked),
              },
              error: null,
            }),
          }),
        }),
      };
    }
    return {
      select: vi.fn().mockReturnValue({
        eq: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: {
              workspace_path: tmpWorkspace,
              workspace_status: "ready",
            },
            error: null,
          }),
        }),
      }),
    };
  });
}

function mockShareNotFound() {
  mocks.mockServiceFrom.mockImplementation(() => ({
    select: vi.fn().mockReturnValue({
      eq: vi.fn().mockReturnValue({
        single: vi.fn().mockResolvedValue({ data: null, error: null }),
      }),
    }),
  }));
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.mockIsAllowed.mockReturnValue(true);
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "shared-page-bin-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("GET /api/shared/[token] — binary vs markdown branching", () => {
  it("returns application/pdf for a .pdf share", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDFBYTES"));
    mockShareAndOwner("report.pdf");

    const res = await callGET(buildRequest("abc"), "abc");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/pdf");
    expect(res.headers.get("Content-Disposition")).toContain("inline");
    expect(res.headers.get("X-Content-Type-Options")).toBe("nosniff");
  });

  it("returns application/json for a .md share", async () => {
    fs.writeFileSync(
      path.join(kbRoot, "note.md"),
      "# Note\n\nhello",
    );
    mockShareAndOwner("note.md");

    const res = await callGET(buildRequest("mdtoken"), "mdtoken");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/application\/json/);
    const body = await res.json();
    expect(body.path).toBe("note.md");
    expect(body.content).toContain("# Note");
  });

  it("returns image/png for a .png share inline", async () => {
    fs.writeFileSync(path.join(kbRoot, "shot.png"), Buffer.from("PNGBYTES"));
    mockShareAndOwner("shot.png");

    const res = await callGET(buildRequest("png1"), "png1");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("image/png");
    expect(res.headers.get("Content-Disposition")).toContain("inline");
  });

  it("returns 404 when the binary file has been deleted", async () => {
    mockShareAndOwner("gone.pdf");
    const res = await callGET(buildRequest("gone"), "gone");
    expect(res.status).toBe(404);
  });

  it("returns 410 for a revoked binary share", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDF"));
    mockShareAndOwner("report.pdf", { revoked: true });
    const res = await callGET(buildRequest("rev"), "rev");
    expect(res.status).toBe(410);
  });

  it("returns 404 when the token does not exist", async () => {
    mockShareNotFound();
    const res = await callGET(buildRequest("nope"), "nope");
    expect(res.status).toBe(404);
  });

  it("returns 403 when the stored path is a symlink", async () => {
    const outside = path.join(tmpWorkspace, "outside.pdf");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link.pdf"));
    mockShareAndOwner("link.pdf");

    const res = await callGET(buildRequest("linktok"), "linktok");
    expect(res.status).toBe(403);
  });

  it("returns 413 when the stored binary exceeds the size limit", async () => {
    fs.writeFileSync(
      path.join(kbRoot, "huge.pdf"),
      Buffer.alloc(50 * 1024 * 1024 + 1),
    );
    mockShareAndOwner("huge.pdf");

    const res = await callGET(buildRequest("hugetok"), "hugetok");
    expect(res.status).toBe(413);
  });

  it("returns 403 when the stored path contains a null byte", async () => {
    mockShareAndOwner("evil\0.pdf");
    const res = await callGET(buildRequest("nulltok"), "nulltok");
    expect(res.status).toBe(403);
  });

  it("emits RFC 6266 Content-Disposition with UTF-8 filename* for non-ASCII names", async () => {
    fs.writeFileSync(path.join(kbRoot, "文档.pdf"), Buffer.from("PDF"));
    mockShareAndOwner("文档.pdf");

    const res = await callGET(buildRequest("utftok"), "utftok");
    expect(res.status).toBe(200);
    const disposition = res.headers.get("Content-Disposition");
    expect(disposition).toContain("filename=");
    expect(disposition).toMatch(/filename\*=UTF-8''/);
  });
});
