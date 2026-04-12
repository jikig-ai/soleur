import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { GET } from "@/app/api/kb/content/[...path]/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function buildRequest(pathStr: string): Request {
  return new Request(`http://localhost:3000/api/kb/content/${pathStr}`);
}

function callGET(request: Request, pathSegments: string[]) {
  return GET(request, { params: Promise.resolve({ path: pathSegments }) });
}

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-binary-test-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GET /api/kb/content/[...path] — binary files", () => {
  test("unauthenticated request returns 401", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: null },
      error: { message: "not authenticated" },
    });

    const res = await callGET(buildRequest("images/logo.png"), [
      "images",
      "logo.png",
    ]);
    expect(res.status).toBe(401);
  });

  test("PNG file returns Content-Type image/png", async () => {
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

    fs.mkdirSync(path.join(kbRoot, "images"), { recursive: true });
    fs.writeFileSync(
      path.join(kbRoot, "images", "logo.png"),
      Buffer.from("fake-png-data"),
    );

    const res = await callGET(buildRequest("images/logo.png"), [
      "images",
      "logo.png",
    ]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("image/png");
  });

  test("image file returns Content-Disposition: inline", async () => {
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

    fs.writeFileSync(
      path.join(kbRoot, "photo.jpg"),
      Buffer.from("fake-jpg-data"),
    );

    const res = await callGET(buildRequest("photo.jpg"), ["photo.jpg"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Disposition")).toContain("inline");
    expect(res.headers.get("Content-Disposition")).toContain("photo.jpg");
  });

  test("PDF returns Content-Disposition: inline", async () => {
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

    fs.writeFileSync(
      path.join(kbRoot, "report.pdf"),
      Buffer.from("fake-pdf-data"),
    );

    const res = await callGET(buildRequest("report.pdf"), ["report.pdf"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/pdf");
    expect(res.headers.get("Content-Disposition")).toContain("inline");
  });

  test("DOCX returns Content-Disposition: attachment", async () => {
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

    fs.writeFileSync(
      path.join(kbRoot, "doc.docx"),
      Buffer.from("fake-docx-data"),
    );

    const res = await callGET(buildRequest("doc.docx"), ["doc.docx"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe(
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    );
    expect(res.headers.get("Content-Disposition")).toContain("attachment");
  });

  test("path traversal on binary path returns 403", async () => {
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

    const res = await callGET(
      buildRequest("../../../etc/passwd.png"),
      ["..", "..", "..", "etc", "passwd.png"],
    );
    expect(res.status).toBe(403);
  });

  test("non-existent binary file returns 404", async () => {
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

    const res = await callGET(buildRequest("missing.png"), ["missing.png"]);
    expect(res.status).toBe(404);
  });

  test(".md file still goes through readContent path", async () => {
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

    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# Hello World");

    const res = await callGET(buildRequest("readme.md"), ["readme.md"]);
    expect(res.status).toBe(200);
    const body = await res.json();
    // readContent returns { path, frontmatter, content } as JSON
    expect(body.path).toBe("readme.md");
    expect(body.content).toBe("# Hello World");
  });

  test("symlink in binary path is rejected", async () => {
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

    // Create a real file outside the KB, then symlink to it
    const outsideFile = path.join(tmpWorkspace, "secret.txt");
    fs.writeFileSync(outsideFile, "secret-data");
    fs.symlinkSync(outsideFile, path.join(kbRoot, "link.png"));

    const res = await callGET(buildRequest("link.png"), ["link.png"]);
    expect(res.status).toBe(403);
  });

  test("returns Content-Length header", async () => {
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

    const data = Buffer.from("exactly-this-content");
    fs.writeFileSync(path.join(kbRoot, "file.csv"), data);

    const res = await callGET(buildRequest("file.csv"), ["file.csv"]);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Length")).toBe(data.length.toString());
  });
});
