// Unit tests for the kb_share_preview MCP wrapper in server/kb-share-tools.ts.
// previewShare() itself is mocked — these tests cover only the wrap layer
// (registration, JSON envelope shape, isError routing, negative-space
// delegation gate).

import fs from "node:fs";
import path from "node:path";
import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: Function) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

const mocks = vi.hoisted(() => ({
  createShare: vi.fn(),
  listShares: vi.fn(),
  revokeShare: vi.fn(),
  previewShare: vi.fn(),
}));

vi.mock("@/server/kb-share", () => ({
  createShare: mocks.createShare,
  listShares: mocks.listShares,
  revokeShare: mocks.revokeShare,
  previewShare: mocks.previewShare,
}));

import { buildKbShareTools } from "@/server/kb-share-tools";

type ToolHandler = (args: Record<string, unknown>) => Promise<{
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}>;

function findTool(
  tools: ReturnType<typeof buildKbShareTools>,
  name: string,
): { name: string; handler: ToolHandler } {
  const t = (tools as unknown as Array<{ name: string; handler: ToolHandler }>).find(
    (x) => x.name === name,
  );
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

const baseDeps = {
  serviceClient: {} as never,
  userId: "user-1",
  kbRoot: "/workspace/knowledge-base",
  baseUrl: "https://app.soleur.ai",
};

beforeEach(() => {
  vi.clearAllMocks();
});

// -----------------------------------------------------------------------------
// Registration (test 23)
// -----------------------------------------------------------------------------

describe("buildKbShareTools — registration with preview", () => {
  it("registers kb_share_preview as the fourth tool (test 23)", () => {
    const tools = buildKbShareTools(baseDeps);
    const names = (tools as unknown as Array<{ name: string }>).map(
      (t) => t.name,
    );
    expect(names).toEqual([
      "kb_share_create",
      "kb_share_list",
      "kb_share_revoke",
      "kb_share_preview",
    ]);
  });
});

// -----------------------------------------------------------------------------
// kb_share_preview handler — success + isError shapes (tests 24-27)
// -----------------------------------------------------------------------------

describe("kb_share_preview handler", () => {
  it("wraps success into content text with ok:true-style payload (test 24)", async () => {
    mocks.previewShare.mockResolvedValue({
      ok: true,
      status: 200,
      token: "tok-1",
      documentPath: "report.pdf",
      kind: "binary",
      contentType: "application/pdf",
      size: 12345,
      filename: "report.pdf",
      firstPagePreview: { kind: "pdf", width: 612, height: 792, numPages: 3 },
    });
    const tools = buildKbShareTools(baseDeps);
    const previewTool = findTool(tools, "kb_share_preview");

    const result = await previewTool.handler({ token: "tok-1" });

    expect(result.isError).toBeFalsy();
    const payload = JSON.parse(result.content[0].text);
    expect(payload.kind).toBe("binary");
    expect(payload.contentType).toBe("application/pdf");
    expect(payload.size).toBe(12345);
    expect(payload.filename).toBe("report.pdf");
    expect(payload.firstPagePreview.numPages).toBe(3);
    expect(mocks.previewShare).toHaveBeenCalledWith(
      baseDeps.serviceClient,
      "tok-1",
    );
  });

  it("wraps revoked with isError: true (test 25)", async () => {
    mocks.previewShare.mockResolvedValue({
      ok: false,
      status: 410,
      code: "revoked",
      error: "This link has been disabled",
    });
    const tools = buildKbShareTools(baseDeps);
    const previewTool = findTool(tools, "kb_share_preview");

    const result = await previewTool.handler({ token: "tok-dead" });

    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0].text);
    expect(payload.code).toBe("revoked");
    expect(payload.status).toBe(410);
  });

  it("wraps content-changed with isError: true (test 26)", async () => {
    mocks.previewShare.mockResolvedValue({
      ok: false,
      status: 410,
      code: "content-changed",
      error: "Document no longer matches share snapshot",
    });
    const tools = buildKbShareTools(baseDeps);
    const previewTool = findTool(tools, "kb_share_preview");

    const result = await previewTool.handler({ token: "tok-drift" });

    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0].text);
    expect(payload.code).toBe("content-changed");
  });

  it("wraps not-found with isError: true (test 27)", async () => {
    mocks.previewShare.mockResolvedValue({
      ok: false,
      status: 404,
      code: "not-found",
      error: "Not found",
    });
    const tools = buildKbShareTools(baseDeps);
    const previewTool = findTool(tools, "kb_share_preview");

    const result = await previewTool.handler({ token: "tok-gone" });

    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0].text);
    expect(payload.code).toBe("not-found");
    expect(payload.status).toBe(404);
  });

  it("does not leak raw token into error text (test 28)", async () => {
    const secretToken =
      "sk_secret_token_should_not_appear_verbatim_in_errors_12345";
    mocks.previewShare.mockResolvedValue({
      ok: false,
      status: 410,
      code: "revoked",
      error: "This link has been disabled",
    });
    const tools = buildKbShareTools(baseDeps);
    const previewTool = findTool(tools, "kb_share_preview");

    const result = await previewTool.handler({ token: secretToken });

    expect(result.isError).toBe(true);
    // The wrapper relays previewShare's error/code/status verbatim — the
    // raw token must never be echoed unless the underlying call deliberately
    // put it there. The previewShare mock here returns no token field, so
    // the text body must not contain the token as a side-effect leak.
    expect(result.content[0].text).not.toContain(secretToken);
  });
});

// -----------------------------------------------------------------------------
// Negative-space delegation gate (test 34)
// -----------------------------------------------------------------------------

describe("kb-share-tools.ts — no direct filesystem / path-validation imports (test 34)", () => {
  it("server/kb-share-tools.ts has no direct fs/path-validation imports or call sites", () => {
    const filePath = path.resolve(__dirname, "../server/kb-share-tools.ts");
    const src = fs.readFileSync(filePath, "utf-8");

    // Negative-only gates: the wrapper must never duplicate traversal,
    // symlink, null-byte, or fs-open logic. All filesystem + path validation
    // lives in server/kb-share.ts (transitively via validateBinaryFile /
    // readContentRaw). Positive delegation assertions are covered by the
    // mocked-behavior tests above.
    expect(src).not.toMatch(/from\s+["']node:fs["']/);
    expect(src).not.toMatch(/from\s+["']fs["']/);
    expect(src).not.toMatch(/\bisPathInWorkspace\b/);
    expect(src).not.toMatch(/\bvalidateBinaryFile\b/);
    expect(src).not.toMatch(/\breadContentRaw\b/);
    // path.join is conservatively rejected too — base-URL concat uses
    // template-string, not path.join. Any path.join use in this file would
    // be a signal the wrapper is re-doing kb-share.ts's job.
    expect(src).not.toMatch(/\bpath\.join\b/);
  });
});
