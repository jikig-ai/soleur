import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

const { mockGetUser, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

import { HEAD } from "@/app/api/kb/content/[...path]/route";

let tmpWorkspace: string;
let kbRoot: string;

function mockQueryBuilder(data: unknown, error: unknown = null) {
  return {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnValue({
      then: (fn: (v: unknown) => unknown) =>
        Promise.resolve({ data, error }).then(fn),
    }),
  };
}

function buildRequest(pathStr: string, headers: Record<string, string> = {}): Request {
  return new Request(`http://localhost:3000/api/kb/content/${pathStr}`, {
    headers,
  });
}

function callHEAD(request: Request, pathSegments: string[]) {
  return HEAD(request, { params: Promise.resolve({ path: pathSegments }) });
}

function mockAuthOk() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: "user-1" } },
    error: null,
  });
  mockFrom.mockReturnValue(
    mockQueryBuilder({
      workspace_path: tmpWorkspace,
      workspace_status: "ready",
    }),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-content-head-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("HEAD /api/kb/content/[...path]", () => {
  test("returns 200 with correct headers and empty body for an authenticated binary", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDFBYTES"));
    mockAuthOk();
    const res = await callHEAD(buildRequest("report.pdf"), ["report.pdf"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/pdf");
    expect(res.headers.get("Content-Length")).toBe("8");
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  test("returns 401 without auth", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: null },
      error: { message: "not authenticated" },
    });
    const res = await callHEAD(buildRequest("report.pdf"), ["report.pdf"]);
    expect(res.status).toBe(401);
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  test("returns 200 with application/json for a markdown HEAD", async () => {
    fs.writeFileSync(path.join(kbRoot, "note.md"), "# hi\n");
    mockAuthOk();
    const res = await callHEAD(buildRequest("note.md"), ["note.md"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toMatch(/application\/json/);
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  test("returns 404 with empty body when the file is missing", async () => {
    mockAuthOk();
    const res = await callHEAD(buildRequest("gone.pdf"), ["gone.pdf"]);
    expect(res.status).toBe(404);
    expect((await res.arrayBuffer()).byteLength).toBe(0);
  });

  test("returns 403 with empty body when the path is a symlink", async () => {
    const outside = path.join(tmpWorkspace, "outside.pdf");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link.pdf"));
    mockAuthOk();
    const res = await callHEAD(buildRequest("link.pdf"), ["link.pdf"]);
    expect(res.status).toBe(403);
    expect((await res.arrayBuffer()).byteLength).toBe(0);
  });

  test("returns 403 when the path contains a null byte", async () => {
    mockAuthOk();
    const res = await callHEAD(buildRequest("evil%00.pdf"), ["evil\0.pdf"]);
    expect(res.status).toBe(403);
  });

  test("returns 503 with empty body when workspace_status is not ready", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });
    mockFrom.mockReturnValue(
      mockQueryBuilder({
        workspace_path: tmpWorkspace,
        workspace_status: "provisioning",
      }),
    );
    const res = await callHEAD(buildRequest("report.pdf"), ["report.pdf"]);
    expect(res.status).toBe(503);
    expect((await res.arrayBuffer()).byteLength).toBe(0);
  });

  test("returns 304 when If-None-Match matches the weak ETag (binary)", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("PDFBYTES"));
    mockAuthOk();
    // First issue a HEAD to read back the weak ETag the server emits,
    // then replay the request with If-None-Match set to it.
    const first = await callHEAD(buildRequest("report.pdf"), ["report.pdf"]);
    const etag = first.headers.get("ETag")!;
    expect(etag).toMatch(/^W\//);
    const res = await callHEAD(
      buildRequest("report.pdf", { "if-none-match": etag }),
      ["report.pdf"],
    );
    expect(res.status).toBe(304);
    expect((await res.arrayBuffer()).byteLength).toBe(0);
  });
});
