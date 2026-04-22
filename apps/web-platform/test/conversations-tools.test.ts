import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for #2512 — `conversations_lookup` MCP tool.
//
// Contract (from plan Phase 4):
//   buildConversationsTools({ userId }) returns an array containing exactly
//   ONE tool — no `_list`, no `_archive` (those are deferred P3 items).
//   The tool's name is "conversations_lookup".
//
//   Handler behavior (delegates to lookupConversationForPath):
//     - Hit row: returns ToolTextResponse with JSON camelCase shape
//       { conversationId, contextPath, lastActive, messageCount }.
//     - Miss (row null): returns ToolTextResponse whose content[0].text
//       parses to JS `null`.
//     - Helper error { ok: false, error: "lookup_failed" }: returns
//       ToolTextResponse with isError: true.
//
//   userId captured in closure: two builders with different userIds must
//   invoke the helper with their respective userIds (no cross-contamination).

const { mockLookup, mockUserRepoUrl } = vi.hoisted(() => ({
  mockLookup: vi.fn(),
  mockUserRepoUrl: vi.fn(() => "https://github.com/acme/repo" as string | null),
}));

vi.mock("@/server/lookup-conversation-for-path", () => ({
  lookupConversationForPath: (...args: unknown[]) => mockLookup(...args),
}));

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: (...args: unknown[]) => {
    void args;
    return Promise.resolve(mockUserRepoUrl());
  },
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (
      name: string,
      description: string,
      schema: unknown,
      handler: Function,
    ) => ({ name, description, schema, handler }),
  ),
}));

async function importBuilder() {
  return await import("@/server/conversations-tools");
}

type ToolStub = {
  name: string;
  description: string;
  schema: Record<string, unknown>;
  handler: (args: Record<string, unknown>) => Promise<unknown>;
};

async function getTool(name: string, userId = "u1"): Promise<ToolStub> {
  const { buildConversationsTools } = await importBuilder();
  const tools = buildConversationsTools({ userId }) as unknown as ToolStub[];
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not found`);
  return t;
}

describe("buildConversationsTools", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("returns five tools (lookup + list + archive + unarchive + update_status)", async () => {
    const { buildConversationsTools } = await importBuilder();
    const tools = buildConversationsTools({ userId: "u1" });
    expect(tools).toHaveLength(5);
  });

  test("exposes conversations_lookup", async () => {
    const { buildConversationsTools } = await importBuilder();
    const names = (
      buildConversationsTools({ userId: "u1" }) as unknown as Array<{ name: string }>
    ).map((t) => t.name);
    expect(names).toContain("conversations_lookup");
  });

  test("exposes conversations_list, conversation_archive, conversation_unarchive, conversation_update_status (#2776)", async () => {
    const { buildConversationsTools } = await importBuilder();
    const names = (
      buildConversationsTools({ userId: "u1" }) as unknown as Array<{ name: string }>
    ).map((t) => t.name);
    expect(names).toContain("conversations_list");
    expect(names).toContain("conversation_archive");
    expect(names).toContain("conversation_unarchive");
    expect(names).toContain("conversation_update_status");
  });

  test("hit path: returns camelCase JSON payload (not isError)", async () => {
    mockLookup.mockResolvedValue({
      ok: true,
      row: {
        id: "conv-1",
        context_path: "knowledge-base/x.md",
        last_active: "2026-04-17T00:00:00Z",
        message_count: 7,
      },
    });
    const t = await getTool("conversations_lookup");
    const res = (await t.handler({
      contextPath: "knowledge-base/x.md",
    })) as {
      content: Array<{ text: string }>;
      isError?: boolean;
    };
    expect(res.isError).toBeFalsy();
    expect(JSON.parse(res.content[0].text)).toEqual({
      conversationId: "conv-1",
      contextPath: "knowledge-base/x.md",
      lastActive: "2026-04-17T00:00:00Z",
      messageCount: 7,
    });
  });

  test("miss path: returns JSON `null` (not isError)", async () => {
    mockLookup.mockResolvedValue({ ok: true, row: null });
    const t = await getTool("conversations_lookup");
    const res = (await t.handler({
      contextPath: "knowledge-base/x.md",
    })) as {
      content: Array<{ text: string }>;
      isError?: boolean;
    };
    expect(res.isError).toBeFalsy();
    expect(JSON.parse(res.content[0].text)).toBeNull();
  });

  test("error path: sets isError: true with code `lookup_failed`", async () => {
    mockLookup.mockResolvedValue({ ok: false, error: "lookup_failed" });
    const t = await getTool("conversations_lookup");
    const res = (await t.handler({
      contextPath: "knowledge-base/x.md",
    })) as {
      content: Array<{ text: string }>;
      isError?: boolean;
    };
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("lookup_failed");
  });

  test("closure captures userId — distinct builders isolate per-user queries", async () => {
    mockLookup.mockResolvedValue({ ok: true, row: null });
    const toolA = await getTool("conversations_lookup", "user-a");
    const toolB = await getTool("conversations_lookup", "user-b");

    await toolA.handler({ contextPath: "knowledge-base/x.md" });
    await toolB.handler({ contextPath: "knowledge-base/x.md" });

    expect(mockLookup).toHaveBeenNthCalledWith(
      1,
      "user-a",
      "knowledge-base/x.md",
      "https://github.com/acme/repo",
    );
    expect(mockLookup).toHaveBeenNthCalledWith(
      2,
      "user-b",
      "knowledge-base/x.md",
      "https://github.com/acme/repo",
    );
  });

  test("Zod schema rejects missing contextPath via safeParse", async () => {
    const zodMod = await import("zod/v4");
    const t = await getTool("conversations_lookup");
    // Run the actual Zod parse against a missing-field input. A schema that
    // accepted `z.any()` by mistake would pass here; `z.string()` does not.
    const schema = zodMod.z.object(
      t.schema as Parameters<typeof zodMod.z.object>[0],
    );
    const result = schema.safeParse({});
    expect(result.success).toBe(false);
  });

  test("invalid contextPath: returns isError with code invalid_context_path", async () => {
    const t = await getTool("conversations_lookup");
    // Path without the "knowledge-base/" prefix is rejected by validateContextPath.
    const res = (await t.handler({ contextPath: "not-a-kb-path.md" })) as {
      content: Array<{ text: string }>;
      isError?: boolean;
    };
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("invalid_context_path");
    // Lookup helper was never invoked — early-return before DB round-trip.
    expect(mockLookup).not.toHaveBeenCalled();
  });
});
