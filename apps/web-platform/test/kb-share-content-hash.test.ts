import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";
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

import { POST } from "@/app/api/kb/share/route";
import { shareSupabaseFromMock } from "./helpers/share-mocks";

function hex(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

let workspacesRoot: string;
let tmpWorkspace: string;
let kbRoot: string;
const TEST_USER_ID = randomUUID();
let insertSpy: ReturnType<
  typeof vi.fn<(payload: { content_sha256: string }) => Promise<{ error: null }>>
>;
let updateSpy: ReturnType<typeof vi.fn<(payload: unknown) => Promise<{ error: null }>>>;
let existingShare: { id: string; token: string; content_sha256: string | null } | null;

function createShareRequest(documentPath: string): Request {
  return new Request("http://localhost:3000/api/kb/share", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Origin: "http://localhost:3000",
    },
    body: JSON.stringify({ documentPath }),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  // ADR-044: the route resolves kbRoot via resolveActiveWorkspaceKbRoot, which
  // derives the path as `<WORKSPACES_ROOT>/<active_id>` (solo: active id ===
  // userId). Create the workspace dir at that path; point WORKSPACES_ROOT at it.
  workspacesRoot = fs.mkdtempSync(path.join(os.tmpdir(), "kb-share-hash-"));
  process.env.WORKSPACES_ROOT = workspacesRoot;
  tmpWorkspace = path.join(workspacesRoot, TEST_USER_ID);
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });

  insertSpy = vi.fn().mockResolvedValue({ error: null });
  updateSpy = vi.fn().mockResolvedValue({ error: null });
  existingShare = null;

  mocks.mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "http://localhost:3000",
  });
  mocks.mockGetUser.mockResolvedValue({
    data: { user: { id: TEST_USER_ID } },
  });

  mocks.mockServiceFrom.mockImplementation(
    shareSupabaseFromMock({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        // existingShare is mutated per-test; getter resolves at call time.
        shareRow: () => existingShare,
        shareError: null,
        insertSpy,
        updateSpy,
      },
    }),
  );
});

afterEach(() => {
  fs.rmSync(workspacesRoot, { recursive: true, force: true });
  delete process.env.WORKSPACES_ROOT;
});

describe("KB share — content hash", () => {
  it("persists SHA-256 of file bytes in the insert payload", async () => {
    const bytes = Buffer.from("hash-me plz");
    fs.writeFileSync(path.join(kbRoot, "note.md"), bytes);
    const expected = hex(bytes);

    const res = await POST(createShareRequest("note.md"));
    expect(res.status).toBe(201);
    expect(insertSpy).toHaveBeenCalledTimes(1);
    const payload = insertSpy.mock.calls[0][0];
    expect(payload.content_sha256).toBe(expected);
    expect(payload.content_sha256).toMatch(/^[a-f0-9]{64}$/);
  });

  it("hashes a PDF (binary) identically to hashBytes on its raw bytes", async () => {
    const bytes = Buffer.from([0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34, 0x00, 0xff, 0xfe]);
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), bytes);
    const expected = hex(bytes);

    const res = await POST(createShareRequest("doc.pdf"));
    expect(res.status).toBe(201);
    const payload = insertSpy.mock.calls[0][0];
    expect(payload.content_sha256).toBe(expected);
  });

  it("returns the existing token (no new insert) when the file bytes match the stored hash", async () => {
    const bytes = Buffer.from("same content");
    fs.writeFileSync(path.join(kbRoot, "doc.md"), bytes);
    existingShare = {
      id: "share-1",
      token: "existing-token",
      content_sha256: hex(bytes),
    };

    const res = await POST(createShareRequest("doc.md"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.token).toBe("existing-token");
    expect(insertSpy).not.toHaveBeenCalled();
  });

  it("revokes the stale row and issues a new token when content changed since the original share", async () => {
    const newBytes = Buffer.from("version 2");
    fs.writeFileSync(path.join(kbRoot, "doc.md"), newBytes);
    existingShare = {
      id: "share-1",
      token: "stale-token",
      content_sha256: hex(Buffer.from("version 1")),
    };

    const res = await POST(createShareRequest("doc.md"));
    expect(res.status).toBe(201);
    expect(updateSpy).toHaveBeenCalled();
    expect(insertSpy).toHaveBeenCalledTimes(1);
    const payload = insertSpy.mock.calls[0][0];
    expect(payload.content_sha256).toBe(hex(newBytes));
    const body = await res.json();
    expect(body.token).not.toBe("stale-token");
  });

  it("rejects a symlink even if the target is a regular file (O_NOFOLLOW guard)", async () => {
    const outside = path.join(tmpWorkspace, "real.md");
    fs.writeFileSync(outside, "x");
    fs.symlinkSync(outside, path.join(kbRoot, "link.md"));

    const res = await POST(createShareRequest("link.md"));
    // lstat already rejects symlinks with 400 — confirm the post-hash path never runs.
    expect(res.status).toBe(400);
    expect(insertSpy).not.toHaveBeenCalled();
  });
});
