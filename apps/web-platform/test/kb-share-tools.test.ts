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
}));

vi.mock("@/server/kb-share", () => ({
  createShare: mocks.createShare,
  listShares: mocks.listShares,
  revokeShare: mocks.revokeShare,
}));

// Verbatim copy of REVOKE_PURGE_FAILED_MESSAGE from server/kb-share.ts.
// Cannot import the real constant — this test fully mocks @/server/kb-share
// so an import would resolve to undefined. Drift between this literal and
// the real constant is caught by the kb-share.test.ts assertion which DOES
// import the real symbol.
const REVOKE_PURGE_FAILED_MESSAGE =
  "Revoke succeeded but cache purge failed; share may be served from cache for up to 60 seconds";

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

describe("buildKbShareTools — registration", () => {
  it("returns four tools: kb_share_create, kb_share_list, kb_share_revoke, kb_share_preview", () => {
    const tools = buildKbShareTools(baseDeps);
    const names = (
      tools as unknown as Array<{ name: string }>
    ).map((t) => t.name);
    expect(names).toEqual([
      "kb_share_create",
      "kb_share_list",
      "kb_share_revoke",
      "kb_share_preview",
    ]);
  });
});

describe("kb_share_create handler", () => {
  it("wraps success into content text with absolute URL", async () => {
    mocks.createShare.mockResolvedValue({
      ok: true,
      token: "tok-abc",
      url: "/shared/tok-abc",
      documentPath: "readme.md",
      size: 42,
    });
    const tools = buildKbShareTools(baseDeps);
    const createTool = findTool(tools, "kb_share_create");

    const result = await createTool.handler({ documentPath: "readme.md" });

    expect(result.isError).toBeFalsy();
    const payload = JSON.parse(result.content[0].text);
    expect(payload.token).toBe("tok-abc");
    expect(payload.documentPath).toBe("readme.md");
    expect(payload.size).toBe(42);
    // MCP tool returns absolute URL so agent can paste verbatim.
    expect(payload.url).toBe("https://app.soleur.ai/shared/tok-abc");
    expect(mocks.createShare).toHaveBeenCalledWith(
      baseDeps.serviceClient,
      "user-1",
      baseDeps.kbRoot,
      "readme.md",
    );
  });

  it("wraps failure with isError: true and surfaces the error message", async () => {
    mocks.createShare.mockResolvedValue({
      ok: false,
      status: 413,
      code: "too-large",
      error: "File exceeds maximum size limit",
    });
    const tools = buildKbShareTools(baseDeps);
    const createTool = findTool(tools, "kb_share_create");

    const result = await createTool.handler({ documentPath: "huge.pdf" });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("File exceeds maximum size limit");
    expect(result.content[0].text).toContain("too-large");
  });
});

describe("kb_share_list handler", () => {
  it("wraps success into JSON array text", async () => {
    mocks.listShares.mockResolvedValue({
      ok: true,
      shares: [
        {
          token: "t1",
          documentPath: "a.md",
          createdAt: "2026-04-17T00:00:00Z",
          revoked: false,
        },
      ],
    });
    const tools = buildKbShareTools(baseDeps);
    const listTool = findTool(tools, "kb_share_list");

    const result = await listTool.handler({});

    expect(result.isError).toBeFalsy();
    const payload = JSON.parse(result.content[0].text);
    expect(payload.shares).toHaveLength(1);
    expect(payload.shares[0].token).toBe("t1");
  });

  it("forwards documentPath filter when provided", async () => {
    mocks.listShares.mockResolvedValue({ ok: true, shares: [] });
    const tools = buildKbShareTools(baseDeps);
    const listTool = findTool(tools, "kb_share_list");

    await listTool.handler({ documentPath: "readme.md" });

    expect(mocks.listShares).toHaveBeenCalledWith(
      baseDeps.serviceClient,
      "user-1",
      { documentPath: "readme.md" },
    );
  });
});

describe("kb_share_revoke handler", () => {
  it("wraps success into content text including documentPath", async () => {
    mocks.revokeShare.mockResolvedValue({
      ok: true,
      token: "tok-1",
      documentPath: "readme.md",
    });
    const tools = buildKbShareTools(baseDeps);
    const revokeTool = findTool(tools, "kb_share_revoke");

    const result = await revokeTool.handler({ token: "tok-1" });

    expect(result.isError).toBeFalsy();
    const payload = JSON.parse(result.content[0].text);
    expect(payload.revoked).toBe(true);
    expect(payload.token).toBe("tok-1");
    expect(payload.documentPath).toBe("readme.md");
  });

  it("surfaces 403 forbidden as isError with human-readable message", async () => {
    mocks.revokeShare.mockResolvedValue({
      ok: false,
      status: 403,
      code: "forbidden",
      error: "Forbidden",
    });
    const tools = buildKbShareTools(baseDeps);
    const revokeTool = findTool(tools, "kb_share_revoke");

    const result = await revokeTool.handler({ token: "not-mine" });

    expect(result.isError).toBe(true);
    expect(result.content[0].text).toContain("Forbidden");
    expect(result.content[0].text).toContain("forbidden");
  });

  it("surfaces 502 purge-failed verbatim so the agent caller sees the bounded leak window", async () => {
    mocks.revokeShare.mockResolvedValue({
      ok: false,
      status: 502,
      code: "purge-failed",
      error:
        REVOKE_PURGE_FAILED_MESSAGE,
    });
    const tools = buildKbShareTools(baseDeps);
    const revokeTool = findTool(tools, "kb_share_revoke");

    const result = await revokeTool.handler({ token: "tok-1" });

    expect(result.isError).toBe(true);
    const payload = JSON.parse(result.content[0].text);
    expect(payload.status).toBe(502);
    expect(payload.code).toBe("purge-failed");
    expect(payload.error).toBe(
      REVOKE_PURGE_FAILED_MESSAGE,
    );
  });
});
