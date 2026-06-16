import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { randomUUID } from "node:crypto";
import { MAX_BINARY_SIZE } from "@/server/kb-limits";

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

// PR-C §2.8 (#3244): kb-route-helpers tenant migration.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mocks.mockServiceFrom })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mocks.mockValidateOrigin,
  rejectCsrf: mocks.mockRejectCsrf,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
}));

// NOTE: isPathInWorkspace is intentionally NOT mocked — we use a real temp
// workspace so lstat + isFile + isSymbolicLink checks exercise the real FS.

import { POST } from "@/app/api/kb/share/route";
import { shareSupabaseFromMock } from "./helpers/share-mocks";

let workspacesRoot: string;
let tmpWorkspace: string;
let kbRoot: string;
const TEST_USER_ID = randomUUID();

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
  // ADR-044: the route now resolves the kbRoot via resolveActiveWorkspaceKbRoot,
  // which derives the workspace path as `<WORKSPACES_ROOT>/<active_workspace_id>`
  // (NOT users.workspace_path). For a solo caller the active id === userId, so
  // create the workspace dir AT that path and point WORKSPACES_ROOT at its parent.
  workspacesRoot = fs.mkdtempSync(path.join(os.tmpdir(), "kb-share-paths-"));
  process.env.WORKSPACES_ROOT = workspacesRoot;
  tmpWorkspace = path.join(workspacesRoot, TEST_USER_ID);
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });

  mocks.mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "http://localhost:3000",
  });
  mocks.mockGetUser.mockResolvedValue({
    data: { user: { id: TEST_USER_ID } },
  });

  // Solo, connected, ready active workspace (current_workspace_id null → solo
  // == userId; repo_status ready; users.workspace_status ready).
  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: { shareRow: null, shareError: null },
    }),
  );
});

afterEach(() => {
  fs.rmSync(workspacesRoot, { recursive: true, force: true });
  delete process.env.WORKSPACES_ROOT;
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
    const big = Buffer.alloc(MAX_BINARY_SIZE + 1);
    fs.writeFileSync(path.join(kbRoot, "huge.pdf"), big);
    const res = await POST(createShareRequest("huge.pdf"));
    expect(res.status).toBe(413);
  });

  it("forwards the resolver's active id into the createShare insert workspace_id", async () => {
    // Regression guard for the ADR-044 swap: the route must write the
    // workspace_id resolved by resolveActiveWorkspaceKbRoot (access.activeWorkspaceId),
    // NOT a hardcoded user.id or an undefined/wrong field — kb_share_links.workspace_id
    // is NOT NULL (migration 059) and feeds the workspace-member RLS policy. The
    // membership self-heal that makes active-id ≠ user.id on a stale claim is
    // covered at the resolver level by workspace-resolver-repo-meta.test.ts; here
    // we pin that whatever the resolver returns reaches the insert payload.
    const insertSpy = vi.fn().mockResolvedValue({ error: null });
    mocks.mockServiceFrom.mockImplementation(
      shareSupabaseFromMock({
        users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
        kb_share_links: { shareRow: null, shareError: null, insertSpy },
      }),
    );
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# hi");
    const res = await POST(createShareRequest("readme.md"));
    expect(res.status).toBe(201);
    expect(insertSpy).toHaveBeenCalledTimes(1);
    // Solo caller: resolver's active id === user.id; the assertion proves the
    // route sources workspace_id from the resolver path (not a literal/undefined).
    expect(insertSpy.mock.calls[0][0].workspace_id).toBe(TEST_USER_ID);
  });
});

describe("KB share — resolver failure surfaces correct HTTP status (Workstream B)", () => {
  it("returns 404 when the active workspace has no connected repo", async () => {
    // resolveActiveWorkspaceKbRoot returns {ok:false,404} when repo_status is
    // not_connected — the share route must map it straight through.
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# hi");
    mocks.mockServiceFrom.mockImplementation(
      shareSupabaseFromMock({
        users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
        kb_share_links: { shareRow: null, shareError: null },
        activeWorkspace: { repoStatus: "not_connected" },
      }),
    );
    const res = await POST(createShareRequest("readme.md"));
    expect(res.status).toBe(404);
  });

  it("returns 503 when the active workspace owner is not ready", async () => {
    // resolveActiveWorkspaceKbRoot returns {ok:false,503} when the owner's
    // users.workspace_status !== "ready".
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# hi");
    mocks.mockServiceFrom.mockImplementation(
      shareSupabaseFromMock({
        users: { workspacePath: tmpWorkspace, workspaceStatus: "provisioning" },
        kb_share_links: { shareRow: null, shareError: null },
      }),
    );
    const res = await POST(createShareRequest("readme.md"));
    expect(res.status).toBe(503);
  });
});
