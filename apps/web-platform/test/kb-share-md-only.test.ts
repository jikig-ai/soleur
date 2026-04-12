import { describe, it, expect, vi, beforeEach } from "vitest";

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

vi.mock("@/server/sandbox", () => ({
  isPathInWorkspace: vi.fn(() => true),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
}));

import { POST } from "@/app/api/kb/share/route";

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

describe("KB share .md-only restriction", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.mockValidateOrigin.mockReturnValue({
      valid: true,
      origin: "http://localhost:3000",
    });
    mocks.mockGetUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
    // Build a chainable query mock that supports arbitrary .eq() depth
    const makeChain = (terminal: Record<string, unknown>) => {
      const chain: Record<string, unknown> = { ...terminal };
      chain.eq = vi.fn().mockReturnValue(chain);
      return chain;
    };

    // Track call count to return different chains per .from() call
    let fromCallCount = 0;
    mocks.mockServiceFrom.mockImplementation(() => {
      fromCallCount++;
      if (fromCallCount === 1) {
        // First call: users table query
        return {
          select: vi.fn().mockReturnValue(
            makeChain({
              single: vi.fn().mockResolvedValue({
                data: {
                  workspace_path: "/tmp/test-workspace",
                  workspace_status: "ready",
                },
                error: null,
              }),
            }),
          ),
        };
      }
      // Second call: kb_share_links check for existing
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

  it("allows share creation for .md files", async () => {
    const req = createShareRequest("docs/readme.md");
    const res = await POST(req);
    expect(res.status).not.toBe(400);
  });

  it("rejects share creation for .png files with 400", async () => {
    const req = createShareRequest("images/screenshot.png");
    const res = await POST(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Only markdown files can be shared");
  });

  it("rejects share creation for .pdf files with 400", async () => {
    const req = createShareRequest("docs/report.pdf");
    const res = await POST(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Only markdown files can be shared");
  });

  it("rejects share creation for .csv files with 400", async () => {
    const req = createShareRequest("data/export.csv");
    const res = await POST(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Only markdown files can be shared");
  });

  it("rejects share creation for files without extension with 400", async () => {
    const req = createShareRequest("docs/README");
    const res = await POST(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Only markdown files can be shared");
  });
});
