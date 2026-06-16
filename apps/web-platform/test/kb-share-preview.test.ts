// Unit tests for previewShare() in server/kb-share.ts (#2322).
//
// Covers the view-parity MCP tool that lets the agent verify a share link
// renders correctly without issuing an HTTP fetch. Mirrors the terminal
// states of GET /api/shared/[token]: revoked, legacy-null-hash,
// workspace-unavailable, content-changed, access-denied, too-large.
//
// Mock strategy: real temp files + real validateBinaryFile / readContentRaw
// (no mocks of fs), so the hash gate is exercised end-to-end. pdfjs / sharp
// are isolated in server/kb-preview-metadata.ts and mocked here to control
// the firstPagePreview branch without bundling PDF/image fixtures.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash, randomUUID } from "node:crypto";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  }),
}));

const observabilityMocks = vi.hoisted(() => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => observabilityMocks);

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

// Spy-wrap openBinaryStream so tests can (a) assert `expected: { ino, size }`
// is passed on every call and (b) override with mockImplementationOnce to
// simulate TOCTOU drift without touching the filesystem. Default impl falls
// through to the real function so the happy-path tests exercise the real
// O_NOFOLLOW + fstat guard.
const openBinaryStreamSpy = vi.hoisted(() => vi.fn());
vi.mock("@/server/kb-binary-response", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/kb-binary-response")>();
  return {
    ...actual,
    openBinaryStream: openBinaryStreamSpy,
  };
});

const metadataMocks = vi.hoisted(() => ({
  readPdfMetadata: vi.fn(),
  readImageMetadata: vi.fn(),
}));
vi.mock("@/server/kb-preview-metadata", () => metadataMocks);

import { previewShare } from "@/server/kb-share";
import { shareSupabaseFromMock } from "./helpers/share-mocks";
import { makeUuidWorkspaceTmpdir } from "./helpers/workspace-tmpdir";

function hex(buf: Buffer): string {
  return createHash("sha256").update(buf).digest("hex");
}

let tmpWorkspace: string;
let kbRoot: string;

beforeEach(async () => {
  vi.clearAllMocks();
  openBinaryStreamSpy.mockReset();
  // Restore default behavior: delegate to the real openBinaryStream so
  // O_NOFOLLOW + fstat + expected-tuple check all run. Tests that need
  // TOCTOU drift simulate via mockImplementationOnce, which shadows this
  // default for exactly one call.
  const actual = await vi.importActual<
    typeof import("@/server/kb-binary-response")
  >("@/server/kb-binary-response");
  openBinaryStreamSpy.mockImplementation(actual.openBinaryStream);
  metadataMocks.readPdfMetadata.mockResolvedValue(null);
  metadataMocks.readImageMetadata.mockResolvedValue(null);
  tmpWorkspace = makeUuidWorkspaceTmpdir("kb-share-preview-").workspacePath;
  // ADR-044: previewShare resolves kbRoot via workspacePathForWorkspaceId
  // (`<WORKSPACES_ROOT>/<workspace_id>`). The mock derives workspace_id from
  // this dir's basename, so point WORKSPACES_ROOT at its parent.
  process.env.WORKSPACES_ROOT = path.dirname(tmpWorkspace);
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  delete process.env.WORKSPACES_ROOT;
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

function makeClient(
  opts: Parameters<typeof shareSupabaseFromMock>[0],
): { from: (table: string) => unknown } {
  const impl = shareSupabaseFromMock(opts);
  return { from: (table: string) => impl(table) };
}

// Most tests use the ready-workspace fixture. Unknown / revoked / null-hash
// tests override the share row or drop the users fixture.
function readyWorkspace() {
  return { workspacePath: tmpWorkspace, workspaceStatus: "ready" as const };
}

// -----------------------------------------------------------------------------
// Lookup / row-state branches (tests 1-6)
// -----------------------------------------------------------------------------

describe("previewShare — lookup and row-state branches", () => {
  it("returns 404 not-found for an unknown token (test 1)", async () => {
    // PostgREST returns `code: "PGRST116"` for zero-row results on `.single()`.
    // previewShare must interpret that as 404 not-found, distinct from a
    // genuine infrastructure error (test 6).
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: null,
        shareError: { code: "PGRST116", message: "0 rows" } as never,
      },
    });

    const result = await previewShare(client as never, "nope-nope-nope");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(404);
    expect(result.code).toBe("not-found");
  });

  it("returns 410 revoked for a revoked row (test 2)", async () => {
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "readme.md",
          revoked: true,
          content_sha256: hex(Buffer.from("x")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(410);
    expect(result.code).toBe("revoked");
  });

  it("returns 410 legacy-null-hash when content_sha256 is null (test 3)", async () => {
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "readme.md",
          revoked: false,
          content_sha256: null,
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(410);
    expect(result.code).toBe("legacy-null-hash");
  });

  it("resolves the KB root from the share's workspace_id, not the owner users row (tests 4-5, ADR-044)", async () => {
    // Regression guard for the shared-read 404 bug. The create path resolves
    // kbRoot via the workspace_id-keyed resolver, but this read path used to
    // gate on the owner's legacy users.workspace_status/workspace_path columns.
    // Those are stale/empty for users provisioned after the users → workspaces
    // relocation, so a freshly-created share 404'd even though the file exists.
    // Here the owner row is NOT "ready" (would have tripped the removed gate),
    // yet the document resolves and previews successfully off workspace_id.
    const bytes = Buffer.from("# resolves off workspace_id\n");
    fs.writeFileSync(path.join(kbRoot, "readme.md"), bytes);
    const client = makeClient({
      users: { workspacePath: tmpWorkspace, workspaceStatus: "provisioning" },
      kb_share_links: {
        shareRow: {
          document_path: "readme.md",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.status).toBe(200);
    expect(result.kind).toBe("markdown");
    expect(result.documentPath).toBe("readme.md");
  });

  it("resolves off workspace_id even when it DIFFERS from the owner's workspace_path (ADR-044 divergence)", async () => {
    // Stronger guard: the prior test couples workspace_id to the owner's
    // workspace_path (both basename to the same temp dir), so it cannot prove
    // the read keys off workspace_id rather than workspace_path. Here the two
    // DIVERGE — the file lives ONLY under the workspace_id-resolved dir, while
    // the owner's workspace_path points at a file-less dir. A regression that
    // re-read workspace_path would 404; resolving off workspace_id returns 200.
    const divergentId = randomUUID();
    const divergentKbRoot = path.join(
      // WORKSPACES_ROOT is set to dirname(tmpWorkspace) in beforeEach, so
      // workspacePathForWorkspaceId(divergentId) lands here.
      path.dirname(tmpWorkspace),
      divergentId,
      "knowledge-base",
    );
    fs.mkdirSync(divergentKbRoot, { recursive: true });
    const bytes = Buffer.from("# lives only under workspace_id\n");
    fs.writeFileSync(path.join(divergentKbRoot, "readme.md"), bytes);

    const client = makeClient({
      // Owner's legacy path points at tmpWorkspace, which does NOT contain the
      // file — only the divergent workspace_id dir does.
      users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
      kb_share_links: {
        shareRow: {
          document_path: "readme.md",
          revoked: false,
          content_sha256: hex(bytes),
          // Explicit workspace_id wins over the mock's basename derivation.
          workspace_id: divergentId,
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.status).toBe(200);
    expect(result.kind).toBe("markdown");
    expect(result.documentPath).toBe("readme.md");

    fs.rmSync(path.join(path.dirname(tmpWorkspace), divergentId), {
      recursive: true,
      force: true,
    });
  });

  it("returns 500 db-error and reports to Sentry on DB error (test 6)", async () => {
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: null,
        shareError: { message: "connection refused" },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(500);
    expect(result.code).toBe("db-error");
    expect(observabilityMocks.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = observabilityMocks.reportSilentFallback.mock.calls[0];
    expect(opts.feature).toBe("kb-share");
    expect(opts.op).toBe("preview");
  });
});

// -----------------------------------------------------------------------------
// Markdown branch (tests 7-10)
// -----------------------------------------------------------------------------

describe("previewShare — markdown branch", () => {
  it("returns 200 markdown metadata when hash matches (test 7)", async () => {
    const bytes = Buffer.from("# readme\n\nHello world.\n");
    fs.writeFileSync(path.join(kbRoot, "readme.md"), bytes);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "readme.md",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.status).toBe(200);
    expect(result.kind).toBe("markdown");
    expect(result.contentType).toBe("text/markdown");
    expect(result.size).toBe(bytes.length);
    expect(result.filename).toBe("readme.md");
    expect(result.documentPath).toBe("readme.md");
    expect(result.token).toBe("tok");
    expect(result.firstPagePreview).toBeUndefined();
  });

  it("flags hasDiagram + diagramModelBuilt=true when a likec4-view embed has a built model (test 7b)", async () => {
    const diagramsDir = path.join(kbRoot, "engineering/architecture/diagrams");
    fs.mkdirSync(diagramsDir, { recursive: true });
    fs.writeFileSync(
      path.join(diagramsDir, "model.likec4.json"),
      JSON.stringify({ views: { context: {} } }),
    );
    const bytes = Buffer.from(
      "# C4\n\n```likec4-view\ncontext\n```\n\nprose.\n",
    );
    fs.writeFileSync(
      path.join(diagramsDir, "c4-model.md"),
      bytes,
    );
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "engineering/architecture/diagrams/c4-model.md",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.kind).toBe("markdown");
    expect(result.hasDiagram).toBe(true);
    expect(result.diagramModelBuilt).toBe(true);
  });

  it("flags hasDiagram + diagramModelBuilt=false when the embed's model is NOT built (test 7c)", async () => {
    const diagramsDir = path.join(kbRoot, "engineering/architecture/diagrams");
    fs.mkdirSync(diagramsDir, { recursive: true });
    // No model.likec4.json written → recipient would see "model not built".
    const bytes = Buffer.from("# C4\n\n```likec4-view\ncontext\n```\n");
    fs.writeFileSync(path.join(diagramsDir, "c4-model.md"), bytes);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "engineering/architecture/diagrams/c4-model.md",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.hasDiagram).toBe(true);
    expect(result.diagramModelBuilt).toBe(false);
  });

  it("omits diagram fields for a plain markdown doc with no embed (test 7d)", async () => {
    const bytes = Buffer.from("# readme\n\nNo diagram here.\n");
    fs.writeFileSync(path.join(kbRoot, "plain.md"), bytes);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "plain.md",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.hasDiagram).toBeUndefined();
    expect(result.diagramModelBuilt).toBeUndefined();
  });

  it("returns 410 content-changed when disk buffer hash drifts (test 8)", async () => {
    fs.writeFileSync(path.join(kbRoot, "doc.md"), "v2 content");
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "doc.md",
          revoked: false,
          content_sha256: hex(Buffer.from("v1 content")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(410);
    expect(result.code).toBe("content-changed");
  });

  it("returns 404 not-found when markdown is missing from disk (test 9)", async () => {
    // share row exists but file deleted on disk → KbNotFoundError
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "ghost.md",
          revoked: false,
          content_sha256: hex(Buffer.from("irrelevant")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(404);
    expect(result.code).toBe("not-found");
  });

  it("returns 403 access-denied for markdown path with null byte (test 10)", async () => {
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "foo\0bar.md",
          revoked: false,
          content_sha256: hex(Buffer.from("x")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(403);
    expect(result.code).toBe("access-denied");
  });
});

// -----------------------------------------------------------------------------
// Binary branch (tests 11-15)
// -----------------------------------------------------------------------------

describe("previewShare — binary branch", () => {
  it("returns 200 binary metadata when hash matches (test 11)", async () => {
    const bytes = Buffer.from("%PDF-fake-bytes");
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), bytes);
    metadataMocks.readPdfMetadata.mockResolvedValue({
      kind: "pdf",
      width: 612,
      height: 792,
      numPages: 3,
    });
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "report.pdf",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.status).toBe(200);
    expect(result.kind).toBe("binary");
    expect(result.contentType).toBe("application/pdf");
    expect(result.size).toBe(bytes.length);
    expect(result.filename).toBe("report.pdf");
    expect(result.firstPagePreview).toEqual({
      kind: "pdf",
      width: 612,
      height: 792,
      numPages: 3,
    });
  });

  it("returns 410 content-changed on stream hash drift (test 12)", async () => {
    const onDisk = Buffer.from("%PDF-drifted");
    fs.writeFileSync(path.join(kbRoot, "report.pdf"), onDisk);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "report.pdf",
          revoked: false,
          content_sha256: hex(Buffer.from("%PDF-original")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(410);
    expect(result.code).toBe("content-changed");
  });

  it("returns 410 content-changed on inode drift between validate and hash (test 13)", async () => {
    const bytes = Buffer.from("%PDF-swap");
    fs.writeFileSync(path.join(kbRoot, "swap.pdf"), bytes);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "swap.pdf",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    // Simulate a rename-swap between validateBinaryFile (which captured the
    // original ino) and openBinaryStream (which fstats the new fd). The
    // TOCTOU guard inside openBinaryStream throws BinaryOpenError("content-
    // changed") when the second fd's ino differs from `expected.ino`.
    openBinaryStreamSpy.mockImplementationOnce(async () => {
      const { BinaryOpenError } = await import("@/server/kb-binary-response");
      throw new BinaryOpenError(
        404,
        "File changed between validation and read",
        "content-changed",
      );
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(410);
    expect(result.code).toBe("content-changed");
  });

  it("returns 413 too-large when file exceeds MAX_BINARY_SIZE (test 14)", async () => {
    // 50 MB + 1 byte to trigger KbFileTooLargeError via validateBinaryFile.
    // Use sparse-file trick to avoid actually writing 50 MB.
    const filePath = path.join(kbRoot, "huge.pdf");
    const fd = fs.openSync(filePath, "w");
    fs.ftruncateSync(fd, 50 * 1024 * 1024 + 1);
    fs.closeSync(fd);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "huge.pdf",
          revoked: false,
          content_sha256: hex(Buffer.from("irrelevant")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(413);
    expect(result.code).toBe("too-large");
  });

  it("returns 403 access-denied for a terminal symlink binary (test 15)", async () => {
    const target = path.join(kbRoot, "real.pdf");
    fs.writeFileSync(target, "%PDF-target");
    fs.symlinkSync(target, path.join(kbRoot, "link.pdf"));
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "link.pdf",
          revoked: false,
          content_sha256: hex(Buffer.from("irrelevant")),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(false);
    if (result.ok) throw new Error("unreachable");
    expect(result.status).toBe(403);
    expect(result.code).toBe("access-denied");
  });
});

// -----------------------------------------------------------------------------
// First-page preview branch (tests 16-20)
// -----------------------------------------------------------------------------

describe("previewShare — first-page preview branch", () => {
  it("attaches PDF firstPagePreview via pdfjs metadata (test 16)", async () => {
    const bytes = Buffer.from("%PDF-multi");
    fs.writeFileSync(path.join(kbRoot, "multi.pdf"), bytes);
    metadataMocks.readPdfMetadata.mockResolvedValue({
      kind: "pdf",
      width: 595,
      height: 842,
      numPages: 42,
    });
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "multi.pdf",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.firstPagePreview).toBeDefined();
    expect(result.firstPagePreview).toEqual({
      kind: "pdf",
      width: 595,
      height: 842,
      numPages: 42,
    });
    // Narrow union: only PdfPreview carries numPages.
    if (result.firstPagePreview?.kind === "pdf") {
      expect(result.firstPagePreview.numPages).toBeGreaterThanOrEqual(1);
    } else {
      throw new Error("expected pdf firstPagePreview");
    }
    expect(metadataMocks.readPdfMetadata).toHaveBeenCalledTimes(1);
  });

  it("silent-fallbacks to undefined firstPagePreview on PDF parse failure (test 17)", async () => {
    const bytes = Buffer.from("not really a pdf");
    fs.writeFileSync(path.join(kbRoot, "corrupt.pdf"), bytes);
    metadataMocks.readPdfMetadata.mockResolvedValue(null);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "corrupt.pdf",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.firstPagePreview).toBeUndefined();
    // Core metadata still present.
    expect(result.contentType).toBe("application/pdf");
    expect(result.size).toBe(bytes.length);
  });

  it("attaches image firstPagePreview via sharp metadata (test 18)", async () => {
    const bytes = Buffer.from("\x89PNG-fake");
    fs.writeFileSync(path.join(kbRoot, "diagram.png"), bytes);
    metadataMocks.readImageMetadata.mockResolvedValue({
      kind: "image",
      width: 1024,
      height: 768,
      format: "png",
    });
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "diagram.png",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.firstPagePreview).toEqual({
      kind: "image",
      width: 1024,
      height: 768,
      format: "png",
    });
    expect(metadataMocks.readImageMetadata).toHaveBeenCalledTimes(1);
  });

  it("silent-fallbacks to undefined firstPagePreview on image parse failure (test 19)", async () => {
    const bytes = Buffer.from("corrupt-image");
    fs.writeFileSync(path.join(kbRoot, "bad.png"), bytes);
    metadataMocks.readImageMetadata.mockResolvedValue(null);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "bad.png",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.firstPagePreview).toBeUndefined();
    expect(result.contentType).toBe("image/png");
  });

  it("omits firstPagePreview for non-pdf/non-image binaries (test 20)", async () => {
    const bytes = Buffer.from("PK\x03\x04docx-fake");
    fs.writeFileSync(path.join(kbRoot, "manual.docx"), bytes);
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "manual.docx",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.firstPagePreview).toBeUndefined();
    expect(result.kind).toBe("binary");
    // docx maps to the OpenXML content-type, NOT a preview-eligible type.
    expect(result.contentType).toContain(
      "application/vnd.openxmlformats-officedocument",
    );
    // Non-preview kinds must not invoke pdfjs or sharp.
    expect(metadataMocks.readPdfMetadata).not.toHaveBeenCalled();
    expect(metadataMocks.readImageMetadata).not.toHaveBeenCalled();
  });
});

// -----------------------------------------------------------------------------
// Mock-shape assertions (tests 21-22)
// -----------------------------------------------------------------------------

describe("previewShare — mock-shape invariants", () => {
  it("Supabase lookup filters on .eq('token', token) (test 21)", async () => {
    // Capture every .eq() arg via a recording spy. shareSupabaseFromMock
    // returns a chain; we wrap .from to record the eq sequence for
    // kb_share_links.
    const eqCalls: Array<[string, unknown]> = [];
    const base = shareSupabaseFromMock({
      users: readyWorkspace(),
      kb_share_links: { shareRow: null, shareError: null },
    });
    const client = {
      from: (table: string) => {
        const chain = base(table) as Record<string, unknown>;
        if (table !== "kb_share_links") return chain;
        const select = chain.select as (cols: string) => Record<string, unknown>;
        return {
          ...chain,
          select: (cols: string) => {
            const eqChain = select(cols) as Record<string, unknown>;
            const originalEq = eqChain.eq as (c: string, v: unknown) => unknown;
            eqChain.eq = (col: string, val: unknown) => {
              eqCalls.push([col, val]);
              return originalEq(col, val);
            };
            return eqChain;
          },
        };
      },
    };

    await previewShare(client as never, "my-token-value");

    expect(eqCalls[0]).toEqual(["token", "my-token-value"]);
  });

  it("passes expected:{ino,size} on every openBinaryStream call (test 22)", async () => {
    const bytes = Buffer.from("%PDF-expected-check");
    fs.writeFileSync(path.join(kbRoot, "check.pdf"), bytes);
    metadataMocks.readPdfMetadata.mockResolvedValue({
      kind: "pdf",
      width: 100,
      height: 100,
      numPages: 1,
    });
    const client = makeClient({
      users: readyWorkspace(),
      kb_share_links: {
        shareRow: {
          document_path: "check.pdf",
          revoked: false,
          content_sha256: hex(bytes),
        },
      },
    });

    const result = await previewShare(client as never, "tok");
    expect(result.ok).toBe(true);

    // At least two calls: one for hash gate, one for preview-metadata drain.
    expect(openBinaryStreamSpy.mock.calls.length).toBeGreaterThanOrEqual(2);
    for (const [, opts] of openBinaryStreamSpy.mock.calls) {
      expect(opts).toBeDefined();
      expect(opts.expected).toBeDefined();
      expect(typeof opts.expected.ino).toBe("number");
      expect(typeof opts.expected.size).toBe("number");
      expect(opts.expected.size).toBe(bytes.length);
    }
  });
});
