import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mocks = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockValidateOrigin: vi.fn(),
  mockRejectCsrf: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(() =>
    Promise.resolve({
      auth: { getUser: mocks.mockGetUser },
    }),
  ),
  createServiceClient: vi.fn(() => ({
    from: mocks.mockServiceFrom,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mocks.mockValidateOrigin,
  rejectCsrf: mocks.mockRejectCsrf,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
}));

// NOTE: isPathInWorkspace is intentionally NOT mocked — we use a real temp
// workspace so lstat + isFile + isSymbolicLink checks exercise the real FS.

import { POST } from "@/app/api/kb/share/route";

let tmpWorkspace: string;
let kbRoot: string;

function createShareRequest(
  documentPath: string,
  origin = "http://localhost:3000",
): Request {
  return new Request("http://localhost:3000/api/kb/share", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: origin,
    },
    body: JSON.stringify({ documentPath }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-share-paths-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });

  mocks.mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "http://localhost:3000",
  });
  mocks.mockGetUser.mockResolvedValue({
    data: { user: { id: "user-1" } },
  });

  const makeChain = (terminal: Record<string, unknown>) => {
    const chain: Record<string, unknown> = { ...terminal };
    chain.eq = vi.fn().mockReturnValue(chain);
    return chain;
  };

  let fromCallCount = 0;
  mocks.mockServiceFrom.mockImplementation(() => {
    fromCallCount++;
    if (fromCallCount === 1) {
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
    }
    return {
      select: vi.fn().mockReturnValue(
        makeChain({
          maybeSingle: vi.fn().mockResolvedValue({
            data: null,
            error: null,
          }),
        }),
      ),
      insert: vi.fn().mockResolvedValue({ error: null }),
    };
  });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("KB share allowed paths — existence + filetype validation", () => {
  it("allows share creation for .md files that exist", async () => {
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# hi");
    const res = await POST(createShareRequest("readme.md"));
    expect(res.status).toBe(201);
  });

  it("allows share creation for .pdf files that exist", async () => {
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), Buffer.from("pdf"));
    const res = await POST(createShareRequest("report.pdf"));
    expect(res.status).toBe(201);
  });

  it("allows share creation for .png files that exist", async () => {
    fs.writeFileSync(path.join(kbRoot, "shot.png"), Buffer.from("png"));
    const res = await POST(createShareRequest("shot.png"));
    expect(res.status).toBe(201);
  });

  it("allows share creation for .csv files that exist", async () => {
    fs.writeFileSync(path.join(kbRoot, "data.csv"), "a,b\n1,2");
    const res = await POST(createShareRequest("data.csv"));
    expect(res.status).toBe(201);
  });

  it("rejects non-existent paths with 404", async () => {
    const res = await POST(createShareRequest("missing.pdf"));
    expect(res.status).toBe(404);
  });

  it("rejects symlinks with 400", async () => {
    const outside = path.join(tmpWorkspace, "secret.txt");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link.pdf"));
    const res = await POST(createShareRequest("link.pdf"));
    expect(res.status).toBe(400);
  });

  it("rejects directories with 400", async () => {
    fs.mkdirSync(path.join(kbRoot, "subdir"));
    const res = await POST(createShareRequest("subdir"));
    expect(res.status).toBe(400);
  });

  it("rejects path traversal outside kbRoot with 400", async () => {
    fs.writeFileSync(path.join(tmpWorkspace, "outside.md"), "x");
    const res = await POST(createShareRequest("../outside.md"));
    expect(res.status).toBe(400);
  });

  it("rejects oversize files with 413", async () => {
    const big = Buffer.alloc(50 * 1024 * 1024 + 1);
    fs.writeFileSync(path.join(kbRoot, "huge.pdf"), big);
    const res = await POST(createShareRequest("huge.pdf"));
    expect(res.status).toBe(413);
  });
});
